/// AsmJit A64 Code Builder
///
/// Minimal builder that targets A64 assembler/serializer.

import '../core/builder.dart' as ir;
import '../core/code_holder.dart';
import '../core/environment.dart';
import '../core/labels.dart';
import '../core/operand.dart';
import '../runtime/jit_runtime.dart';
import 'a64.dart';
import 'a64_assembler.dart';
import 'a64_inst_db.g.dart';
import 'a64_serializer.dart';

/// A minimal A64 builder/compilador.
///
/// This builder does not yet implement register allocation. It uses
/// simple physical register pools for convenience and relies on the
/// caller to manage lifetimes.
class A64CodeBuilder extends ir.BaseBuilder {
  final CodeHolder code;
  final Environment env;

  int _userStackSize = 0;
  int _vregId = 0;

  A64CodeBuilder._(this.code, this.env);

  /// Creates a new A64 builder using the given environment.
  factory A64CodeBuilder.create({Environment? env}) {
    env ??= Environment.aarch64();
    final code = CodeHolder(env: env);
    return A64CodeBuilder._(code, env);
  }

  @override
  Label newLabel() => code.newLabel();

  /// Current code offset.
  int get offset => code.text.buffer.length;

  /// Configure stack size for prologue/epilogue.
  void setStackSize(int size) {
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'must be >= 0');
    }
    _userStackSize = (size + 15) & ~15;
  }

  /// Allocate a virtual GP register.
  A64Gp newGpReg({int sizeBits = 64}) {
    if (sizeBits != 64 && sizeBits != 32) {
      throw ArgumentError.value(sizeBits, 'sizeBits', 'must be 32 or 64');
    }
    final id = _vregId++;
    return _A64VirtGp(id, sizeBits);
  }

  /// Allocate a virtual vector register.
  A64Vec newVecReg({int sizeBits = 128}) {
    if (sizeBits != 128 &&
        sizeBits != 64 &&
        sizeBits != 32 &&
        sizeBits != 16 &&
        sizeBits != 8) {
      throw ArgumentError.value(sizeBits, 'sizeBits', 'unsupported size');
    }
    final id = _vregId++;
    return _A64VirtVec(id, sizeBits);
  }

  /// Returns the AAPCS64 argument register for [index].
  A64Gp getArgReg(int index) {
    if (index < 0 || index >= aapcs64ArgRegs.length) {
      throw RangeError.range(index, 0, aapcs64ArgRegs.length - 1, 'index');
    }
    return aapcs64ArgRegs[index];
  }

  /// Returns the AAPCS64 vector argument register for [index].
  A64Vec getVecArgReg(int index) {
    if (index < 0 || index >= aapcs64VecArgRegs.length) {
      throw RangeError.range(index, 0, aapcs64VecArgRegs.length - 1, 'index');
    }
    return aapcs64VecArgRegs[index];
  }

  void mov(A64Gp rd, A64Gp rn) => _inst(A64InstId.kMov, [rd, rn]);

  void add(A64Gp rd, A64Gp rn, Object rmOrImm) {
    _inst(A64InstId.kAdd, [rd, rn, rmOrImm]);
  }

  void sub(A64Gp rd, A64Gp rn, Object rmOrImm) {
    _inst(A64InstId.kSub, [rd, rn, rmOrImm]);
  }

  void mul(A64Gp rd, A64Gp rn, A64Gp rm) {
    // MUL is alias for MADD rd, rn, rm, xzr
    _inst(A64InstId.kMadd, [rd, rn, rm, xzr]);
  }

  void cmp(A64Gp rn, Object rmOrImm) {
    _inst(A64InstId.kCmp, [rn, rmOrImm]);
  }

  void and(A64Gp rd, A64Gp rn, A64Gp rm) {
    _inst(A64InstId.kAnd, [rd, rn, rm]);
  }

  void orr(A64Gp rd, A64Gp rn, A64Gp rm) {
    _inst(A64InstId.kOrr, [rd, rn, rm]);
  }

  void eor(A64Gp rd, A64Gp rn, A64Gp rm) {
    _inst(A64InstId.kEor, [rd, rn, rm]);
  }

  void lsl(A64Gp rd, A64Gp rn, int shift) {
    _inst(A64InstId.kLsl, [rd, rn, shift]);
  }

  void lsr(A64Gp rd, A64Gp rn, int shift) {
    _inst(A64InstId.kLsr, [rd, rn, shift]);
  }

  void b(Label label) => _inst(A64InstId.kB, [label]);

  void bl(Label label) => _inst(A64InstId.kBl, [label]);

  void br(A64Gp rn) => _inst(A64InstId.kBr, [rn]);

  void cbz(A64Gp rt, Label label) => _inst(A64InstId.kCbz, [rt, label]);

  void cbnz(A64Gp rt, Label label) => _inst(A64InstId.kCbnz, [rt, label]);

  void ret() => _inst(A64InstId.kRet, []);

  void ldr(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _inst(A64InstId.kLdr, [rt, rn, offset]);
  }

  void ldrb(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _inst(A64InstId.kLdrb, [rt, rn, offset]);
  }

  void str(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _inst(A64InstId.kStr, [rt, rn, offset]);
  }

  void strb(A64Gp rt, A64Gp rn, [int offset = 0]) {
    _inst(A64InstId.kStrb, [rt, rn, offset]);
  }

  void movz(A64Gp rd, int imm16, {int shift = 0}) {
    _inst(A64InstId.kMovz, [rd, imm16, shift]);
  }

  void movk(A64Gp rd, int imm16, {int shift = 0}) {
    _inst(A64InstId.kMovk, [rd, imm16, shift]);
  }

  void movImm32(A64Gp rd, int imm32) {
    final value = imm32 & 0xFFFFFFFF;
    movz(rd, value & 0xFFFF);
    final high = (value >> 16) & 0xFFFF;
    if (high != 0) {
      movk(rd, high, shift: 16);
    }
  }

  void ldrVec(A64Vec vt, A64Gp rn, [int offset = 0]) {
    _inst(A64InstId.kLdr, [vt, rn, offset]);
  }

  void strVec(A64Vec vt, A64Gp rn, [int offset = 0]) {
    _inst(A64InstId.kStr, [vt, rn, offset]);
  }

  void addVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kAdd, [rd, rn, rm]);
  }

  void subVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kSub, [rd, rn, rm]);
  }

  void mulVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kMul, [rd, rn, rm]);
  }

  void andVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kAnd, [rd, rn, rm]);
  }

  void eorVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kEor, [rd, rn, rm]);
  }

  void fadd(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFadd, [rd, rn, rm]);
  }

  void fsub(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFsub, [rd, rn, rm]);
  }

  void fmul(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFmul, [rd, rn, rm]);
  }

  void fdiv(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFdiv, [rd, rn, rm]);
  }

  void faddVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFadd, [rd, rn, rm]);
  }

  void fsubVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFsub, [rd, rn, rm]);
  }

  void fmulVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFmul, [rd, rn, rm]);
  }

  void fdivVec(A64Vec rd, A64Vec rn, A64Vec rm) {
    _inst(A64InstId.kFdiv, [rd, rn, rm]);
  }

  void nop() => _inst(A64InstId.kNop, []);

  void _inst(int instId, List<Object> operands) {
    final ops = <ir.Operand>[];
    for (final op in operands) {
      ops.add(_toOperand(op));
    }
    inst(instId, ops);
  }

  ir.Operand _toOperand(Object o) {
    if (o is A64Gp || o is A64Vec) return o as BaseReg;
    if (o is int) return ir.Imm(o);
    if (o is Label) return ir.LabelOp(o);
    throw ArgumentError('Unsupported operand type: ${o.runtimeType}');
  }

  /// Builds the code and returns executable function.
  JitFunction build(JitRuntime runtime,
      {bool useCache = false, String? cacheKey}) {
    final asm = A64Assembler(code);
    final alloc = _A64RegAlloc(_allocGpRegs, _allocVecRegs);
    alloc.allocate(nodes);
    final spillBase = _userStackSize;
    final frameSize = _align16(_userStackSize + alloc.spillAreaSize);
    if (frameSize > 0) {
      asm.emitPrologue(stackSize: frameSize);
    }

    final serializer = _A64FuncSerializer(asm, frameSize, alloc, spillBase);
    serialize(serializer);

    if (useCache) {
      return runtime.addCached(code, key: cacheKey);
    }
    return runtime.add(code);
  }

  /// Finalizes the code without executing it.
  FinalizedCode finalize() {
    final asm = A64Assembler(code);
    final alloc = _A64RegAlloc(_allocGpRegs, _allocVecRegs);
    alloc.allocate(nodes);
    final spillBase = _userStackSize;
    final frameSize = _align16(_userStackSize + alloc.spillAreaSize);
    if (frameSize > 0) {
      asm.emitPrologue(stackSize: frameSize);
    }
    final serializer = _A64FuncSerializer(asm, frameSize, alloc, spillBase);
    serialize(serializer);
    return asm.finalize();
  }

  /// Debug helper to inspect computed spill offsets (absolute from SP).
  List<int> debugSpillOffsets() {
    final alloc = _A64RegAlloc(_allocGpRegs, _allocVecRegs);
    alloc.allocate(nodes);
    final base = _userStackSize;
    return alloc.spillOffsets.map((o) => o + base).toList()..sort();
  }
}

