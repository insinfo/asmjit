part of 'unicompiler.dart';

/// X86-specific functionality for UniCompiler.
mixin UniCompilerX86 on UniCompilerBase {
  /// Updates X86 extension masks based on CpuFeatures.
  void _updateX86Features() {
    if (!isX86Family) return;

    // Reset masks
    _gpExtMask = 0;
    _sseExtMask = 0;
    _avxExtMask = 0;

    // Map CpuFeatures to extension masks
    final features = _features;

    // GP Extensions
    if (features.adx) _gpExtMask |= (1 << GPExt.kADX.index);
    if (features.bmi1) _gpExtMask |= (1 << GPExt.kBMI.index);
    if (features.bmi2) _gpExtMask |= (1 << GPExt.kBMI2.index);
    if (features.lzcnt) _gpExtMask |= (1 << GPExt.kLZCNT.index);
    if (features.popcnt) _gpExtMask |= (1 << GPExt.kPOPCNT.index);

    // SSE Extensions (SSE2 is baseline for x64)
    _sseExtMask |= (1 << SSEExt.kSSE2.index); // Always on for x64
    if (features.sse3) _sseExtMask |= (1 << SSEExt.kSSE3.index);
    if (features.ssse3) _sseExtMask |= (1 << SSEExt.kSSSE3.index);
    if (features.sse41) _sseExtMask |= (1 << SSEExt.kSSE4_1.index);
    if (features.sse42) _sseExtMask |= (1 << SSEExt.kSSE4_2.index);
    if (features.pclmulqdq) _sseExtMask |= (1 << SSEExt.kPCLMULQDQ.index);

    // AVX Extensions
    if (features.avx) _avxExtMask |= (1 << AVXExt.kAVX.index);
    if (features.avx2) _avxExtMask |= (1 << AVXExt.kAVX2.index);
    if (features.f16c) _avxExtMask |= (1 << AVXExt.kF16C.index);
    if (features.fma) _avxExtMask |= (1 << AVXExt.kFMA.index);
    if (features.vpclmulqdq) _avxExtMask |= (1 << AVXExt.kVPCLMULQDQ.index);

    // AVX-512
    if (features.avx512f &&
        features.avx512bw &&
        features.avx512dq &&
        features.avx512vl) {
      _avxExtMask |= (1 << AVXExt.kAVX512.index);
    }

    // Set FMA behavior
    if (features.fma) {
      _fMAddOpBehavior = FMAddOpBehavior.fmaStoreToAny;
    }

    // Update vec reg count
    if (hasAvx512) {
      _vecRegCount = 32;
    }
  }

  /// Gets the maximum vector width supported by CPU features.
  VecWidth maxVecWidthFromCpuFeatures() {
    if (hasAvx512) return VecWidth.k512;
    if (hasAvx2 || hasAvx) return VecWidth.k256;
    return VecWidth.k128;
  }

  // ============================================================================
  // [X86 Intrinsic Wrappers]
  // ============================================================================

  void _vLoadAX86(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqa, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
    }
  }

  void _vLoadUX86(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqu, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqu, [dst, src]));
    }
  }

  void _vStoreAX86(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqa, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
    }
  }

  void _vStoreUX86(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqu, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqu, [dst, src]));
    }
  }

  void _vMovX86(BaseReg dst, BaseReg src) {
    if (dst.id == src.id) return;
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqa, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
    }
  }

  void _vZeroX86(BaseReg dst) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpxor, [dst, dst, dst]));
    } else {
      cc.addNode(InstNode(X86InstId.kPxor, [dst, dst]));
    }
  }

  void _vXorX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpxor, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPxor, [dst, b]));
    }
  }

  void _vOrX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpor, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPor, [dst, b]));
    }
  }

  void _vAndX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpand, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPand, [dst, b]));
    }
  }

  void _vAndNotX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpandn, [dst, b, a]));
    } else {
      if (b is BaseReg) {
        if (dst.id != b.id) _vMovX86(dst, b);
      } else {
        _vLoadUX86(dst, b as X86Mem);
      }
      cc.addNode(InstNode(X86InstId.kPandn, [dst, a]));
    }
  }

  void _vAddI8X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpaddb, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPaddb, [dst, b]));
    }
  }

  void _vAddI16X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpaddw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPaddw, [dst, b]));
    }
  }

  void _vAddI32X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpaddd, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPaddd, [dst, b]));
    }
  }

  void _vSubI8X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsubb, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPsubb, [dst, b]));
    }
  }

  void _vSubI16X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsubw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPsubw, [dst, b]));
    }
  }

  void _vSubI32X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsubd, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPsubd, [dst, b]));
    }
  }

  void _vMulLoI16X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpmullw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPmullw, [dst, b]));
    }
  }

  void _vMulHiI16X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpmulhw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPmulhw, [dst, b]));
    }
  }

  void _vMulHiU16X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpmulhuw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPmulhuw, [dst, b]));
    }
  }

  void _vShufBX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpshufb, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPshufb, [dst, b]));
    }
  }

  void _vPackUSWBX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpackuswb, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPackuswb, [dst, b]));
    }
  }

  void _vPackSSDWX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpackssdw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPackssdw, [dst, b]));
    }
  }

  void _vUnpackLoI8X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpunpcklbw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPunpcklbw, [dst, b]));
    }
  }

  void _vUnpackHiI8X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpunpckhbw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPunpckhbw, [dst, b]));
    }
  }

  void _vCmpEqI8X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpcmpeqb, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPcmpeqb, [dst, b]));
    }
  }

  void _vCmpEqI16X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpcmpeqw, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPcmpeqw, [dst, b]));
    }
  }

  void _vCmpGtI8X86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpcmpgtb, [dst, a, b]));
    } else {
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPcmpgtb, [dst, b]));
    }
  }

  void _vSllI16X86(BaseReg dst, BaseReg src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsllw, [dst, src, Imm(imm)]));
    } else {
      if (dst.id != src.id) _vMovX86(dst, src);
      cc.addNode(InstNode(X86InstId.kPsllw, [dst, Imm(imm)]));
    }
  }

  void _vSrlI16X86(BaseReg dst, BaseReg src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsrlw, [dst, src, Imm(imm)]));
    } else {
      if (dst.id != src.id) _vMovX86(dst, src);
      cc.addNode(InstNode(X86InstId.kPsrlw, [dst, Imm(imm)]));
    }
  }

  void _vSraI16X86(BaseReg dst, BaseReg src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsraw, [dst, src, Imm(imm)]));
    } else {
      if (dst.id != src.id) _vMovX86(dst, src);
      cc.addNode(InstNode(X86InstId.kPsraw, [dst, Imm(imm)]));
    }
  }

  void _vLoad64X86(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovq, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovq, [dst, src]));
    }
  }

  void _vStore64X86(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovq, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovq, [dst, src]));
    }
  }

  void _vLoad32X86(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovd, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovd, [dst, src]));
    }
  }

  void _vStore32X86(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovd, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovd, [dst, src]));
    }
  }

  void _vStoreNTX86(X86Mem dst, BaseReg src) {
    cc.addNode(InstNode(hasAvx ? X86InstId.kVmovntdq : X86InstId.kMovntdq,
        [dst.withSize(16), src]));
  }

  void _vBlendX86(BaseReg dst, BaseReg src1, Operand src2, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpblendw, [dst, src1, src2, Imm(imm)]));
    } else if (hasSse41) {
      if (dst.id != src1.id) _vMovX86(dst, src1);
      cc.addNode(InstNode(X86InstId.kPblendw, [dst, src2, Imm(imm)]));
    }
  }

  void _vBlendVX86(BaseReg dst, BaseReg src1, Operand src2, BaseReg mask) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpblendvb, [dst, src1, src2, mask]));
    } else if (hasSse41) {
      if (dst.id != src1.id) _vMovX86(dst, src1);
      cc.addNode(InstNode(X86InstId.kPblendvb, [dst, src2]));
    }
  }

  void _sMovX86(BaseReg dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovaps, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovaps, [dst, src]));
    }
  }

  void _sExtractU16X86(Operand dst, BaseReg src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpextrw, [dst, src, Imm(imm)]));
    } else {
      cc.addNode(InstNode(X86InstId.kPextrw, [dst, src, Imm(imm)]));
    }
  }

  void _sInsertU16X86(BaseReg dst, BaseReg src, Operand val, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpinsrw, [dst, src, val, Imm(imm)]));
    } else {
      if (dst.id != src.id) _vMovX86(dst, src);
      cc.addNode(InstNode(X86InstId.kPinsrw, [dst, val, Imm(imm)]));
    }
  }

  // ============================================================================
  // [X86 Internal Dispatchers]
  // ============================================================================

  void _emitVMX86(
      UniOpVM op, BaseReg dst, X86Mem src, Alignment alignment, int idx) {
    final info = _getUniOpVMInfo(op);
    if (info == null) {
      throw UnimplementedError('UniOpVM $op not implemented for X86');
    }

    if (hasAvx) {
      switch (op) {
        case UniOpVM.load8:
          _vZeroX86(dst);
          cc.addNode(InstNode(
              X86InstId.kVpinsrb, [dst, dst, src.withSize(1), Imm(0)]));
          return;
        case UniOpVM.load16U16:
          _vZeroX86(dst);
          cc.addNode(InstNode(
              X86InstId.kVpinsrw, [dst, dst, src.withSize(2), Imm(0)]));
          return;
        case UniOpVM.load32U32:
        case UniOpVM.load32F32:
        case UniOpVM.load64U32:
        case UniOpVM.load64U64:
        case UniOpVM.load64F32:
        case UniOpVM.load64F64:
          cc.addNode(
              InstNode(info.avxInstId, [dst, src.withSize(info.memSize)]));
          return;
        case UniOpVM.load128U32:
        case UniOpVM.load128U64:
        case UniOpVM.load128F32:
        case UniOpVM.load128F64:
        case UniOpVM.load256U32:
        case UniOpVM.load256U64:
        case UniOpVM.load256F32:
        case UniOpVM.load256F64:
          final mem = src.withSize(info.memSize);
          bool aligned = alignment.size != 0 && alignment.size >= info.memSize;
          int instId = (op.name.contains('F'))
              ? (aligned ? X86InstId.kVmovaps : X86InstId.kVmovups)
              : (aligned ? X86InstId.kVmovdqa : X86InstId.kVmovdqu);
          cc.addNode(InstNode(instId, [dst, mem]));
          return;
        default:
          if (info.avxInstId != 0) {
            cc.addNode(
                InstNode(info.avxInstId, [dst, src.withSize(info.memSize)]));
            return;
          }
      }
    } else {
      switch (op) {
        case UniOpVM.load8:
          _vZeroX86(dst);
          cc.addNode(
              InstNode(X86InstId.kPinsrb, [dst, src.withSize(1), Imm(0)]));
          return;
        case UniOpVM.load16U16:
          _vZeroX86(dst);
          cc.addNode(
              InstNode(X86InstId.kPinsrw, [dst, src.withSize(2), Imm(0)]));
          return;
        case UniOpVM.load32U32:
        case UniOpVM.load32F32:
        case UniOpVM.load64U32:
        case UniOpVM.load64U64:
        case UniOpVM.load64F32:
        case UniOpVM.load64F64:
          cc.addNode(
              InstNode(info.sseInstId, [dst, src.withSize(info.memSize)]));
          return;
        default:
          if (info.sseInstId != 0) {
            cc.addNode(
                InstNode(info.sseInstId, [dst, src.withSize(info.memSize)]));
            return;
          }
      }
    }
  }

  void _emitMVX86(
      UniOpMV op, X86Mem dst, BaseReg src, Alignment alignment, int idx) {
    final info = _getUniOpMVInfo(op);
    if (info == null) {
      throw UnimplementedError('UniOpMV $op not implemented for X86');
    }

    if (hasAvx) {
      switch (op) {
        case UniOpMV.store32U32:
        case UniOpMV.store32F32:
        case UniOpMV.store64U32:
        case UniOpMV.store64U64:
        case UniOpMV.store64F32:
        case UniOpMV.store64F64:
          cc.addNode(
              InstNode(info.avxInstId, [dst.withSize(info.memSize), src]));
          return;
        case UniOpMV.store128U32:
        case UniOpMV.store128U64:
        case UniOpMV.store128F32:
        case UniOpMV.store128F64:
        case UniOpMV.store256U32:
        case UniOpMV.store256U64:
        case UniOpMV.store256F32:
        case UniOpMV.store256F64:
          final mem = dst.withSize(info.memSize);
          bool aligned = alignment.size != 0 && alignment.size >= info.memSize;
          int instId = (op.name.contains('F'))
              ? (aligned ? X86InstId.kVmovaps : X86InstId.kVmovups)
              : (aligned ? X86InstId.kVmovdqa : X86InstId.kVmovdqu);
          cc.addNode(InstNode(instId, [mem, src]));
          return;
        default:
          break;
      }
    } else {
      switch (op) {
        case UniOpMV.store32U32:
        case UniOpMV.store32F32:
        case UniOpMV.store64U32:
        case UniOpMV.store64U64:
        case UniOpMV.store64F32:
        case UniOpMV.store64F64:
          cc.addNode(
              InstNode(info.sseInstId, [dst.withSize(info.memSize), src]));
          return;
        default:
          break;
      }
    }
  }

  void _emit2vX86(UniOpVV op, Operand dst, Operand src) {
    if (dst is! BaseReg || src is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    switch (op) {
      case UniOpVV.mov:
        _vMovX86(dst, src);
        break;
      case UniOpVV.movU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmovq, [dst, src]));
        } else {
          cc.addNode(InstNode(X86InstId.kMovq, [dst, src]));
        }
        break;
      case UniOpVV.broadcastU32:
        if (hasAvx2) {
          cc.addNode(InstNode(X86InstId.kVpbroadcastd, [dst, src]));
        } else if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVbroadcastss, [dst, src]));
        } else {
          cc.addNode(InstNode(X86InstId.kPshufd, [dst, src, Imm(0)]));
        }
        break;
      case UniOpVV.broadcastU64:
        if (hasAvx2) {
          cc.addNode(InstNode(X86InstId.kVpbroadcastq, [dst, src]));
        } else if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVbroadcastsd, [dst, src]));
        } else {
          cc.addNode(InstNode(X86InstId.kPshufd, [dst, src, Imm(0x44)]));
        }
        break;
      case UniOpVV.absI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsb, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPabsb, [dst, dst]));
        }
        break;
      case UniOpVV.absI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsw, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPabsw, [dst, dst]));
        }
        break;
      case UniOpVV.absI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsd, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPabsd, [dst, dst]));
        }
        break;
      case UniOpVV.notU32:
      case UniOpVV.notU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpcmpeqd, [dst, dst, dst]));
          cc.addNode(InstNode(X86InstId.kVpxor, [dst, dst, src]));
        } else {
          cc.addNode(InstNode(X86InstId.kPcmpeqd, [dst, dst]));
          cc.addNode(InstNode(X86InstId.kPxor, [dst, src]));
        }
        break;
      case UniOpVV.cvtU8LoToU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmovzxbw, [dst, src]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kPmovzxbw, [dst, src]));
        } else {
          _vZeroX86(dst);
          cc.addNode(InstNode(X86InstId.kPunpcklbw, [dst, src]));
        }
        break;
      case UniOpVV.cvtI8LoToI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmovsxbw, [dst, src]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kPmovsxbw, [dst, src]));
        }
        break;
      case UniOpVV.cvtU16LoToU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmovzxwd, [dst, src]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kPmovzxwd, [dst, src]));
        } else {
          _vZeroX86(dst);
          cc.addNode(InstNode(X86InstId.kPunpcklwd, [dst, src]));
        }
        break;
      case UniOpVV.cvtI16LoToI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmovsxwd, [dst, src]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kPmovsxwd, [dst, src]));
        }
        break;
      case UniOpVV.cvtU32LoToU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmovzxdq, [dst, src]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kPmovzxdq, [dst, src]));
        } else {
          _vZeroX86(dst);
          cc.addNode(InstNode(X86InstId.kPunpckldq, [dst, src]));
        }
        break;
      case UniOpVV.cvtI32LoToI64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmovsxdq, [dst, src]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kPmovsxdq, [dst, src]));
        }
        break;
      case UniOpVV.sqrtF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsqrtps, [dst, src]));
        } else {
          if (dst != src) cc.addNode(InstNode(X86InstId.kMovaps, [dst, src]));
          cc.addNode(InstNode(X86InstId.kSqrtps, [dst, dst]));
        }
        break;
      case UniOpVV.sqrtF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsqrtpd, [dst, src]));
        } else {
          if (dst != src) cc.addNode(InstNode(X86InstId.kMovapd, [dst, src]));
          cc.addNode(InstNode(X86InstId.kSqrtpd, [dst, dst]));
        }
        break;
      case UniOpVV.rcpF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVrcpps, [dst, src]));
        } else {
          if (dst != src) cc.addNode(InstNode(X86InstId.kMovaps, [dst, src]));
          cc.addNode(InstNode(X86InstId.kRcpps, [dst, dst]));
        }
        break;
      case UniOpVV.cvtI32ToF32:
        cc.addNode(InstNode(
            hasAvx ? X86InstId.kVcvtdq2ps : X86InstId.kCvtdq2ps, [dst, src]));
        break;
      case UniOpVV.cvtF32LoToF64:
        cc.addNode(InstNode(
            hasAvx ? X86InstId.kVcvtps2pd : X86InstId.kCvtps2pd, [dst, src]));
        break;
      case UniOpVV.cvtTruncF32ToI32:
        cc.addNode(InstNode(
            hasAvx ? X86InstId.kVcvttps2dq : X86InstId.kCvttps2dq, [dst, src]));
        break;
      case UniOpVV.truncF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundps, [dst, src, Imm(3)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(3)]));
        }
        break;
      case UniOpVV.truncF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundpd, [dst, src, Imm(3)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(3)]));
        }
        break;
      case UniOpVV.floorF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundps, [dst, src, Imm(1)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(1)]));
        }
        break;
      case UniOpVV.floorF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundpd, [dst, src, Imm(1)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(1)]));
        }
        break;
      case UniOpVV.ceilF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundps, [dst, src, Imm(2)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(2)]));
        }
        break;
      case UniOpVV.ceilF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundpd, [dst, src, Imm(2)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(2)]));
        }
        break;
      default:
        throw UnimplementedError('_emit2vX86: $op not implemented');
    }
  }

  void _emit3vX86(UniOpVVV op, Operand dst, Operand src1, Operand src2) {
    if (dst is! BaseReg || src1 is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    switch (op) {
      case UniOpVVV.andU32:
      case UniOpVVV.andU64:
        _vAndX86(dst, src1, src2);
        break;
      case UniOpVVV.orU32:
      case UniOpVVV.orU64:
        _vOrX86(dst, src1, src2);
        break;
      case UniOpVVV.xorU32:
      case UniOpVVV.xorU64:
        _vXorX86(dst, src1, src2);
        break;
      case UniOpVVV.andnU32:
      case UniOpVVV.andnU64:
        _vAndNotX86(dst, src1, src2);
        break;
      case UniOpVVV.addU8:
        _vAddI8X86(dst, src1, src2);
        break;
      case UniOpVVV.addU16:
        _vAddI16X86(dst, src1, src2);
        break;
      case UniOpVVV.addU32:
        _vAddI32X86(dst, src1, src2);
        break;
      case UniOpVVV.addU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddq, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPaddq, [dst, src2]));
        }
        break;
      case UniOpVVV.subU8:
        _vSubI8X86(dst, src1, src2);
        break;
      case UniOpVVV.subU16:
        _vSubI16X86(dst, src1, src2);
        break;
      case UniOpVVV.subU32:
        _vSubI32X86(dst, src1, src2);
        break;
      case UniOpVVV.subU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubq, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPsubq, [dst, src2]));
        }
        break;
      case UniOpVVV.addsI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddsb, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPaddsb, [dst, src2]));
        }
        break;
      case UniOpVVV.addsU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddusb, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPaddusb, [dst, src2]));
        }
        break;
      case UniOpVVV.addsI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddsw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPaddsw, [dst, src2]));
        }
        break;
      case UniOpVVV.addsU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddusw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPaddusw, [dst, src2]));
        }
        break;
      case UniOpVVV.subsI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubsb, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPsubsb, [dst, src2]));
        }
        break;
      case UniOpVVV.subsU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubusb, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPsubusb, [dst, src2]));
        }
        break;
      case UniOpVVV.subsI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubsw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPsubsw, [dst, src2]));
        }
        break;
      case UniOpVVV.subsU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubusw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPsubusw, [dst, src2]));
        }
        break;
      case UniOpVVV.bicU32:
      case UniOpVVV.bicU64:
        _vAndNotX86(dst, src1, src2);
        break;
      case UniOpVVV.avgrU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpavgb, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPavgb, [dst, src2]));
        }
        break;
      case UniOpVVV.avgrU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpavgw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPavgw, [dst, src2]));
        }
        break;
      case UniOpVVV.mulU16:
        _vMulLoI16X86(dst, src1, src2);
        break;
      case UniOpVVV.mulhI16:
        _vMulHiI16X86(dst, src1, src2);
        break;
      case UniOpVVV.mulhU16:
        _vMulHiU16X86(dst, src1, src2);
        break;
      case UniOpVVV.mulU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmulld, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmulld, [dst, src2]));
        }
        break;
      case UniOpVVV.cmpEqU8:
        _vCmpEqI8X86(dst, src1, src2);
        break;
      case UniOpVVV.cmpEqU16:
        _vCmpEqI16X86(dst, src1, src2);
        break;
      case UniOpVVV.cmpEqU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpcmpeqd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPcmpeqd, [dst, src2]));
        }
        break;
      case UniOpVVV.cmpGtI8:
        _vCmpGtI8X86(dst, src1, src2);
        break;
      case UniOpVVV.cmpGtI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpcmpgtw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPcmpgtw, [dst, src2]));
        }
        break;
      case UniOpVVV.cmpGtI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpcmpgtd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPcmpgtd, [dst, src2]));
        }
        break;
      case UniOpVVV.minI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminsb, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPminsb, [dst, src2]));
        }
        break;
      case UniOpVVV.minU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminub, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPminub, [dst, src2]));
        }
        break;
      case UniOpVVV.minI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminsw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPminsw, [dst, src2]));
        }
        break;
      case UniOpVVV.minU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminuw, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPminuw, [dst, src2]));
        }
        break;
      case UniOpVVV.maxI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxsb, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmaxsb, [dst, src2]));
        }
        break;
      case UniOpVVV.maxU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxub, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmaxub, [dst, src2]));
        }
        break;
      case UniOpVVV.maxI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxsw, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmaxsw, [dst, src2]));
        }
        break;
      case UniOpVVV.maxU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxuw, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmaxuw, [dst, src2]));
        }
        break;
      case UniOpVVV.packsI16I8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpacksswb, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPacksswb, [dst, src2]));
        }
        break;
      case UniOpVVV.packsI16U8:
        _vPackUSWBX86(dst, src1, src2);
        break;
      case UniOpVVV.packsI32I16:
        _vPackSSDWX86(dst, src1, src2);
        break;
      case UniOpVVV.interleaveLoU8:
        _vUnpackLoI8X86(dst, src1, src2);
        break;
      case UniOpVVV.interleaveHiU8:
        _vUnpackHiI8X86(dst, src1, src2);
        break;
      case UniOpVVV.interleaveLoU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpcklwd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPunpcklwd, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveHiU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckhwd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPunpckhwd, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveLoU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckldq, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPunpckldq, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveHiU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckhdq, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPunpckhdq, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveLoU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpcklqdq, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPunpcklqdq, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveHiU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckhqdq, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPunpckhqdq, [dst, src2]));
        }
        break;
      case UniOpVVV.swizzlevU8:
        _vShufBX86(dst, src1, src2);
        break;
      case UniOpVVV.addF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVaddps, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kAddps, [dst, src2]));
        }
        break;
      case UniOpVVV.addF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVaddpd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kAddpd, [dst, src2]));
        }
        break;
      case UniOpVVV.subF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsubps, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kSubps, [dst, src2]));
        }
        break;
      case UniOpVVV.subF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsubpd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kSubpd, [dst, src2]));
        }
        break;
      case UniOpVVV.mulF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmulps, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMulps, [dst, src2]));
        }
        break;
      case UniOpVVV.mulF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmulpd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMulpd, [dst, src2]));
        }
        break;
      case UniOpVVV.divF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVdivps, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kDivps, [dst, src2]));
        }
        break;
      case UniOpVVV.divF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVdivpd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kDivpd, [dst, src2]));
        }
        break;
      case UniOpVVV.minF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVminps, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMinps, [dst, src2]));
        }
        break;
      case UniOpVVV.minF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVminpd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMinpd, [dst, src2]));
        }
        break;
      case UniOpVVV.maxF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmaxps, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMaxps, [dst, src2]));
        }
        break;
      case UniOpVVV.maxF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmaxpd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMaxpd, [dst, src2]));
        }
        break;
      default:
        throw UnimplementedError('_emit3vX86: $op not implemented');
    }
  }

  void _emit2viX86(UniOpVVI op, Operand dst, Operand src, int imm) {
    if (dst is! BaseReg || src is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    switch (op) {
      case UniOpVVI.sllU16:
        _vSllI16X86(dst, src, imm);
        break;
      case UniOpVVI.sllU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpslld, [dst, src, Imm(imm)]));
        } else {
          if (dst.id != src.id) {
            _vMovX86(dst, src);
          }
          cc.addNode(InstNode(X86InstId.kPslld, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.sllU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsllq, [dst, src, Imm(imm)]));
        } else {
          if (dst.id != src.id) {
            _vMovX86(dst, src);
          }
          cc.addNode(InstNode(X86InstId.kPsllq, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.srlU16:
        _vSrlI16X86(dst, src, imm);
        break;
      case UniOpVVI.srlU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsrld, [dst, src, Imm(imm)]));
        } else {
          if (dst.id != src.id) {
            _vMovX86(dst, src);
          }
          cc.addNode(InstNode(X86InstId.kPsrld, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.srlU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsrlq, [dst, src, Imm(imm)]));
        } else {
          if (dst.id != src.id) {
            _vMovX86(dst, src);
          }
          cc.addNode(InstNode(X86InstId.kPsrlq, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.sraI16:
        _vSraI16X86(dst, src, imm);
        break;
      case UniOpVVI.sraI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsrad, [dst, src, Imm(imm)]));
        } else {
          if (dst.id != src.id) {
            _vMovX86(dst, src);
          }
          cc.addNode(InstNode(X86InstId.kPsrad, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.shufI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpshufb, [dst, src, Imm(imm)]));
        } else if (hasSsse3) {
          if (dst != src) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPshufb, [dst, Imm(imm)]));
        }
        break;
      default:
        throw UnimplementedError('_emit2viX86: $op not implemented');
    }
  }

  void _emit3viX86(
      UniOpVVVI op, Operand dst, Operand src1, Operand src2, int imm) {
    if (dst is! BaseReg || src1 is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    switch (op) {
      case UniOpVVVI.alignrU128:
        if (hasAvx) {
          cc.addNode(
              InstNode(X86InstId.kVpalignr, [dst, src1, src2, Imm(imm)]));
        } else if (hasSsse3) {
          if (dst.id != src1.id) {
            _vMovX86(dst, src1);
          }
          cc.addNode(InstNode(X86InstId.kPalignr, [dst, src2, Imm(imm)]));
        }
        break;
      default:
        throw UnimplementedError('_emit3viX86: $op not implemented');
    }
  }

  void _emit4vX86(
      UniOpVVVV op, Operand dst, Operand src1, Operand src2, Operand src3) {
    if (dst is! BaseReg || src1 is! BaseReg || src3 is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    switch (op) {
      case UniOpVVVV.blendvU8:
        _vBlendVX86(dst, src1, src2, src3);
        break;
      default:
        throw UnimplementedError('_emit4vX86: $op not implemented');
    }
  }

  void _emit5vX86(UniOpVVVVV op, Operand dst, Operand src1, Operand src2,
      Operand src3, Operand src4) {
    throw UnimplementedError('_emit5vX86: $op not implemented');
  }

  void _emit9vX86(
      UniOpVVVVVVVVV op,
      Operand dst,
      Operand src1,
      Operand src2,
      Operand src3,
      Operand src4,
      Operand src5,
      Operand src6,
      Operand src7,
      Operand src8) {
    throw UnimplementedError('_emit9vX86: $op not implemented');
  }

  UniOpVMInfo? _getUniOpVMInfo(UniOpVM op) {
    switch (op) {
      case UniOpVM.load32U32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovd,
            avxInstId: X86InstId.kVmovd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 4,
            memSizeShift: 0);
      case UniOpVM.load32F32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovss,
            avxInstId: X86InstId.kVmovss,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 4,
            memSizeShift: 0);
      case UniOpVM.load64U32:
      case UniOpVM.load64U64:
      case UniOpVM.load64F32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovq,
            avxInstId: X86InstId.kVmovq,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 0);
      case UniOpVM.load64F64:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovsd,
            avxInstId: X86InstId.kVmovsd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 0);
      case UniOpVM.load128U32:
      case UniOpVM.load128U64:
      case UniOpVM.load128F32:
      case UniOpVM.load128F64:
        return const UniOpVMInfo(
            sseInstId: 0,
            avxInstId: 0,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 16,
            memSizeShift: 0);
      case UniOpVM.load256U32:
      case UniOpVM.load256U64:
      case UniOpVM.load256F32:
      case UniOpVM.load256F64:
        return const UniOpVMInfo(
            sseInstId: 0,
            avxInstId: 0,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 32,
            memSizeShift: 0);
      case UniOpVM.loadCvt32I8ToI32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovsxbd,
            avxInstId: X86InstId.kVpmovsxbd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 4,
            memSizeShift: 2);
      case UniOpVM.loadCvt32U8ToU32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovzxbd,
            avxInstId: X86InstId.kVpmovzxbd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 4,
            memSizeShift: 2);
      default:
        return null;
    }
  }

  UniOpVMInfo? _getUniOpMVInfo(UniOpMV op) {
    switch (op) {
      case UniOpMV.store32U32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovd,
            avxInstId: X86InstId.kVmovd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 4,
            memSizeShift: 0);
      case UniOpMV.store32F32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovss,
            avxInstId: X86InstId.kVmovss,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 4,
            memSizeShift: 0);
      case UniOpMV.store64U32:
      case UniOpMV.store64U64:
      case UniOpMV.store64F32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovq,
            avxInstId: X86InstId.kVmovq,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 0);
      case UniOpMV.store64F64:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kMovsd,
            avxInstId: X86InstId.kVmovsd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 0);
      case UniOpMV.store128U32:
      case UniOpMV.store128U64:
      case UniOpMV.store128F32:
      case UniOpMV.store128F64:
        return const UniOpVMInfo(
            sseInstId: 0,
            avxInstId: 0,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 16,
            memSizeShift: 0);
      case UniOpMV.store256U32:
      case UniOpMV.store256U64:
      case UniOpMV.store256F32:
      case UniOpMV.store256F64:
        return const UniOpVMInfo(
            sseInstId: 0,
            avxInstId: 0,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 32,
            memSizeShift: 0);
      default:
        return null;
    }
  }
}
