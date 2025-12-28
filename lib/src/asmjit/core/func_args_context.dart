import 'arch.dart';
import 'error.dart';
import 'environment.dart';
import 'func.dart';
import 'globals.dart';
import 'operand.dart' show RegGroup;
import 'reg_type.dart';
import 'reg_utils.dart';
import 'raconstraints.dart';
import 'support.dart';
import 'type.dart';

const int _kVarIdNone = 0xFF;
const int _kMaxVarCount = kMaxFuncArgs * kMaxValuePack + 1;

/// Determines a suitable register group for a mem→mem move.
OperandSignature getSuitableRegForMemToMemMove(
    Arch arch, TypeId dstType, TypeId srcType) {
  final dstSize = dstType.sizeInBytes;
  final srcSize = srcType.sizeInBytes;
  final maxSize = dstSize > srcSize ? dstSize : srcSize;
  final regSize = Environment.regSizeOfArch(arch);
  final bothInt = dstType.isInt && srcType.isInt;

  if (maxSize <= regSize || bothInt) {
    return const OperandSignature(RegGroup.gp);
  }

  if (maxSize <= 16) {
    return const OperandSignature(RegGroup.vec);
  }

  if (maxSize <= 32) {
    return const OperandSignature(RegGroup.vec);
  }

  if (maxSize <= 64) {
    return const OperandSignature(RegGroup.vec);
  }

  return OperandSignature.invalid;
}

// =============================================================================
// FuncArgsContext helpers
// =============================================================================

class FuncArgsContextVar {
  FuncValue cur = FuncValue();
  FuncValue out = FuncValue();

  void init(FuncValue curValue, FuncValue outValue) {
    cur = FuncValue.from(curValue);
    out = FuncValue.from(outValue);
  }

  void reset() {
    cur.reset();
    out.reset();
  }

  bool get isDone => cur.isDone;

  void markDone() {
    cur.addFlags(FuncValueBits.kFlagIsDone);
  }
}

class FuncArgsContextWorkData {
  int archRegs = 0;
  int workRegs = 0;
  int usedRegs = 0;
  int assignedRegs = 0;
  int dstRegs = 0;
  int dstShuf = 0;
  int numSwaps = 0;
  int numStackArgs = 0;
  bool needsScratch = false;
  final List<int> physToVarId = List.filled(32, _kVarIdNone);

  void reset() {
    archRegs = 0;
    workRegs = 0;
    usedRegs = 0;
    assignedRegs = 0;
    dstRegs = 0;
    dstShuf = 0;
    numSwaps = 0;
    numStackArgs = 0;
    needsScratch = false;
    physToVarId.fillRange(0, physToVarId.length, _kVarIdNone);
  }

  bool isAssigned(int regId) => bitTest(assignedRegs, regId);

  void assign(int varId, int regId) {
    assert(!isAssigned(regId));
    assert(physToVarId[regId] == _kVarIdNone);
    physToVarId[regId] = varId;
    assignedRegs ^= bitMask(regId);
  }

  void reassign(int varId, int newRegId, int oldRegId) {
    assert(isAssigned(oldRegId));
    assert(!isAssigned(newRegId));
    assert(physToVarId[oldRegId] == varId);
    assert(physToVarId[newRegId] == _kVarIdNone);
    physToVarId[oldRegId] = _kVarIdNone;
    physToVarId[newRegId] = varId;
    assignedRegs ^= bitMask(newRegId) ^ bitMask(oldRegId);
  }

  void swap(int aVarId, int aRegId, int bVarId, int bRegId) {
    assert(isAssigned(aRegId));
    assert(isAssigned(bRegId));
    assert(physToVarId[aRegId] == aVarId);
    assert(physToVarId[bRegId] == bVarId);
    physToVarId[aRegId] = bVarId;
    physToVarId[bRegId] = aVarId;
  }

  void unassign(int varId, int regId) {
    assert(isAssigned(regId));
    assert(physToVarId[regId] == varId);
    physToVarId[regId] = _kVarIdNone;
    assignedRegs ^= bitMask(regId);
  }