class _A64FuncSerializer extends A64Serializer {
  final int frameSize;
  final _A64RegAlloc alloc;
  final int spillBase;

  _A64FuncSerializer(
      A64Assembler asm, this.frameSize, this.alloc, this.spillBase)
      : super(asm);

  @override
  void onInst(int instId, List<ir.Operand> operands, int options) {
    if (instId == A64InstId.kRet && frameSize > 0) {
      asm.emitEpilogue(stackSize: frameSize);
      return;
    }

    final scratch = _ScratchAllocator(_scratchGpRegs, _scratchVecRegs);
    _reservePhysicalOperands(operands, scratch);

    final preSpills = <_SpillAccess>[];
    final postSpills = <_SpillAccess>[];
    final rewritten = <ir.Operand>[];

    for (final op in operands) {
      if (op is ir.BaseReg) {
        final reg = op;
        final newReg = _rewriteReg(
          reg,
          scratch,
          preSpills,
          postSpills,
          writeBack: true,
        );
        rewritten.add(newReg);
      } else if (op is ir.BaseMem && op is A64Mem) {
        final mem = op as A64Mem;
        final base = _rewriteMemBase(mem.base, scratch, preSpills);
        final index = _rewriteMemIndex(mem.index, scratch, preSpills);
        final rebuilt = _rebuildMem(mem, base, index);
        rewritten.add(rebuilt as ir.Operand);
      } else {
        rewritten.add(op);
      }
    }

    for (final spill in preSpills) {
      _emitSpillLoad(spill, scratch);
    }

    super.onInst(instId, rewritten, options);

    for (final spill in postSpills) {
      _emitSpillStore(spill, scratch);
    }
  }

