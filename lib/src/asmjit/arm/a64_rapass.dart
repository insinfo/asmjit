/// AArch64 hooks for the register allocator (counterpart of asmjit's
/// `a64::ARMRAPass` and `a64::EmitHelper`).
///
/// Frame layout produced by [A64RAArch.insertPrologEpilog] (AAPCS64):
///
/// ```
///   [x29 + 8]   saved x30 (LR)
///   [x29 + 0]   saved x29 (FP)          <- x29
///   ...         callee-saved x19-x28 / d8-d15
///   [sp + 0]    spill slots              <- sp (16-byte aligned)
/// ```
///
/// Spill slots are addressed from SP with positive offsets, so the scaled
/// unsigned-offset LDR/STR forms can be used.

import '../core/compiler.dart';
import '../core/labels.dart';
import '../core/raarch.dart';
import '../core/radefs.dart';
import '../core/type.dart';
import 'a64.dart';
import 'a64_inst_db.g.dart';

class A64RAArch extends RAArch {
  static const _sp = A64Gp(31, 64);
  static const _fp = A64Gp(29, 64);
  static const _lr = A64Gp(30, 64);

  /// All register operands are read (stores, compares, branches).
  static final Set<int> _readOnlyIds = {
    A64InstId.kStr,
    A64InstId.kStrb,
    A64InstId.kStrh,
    A64InstId.kStur,
    A64InstId.kSturb,
    A64InstId.kSturh,
    A64InstId.kStp,
    A64InstId.kStnp,
    A64InstId.kSt1,
    A64InstId.kSt2,
    A64InstId.kSt3,
    A64InstId.kSt4,
    A64InstId.kStlr,
    A64InstId.kCmp,
    A64InstId.kCmn,
    A64InstId.kTst,
    A64InstId.kFcmp,
    A64InstId.kFcmpe,
    A64InstId.kCcmp,
    A64InstId.kCcmn,
    A64InstId.kCbz,
    A64InstId.kCbnz,
    A64InstId.kTbz,
    A64InstId.kTbnz,
    A64InstId.kBr,
    A64InstId.kBlr,
    A64InstId.kRet,
    A64InstId.kB,
    A64InstId.kBl,
    A64InstId.kB_cond,
  };

  /// Operand 0 is read and written (accumulate / insert / narrow-high).
  static final Set<int> _readWriteDstIds = {
    A64InstId.kMovk,
    A64InstId.kBfi,
    A64InstId.kBfxil,
    A64InstId.kBfm,
    A64InstId.kFmla,
    A64InstId.kFmls,
    A64InstId.kMla,
    A64InstId.kMls,
    A64InstId.kSdot,
    A64InstId.kUdot,
    A64InstId.kBsl,
    A64InstId.kBit,
    A64InstId.kBif,
    A64InstId.kSri,
    A64InstId.kSli,
    A64InstId.kTbx,
    A64InstId.kXtn2,
    A64InstId.kSqxtn2,
    A64InstId.kUqxtn2,
    A64InstId.kSqxtun2,
    A64InstId.kFcvtn2,
  };

  /// Every register operand is written (loads of multiple registers).
  static final Set<int> _multiLoadIds = {
    A64InstId.kLdp,
    A64InstId.kLdnp,
    A64InstId.kLd1,
    A64InstId.kLd2,
    A64InstId.kLd3,
    A64InstId.kLd4,
  };

  @override
  void initRegMasks(BaseCompiler cc, RARegMask avail, RARegMask preserved,
      {FuncNode? func}) {
    // x18 is the platform register (reserved on Apple and Windows), x29/x30
    // are FP/LR and x31 is SP/ZR.
    avail[RegGroup.gp] = 0x7FFFFFFF & ~(1 << 18) & ~(1 << 29) & ~(1 << 30);
    avail[RegGroup.vec] = 0xFFFFFFFF;

    // AAPCS64 callee-saved: x19-x28 and the low 64 bits of v8-v15.
    preserved[RegGroup.gp] = 0x1FF80000;
    preserved[RegGroup.vec] = 0xFF00;
  }

  @override
  bool get preciseLiveness => true;

  @override
  bool isMove(InstNode node) => node.instId == A64InstId.kMov;

  @override
  List<int> operandFlags(InstNode node) {
    const use = RATiedFlags.kUse | RATiedFlags.kRead;
    const out = RATiedFlags.kOut | RATiedFlags.kWrite;
    final id = node.instId;
    final n = node.opCount;
    final flags = List<int>.filled(n, use);
    if (n == 0 || _readOnlyIds.contains(id)) return flags;

    if (_multiLoadIds.contains(id)) {
      for (int i = 0; i < n; i++) {
        if (node.operands[i] is BaseReg) flags[i] = out;
      }
    } else if (_readWriteDstIds.contains(id)) {
      flags[0] = use | out;
    } else {
      flags[0] = out;
    }
    return flags;
  }

  /// The allocator moves, spills and reloads whole registers (X / Q): the
  /// operand that introduced a virtual register may be a narrower view
  /// (`w0`, `s0`) of a value that is wider elsewhere.
  static BaseReg _full(BaseReg reg) =>
      reg is A64Vec ? A64Vec(reg.id, 128) : (reg as A64Gp).x;

  @override
  int spillSize(BaseReg reg) => reg is A64Vec ? 16 : 8;

  @override
  InstNode jump(Label target) => JumpNode(A64InstId.kB, [LabelOp(target)]);

  @override
  InstNode move(BaseReg dst, BaseReg src) =>
      InstNode(A64InstId.kMov, [_full(dst), _full(src)]);

  @override
  InstNode load(BaseReg dst, BaseMem src) =>
      InstNode(A64InstId.kLdr, [_full(dst), src]);