  int availableRegs() => workRegs & ~assignedRegs;
}

/// Function argument shuffling helper.
class FuncArgsContext {
  ArchTraits? _archTraits;
  Arch _arch = Arch.unknown;
  bool _hasStackSrc = false;
  bool _hasPreservedFP = false;
  int _stackDstMask = 0;
  int _regSwapsMask = 0;
  int _saVarId = _kVarIdNone;
  int _varCount = 0;
  final List<FuncArgsContextWorkData> _workData =
      List.generate(Globals.numVirtGroups, (_) => FuncArgsContextWorkData());
  final List<FuncArgsContextVar> _vars =
      List.generate(_kMaxVarCount, (_) => FuncArgsContextVar());

  FuncArgsContext() {
    for (final wd in _workData) {
      wd.reset();
    }
  }

  ArchTraits get archTraits => _archTraits!;

  Arch get arch => _arch;

  bool get hasPreservedFP => _hasPreservedFP;

  int indexOf(FuncArgsContextVar value) => _vars.indexOf(value);

  FuncArgsContextVar varAt(int varId) => _vars[varId];

  AsmJitError initWorkData(
      FuncFrame frame, FuncArgsAssignment args, RAConstraints constraints) {
    final func = args.funcDetail;
    if (func == null) return AsmJitError.invalidState;

    _archTraits = ArchTraits.forArch(frame.arch);
    _arch = frame.arch;
    _hasStackSrc = false;
    _hasPreservedFP = frame.hasPreservedFP;
    _stackDstMask = 0;
    _regSwapsMask = 0;
    _saVarId = _kVarIdNone;
    _varCount = 0;

    for (final wd in _workData) {
      wd.reset();
    }

    for (final group in enumerateRegGroups()) {
      _workData[group.index].archRegs = constraints.availableRegs(group);
    }

    final fpId = _archTraits!.fpRegId;
    if (frame.hasPreservedFP && fpId >= 0) {
      _workData[RegGroup.gp.index].archRegs &= ~bitMask(fpId);
    }

    int reassignmentFlagMask = 0;
    int varId = 0;
    final argCount = func.argCount;

    for (var argIndex = 0; argIndex < argCount; argIndex++) {
      for (var valueIndex = 0;
          valueIndex < FuncValuePack.kMaxValuePack;
          valueIndex++) {
        final dst = args.arg(argIndex, valueIndex);
        if (!dst.isAssigned) continue;

        final src = func.args[argIndex][valueIndex];
        if (!src.isAssigned) return AsmJitError.invalidState;

        final currentVar = _vars[varId];
        currentVar.init(src, dst);

        var dstGroup = RegGroup.extra;
        var dstId = Reg.kIdBad;
        FuncArgsContextWorkData? dstWd;

        if (src.isIndirect) {
          return AsmJitError.invalidAssignment;
        }

        if (dst.isReg) {
          final dstType = dst.fullRegType;
          final dstGroupCandidate = RegUtils.groupOf(dstType);
          if (!_archTraits!.hasRegType(dstType)) {
            return AsmJitError.invalidRegType;
          }

          if (!dst.isInitialized) {
            dst.setTypeId(RegUtils.typeIdOf(dst.fullRegType));
          }

          dstGroup = dstGroupCandidate;
          if (dstGroup.index >= RegGroup.values.length) {
            return AsmJitError.invalidRegGroup;
          }

          dstWd = _workData[dstGroup.index];
          dstId = dst.regId;

          if (dstId >= 32 || !bitTest(dstWd.archRegs, dstId)) {
            return AsmJitError.invalidPhysId;
          }
          if (bitTest(dstWd.dstRegs, dstId)) {
            return AsmJitError.overlappedRegs;
          }

          dstWd.dstRegs |= bitMask(dstId);
          dstWd.dstShuf |= bitMask(dstId);
          dstWd.usedRegs |= bitMask(dstId);
        } else {
          if (!dst.isInitialized) {
            dst.setTypeId(src.typeId);
          }
          final signature =
              getSuitableRegForMemToMemMove(_arch, dst.typeId, src.typeId);
          if (!signature.isValid) {
            return AsmJitError.invalidState;
          }
          _stackDstMask |= bitMask(signature.regGroup().index);
        }

        if (src.isReg) {
          final srcId = src.regId;
          final srcGroup = RegUtils.groupOf(src.fullRegType);

          if (dstGroup == srcGroup) {
            assert(dstWd != null);
            dstWd!.assign(varId, srcId);
            if (dstId != srcId) {
              reassignmentFlagMask |= 1 << dstGroup.index;
            }
            if (dstId == srcId) {
              if (dstGroup != RegGroup.gp) {
                currentVar.markDone();
              } else {
                final dstType = dst.typeId;
                final srcType = src.typeId;
                final dstSize = dstType.sizeInBytes;
                final srcSize = srcType.sizeInBytes;
                if (dstType == TypeId.void_ ||
                    srcType == TypeId.void_ ||
                    dstSize <= srcSize) {
                  currentVar.markDone();
                }
              }
            }
          } else {
            if (srcGroup.index >= RegGroup.values.length) {
              return AsmJitError.invalidState;
            }
            final srcData = _workData[srcGroup.index];
            srcData.assign(varId, srcId);
            reassignmentFlagMask |= 1 << dstGroup.index;
          }
        } else {
          dstWd?.numStackArgs++;
          _hasStackSrc = true;
        }

        varId++;
      }
    }

    for (final group in enumerateRegGroups()) {
      final wd = _workData[group.index];
      final dirty = frame.dirtyRegs(group);
      final preserved = frame.preservedRegs(group);
      wd.workRegs =
          (wd.archRegs & (dirty | ~preserved)) | wd.dstRegs | wd.assignedRegs;
      wd.needsScratch = ((reassignmentFlagMask >> group.index) & 1) != 0;
    }

    var saRegRequired = _hasStackSrc && frame.hasDA && !frame.hasPreservedFP;
    final gpRegs = _workData[RegGroup.gp.index];
    var saCurRegId = frame.saRegId; // Now it's a getter
    final saOutRegId = args.saRegId; // Now it's a getter

    if (saCurRegId != Reg.kIdBad) {
      if (gpRegs.isAssigned(saCurRegId)) {
        return AsmJitError.overlappedRegs;
      }
    }

    if (saOutRegId != Reg.kIdBad) {
      if (bitTest(gpRegs.dstRegs, saOutRegId)) {
        return AsmJitError.overlappedRegs;
      }
      saRegRequired = true;
    }

    if (saRegRequired) {
      final ptrTypeId = _arch.is32Bit ? TypeId.uint32 : TypeId.uint64;
      final ptrRegType = _arch.is32Bit ? RegType.gp32 : RegType.gp64;
      final saVar = _vars[varId];
      saVar.reset();

      if (saCurRegId == Reg.kIdBad) {
        if (saOutRegId != Reg.kIdBad && !gpRegs.isAssigned(saOutRegId)) {
          saCurRegId = saOutRegId;
        } else {
          var availableRegs = gpRegs.availableRegs();
          if (availableRegs == 0) {
            availableRegs = gpRegs.archRegs & ~gpRegs.workRegs;
          }
          if (availableRegs == 0) {
            return AsmJitError.invalidState;
          }
          saCurRegId = ctz(availableRegs);
        }
      }

      saVar.cur.initReg(ptrRegType, saCurRegId, ptrTypeId);
      gpRegs.assign(varId, saCurRegId);
      gpRegs.workRegs |= bitMask(saCurRegId);

      if (saOutRegId != Reg.kIdBad) {
        saVar.out.initReg(ptrRegType, saOutRegId, ptrTypeId);
        gpRegs.dstRegs |= bitMask(saOutRegId);
        gpRegs.workRegs |= bitMask(saOutRegId);
      } else {
        saVar.markDone();
      }

      _saVarId = varId;
      varId++;
    }

    _varCount = varId;

    for (var entry = 0; entry < _varCount; entry++) {
      final variable = _vars[entry];
      if (!variable.cur.isReg || !variable.out.isReg) continue;

      final srcId = variable.cur.regId;
      final dstId = variable.out.regId;
      final group = RegUtils.groupOf(variable.cur.fullRegType);
      if (group != RegUtils.groupOf(variable.out.fullRegType)) continue;

      final wd = _workData[group.index];
      if (wd.isAssigned(dstId)) {
        final otherVarId = wd.physToVarId[dstId];
        if (otherVarId == _kVarIdNone) continue;
        final other = _vars[otherVarId];
        if (RegUtils.groupOf(other.out.fullRegType) == group &&
            other.out.regId == srcId) {
          wd.numSwaps++;
          _regSwapsMask |= bitMask(group.index);
        }
      }
    }

    return AsmJitError.ok;
  }