  void _reservePhysicalOperands(
      List<ir.Operand> operands, _ScratchAllocator scratch) {
    for (final op in operands) {
      if (op is ir.BaseReg) {
        final reg = op;
        if (reg is _A64VirtReg) {
          if (!reg.isSpilled) {
            scratch.reserve(_physFor(reg)!);
          }
        } else {
          scratch.reserve(reg);
        }
      } else if (op is ir.BaseMem && op is A64Mem) {
        final mem = op as A64Mem;
        if (mem.base is _A64VirtReg) {
          final reg = mem.base as _A64VirtReg;
          if (!reg.isSpilled) {
            scratch.reserve(_physFor(reg)!);
          }
        } else if (mem.base is BaseReg) {
          scratch.reserve(mem.base as BaseReg);
        }
        if (mem.index is _A64VirtReg) {
          final reg = mem.index as _A64VirtReg;
          if (!reg.isSpilled) {
            scratch.reserve(_physFor(reg)!);
          }
        } else if (mem.index is BaseReg) {
          scratch.reserve(mem.index as BaseReg);
        }
      }
    }
  }

  BaseReg _rewriteReg(
    BaseReg reg,
    _ScratchAllocator scratch,
    List<_SpillAccess> pre,
    List<_SpillAccess> post, {
    required bool writeBack,
  }) {
    if (reg is _A64VirtReg) {
      if (!reg.isSpilled) {
        return _physFor(reg)!;
      }
      final scratchReg = scratch.allocFor(reg);
      pre.add(_SpillAccess(reg, scratchReg, spillBase));
      if (writeBack) {
        post.add(_SpillAccess(reg, scratchReg, spillBase));
      }
      return scratchReg;
    }
    return reg;
  }