  @override
  InstNode loadStackArg(BaseReg dst, int stackOffset, TypeId typeId) {
    final size = typeId.sizeInBytes;
    final mem = A64Mem.baseOffset(_fp, 16 + stackOffset);
    if (dst is A64Vec) {
      return InstNode(A64InstId.kLdr, [A64Vec(dst.id, size * 8), mem]);
    }
    final gp = dst as A64Gp;
    final id = switch ((size, typeId.isSigned)) {
      (1, false) => A64InstId.kLdrb,
      (1, true) => A64InstId.kLdrsb,
      (2, false) => A64InstId.kLdrh,
      (2, true) => A64InstId.kLdrsh,
      _ => A64InstId.kLdr,
    };
    return InstNode(id, [size <= 4 ? gp.w : gp.x, mem]);
  }

  @override
  InstNode save(BaseMem dst, BaseReg src) =>
      InstNode(A64InstId.kStr, [_full(src), dst]);

  @override
  List<InstNode> swap(BaseReg a, BaseReg b) {
    // a ^= b; b ^= a; a ^= b (no scratch register needed).
    if (a is A64Vec && b is A64Vec) {
      final va = A64Vec(a.id, 128, A64Layout.b16);
      final vb = A64Vec(b.id, 128, A64Layout.b16);
      return [
        InstNode(A64InstId.kEor, [va, va, vb]),
        InstNode(A64InstId.kEor, [vb, vb, va]),
        InstNode(A64InstId.kEor, [va, va, vb]),
      ];
    }
    final ga = (a as A64Gp).x, gb = (b as A64Gp).x;
    return [
      InstNode(A64InstId.kEor, [ga, ga, gb]),
      InstNode(A64InstId.kEor, [gb, gb, ga]),
      InstNode(A64InstId.kEor, [ga, ga, gb]),
    ];
  }

  @override
  BaseMem spillSlot(BaseCompiler cc, int offset, int size) =>
      A64Mem.baseOffset(_sp, offset, size: size);

  @override
  BaseMem rebuildMem(BaseMem mem,
      {required BaseReg? base,
      required BaseReg? index,
      required int displacement,
      required int size}) {
    final m = mem as A64Mem;
    final b = base as A64Gp;
    if (index != null) {
      return A64Mem.baseIndex(b, index as A64Gp, shift: m.shift, size: size);
    }
    switch (m.addrMode) {
      case A64AddrMode.offset:
        return A64Mem.baseOffset(b, displacement, size: size);
      case A64AddrMode.preIndex:
        return A64Mem.preIndex(b, displacement, size: size);
      case A64AddrMode.postIndex:
        return A64Mem.postIndex(b, displacement, size: size);
    }
  }

  @override
  void insertPrologEpilog(RAFrameContext ctx) {
    final func = ctx.func;
    final compiler = ctx.compiler;
    func.frame.finalize();

    final gpToSave = ctx.clobbered[RegGroup.gp] & ctx.preserved[RegGroup.gp];
    final vecToSave = ctx.clobbered[RegGroup.vec] & ctx.preserved[RegGroup.vec];

    // Callee-saved registers go right above the spill area.
    int offset = _alignUp(ctx.spillSize, 8);
    final saves = <(BaseReg, int)>[];
    for (int i = 0; i < 32; i++) {
      if ((gpToSave & (1 << i)) != 0) {
        saves.add((A64Gp(i, 64), offset));
        offset += 8;
      }
    }
    for (int i = 0; i < 32; i++) {
      if ((vecToSave & (1 << i)) != 0) {
        // Only the low 64 bits (d8-d15) are callee-saved.
        saves.add((A64Vec(i, 64), offset));
        offset += 8;
      }
    }
    final frameSize = _alignUp(offset, 16);
    if (func.frame.localStackSize < frameSize) {
      func.frame.setLocalStackSize(frameSize);
    }

    final prolog = <InstNode>[
      InstNode(A64InstId.kStp, [_fp, _lr, A64Mem.preIndex(_sp, -16)]),
      InstNode(A64InstId.kMov, [_fp, _sp]),
      ..._adjustSp(A64InstId.kSub, frameSize),
      for (final (reg, off) in saves)
        InstNode(A64InstId.kStr, [reg, A64Mem.baseOffset(_sp, off)]),
    ];
    BaseNode last = func;
    for (final node in prolog) {
      ctx.insertAfter(last, node);
      last = node;
    }

    for (final ret in ctx.retNodes) {
      for (final (reg, off) in saves.reversed) {
        ctx.insertBefore(
            ret, InstNode(A64InstId.kLdr, [reg, A64Mem.baseOffset(_sp, off)]));
      }
      ctx.insertBefore(ret, InstNode(A64InstId.kMov, [_sp, _fp]));
      ctx.insertBefore(
          ret, InstNode(A64InstId.kLdp, [_fp, _lr, A64Mem.postIndex(_sp, 16)]));
      ctx.insertBefore(ret, InstNode(A64InstId.kRet, []));
      compiler.nodes.remove(ret);
    }
  }

  /// `sub/add sp, sp, #size` split into 12-bit chunks (shifted and not).
  static List<InstNode> _adjustSp(int instId, int size) {
    if (size == 0) return const [];
    if (size >= 1 << 24) {
      throw StateError('AArch64 frame too large: $size bytes');
    }
    final hi = size & 0xFFF000, lo = size & 0xFFF;
    return [
      if (hi != 0) InstNode(instId, [_sp, _sp, Imm(hi)]),
      if (lo != 0) InstNode(instId, [_sp, _sp, Imm(lo)]),
    ];
  }

  static int _alignUp(int value, int alignment) =>
      (value + alignment - 1) & ~(alignment - 1);
}
