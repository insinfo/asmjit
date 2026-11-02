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
      // TODO: Enable 32 registers when EVEX encoding is fully verified
      // _vecRegCount = 32;
      _vecRegCount = 16;
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

  void emitCVX86(UniOpCV op, BaseReg dst, BaseReg src) {
    switch (op) {
      case UniOpCV.cvtI2F:
        cc.addNode(InstNode(X86InstId.kCvtsi2ss, [dst, src]));
        break;
      case UniOpCV.cvtI2D:
        cc.addNode(InstNode(X86InstId.kCvtsi2sd, [dst, src]));
        break;
      case UniOpCV.cvtF2I:
        cc.addNode(InstNode(X86InstId.kCvttss2si, [dst, src]));
        break;
      case UniOpCV.cvtD2I:
        cc.addNode(InstNode(X86InstId.kCvttsd2si, [dst, src]));
        break;
    }
  }

  void _vMovX86(BaseReg dst, Operand src) {
    if (src is BaseReg && dst.id == src.id) return;

    // Handle GP registers
    if (dst.isGp) {
      if (src is BaseReg && src.isGp) {
        cc.addNode(InstNode(X86InstId.kMov, [dst, src]));
        return;
      }
      if (src is X86Mem) {
        cc.addNode(InstNode(X86InstId.kMov, [dst, src]));
        return;
      }
    }

    if (src is X86Mem) {
      // Use unaligned load by default for safety
      final instId = hasAvx ? X86InstId.kVmovdqu : X86InstId.kMovdqu;
      cc.addNode(InstNode(instId, [dst, src]));
      return;
    }

    if (src is BaseReg) {
      if (hasAvx) {
        cc.addNode(InstNode(X86InstId.kVmovdqa, [dst, src]));
      } else {
        // MOVDQA ainda não está no x86Dispatch -> use MOVDQU (funciona para reg->reg)
        cc.addNode(InstNode(X86InstId.kMovdqu, [dst, src]));
      }
      return;
    }
    throw ArgumentError("Invalid src operand type for vMov");
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

  /// `dst = ~a & b` (PANDN semantics, UniOpVVV.andn*).
  void _vAndNotX86(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpandn, [dst, a, b]));
    } else {
      // PANDN dst, src computes dst = ~dst & src.
      if (dst.id != a.id) _vMovX86(dst, a);
      cc.addNode(InstNode(X86InstId.kPandn, [dst, b]));
    }
  }

  /// `dst = a & ~b` (UniOpVVV.bic*), i.e. andn with swapped sources.
  void _vBicX86(BaseReg dst, BaseReg a, Operand b) {
    final bReg = b is BaseReg ? b : newVecWithWidth(VecWidth.k128, '@bic');
    if (b is! BaseReg) _vMovX86(bReg, b);
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpandn, [dst, bReg, a]));
    } else if (dst.id == a.id) {
      final tmp = newVecWithWidth(VecWidth.k128, '@bic');
      _vMovX86(tmp, bReg);
      cc.addNode(InstNode(X86InstId.kPandn, [tmp, a]));
      _vMovX86(dst, tmp);
    } else {
      if (dst.id != bReg.id) _vMovX86(dst, bReg);
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
    } else {
      throw _requiresX86('pblendw', 'SSE4.1');
    }
  }

  void _vBlendVX86(BaseReg dst, BaseReg src1, Operand src2, BaseReg mask) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpblendvb, [dst, src1, src2, mask]));
    } else {
      // PBLENDVB (SSE4.1) takes its mask implicitly in XMM0, which the
      // register allocator cannot pin, so use the SSE2 bitwise select:
      // dst = (src1 & ~mask) | (src2 & mask).
      final tmp = newVecWithWidth(VecWidth.k128, '@blend');
      _vMovX86(tmp, mask);
      cc.addNode(InstNode(X86InstId.kPand, [tmp, src2]));
      final notMask = newVecWithWidth(VecWidth.k128, '@nmask');
      _vMovX86(notMask, mask);
      cc.addNode(InstNode(X86InstId.kPandn, [notMask, src1]));
      cc.addNode(InstNode(X86InstId.kPor, [tmp, notMask]));
      _vMovX86(dst, tmp);
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
      // Manual handling for complex operations not fitting single-instruction mapping
      if (op == UniOpVM.loadDup32) {
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVbroadcastss, [dst, src.withSize(4)]));
        } else {
          _vLoad32X86(dst, src); // movd
          cc.addNode(InstNode(X86InstId.kPshufd, [dst, dst, Imm(0)]));
        }
        return;
      }
      if (op == UniOpVM.loadDup64) {
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVbroadcastsd, [dst, src.withSize(8)]));
        } else if (hasSse3) {
          cc.addNode(InstNode(X86InstId.kMovddup, [dst, src.withSize(8)]));
        } else {
          _vLoad64X86(dst, src); // movq
          // punpcklqdq xmm, xmm -> duplicates lo qword to hi
          cc.addNode(InstNode(X86InstId.kPunpcklqdq, [dst, dst]));
        }
        return;
      }
      if (op == UniOpVM.loadDup16) {
        if (hasAvx2) {
          cc.addNode(InstNode(X86InstId.kVpbroadcastw, [dst, src.withSize(2)]));
        } else {
          // SSE2 sequence
          _vZeroX86(dst); // Break dependency
          cc.addNode(
              InstNode(X86InstId.kPinsrw, [dst, src.withSize(2), Imm(0)]));
          cc.addNode(InstNode(X86InstId.kPshuflw, [dst, dst, Imm(0)]));
          cc.addNode(InstNode(X86InstId.kPunpcklqdq, [dst, dst]));
        }
        return;
      }
      throw UnimplementedError('UniOpVM $op not implemented for X86');
    }

    if (hasAvx) {
      switch (op) {
        // NOTE: uses the SSE forms — the encoder has no VEX pinsrb/pinsrw
        // yet. The destination was just zeroed, so this is functionally
        // equivalent (only a potential SSE/AVX transition penalty).
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
          // Force floating point moves for AVX to avoid vmovdqu issues
          int instId = (aligned ? X86InstId.kVmovaps : X86InstId.kVmovups);

          // Fix: Ensure we use the correct register width for the operation
          var target = dst;
          if (info.memSize == 16 && dst is X86Vec) {
            target = dst.xmm;
          }

          cc.addNode(InstNode(instId, [target, mem]));
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
        case UniOpVM.load128U32:
        case UniOpVM.load128U64:
        case UniOpVM.load128F32:
        case UniOpVM.load128F64:
          final mem = src.withSize(info.memSize);
          bool aligned = alignment.size != 0 && alignment.size >= info.memSize;
          int instId = (op.name.contains('F'))
              ? (aligned ? X86InstId.kMovaps : X86InstId.kMovups)
              : (aligned ? X86InstId.kMovdqa : X86InstId.kMovdqu);
          cc.addNode(InstNode(instId, [dst, mem]));
          return;
        default:
          if (info.sseInstId != 0) {
            cc.addNode(
                InstNode(info.sseInstId, [dst, src.withSize(info.memSize)]));
            return;
          }
      }
    }

    // Falling through would silently drop the load and execute garbage.
    throw UnimplementedError(
        '_emitVMX86: $op not implemented (hasAvx=$hasAvx)');
  }

  void _emitMVX86(
      UniOpMV op, X86Mem dst, BaseReg src, Alignment alignment, int idx) {
    // Narrow scalar stores extract the low element (mirrors C++ emit_mv).
    // Uses the SSE forms; correct under AVX as well.
    if (op == UniOpMV.store8 || op == UniOpMV.store16U16) {
      final s = src is X86Vec ? src.xmm : src;
      final isByte = op == UniOpMV.store8;
      cc.addNode(InstNode(isByte ? X86InstId.kPextrb : X86InstId.kPextrw,
          [dst.withSize(isByte ? 1 : 2), s, Imm(0)]));
      return;
    }

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
          // Force floating point moves for AVX to avoid vmovdqu issues
          int instId = (aligned ? X86InstId.kVmovaps : X86InstId.kVmovups);

          // Fix: Ensure we use the correct register width for the operation
          var source = src;
          if (info.memSize == 16 && src is X86Vec) {
            source = src.xmm;
          }

          cc.addNode(InstNode(instId, [mem, source]));
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
        case UniOpMV.store128U32:
        case UniOpMV.store128U64:
        case UniOpMV.store128F32:
        case UniOpMV.store128F64:
          final mem = dst.withSize(info.memSize);
          bool aligned = alignment.size != 0 && alignment.size >= info.memSize;
          int instId = (op.name.contains('F'))
              ? (aligned ? X86InstId.kMovaps : X86InstId.kMovups)
              : (aligned ? X86InstId.kMovdqa : X86InstId.kMovdqu);
          cc.addNode(InstNode(instId, [mem, src]));
          return;
        default:
          break;
      }
    }

    // Falling through would silently drop the store (data never written).
    throw UnimplementedError(
        '_emitMVX86: $op not implemented (hasAvx=$hasAvx)');
  }

  void _emit2vX86(UniOpVV op, Operand dst, Operand src) {
    if (dst is! BaseReg) {
      throw ArgumentError('SIMD dst must be register');
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
      case UniOpVV.broadcastU8:
        if (hasAvx2) {
          cc.addNode(InstNode(X86InstId.kVpbroadcastb, [dst, src]));
        } else {
          if (src is! BaseReg || dst.id != src.id) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPunpcklbw, [dst, dst]));
          cc.addNode(InstNode(X86InstId.kPunpcklwd, [dst, dst]));
          cc.addNode(InstNode(X86InstId.kPshufd, [dst, dst, Imm(0)]));
        }
        break;
      case UniOpVV.broadcastU16:
        if (hasAvx2) {
          cc.addNode(InstNode(X86InstId.kVpbroadcastw, [dst, src]));
        } else {
          if (src is! BaseReg || dst.id != src.id) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPshuflw, [dst, dst, Imm(0)]));
          cc.addNode(InstNode(X86InstId.kPshufd, [dst, dst, Imm(0)]));
        }
        break;
      case UniOpVV.absI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsb, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPabsb, [dst, dst]));
        } else {
          throw _requiresX86(op, 'SSSE3');
        }
        break;
      case UniOpVV.absI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsw, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPabsw, [dst, dst]));
        } else {
          throw _requiresX86(op, 'SSSE3');
        }
        break;
      case UniOpVV.absI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsd, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) _vMovX86(dst, src);
          cc.addNode(InstNode(X86InstId.kPabsd, [dst, dst]));
        } else {
          throw _requiresX86(op, 'SSSE3');
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
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
          if (dst != src) cc.addNode(InstNode(X86InstId.kMovaps, [dst, src]));
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVV.truncF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundpd, [dst, src, Imm(3)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(3)]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVV.floorF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundps, [dst, src, Imm(1)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(1)]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVV.floorF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundpd, [dst, src, Imm(1)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(1)]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVV.ceilF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundps, [dst, src, Imm(2)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(2)]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVV.ceilF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVroundpd, [dst, src, Imm(2)]));
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(2)]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVV.negF32:
        {
          Operand mask = (this as UniCompiler).simdConst(
              VecConstTable.p_8000000080000000, Bcst.kNA_Unique, VecWidth.k128);
          // XOR is commutative. Ensure first operand is Reg.
          // If src is Reg: dst = src ^ mask (mask can be Mem)
          // If src is Mem: dst = mask ^ src (mask must be loaded to dst first)
          if (src is BaseReg) {
            _vXorX86(dst, src, mask);
          } else {
            _vMovX86(dst, mask);
            _vXorX86(dst, dst, src);
          }
        }
        break;
      case UniOpVV.negF64:
        {
          Operand mask = (this as UniCompiler).simdConst(
              VecConstTable.p_8000000000000000, Bcst.kNA_Unique, VecWidth.k128);
          if (src is BaseReg) {
            _vXorX86(dst, src, mask);
          } else {
            _vMovX86(dst, mask);
            _vXorX86(dst, dst, src);
          }
        }
        break;
      case UniOpVV.absF32:
        {
          Operand mask = (this as UniCompiler).simdConst(
              VecConstTable.p_7FFFFFFF7FFFFFFF, Bcst.kNA_Unique, VecWidth.k128);
          if (src is BaseReg) {
            _vAndX86(dst, src, mask);
          } else {
            _vMovX86(dst, mask);
            _vAndX86(dst, dst, src);
          }
        }
        break;
      case UniOpVV.absF64:
        {
          Operand mask = (this as UniCompiler).simdConst(
              VecConstTable.p_7FFFFFFFFFFFFFFF, Bcst.kNA_Unique, VecWidth.k128);
          if (src is BaseReg) {
            _vAndX86(dst, src, mask);
          } else {
            _vMovX86(dst, mask);
            _vAndX86(dst, dst, src);
          }
        }
        break;
      default:
        throw UnimplementedError('_emit2vX86: $op not implemented');
    }
  }

  // ===========================================================================
  // SSE2 sequences for ops without a native instruction on the target
  // (ported from the sse_* helpers in unicompiler_x86.cpp).
  // ===========================================================================

  static final Map<int, int> _vexIdCache = {};

  /// VEX counterpart of a legacy SSE instruction (`paddq` -> `vpaddq`).
  int _vexIdX86(int legacyId) => _vexIdCache.putIfAbsent(legacyId, () {
        final name = 'v${kX86InstDb[legacyId].name}';
        return kX86InstDb.firstWhere((i) => i.name == name).id;
      });

  /// `dst = op(dst, src)`: legacy 2-operand form, or the VEX form with dst
  /// as both destination and first source.
  void _sseOpX86(int legacyId, BaseReg dst, Operand src) {
    if (hasAvx) {
      cc.addNode(InstNode(_vexIdX86(legacyId), [dst, dst, src]));
    } else {
      cc.addNode(InstNode(legacyId, [dst, src]));
    }
  }

  void _sseShiftImmX86(int legacyId, BaseReg dst, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(_vexIdX86(legacyId), [dst, dst, Imm(imm)]));
    } else {
      cc.addNode(InstNode(legacyId, [dst, Imm(imm)]));
    }
  }

  BaseReg _tmpVecX86() => newVecWithWidth(VecWidth.k128, '@tmp');

  BaseReg _copyVecX86(Operand src) {
    final t = _tmpVecX86();
    _vMovX86(t, src);
    return t;
  }

  /// All bits set.
  BaseReg _onesX86() {
    final t = _tmpVecX86();
    _sseOpX86(X86InstId.kPcmpeqd, t, t);
    return t;
  }

  /// Sign bit of every element of size `8 << el` bits.
  BaseReg _signMaskX86(int el) {
    final t = _onesX86();
    switch (el) {
      case 0: // 0xFF80 per word, saturating pack -> 0x80 per byte.
        _sseShiftImmX86(X86InstId.kPsllw, t, 7);
        _sseOpX86(X86InstId.kPacksswb, t, t);
      case 1:
        _sseShiftImmX86(X86InstId.kPsllw, t, 15);
      case 2:
        _sseShiftImmX86(X86InstId.kPslld, t, 31);
      default:
        _sseShiftImmX86(X86InstId.kPsllq, t, 63);
    }
    return t;
  }

  /// Signed `a > b` per element; returns a new register.
  BaseReg _cmpGtSignedX86(Operand a, Operand b, int el) {
    if (el < 3) {
      final r = _copyVecX86(a);
      _sseOpX86(
          [X86InstId.kPcmpgtb, X86InstId.kPcmpgtw, X86InstId.kPcmpgtd][el],
          r,
          b);
      return r;
    }
    if (hasSse42 || hasAvx) {
      final r = _copyVecX86(a);
      _sseOpX86(X86InstId.kPcmpgtq, r, b);
      return r;
    }
    // hi(a) > hi(b) || (hi(a) == hi(b) && lo(a) >u lo(b)), then broadcast
    // the high dword of each qword.
    final t1 = _copyVecX86(a);
    final t2 = _copyVecX86(b);
    _sseOpX86(X86InstId.kPcmpeqd, t1, t2);
    _sseOpX86(X86InstId.kPsubq, t2, a);
    _sseOpX86(X86InstId.kPand, t1, t2);
    final r = _copyVecX86(a);
    _sseOpX86(X86InstId.kPcmpgtd, r, b);
    _sseOpX86(X86InstId.kPor, r, t1);
    final out = _tmpVecX86();
    cc.addNode(InstNode(
        hasAvx ? X86InstId.kVpshufd : X86InstId.kPshufd, [out, r, Imm(0xF5)]));
    return out;
  }

  /// Unsigned `a > b` per element: flip the sign bits, compare signed.
  BaseReg _cmpGtUnsignedX86(Operand a, Operand b, int el) {
    final m = _signMaskX86(el);
    final fa = _copyVecX86(a);
    _sseOpX86(X86InstId.kPxor, fa, m);
    final fb = _copyVecX86(b);
    _sseOpX86(X86InstId.kPxor, fb, m);
    return _cmpGtSignedX86(fa, fb, el);
  }

  BaseReg _cmpGtX86(Operand a, Operand b, int el, bool signed) =>
      signed ? _cmpGtSignedX86(a, b, el) : _cmpGtUnsignedX86(a, b, el);

  BaseReg _notX86(BaseReg v) {
    _sseOpX86(X86InstId.kPxor, v, _onesX86());
    return v;
  }

  /// `dst = mask ? y : x` (bitwise).
  void _selectX86(BaseReg dst, Operand x, Operand y, BaseReg mask) {
    final hi = _copyVecX86(y);
    _sseOpX86(X86InstId.kPand, hi, mask);
    final lo = _copyVecX86(mask);
    _sseOpX86(X86InstId.kPandn, lo, x);
    _sseOpX86(X86InstId.kPor, hi, lo);
    _vMovX86(dst, hi);
  }

  /// Integer compare/min/max (and a few others) that have no native
  /// instruction for the enabled features. Returns false when the regular
  /// lowering in [_emit3vX86] should be used.
  bool _emit3vEmulatedX86(
      UniOpVVV op, BaseReg dst, BaseReg src1, Operand src2) {
    final name = op.name;
    final cmp =
        RegExp(r'^cmp(Gt|Ge|Lt|Le)([IU])(8|16|32|64)$').firstMatch(name);
    if (cmp != null) {
      final kind = cmp.group(1)!;
      final signed = cmp.group(2) == 'I';
      final el = const {'8': 0, '16': 1, '32': 2, '64': 3}[cmp.group(3)]!;
      // Native signed > for 8/16/32 is handled by the regular lowering.
      if (kind == 'Gt' && signed && el < 3) return false;
      final BaseReg r = switch (kind) {
        'Gt' => _cmpGtX86(src1, src2, el, signed),
        'Lt' => _cmpGtX86(src2, src1, el, signed),
        'Ge' => _notX86(_cmpGtX86(src2, src1, el, signed)),
        _ => _notX86(_cmpGtX86(src1, src2, el, signed)),
      };
      _vMovX86(dst, r);
      return true;
    }

    if (name == 'cmpEqU64' && !hasSse41 && !hasAvx) {
      // 32-bit equality of both halves.
      final r = _copyVecX86(src1);
      _sseOpX86(X86InstId.kPcmpeqd, r, src2);
      final t = _tmpVecX86();
      cc.addNode(InstNode(X86InstId.kPshufd, [t, r, Imm(0xB1)]));
      _sseOpX86(X86InstId.kPand, r, t);
      _vMovX86(dst, r);
      return true;
    }

    final mm = RegExp(r'^(min|max)([IU])(8|16|32|64)$').firstMatch(name);
    if (mm != null) {
      final isMin = mm.group(1) == 'min';
      final signed = mm.group(2) == 'I';
      final el = const {'8': 0, '16': 1, '32': 2, '64': 3}[mm.group(3)]!;
      // SSE2 has pminub/pmaxub and pminsw/pmaxsw; SSE4.1 (or AVX) covers the
      // remaining 8/16/32-bit forms natively.
      final sse2Native = (el == 0 && !signed) || (el == 1 && signed);
      if (el < 3 && (sse2Native || hasSse41 || hasAvx)) return false;
      final gt = _cmpGtX86(src1, src2, el, signed); // a > b
      // min: a > b ? b : a ; max: a > b ? a : b
      if (isMin) {
        _selectX86(dst, src1, src2, gt);
      } else {
        _selectX86(dst, src2, src1, gt);
      }
      return true;
    }

    if (op == UniOpVVV.mulU32 && !hasSse41 && !hasAvx) {
      // pmuludq multiplies the even dwords; do even and odd lanes and merge.
      final even = _copyVecX86(src1);
      _sseOpX86(X86InstId.kPmuludq, even, src2);
      final a1 = _tmpVecX86();
      cc.addNode(InstNode(X86InstId.kPshufd, [a1, src1, Imm(0xF5)]));
      final b1 = _tmpVecX86();
      cc.addNode(InstNode(X86InstId.kPshufd, [b1, src2, Imm(0xF5)]));
      _sseOpX86(X86InstId.kPmuludq, a1, b1);
      cc.addNode(InstNode(X86InstId.kPshufd, [even, even, Imm(0x08)]));
      cc.addNode(InstNode(X86InstId.kPshufd, [a1, a1, Imm(0x08)]));
      _sseOpX86(X86InstId.kPunpckldq, even, a1);
      _vMovX86(dst, even);
      return true;
    }

    if (op == UniOpVVV.combineLoHiU64 || op == UniOpVVV.combineLoHiF64) {
      // dst = {src2.u64[1], src1.u64[0]} (low, high).
      final r = _copyVecX86(src2);
      if (hasAvx) {
        cc.addNode(InstNode(X86InstId.kVshufpd, [r, r, src1, Imm(1)]));
      } else {
        cc.addNode(InstNode(X86InstId.kShufpd, [r, src1, Imm(1)]));
      }
      _vMovX86(dst, r);
      return true;
    }

    return false;
  }

  /// Error for an operation whose x86 lowering needs a CPU extension that is
  /// not enabled in the compiler's [CpuFeatures] (no SSE2 fallback yet).
  UnsupportedError _requiresX86(Object op, String ext) => UnsupportedError(
      'UniCompiler x86: $op requires $ext, which is not enabled in the '
      'CpuFeatures given to UniCompiler');

  void _emit3vX86(UniOpVVV op, Operand dst, Operand src1, Operand src2) {
    if (dst is! BaseReg || src1 is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    if (_emit3vEmulatedX86(op, dst, src1, src2)) return;
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
        _vBicX86(dst, src1, src2);
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVVV.maxI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxsb, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmaxsb, [dst, src2]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
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
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVVV.minI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminsd, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPminsd, [dst, src2]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVVV.minU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminud, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPminud, [dst, src2]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVVV.maxI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxsd, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmaxsd, [dst, src2]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
        }
        break;
      case UniOpVVV.maxU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxud, [dst, src1, src2]));
        } else if (hasSse41) {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kPmaxud, [dst, src2]));
        } else {
          throw _requiresX86(op, 'SSE4.1');
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
      case UniOpVVV.addF32S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVaddss, [dst, src1, src2]));
        } else {
          // Always copy src1 into dst to avoid losing the initial value after register allocation.
          cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kAddss, [dst, src2]));
        }
        break;
      case UniOpVVV.addF64S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVaddsd, [dst, src1, src2]));
        } else {
          // Always copy src1 into dst to avoid losing the initial value after register allocation.
          cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kAddsd, [dst, src2]));
        }
        break;
      case UniOpVVV.subF32S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsubss, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kSubss, [dst, src2]));
        }
        break;
      case UniOpVVV.subF64S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsubsd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kSubsd, [dst, src2]));
        }
        break;
      case UniOpVVV.mulF32S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmulss, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMulss, [dst, src2]));
        }
        break;
      case UniOpVVV.mulF64S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmulsd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMulsd, [dst, src2]));
        }
        break;
      case UniOpVVV.divF32S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVdivss, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kDivss, [dst, src2]));
        }
        break;
      case UniOpVVV.divF64S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVdivsd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kDivsd, [dst, src2]));
        }
        break;
      case UniOpVVV.minF32S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVminss, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMinss, [dst, src2]));
        }
        break;
      case UniOpVVV.minF64S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVminsd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMinsd, [dst, src2]));
        }
        break;
      case UniOpVVV.maxF32S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmaxss, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMaxss, [dst, src2]));
        }
        break;
      case UniOpVVV.maxF64S:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmaxsd, [dst, src1, src2]));
        } else {
          if (dst.id != src1.id)
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMaxsd, [dst, src2]));
        }
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
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
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
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
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
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
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
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
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
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
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
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          cc.addNode(InstNode(X86InstId.kMaxpd, [dst, src2]));
        }
        break;
      case UniOpVVV.cmpEqF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmpps, [dst, src1, src2, Imm(0)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmpps, [dst, src2, Imm(0)]));
        }
        break;
      case UniOpVVV.cmpEqF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmppd, [dst, src1, src2, Imm(0)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmppd, [dst, src2, Imm(0)]));
        }
        break;
      case UniOpVVV.cmpLtF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmpps, [dst, src1, src2, Imm(1)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmpps, [dst, src2, Imm(1)]));
        }
        break;
      case UniOpVVV.cmpLtF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmppd, [dst, src1, src2, Imm(1)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmppd, [dst, src2, Imm(1)]));
        }
        break;
      case UniOpVVV.cmpLeF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmpps, [dst, src1, src2, Imm(2)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmpps, [dst, src2, Imm(2)]));
        }
        break;
      case UniOpVVV.cmpLeF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmppd, [dst, src1, src2, Imm(2)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmppd, [dst, src2, Imm(2)]));
        }
        break;
      case UniOpVVV.cmpNeF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmpps, [dst, src1, src2, Imm(4)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmpps, [dst, src2, Imm(4)]));
        }
        break;
      case UniOpVVV.cmpNeF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcmppd, [dst, src1, src2, Imm(4)]));
        } else {
          if (dst.id != src1.id) _vMovX86(dst, src1);
          cc.addNode(InstNode(X86InstId.kCmppd, [dst, src2, Imm(4)]));
        }
        break;
      case UniOpVVV.cmpGtF32:
      case UniOpVVV.cmpGeF32:
      case UniOpVVV.cmpGtF64:
      case UniOpVVV.cmpGeF64:
        {
          Operand op2 = src2;
          if (src2 is! BaseReg) {
            final tmp = (this as UniCompiler)
                .newVecWithWidth((this as UniCompiler).vecWidth, "tmp_swap");
            _vLoadUX86(tmp, src2 as X86Mem);
            op2 = tmp;
          }

          final UniOpVVV newOp;
          if (op == UniOpVVV.cmpGtF32)
            newOp = UniOpVVV.cmpLtF32;
          else if (op == UniOpVVV.cmpGeF32)
            newOp = UniOpVVV.cmpLeF32;
          else if (op == UniOpVVV.cmpGtF64)
            newOp = UniOpVVV.cmpLtF64;
          else
            newOp = UniOpVVV.cmpLeF64; // cmpGeF64

          _emit3vX86(newOp, dst, op2, src1);
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
        } else {
          throw _requiresX86(op, 'SSSE3');
        }
        break;
      case UniOpVVI.swizzleU32x4:
        cc.addNode(InstNode(hasAvx ? X86InstId.kVpshufd : X86InstId.kPshufd,
            [dst, src, Imm(imm)]));
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
        } else {
          throw _requiresX86(op, 'SSSE3');
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

  void _emitCmovX86(UniCondition cond, BaseReg dst, Operand src) {
    // Generate condition test (CMP/TEST/etc.)
    (this as UniCompiler)._emitConditionTestX86(cond);

    // X86 CMOVcc only works with 16/32/64-bit GP registers
    if (dst is! X86Gp) {
      throw ArgumentError('emitCmov only supports GP registers on X86');
    }

    final cmovId = _condCodeToCmov(cond.cond);
    cc.addNode(InstNode(cmovId, [dst, src]));
  }

  void _emitSelectX86(
      UniCondition cond, BaseReg dst, Operand src1, Operand src2) {
    if (dst is! X86Gp) {
      throw ArgumentError('emitSelect only supports GP registers on X86');
    }

    // Typical pattern: mov dst, src2; cmovcc dst, src1
    if (src2 is! X86Gp || dst.id != src2.id) {
      (this as UniCompiler).emitMov(dst, src2);
    }
    _emitCmovX86(cond, dst, src1);
  }

  int _condCodeToCmov(int cond) {
    switch (cond) {
      case CondCode.kEqual:
        return X86InstId.kCmovz;
      case CondCode.kNotEqual:
        return X86InstId.kCmovnz;
      case CondCode.kSignedLT:
        return X86InstId.kCmovl;
      case CondCode.kSignedGE:
        return X86InstId.kCmovnl;
      case CondCode.kSignedLE:
        return X86InstId.kCmovle;
      case CondCode.kSignedGT:
        return X86InstId.kCmovnle;
      case CondCode.kUnsignedLT:
        return X86InstId.kCmovb;
      case CondCode.kUnsignedGE:
        return X86InstId.kCmovnb;
      case CondCode.kUnsignedLE:
        return X86InstId.kCmovbe;
      case CondCode.kUnsignedGT:
        return X86InstId.kCmovnbe;
      case CondCode.kOverflow:
        return X86InstId.kCmovo;
      case CondCode.kNotOverflow:
        return X86InstId.kCmovno;
      case CondCode.kSign:
        return X86InstId.kCmovs;
      case CondCode.kNotSign:
        return X86InstId.kCmovns;
      case CondCode.kParityEven:
        return X86InstId.kCmovp;
      case CondCode.kParityOdd:
        return X86InstId.kCmovnp;
      default:
        throw ArgumentError('Unsupported condition for CMOV: $cond');
    }
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
      case UniOpVM.loadCvt64I16ToI32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovsxwd,
            avxInstId: X86InstId.kVpmovsxwd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 1);
      case UniOpVM.loadCvt64U16ToU32:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovzxwd,
            avxInstId: X86InstId.kVpmovzxwd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 1);
      case UniOpVM.loadCvt64I32ToI64:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovsxdq,
            avxInstId: X86InstId.kVpmovsxdq,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 1);
      case UniOpVM.loadCvt64U32ToU64:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovzxdq,
            avxInstId: X86InstId.kVpmovzxdq,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 8,
            memSizeShift: 1);
      case UniOpVM.load8:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovzxbd,
            avxInstId: X86InstId.kVpmovzxbd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 1,
            memSizeShift: 0);
      case UniOpVM.load16U16:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPmovzxwd,
            avxInstId: X86InstId.kVpmovzxwd,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 2,
            memSizeShift: 0);
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
      case UniOpMV.store8:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPextrb,
            avxInstId: X86InstId.kVpextrb,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 1,
            memSizeShift: 0);
      case UniOpMV.store16U16:
        return const UniOpVMInfo(
            sseInstId: X86InstId.kPextrw,
            avxInstId: X86InstId.kVpextrw,
            asimdInstId: 0,
            narrowingOp: 0,
            memSize: 2,
            memSizeShift: 0);
      default:
        return null;
    }
  }
}