  A64Gp? _rewriteMemBase(
    A64Gp? reg,
    _ScratchAllocator scratch,
    List<_SpillAccess> pre,
  ) {
    if (reg == null) return null;
    if (reg is _A64VirtReg) {
      final vreg = reg as _A64VirtReg;
      if (!vreg.isSpilled) return _physFor(vreg) as A64Gp;
      final scratchReg = scratch.allocFor(vreg) as A64Gp;
      pre.add(_SpillAccess(vreg, scratchReg, spillBase));
      return scratchReg;
    }
    return reg;
  }

  A64Gp? _rewriteMemIndex(
    A64Gp? reg,
    _ScratchAllocator scratch,
    List<_SpillAccess> pre,
  ) {
    if (reg == null) return null;
    if (reg is _A64VirtReg) {
      final vreg = reg as _A64VirtReg;
      if (!vreg.isSpilled) return _physFor(vreg) as A64Gp;
      final scratchReg = scratch.allocFor(vreg) as A64Gp;
      pre.add(_SpillAccess(vreg, scratchReg, spillBase));
      return scratchReg;
    }
    return reg;
  }

  A64Mem _rebuildMem(A64Mem mem, A64Gp? base, A64Gp? index) {
    if (mem.addrMode == A64AddrMode.postIndex) {
      return A64Mem.postIndex(base!, mem.offset);
    }
    if (mem.addrMode == A64AddrMode.preIndex) {
      return A64Mem.preIndex(base!, mem.offset);
    }
    if (index != null) {
      return A64Mem.baseIndex(base!, index, shift: mem.shift);
    }
    if (mem.offset != 0) {
      return A64Mem.baseOffset(base!, mem.offset);
    }
    return A64Mem.base(base!);
  }

  BaseReg? _physFor(_A64VirtReg reg) {
    if (reg is _A64VirtGp) return reg.physGp;
    if (reg is _A64VirtVec) return reg.physVec;
    return null;
  }

  void _emitSpillLoad(_SpillAccess spill, _ScratchAllocator scratch) {
    if (_canUseScaledImm(spill.offset, spill.scale)) {
      if (spill.isVec) {
        asm.ldrVec(spill.reg as A64Vec, sp, spill.offset);
      } else {
        asm.ldr(spill.reg as A64Gp, sp, spill.offset);
      }
      return;
    }

    final addr = _materializeSpillAddr(spill.offset, scratch);
    if (spill.isVec) {
      asm.ldrVec(spill.reg as A64Vec, addr, 0);
    } else {
      asm.ldr(spill.reg as A64Gp, addr, 0);
    }
  }

  void _emitSpillStore(_SpillAccess spill, _ScratchAllocator scratch) {
    if (_canUseScaledImm(spill.offset, spill.scale)) {
      if (spill.isVec) {
        asm.strVec(spill.reg as A64Vec, sp, spill.offset);
      } else {
        asm.str(spill.reg as A64Gp, sp, spill.offset);
      }
      return;
    }

    final addr = _materializeSpillAddr(spill.offset, scratch);
    if (spill.isVec) {
      asm.strVec(spill.reg as A64Vec, addr, 0);
    } else {
      asm.str(spill.reg as A64Gp, addr, 0);
    }
  }

