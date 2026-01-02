/// AsmJit Emit Helpers
///
/// Provides shared abstractions for argument shuffling.

import 'arch.dart';
import 'emitter.dart';
import 'environment.dart';
import 'error.dart';
import 'func.dart';
import 'func_args_context.dart';
import 'raconstraints.dart';
import 'reg_utils.dart';
import 'support.dart';
import 'type.dart';
import 'operand.dart';
import 'reg_type.dart';

const int _kVarIdNone = 0xFF;

/// Determines a suitable register group for a mem→mem move.
OperandSignature getSuitableRegForMemToMemMove(
    Arch arch, TypeId dstType, TypeId srcType) {
  final dstSize = dstType.sizeInBytes;
  final srcSize = srcType.sizeInBytes;
  final maxSize = dstSize > srcSize ? dstSize : srcSize;
  final regSize = Environment.regSizeOfArch(arch);
  final bothInt = dstType.isInt && srcType.isInt;

  if (maxSize <= regSize || bothInt) {
    return const OperandSignature(OperandSignature.kGroupGp);
  }

  if (maxSize <= 16) {
    return const OperandSignature(OperandSignature.kGroupVec);
  }

  if (maxSize <= 32) {
    return const OperandSignature(OperandSignature.kGroupVec);
  }

  if (maxSize <= 64) {
    return const OperandSignature(OperandSignature.kGroupVec);
  }

  return OperandSignature.invalid;
}

/// Lightweight operand representation used by emit helpers.
abstract class EmitOperand {
  bool get isReg;
  bool get isMem;
}

/// Register operand passed to emit helpers.
class RegOperand extends EmitOperand {
  RegType regType;
  int regId;

  RegOperand(this.regType, this.regId);

  RegOperand.from(RegOperand other)
      : regType = other.regType,
        regId = other.regId;

  @override
  bool get isReg => true;

  @override
  bool get isMem => false;

  void setRegId(int id) {
    regId = id;
  }

  @override
  String toString() => 'RegOperand(type: $regType, id: $regId)';
}

/// Memory operand used by emit helpers that wrap stack accesses.
class MemOperand extends BaseMem implements EmitOperand {
  RegOperand? baseReg;
  RegOperand? indexReg;
  int scale;
  int displacement;
  int memSize;

  MemOperand({
    this.baseReg,
    this.indexReg,
    this.scale = 1,
    this.displacement = 0,
    this.memSize = 0,
  });

  MemOperand cloneAdjusted(int offset) => MemOperand(
        baseReg: baseReg,
        indexReg: indexReg,
        scale: scale,
        displacement: displacement + offset,
        memSize: memSize,
      );

  void setBaseId(int id) => baseReg?.setRegId(id);

  void setSize(int size) {
    memSize = size;
  }

  @override
  bool get isReg => false;

  @override
  bool get isMem => true;

  @override
  int get size => memSize;

  @override
  bool get hasBase => baseReg != null;

  @override
  bool get hasIndex => indexReg != null;

  @override
  BaseReg? get base => null;

  @override
  BaseReg? get index => null;

  @override
  String toString() =>
      'MemOperand(base=${baseReg?.regId}, disp=$displacement, size=$memSize)';
}

class _SwapOutcome {
  final AsmJitError error;
  final int flags;
  final bool swapped;
  final int? scratchRegId;

  const _SwapOutcome(this.error, this.flags,
      {this.swapped = false, this.scratchRegId});
}

/// Base emit helper that implements argument shuffling independent of the emitter.
abstract class BaseEmitHelper {
  final BaseEmitter emitter;

  BaseEmitHelper(this.emitter);

  RegType _gpRegTypeForArch(Arch arch) =>
      Environment.regSizeOfArch(arch) >= 8 ? RegType.gp64 : RegType.gp32;

  RegType _regTypeForGroup(int group, Arch arch) {
    if (group == OperandSignature.kGroupGp) {
      return _gpRegTypeForArch(arch);
    } else if (group == OperandSignature.kGroupVec) {
      return RegType.vec128;
    } else if (group == OperandSignature.kGroupMask) {
      return RegType.mask;
    } else {
      return _gpRegTypeForArch(arch);
    }
  }

