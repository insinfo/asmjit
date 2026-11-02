/// x86/x64 hooks for the register allocator (counterpart of asmjit's
/// `x86::X86RAPass`).
///
/// Instruction analysis is still heuristic (operand 0 read/write unless the
/// instruction is a move/compare); it should eventually come from the
/// instruction database RW info like in the C++ implementation.

import '../core/arch.dart';
import '../core/compiler.dart';
import '../core/labels.dart';
import '../core/raarch.dart';
import '../core/radefs.dart';
import 'x86.dart';
import 'x86_inst_db.g.dart';
import 'x86_operands.dart';
import 'x86_simd.dart';

class X86RAArch extends RAArch {
  final BaseCompiler? _cc;
  bool _isWindowsTarget = false;

  X86RAArch([this._cc]);

  static final Set<int> _moveIds = {
    X86InstId.kMov,
    X86InstId.kMovaps,
    X86InstId.kMovups,
    X86InstId.kMovdqa,
    X86InstId.kMovdqu,
    X86InstId.kMovss,
    X86InstId.kMovsd,
    X86InstId.kMovd,
    X86InstId.kMovq,
    X86InstId.kVmovaps,
    X86InstId.kVmovups,
    X86InstId.kVmovdqa,
    X86InstId.kVmovdqu,
    X86InstId.kVmovss,
    X86InstId.kVmovsd,
    X86InstId.kVmovd,
    X86InstId.kVmovq,
    X86InstId.kLea,
  };

  // Moves as seen by operand analysis (also covers zero/sign extensions).
  static final Set<int> _tiedMoveIds = {
    ..._moveIds,
    X86InstId.kMovabs,
    X86InstId.kMovzx,
    X86InstId.kMovsx,
    X86InstId.kMovsxd,
  };

  static final Set<int> _readOnlyIds = {
    X86InstId.kTest,
    X86InstId.kCmp,
    X86InstId.kComiss,
    X86InstId.kComisd,
    X86InstId.kUcomiss,
    X86InstId.kUcomisd,
    X86InstId.kPtest,
    X86InstId.kVptest,
  };

  static final Set<int> _mulDivIds = {
    X86InstId.kDiv,
    X86InstId.kIdiv,
    X86InstId.kMul,
  };

  static final Set<int> _blendvIds = {
    X86InstId.kPblendvb,
    X86InstId.kBlendvps,
    X86InstId.kBlendvpd,
  };

  static final Set<int> _shiftIds = {
    X86InstId.kShl,
    X86InstId.kShr,
    X86InstId.kSar,
    X86InstId.kRol,
    X86InstId.kRor,
  };

  @override
  void initRegMasks(BaseCompiler cc, RARegMask avail, RARegMask preserved) {
    if (cc.arch == Arch.x64) {
      final isWindows = cc.environment.os == 'windows';
      _isWindowsTarget = isWindows;

      // All 16 GPs except RSP (stack pointer) and RBP (frame pointer).
      avail[RegGroup.gp] = 0xFFFF & ~(1 << 4) & ~(1 << 5);
      // XMM0-XMM15 (AVX-512 registers are not allocated yet).
      avail[RegGroup.vec] = 0xFFFF;

      int presGp = 0;
      for (final reg
          in isWindows ? x64WindowsPreservedGp : x64SystemVPreservedGp) {
        presGp |= 1 << reg.id;
      }
      preserved[RegGroup.gp] = presGp;

      // Win64: XMM6-XMM15 are callee-saved; SysV: all vector regs volatile.
      preserved[RegGroup.vec] = isWindows ? 0xFFC0 : 0;
    } else {
      avail[RegGroup.gp] = 0xFF & ~(1 << 4); // Remove ESP
      avail[RegGroup.vec] = 0xFF; // 8 XMMs
      // EBX, EBP, ESI, EDI.
      preserved[RegGroup.gp] = (1 << 3) | (1 << 5) | (1 << 6) | (1 << 7);
    }
  }