  A64Gp _materializeSpillAddr(int offset, _ScratchAllocator scratch) {
    final tmp = scratch.allocTempGp();
    if (_canUseAddImm(offset)) {
      asm.addImm(tmp, sp, offset);
      return tmp;
    }
    asm.movImm64(tmp, offset);
    asm.add(tmp, sp, tmp);
    return tmp;
  }
}

const List<A64Gp> _allocGpRegs = [
  x11,
  x12,
  x13,
  x14,
  x15,
  x19,
  x20,
  x21,
  x22,
  x23,
  x24,
  x25,
  x26,
  x27,
  x28,
];

const List<A64Vec> _allocVecRegs = [
  v8,
  v9,
  v10,
  v11,
  v12,
  v13,
  v14,
  v15,
  v16,
  v17,
  v18,
  v19,
  v20,
  v21,
  v22,
  v23,
  v24,
  v25,
  v26,
  v27,
  v28,
];

const List<A64Gp> _scratchGpRegs = [
  x0,
  x1,
  x2,
  x3,
  x4,
  x5,
  x6,
  x7,
  x8,
  x9,
  x10,
  x16,
  x17,
];
const List<A64Vec> _scratchVecRegs = [
  v30,
  v31,
  v29,
  v0,
  v1,
  v2,
  v3,
  v4,
  v5,
  v6,
  v7
];

int _align16(int value) => (value + 15) & ~15;

class _SpillAccess {
  final _A64VirtReg vreg;
  final BaseReg reg;
  final int base;

  _SpillAccess(this.vreg, this.reg, this.base);

  bool get isVec => reg.isVec;

  int get offset => vreg.spillOffset + base;

  int get scale => reg.size;
}

abstract class _A64VirtReg implements BaseReg {
  int get virtId;
  int get firstUse;
  set firstUse(int value);
  int get lastUse;
  set lastUse(int value);
  bool get isSpilled;
  set isSpilled(bool value);
  int get spillOffset;
  set spillOffset(int value);
}

class _A64VirtGp extends A64Gp implements _A64VirtReg {
  @override
  final int virtId;

  @override
  int firstUse = -1;

  @override
  int lastUse = -1;

  @override
  bool isSpilled = false;

  @override
  int spillOffset = 0;

  A64Gp? physGp;

  _A64VirtGp(this.virtId, int sizeBits) : super(virtId, sizeBits);

  @override
  bool get isPhysical => false;

  @override
  String toString() => 'v$virtId${is64Bit ? ".x" : ".w"}';
}

class _A64VirtVec extends A64Vec implements _A64VirtReg {
  @override
  final int virtId;

  @override
  int firstUse = -1;

  @override
  int lastUse = -1;

  @override
  bool isSpilled = false;

  @override
  int spillOffset = 0;

  A64Vec? physVec;

  _A64VirtVec(this.virtId, int sizeBits) : super(virtId, sizeBits);

  @override
  bool get isPhysical => false;

  @override
  String toString() => 'v$virtId.$sizeBits';
}

class _A64LiveInterval {
  final _A64VirtReg vreg;
  final int start;
  int end;

  _A64LiveInterval(this.vreg, this.start, this.end);
}

class _A64RegAlloc {
  final List<A64Gp> _gpRegs;
  final List<A64Vec> _vecRegs;
  final List<_A64LiveInterval> _intervals = [];

  int _spillSize = 0;

  _A64RegAlloc(this._gpRegs, this._vecRegs);

  int get spillAreaSize => _align16(_spillSize);

  List<int> get spillOffsets {
    final offsets = <int>{};
    for (final interval in _intervals) {
      if (interval.vreg.isSpilled) {
        offsets.add(interval.vreg.spillOffset);
      }
    }
    return offsets.toList();
  }