  AsmJitError emitArgsAssignment(FuncFrame frame, FuncArgsAssignment args) {
    final arch = frame.arch;
    final archTraits = ArchTraits.forArch(arch);

    final constraints = RAConstraints();
    var err = constraints.init(arch);
    if (err != AsmJitError.ok) return err;

    final ctx = FuncArgsContext();
    err = ctx.initWorkData(frame, args, constraints);
    if (err != AsmJitError.ok) return err;

    final workData = ctx.workData;
    final varCount = ctx.varCount;
    final saVarId = ctx.saVarId;

    final spRegType = _gpRegTypeForArch(arch);
    final sp = RegOperand(spRegType, archTraits.spRegId);
    final sa = RegOperand(spRegType, sp.regId);

    if (frame.hasDynamicAlignment()) {
      if (frame.hasPreservedFP && archTraits.fpRegId >= 0) {
        sa.setRegId(archTraits.fpRegId);
      } else {
        final saId =
            saVarId < varCount ? ctx.vars[saVarId].cur.regId : frame.saRegId;
        if (saId != Reg.kIdBad) {
          sa.setRegId(saId);
        }
      }
    }

    if (ctx.stackDstMask != 0) {
      final saId = sa.regId;
      final saOffset = saId != Reg.kIdBad ? frame.saOffset(saId) : 0;
      final baseArgPtr = MemOperand(baseReg: sa, displacement: saOffset);
      final baseStackPtr = MemOperand(baseReg: sp);

      for (var varId = 0; varId < varCount; varId++) {
        final variable = ctx.vars[varId];
        if (!variable.out.isStack) continue;

        final cur = variable.cur;
        final out = variable.out;
        final dstStackPtr = baseStackPtr.cloneAdjusted(out.stackOffset);
        final srcStackPtr = baseArgPtr.cloneAdjusted(cur.stackOffset);

        late final RegOperand tempReg;

        if (cur.isIndirect) {
          if (cur.isStack) {
            return AsmJitError.invalidAssignment;
          }
          srcStackPtr.setBaseId(cur.regId);
        }

        if (cur.isReg && !cur.isIndirect) {
          final group = RegUtils.groupOf(cur.fullRegType);
          final wd = workData[group.index];
          final regId = cur.regId;
          tempReg = RegOperand(cur.fullRegType, regId);
          wd.unassign(varId, regId);
        } else {
          final signature =
              getSuitableRegForMemToMemMove(arch, out.typeId, cur.typeId);
          if (!signature.isValid) {
            return AsmJitError.invalidState;
          }

          final targetGroup = signature.regGroup;
          final wd = workData[targetGroup];
          var available = wd.availableRegs();
          if (available == 0) {
            return AsmJitError.invalidState;
          }

          final selected = ctz(available);
          final regType = _regTypeForGroup(targetGroup, arch);
          tempReg = RegOperand(regType, selected);

          final movErr =
              emitArgMove(tempReg, out.typeId, srcStackPtr, cur.typeId);
          if (movErr != AsmJitError.ok) return movErr;
        }

        if (cur.isIndirect && cur.isReg) {
          workData[RegGroup.gp.index].unassign(varId, cur.regId);
        }

        final moveErr = emitRegMove(dstStackPtr, tempReg, cur.typeId);
        if (moveErr != AsmJitError.ok) return moveErr;

        variable.markDone();
      }
    }

    const kWorkNone = 0;
    const kWorkDidSome = 1;
    const kWorkPending = 2;
    const kWorkPostponed = 4;

    var workFlags = kWorkNone;

    for (;;) {
      for (var varId = 0; varId < varCount; varId++) {
        final variable = ctx.vars[varId];
        if (variable.isDone || !variable.cur.isReg) continue;

        final out = variable.out;
        var currentOutId = out.regId;
        final group = RegUtils.groupOf(variable.cur.fullRegType);
        final wd = workData[group.index];

        var loopActive = true;
        while (loopActive) {
          final curId = variable.cur.regId;
          if (!wd.isAssigned(currentOutId) || curId == currentOutId) {
            final moveErr = _emitMoveToTarget(
              variable,
              wd,
              varId,
              currentOutId,
              curId,
            );
            if (moveErr != AsmJitError.ok) return moveErr;
            workFlags |= kWorkDidSome | kWorkPending;
            loopActive = false;
            continue;
          }

          final altId = wd.physToVarId[currentOutId];
          if (altId == _kVarIdNone) {
            workFlags |= kWorkPending;
            loopActive = false;
            continue;
          }

          final altVar = ctx.vars[altId];
          if (!altVar.out.isInitialized ||
              (altVar.out.isReg && altVar.out.regId == curId)) {
            final swapOutcome = _trySwapRegs(
              archTraits,
              wd,
              group,
              variable,
              altVar,
              varId,
              curId,
              currentOutId,
              altId,
            );

            workFlags |= swapOutcome.flags;
            if (swapOutcome.error != AsmJitError.ok) {
              return swapOutcome.error;
            }

            if (swapOutcome.swapped) {
              loopActive = false;
              continue;
            }

            if (swapOutcome.scratchRegId != null) {
              currentOutId = swapOutcome.scratchRegId!;
              continue;
            }

            loopActive = false;
            continue;
          }

          workFlags |= kWorkPending;
          loopActive = false;
        }
      }

      if ((workFlags & kWorkPending) == 0) {
        break;
      }

      if ((workFlags & (kWorkDidSome | kWorkPostponed)) == kWorkPostponed) {
        return AsmJitError.invalidState;
      }

      workFlags = (workFlags & kWorkDidSome) != 0 ? kWorkNone : kWorkPostponed;
    }

    if (ctx.hasStackSrc) {
      var iterCount = 1;
      if (frame.hasDynamicAlignment() && !frame.hasPreservedFP) {
        final saId =
            saVarId < varCount ? ctx.vars[saVarId].cur.regId : frame.saRegId;
        if (saId != Reg.kIdBad) {
          sa.setRegId(saId);
        }
      }

      final saIdAlt = sa.regId;
      final saDisp = saIdAlt != Reg.kIdBad ? frame.saOffset(saIdAlt) : 0;
      final baseArgPtr = MemOperand(baseReg: sa, displacement: saDisp);

      for (var iter = 0; iter < iterCount; iter++) {
        for (var varId = 0; varId < varCount; varId++) {
          final variable = ctx.vars[varId];
          if (variable.isDone) continue;
          if (!variable.cur.isStack) continue;

          final out = variable.out;
          final group = RegUtils.groupOf(out.fullRegType);
          final wd = workData[group.index];
          final outId = out.regId;

          if (outId == sa.regId && group == RegGroup.gp) {
            if (iterCount == 1) {
              iterCount++;
              continue;
            }
            wd.unassign(wd.physToVarId[outId], outId);
          }

          final dstReg = RegOperand(out.fullRegType, outId);
          final srcMem = baseArgPtr.cloneAdjusted(variable.cur.stackOffset);

          final loadErr =
              emitArgMove(dstReg, out.typeId, srcMem, variable.cur.typeId);
          if (loadErr != AsmJitError.ok) return loadErr;

          wd.assign(varId, outId);
          variable.cur.initReg(
            out.fullRegType,
            outId,
            variable.cur.typeId,
            FuncValueBits.kFlagIsDone,
          );
        }
      }
    }

    return AsmJitError.ok;
  }