  @override
  bool isMove(InstNode node) => _moveIds.contains(node.instId);

  @override
  List<int> operandFlags(InstNode node) {
    const use = RATiedFlags.kUse | RATiedFlags.kRead;
    const out = RATiedFlags.kOut | RATiedFlags.kWrite;
    // Like asmjit (`kRW | kUse`): a read/write operand is rewritten in place,
    // in the register it is read from.
    const rw = RATiedFlags.kUse | RATiedFlags.kRead | RATiedFlags.kWrite;
    final id = node.instId;
    final opCount = node.opCount;
    final flags = List<int>.filled(opCount, 0);
    if (opCount == 0) return flags;

    if (_mulDivIds.contains(id) && opCount == 3) {
      // asmjit's explicit form `div rdx, rax, src`: RDX:RAX are read and
      // written in place (fixedUseId assigns them).
      flags[0] = rw;
      flags[1] = rw;
      flags[2] = use;
    } else if (_tiedMoveIds.contains(id)) {
      flags[0] = out;
      if (opCount > 1) flags[1] = use;
    } else if (id == X86InstId.kXchg) {
      flags[0] = use | out;
      if (opCount > 1) flags[1] = use | out;
    } else if (_readOnlyIds.contains(id) || id == X86InstId.kPush) {
      for (int i = 0; i < opCount && i < 2; i++) {
        flags[i] = use;
      }
    } else if (id == X86InstId.kPop) {
      flags[0] = out;
    } else if (_op0Access(id, opCount) != 0) {
      // Access of the destination from the instruction database (`W:`,
      // `X:`, ... in isa_x86.json): legacy SSE forms with an immediate or an
      // implicit XMM0 (`shufps`, `palignr`, `pblendvb`) read and write it,
      // `pshufd` and the VEX forms only write it.
      flags[0] = switch (_op0Access(id, opCount)) {
        1 => use,
        2 => out,
        _ => rw,
      };
      for (int i = 1; i < opCount; i++) {
        flags[i] = use;
      }
    } else if (opCount >= 3) {
      // AVX non-destructive form: op0 = out, rest = use.
      flags[0] = out;
      for (int i = 1; i < opCount; i++) {
        flags[i] = use;
      }
    } else {
      // Destructive 2-operand form: op0 = read/write.
      flags[0] = use | out;
      if (opCount > 1) flags[1] = use;
    }
    return flags;
  }

  static int _op0Access(int instId, int opCount) =>
      instId >= 0 && instId < kX86InstDb.length
          ? kX86InstDb[instId].op0AccessOf(opCount)
          : 0;

  @override
  int fixedUseId(InstNode node, int opIndex) {
    // Variable shift/rotate count must be in CL.
    if (opIndex == 1 && _shiftIds.contains(node.instId)) return 1;
    // The legacy SSE4.1 variable blends take their mask implicitly in XMM0.
    if (opIndex == 2 && _blendvIds.contains(node.instId)) return 0;
    // `div rdx, rax, src` (and MUL/IDIV) with explicit RDX:RAX operands.
    if (node.opCount == 3 && _mulDivIds.contains(node.instId)) {
      if (opIndex == 0) return 2;
      if (opIndex == 1) return 0;
    }
    return RAAssignment.kPhysNone;
  }

  @override
  void implicitRegs(InstNode node, RARegMask used, RARegMask clobbered) {
    final id = node.instId;
    if (_mulDivIds.contains(id) && node.opCount == 1) {
      clobbered[RegGroup.gp] |= (1 << 0) | (1 << 2); // RAX, RDX
      used[RegGroup.gp] |= (1 << 0) | (1 << 2);
    } else if (id == X86InstId.kCpuid) {
      clobbered[RegGroup.gp] |= (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3);
      used[RegGroup.gp] |= 1 << 0; // EAX input
    }
  }

  bool _hasAvx(BaseCompiler? cc) {
    try {
      return (cc as dynamic).hasAvx as bool;
    } catch (_) {
      return false;
    }
  }