  void allocate(ir.NodeList nodes) {
    _intervals.clear();
    _spillSize = 0;
    _buildIntervals(nodes);
    _intervals.sort((a, b) => a.start.compareTo(b.start));

    final activeGp = <_A64LiveInterval>[];
    final activeVec = <_A64LiveInterval>[];

    for (final interval in _intervals) {
      _expireIntervals(activeGp, interval.start);
      _expireIntervals(activeVec, interval.start);

      if (interval.vreg.isGp) {
        _allocateGp(interval, activeGp);
      } else if (interval.vreg.isVec) {
        _allocateVec(interval, activeVec);
      }
    }
  }

  void _buildIntervals(ir.NodeList nodes) {
    int pos = 0;
    final seen = <_A64VirtReg>{};
    for (final node in nodes.nodes) {
      if (node is ir.InstNode) {
        for (final op in node.operands) {
          _scanOperand(op, pos, seen);
        }
        pos += 2;
      }
    }

    for (final vreg in seen) {
      if (vreg.firstUse >= 0) {
        _intervals.add(_A64LiveInterval(vreg, vreg.firstUse, vreg.lastUse));
      }
    }
  }

  void _scanOperand(ir.Operand op, int pos, Set<_A64VirtReg> seen) {
    if (op is ir.BaseReg && op is _A64VirtReg) {
      final vreg = op;
      seen.add(vreg);
      _recordUse(vreg, pos);
    } else if (op is ir.BaseMem && op is A64Mem) {
      final mem = op as A64Mem;
      if (mem.base is _A64VirtReg) {
        final vreg = mem.base as _A64VirtReg;
        seen.add(vreg);
        _recordUse(vreg, pos);
      }
      if (mem.index is _A64VirtReg) {
        final vreg = mem.index as _A64VirtReg;
        seen.add(vreg);
        _recordUse(vreg, pos);
      }
    }
  }

  void _recordUse(_A64VirtReg vreg, int pos) {
    if (vreg.firstUse < 0) {
      vreg.firstUse = pos;
    }
    vreg.lastUse = pos;
  }

  void _expireIntervals(List<_A64LiveInterval> active, int pos) {
    active.removeWhere((interval) => interval.end < pos);
  }

  void _allocateGp(_A64LiveInterval interval, List<_A64LiveInterval> active) {
    final vreg = interval.vreg as _A64VirtGp;
    final reg = _firstFreeGp(active);
    if (reg != null) {
      vreg.physGp = _coerceGpSize(reg, vreg.sizeBits);
      active.add(interval);
      return;
    }
    _spillGp(interval, active);
  }

  void _allocateVec(_A64LiveInterval interval, List<_A64LiveInterval> active) {
    final vreg = interval.vreg as _A64VirtVec;
    final reg = _firstFreeVec(active);
    if (reg != null) {
      vreg.physVec = _coerceVecSize(reg, vreg.sizeBits);
      active.add(interval);
      return;
    }
    _spillVec(interval, active);
  }

  A64Gp? _firstFreeGp(List<_A64LiveInterval> active) {
    for (final reg in _gpRegs) {
      final inUse = active.any((it) =>
          it.vreg is _A64VirtGp &&
          (it.vreg as _A64VirtGp).physGp?.id == reg.id);
      if (!inUse) return reg;
    }
    return null;
  }

  A64Vec? _firstFreeVec(List<_A64LiveInterval> active) {
    for (final reg in _vecRegs) {
      final inUse = active.any((it) =>
          it.vreg is _A64VirtVec &&
          (it.vreg as _A64VirtVec).physVec?.id == reg.id);
      if (!inUse) return reg;
    }
    return null;
  }