  AsmJitError _emitMoveToTarget(
    FuncArgsContextVar variable,
    FuncArgsContextWorkData wd,
    int varId,
    int targetId,
    int curId,
  ) {
    final dstReg = RegOperand(variable.out.fullRegType, targetId);
    final srcReg = RegOperand(variable.cur.fullRegType, curId);
    final err =
        emitArgMove(dstReg, variable.out.typeId, srcReg, variable.cur.typeId);
    if (err != AsmJitError.ok) return err;

    if (curId != targetId) {
      wd.reassign(varId, targetId, curId);
    }

    variable.cur
        .initReg(variable.out.fullRegType, targetId, variable.out.typeId);
    if (targetId == variable.out.regId) {
      variable.markDone();
    }
    return AsmJitError.ok;
  }

  _SwapOutcome _trySwapRegs(
    ArchTraits archTraits,
    FuncArgsContextWorkData wd,
    RegGroup group,
    FuncArgsContextVar variable,
    FuncArgsContextVar altVar,
    int varId,
    int curId,
    int outId,
    int altVarId,
  ) {
    const kWorkDidSome = 1;
    const kWorkPending = 2;

    if (archTraits.hasRegSwap(group)) {
      final dstReg = RegOperand(variable.out.fullRegType, outId);
      final srcReg = RegOperand(variable.cur.fullRegType, curId);
      final err = emitRegSwap(dstReg, srcReg);
      if (err != AsmJitError.ok) {
        return _SwapOutcome(err, kWorkPending);
      }

      wd.swap(varId, curId, altVarId, outId);
      variable.cur.setRegId(outId);
      variable.markDone();
      altVar.cur.setRegId(curId);
      if (altVar.out.isInitialized) {
        altVar.markDone();
      }

      return _SwapOutcome(AsmJitError.ok, kWorkDidSome, swapped: true);
    }

    var available = wd.availableRegs();
    if (available != 0) {
      var mask = available & ~wd.dstRegs;
      if (mask == 0) {
        mask = available;
      }

      if (mask != 0) {
        final scratchId = ctz(mask);
        return _SwapOutcome(AsmJitError.ok, kWorkPending,
            scratchRegId: scratchId);
      }
    }

    return _SwapOutcome(AsmJitError.ok, kWorkPending);
  }

  AsmJitError emitRegMove(EmitOperand dst, EmitOperand src, TypeId typeId);

  AsmJitError emitRegSwap(RegOperand a, RegOperand b);

  AsmJitError emitArgMove(
      RegOperand dst, TypeId dstTypeId, EmitOperand src, TypeId srcTypeId);
}