  @override
  InstNode jump(Label target) => JumpNode(X86InstId.kJmp, [LabelOp(target)]);

  @override
  InstNode move(BaseReg dst, BaseReg src) {
    if (dst.group == RegGroup.vec) {
      return InstNode(
          _hasAvx(_cc) ? X86InstId.kVmovaps : X86InstId.kMovaps, [dst, src]);
    }
    return InstNode(X86InstId.kMov, [dst, src]);
  }

  @override
  InstNode load(BaseReg dst, BaseMem src) {
    if (dst.group == RegGroup.vec) {
      return InstNode(
          _hasAvx(_cc) ? X86InstId.kVmovups : X86InstId.kMovups, [dst, src]);
    }
    return InstNode(X86InstId.kMov, [dst, src]);
  }

  @override
  InstNode save(BaseMem dst, BaseReg src) {
    if (src.group == RegGroup.vec) {
      return InstNode(
          _hasAvx(_cc) ? X86InstId.kVmovups : X86InstId.kMovups, [dst, src]);
    }
    return InstNode(X86InstId.kMov, [dst, src]);
  }

  @override
  List<InstNode> swap(BaseReg a, BaseReg b) {
    if (a.group == RegGroup.vec) {
      if (_hasAvx(_cc)) {
        return [
          InstNode(X86InstId.kVpxor, [a, a, b]),
          InstNode(X86InstId.kVpxor, [b, a, b]),
          InstNode(X86InstId.kVpxor, [a, a, b]),
        ];
      }
      return [
        InstNode(X86InstId.kPxor, [a, b]),
        InstNode(X86InstId.kPxor, [b, a]),
        InstNode(X86InstId.kPxor, [a, b]),
      ];
    }
    return [
      InstNode(X86InstId.kXchg, [a, b])
    ];
  }

  @override
  BaseMem spillSlot(BaseCompiler cc, int offset, int size) {
    // Spill slots live below the frame pointer: [rbp - (offset + size)].
    return cc.newStackSlot(X86RegId.rbp.index, -(offset + size), size);
  }

  @override
  BaseMem rebuildMem(BaseMem mem,
      {required BaseReg? base,
      required BaseReg? index,
      required int displacement,
      required int size}) {
    final m = mem as X86Mem;
    return X86Mem(
        base: base,
        index: index,
        scale: m.scale,
        displacement: displacement,
        size: size,
        segment: m.segment,
        label: m.label);
  }