  void _spillGp(_A64LiveInterval interval, List<_A64LiveInterval> active) {
    _A64LiveInterval? longest;
    for (final it in active) {
      if (it.vreg is _A64VirtGp) {
        if (longest == null || it.end > longest.end) {
          longest = it;
        }
      }
    }

    if (longest != null && longest.end > interval.end) {
      final victim = longest.vreg as _A64VirtGp;
      victim.isSpilled = true;
      victim.spillOffset = _allocSpillSlot(8);
      final reg = victim.physGp!;
      victim.physGp = null;

      final vreg = interval.vreg as _A64VirtGp;
      vreg.physGp = _coerceGpSize(reg, vreg.sizeBits);
      active.remove(longest);
      active.add(interval);
    } else {
      final vreg = interval.vreg as _A64VirtGp;
      vreg.isSpilled = true;
      vreg.spillOffset = _allocSpillSlot(8);
    }
  }

  void _spillVec(_A64LiveInterval interval, List<_A64LiveInterval> active) {
    _A64LiveInterval? longest;
    for (final it in active) {
      if (it.vreg is _A64VirtVec) {
        if (longest == null || it.end > longest.end) {
          longest = it;
        }
      }
    }

    if (longest != null && longest.end > interval.end) {
      final victim = longest.vreg as _A64VirtVec;
      victim.isSpilled = true;
      victim.spillOffset = _allocSpillSlot(16);
      final reg = victim.physVec!;
      victim.physVec = null;

      final vreg = interval.vreg as _A64VirtVec;
      vreg.physVec = _coerceVecSize(reg, vreg.sizeBits);
      active.remove(longest);
      active.add(interval);
    } else {
      final vreg = interval.vreg as _A64VirtVec;
      vreg.isSpilled = true;
      vreg.spillOffset = _allocSpillSlot(16);
    }
  }

  int _allocSpillSlot(int slotSize) {
    final align = slotSize;
    final offset = (_spillSize + (align - 1)) & ~(align - 1);
    _spillSize = offset + slotSize;
    return offset;
  }
}

class _ScratchAllocator {
  final List<A64Gp> _gp;
  final List<A64Vec> _vec;
  final Map<_A64VirtReg, BaseReg> _assigned = {};
  final Set<int> _usedGpIds = {};
  final Set<int> _usedVecIds = {};

  _ScratchAllocator(this._gp, this._vec);

  void reserve(BaseReg reg) {
    if (reg is A64Gp) {
      _usedGpIds.add(reg.id);
    } else if (reg is A64Vec) {
      _usedVecIds.add(reg.id);
    }
  }

  BaseReg allocFor(_A64VirtReg vreg) {
    if (_assigned.containsKey(vreg)) {
      return _assigned[vreg]!;
    }
    if (vreg.isVec) {
      final reg = _allocVec();
      _assigned[vreg] = reg;
      return reg;
    }
    final reg = _allocGp();
    _assigned[vreg] = reg;
    return reg;
  }

  A64Gp _allocGp() {
    for (final reg in _gp) {
      if (!_usedGpIds.contains(reg.id)) {
        _usedGpIds.add(reg.id);
        return reg;
      }
    }
    throw StateError('A64 scratch GP registers exhausted');
  }

  A64Vec _allocVec() {
    for (final reg in _vec) {
      if (!_usedVecIds.contains(reg.id)) {
        _usedVecIds.add(reg.id);
        return reg;
      }
    }
    throw StateError('A64 scratch vector registers exhausted');
  }

  A64Gp allocTempGp() => _allocGp();
}

A64Gp _coerceGpSize(A64Gp base, int sizeBits) {
  return sizeBits == 32 ? base.w : base.x;
}

A64Vec _coerceVecSize(A64Vec base, int sizeBits) {
  switch (sizeBits) {
    case 128:
      return base;
    case 64:
      return base.d;
    case 32:
      return base.s;
    case 16:
      return base.h;
    case 8:
      return base.b;
    default:
      throw ArgumentError('Unsupported vector size: $sizeBits');
  }
}

bool _canUseScaledImm(int offset, int scale) {
  if (offset < 0) return false;
  if (scale <= 0) return false;
  if (offset % scale != 0) return false;
  final imm = offset ~/ scale;
  return imm >= 0 && imm <= 4095;
}

bool _canUseAddImm(int offset) {
  return offset >= 0 && offset <= 4095;
}
