/// x86/x64 hooks for the register allocator (counterpart of asmjit's
/// `x86::X86RAPass`).
///
/// Instruction analysis is still heuristic (operand 0 read/write unless the
/// instruction is a move/compare); it should eventually come from the
/// instruction database RW info like in the C++ implementation.

import '../core/arch.dart';
import '../core/compiler.dart';
import '../core/error.dart';
import '../core/func.dart';
import '../core/globals.dart';
import '../core/reg_utils.dart';
import '../core/labels.dart';
import '../core/raarch.dart';
import '../core/radefs.dart';
import '../core/reg_type.dart';
import '../core/inst_api.dart';
import '../core/type.dart';
import 'x86.dart';
import 'x86_inst_db.g.dart';
import 'x86_opcode.dart';
import 'x86_rw_info.dart';
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
  void initRegMasks(BaseCompiler cc, RARegMask avail, RARegMask preserved,
      {FuncNode? func}) {
    if (cc.arch == Arch.x64) {
      // The calling convention of the function decides what it preserves
      // (a function may use another convention than the target's default,
      // e.g. `CallConvId::kX64Windows` or a light call).
      final callConv = func?.detail.callConv;
      final isWindows = callConv != null && callConv.arch != Arch.unknown
          ? callConv.id == CallConvId.x64Windows
          : cc.environment.os == 'windows';
      _isWindowsTarget = isWindows;
      _avxEnabled = func?.frame.isAvxEnabled() ?? false;

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

      if (callConv != null && callConv.arch != Arch.unknown) {
        preserved[RegGroup.gp] =
            callConv.preservedRegs(RegGroup.gp) & avail[RegGroup.gp];
        preserved[RegGroup.vec] =
            callConv.preservedRegs(RegGroup.vec) & avail[RegGroup.vec];
      }
    } else {
      avail[RegGroup.gp] = 0xFF & ~(1 << 4); // Remove ESP
      avail[RegGroup.vec] = 0xFF; // 8 XMMs
      // EBX, EBP, ESI, EDI.
      preserved[RegGroup.gp] = (1 << 3) | (1 << 5) | (1 << 6) | (1 << 7);
    }
  }

  // ===========================================================================
  // RACFGBuilder::on_instruction()
  // ===========================================================================

  /// `ra_use_out_flags_from_rw_flags()`.
  static int _useOutFlags(int rwFlags) {
    const map = [
      RATiedFlags.kNone,
      RATiedFlags.kRead | RATiedFlags.kUse, // kRead
      RATiedFlags.kWrite | RATiedFlags.kOut, // kWrite
      RATiedFlags.kRW | RATiedFlags.kUse, // kRW
      RATiedFlags.kNone,
      // kRead | kRegMem
      RATiedFlags.kRead | RATiedFlags.kUse | RATiedFlags.kUseRM,
      // kWrite | kRegMem
      RATiedFlags.kWrite | RATiedFlags.kOut | RATiedFlags.kOutRM,
      // kRW | kRegMem
      RATiedFlags.kRW | RATiedFlags.kUse | RATiedFlags.kUseRM,
    ];
    return map[rwFlags & (OpRWFlags.kRW | OpRWFlags.kRegMem)];
  }

  /// `ra_imm_mask_from_size()`.
  static int _immMaskFromSize(int size) => switch (size) {
        1 => 0xFF,
        2 => 0xFFFF,
        4 => 0xFFFFFFFF,
        8 => -1,
        _ => 0,
      };

  /// Port of `x86::RACFGBuilder::on_instruction()`: the tied registers of
  /// [node] from its read/write information ([x86QueryRWInfo]). Returns
  /// null for an instruction the RW information does not describe.
  ///
  /// Physical registers are listed too (with their RW flags); upstream
  /// ignores them, the Dart [RAPass] uses them as used/clobbered registers.
  @override
  List<RAInstOp>? analyzeInst(BaseCompiler cc, InstNode node) {
    if (node is FuncRetNode) return null;
    final instId = node.instId;
    if (instId < 0 || instId >= kX86InstDb.length) return null;

    final operands = node.operands;
    final rwInfo = InstRWInfo();
    if (!x86QueryRWInfo(cc.arch.is64Bit, instId, operands, rwInfo,
        options: node.options, extraReg: node.extraReg)) {
      return null;
    }

    final dbFlags = kX86InstDb[instId].dbFlags;
    final is64Bit = cc.arch.is64Bit;
    var hasGpbHiConstraint = false;
    var singleRegOps = 0;
    final ops = <RAInstOp>[];

    // The mask is for all registers, but we are mostly interested in
    // AVX-512 registers at the moment.
    var instructionAllowedRegs = 0xFFFFFFFF;
    if ((dbFlags & X86InstDbFlags.kEvex) != 0) {
      // EVEX instruction and VEX instructions that can be encoded with EVEX
      // have the possibility to use 32 SIMD registers (XMM/YMM/ZMM).
      if ((dbFlags & X86InstDbFlags.kVex) != 0 &&
          (dbFlags & X86InstDbFlags.kEvexCompat) == 0) {
        if ((dbFlags & X86InstDbFlags.kEvexKReg) != 0) {
          // EVEX encodable only if the first operand is K register.
          if (operands.isEmpty || operands[0] is! X86KReg) {
            instructionAllowedRegs = 0xFFFF;
          }
        } else if ((dbFlags & X86InstDbFlags.kEvexTwoOp) != 0) {
          // EVEX encodable only if the instruction has two operands.
          if (operands.length != 2) instructionAllowedRegs = 0xFFFF;
        } else {
          instructionAllowedRegs = 0xFFFF;
        }
      }
    } else if ((dbFlags & X86InstDbFlags.kEvexTransformable) == 0) {
      // Not EVEX, restrict everything to [0-15] registers.
      instructionAllowedRegs = 0xFFFF;
    }

    for (var i = 0; i < operands.length; i++) {
      final op = operands[i];
      final opRwInfo = rwInfo.operand(i);

      if (op is BaseReg) {
        var flags = _useOutFlags(opRwInfo.opFlags);
        var allowedRegs = instructionAllowedRegs;

        if (opRwInfo.isUnique) flags |= RATiedFlags.kUnique;

        // X86-specific constraints related to LO|HI general purpose
        // registers. This is only required when the register is part of the
        // encoding. If the register is fixed we won't restrict anything as
        // it doesn't restrict encoding of other registers.
        if (op is X86Gp &&
            op.size == 1 &&
            !opRwInfo.hasOpFlag(OpRWFlags.kRegPhysId)) {
          flags |= RATiedFlags.kX86Gpb;
          if (!is64Bit) {
            allowedRegs = 0x0F;
          } else if (op.isHighByte) {
            hasGpbHiConstraint = true;
            allowedRegs = 0x0F;
          }
        }

        if (op.isPhysical) {
          ops.add(RAInstOp(op, RAInstOp.kSlotReg, i, flags));
          continue;
        }

        // Use RW instead of Write in case that not the whole register is
        // overwritten. This is important for liveness as we cannot kill a
        // register that will be used. For example `mov al, 0xFF` is not a
        // write-only operation if user allocated the whole `rax` register.
        if ((flags & RATiedFlags.kRW) == RATiedFlags.kWrite) {
          final virtSize = cc.virtRegById(op.id)?.size ?? 0;
          final regSize = virtSize > 0 ? virtSize : op.size;
          final regByteMask = regSize >= 64 ? -1 : (1 << regSize) - 1;
          if ((regByteMask &
                  ~(opRwInfo.writeByteMask | opRwInfo.extendByteMask)) !=
              0) {
            // Not write-only operation.
            flags = (flags & ~RATiedFlags.kOut) |
                (RATiedFlags.kRead | RATiedFlags.kUse);
          }
        }

        final raOp = RAInstOp(op, RAInstOp.kSlotReg, i, flags,
            useMask: allowedRegs, outMask: allowedRegs);
        if ((flags & RATiedFlags.kUse) != 0) {
          if (opRwInfo.hasOpFlag(OpRWFlags.kRegPhysId)) {
            raOp.useId = opRwInfo.physId;
            raOp.flags |= RATiedFlags.kUseFixed;
          }
        } else {
          if (opRwInfo.hasOpFlag(OpRWFlags.kRegPhysId)) {
            raOp.outId = opRwInfo.physId;
            raOp.flags |= RATiedFlags.kOutFixed;
          }
        }
        ops.add(raOp);
        if (singleRegOps == i) singleRegOps++;
      } else if (op is BaseMem) {
        final base = op.base;
        if (base != null) {
          // `ra_mem_base_rw_flags()`.
          final flags = _useOutFlags((opRwInfo.opFlags >> 12) & OpRWFlags.kRW);
          final raOp = RAInstOp(base, RAInstOp.kSlotMemBase, i, flags);
          if (opRwInfo.hasOpFlag(OpRWFlags.kMemPhysId)) {
            if ((flags & RATiedFlags.kUse) != 0) {
              raOp.useId = opRwInfo.physId;
              raOp.flags |= RATiedFlags.kUseFixed;
            } else {
              raOp.outId = opRwInfo.physId;
              raOp.flags |= RATiedFlags.kOutFixed;
            }
          }
          ops.add(raOp);
        }

        final index = op.index;
        if (index != null) {
          // Index registers have never fixed id on X86/x64.
          ops.add(RAInstOp(index, RAInstOp.kSlotMemIndex, i,
              RATiedFlags.kUse | RATiedFlags.kRead,
              useMask: instructionAllowedRegs,
              outMask: instructionAllowedRegs));
        }
      }
    }

    // Handle extra operand (either REP {cx|ecx|rcx} or AVX-512 {k}
    // selector).
    final extraReg = node.extraReg;
    if (extraReg != null) {
      if (!extraReg.isPhysical) {
        if (extraReg.group == RegGroup.mask) {
          // AVX-512 mask selector {k} register - read-only, allocable to any
          // register except {k0}.
          ops.add(RAInstOp(extraReg, RAInstOp.kSlotExtra, -1,
              RATiedFlags.kUse | RATiedFlags.kRead));
          singleRegOps = 0;
        } else {
          // REP {cx|ecx|rcx} register - read & write, allocable to
          // {cx|ecx|rcx} only.
          ops.add(RAInstOp(extraReg, RAInstOp.kSlotExtra, -1,
              RATiedFlags.kUse | RATiedFlags.kRW | RATiedFlags.kUseFixed,
              useId: X86RegId.rcx.index));
        }
      } else if (extraReg.group == RegGroup.mask && extraReg.id != 0) {
        singleRegOps = 0;
      }
    }

    // Handle X86 constraints.
    if (hasGpbHiConstraint) {
      for (final o in ops) {
        final filter = (o.flags & RATiedFlags.kX86Gpb) != 0 ? 0x0F : 0xFF;
        o.useMask &= filter;
        o.outMask &= filter;
      }
    }

    // `ib.tied_reg_count() == 1`: a single virtual register.
    final virtIds = {
      for (final o in ops)
        if (!o.reg.isPhysical) o.reg.id
    };
    if (virtIds.length == 1) {
      // Handle special cases of some instructions where all operands share
      // the same register. In such case the single operand becomes
      // read-only or write-only.
      var sameRegHint = InstSameRegHint.kNone;
      if (singleRegOps == operands.length) {
        sameRegHint = x86InstSameRegHint(instId);
      } else if (operands.length == 2 &&
          operands[1] is Imm &&
          operands[0] is BaseReg) {
        // Handle some tricks used by X86 asm.
        final reg = operands[0] as BaseReg;
        final imm = (operands[1] as Imm).value;
        final virtSize = cc.virtRegById(virtIds.first)?.size ?? 0;
        final workRegSize = virtSize > 0 ? virtSize : reg.size;

        if (instId == X86InstId.kOr) {
          // Sets the value of the destination register to -1, previous
          // content unused.
          if (reg.size >= 4 || reg.size >= workRegSize) {
            if (imm == -1 || imm == _immMaskFromSize(reg.size)) {
              sameRegHint = InstSameRegHint.kWO;
            }
          }
        }
        if (instId == X86InstId.kOr ||
            instId == X86InstId.kAdd ||
            instId == X86InstId.kAnd ||
            instId == X86InstId.kRol ||
            instId == X86InstId.kRor ||
            instId == X86InstId.kSar ||
            instId == X86InstId.kShl ||
            instId == X86InstId.kShr ||
            instId == X86InstId.kSub ||
            instId == X86InstId.kXor) {
          // Updates [E|R]FLAGS without changing the content.
          if (reg.size != 4 || reg.size >= workRegSize) {
            if (imm == 0) sameRegHint = InstSameRegHint.kRO;
          }
        }
      } else if (operands.length == 4 && operands[3] is Imm) {
        if (instId == X86InstId.kVpternlogd ||
            instId == X86InstId.kVpternlogq) {
          final predicate = (operands[3] as Imm).value & 0xFF;
          if (predicate == 0x00 || predicate == 0xFF) {
            for (final o in ops) {
              if (!o.reg.isPhysical) o.makeWriteOnly();
            }
          }
        }
      }

      switch (sameRegHint) {
        case InstSameRegHint.kRO:
          for (final o in ops) {
            if (!o.reg.isPhysical) o.makeReadOnly();
          }
        case InstSameRegHint.kWO:
          for (final o in ops) {
            if (!o.reg.isPhysical) o.makeWriteOnly();
          }
      }
    }

    return ops;
  }

  @override
  BaseReg virtRegOperand(VirtReg vr, BaseReg seen) {
    final id = seen.id;
    return switch (RegType.values[vr.signature.regType]) {
      RegType.gp8Lo => X86Gp.r8(id),
      RegType.gp16 => X86Gp.r16(id),
      RegType.gp32 => X86Gp.r32(id),
      RegType.gp64 => X86Gp.r64(id),
      RegType.vec128 => X86Xmm(id),
      RegType.vec256 => X86Ymm(id),
      RegType.vec512 => X86Zmm(id),
      RegType.mask => X86KReg(id),
      _ => seen,
    };
  }

  // ===========================================================================
  // RACFGBuilder::on_before_invoke()
  // ===========================================================================

  static bool _isGp8(TypeId t) => t == TypeId.int8 || t == TypeId.uint8;
  static bool _isGp16(TypeId t) => t == TypeId.int16 || t == TypeId.uint16;
  static bool _isGp32(TypeId t) => t == TypeId.int32 || t == TypeId.uint32;
  static bool _isGp64(TypeId t) => t == TypeId.int64 || t == TypeId.uint64;

  /// `TypeUtils::deabstract()`: the abstract pointer-sized integers.
  static TypeId _deabstract(TypeId t, bool is64Bit) => switch (t) {
        TypeId.intPtr => is64Bit ? TypeId.int64 : TypeId.int32,
        TypeId.uintPtr => is64Bit ? TypeId.uint64 : TypeId.uint32,
        _ => t,
      };

  X86Gp _zsp(BaseCompiler cc) => cc.arch.is64Bit ? X86Gp.rsp : X86Gp.esp;

  /// New virtual GP register of [typeId] (`_new_reg()`).
  X86Gp _newGp(BaseCompiler cc, TypeId typeId) {
    final is64 = typeId.sizeInBytes == 8;
    final vr = cc.newVirtReg(
        typeId,
        OperandSignature.fromRegTypeAndGroup(
            is64 ? RegType.gp64 : RegType.gp32, RegGroup.gp));
    return is64 ? X86Gp.r64(vr.id) : X86Gp.r32(vr.id);
  }

  /// Port of `x86::RACFGBuilder::on_before_invoke()`: moves the immediate
  /// arguments to registers or to the stack, stores the register arguments
  /// passed on the stack and passes vectors by pointer where the calling
  /// convention requires it, with instructions inserted before [node].
  @override
  void onBeforeInvoke(BaseCompiler cc, FuncNode func, InvokeNode node) {
    final fd = node.detail;
    final argCount = node.argCount;
    final prevCursor = cc.cursor;

    cc.setCursor(node.prev);
    final nativeRegType = cc.arch.is64Bit ? RegType.gp64 : RegType.gp32;

    for (var argIndex = 0; argIndex < argCount; argIndex++) {
      final argPack = fd.args[argIndex];
      for (var valueIndex = 0;
          valueIndex < Globals.kMaxValuePack;
          valueIndex++) {
        final arg = argPack[valueIndex];
        if (!arg.isInitialized) break;

        final op = node.arg(argIndex, valueIndex);
        if (op.isNone) continue;

        if (op is BaseReg) {
          if (arg.isReg) {
            final regGroup = op.group;
            final argGroup = RegUtils.groupOf(arg.fullRegType);

            if (arg.isIndirect) {
              if (op is X86Gp) {
                if (op.type != nativeRegType) {
                  throw AsmJitException(AsmJitError.invalidAssignment,
                      'invalid assignment of a function call argument');
                }
                // It's considered allocated if this is an indirect argument
                // and the user used GP.
                continue;
              }

              final indirectReg = _moveVecToPtr(cc, func, node, arg, op);
              node.setArgValue(argIndex, valueIndex, indirectReg);
            } else if (regGroup != argGroup) {
              // TODO: Conversion is not supported (as upstream).
              throw AsmJitException(AsmJitError.invalidAssignment,
                  'invalid assignment of a function call argument');
            }
          } else {
            if (arg.isIndirect) {
              if (op is X86Gp) {
                if (op.type != nativeRegType) {
                  throw AsmJitException(AsmJitError.invalidAssignment,
                      'invalid assignment of a function call argument');
                }
                _moveRegToStackArg(cc, arg, op);
                continue;
              }

              final indirectReg = _moveVecToPtr(cc, func, node, arg, op);
              _moveRegToStackArg(cc, arg, indirectReg);
            } else {
              _moveRegToStackArg(cc, arg, op);
            }
          }
        } else if (op is Imm) {
          if (arg.isReg) {
            final reg = _moveImmToRegArg(cc, arg, op);
            node.setArgValue(argIndex, valueIndex, reg);
          } else {
            _moveImmToStackArg(cc, arg, op);
          }
        }
      }
    }

    cc.setCursor(node);
    if (fd.hasFlag(CallConvFlags.kCalleePopsStack) && fd.argStackSize != 0) {
      cc.inst(X86InstId.kSub, [_zsp(cc), Imm(fd.argStackSize)]);
    }

    if (fd.hasRet()) {
      for (var valueIndex = 0;
          valueIndex < Globals.kMaxValuePack;
          valueIndex++) {
        final ret = fd.rets[valueIndex];
        if (!ret.isInitialized) break;

        final op = node.ret(valueIndex);
        if (op is BaseReg && ret.isReg) {
          if (ret.fullRegType == RegType.x86St) {
            // x87 return values (32-bit conventions) are not ported.
            throw UnsupportedError('x87 return values are not supported');
          }
          if (op.group != RegUtils.groupOf(ret.fullRegType)) {
            // TODO: Conversion is not supported (as upstream).
            throw AsmJitException(AsmJitError.invalidAssignment,
                'invalid assignment of a function call argument');
          }
        }
      }
    }

    cc.setCursor(prevCursor);
  }

  /// `x86::RACFGBuilder::move_vec_to_ptr()`.
  X86Gp _moveVecToPtr(BaseCompiler cc, FuncNode func, InvokeNode node,
      FuncValue arg, BaseReg src) {
    var argSize = arg.typeId.sizeInBytes;
    if (argSize == 0)
      throw AsmJitException(AsmJitError.invalidState, 'invalid function call');
    if (argSize < 16) argSize = 16;

    final fd = node.detail;
    final argStackOffset = (fd.argStackSize + argSize - 1) & ~(argSize - 1);
    func.frame.updateCallStackAlignment(argSize);
    fd.setArgStackSize(argStackOffset + argSize);

    final BaseReg vecReg = argSize >= 64
        ? X86Zmm(src.id)
        : argSize >= 32
            ? X86Ymm(src.id)
            : X86Xmm(src.id);
    final vecPtr = X86Mem.baseDisp(_zsp(cc), argStackOffset);

    var vecMovInstId = _hasAvx(_cc) ? X86InstId.kVmovaps : X86InstId.kMovaps;
    if (argSize > 16) vecMovInstId = X86InstId.kVmovaps;

    final out = _newGp(cc, cc.arch.is64Bit ? TypeId.int64 : TypeId.int32);
    cc.inst(X86InstId.kLea, [out, vecPtr]);
    cc.inst(vecMovInstId, [X86Mem.base(out), vecReg]);

    if (arg.isStack) {
      final stackPtr = X86Mem.baseDisp(_zsp(cc), arg.stackOffset);
      cc.inst(X86InstId.kMov, [stackPtr, out]);
    }
    return out;
  }

  /// `x86::RACFGBuilder::move_imm_to_reg_arg()`.
  X86Gp _moveImmToRegArg(BaseCompiler cc, FuncValue arg, Imm imm) {
    var value = imm.value;
    var regTypeId = TypeId.uint32;

    switch (_deabstract(arg.typeId, cc.arch.is64Bit)) {
      case TypeId.int8:
        value = value.toSigned(8) & 0xFFFFFFFF;
      case TypeId.uint8:
        value = value & 0xFF;
      case TypeId.int16:
        value = value.toSigned(16) & 0xFFFFFFFF;
      case TypeId.uint16:
        value = value & 0xFFFF;
      case TypeId.int32:
      case TypeId.uint32:
        value = value & 0xFFFFFFFF;
      case TypeId.int64:
      case TypeId.uint64:
        // Moving to GPD automatically zero extends in 64-bit mode.
        if (value >= 0 && value <= 0xFFFFFFFF) break;
        regTypeId = TypeId.uint64;
      default:
        throw AsmJitException(AsmJitError.invalidAssignment,
            'invalid assignment of a function call argument');
    }

    final out = _newGp(cc, regTypeId);
    cc.inst(X86InstId.kMov, [out, Imm(value)]);
    return out;
  }

  /// `x86::RACFGBuilder::move_imm_to_stack_arg()`.
  void _moveImmToStackArg(BaseCompiler cc, FuncValue arg, Imm imm) {
    var stackOffset = arg.stackOffset;
    var size = 4;
    final values = <int>[];
    final value = imm.value;

    // One stack entry has the same size as the native register size. That
    // means that if we want to move a 32-bit integer on the stack in 64-bit
    // mode, we need to extend it to a 64-bit integer first. In 32-bit mode,
    // pushing a 64-bit on stack is done in two steps by pushing low and high
    // parts separately.
    switch (_deabstract(arg.typeId, cc.arch.is64Bit)) {
      case TypeId.int8:
        values.add(value.toSigned(8) & 0xFFFFFFFF);
      case TypeId.uint8:
        values.add(value & 0xFF);
      case TypeId.int16:
        values.add(value.toSigned(16) & 0xFFFFFFFF);
      case TypeId.uint16:
        values.add(value & 0xFFFF);
      case TypeId.int32:
      case TypeId.uint32:
      case TypeId.float32:
        values.add(value & 0xFFFFFFFF);
      case TypeId.int64:
      case TypeId.uint64:
      case TypeId.float64:
      case TypeId.mmx32:
      case TypeId.mmx64:
        if (cc.arch.is64Bit && value == value.toSigned(32)) {
          size = 8;
          values.add(value);
          break;
        }
        values
          ..add(value & 0xFFFFFFFF)
          ..add((value >> 32) & 0xFFFFFFFF);
      default:
        throw AsmJitException(AsmJitError.invalidAssignment,
            'invalid assignment of a function call argument');
    }

    for (final v in values) {
      cc.inst(X86InstId.kMov, [
        X86Mem.baseDisp(_zsp(cc), stackOffset, size: size),
        Imm(size == 4 ? v.toSigned(32) : v)
      ]);
      stackOffset += size;
    }
  }

  /// `x86::RACFGBuilder::move_reg_to_stack_arg()`.
  void _moveRegToStackArg(BaseCompiler cc, FuncValue arg, BaseReg reg) {
    final zsp = _zsp(cc);
    final offset = arg.stackOffset;
    final id = reg.id;
    final is64Bit = cc.arch.is64Bit;
    final dstTypeId = _deabstract(arg.typeId, is64Bit);
    final srcTypeId =
        _deabstract(cc.virtRegById(id)?.typeId ?? TypeId.void_, is64Bit);
    final hasAvx = _hasAvx(_cc);

    X86Mem at(int size, [int disp = 0]) =>
        X86Mem.baseDisp(zsp, offset + disp, size: size);
    void emit(int instId, List<Operand> ops) => cc.inst(instId, ops);

    // Extend+Move Gp.
    void extendMovGpD(int instId, X86Gp r1) {
      final r0 = X86Gp.r32(id);
      emit(instId, [r0, r1]);
      emit(X86InstId.kMov, [at(4), r0]);
    }

    void extendMovGpDQ(X86Gp r0) {
      emit(X86InstId.kMov, [at(4), r0]);
      emit(X86InstId.kAnd, [at(4, 4), Imm(0)]);
    }

    void extendMovGpXQ(int instId, X86Gp r1) {
      if (is64Bit) {
        final r0 = X86Gp.r64(id);
        emit(instId, [r0, r1]);
        emit(X86InstId.kMov, [at(8), r0]);
      } else {
        final r0 = X86Gp.r32(id);
        emit(instId, [r0, r1]);
        extendMovGpDQ(r0);
      }
    }

    void movGpD() => emit(X86InstId.kMov, [at(4), X86Gp.r32(id)]);
    void movGpQ() => emit(X86InstId.kMov, [at(8), X86Gp.r64(id)]);
    void movMmD() => emit(X86InstId.kMovd, [at(4), X86Mm(id)]);
    void movMmQ() => emit(X86InstId.kMovq, [at(8), X86Mm(id)]);
    void movXmmD() => emit(
        hasAvx ? X86InstId.kVmovss : X86InstId.kMovss, [at(4), X86Xmm(id)]);
    void movXmmQ() => emit(
        hasAvx ? X86InstId.kVmovlps : X86InstId.kMovlps, [at(8), X86Xmm(id)]);

    switch (dstTypeId) {
      case TypeId.int64:
      case TypeId.uint64:
        // Extend BYTE->QWORD (GP).
        if (_isGp8(srcTypeId)) {
          return extendMovGpXQ(
              dstTypeId == TypeId.int64 && srcTypeId == TypeId.int8
                  ? X86InstId.kMovsx
                  : X86InstId.kMovzx,
              X86Gp.r8(id));
        }
        // Extend WORD->QWORD (GP).
        if (_isGp16(srcTypeId)) {
          return extendMovGpXQ(
              dstTypeId == TypeId.int64 && srcTypeId == TypeId.int16
                  ? X86InstId.kMovsx
                  : X86InstId.kMovzx,
              X86Gp.r16(id));
        }
        // Extend DWORD->QWORD (GP).
        if (_isGp32(srcTypeId)) {
          if (dstTypeId == TypeId.int64 && srcTypeId == TypeId.int32) {
            return extendMovGpXQ(X86InstId.kMovsxd, X86Gp.r32(id));
          }
          // ZeroExtendGpDQ.
          return extendMovGpDQ(X86Gp.r32(id));
        }
        // Move QWORD (GP).
        if (_isGp64(srcTypeId)) return movGpQ();
        if (srcTypeId.isMmx) return movMmQ();
        if (srcTypeId.isVec) return movXmmQ();

      case TypeId.int32:
      case TypeId.uint32:
      case TypeId.int16:
      case TypeId.uint16:
      case TypeId.int8:
      case TypeId.uint8:
        if (dstTypeId != TypeId.int8 && dstTypeId != TypeId.uint8) {
          final isDstSigned =
              dstTypeId == TypeId.int16 || dstTypeId == TypeId.int32;
          final isSrcSigned =
              srcTypeId == TypeId.int8 || srcTypeId == TypeId.int16;
          // DWORD <- WORD (Zero|Sign Extend).
          if (_isGp16(srcTypeId)) {
            return extendMovGpD(
                isDstSigned && isSrcSigned
                    ? X86InstId.kMovsx
                    : X86InstId.kMovzx,
                X86Gp.r16(id));
          }
          // DWORD <- BYTE (Zero|Sign Extend).
          if (_isGp8(srcTypeId)) {
            return extendMovGpD(
                isDstSigned && isSrcSigned
                    ? X86InstId.kMovsx
                    : X86InstId.kMovzx,
                X86Gp.r8(id));
          }
        }
        if (srcTypeId.isInt) return movGpD();
        if (srcTypeId.isMmx) return movMmD();
        if (srcTypeId.isVec) return movXmmD();

      case TypeId.mmx32:
      case TypeId.mmx64:
        // Extend BYTE->QWORD (GP).
        if (_isGp8(srcTypeId)) {
          return extendMovGpXQ(X86InstId.kMovzx, X86Gp.r8(id));
        }
        // Extend WORD->QWORD (GP).
        if (_isGp16(srcTypeId)) {
          return extendMovGpXQ(X86InstId.kMovzx, X86Gp.r16(id));
        }
        // Upstream jumps to ExtendMovGpDQ with r0 unset, which fails to
        // emit (an invalid operand).
        if (_isGp32(srcTypeId)) {
          throw AsmJitException(AsmJitError.invalidAssignment,
              'invalid assignment of a function call argument');
        }
        if (_isGp64(srcTypeId)) return movGpQ();
        if (srcTypeId.isMmx) return movMmQ();
        if (srcTypeId.isVec) return movXmmQ();

      case TypeId.float32:
      case TypeId.float32x1:
        if (srcTypeId.isVec) return movXmmD();

      case TypeId.float64:
      case TypeId.float64x1:
        if (srcTypeId.isVec) return movXmmQ();

      default:
        if (dstTypeId.isVec && reg.isVec) {
          final size = dstTypeId.sizeInBytes;
          final vecMovInstId = hasAvx ? X86InstId.kVmovaps : X86InstId.kMovaps;
          final BaseReg r0;
          if (dstTypeId.isVec128) {
            r0 = X86Xmm(id);
          } else if (dstTypeId.isVec256) {
            r0 = X86Ymm(id);
          } else if (dstTypeId.isVec512) {
            r0 = X86Zmm(id);
          } else {
            break;
          }
          return emit(vecMovInstId, [at(size), r0]);
        }
    }
    throw AsmJitException(AsmJitError.invalidAssignment,
        'invalid assignment of a function call argument');
  }

  /// Port of `X86RAPass::emit_pre_call()`: a variadic call sets AL to the
  /// number of vector registers used (SysV) or passes every vector
  /// argument also in the GP register of its position (Win64). [insert]
  /// inserts an instruction right before the call.
  @override
  void emitPreCall(
      BaseCompiler cc, InvokeNode node, void Function(InstNode) insert) {
    final fd = node.detail;
    if (!fd.hasVarArgs || !cc.arch.is64Bit) return;
    final argCount = node.argCount;

    switch (fd.callConv.id) {
      case CallConvId.x64SystemV:
        // AL register contains the number of arguments passed in XMM
        // register(s).
        var n = 0;
        for (var argIndex = 0; argIndex < argCount; argIndex++) {
          for (var v = 0; v < Globals.kMaxValuePack; v++) {
            final arg = fd.args[argIndex][v];
            if (!arg.isInitialized) break;
            if (arg.isReg &&
                RegUtils.groupOf(arg.fullRegType) == RegGroup.vec) {
              n++;
            }
          }
        }
        insert(n == 0
            ? InstNode(X86InstId.kXor, [X86Gp.eax, X86Gp.eax])
            : InstNode(X86InstId.kMov, [X86Gp.eax, Imm(n)]));

      case CallConvId.x64Windows:
        // Each double-precision argument passed in XMM must be also passed
        // in GP.
        for (var argIndex = 0; argIndex < argCount; argIndex++) {
          for (var v = 0; v < Globals.kMaxValuePack; v++) {
            final arg = fd.args[argIndex][v];
            if (!arg.isInitialized) break;
            if (arg.isReg &&
                RegUtils.groupOf(arg.fullRegType) == RegGroup.vec) {
              final dst =
                  X86Gp.r64(fd.callConv.passedOrder(RegGroup.gp)[argIndex]);
              final src = X86Xmm(arg.regId);
              insert(InstNode(_hasAvx(_cc) ? X86InstId.kVmovq : X86InstId.kMovq,
                  [dst, src]));
            }
          }
        }

      default:
        throw AsmJitException(
            AsmJitError.invalidState, 'invalid function call');
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

  /// Whether the function being allocated uses VEX encoded moves for its
  /// vector registers (`FuncFrame::is_avx_enabled()`, as upstream
  /// `EmitHelper::reset(..., avx_enabled)`): needed for YMM/ZMM registers.
  bool _avxEnabled = false;

  bool _hasAvx(BaseCompiler? cc) => _avxEnabled;

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
  InstNode loadStackArg(BaseReg dst, int stackOffset, TypeId typeId) {
    final size = typeId.sizeInBytes;
    final mem = X86Mem.baseDisp(X86Gp.r64(X86RegId.rbp.index), 16 + stackOffset,
        size: size);
    if (dst.group == RegGroup.vec) {
      final id = switch (size) {
        4 => _hasAvx(_cc) ? X86InstId.kVmovss : X86InstId.kMovss,
        8 => _hasAvx(_cc) ? X86InstId.kVmovsd : X86InstId.kMovsd,
        _ => _hasAvx(_cc) ? X86InstId.kVmovups : X86InstId.kMovups,
      };
      return InstNode(id, [dst, mem]);
    }
    final gp = dst as X86Gp;
    if (size < 4) {
      return InstNode(typeId.isSigned ? X86InstId.kMovsx : X86InstId.kMovzx,
          [gp.as32, mem]);
    }
    return InstNode(X86InstId.kMov, [size == 8 ? gp.as64 : gp.as32, mem]);
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
    // A dynamically aligned frame (`and rsp, -alignment` in the prolog)
    // addresses the local area from the aligned stack pointer, as upstream
    // addresses locals from SP: [rsp + offset].
    if (localStackAlignment > 16) {
      return cc.newStackSlot(X86RegId.rsp.index, callStackSize + offset, size);
    }
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
    for (final n in ctx.funcNodes) {
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

    // Layout below RBP: locals/spills -> aligned vec saves -> gp saves. A
    // dynamically aligned frame has the locals at the bottom ([rsp + x])
    // and only the saves below RBP.
    final dynamicAlignment = ctx.stackAlignment > 16;
    int currentOffset = dynamicAlignment ? 0 : _alignUp(ctx.spillSize, 16);
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

    // The outgoing argument area of the calls is at the bottom ([rsp + x]).
    final totalStackSize = dynamicAlignment
        ? _alignUp(
            callStackSize + ctx.spillSize + currentOffset, ctx.stackAlignment)
        : _alignUp(callStackSize + currentOffset, 16);
    if (func.frame.localStackSize < totalStackSize) {
      func.frame.setLocalStackSize(totalStackSize);
    }

    final rbp = X86Gp.r64(X86RegId.rbp.index);
    final rsp = X86Gp.r64(X86RegId.rsp.index);

    // Prolog: push rbp; mov rbp, rsp; sub rsp, N; save registers.
    final prolog = <InstNode>[
      InstNode(X86InstId.kPush, [rbp]),
      InstNode(X86InstId.kMov, [rbp, rsp]),
      if (dynamicAlignment)
        InstNode(X86InstId.kAnd, [rsp, Imm(-ctx.stackAlignment)]),
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
      // As upstream `emit_epilog()`: VZEROUPPER after the registers are
      // restored, with AVX cleanup or with automatic AVX cleanup when
      // vector registers are dirty.
      if (func.frame.hasAvxCleanup ||
          (func.frame.hasAttribute(FuncAttributes.kX86_AVXAutoCleanup) &&
              ctx.clobbered[RegGroup.vec] != 0)) {
        ctx.insertBefore(ret, InstNode(X86InstId.kVzeroupper, []));
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