  @override
  void insertPrologEpilog(RAFrameContext ctx) {
    final func = ctx.func;
    final compiler = ctx.compiler;

    // Finalize frame to calculate total size
    func.frame.finalize();

    final is64Bit = compiler.arch == Arch.x64;
    if (!is64Bit) return;

    // Detect VEX-prefixed (AVX) instructions by name in the instruction DB.
    // This matters on Win64: VEX-encoded scalar ops on XMM6..XMM15 also
    // modify the upper 128 bits of the corresponding YMM register, which are
    // required to be preserved when AVX is in use.
    bool usesVex = false;
    for (final n in compiler.nodes.nodes) {
      if (n is InstNode) {
        final id = n.instId;
        if (id >= 0 && id < kX86InstDb.length) {
          final name = kX86InstDb[id].name;
          if (name.isNotEmpty && name.codeUnitAt(0) == 0x76 /* 'v' */) {
            usesVex = true;
            break;
          }
        }
      }
    }

    final gpPreserved = ctx.preserved[RegGroup.gp];
    // On Win64 conservatively save all allocatable preserved GP registers
    // (RBX, RSI, RDI, R12-R15...).
    final gpToSave = _isWindowsTarget
        ? (gpPreserved & ctx.available[RegGroup.gp])
        : (ctx.clobbered[RegGroup.gp] & gpPreserved);

    // Win64: XMM6..XMM15 are callee-saved. If clobber tracking misses a vector
    // reg in some corner case we would corrupt the caller (Dart VM), so save
    // all preserved vector registers conservatively.
    final vecPreserved = ctx.preserved[RegGroup.vec];
    final vecToSave = _isWindowsTarget
        ? (vecPreserved & ctx.available[RegGroup.vec])
        : (ctx.clobbered[RegGroup.vec] & vecPreserved);

    final savedRegs = <X86Gp>[
      for (int i = 0; i < 16; i++)
        if ((gpToSave & (1 << i)) != 0) X86Gp.r64(i)
    ];

    // On Win64 + AVX, preserve YMM6..YMM15 (full 256-bit).
    final vecSaveBytes = (_isWindowsTarget && usesVex) ? 32 : 16;

    // Layout below RBP: locals/spills -> aligned vec saves -> gp saves.
    int currentOffset = _alignUp(ctx.spillSize, 16);
    final vecSlots = <MapEntry<X86Xmm, int>>[];
    final gpSlots = <MapEntry<X86Gp, int>>[];

    for (int i = 0; i < 32; i++) {
      if ((vecToSave & (1 << i)) != 0) {
        currentOffset += vecSaveBytes;
        vecSlots.add(MapEntry(X86Xmm(i), currentOffset));
      }
    }

    if (savedRegs.isNotEmpty) {
      currentOffset = _alignUp(currentOffset, 8);
      for (final reg in savedRegs) {
        currentOffset += 8;
        gpSlots.add(MapEntry(reg, currentOffset));
      }
    }

    final totalStackSize = _alignUp(currentOffset, 16);
    if (func.frame.localStackSize < totalStackSize) {
      func.frame.setLocalStackSize(totalStackSize);
    }

    final rbp = X86Gp.r64(X86RegId.rbp.index);
    final rsp = X86Gp.r64(X86RegId.rsp.index);

    // Prolog: push rbp; mov rbp, rsp; sub rsp, N; save registers.
    final prolog = <InstNode>[
      InstNode(X86InstId.kPush, [rbp]),
      InstNode(X86InstId.kMov, [rbp, rsp]),
      if (totalStackSize > 0)
        InstNode(X86InstId.kSub, [rsp, Imm(totalStackSize)]),
      for (final slot in vecSlots)
        InstNode(vecSaveBytes == 32 ? X86InstId.kVmovdqu : X86InstId.kMovdqu, [
          X86Mem.baseDisp(rbp, -slot.value, size: vecSaveBytes),
          vecSaveBytes == 32 ? X86Ymm(slot.key.id) : slot.key
        ]),
      for (final slot in gpSlots)
        InstNode(X86InstId.kMov, [X86Mem.baseDisp(rbp, -slot.value), slot.key]),
    ];
    BaseNode last = func;
    for (final node in prolog) {
      ctx.insertAfter(last, node);
      last = node;
    }

    // Epilog before every return.
    for (final ret in ctx.retNodes) {
      for (final slot in gpSlots.reversed) {
        ctx.insertBefore(
            ret,
            InstNode(
                X86InstId.kMov, [slot.key, X86Mem.baseDisp(rbp, -slot.value)]));
      }
      for (final slot in vecSlots.reversed) {
        ctx.insertBefore(
            ret,
            InstNode(
                vecSaveBytes == 32 ? X86InstId.kVmovdqu : X86InstId.kMovdqu, [
              vecSaveBytes == 32 ? X86Ymm(slot.key.id) : slot.key,
              X86Mem.baseDisp(rbp, -slot.value, size: vecSaveBytes)
            ]));
      }
      ctx.insertBefore(ret, InstNode(X86InstId.kMov, [rsp, rbp]));
      ctx.insertBefore(ret, InstNode(X86InstId.kPop, [rbp]));
      ctx.insertBefore(ret, InstNode(X86InstId.kRet, []));
      compiler.nodes.remove(ret);
    }
  }

  static int _alignUp(int value, int alignment) =>
      (value + alignment - 1) & ~(alignment - 1);
}
