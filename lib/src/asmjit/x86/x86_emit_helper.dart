/// x86 emit helper
///
/// Provides concrete `BaseEmitHelper` implementation for the x86 backend.

import '../core/emit_helper.dart';
import '../core/error.dart';
import '../core/operand.dart';
import '../core/reg_type.dart';
import '../core/reg_utils.dart';
import '../core/type.dart';
import 'x86.dart';
import 'x86_assembler.dart';
import 'x86_operands.dart';
import 'x86_simd.dart';

class X86EmitHelper extends BaseEmitHelper {
  late final X86Assembler _asm;

  X86EmitHelper(X86Assembler asm) : super(asm) {
    _asm = asm;
  }

  X86Gp _asGp(RegOperand reg) {
    switch (reg.regType) {
      case RegType.gp64:
        return X86Gp.r64(reg.regId);
      case RegType.gp32:
        return X86Gp.r32(reg.regId);
      case RegType.gp16:
        return X86Gp.r16(reg.regId);
      case RegType.gp8Lo:
        return X86Gp.r8(reg.regId);
      case RegType.gp8Hi:
        return X86Gp.r8h(reg.regId);
      default:
        return _asm.is64Bit ? X86Gp.r64(reg.regId) : X86Gp.r32(reg.regId);
    }
  }

  X86Mem _memFrom(MemOperand mem) {
    final baseReg = mem.baseReg;
    if (baseReg == null) {
      throw StateError('MemOperand requires a base register');
    }
    final base = _asGp(baseReg);
    return X86Mem.baseDisp(base, mem.displacement, size: mem.memSize);
  }

  BaseReg _asReg(RegOperand reg) {
    switch (reg.regType) {
      case RegType.vec128:
        return X86Xmm(reg.regId);
      case RegType.vec256:
        return X86Ymm(reg.regId);
      case RegType.vec512:
        return X86Zmm(reg.regId);
      case RegType.mask:
        return X86KReg(reg.regId);
      default:
        return _asGp(reg);
    }
  }

  @override
  AsmJitError emitRegMove(EmitOperand dst, EmitOperand src, TypeId typeId) {
    if (dst is MemOperand && src is RegOperand) {
      return _moveRegToMem(dst, src);
    }
    return AsmJitError.invalidState;
  }

  @override
  AsmJitError emitRegSwap(RegOperand a, RegOperand b) {
    final regA = _asGp(a);
    final regB = _asGp(b);
    _asm.xchg(regA, regB);
    return AsmJitError.ok;
  }

  @override
  AsmJitError emitArgMove(
      RegOperand dst, TypeId dstTypeId, EmitOperand src, TypeId srcTypeId) {
    final dstReg = _asReg(dst);
    switch (RegUtils.groupOf(dst.regType)) {
      case RegGroup.gp:
        return dstReg is X86Gp ? _moveToGp(dstReg, src) : AsmJitError.invalidState;
      case RegGroup.vec:
        return _moveToVec(dstReg, src);
      case RegGroup.mask:
        return _moveToMask(dstReg, src);
      default:
        return AsmJitError.invalidState;
    }
  }

  AsmJitError _moveRegToMem(MemOperand dst, RegOperand src) {
    final mem = _memFrom(dst);
    final srcReg = _asReg(src);

    if (srcReg is X86Gp) {
      _asm.movMR(mem, srcReg);
      return AsmJitError.ok;
    }

    if (srcReg is X86Xmm) {
      _asm.movupsMX(mem, srcReg);
      return AsmJitError.ok;
    }

    if (srcReg is X86Ymm) {
      _asm.vmovupsMY(mem, srcReg);
      return AsmJitError.ok;
    }

    if (srcReg is X86Zmm) {
      _asm.vmovupsMemZmm(mem, srcReg);
      return AsmJitError.ok;
    }

    return AsmJitError.invalidState;
  }

  AsmJitError _moveToGp(X86Gp dst, EmitOperand src) {
    if (src is RegOperand) {
      final reg = _asReg(src);
      if (reg is X86Gp) {
        _asm.movRR(dst, reg);
        return AsmJitError.ok;
      }
    }

    if (src is MemOperand) {
      final mem = _memFrom(src);
      _asm.movRM(dst, mem);
      return AsmJitError.ok;
    }

    return AsmJitError.invalidState;
  }

  AsmJitError _moveToVec(BaseReg dstReg, EmitOperand src) {
    if (dstReg is X86Xmm) {
      if (src is RegOperand) {
        final reg = _asReg(src);
        if (reg is X86Xmm) {
          _asm.movupsXX(dstReg, reg);
          return AsmJitError.ok;
        }
      } else if (src is MemOperand) {
        final mem = _memFrom(src);
        _asm.movupsXM(dstReg, mem);
        return AsmJitError.ok;
      }
    } else if (dstReg is X86Ymm) {
      if (src is RegOperand) {
        final reg = _asReg(src);
        if (reg is X86Ymm) {
          _asm.vmovupsYY(dstReg, reg);
          return AsmJitError.ok;
        }
      } else if (src is MemOperand) {
        final mem = _memFrom(src);
        _asm.vmovupsYM(dstReg, mem);
        return AsmJitError.ok;
      }
    } else if (dstReg is X86Zmm) {
      if (src is RegOperand) {
        final reg = _asReg(src);
        if (reg is X86Zmm) {
          _asm.vmovupsZmm(dstReg, reg);
          return AsmJitError.ok;
        }
      } else if (src is MemOperand) {
        final mem = _memFrom(src);
        _asm.vmovupsZmmMem(dstReg, mem);
        return AsmJitError.ok;
      }
    }
    return AsmJitError.invalidState;
  }

  AsmJitError _moveToMask(BaseReg dstReg, EmitOperand src) {
    if (dstReg is X86KReg && src is RegOperand) {
      final reg = _asReg(src);
      if (reg is X86Gp) {
        _asm.kmovqKR(dstReg, reg);
        return AsmJitError.ok;
      }
    }
    return AsmJitError.invalidState;
  }
}