  AsmJitError markDstRegsDirty(FuncFrame frame) {
    for (final group in enumerateRegGroups()) {
      final wd = _workData[group.index];
      final regs = wd.usedRegs | wd.dstShuf;
      wd.workRegs |= regs;
      frame.addDirtyRegs(group, regs);
    }
    return AsmJitError.ok;
  }

  AsmJitError markScratchRegs(FuncFrame frame) {
    var groupMask = _stackDstMask;
    groupMask |= _regSwapsMask & ~bitMask(RegGroup.gp.index);

    if (groupMask == 0) return AsmJitError.ok;

    for (final group in enumerateRegGroups()) {
      if (!bitTest(groupMask, group.index)) continue;
      final wd = _workData[group.index];
      if (!wd.needsScratch) continue;

      var regs = wd.workRegs & ~(wd.usedRegs | wd.dstShuf);
      if (regs == 0) {
        regs = wd.workRegs & ~wd.usedRegs;
      }
      if (regs == 0) {
        regs = wd.archRegs & ~wd.workRegs;
      }
      if (regs == 0) continue;

      final regMask = blsi(regs);
      wd.workRegs |= regMask;
      frame.addDirtyRegs(group, regMask);
    }

    return AsmJitError.ok;
  }

  AsmJitError markStackArgsReg(FuncFrame frame) {
    if (_saVarId != _kVarIdNone) {
      final saVar = _vars[_saVarId];
      frame.setSaRegId(saVar.cur.regId);
    } else if (frame.hasPreservedFP) {
      final fpId = _archTraits?.fpRegId ?? -1;
      if (fpId >= 0) {
        frame.setSaRegId(fpId);
      }
    }
    return AsmJitError.ok;
  }

  int get stackDstMask => _stackDstMask;

  int get regSwapsMask => _regSwapsMask;

  bool get hasStackSrc => _hasStackSrc;

  int get saVarId => _saVarId;

  int get varCount => _varCount;

  List<FuncArgsContextWorkData> get workData => _workData;

  List<FuncArgsContextVar> get vars => _vars;
}

/// Extension providing the update helper for [FuncArgsAssignment].
extension FuncArgsAssignmentExt on FuncArgsAssignment {
  AsmJitError updateFuncFrame(FuncFrame frame) {
    final func = funcDetail;
    if (func == null) {
      return AsmJitError.invalidState;
    }

    final constraints = RAConstraints();
    var err = constraints.init(frame.arch);
    if (err != AsmJitError.ok) {
      return err;
    }

    final ctx = FuncArgsContext();
    err = ctx.initWorkData(frame, this, constraints);
    if (err != AsmJitError.ok) {
      return err;
    }

    err = ctx.markDstRegsDirty(frame);
    if (err != AsmJitError.ok) {
      return err;
    }

    err = ctx.markScratchRegs(frame);
    if (err != AsmJitError.ok) {
      return err;
    }

    return ctx.markStackArgsReg(frame);
  }
}
