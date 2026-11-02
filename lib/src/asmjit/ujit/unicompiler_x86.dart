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

    // AVX-512 is not enabled: the EVEX encodings its lowerings need (k
    // registers, vpternlog, EVEX-only compares and moves) are not ported
    // and verified yet, so AVX-512 hosts use the AVX2 lowerings.

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
      // loadInsert*: port of the kLoadInsert* cases of emit_vm()
      // (unicompiler_x86.cpp).
      if (op.name.startsWith('loadInsert')) {
        _loadInsertX86(op, dst, src, idx);
        return;
      }

      // loadCvt*: load exactly the source bytes, then widen in registers.
      final cvt =
          RegExp(r'^loadCvt(16|32|64|N)([IU])(8|16|32)To[IU](16|32|64)$')
              .firstMatch(op.name);
      if (cvt != null) {
        final memBits = cvt.group(1) == 'N' ? 64 : int.parse(cvt.group(1)!);
        (this as UniCompiler).emitVM(
            const {
              16: UniOpVM.load16U16,
              32: UniOpVM.load32U32,
              64: UniOpVM.load64U64
            }[memBits]!,
            dst,
            src);
        final sign = cvt.group(2)!;
        for (int w = int.parse(cvt.group(3)!);
            w < int.parse(cvt.group(4)!);
            w *= 2) {
          (this as UniCompiler).emit2v(
              UniOpVV.values.byName('cvt$sign${w}LoTo$sign${w * 2}'), dst, dst);
        }
        return;
      }
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
      // storeExtract*: port of the kStoreExtract* cases of emit_mv().
      if (op.name.startsWith('storeExtract')) {
        _storeExtractX86(op, dst, src, idx);
        return;
      }
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

  /// `avx_fmov()`.
  void _avxFmovX86(BaseReg dst, Operand src, int fm) {
    if (src is BaseReg) {
      if (dst.id != src.id) {
        _emitX86(
            X86InstId.kVmovaps, [_isScalarFm(fm) ? X86Xmm(dst.id) : dst, src]);
      }
    } else if (_isScalarFm(fm)) {
      _emitX86(_vexIdX86(_sseFloatInst[fm].fmovs), [dst, src]);
    } else {
      _emitX86(_vexIdX86(_sseFloatInst[fm].fmovu), [dst, src]);
    }
  }

  // WideningOp of `sse_int_widen()`.
  static const _kI8ToI16 = 1, _kU8ToU16 = 2, _kI8ToI32 = 3, _kU8ToU32 = 4;
  static const _kI16ToI32 = 6, _kU16ToU32 = 7, _kI32ToI64 = 8, _kU32ToU64 = 9;

  /// `sse_int_widening_op_info`: (mov, unpack_lo, sign_extends).
  static const _sseIntWidening = <(int, int, bool)>[
    (-1, -1, false), // kNone.
    (X86InstId.kPmovsxbw, X86InstId.kPunpcklbw, true), // kI8ToI16.
    (X86InstId.kPmovzxbw, X86InstId.kPunpcklbw, false), // kU8ToU16.
    (X86InstId.kPmovsxbd, -1, true), // kI8ToI32.
    (X86InstId.kPmovzxbd, -1, false), // kU8ToU32.
    (X86InstId.kPmovzxbq, -1, false), // kU8ToU64.
    (X86InstId.kPmovsxwd, X86InstId.kPunpcklwd, true), // kI16ToI32.
    (X86InstId.kPmovzxwd, X86InstId.kPunpcklwd, false), // kU16ToU32.
    (X86InstId.kPmovsxdq, X86InstId.kPunpckldq, true), // kI32ToI64.
    (X86InstId.kPmovzxdq, X86InstId.kPunpckldq, false), // kU32ToU64.
  ];

  /// `sse_int_widen()`.
  void _sseIntWidenX86(BaseReg dst, BaseReg src, int cvt) {
    final (mov, unpackLo, signExtends) = _sseIntWidening[cvt];

    if (hasSse41) {
      _emitX86(mov, [dst, src]);
      return;
    }

    if (!signExtends && unpackLo != -1) {
      final zero =
          _simdConstX86(VecConstTable.p_0000000000000000, Bcst.kNA, dst);
      _sseMovX86(dst, src);
      _emitX86(unpackLo, [dst, zero]);
      return;
    }

    switch (cvt) {
      case _kI8ToI16:
        _emitX86(unpackLo, [dst, src]);
        _emitX86(X86InstId.kPsraw, [dst, Imm(8)]);
      case _kI8ToI32:
        _emitX86(X86InstId.kPunpcklbw, [dst, src]);
        _emitX86(X86InstId.kPunpcklwd, [dst, dst]);
        _emitX86(X86InstId.kPsrad, [dst, Imm(24)]);
      case _kU8ToU32:
        final zero =
            _simdConstX86(VecConstTable.p_0000000000000000, Bcst.kNA, dst);
        _sseMovX86(dst, src);
        _emitX86(X86InstId.kPunpcklbw, [dst, zero]);
        _emitX86(X86InstId.kPunpcklwd, [dst, zero]);
      case _kI16ToI32:
        _emitX86(unpackLo, [dst, src]);
        _emitX86(X86InstId.kPsrad, [dst, Imm(16)]);
      case _kI32ToI64:
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _sseMovX86(tmp, src);
        _sseMovX86(dst, src);
        _emitX86(X86InstId.kPsrad, [tmp, Imm(31)]);
        _emitX86(X86InstId.kPunpckldq, [dst, tmp]);
      default:
        throw StateError('unreachable widening $cvt');
    }
  }

  /// Masks of the abs/neg float ops of `emit_2v()`.
  static VecConst _absNegMaskX86(UniOpVV op) => switch (op) {
        UniOpVV.absF32 || UniOpVV.absF32S => VecConstTable.p_7FFFFFFF7FFFFFFF,
        UniOpVV.absF64 || UniOpVV.absF64S => VecConstTable.p_7FFFFFFFFFFFFFFF,
        UniOpVV.negF32 || UniOpVV.negF32S => VecConstTable.p_8000000080000000,
        _ => VecConstTable.p_8000000000000000,
      };

  static Bcst _bcstOf(int broadcastSize) => switch (broadcastSize) {
        4 => Bcst.k32,
        8 => Bcst.k64,
        _ => Bcst.kNA,
      };

  /// `get_fop_half_minus_1ulp()` / `get_fop_msb_bit()`.
  Operand _fopHalfMinus1UlpX86(BaseReg dst, int fm) => _isF32Fm(fm)
      ? _simdConstX86(VecConstTable.f32_0_5_minus_1ulp, Bcst.k32, dst)
      : _simdConstX86(VecConstTable.f64_0_5_minus_1ulp, Bcst.k64, dst);

  Operand _fopMsbBitX86(BaseReg dst, int fm) => _isF32Fm(fm)
      ? _simdConstX86(VecConstTable.p_8000000080000000, Bcst.k32, dst)
      : _simdConstX86(VecConstTable.p_8000000000000000, Bcst.k64, dst);

  static BaseReg _asGpX86(BaseReg r, int bits) => switch (bits) {
        8 => X86Gp.r8(r.id),
        16 => X86Gp.r16(r.id),
        32 => X86Gp.r32(r.id),
        _ => X86Gp.r64(r.id),
      };

  /// Port of `emit_2v()` (ujit/unicompiler_x86.cpp).
  ///
  /// As a Dart convenience `mov` also moves general purpose registers.
  void _emit2vX86(UniOpVV op, Operand dst_, Operand src_) {
    if (dst_ is! BaseReg) {
      throw ArgumentError('SIMD destination must be a register');
    }
    if (op == UniOpVV.mov && (dst_.isGp || (src_ is BaseReg && src_.isGp))) {
      _vMovX86(dst_, src_);
      return;
    }

    var dst = dst_;
    var src = src_;
    final info = kX86OpcodeInfo2v[op.index];
    final fm = info.floatMode;

    if (hasAvx) {
      // AVX Implementation
      // ------------------
      var instId = info.avxInstId;

      if (hasAvxExt(info.avxExt)) {
        _emitX86(instId, [dst, src, if (info.useImm != 0) Imm(info.imm)]);
        return;
      }

      switch (op) {
        case UniOpVV.mov:
          _emitX86(X86InstId.kVmovaps, [dst, src]);
          return;

        case UniOpVV.movU64:
          if (src is BaseReg) src = X86Xmm(src.id);
          _emitX86(X86InstId.kVmovq, [X86Xmm(dst.id), src]);
          return;

        case UniOpVV.broadcastU8Z:
        case UniOpVV.broadcastU16Z:
        case UniOpVV.broadcastU8:
        case UniOpVV.broadcastU16:
        case UniOpVV.broadcastU32:
        case UniOpVV.broadcastU64:
        case UniOpVV.broadcastF32:
        case UniOpVV.broadcastF64:
          // Intrinsic - 32/64-bit broadcasts require AVX, 8/16-bit
          // broadcasts require AVX2/AVX512.
          final elementSize = info.elementSize;

          if (src is BaseReg && src.isGp) {
            final srcGp = _asGpX86(src, elementSize <= 2 ? 32 : 64);

            // BroadcastU[8|16]Z without AVX2: the unused part of the source
            // is zero, so multiplying by a constant extends the data into 32
            // bits and VPSHUFD does the rest.
            if (!hasAvx2 && elementSize <= 1 && info.imm == 0x01) {
              final expanded = (this as UniCompiler).newGp32('@expanded');
              _emitX86(X86InstId.kImul, [
                expanded,
                srcGp,
                Imm(elementSize == 0 ? 0x01010101 : 0x00010001)
              ]);
              final x = X86Xmm(dst.id);
              _emitX86(X86InstId.kVmovd, [x, expanded]);
              _emitX86(X86InstId.kVpshufd, [x, x, Imm(_shufImm4(0, 0, 0, 0))]);
              if (dst is! X86Xmm) {
                _emitX86(X86InstId.kVinsertf128, [dst, dst, x, Imm(0)]);
              }
              return;
            }

            // AVX/AVX2 doesn't provide broadcast from GP to XMM, we have to
            // move to XMM first.
            _emitX86(elementSize <= 2 ? X86InstId.kVmovd : X86InstId.kVmovq,
                [X86Xmm(dst.id), srcGp]);
            src = X86Xmm(dst.id);
          }

          // We have either a broadcast from memory or an XMM register - AVX2
          // requires special handling from here...
          if (!hasAvx2) {
            final dstXmm = X86Xmm(dst.id);
            if (elementSize <= 1) {
              // AVX doesn't provide 8-bit and 16-bit broadcasts - VPSHUFB
              // repeats the byte (word).
              final insertInstId =
                  elementSize == 0 ? X86InstId.kVpinsrb : X86InstId.kVpinsrw;
              final pred = _simdVecConstX86(
                  elementSize == 0
                      ? VecConstTable.p_0000000000000000
                      : VecConstTable.p_0100010001000100,
                  Bcst.k32,
                  dstXmm);
              if (src is X86Mem) {
                _emitX86(insertInstId, [
                  dstXmm,
                  pred,
                  src.withSize(elementSize == 0 ? 1 : 2),
                  Imm(0)
                ]);
                _emitX86(X86InstId.kVpshufb, [dstXmm, dstXmm, pred]);
              } else {
                _emitX86(X86InstId.kVpshufb,
                    [dstXmm, X86Xmm((src as BaseReg).id), pred]);
              }
            } else {
              // AVX's VBROADCAST[SS|SD] only take memory sources.
              if (src is X86Mem) {
                var bcstInstId = elementSize == 2
                    ? X86InstId.kVbroadcastss
                    : X86InstId.kVbroadcastsd;
                if (dst is X86Xmm && bcstInstId == X86InstId.kVbroadcastsd) {
                  bcstInstId = X86InstId.kVmovddup;
                }
                _emitX86(
                    bcstInstId, [dst, src.withSize(elementSize == 2 ? 4 : 8)]);
                return;
              }
              final srcXmm = X86Xmm((src as BaseReg).id);
              if (elementSize == 2) {
                _emitX86(X86InstId.kVpshufd,
                    [dstXmm, srcXmm, Imm(_shufImm4(0, 0, 0, 0))]);
              } else {
                _emitX86(X86InstId.kVmovddup, [dstXmm, srcXmm]);
              }
            }
            if (dst is! X86Xmm) {
              _emitX86(X86InstId.kVinsertf128, [dst, dst, dstXmm, Imm(0)]);
            }
            return;
          }

          // VBROADCASTSD cannot be used when XMM is a destination, in that
          // case we must use VMOVDDUP.
          if (dst is X86Xmm && instId == X86InstId.kVbroadcastsd) {
            instId = X86InstId.kVmovddup;
          }
          if (src is X86Mem) {
            _emitX86(instId, [dst, src.withSize(1 << elementSize)]);
          } else {
            _emitX86(instId, [dst, X86Xmm((src as BaseReg).id)]);
          }
          return;

        case UniOpVV.broadcastV128U32:
        case UniOpVV.broadcastV128U64:
        case UniOpVV.broadcastV128F32:
        case UniOpVV.broadcastV128F64:
          if (src is BaseReg) src = X86Xmm(src.id);
          // 128-bit broadcast is like 128-bit mov in this case as we don't
          // have a wider destination.
          if (dst is X86Xmm) {
            _avxMovX86(dst, src);
            return;
          }
          final isFloat = op.index >= UniOpVV.broadcastV128F32.index;
          if (src is X86Mem) {
            _emitX86(
                isFloat || !hasAvx2
                    ? X86InstId.kVbroadcastf128
                    : X86InstId.kVbroadcasti128,
                [dst, src]);
            return;
          }
          _emitX86(
              isFloat || !hasAvx2
                  ? X86InstId.kVinsertf128
                  : X86InstId.kVinserti128,
              [dst, X86Ymm((src as BaseReg).id), src, Imm(1)]);
          return;

        case UniOpVV.broadcastV256U32:
        case UniOpVV.broadcastV256U64:
        case UniOpVV.broadcastV256F32:
        case UniOpVV.broadcastV256F64:
          if (src is BaseReg) src = X86Ymm(src.id);
          // Cannot broadcast 256-bit vector to a 128-bit or 256-bit vector.
          _avxMovX86(X86Ymm(dst.id), src);
          return;

        case UniOpVV.absI64:
          // Native operation requires AVX512, which is not supported by the
          // target.
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _emitX86(X86InstId.kVpxor, [tmp, tmp, tmp]);
          _emitX86(X86InstId.kVpsubq, [tmp, tmp, src]);
          _emitX86(X86InstId.kVblendvpd, [dst, tmp, src, tmp]);
          return;

        case UniOpVV.notU32:
        case UniOpVV.notU64:
        case UniOpVV.notF32:
        case UniOpVV.notF64:
          _avxBitNotX86(dst, src);
          return;

        case UniOpVV.cvtI8ToI32:
        case UniOpVV.cvtU8ToU32:
          if (src is BaseReg) {
            src = X86Xmm(src.id);
          } else {
            src = (src as X86Mem).withSize(dst.size ~/ 4);
          }
          _emitX86(instId, [dst, src]);
          return;

        case UniOpVV.cvtI8HiToI16:
        case UniOpVV.cvtU8HiToU16:
        case UniOpVV.cvtI16HiToI32:
        case UniOpVV.cvtU16HiToU32:
        case UniOpVV.cvtI32HiToI64:
        case UniOpVV.cvtU32HiToU64:
        case UniOpVV.cvtI8LoToI16:
        case UniOpVV.cvtU8LoToU16:
        case UniOpVV.cvtI16LoToI32:
        case UniOpVV.cvtU16LoToU32:
        case UniOpVV.cvtI32LoToI64:
        case UniOpVV.cvtU32LoToU64:
          final hi = op == UniOpVV.cvtI8HiToI16 ||
              op == UniOpVV.cvtU8HiToU16 ||
              op == UniOpVV.cvtI16HiToI32 ||
              op == UniOpVV.cvtU16HiToU32 ||
              op == UniOpVV.cvtI32HiToI64 ||
              op == UniOpVV.cvtU32HiToU64;
          if (hi) {
            if (src is BaseReg) {
              if (dst is X86Xmm) {
                final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
                _emitX86(
                    X86InstId.kVpshufd, [tmp, src, Imm(_shufImm4(3, 2, 3, 2))]);
                src = tmp;
              } else {
                final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
                _emitX86(
                    X86InstId.kVextractf128, [tmp, X86Ymm(src.id), Imm(1)]);
                src = tmp;
              }
            } else {
              final m = src as X86Mem;
              src = m.withDisplacement(m.displacement + dst.size ~/ 2);
            }
          }
          if (src is BaseReg) {
            src = dst is X86Zmm ? X86Ymm(src.id) : X86Xmm(src.id);
          } else {
            src = (src as X86Mem).withSize(dst.size ~/ 2);
          }
          _emitX86(instId, [dst, src]);
          return;

        case UniOpVV.absF32S:
        case UniOpVV.absF64S:
        case UniOpVV.absF32:
        case UniOpVV.absF64:
        case UniOpVV.negF32S:
        case UniOpVV.negF64S:
        case UniOpVV.negF32:
        case UniOpVV.negF64:
          final msk = _simdConstX86(
              _absNegMaskX86(op), _bcstOf(info.broadcastSize), dst);
          if (src is! BaseReg && _isScalarFm(fm)) {
            _avxFmovX86(dst, src, fm);
            _emitX86(instId, [dst, dst, msk]);
          } else if (src is! BaseReg && msk is! BaseReg) {
            _avxFmovX86(dst, msk, fm);
            _emitX86(instId, [dst, dst, src]);
          } else if (src is! BaseReg) {
            _emitX86(instId, [dst, msk, src]);
          } else {
            _emitX86(instId, [dst, src, msk]);
          }
          return;

        case UniOpVV.rcpF32:
        case UniOpVV.rcpF64:
          final one = _simdVecConstX86(
              op == UniOpVV.rcpF32 ? VecConstTable.f32_1 : VecConstTable.f64_1,
              Bcst.k32,
              dst);
          _emitX86(op == UniOpVV.rcpF32 ? X86InstId.kVdivps : X86InstId.kVdivpd,
              [dst, one, src]);
          return;

        case UniOpVV.truncF32S:
        case UniOpVV.truncF64S:
        case UniOpVV.truncF32:
        case UniOpVV.truncF64:
        case UniOpVV.floorF32S:
        case UniOpVV.floorF64S:
        case UniOpVV.floorF32:
        case UniOpVV.floorF64:
        case UniOpVV.ceilF32S:
        case UniOpVV.ceilF64S:
        case UniOpVV.ceilF32:
        case UniOpVV.ceilF64:
        case UniOpVV.roundEvenF32S:
        case UniOpVV.roundEvenF64S:
        case UniOpVV.roundEvenF32:
        case UniOpVV.roundEvenF64:
          if (_isScalarFm(fm)) {
            dst = X86Xmm(dst.id);
            // These instructions use 3 operand form for historical reasons.
            if (src is! BaseReg) {
              _emitX86(_vexIdX86(_sseFloatInst[fm].fmovs), [dst, src]);
              _emitX86(instId, [dst, dst, dst, Imm(info.imm)]);
            } else {
              final s = X86Xmm(src.id);
              _emitX86(instId, [dst, s, s, Imm(info.imm)]);
            }
          } else {
            _emitX86(instId, [dst, src, Imm(info.imm)]);
          }
          return;

        case UniOpVV.roundHalfAwayF32S:
        case UniOpVV.roundHalfAwayF64S:
        case UniOpVV.roundHalfAwayF32:
        case UniOpVV.roundHalfAwayF64:
          final fi = _sseFloatInst[fm];
          if (_isScalarFm(fm)) {
            dst = X86Xmm(dst.id);
            if (src is BaseReg) src = X86Xmm(src.id);
          }
          if (src is! BaseReg) {
            _avxFmovX86(dst, src, fm);
            src = dst;
          }
          final half = _fopHalfMinus1UlpX86(dst, fm);
          final msb = _fopMsbBitX86(dst, fm);
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _emitX86(_vexIdX86(fi.fand), [tmp, src, msb]);
          _emitX86(_vexIdX86(fi.for_), [tmp, tmp, half]);
          _emitX86(_vexIdX86(fi.fadd), [dst, src, tmp]);
          // kTrunc | kSuppress.
          if (_isScalarFm(fm)) {
            _emitX86(_vexIdX86(fi.fround), [dst, dst, dst, Imm(0x0B)]);
          } else {
            _emitX86(_vexIdX86(fi.fround), [dst, dst, Imm(0x0B)]);
          }
          return;

        case UniOpVV.roundHalfUpF32S:
        case UniOpVV.roundHalfUpF64S:
        case UniOpVV.roundHalfUpF32:
        case UniOpVV.roundHalfUpF64:
          if (_isScalarFm(fm)) dst = X86Xmm(dst.id);
          final half = _fopHalfMinus1UlpX86(dst, fm);
          final off = op.index - UniOpVV.roundHalfUpF32S.index;
          final addOp = UniOpVVV.values[UniOpVVV.addF32S.index + off];
          final floorOp = UniOpVV.values[UniOpVV.floorF32S.index + off];
          if (src is! BaseReg) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _avxFmovX86(tmp, src, fm);
            _emit3vX86(addOp, tmp, tmp, half);
            _emit2vX86(floorOp, dst, tmp);
          } else {
            _emit3vX86(addOp, dst, _cloneAsX86(src, dst), half);
            _emit2vX86(floorOp, dst, dst);
          }
          return;

        case UniOpVV.sqrtF32S:
        case UniOpVV.sqrtF64S:
          dst = X86Xmm(dst.id);
          // These instructions use 3 operand form for historical reasons.
          if (src is! BaseReg) {
            _avxFmovX86(dst, src, fm);
            _emitX86(instId, [dst, dst, dst]);
          } else {
            final s = X86Xmm(src.id);
            _emitX86(instId, [dst, s, s]);
          }
          return;

        case UniOpVV.cvtF32ToF64S:
        case UniOpVV.cvtF64ToF32S:
          dst = X86Xmm(dst.id);
          if (src is BaseReg) src = X86Xmm(src.id);
          // These instructions use 3 operand form for historical reasons.
          final zeros =
              _simdVecConstX86(VecConstTable.p_0000000000000000, Bcst.k32, dst);
          _emitX86(instId, [dst, zeros, src]);
          return;

        case UniOpVV.cvtF32LoToF64:
        case UniOpVV.cvtI32LoToF64:
          // Widening conversion - low part conversions are native.
          if (src is BaseReg) {
            src = dst is X86Zmm ? X86Ymm(src.id) : X86Xmm(src.id);
          } else {
            src = (src as X86Mem).withSize((dst.size >> 4) * 8);
          }
          _emitX86(instId, [dst, src]);
          return;

        case UniOpVV.cvtF32HiToF64:
        case UniOpVV.cvtI32HiToF64:
          if (src is BaseReg) {
            final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
            if (dst is X86Ymm) {
              _emitX86(X86InstId.kVextracti128, [tmp, X86Ymm(src.id), Imm(1)]);
            } else {
              _emitX86(X86InstId.kVpshufd,
                  [tmp, X86Xmm(src.id), Imm(_shufImm4(3, 2, 3, 2))]);
            }
            _emitX86(instId, [dst, tmp]);
          } else {
            final w = dst.size >> 4;
            final m = src as X86Mem;
            _emitX86(instId, [
              dst,
              m.withSize(w * 8).withDisplacement(m.displacement + w * 8)
            ]);
          }
          return;

        case UniOpVV.cvtF64ToF32Lo:
        case UniOpVV.cvtTruncF64ToI32Lo:
        case UniOpVV.cvtRoundF64ToI32Lo:
          // Narrowing conversion - low part conversions are native.
          final srcSize = src is X86Mem ? src.size : (src as BaseReg).size;
          final dstSize = math.max(dst.size ~/ 2, srcSize);
          final w = dstSize >> 5;
          dst = w <= 1 ? X86Xmm(dst.id) : X86Ymm(dst.id);
          if (src is BaseReg) {
            src = w == 0 ? X86Xmm(src.id) : X86Ymm(src.id);
          } else if ((src as X86Mem).size == 0) {
            src = src.withSize(w * 32);
          }
          _emitX86(instId, [dst, src]);
          return;

        case UniOpVV.cvtF64ToF32Hi:
        case UniOpVV.cvtTruncF64ToI32Hi:
        case UniOpVV.cvtRoundF64ToI32Hi:
          final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
          if (src is X86Mem) src = src.withSize(dst.size);
          _emitX86(instId, [tmp, src]);
          if (dst is X86Ymm) {
            _emitX86(X86InstId.kVinserti128, [dst, dst, tmp, Imm(1)]);
          } else {
            _emitX86(X86InstId.kVunpcklpd, [dst, dst, tmp]);
          }
          return;

        default:
          throw _requiresX86(op, info.avxExt.name.substring(1));
      }
    }

    // SSE Implementation
    // ------------------
    final instId = info.sseInstId;

    if (hasSseExt(info.sseExt)) {
      _emitX86(instId, [dst, src, if (info.useImm != 0) Imm(info.imm)]);
      return;
    }

    switch (op) {
      case UniOpVV.mov:
        _emitX86(X86InstId.kMovaps, [dst, src]);
        return;

      case UniOpVV.movU64:
        _emitX86(X86InstId.kMovq, [dst, src]);
        return;

      case UniOpVV.broadcastU8Z:
      case UniOpVV.broadcastU16Z:
      case UniOpVV.broadcastU8:
      case UniOpVV.broadcastU16:
        // Intrinsic - 8/16-bit broadcasts are not available in SSE mode.
        final elementSize = info.elementSize;
        if (src is X86Mem || (src is BaseReg && src.isGp)) {
          final tmp = (this as UniCompiler).newGp32('@tmp');
          final mulBy = elementSize == 0 ? 0x01010101 : 0x00010001;
          if (src is X86Mem) {
            _emitX86(X86InstId.kMovzx,
                [tmp, src.withSize(elementSize == 0 ? 1 : 2)]);
            _emitX86(X86InstId.kImul, [tmp, tmp, Imm(mulBy)]);
          } else if (info.imm == 0x01) {
            // If it's guaranteed that the unused part of the register is
            // zero, we can multiply without zero extending.
            _emitX86(X86InstId.kImul,
                [tmp, _asGpX86(src as BaseReg, 32), Imm(mulBy)]);
          } else {
            _emitX86(X86InstId.kMovzx,
                [tmp, _asGpX86(src as BaseReg, elementSize == 0 ? 8 : 16)]);
            _emitX86(X86InstId.kImul, [tmp, tmp, Imm(mulBy)]);
          }
          _emitX86(X86InstId.kMovd, [dst, tmp]);
          _emitX86(X86InstId.kPshufd, [dst, dst, Imm(_shufImm4(0, 0, 0, 0))]);
          return;
        }

        if (hasSsse3 &&
            (elementSize == 0 ||
                (elementSize == 1 && _isSameVecX86(dst, src)))) {
          final predicate = _simdConstX86(
              elementSize == 0
                  ? VecConstTable.p_0000000000000000
                  : VecConstTable.p_0100010001000100,
              Bcst.kNA,
              dst);
          _sseMovX86(dst, src);
          _emitX86(X86InstId.kPshufb, [dst, predicate]);
          return;
        }

        if (elementSize == 0) {
          _sseMovX86(dst, src);
          _emitX86(X86InstId.kPunpcklbw, [dst, dst]);
          src = dst;
        }
        _emitX86(X86InstId.kPshuflw, [dst, src, Imm(_shufImm4(0, 0, 0, 0))]);
        _emitX86(X86InstId.kPshufd, [dst, dst, Imm(_shufImm4(0, 0, 0, 0))]);
        return;

      case UniOpVV.broadcastU32:
      case UniOpVV.broadcastF32:
        // Intrinsic - 32-bit broadcast is not available in SSE mode.
        if (src is BaseReg && src.isGp) {
          _emitX86(X86InstId.kMovd, [dst, _asGpX86(src, 32)]);
          src = dst;
        }
        if (src is BaseReg) {
          _emitX86(X86InstId.kPshufd, [dst, src, Imm(_shufImm4(0, 0, 0, 0))]);
        } else {
          _emitX86(X86InstId.kMovd, [dst, (src as X86Mem).withSize(4)]);
          _emitX86(X86InstId.kPshufd, [dst, dst, Imm(_shufImm4(0, 0, 0, 0))]);
        }
        return;

      case UniOpVV.broadcastU64:
      case UniOpVV.broadcastF64:
        // Intrinsic - 64-bit broadcast is not available in SSE mode.
        if (src is BaseReg && src.isGp) {
          _emitX86(X86InstId.kMovq, [dst, _asGpX86(src, 64)]);
          src = dst;
        }
        if (src is X86Mem) src = src.withSize(8);
        if (hasSse3) {
          _emitX86(X86InstId.kMovddup, [dst, src]);
        } else if (src is BaseReg) {
          _emitX86(X86InstId.kPshufd, [dst, src, Imm(_shufImm4(1, 0, 1, 0))]);
        } else {
          _emitX86(X86InstId.kMovq, [dst, src]);
          _emitX86(X86InstId.kPshufd, [dst, dst, Imm(_shufImm4(1, 0, 1, 0))]);
        }
        return;

      case UniOpVV.broadcastV128U32:
      case UniOpVV.broadcastV128U64:
      case UniOpVV.broadcastV128F32:
      case UniOpVV.broadcastV128F64:
        // 128-bit broadcast is like 128-bit mov as there are no wider
        // vectors.
        _sseMovX86(dst, src);
        return;

      case UniOpVV.absI8:
      case UniOpVV.absI16:
        // Native operation requires SSSE3, which is not supported by the
        // target.
        final sub = op == UniOpVV.absI8 ? X86InstId.kPsubb : X86InstId.kPsubw;
        final sel = op == UniOpVV.absI8 ? X86InstId.kPminub : X86InstId.kPmaxsw;
        if (_isSameVecX86(dst, src)) {
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _emitX86(X86InstId.kPxor, [tmp, tmp]);
          _emitX86(sub, [tmp, dst]);
          _emitX86(sel, [dst, tmp]);
        } else {
          _emitX86(X86InstId.kPxor, [dst, dst]);
          _emitX86(sub, [dst, src]);
          _emitX86(sel, [dst, src]);
        }
        return;

      case UniOpVV.absI32:
        // Native operation requires SSSE3, which is not supported by the
        // target.
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _emitX86(X86InstId.kMovaps, [tmp, src]);
        _emitX86(X86InstId.kPsrad, [tmp, Imm(31)]);
        _sseMovX86(dst, src);
        _emitX86(X86InstId.kPxor, [dst, tmp]);
        _emitX86(X86InstId.kPsubd, [dst, tmp]);
        return;

      case UniOpVV.absI64:
        // Native operation requires AVX512, which is not supported by the
        // target.
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _emitX86(X86InstId.kPshufd, [tmp, src, Imm(_shufImm4(3, 3, 1, 1))]);
        _emitX86(X86InstId.kPsrad, [tmp, Imm(31)]);
        _sseMovX86(dst, src);
        _emitX86(X86InstId.kPxor, [dst, tmp]);
        _emitX86(X86InstId.kPsubq, [dst, tmp]);
        return;

      case UniOpVV.notU32:
      case UniOpVV.notU64:
      case UniOpVV.notF32:
      case UniOpVV.notF64:
        _sseBitNotX86(dst, src);
        return;

      case UniOpVV.cvtI8ToI32:
      case UniOpVV.cvtU8ToU32:
        if (src is X86Mem) src = src.withSize(4);
        if (hasSse41) {
          _emitX86(instId, [dst, src]);
          return;
        }
        if (src is X86Mem) {
          _emitX86(X86InstId.kMovd, [dst, src]);
          src = dst;
        }
        _sseIntWidenX86(dst, src as BaseReg,
            op == UniOpVV.cvtI8ToI32 ? _kI8ToI32 : _kU8ToU32);
        return;

      case UniOpVV.cvtI8HiToI16:
      case UniOpVV.cvtU8HiToU16:
      case UniOpVV.cvtI16HiToI32:
      case UniOpVV.cvtU16HiToU32:
      case UniOpVV.cvtI32HiToI64:
      case UniOpVV.cvtU32HiToU64:
      case UniOpVV.cvtI8LoToI16:
      case UniOpVV.cvtU8LoToU16:
      case UniOpVV.cvtI16LoToI32:
      case UniOpVV.cvtU16LoToU32:
      case UniOpVV.cvtI32LoToI64:
      case UniOpVV.cvtU32LoToU64:
        var cvtOp = op;
        var cvtInstId = instId;
        final unsignedHi = op == UniOpVV.cvtU8HiToU16 ||
            op == UniOpVV.cvtU16HiToU32 ||
            op == UniOpVV.cvtU32HiToU64;
        final hi = unsignedHi ||
            op == UniOpVV.cvtI8HiToI16 ||
            op == UniOpVV.cvtI16HiToI32 ||
            op == UniOpVV.cvtI32HiToI64;

        if (unsignedHi && src is BaseReg && dst.id != src.id && hasSse41) {
          _emitX86(X86InstId.kPshufd, [dst, src, Imm(_shufImm4(3, 2, 3, 2))]);
          _emitX86(instId, [dst, dst]);
          return;
        }

        if (hi) {
          if (src is BaseReg) {
            _sseMovX86(dst, src);
            final zero =
                _simdConstX86(VecConstTable.p_0000000000000000, Bcst.kNA, dst);
            switch (op) {
              case UniOpVV.cvtI8HiToI16:
                _emitX86(X86InstId.kPunpckhbw, [dst, dst]);
                _emitX86(X86InstId.kPsraw, [dst, Imm(8)]);
              case UniOpVV.cvtU8HiToU16:
                _emitX86(X86InstId.kPunpckhbw, [dst, zero]);
              case UniOpVV.cvtI16HiToI32:
                _emitX86(X86InstId.kPunpckhwd, [dst, dst]);
                _emitX86(X86InstId.kPsrad, [dst, Imm(16)]);
              case UniOpVV.cvtU16HiToU32:
                _emitX86(X86InstId.kPunpckhwd, [dst, zero]);
              case UniOpVV.cvtI32HiToI64:
                final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
                _sseMovX86(tmp, dst);
                _emitX86(X86InstId.kPsrad, [tmp, Imm(31)]);
                _emitX86(X86InstId.kPunpckhdq, [dst, tmp]);
              default:
                _emitX86(X86InstId.kPunpckhdq, [dst, zero]);
            }
            return;
          }
          // The high half in memory is the low half of the next 8 bytes.
          final m = src as X86Mem;
          src = m.withDisplacement(m.displacement + 8);
          cvtOp = UniOpVV.values[op.index - 1];
          cvtInstId = kX86OpcodeInfo2v[cvtOp.index].sseInstId;
        }

        if (src is X86Mem) src = src.withSize(8);
        if (hasSse41) {
          _emitX86(cvtInstId, [dst, src]);
          return;
        }
        if (src is X86Mem) {
          _emitX86(X86InstId.kMovq, [dst, src]);
          src = dst;
        }
        final cvt = switch (cvtOp) {
          UniOpVV.cvtI8LoToI16 => _kI8ToI16,
          UniOpVV.cvtU8LoToU16 => _kU8ToU16,
          UniOpVV.cvtI16LoToI32 => _kI16ToI32,
          UniOpVV.cvtU16LoToU32 => _kU16ToU32,
          UniOpVV.cvtI32LoToI64 => _kI32ToI64,
          _ => _kU32ToU64,
        };
        _sseIntWidenX86(dst, src as BaseReg, cvt);
        return;

      case UniOpVV.truncF32:
      case UniOpVV.truncF64:
      case UniOpVV.floorF32:
      case UniOpVV.floorF64:
      case UniOpVV.ceilF32:
      case UniOpVV.ceilF64:
      case UniOpVV.roundEvenF32:
      case UniOpVV.roundEvenF64:
      case UniOpVV.truncF32S:
      case UniOpVV.truncF64S:
      case UniOpVV.floorF32S:
      case UniOpVV.floorF64S:
      case UniOpVV.ceilF32S:
      case UniOpVV.ceilF64S:
      case UniOpVV.roundEvenF32S:
      case UniOpVV.roundEvenF64S:
        // Native operation requires SSE4.1.
        if (hasSse41) {
          if (!_isScalarFm(fm)) {
            _emitX86(instId, [dst, src, Imm(info.imm)]);
          } else {
            _sseFmovX86(dst, src, fm);
            _emitX86(instId, [dst, dst, Imm(info.imm)]);
          }
          return;
        }
        _sseRoundX86(dst, src, fm, info.imm & 0x7);
        return;

      case UniOpVV.roundHalfAwayF32S:
      case UniOpVV.roundHalfAwayF64S:
      case UniOpVV.roundHalfAwayF32:
      case UniOpVV.roundHalfAwayF64:
        final fi = _sseFloatInst[fm];
        final half = _fopHalfMinus1UlpX86(dst, fm);
        final msb = _fopMsbBitX86(dst, fm);
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _sseFmovX86(dst, src, fm);
        _sseMovX86(tmp, msb);
        _emitX86(fi.fand, [tmp, dst]);
        _emitX86(fi.for_, [tmp, half]);
        _emitX86(fi.fadd, [dst, tmp]);
        _sseRoundX86(dst, dst, fm, info.imm & 0x7);
        return;

      case UniOpVV.roundHalfUpF32S:
      case UniOpVV.roundHalfUpF64S:
      case UniOpVV.roundHalfUpF32:
      case UniOpVV.roundHalfUpF64:
        final fi = _sseFloatInst[fm];
        final half = _fopHalfMinus1UlpX86(dst, fm);
        _sseFmovX86(dst, src, fm);
        _emitX86(fi.fadd, [dst, half]);
        _sseRoundX86(dst, dst, fm, info.imm & 0x7);
        return;

      case UniOpVV.absF32S:
      case UniOpVV.absF64S:
      case UniOpVV.absF32:
      case UniOpVV.absF64:
      case UniOpVV.negF32S:
      case UniOpVV.negF64S:
      case UniOpVV.negF32:
      case UniOpVV.negF64:
        final msk =
            _simdConstX86(_absNegMaskX86(op), _bcstOf(info.broadcastSize), dst);
        _sseFmovX86(dst, src, fm);
        _emitX86(instId, [dst, msk]);
        return;

      case UniOpVV.rcpF32:
      case UniOpVV.rcpF64:
        final f32 = op == UniOpVV.rcpF32;
        final one = _simdConstX86(
            f32 ? VecConstTable.f32_1 : VecConstTable.f64_1,
            f32 ? Bcst.k32 : Bcst.k64,
            dst);
        final div = f32 ? X86InstId.kDivps : X86InstId.kDivpd;
        if (_isSameVecX86(dst, src)) {
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _sseMovX86(tmp, one);
          _emitX86(div, [tmp, src]);
          _sseMovX86(dst, tmp);
        } else {
          _sseMovX86(dst, one);
          _emitX86(div, [dst, src]);
        }
        return;

      case UniOpVV.sqrtF32S:
      case UniOpVV.sqrtF64S:
        _sseMovX86(dst, src);
        _emitX86(instId, [dst, dst]);
        return;

      case UniOpVV.cvtF32ToF64S:
      case UniOpVV.cvtF64ToF32S:
        if (_isSameVecX86(dst, src)) {
          _emitX86(instId, [dst, src]);
        } else {
          _emitX86(X86InstId.kXorps, [dst, dst]);
          _emitX86(instId, [dst, src]);
        }
        return;

      case UniOpVV.cvtF32HiToF64:
      case UniOpVV.cvtI32HiToF64:
        if (src is X86Mem) {
          _emitX86(instId, [dst, src.withDisplacement(src.displacement + 8)]);
        } else {
          if (_isSameVecX86(dst, src)) {
            _emitX86(X86InstId.kMovhlps, [dst, src]);
          } else {
            _emitX86(X86InstId.kPshufd, [dst, src, Imm(_shufImm4(3, 2, 3, 2))]);
          }
          _emitX86(instId, [dst, dst]);
        }
        return;

      case UniOpVV.cvtF64ToF32Hi:
      case UniOpVV.cvtTruncF64ToI32Hi:
      case UniOpVV.cvtRoundF64ToI32Hi:
        final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
        if (src is X86Mem) src = src.withSize(dst.size);
        _emitX86(instId, [tmp, src]);
        _emitX86(X86InstId.kUnpcklpd, [dst, tmp]);
        return;

      default:
        throw _requiresX86(op, info.sseExt.name.substring(1));
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

  /// `dst = op(dst, src, imm)` in legacy or VEX form.
  void _sseOpImmX86(int legacyId, BaseReg dst, Operand src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(_vexIdX86(legacyId), [dst, dst, src, Imm(imm)]));
    } else {
      cc.addNode(InstNode(legacyId, [dst, src, Imm(imm)]));
    }
  }

  Operand _constX86(VecConst c) =>
      (this as UniCompiler).simdConst(c, Bcst.kNA_Unique, VecWidth.k128);

  // Port of `sse_float_inst` / `sse_fmov()` / `sse_round()`
  // (unicompiler_x86.cpp). Float modes: 0 = F32S, 1 = F64S, 2 = F32V,
  // 3 = F64V.
  static const _sseFloatInst = [
    _X86FloatInst(
        X86InstId.kMovss,
        X86InstId.kAndps,
        X86InstId.kOrps,
        X86InstId.kXorps,
        X86InstId.kAndnps,
        X86InstId.kAddss,
        X86InstId.kSubss,
        X86InstId.kCmpss,
        X86InstId.kRoundss,
        X86InstId.kPsrld,
        X86InstId.kPslld,
        X86InstId.kMovups,
        X86InstId.kMulss,
        X86InstId.kDivss),
    _X86FloatInst(
        X86InstId.kMovsd,
        X86InstId.kAndpd,
        X86InstId.kOrpd,
        X86InstId.kXorpd,
        X86InstId.kAndnpd,
        X86InstId.kAddsd,
        X86InstId.kSubsd,
        X86InstId.kCmpsd,
        X86InstId.kRoundsd,
        X86InstId.kPsrlq,
        X86InstId.kPsllq,
        X86InstId.kMovups,
        X86InstId.kMulsd,
        X86InstId.kDivsd),
    _X86FloatInst(
        X86InstId.kMovaps,
        X86InstId.kAndps,
        X86InstId.kOrps,
        X86InstId.kXorps,
        X86InstId.kAndnps,
        X86InstId.kAddps,
        X86InstId.kSubps,
        X86InstId.kCmpps,
        X86InstId.kRoundps,
        X86InstId.kPsrld,
        X86InstId.kPslld,
        X86InstId.kMovups,
        X86InstId.kMulps,
        X86InstId.kDivps),
    _X86FloatInst(
        X86InstId.kMovaps,
        X86InstId.kAndpd,
        X86InstId.kOrpd,
        X86InstId.kXorpd,
        X86InstId.kAndnpd,
        X86InstId.kAddpd,
        X86InstId.kSubpd,
        X86InstId.kCmppd,
        X86InstId.kRoundpd,
        X86InstId.kPsrlq,
        X86InstId.kPsllq,
        X86InstId.kMovups,
        X86InstId.kMulpd,
        X86InstId.kDivpd),
  ];

  static bool _isF32Fm(int fm) => fm == 0 || fm == 2;
  static bool _isScalarFm(int fm) => fm < 2;

  void _emitX86(int id, List<Operand> ops) => cc.addNode(InstNode(id, ops));

  /// `sse_fmov()`.
  void _sseFmovX86(BaseReg dst, Operand src, int fm) {
    if (src is BaseReg) {
      if (dst.id != src.id) _emitX86(X86InstId.kMovaps, [dst, src]);
    } else if (_isScalarFm(fm)) {
      _emitX86(_sseFloatInst[fm].fmovs, [dst, src]);
    } else {
      _emitX86(_sseFloatInst[fm].fmovu, [dst, src]);
    }
  }

  /// `sse_round()`: [roundMode] is x86 RoundImm (0 nearest, 1 down, 2 up,
  /// 3 trunc).
  void _sseRoundX86(BaseReg dst, Operand src, int fm, int roundMode) {
    final fi = _sseFloatInst[fm];
    final isF32 = _isF32Fm(fm);

    if (hasSse41) {
      _emitX86(fi.fround, [dst, src, Imm(roundMode | 8)]);
      return;
    }

    // Deviation from upstream (proven by executing upstream's sse_round with
    // SSE2-only features: ceil(-0.25), trunc(-0.25) and round(-0.25) give
    // +0.0 while its own SSE4.1 path and IEEE give -0.0). Rounding never
    // changes the sign, so the sign of the input is OR-ed into the result.
    final sign = _copyVecX86(src);
    _emitX86(_sseFloatInst[fm].fand, [
      sign,
      _constX86(isF32
          ? VecConstTable.p_8000000080000000
          : VecConstTable.p_8000000000000000)
    ]);
    _sseRoundUpstreamX86(dst, src, fm, roundMode);
    _emitX86(_sseFloatInst[fm].for_, [dst, sign]);
  }

  /// `sse_round()` without SSE4.1, as in upstream.
  void _sseRoundUpstreamX86(BaseReg dst, Operand src, int fm, int roundMode) {
    final fi = _sseFloatInst[fm];
    final isF32 = _isF32Fm(fm);
    const kLT = 1, kNLT = 5, kNLE = 6;
    final maxn = _constX86(
        isF32 ? VecConstTable.f32_round_magic : VecConstTable.f64_round_magic);
    final t1 = _tmpVecX86();
    final t2 = _tmpVecX86();
    final t3 = _tmpVecX86();

    if (roundMode == 3 && (fm == 0 || fm == 1)) {
      final uc = this as UniCompiler;
      final r = fm == 0 ? uc.newGp32('@gp_tmp') : uc.newGp64('@gp_tmp');
      final msb = _constX86(fm == 0
          ? VecConstTable.p_8000000080000000
          : VecConstTable.p_8000000000000000);
      _sseFmovX86(dst, src, fm);
      _emitX86(fm == 0 ? X86InstId.kCvttss2si : X86InstId.kCvttsd2si, [r, dst]);
      _emitX86(fi.fmova, [t2, msb]);
      _emitX86(fi.fandn, [t2, dst]);
      _emitX86(fi.fxor, [t1, t1]);
      _emitX86(fm == 0 ? X86InstId.kCvtsi2ss : X86InstId.kCvtsi2sd, [t1, r]);
      _emitX86(fi.fcmp, [t2, maxn, Imm(kLT)]);
      _emitX86(fi.fand, [t1, t2]);
      _emitX86(fi.fandn, [t2, dst]);
      _emitX86(fi.for_, [t2, t1]);
      _emitX86(fi.fmovs, [dst, t2]);
      return;
    }

    if (roundMode == 0) {
      _sseFmovX86(dst, src, fm);
      _emitX86(fi.fmova, [t3, dst]);
      _emitX86(fi.psrl, [t3, Imm(isF32 ? 31 : 63)]);
      _emitX86(fi.psll, [t3, Imm(isF32 ? 23 : 52)]);
      _emitX86(isF32 ? X86InstId.kPaddd : X86InstId.kPaddq, [t3, maxn]);
      _emitX86(fi.fmova, [t1, dst]);
      _emitX86(fi.fcmp, [t1, t3, Imm(kLT)]);
      _emitX86(fi.fand, [t1, t3]);
      _emitX86(fi.fadd, [dst, t1]);
      _emitX86(fi.fsub, [dst, t1]);
      return;
    }

    final one = _constX86(isF32 ? VecConstTable.f32_1 : VecConstTable.f64_1);

    if (roundMode == 3) {
      if (fm == 2) {
        final msb = _constX86(VecConstTable.p_8000000080000000);
        _sseFmovX86(dst, src, fm);
        _emitX86(X86InstId.kCvttps2dq, [t1, dst]);
        _emitX86(fi.fmova, [t2, msb]);
        _emitX86(fi.fandn, [t2, dst]);
        _emitX86(X86InstId.kCvtdq2ps, [t1, t1]);
        _emitX86(fi.fcmp, [t2, maxn, Imm(kLT)]);
        _emitX86(fi.fand, [t1, t2]);
        _emitX86(fi.fandn, [t2, dst]);
        _emitX86(fi.for_, [t2, t1]);
        _emitX86(fi.fmova, [dst, t2]);
      } else {
        final msb = _constX86(VecConstTable.p_8000000000000000);
        _sseFmovX86(dst, src, fm);
        _emitX86(fi.fmova, [t3, msb]);
        _emitX86(fi.fandn, [t3, dst]);
        _emitX86(fi.fmova, [t2, t3]);
        _emitX86(fi.fcmp, [t2, maxn, Imm(kLT)]);
        _emitX86(fi.fand, [t2, maxn]);
        _emitX86(fi.fmova, [t1, t3]);
        _emitX86(fi.fadd, [t1, t2]);
        _emitX86(fi.fsub, [t1, t2]);
        _emitX86(fi.fcmp, [t3, t1, Imm(kLT)]);
        _emitX86(fi.fand, [t3, one]);
        _emitX86(fi.fsub, [t1, t3]);
        _emitX86(fi.fand, [dst, msb]);
        _emitX86(fi.for_, [dst, t1]);
      }
      return;
    }

    // Round down / up: adding and subtracting the magic number rounds to
    // nearest, so correct by one where needed.
    final correction = roundMode == 1 ? fi.fsub : fi.fadd;
    final predicate = roundMode == 1 ? kLT : kNLE;
    _sseFmovX86(dst, src, fm);
    _emitX86(fi.fmova, [t3, dst]);
    _emitX86(fi.psrl, [t3, Imm(isF32 ? 31 : 63)]);
    _emitX86(fi.psll, [t3, Imm(isF32 ? 23 : 52)]);
    _emitX86(isF32 ? X86InstId.kPaddd : X86InstId.kPaddq, [t3, maxn]);
    _emitX86(fi.fmova, [t1, dst]);
    _emitX86(fi.fmova, [t2, dst]);
    _emitX86(fi.fadd, [t2, t3]);
    _emitX86(fi.fsub, [t2, t3]);
    _emitX86(fi.fcmp, [t1, t3, Imm(kNLT)]);
    _emitX86(fi.fmova, [t3, dst]);
    _emitX86(fi.fcmp, [t3, t2, Imm(predicate)]);
    _emitX86(fi.fand, [t3, one]);
    _emitX86(fi.fand, [dst, t1]);
    _emitX86(correction, [t2, t3]);
    _emitX86(fi.fandn, [t1, t2]);
    _emitX86(fi.for_, [dst, t1]);
  }

  /// Port of the kLoadInsert* cases of `UniCompiler::emit_vm()`
  /// (unicompiler_x86.cpp). Only 64-bit targets are supported.
  void _loadInsertX86(UniOpVM op, BaseReg dst, X86Mem src, int idx) {
    if (hasAvx) {
      switch (op) {
        case UniOpVM.loadInsertU8:
        case UniOpVM.loadInsertU16:
        case UniOpVM.loadInsertU32:
        case UniOpVM.loadInsertF32:
        case UniOpVM.loadInsertU64:
          final (id, size) = switch (op) {
            UniOpVM.loadInsertU8 => (X86InstId.kVpinsrb, 1),
            UniOpVM.loadInsertU16 => (X86InstId.kVpinsrw, 2),
            UniOpVM.loadInsertU64 => (X86InstId.kVpinsrq, 8),
            _ => (X86InstId.kVpinsrd, 4),
          };
          cc.addNode(InstNode(id, [dst, dst, src.withSize(size), Imm(idx)]));
        case UniOpVM.loadInsertF32x2:
          cc.addNode(InstNode(
              idx == 0 ? X86InstId.kVmovlps : X86InstId.kVmovhps,
              [dst, dst, src.withSize(8)]));
        case UniOpVM.loadInsertF64:
          cc.addNode(InstNode(
              idx == 0 ? X86InstId.kVmovlpd : X86InstId.kVmovhpd,
              [dst, dst, src.withSize(8)]));
        default:
          throw UnimplementedError('_loadInsertX86: $op');
      }
      return;
    }

    switch (op) {
      case UniOpVM.loadInsertU16:
        // Upstream emits `pinsrw dst, dst, idx` here, which looks like a bug;
        // the inserted value is the memory operand.
        cc.addNode(
            InstNode(X86InstId.kPinsrw, [dst, src.withSize(2), Imm(idx)]));
      case UniOpVM.loadInsertF32:
      case UniOpVM.loadInsertU8:
      case UniOpVM.loadInsertU32:
      case UniOpVM.loadInsertU64:
        final u = op == UniOpVM.loadInsertF32 ? UniOpVM.loadInsertU32 : op;
        if (hasSse41) {
          final (id, size) = switch (u) {
            UniOpVM.loadInsertU8 => (X86InstId.kPinsrb, 1),
            UniOpVM.loadInsertU64 => (X86InstId.kPinsrq, 8),
            _ => (X86InstId.kPinsrd, 4),
          };
          cc.addNode(InstNode(id, [dst, src.withSize(size), Imm(idx)]));
          return;
        }
        if (u == UniOpVM.loadInsertU8) {
          // Upstream merges the byte through a high-byte register (AH...);
          // those cannot be allocated freely, so merge with shifts instead.
          final uc = this as UniCompiler;
          final tmp = uc.newGp32('@tmp');
          cc.addNode(InstNode(X86InstId.kPextrw, [tmp, dst, Imm(idx ~/ 2)]));
          final byte = uc.newGp32('@byte');
          cc.addNode(InstNode(X86InstId.kMovzx, [byte, src.withSize(1)]));
          if (idx & 1 != 0) {
            cc.addNode(InstNode(X86InstId.kShl, [byte, Imm(8)]));
            cc.addNode(InstNode(X86InstId.kAnd, [tmp, Imm(0xFF)]));
          } else {
            cc.addNode(InstNode(X86InstId.kAnd, [tmp, Imm(0xFF00)]));
          }
          cc.addNode(InstNode(X86InstId.kOr, [tmp, byte]));
          cc.addNode(InstNode(X86InstId.kPinsrw, [dst, tmp, Imm(idx ~/ 2)]));
          return;
        }
        if (u == UniOpVM.loadInsertU32) {
          if (idx == 0) {
            final tmp = _tmpVecX86();
            cc.addNode(InstNode(X86InstId.kMovd, [tmp, src.withSize(4)]));
            cc.addNode(InstNode(X86InstId.kMovss, [dst, tmp]));
          } else {
            cc.addNode(InstNode(
                X86InstId.kPinsrw, [dst, src.withSize(2), Imm(idx * 2)]));
            cc.addNode(InstNode(X86InstId.kPinsrw, [
              dst,
              X86Mem(
                  base: src.base,
                  index: src.index,
                  scale: src.scale,
                  displacement: src.displacement + 2,
                  size: 2,
                  segment: src.segment,
                  label: src.label),
              Imm(idx * 2 + 1)
            ]));
          }
          return;
        }
        cc.addNode(InstNode(idx == 0 ? X86InstId.kMovlpd : X86InstId.kMovhpd,
            [dst, src.withSize(8)]));
      case UniOpVM.loadInsertF32x2:
        cc.addNode(InstNode(idx == 0 ? X86InstId.kMovlps : X86InstId.kMovhps,
            [dst, src.withSize(8)]));
      case UniOpVM.loadInsertF64:
        cc.addNode(InstNode(idx == 0 ? X86InstId.kMovlpd : X86InstId.kMovhpd,
            [dst, src.withSize(8)]));
      default:
        throw UnimplementedError('_loadInsertX86: $op');
    }
  }

  /// Port of the kStoreExtract* cases of `UniCompiler::emit_mv()`
  /// (unicompiler_x86.cpp). Only 64-bit targets are supported.
  void _storeExtractX86(UniOpMV op, X86Mem dst, BaseReg src, int idx) {
    if (op == UniOpMV.storeExtractU32 && idx == 0) {
      cc.addNode(InstNode(
          hasAvx ? X86InstId.kVmovd : X86InstId.kMovd, [dst.withSize(4), src]));
      return;
    }
    if (op == UniOpMV.storeExtractU64 && idx == 0) {
      cc.addNode(InstNode(
          hasAvx ? X86InstId.kVmovq : X86InstId.kMovq, [dst.withSize(8), src]));
      return;
    }
    final (int pextr, int vpextr, int size) = switch (op) {
      UniOpMV.storeExtractU16 => (X86InstId.kPextrw, X86InstId.kVpextrw, 2),
      UniOpMV.storeExtractU32 => (X86InstId.kPextrd, X86InstId.kVpextrd, 4),
      _ => (X86InstId.kPextrq, X86InstId.kVpextrq, 8),
    };
    if (hasAvx) {
      cc.addNode(InstNode(vpextr, [dst.withSize(size), src, Imm(idx)]));
      return;
    }
    if (op == UniOpMV.storeExtractU64 && idx == 1) {
      cc.addNode(InstNode(X86InstId.kMovhps, [dst.withSize(8), src]));
      return;
    }
    if (hasSse41) {
      cc.addNode(InstNode(pextr, [dst.withSize(size), src, Imm(idx)]));
      return;
    }
    // No SSE4.1: PEXTRW to memory and PEXTRD do not exist in SSE2.
    if (op == UniOpMV.storeExtractU16) {
      final tmp = (this as UniCompiler).newGp32('@pextrw_tmp');
      cc.addNode(InstNode(X86InstId.kPextrw, [tmp, src, Imm(idx)]));
      cc.addNode(
          InstNode(X86InstId.kMov, [dst.withSize(2), (tmp as X86Gp).as16]));
      return;
    }
    if (op == UniOpMV.storeExtractU32) {
      final tmp = _tmpVecX86();
      cc.addNode(InstNode(X86InstId.kPshufd,
          [tmp, src, Imm(idx | (idx << 2) | (idx << 4) | (idx << 6))]));
      cc.addNode(InstNode(X86InstId.kMovd, [dst.withSize(4), tmp]));
      return;
    }
    throw UnimplementedError('_storeExtractX86: $op');
  }

  /// Error for an operation whose x86 lowering needs a CPU extension that is
  /// not enabled in the compiler's [CpuFeatures] (no SSE2 fallback yet).
  UnsupportedError _requiresX86(Object op, String ext) => UnsupportedError(
      'UniCompiler x86: $op requires $ext, which is not enabled in the '
      'CpuFeatures given to UniCompiler');

  // ---------------------------------------------------------------------------
  // Port of emit_3v() and its helpers (ujit/unicompiler_x86.cpp).
  //
  // AVX-512 is never enabled for the UJIT (see _updateX86Features), so the
  // EVEX-only branches of upstream (k-register compares, vpternlog, 512-bit
  // moves) are not part of the port.
  // ---------------------------------------------------------------------------

  static bool _isSameVecX86(BaseReg a, Operand b) =>
      b is BaseReg && b.id == a.id;

  /// `Vec::clone_as()`: the register [r] with the width of [like].
  static BaseReg _cloneAsX86(BaseReg r, BaseReg like) {
    if (like is X86Ymm) return X86Ymm(r.id);
    if (like is X86Zmm) return X86Zmm(r.id);
    return X86Xmm(r.id);
  }

  BaseReg _newSimilarRegX86(BaseReg ref, [String? name]) =>
      newVecWithWidth(VecWidthUtils.vecWidthOf(ref), name);

  Operand _simdConstX86(VecConst c, Bcst bcst, BaseReg similarTo) =>
      (this as UniCompiler).simdConstSimilarTo(c, bcst, similarTo);

  BaseReg _simdVecConstX86(VecConst c, Bcst bcst, BaseReg similarTo) =>
      (this as UniCompiler)
          .simdVecConst(c, bcst, VecWidthUtils.vecWidthOf(similarTo));

  /// `UniCompiler_load_new()` (memory operands carry no broadcast here).
  BaseReg _loadNewX86(BaseReg ref, Operand mem) {
    final vec = _newSimilarRegX86(ref, '@vec_m');
    final m = (mem as X86Mem).withSize(vec.size);
    _emitX86(hasAvx ? X86InstId.kVmovdqu : X86InstId.kMovdqu, [vec, m]);
    return vec;
  }

  /// `sse_mov()`.
  void _sseMovX86(BaseReg dst, Operand src) {
    if (src is! BaseReg) {
      _emitX86(X86InstId.kMovups, [dst, src]);
    } else if (dst.id != src.id) {
      _emitX86(X86InstId.kMovaps, [dst, src]);
    }
  }

  /// `sse_bit_not()`.
  void _sseBitNotX86(BaseReg dst, Operand src) {
    _sseMovX86(dst, src);
    final ones = _simdConstX86(VecConstTable.p_FFFFFFFFFFFFFFFF, Bcst.k32, dst);
    _emitX86(X86InstId.kPxor, [dst, ones]);
  }

  static VecConst _msbMaskX86(int elementSize) => switch (elementSize) {
        0 => VecConstTable.p_8080808080808080,
        1 => VecConstTable.p_8000800080008000,
        2 => VecConstTable.p_8000000080000000,
        _ => VecConstTable.p_8000000000000000,
      };

  /// `sse_msb_flip()`.
  void _sseMsbFlipX86(BaseReg dst, Operand src, int elementSize) {
    final msk = _simdConstX86(_msbMaskX86(elementSize), Bcst.kNA, dst);
    _sseMovX86(dst, src);
    _emitX86(X86InstId.kPxor, [dst, msk]);
  }

  /// `sse_cmp_gt_i64()`.
  void _sseCmpGtI64X86(BaseReg dst, Operand a, Operand b) {
    if (hasSse42) {
      if (_isSameVecX86(dst, a)) {
        _emitX86(X86InstId.kPcmpgtq, [dst, b]);
      } else {
        var second = b;
        if (_isSameVecX86(dst, b)) {
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _sseMovX86(tmp, b);
          second = tmp;
        }
        _sseMovX86(dst, a);
        _emitX86(X86InstId.kPcmpgtq, [dst, second]);
      }
      return;
    }

    final tmp1 = _newSimilarRegX86(dst, '@tmp1');
    final tmp2 = _newSimilarRegX86(dst, '@tmp2');
    _emitX86(X86InstId.kMovdqa, [tmp1, a]);
    _emitX86(X86InstId.kMovdqa, [tmp2, b]);
    _emitX86(X86InstId.kPcmpeqd, [tmp1, tmp2]);
    _emitX86(X86InstId.kPsubq, [tmp2, a]);
    _emitX86(X86InstId.kPand, [tmp1, tmp2]);

    if (!_isSameVecX86(dst, b)) {
      _sseMovX86(dst, a);
      _emitX86(X86InstId.kPcmpgtd, [dst, b]);
      _emitX86(X86InstId.kPor, [dst, tmp1]);
      _emitX86(X86InstId.kPshufd, [dst, dst, Imm(_shufImm4(3, 3, 1, 1))]);
    } else {
      _sseMovX86(tmp2, a);
      _emitX86(X86InstId.kPcmpgtd, [tmp2, b]);
      _emitX86(X86InstId.kPor, [tmp2, tmp1]);
      _emitX86(X86InstId.kPshufd, [dst, tmp2, Imm(_shufImm4(3, 3, 1, 1))]);
    }
  }

  /// `sse_cmp_gt_u64()`.
  void _sseCmpGtU64X86(BaseReg dst, Operand a, Operand b) {
    if (hasSse42) {
      final msk =
          _simdConstX86(VecConstTable.p_8000000000000000, Bcst.k64, dst);
      final tmp = _newSimilarRegX86(dst, '@tmp');
      if (_isSameVecX86(dst, a)) {
        _sseMovX86(tmp, msk);
        _emitX86(X86InstId.kPxor, [dst, tmp]);
        _emitX86(X86InstId.kPxor, [tmp, b]);
        _emitX86(X86InstId.kPcmpgtq, [dst, tmp]);
      } else {
        _sseMovX86(tmp, b);
        _sseMovX86(dst, a);
        _emitX86(X86InstId.kPxor, [dst, msk]);
        _emitX86(X86InstId.kPxor, [tmp, msk]);
        _emitX86(X86InstId.kPcmpgtq, [dst, tmp]);
      }
      return;
    }

    final tmp1 = _newSimilarRegX86(dst, '@tmp1');
    final tmp2 = _newSimilarRegX86(dst, '@tmp2');
    final tmp3 = _newSimilarRegX86(dst, '@tmp3');
    _sseMovX86(tmp1, b); // tmp1 = b
    _sseMovX86(tmp2, a); // tmp2 = a
    _emitX86(X86InstId.kMovaps, [tmp3, tmp1]); // tmp3 = b
    _emitX86(X86InstId.kPsubq, [tmp3, tmp2]); // tmp3 = b - a
    _emitX86(X86InstId.kPxor, [tmp2, tmp1]); // tmp2 = b ^ a
    _emitX86(X86InstId.kPandn, [tmp1, a]); // tmp1 = ~b & a
    _emitX86(X86InstId.kPandn, [tmp2, tmp3]); // tmp2 = ~(b ^ a) & (b - a)
    _emitX86(X86InstId.kPor, [tmp1, tmp2]);
    _emitX86(X86InstId.kPsrad, [tmp1, Imm(31)]);
    _emitX86(X86InstId.kPshufd, [dst, tmp1, Imm(_shufImm4(3, 3, 1, 1))]);
  }

  /// `sse_select()`: `dst = msk ? a : b` (bitwise); clobbers [msk].
  void _sseSelectX86(BaseReg dst, BaseReg a, Operand b, BaseReg msk) {
    _sseMovX86(dst, a);
    _emitX86(X86InstId.kPand, [dst, msk]);
    _emitX86(X86InstId.kPandn, [msk, b]);
    _emitX86(X86InstId.kPor, [dst, msk]);
  }

  /// `avx_mov()`.
  void _avxMovX86(BaseReg dst, Operand src) => _emitX86(
      src is BaseReg ? X86InstId.kVmovdqa : X86InstId.kVmovdqu, [dst, src]);

  /// `avx_zero()`.
  void _avxZeroX86(BaseReg dst) {
    final x = X86Xmm(dst.id);
    _emitX86(X86InstId.kVpxor, [x, x, x]);
  }

  /// `avx_ones()`.
  void _avxOnesX86(BaseReg dst) =>
      _emitX86(X86InstId.kVpcmpeqb, [dst, dst, dst]);

  /// `avx_bit_not()`.
  void _avxBitNotX86(BaseReg dst, Operand src) {
    final ones = _simdConstX86(VecConstTable.p_FFFFFFFFFFFFFFFF, Bcst.k32, dst);
    if (src is! BaseReg) {
      if (ones is BaseReg) {
        _emitX86(X86InstId.kVpxor, [dst, ones, src]);
      } else {
        _avxMovX86(dst, src);
        _emitX86(X86InstId.kVpxor, [dst, dst, ones]);
      }
    } else {
      _emitX86(X86InstId.kVpxor, [dst, src, ones]);
    }
  }

  /// `avx_isign_flip()`.
  void _avxIsignFlipX86(BaseReg dst, Operand src, int elementSize) {
    final bcst = switch (elementSize) {
      2 => Bcst.k32,
      3 => Bcst.k64,
      _ => Bcst.kNA,
    };
    final msk = _simdConstX86(_msbMaskX86(elementSize), bcst, dst);
    if (src is BaseReg) {
      _emitX86(X86InstId.kVpxor, [dst, src, msk]);
    } else if (msk is BaseReg) {
      _emitX86(X86InstId.kVpxor, [dst, msk, src]);
    } else {
      _avxMovX86(dst, src);
      _emitX86(X86InstId.kVpxor, [dst, dst, msk]);
    }
  }

  /// `x86::shuffle_imm(a, b, c, d)`.
  static int _shufImm4(int a, int b, int c, int d) =>
      (a << 6) | (b << 4) | (c << 2) | d;

  /// `shuf_imm2_from_swizzle_with_width()` for `swizzle(b, a)`.
  static int _shufImm2WithWidthX86(int b, int a, BaseReg dst) {
    const multipliers = [0x1, 0x5, 0x55];
    final imm = ((b & 1) << 1) | (a & 1);
    return imm * multipliers[VecWidthUtils.vecWidthOf(dst).index];
  }

  /// `cmp_min_max` tables: (peq, pgt, pmin, pmax) per UniOp element type
  /// (I8, U8, I16, U16, I32, U32, I64, U64).
  static const _sseCmpMinMax = [
    [
      X86InstId.kPcmpeqb,
      X86InstId.kPcmpgtb,
      X86InstId.kPminsb,
      X86InstId.kPmaxsb
    ],
    [
      X86InstId.kPcmpeqb,
      X86InstId.kPcmpgtb,
      X86InstId.kPminub,
      X86InstId.kPmaxub
    ],
    [
      X86InstId.kPcmpeqw,
      X86InstId.kPcmpgtw,
      X86InstId.kPminsw,
      X86InstId.kPmaxsw
    ],
    [
      X86InstId.kPcmpeqw,
      X86InstId.kPcmpgtw,
      X86InstId.kPminuw,
      X86InstId.kPmaxuw
    ],
    [
      X86InstId.kPcmpeqd,
      X86InstId.kPcmpgtd,
      X86InstId.kPminsd,
      X86InstId.kPmaxsd
    ],
    [
      X86InstId.kPcmpeqd,
      X86InstId.kPcmpgtd,
      X86InstId.kPminud,
      X86InstId.kPmaxud
    ],
    [X86InstId.kPcmpeqq, X86InstId.kPcmpgtq, -1, -1],
    [X86InstId.kPcmpeqq, X86InstId.kPcmpgtq, -1, -1],
  ];

  static const _avxCmpMinMax = [
    [
      X86InstId.kVpcmpeqb,
      X86InstId.kVpcmpgtb,
      X86InstId.kVpminsb,
      X86InstId.kVpmaxsb
    ],
    [
      X86InstId.kVpcmpeqb,
      X86InstId.kVpcmpgtb,
      X86InstId.kVpminub,
      X86InstId.kVpmaxub
    ],
    [
      X86InstId.kVpcmpeqw,
      X86InstId.kVpcmpgtw,
      X86InstId.kVpminsw,
      X86InstId.kVpmaxsw
    ],
    [
      X86InstId.kVpcmpeqw,
      X86InstId.kVpcmpgtw,
      X86InstId.kVpminuw,
      X86InstId.kVpmaxuw
    ],
    [
      X86InstId.kVpcmpeqd,
      X86InstId.kVpcmpgtd,
      X86InstId.kVpminsd,
      X86InstId.kVpmaxsd
    ],
    [
      X86InstId.kVpcmpeqd,
      X86InstId.kVpcmpgtd,
      X86InstId.kVpminud,
      X86InstId.kVpmaxud
    ],
    [
      X86InstId.kVpcmpeqq,
      X86InstId.kVpcmpgtq,
      X86InstId.kVpminsq,
      X86InstId.kVpmaxsq
    ],
    [
      X86InstId.kVpcmpeqq,
      X86InstId.kVpcmpgtq,
      X86InstId.kVpminuq,
      X86InstId.kVpmaxuq
    ],
  ];

  static const _peq = 0, _pgt = 1, _pmin = 2, _pmax = 3;

  /// `translate_op(op, kModF32S, kTruncF32S)`.
  ///
  /// Deviation from upstream, which translates from `kTruncF32` instead:
  /// `kModF32`/`kModF64` then use the scalar `kFloorF32S`/`kFloorF64S`, and
  /// running upstream shows vector modF32 of {7.5, -7.5, 10, 5.25} by
  /// {2, 2, 3, 1.5} returning {1.5, 0, 0, 0} with SSE2, SSE4.1 and AVX
  /// instead of {1.5, -1.5, 1, 0.75}. upstream's AArch64 backend translates
  /// from `kTruncF32S`.
  static UniOpVV _modTruncOpX86(UniOpVVV op) => const [
        UniOpVV.truncF32S,
        UniOpVV.truncF64S,
        UniOpVV.truncF32,
        UniOpVV.truncF64,
      ][op.index - UniOpVVV.modF32S.index];

  void _emit3vX86(UniOpVVV op, Operand dst_, Operand src1_, Operand src2_) {
    if (dst_ is! BaseReg || src1_ is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    if (op.index >= kX86OpcodeInfo3v.length) {
      throw UnsupportedError('UniCompiler x86: $op is an AArch64 operation');
    }

    var dst = dst_;
    var src1v = _cloneAsX86(src1_, dst);
    var src2 = src2_;
    final info = kX86OpcodeInfo3v[op.index];

    if (hasAvx) {
      // AVX Implementation
      // ------------------
      var instId = info.avxInstId;

      if (_isSameVecX86(src1v, src2)) {
        switch (info.sameVecOp) {
          case 1:
            _avxZeroX86(dst);
            return;
          case 2:
            _avxOnesX86(dst);
            return;
          case 3:
            _avxMovX86(dst, src1v);
            return;
        }
      }

      if (hasAvxExt(info.avxExt)) {
        if (_isScalarFm(info.floatMode)) {
          dst = X86Xmm(dst.id);
          src1v = X86Xmm(src1v.id);
          if (src2 is BaseReg) src2 = X86Xmm(src2.id);
        }

        if (op.index >= UniOpVVV.andU32.index &&
            op.index <= UniOpVVV.andnU64.index) {
          const avx512ToAvxBitwise = [
            X86InstId.kVpand,
            X86InstId.kVpand,
            X86InstId.kVpor,
            X86InstId.kVpor,
            X86InstId.kVpxor,
            X86InstId.kVpxor,
            X86InstId.kVpandn,
            X86InstId.kVpandn,
          ];
          instId = avx512ToAvxBitwise[op.index - UniOpVVV.andU32.index];
        }

        _emitX86(instId, [
          dst,
          src1v,
          src2,
          if (info.useImm != 0) Imm(info.imm),
        ]);
        return;
      }

      switch (op) {
        case UniOpVVV.bicU32:
        case UniOpVVV.bicU64:
        case UniOpVVV.bicF32:
        case UniOpVVV.bicF64:
          if (op.index <= UniOpVVV.bicU64.index) instId = X86InstId.kVpandn;
          if (src2 is! BaseReg) src2 = _loadNewX86(dst, src2);
          _emitX86(instId, [dst, src2, src1v]);
          return;

        // dst = a - (trunc(a / b) * b).
        case UniOpVVV.modF32S:
        case UniOpVVV.modF64S:
        case UniOpVVV.modF32:
        case UniOpVVV.modF64:
          final fi = _sseFloatInst[info.floatMode];
          final tmp = _newSimilarRegX86(dst, '@mod_tmp');
          _emitX86(_vexIdX86(fi.fdiv), [tmp, src1v, src2]);
          _emit2vX86(_modTruncOpX86(op), tmp, tmp);
          _emitX86(_vexIdX86(fi.fmul), [tmp, tmp, src2]);
          _emitX86(_vexIdX86(fi.fsub), [dst, src1v, tmp]);
          return;

        case UniOpVVV.mulU64:
          // Native operation requires AVX512, which is not supported by the
          // target.
          if (src2 is! BaseReg) src2 = _loadNewX86(dst, src2);
          final src2v = _cloneAsX86(src2, dst);
          final alBh = _newSimilarRegX86(dst, '@al_bh');
          final ahBl = _newSimilarRegX86(dst, '@ah_bl');
          final hiPart = _newSimilarRegX86(dst, '@hi_part');
          _emitX86(X86InstId.kVpsrlq, [alBh, src2v, Imm(32)]);
          _emitX86(X86InstId.kVpsrlq, [ahBl, src1v, Imm(32)]);
          _emitX86(X86InstId.kVpmuludq, [alBh, alBh, src1v]);
          _emitX86(X86InstId.kVpmuludq, [ahBl, ahBl, src2v]);
          _emitX86(X86InstId.kVpmuludq, [dst, src1v, src2v]);
          _emitX86(X86InstId.kVpaddq, [hiPart, alBh, ahBl]);
          _emitX86(X86InstId.kVpsllq, [hiPart, hiPart, Imm(32)]);
          _emitX86(X86InstId.kVpaddq, [dst, dst, hiPart]);
          return;

        case UniOpVVV.mulU64LoU32:
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _emitX86(
              X86InstId.kVpshufd, [tmp, src1v, Imm(_shufImm4(2, 3, 0, 1))]);
          _emitX86(X86InstId.kVpmuludq, [tmp, tmp, src2]);
          _emitX86(X86InstId.kVpmuludq, [dst, src1v, src2]);
          _emitX86(X86InstId.kVpsllq, [tmp, tmp, Imm(32)]);
          _emitX86(X86InstId.kVpaddq, [dst, dst, tmp]);
          return;

        case UniOpVVV.minI64:
        case UniOpVVV.maxI64:
          // Native operation requires AVX512, which is not supported by the
          // target.
          if (src2 is! BaseReg) src2 = _loadNewX86(dst, src2);
          final src2v = _cloneAsX86(src2, dst);
          var msk = dst;
          if (dst.id == src1v.id || dst.id == src2v.id) {
            msk = _newSimilarRegX86(dst, '@msk');
          }
          _emitX86(X86InstId.kVpcmpgtq, [msk, src1v, src2v]);
          if (op == UniOpVVV.minI64) {
            _emitX86(X86InstId.kVblendvpd, [dst, src1v, src2v, msk]);
          } else {
            _emitX86(X86InstId.kVblendvpd, [dst, src2v, src1v, msk]);
          }
          return;

        case UniOpVVV.minU64:
        case UniOpVVV.maxU64:
          if (src2 is! BaseReg) src2 = _loadNewX86(dst, src2);
          final src2v = _cloneAsX86(src2, dst);
          var tmp1 = dst;
          final tmp2 = _newSimilarRegX86(dst, '@tmp2');
          if (dst.id == src1v.id || dst.id == src2v.id) {
            tmp1 = _newSimilarRegX86(dst, '@tmp1');
          }
          _avxIsignFlipX86(tmp1, src1v, 3);
          _avxIsignFlipX86(tmp2, src2v, 3);
          _emitX86(X86InstId.kVpcmpgtq, [tmp1, tmp1, tmp2]);
          if (op == UniOpVVV.minU64) {
            _emitX86(X86InstId.kVblendvpd, [dst, src1v, src2v, tmp1]);
          } else {
            _emitX86(X86InstId.kVblendvpd, [dst, src2v, src1v, tmp1]);
          }
          return;

        case UniOpVVV.cmpGtU8:
        case UniOpVVV.cmpGtU16:
        case UniOpVVV.cmpGtU32:
          // Native operation requires AVX512, which is not supported by the
          // target.
          final inst = _avxCmpMinMax[(op.index - UniOpVVV.cmpGtI8.index) & 0x7];
          if (_isSameVecX86(dst, src1v)) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _emitX86(inst[_pmin], [tmp, src1v, src2]);
            _emitX86(inst[_peq], [dst, dst, tmp]);
          } else {
            _emitX86(inst[_pmin], [dst, src1v, src2]);
            _emitX86(inst[_peq], [dst, dst, src1v]);
          }
          _avxBitNotX86(dst, dst);
          return;

        case UniOpVVV.cmpGtU64:
        case UniOpVVV.cmpLeU64:
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _avxIsignFlipX86(tmp, src2, 3);
          _avxIsignFlipX86(dst, src1v, 3);
          _emitX86(X86InstId.kVpcmpgtq, [dst, dst, tmp]);
          if (op == UniOpVVV.cmpLeU64) _avxBitNotX86(dst, dst);
          return;

        case UniOpVVV.cmpGeI8:
        case UniOpVVV.cmpGeU8:
        case UniOpVVV.cmpGeI16:
        case UniOpVVV.cmpGeU16:
        case UniOpVVV.cmpGeI32:
        case UniOpVVV.cmpGeU32:
          final inst = _avxCmpMinMax[(op.index - UniOpVVV.cmpGeI8.index) & 0x7];
          if (dst.id == src1v.id) {
            if (src2 is! BaseReg) {
              final tmp = _newSimilarRegX86(dst, '@tmp');
              _emitX86(inst[_pmax], [tmp, src1v, src2]);
              _emitX86(inst[_peq], [dst, tmp, src1v]);
            } else {
              _emitX86(inst[_pmin], [dst, src1v, src2]);
              _emitX86(inst[_peq], [dst, dst, src2]);
            }
          } else {
            _emitX86(inst[_pmax], [dst, src1v, src2]);
            _emitX86(inst[_peq], [dst, dst, src1v]);
          }
          return;

        case UniOpVVV.cmpLtI8:
        case UniOpVVV.cmpLtI16:
        case UniOpVVV.cmpLtI32:
        case UniOpVVV.cmpLtI64:
        case UniOpVVV.cmpGeI64:
          if (src2 is! BaseReg) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _avxMovX86(tmp, src2);
            src2 = tmp;
          }
          final inst = _avxCmpMinMax[(op.index - UniOpVVV.cmpLtI8.index) & 0x7];
          _emitX86(inst[_pgt], [dst, src2, src1v]);
          if (op == UniOpVVV.cmpGeI64) _avxBitNotX86(dst, dst);
          return;

        case UniOpVVV.cmpLtU8:
        case UniOpVVV.cmpLtU16:
        case UniOpVVV.cmpLtU32:
        case UniOpVVV.cmpLtU64:
        case UniOpVVV.cmpGeU64:
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _avxIsignFlipX86(tmp, src2, info.elementSize);
          _avxIsignFlipX86(dst, src1v, info.elementSize);
          final inst = _avxCmpMinMax[(op.index - UniOpVVV.cmpLtI8.index) & 0x7];
          _emitX86(inst[_pgt], [dst, tmp, dst]);
          if (op == UniOpVVV.cmpGeU64) _avxBitNotX86(dst, dst);
          return;

        case UniOpVVV.cmpLeI8:
        case UniOpVVV.cmpLeU8:
        case UniOpVVV.cmpLeI16:
        case UniOpVVV.cmpLeU16:
        case UniOpVVV.cmpLeI32:
        case UniOpVVV.cmpLeU32:
          final inst = _avxCmpMinMax[(op.index - UniOpVVV.cmpLeI8.index) & 0x7];
          if (dst.id == src1v.id) {
            if (src2 is! BaseReg) {
              final tmp = _newSimilarRegX86(dst, '@tmp');
              _emitX86(inst[_pmin], [tmp, src1v, src2]);
              _emitX86(inst[_peq], [dst, tmp, src1v]);
            } else {
              _emitX86(inst[_pmax], [dst, src1v, src2]);
              _emitX86(inst[_peq], [dst, dst, src2]);
            }
          } else {
            _emitX86(inst[_pmin], [dst, src1v, src2]);
            _emitX86(inst[_peq], [dst, dst, src1v]);
          }
          return;

        case UniOpVVV.cmpLeI64:
          _emitX86(X86InstId.kVpcmpgtq, [dst, src1v, src2]);
          _avxBitNotX86(dst, dst);
          return;

        case UniOpVVV.hAddF64:
          _emitX86(instId, [dst, src1v, src2]);
          return;

        case UniOpVVV.combineLoHiU64:
        case UniOpVVV.combineLoHiF64:
          // dst = {src1.u64[0], src2.u64[1]} (high, low).
          if (src2 is! BaseReg) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _avxMovX86(tmp, src2);
            src2 = tmp;
          }
          _emitX86(X86InstId.kVshufpd,
              [dst, src2, src1v, Imm(_shufImm2WithWidthX86(0, 1, dst))]);
          return;

        case UniOpVVV.combineHiLoU64:
        case UniOpVVV.combineHiLoF64:
          // dst = {src1.u64[1], src2.u64[0]} (high, low).
          if (dst is X86Xmm) {
            if (src2 is BaseReg) {
              _emitX86(
                  X86InstId.kVmovsd, [dst, X86Xmm(src1v.id), X86Xmm(src2.id)]);
            } else {
              _emitX86(X86InstId.kVmovlpd, [dst, X86Xmm(src1v.id), src2]);
            }
            return;
          }
          if (src2 is! BaseReg) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _avxMovX86(tmp, src2);
            src2 = tmp;
          }
          _emitX86(X86InstId.kVshufpd,
              [dst, src2, src1v, Imm(_shufImm2WithWidthX86(1, 0, dst))]);
          return;

        default:
          throw _requiresX86(op, info.avxExt.name.substring(1));
      }
    }

    // SSE Implementation
    // ------------------
    final instId = info.sseInstId;

    // SSE floating point comparison cannot use the extended predicates as
    // introduced by AVX.
    const sseFcmpImmTable = [
      0x00, // kCmpEq    (eq ordered quiet).
      0x04, // kCmpNe    (ne ordered quiet).
      0x01, // kCmpGt    (lt ordered quiet <reversed>).
      0x02, // kCmpGe    (le ordered quiet <reversed>).
      0x01, // kCmpLt    (lt ordered quiet).
      0x02, // kCmpLe    (le ordered quiet).
      0x07, // kCmpOrd   (ordered quiet).
      0x03, // kCmpUnord (unordered quiet).
    ];
    int fcmpPred() =>
        sseFcmpImmTable[(op.index - UniOpVVV.cmpEqF32S.index) ~/ 4];

    if (_isSameVecX86(dst, src2) && info.commutative != 0) {
      final t = src1v;
      src1v = _cloneAsX86(src2 as BaseReg, dst);
      src2 = t;
    }

    if (_isSameVecX86(src1v, src2)) {
      switch (info.sameVecOp) {
        case 1:
          _emitX86(X86InstId.kPxor, [dst, dst]);
          return;
        case 2:
          _emitX86(X86InstId.kPcmpeqb, [dst, dst]);
          return;
        case 3:
          _sseMovX86(dst, src1v);
          return;
      }
    }

    if (hasSseExt(info.sseExt)) {
      if (!_isSameVecX86(dst, src1v)) {
        if (_isSameVecX86(dst, src2)) {
          final tmp = _newSimilarRegX86(dst, 'tmp');
          _sseMovX86(tmp, src2);
          src2 = tmp;
        }
        _sseMovX86(dst, src1v);
      }
      _emitX86(instId, [dst, src2, if (info.useImm != 0) Imm(info.imm)]);
      return;
    }

    switch (op) {
      case UniOpVVV.bicU32:
      case UniOpVVV.bicU64:
      case UniOpVVV.bicF32:
      case UniOpVVV.bicF64:
        if (_isSameVecX86(dst, src2)) {
          _emitX86(instId, [dst, src1v]);
          return;
        }
        if (_isSameVecX86(dst, src1v)) {
          final tmp = _newSimilarRegX86(dst);
          _sseMovX86(tmp, src1v);
          src1v = tmp;
        }
        _sseMovX86(dst, src2);
        _emitX86(instId, [dst, src1v]);
        return;

      // dst = a - (trunc(a / b) * b).
      case UniOpVVV.modF32S:
      case UniOpVVV.modF64S:
      case UniOpVVV.modF32:
      case UniOpVVV.modF64:
        final fm = info.floatMode;
        final fi = _sseFloatInst[fm];
        final tmp = _newSimilarRegX86(dst, '@mod_tmp');
        _emitX86(fi.fmova, [tmp, src1v]);
        _emitX86(fi.fdiv, [tmp, src2]);
        _emit2vX86(_modTruncOpX86(op), tmp, tmp);
        _emitX86(fi.fmul, [tmp, src2]);
        _sseFmovX86(dst, src1v, fm);
        _emitX86(fi.fsub, [dst, tmp]);
        return;

      case UniOpVVV.mulU32:
        // Native operation requires SSE4.1, which is not supported by the
        // target.
        final tmp1 = _newSimilarRegX86(dst, 'tmp1');
        final tmp2 = _newSimilarRegX86(dst, 'tmp2');
        _emitX86(X86InstId.kPshufd, [tmp1, src1v, Imm(_shufImm4(3, 3, 1, 1))]);
        _emitX86(X86InstId.kPshufd, [tmp2, src2, Imm(_shufImm4(3, 3, 1, 1))]);
        _emitX86(X86InstId.kPmuludq, [tmp1, tmp2]);
        _sseMovX86(dst, src1v);
        _emitX86(X86InstId.kPmuludq, [dst, src2]);
        _emitX86(X86InstId.kShufps, [dst, tmp1, Imm(_shufImm4(2, 0, 2, 0))]);
        _emitX86(X86InstId.kPshufd, [dst, dst, Imm(_shufImm4(3, 1, 2, 0))]);
        return;

      case UniOpVVV.mulU64:
        // Native operation requires AVX512, which is not supported by the
        // target.
        final alBh = _newSimilarRegX86(dst, '@al_bh');
        final ahBl = _newSimilarRegX86(dst, '@ah_bl');
        _emitX86(X86InstId.kPshufd, [alBh, src2, Imm(_shufImm4(3, 3, 1, 1))]);
        _emitX86(X86InstId.kPshufd, [ahBl, src1v, Imm(_shufImm4(3, 3, 1, 1))]);
        _emitX86(X86InstId.kPmuludq, [alBh, src1v]);
        _emitX86(X86InstId.kPmuludq, [ahBl, src2]);
        _emitX86(X86InstId.kPaddq, [alBh, ahBl]);
        _sseMovX86(dst, src1v);
        _emitX86(X86InstId.kPmuludq, [dst, src2]);
        _emitX86(X86InstId.kPsllq, [alBh, Imm(32)]);
        _emitX86(X86InstId.kPaddq, [dst, alBh]);
        return;

      case UniOpVVV.mulU64LoU32:
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _emitX86(X86InstId.kPshufd, [tmp, src1v, Imm(_shufImm4(2, 3, 0, 1))]);
        _emitX86(X86InstId.kPmuludq, [tmp, src2]);
        if (src2 is BaseReg && dst.id == src2.id) {
          _emitX86(X86InstId.kPmuludq, [dst, src1v]);
        } else {
          _sseMovX86(dst, src1v);
          _emitX86(X86InstId.kPmuludq, [dst, src2]);
        }
        _emitX86(X86InstId.kPsllq, [tmp, Imm(32)]);
        _emitX86(X86InstId.kPaddq, [dst, tmp]);
        return;

      case UniOpVVV.minI64:
      case UniOpVVV.minI8:
      case UniOpVVV.minI32:
        // Native operation requires AVX512 (I64) or SSE4.1, which is not
        // supported by the target.
        final msk = newVecWithWidth(VecWidth.k128, '@msk');
        if (op == UniOpVVV.minI64 && !hasSse42) {
          _sseCmpGtI64X86(msk, src2, src1v);
        } else {
          final cmpInstId = op == UniOpVVV.minI8
              ? X86InstId.kPcmpgtb
              : op == UniOpVVV.minI32
                  ? X86InstId.kPcmpgtd
                  : X86InstId.kPcmpgtq;
          _emitX86(X86InstId.kMovaps, [msk, src2]);
          _emitX86(cmpInstId, [msk, src1v]);
        }
        _sseSelectX86(dst, src1v, src2, msk);
        return;

      case UniOpVVV.maxI64:
      case UniOpVVV.maxI8:
      case UniOpVVV.maxI32:
        final msk = newVecWithWidth(VecWidth.k128, '@msk');
        if (op == UniOpVVV.maxI64 && !hasSse42) {
          _sseCmpGtI64X86(msk, src1v, src2);
        } else {
          final cmpInstId = op == UniOpVVV.maxI8
              ? X86InstId.kPcmpgtb
              : op == UniOpVVV.maxI32
                  ? X86InstId.kPcmpgtd
                  : X86InstId.kPcmpgtq;
          _emitX86(X86InstId.kMovaps, [msk, src1v]);
          _emitX86(cmpInstId, [msk, src2]);
        }
        _sseSelectX86(dst, src1v, src2, msk);
        return;

      case UniOpVVV.minU16:
        // Native operation requires SSE4.1, which is not supported by the
        // target.
        final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
        _emitX86(X86InstId.kMovaps, [tmp, src1v]);
        _emitX86(X86InstId.kPsubusw, [tmp, src2]);
        _sseMovX86(dst, src1v);
        _emitX86(X86InstId.kPsubw, [dst, tmp]);
        return;

      case UniOpVVV.maxU16:
        // Native operation requires SSE4.1, which is not supported by the
        // target.
        _sseMovX86(dst, src1v);
        _emitX86(X86InstId.kPsubusw, [dst, src2]);
        _emitX86(X86InstId.kPaddw, [dst, src2]);
        return;

      case UniOpVVV.minU32:
      case UniOpVVV.maxU32:
        // Native operation requires SSE4.1, which is not supported by the
        // target.
        final flipMask =
            _simdConstX86(VecConstTable.p_8000000080000000, Bcst.kNA, dst);
        final tmp1 = _newSimilarRegX86(dst, '@tmp1');
        final tmp2 = _newSimilarRegX86(dst, '@tmp2');
        if (op == UniOpVVV.minU32) {
          _sseMovX86(tmp1, src2);
          _sseMovX86(tmp2, src1v);
        } else {
          _sseMovX86(tmp1, src1v);
          _sseMovX86(tmp2, src2);
        }
        _emitX86(X86InstId.kPxor, [tmp1, flipMask]);
        _emitX86(X86InstId.kPxor, [tmp2, flipMask]);
        _emitX86(X86InstId.kPcmpgtd, [tmp1, tmp2]);
        _sseSelectX86(dst, src1v, src2, tmp1);
        return;

      case UniOpVVV.minU64:
        // Native operation requires AVX512, which is not supported by the
        // target.
        final msk = _newSimilarRegX86(dst, '@tmp1');
        _sseCmpGtU64X86(msk, src2, src1v);
        _sseSelectX86(dst, src1v, src2, msk);
        return;

      case UniOpVVV.maxU64:
        final msk = _newSimilarRegX86(dst, '@tmp1');
        _sseCmpGtU64X86(msk, src1v, src2);
        _sseSelectX86(dst, src1v, src2, msk);
        return;

      case UniOpVVV.cmpEqU64:
        // Native operation requires SSE4.1, which is not supported by the
        // target.
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _sseMovX86(dst, src1v);
        _emitX86(X86InstId.kPcmpeqd, [dst, src2]);
        _emitX86(X86InstId.kPshufd, [tmp, dst, Imm(_shufImm4(2, 3, 0, 1))]);
        _emitX86(X86InstId.kPand, [dst, tmp]);
        return;

      case UniOpVVV.cmpGtI64:
        // Native operation requires SSE4.2, which is not supported by the
        // target.
        _sseCmpGtI64X86(dst, src1v, src2);
        return;

      case UniOpVVV.cmpGtU8:
      case UniOpVVV.cmpGtU16:
      case UniOpVVV.cmpGtU32:
        final inst = _sseCmpMinMax[op.index - UniOpVVV.cmpGtI8.index];
        if (hasSse41 || op == UniOpVVV.cmpGtU8) {
          if (dst.id == src1v.id) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _emitX86(X86InstId.kMovaps, [tmp, src1v]);
            _emitX86(inst[_pmin], [tmp, src2]);
            _emitX86(inst[_peq], [dst, tmp]);
          } else if (_isSameVecX86(dst, src2)) {
            _emitX86(inst[_pmin], [dst, src1v]);
            _emitX86(inst[_peq], [dst, src1v]);
          } else {
            _emitX86(X86InstId.kMovaps, [dst, src1v]);
            _emitX86(inst[_pmin], [dst, src2]);
            _emitX86(inst[_peq], [dst, src1v]);
          }
          _sseBitNotX86(dst, dst);
          return;
        }
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _sseMsbFlipX86(tmp, src2, info.elementSize);
        _sseMsbFlipX86(dst, src1v, info.elementSize);
        _emitX86(inst[_pgt], [dst, tmp]);
        return;

      case UniOpVVV.cmpGtU64:
        // Native operation requires AVX512, which is not supported by the
        // target.
        _sseCmpGtU64X86(dst, src1v, src2);
        return;

      case UniOpVVV.cmpGeI8:
      case UniOpVVV.cmpGeU8:
      case UniOpVVV.cmpGeI16:
      case UniOpVVV.cmpGeU16:
      case UniOpVVV.cmpGeI32:
      case UniOpVVV.cmpGeU32:
      case UniOpVVV.cmpGeI64:
      case UniOpVVV.cmpGeU64:
        // Native operation requires AVX512, which is not supported by the
        // target.
        if (op.index <= UniOpVVV.cmpGeU32.index) {
          if (hasSse41 || op == UniOpVVV.cmpGeU8 || op == UniOpVVV.cmpGeI16) {
            final inst = _sseCmpMinMax[op.index - UniOpVVV.cmpGeI8.index];
            if (dst.id == src1v.id) {
              final tmp = _newSimilarRegX86(dst, '@tmp');
              _emitX86(X86InstId.kMovaps, [tmp, src1v]);
              _emitX86(inst[_pmax], [tmp, src2]);
              _emitX86(inst[_peq], [dst, tmp]);
            } else if (_isSameVecX86(dst, src2)) {
              _emitX86(inst[_pmax], [dst, src1v]);
              _emitX86(inst[_peq], [dst, src1v]);
            } else {
              _emitX86(X86InstId.kMovaps, [dst, src1v]);
              _emitX86(inst[_pmax], [dst, src2]);
              _emitX86(inst[_peq], [dst, src1v]);
            }
            return;
          }

          if (op == UniOpVVV.cmpGeU16) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _sseMovX86(tmp, src1v);
            _emitX86(X86InstId.kPsubusw, [tmp, src2]);
            _emitX86(X86InstId.kPaddw, [tmp, src2]);
            _sseMovX86(dst, src1v);
            _emitX86(X86InstId.kPcmpeqw, [dst, tmp]);
            return;
          }
        }

        if (src2 is! BaseReg) {
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _sseMovX86(tmp, src2);
          src2 = tmp;
        }
        final gtOp = switch (op) {
          UniOpVVV.cmpGeI8 => UniOpVVV.cmpGtI8,
          UniOpVVV.cmpGeI32 => UniOpVVV.cmpGtI32,
          UniOpVVV.cmpGeU32 => UniOpVVV.cmpGtU32,
          UniOpVVV.cmpGeI64 => UniOpVVV.cmpGtI64,
          UniOpVVV.cmpGeU64 => UniOpVVV.cmpGtU64,
          _ => throw StateError('unreachable: $op'),
        };
        _emit3vX86(gtOp, dst, src2, src1v);
        _sseBitNotX86(dst, dst);
        return;

      case UniOpVVV.cmpLtI8:
      case UniOpVVV.cmpLtI16:
      case UniOpVVV.cmpLtI32:
        if (_isSameVecX86(dst, src1v)) {
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _sseMovX86(tmp, src1v);
          src1v = tmp;
        }
        _sseMovX86(dst, src2);
        _emitX86(instId, [dst, src1v]);
        return;

      case UniOpVVV.cmpLtU8:
      case UniOpVVV.cmpLtU16:
      case UniOpVVV.cmpLtU32:
        final tmp = _newSimilarRegX86(dst, '@tmp');
        _sseMovX86(tmp, src1v);
        _sseMsbFlipX86(tmp, src1v, info.elementSize);
        _sseMsbFlipX86(dst, src2, info.elementSize);
        _emitX86(instId, [dst, tmp]);
        return;

      case UniOpVVV.cmpLtI64:
        // Native operation requires AVX512, which is not supported by the
        // target.
        _sseCmpGtI64X86(dst, src2, src1v);
        return;

      case UniOpVVV.cmpLtU64:
        // Native operation requires AVX512, which is not supported by the
        // target.
        _sseCmpGtU64X86(dst, src2, src1v);
        return;

      case UniOpVVV.cmpLeU8:
        if (_isSameVecX86(dst, src2)) {
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _sseMovX86(tmp, src2);
          src2 = tmp;
        }
        _sseMovX86(dst, src1v);
        _emitX86(X86InstId.kPsubusb, [dst, src2]);
        final zeros =
            _simdVecConstX86(VecConstTable.p_0000000000000000, Bcst.k32, dst);
        _emitX86(X86InstId.kPcmpeqb, [dst, zeros]);
        return;

      case UniOpVVV.cmpLeI8:
      case UniOpVVV.cmpLeI16:
      case UniOpVVV.cmpLeU16:
      case UniOpVVV.cmpLeI32:
      case UniOpVVV.cmpLeU32:
      case UniOpVVV.cmpLeI64:
      case UniOpVVV.cmpLeU64:
        if (op.index <= UniOpVVV.cmpLeU32.index &&
            (hasSse41 || op == UniOpVVV.cmpLeI16)) {
          final inst = _sseCmpMinMax[op.index - UniOpVVV.cmpLeI8.index];
          if (dst.id == src1v.id) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _emitX86(X86InstId.kMovaps, [tmp, src1v]);
            _emitX86(inst[_pmin], [tmp, src2]);
            _emitX86(inst[_peq], [dst, tmp]);
          } else if (_isSameVecX86(dst, src2)) {
            _emitX86(inst[_pmin], [dst, src1v]);
            _emitX86(inst[_peq], [dst, src1v]);
          } else {
            _emitX86(X86InstId.kMovaps, [dst, src1v]);
            _emitX86(inst[_pmin], [dst, src2]);
            _emitX86(inst[_peq], [dst, src1v]);
          }
          return;
        }
        final gtOp = switch (op) {
          UniOpVVV.cmpLeI8 => UniOpVVV.cmpGtI8,
          UniOpVVV.cmpLeU16 => UniOpVVV.cmpGtU16,
          UniOpVVV.cmpLeI32 => UniOpVVV.cmpGtI32,
          UniOpVVV.cmpLeU32 => UniOpVVV.cmpGtU32,
          UniOpVVV.cmpLeI64 => UniOpVVV.cmpGtI64,
          UniOpVVV.cmpLeU64 => UniOpVVV.cmpGtU64,
          _ => throw StateError('unreachable: $op'),
        };
        _emit3vX86(gtOp, dst, src1v, src2);
        _sseBitNotX86(dst, dst);
        return;

      case UniOpVVV.cmpLtF32S:
      case UniOpVVV.cmpLtF64S:
      case UniOpVVV.cmpLtF32:
      case UniOpVVV.cmpLtF64:
      case UniOpVVV.cmpLeF32S:
      case UniOpVVV.cmpLeF64S:
      case UniOpVVV.cmpLeF32:
      case UniOpVVV.cmpLeF64:
      case UniOpVVV.cmpEqF32S:
      case UniOpVVV.cmpEqF64S:
      case UniOpVVV.cmpEqF32:
      case UniOpVVV.cmpEqF64:
      case UniOpVVV.cmpNeF32S:
      case UniOpVVV.cmpNeF64S:
      case UniOpVVV.cmpNeF32:
      case UniOpVVV.cmpNeF64:
      case UniOpVVV.cmpOrdF32S:
      case UniOpVVV.cmpOrdF64S:
      case UniOpVVV.cmpOrdF32:
      case UniOpVVV.cmpOrdF64:
      case UniOpVVV.cmpUnordF32S:
      case UniOpVVV.cmpUnordF64S:
      case UniOpVVV.cmpUnordF32:
      case UniOpVVV.cmpUnordF64:
        final pred = fcmpPred();
        final isLtLe = op.index >= UniOpVVV.cmpLtF32S.index &&
            op.index <= UniOpVVV.cmpLeF64.index;
        if (isLtLe && _isSameVecX86(dst, src2)) {
          // Unfortunately we have to do two moves, because there are no
          // predicates that we could use in case of reversed operands (AVX
          // is much better in this regard).
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _sseMovX86(tmp, src2);
          _sseMovX86(dst, src1v);
          _emitX86(instId, [dst, tmp, Imm(pred)]);
          return;
        }
        _sseMovX86(dst, src1v);
        _emitX86(instId, [dst, src2, Imm(pred)]);
        return;

      case UniOpVVV.cmpGtF32S:
      case UniOpVVV.cmpGtF64S:
      case UniOpVVV.cmpGtF32:
      case UniOpVVV.cmpGtF64:
      case UniOpVVV.cmpGeF32S:
      case UniOpVVV.cmpGeF64S:
      case UniOpVVV.cmpGeF32:
      case UniOpVVV.cmpGeF64:
        // Since SSE compare doesn't provide these modes natively, we have to
        // reverse the operands.
        final pred = fcmpPred();
        if (dst.id != src1v.id) {
          _sseMovX86(dst, src2);
          _emitX86(instId, [dst, src1v, Imm(pred)]);
        } else {
          final tmp = _newSimilarRegX86(dst, '@tmp');
          _sseMovX86(tmp, src2);
          _emitX86(instId, [tmp, src1v, Imm(pred)]);
          _sseMovX86(dst, tmp);
        }
        return;

      case UniOpVVV.hAddF64:
        // Native operation requires SSE3, which is not supported by the
        // target.
        if (_isSameVecX86(src1v, src2)) {
          if (_isSameVecX86(dst, src1v)) {
            final tmp = _newSimilarRegX86(dst, '@tmp');
            _vSwapF64X86(tmp, dst);
            _emitX86(X86InstId.kAddpd, [dst, tmp]);
          } else {
            _vSwapF64X86(dst, src1v);
            _emitX86(X86InstId.kAddpd, [dst, src1v]);
          }
          return;
        }
        // [B A]    [C A]
        // [D C] -> [D B]
        final tmp = _newSimilarRegX86(dst, '@tmp');
        if (src2 is X86Mem) {
          final m = src2.withSize(8);
          _sseMovX86(dst, src1v);
          _vSwapF64X86(tmp, dst);
          _emitX86(X86InstId.kMovhpd, [dst, m]);
          _emitX86(
              X86InstId.kMovhpd, [tmp, m.withDisplacement(m.displacement + 8)]);
          _emitX86(X86InstId.kAddpd, [dst, tmp]);
        } else if (_isSameVecX86(dst, src2)) {
          _sseMovX86(tmp, src1v);
          _emitX86(X86InstId.kUnpcklpd, [tmp, src2]);
          _emitX86(X86InstId.kMovhlps, [dst, src1v]);
          _emitX86(X86InstId.kAddpd, [dst, tmp]);
        } else {
          _sseMovX86(tmp, src1v);
          _emitX86(X86InstId.kUnpckhpd, [tmp, src2]);
          _sseMovX86(dst, src1v);
          _emitX86(X86InstId.kUnpcklpd, [dst, src2]);
          _emitX86(X86InstId.kAddpd, [dst, tmp]);
        }
        return;

      case UniOpVVV.combineLoHiU64:
      case UniOpVVV.combineLoHiF64:
        // dst = {src1.u64[0], src2.u64[1]} (high, low).
        if (src2 is X86Mem) {
          final m = src2.withDisplacement(src2.displacement + 8).withSize(8);
          _emitX86(X86InstId.kPshufd, [dst, src1v, Imm(_shufImm4(1, 0, 1, 0))]);
          _emitX86(X86InstId.kMovlpd, [dst, m]);
          return;
        }
        if (_isSameVecX86(dst, src2)) {
          // dst = {src1.u64[0], dst.u64[1]}
          _emitX86(X86InstId.kShufpd, [dst, src1v, Imm(1)]);
          return;
        } else if (_isSameVecX86(dst, src1v) && hasSsse3) {
          // dst = {dst.u64[0], src2.u64[1]}
          _emitX86(X86InstId.kPalignr, [dst, src2, Imm(8)]);
          return;
        }
        if (hasSse3) {
          _emitX86(X86InstId.kMovddup, [dst, src1v]);
        } else {
          _emitX86(X86InstId.kPshufd, [dst, src1v, Imm(_shufImm4(1, 0, 1, 0))]);
        }
        _emitX86(X86InstId.kMovhlps, [dst, src2]);
        return;

      case UniOpVVV.combineHiLoU64:
      case UniOpVVV.combineHiLoF64:
        // dst = {src1.u64[1], src2.u64[0]} (high, low).
        if (src2 is X86Mem) {
          _sseMovX86(dst, src1v);
          _emitX86(X86InstId.kMovlpd, [dst, src2.withSize(8)]);
        } else if (_isSameVecX86(dst, src2)) {
          // dst = {src1.u64[1], dst.u64[0]}
          _emitX86(X86InstId.kShufpd, [dst, src1v, Imm(0x2)]);
        } else {
          _sseMovX86(dst, src1v);
          _emitX86(X86InstId.kMovsd, [dst, src2]);
        }
        return;

      case UniOpVVV.packsI32U16:
        // Native operation requires SSE4.1, which is not supported by the
        // target. Unsigned saturation is done first (the MSB of each input
        // fills a register that is then used by ANDN), the input is biased
        // so the signed saturation of packssdw applies, and the result is
        // unbiased.
        final bias =
            _simdConstX86(VecConstTable.p_0000800000008000, Bcst.kNA, dst);
        final unbias =
            _simdConstX86(VecConstTable.p_8000800080008000, Bcst.kNA, dst);
        if (_isSameVecX86(src1v, src2)) {
          var tmp = dst;
          if (_isSameVecX86(dst, src1v)) tmp = _newSimilarRegX86(dst, '@tmp1');
          _sseMovX86(tmp, src1v);
          _emitX86(X86InstId.kPsrad, [tmp, Imm(31)]);
          _emitX86(X86InstId.kPandn, [tmp, src1v]);
          _emitX86(X86InstId.kPsubd, [tmp, bias]);
          _emitX86(X86InstId.kPackssdw, [tmp, tmp]);
          _emitX86(X86InstId.kPaddw, [tmp, unbias]);
          _sseMovX86(dst, tmp);
        } else {
          final tmp1 = _newSimilarRegX86(dst, '@tmp1');
          final tmp2 = _newSimilarRegX86(dst, '@tmp2');
          _sseMovX86(tmp1, src1v);
          _sseMovX86(tmp2, src2);
          _emitX86(X86InstId.kPsrad, [tmp1, Imm(31)]);
          _emitX86(X86InstId.kPsrad, [tmp2, Imm(31)]);
          _emitX86(X86InstId.kPandn, [tmp1, src1v]);
          _emitX86(X86InstId.kPandn, [tmp2, src2]);
          _emitX86(X86InstId.kPsubd, [tmp1, bias]);
          _emitX86(X86InstId.kPsubd, [tmp2, bias]);
          _emitX86(X86InstId.kPackssdw, [tmp1, tmp2]);
          _emitX86(X86InstId.kPaddw, [tmp1, unbias]);
          _sseMovX86(dst, tmp1);
        }
        return;

      case UniOpVVV.swizzlevU8:
        _swizzlevU8Sse2X86(dst, src1v, src2);
        return;

      default:
        throw _requiresX86(op, info.sseExt.name.substring(1));
    }
  }

  /// `v_swap_f64()`: swaps the two f64 lanes.
  void _vSwapF64X86(BaseReg dst, BaseReg src) =>
      _emit2viX86(UniOpVVI.swizzleF64x2, dst, src, swizzle2(0, 1).value);

  /// SSE2 emulation of `kSwizzlev_U8` (pshufb) from `emit_3v()`: the table
  /// and the clamped indices go through a stack buffer.
  ///
  /// Deviations from upstream: upstream loads the 0x0F mask with `vmovaps`,
  /// a VEX instruction, in this SSE2-only path (its log shows
  /// `vmovaps xmm0, [rax+256]` when built with SSE2 features only), which
  /// faults on every CPU that takes it; the port uses `movaps`. Upstream
  /// merges the second byte through a high-byte register (`mov ah, [m]`),
  /// which the port's allocator cannot constrain to AL..BL, so the byte is
  /// shifted into place instead.
  void _swizzlevU8Sse2X86(BaseReg dst, BaseReg src1v, Operand src2) {
    final stack = (cc as X86Compiler).newStack(64, 16, 'tmp_stack');
    final mData = stack.withSize(1);
    final mPred = mData.withDisplacement(mData.displacement + 32);

    _emitX86(X86InstId.kMovaps, [stack.withSize(16), src1v]);

    // The trick is to AND all indexes by 0x0F and then to do unsigned
    // minimum so all indexes are in [0, 17) range, where index 16 maps to
    // zero.
    final tmp = _newSimilarRegX86(dst, '@tmp');
    final uc = this as UniCompiler;
    _emitX86(X86InstId.kMovaps, [
      tmp,
      uc.simdMemConst(VecConstTable.p_0F0F0F0F0F0F0F0F, Bcst.kNA,
          VecWidthUtils.vecWidthOf(tmp))
    ]);
    _emitX86(X86InstId.kPand, [tmp, src2]);
    _emitX86(X86InstId.kPminub, [
      tmp,
      uc.simdMemConst(VecConstTable.p_1010101010101010, Bcst.kNA,
          VecWidthUtils.vecWidthOf(tmp))
    ]);
    _emitX86(X86InstId.kMovaps, [mPred.withSize(16), tmp]);
    _emitX86(X86InstId.kMov,
        [mData.withDisplacement(mData.displacement + 16), Imm(0)]);

    final acc = uc.newGpz('@acc');
    final idx = uc.newGpz('@idx');
    final acc32 = X86Gp.r32(acc.id);
    final idx32 = X86Gp.r32(idx.id);

    // Process 2 bytes at a time, then use PINSRW to merge them with the
    // destination.
    for (var i = 0; i < 8; i++) {
      _emitX86(X86InstId.kMovzx,
          [acc32, mPred.withDisplacement(mPred.displacement + 2 * i)]);
      _emitX86(X86InstId.kMovzx,
          [idx32, mPred.withDisplacement(mPred.displacement + 2 * i + 1)]);
      _emitX86(X86InstId.kMovzx, [acc32, _withIndexX86(mData, acc)]);
      _emitX86(X86InstId.kMovzx, [idx32, _withIndexX86(mData, idx)]);
      _emitX86(X86InstId.kShl, [idx32, Imm(8)]);
      _emitX86(X86InstId.kOr, [acc32, idx32]);
      if (i == 0) {
        _emitX86(X86InstId.kMovd, [dst, acc32]);
      } else {
        _emitX86(X86InstId.kPinsrw, [dst, acc32, Imm(i)]);
      }
    }
  }

  static X86Mem _withIndexX86(X86Mem m, BaseReg index) => X86Mem(
      base: m.base,
      index: index,
      scale: 1,
      displacement: m.displacement,
      size: m.size,
      segment: m.segment);

  /// `shuf_imm4_from_swizzle(Swizzle4)`.
  static int _shufImm4FromSwizzle4(int s) =>
      _shufImm4((s >> 24) & 3, (s >> 16) & 3, (s >> 8) & 3, s & 3);

  /// `shuf_imm4_from_swizzle(Swizzle2)`: PSHUFD selecting 64-bit lanes.
  static int _shufImm4FromSwizzle2(int s) {
    final imm0 = s & 1, imm1 = (s >> 8) & 1;
    return _shufImm4(imm1 * 2 + 1, imm1 * 2, imm0 * 2 + 1, imm0 * 2);
  }

  /// `shuf_imm2_from_swizzle(Swizzle2)`: SHUFPD immediate.
  static int _shufImm2FromSwizzle2(int s) => (((s >> 8) & 1) << 1) | (s & 1);

  static final int _swz00 = swizzle2(0, 0).value;
  static final int _swz10 = swizzle2(1, 0).value;
  static final int _swz11 = swizzle2(1, 1).value;

  /// Port of `emit_2vi()` (ujit/unicompiler_x86.cpp). Swizzle immediates are
  /// [Swizzle2] / [Swizzle4] values, as in upstream.
  void _emit2viX86(UniOpVVI op, Operand dst_, Operand src_, int imm) {
    if (dst_ is! BaseReg) {
      throw ArgumentError('SIMD destination must be a register');
    }
    if (op.index >= kX86OpcodeInfo2vi.length) {
      throw UnsupportedError('UniCompiler x86: $op is an AArch64 operation');
    }
    var dst = dst_;
    var src = src_;
    final info = kX86OpcodeInfo2vi[op.index];

    if (hasAvx) {
      // AVX Implementation
      // ------------------
      final instId = info.avxInstId;

      if (hasAvxExt(info.avxExt)) {
        _emitX86(instId, [dst, src, Imm(imm)]);
        return;
      }

      switch (op) {
        case UniOpVVI.sllU16:
        case UniOpVVI.sllU32:
        case UniOpVVI.sllU64:
        case UniOpVVI.srlU16:
        case UniOpVVI.srlU32:
        case UniOpVVI.srlU64:
        case UniOpVVI.sraI16:
        case UniOpVVI.sraI32:
        case UniOpVVI.sllbU128:
        case UniOpVVI.srlbU128:
          // This instruction requires AVX-512 if the source is a memory
          // operand.
          if (src is! BaseReg) {
            _avxMovX86(dst, src);
            _emitX86(instId, [dst, dst, Imm(imm)]);
          } else {
            _emitX86(instId, [dst, src, Imm(imm)]);
          }
          return;

        case UniOpVVI.sraI64:
          // Native operation requires AVX-512, which is not supported by the
          // target.
          if (imm == 0) {
            _avxMovX86(dst, src);
            return;
          }
          if (imm == 63) {
            _emitX86(
                X86InstId.kVpshufd, [dst, src, Imm(_shufImm4(3, 3, 1, 1))]);
            _emitX86(X86InstId.kVpsrad, [dst, dst, Imm(31)]);
            return;
          }
          final tmp = _newSimilarRegX86(dst, '@tmp');
          if (src is! BaseReg) {
            _avxMovX86(dst, src);
            src = dst;
          }
          if (imm <= 32) {
            _emitX86(X86InstId.kVpsrad, [tmp, src, Imm(math.min(imm, 31))]);
            _emitX86(X86InstId.kVpsrlq, [dst, src, Imm(imm)]);
            _emitX86(X86InstId.kVpblendw, [dst, dst, tmp, Imm(0xCC)]);
            return;
          }
          _emitX86(X86InstId.kVpshufd, [tmp, src, Imm(_shufImm4(3, 3, 1, 1))]);
          _emitX86(X86InstId.kVpsrad, [tmp, tmp, Imm(31)]);
          _emitX86(X86InstId.kVpsrlq, [dst, src, Imm(imm)]);
          _emitX86(X86InstId.kVpsllq, [tmp, tmp, Imm(64 - imm)]);
          _emitX86(X86InstId.kVpor, [dst, dst, tmp]);
          return;

        case UniOpVVI.swizzleU16x4:
          final shufImm = _shufImm4FromSwizzle4(imm);
          _emitX86(X86InstId.kVpshuflw, [dst, src, Imm(shufImm)]);
          _emitX86(X86InstId.kVpshufhw, [dst, dst, Imm(shufImm)]);
          return;

        case UniOpVVI.swizzleLoU16x4:
        case UniOpVVI.swizzleHiU16x4:
        case UniOpVVI.swizzleU32x4:
          _emitX86(instId, [dst, src, Imm(_shufImm4FromSwizzle4(imm))]);
          return;

        case UniOpVVI.swizzleU64x2:
          if (imm == _swz00) {
            _emitX86(X86InstId.kVmovddup, [dst, src]);
          } else if (imm == _swz11 && src is BaseReg) {
            _emitX86(X86InstId.kVpunpckhqdq, [dst, src, src]);
          } else {
            _emitX86(X86InstId.kVpshufd,
                [dst, src, Imm(_shufImm4FromSwizzle2(imm))]);
          }
          return;

        case UniOpVVI.swizzleF32x4:
          final shufImm = _shufImm4FromSwizzle4(imm);
          if (src is BaseReg) {
            _emitX86(X86InstId.kVshufps, [dst, src, src, Imm(shufImm)]);
          } else {
            _emitX86(X86InstId.kVpshufd, [dst, src, Imm(shufImm)]);
          }
          return;

        case UniOpVVI.swizzleF64x2:
          if (imm == _swz00) {
            _emitX86(X86InstId.kVmovddup, [dst, src]);
          } else if (imm == _swz11 && src is BaseReg) {
            _emitX86(X86InstId.kVunpckhpd, [dst, src, src]);
          } else if (src is BaseReg) {
            const multipliers = [0x1, 0x5, 0x55];
            final shufImm = _shufImm2FromSwizzle2(imm) *
                multipliers[VecWidthUtils.vecWidthOf(dst).index];
            _emitX86(X86InstId.kVshufpd, [dst, src, src, Imm(shufImm)]);
          } else {
            _emitX86(X86InstId.kVpshufd,
                [dst, src, Imm(_shufImm4FromSwizzle2(imm))]);
          }
          return;

        case UniOpVVI.swizzleF64x4:
        case UniOpVVI.swizzleU64x4:
          _emitX86(info.avxInstId, [dst, src, Imm(_shufImm4FromSwizzle4(imm))]);
          return;

        case UniOpVVI.extractV128I32:
        case UniOpVVI.extractV128I64:
        case UniOpVVI.extractV128F32:
        case UniOpVVI.extractV128F64:
          if (imm >= 4) throw ArgumentError('extractV128 index $imm');
          dst = X86Xmm(dst.id);
          if (src is X86Mem) {
            _emitX86(X86InstId.kVmovdqu, [
              dst,
              src.withDisplacement(src.displacement + imm * 16).withSize(16)
            ]);
            return;
          }
          if (src is X86Ymm) {
            if (imm >= 2) throw ArgumentError('extractV128 index $imm');
            _emitX86(X86InstId.kVextractf128, [dst, src, Imm(imm)]);
            return;
          }
          throw UnsupportedError('UniCompiler x86: $op of $src');

        default:
          // extractV256* needs a 512-bit source (AVX-512).
          throw _requiresX86(op, info.avxExt.name.substring(1));
      }
    }

    // SSE Implementation
    // ------------------
    final instId = info.sseInstId;

    if (hasSseExt(info.sseExt)) {
      if (info.sseOpCount == 2) {
        _sseMovX86(dst, src);
        _emitX86(instId, [dst, Imm(imm)]);
        return;
      }
      if (info.sseOpCount == 3) {
        _emitX86(instId, [dst, src, Imm(imm)]);
        return;
      }
    }

    switch (op) {
      case UniOpVVI.sraI64:
        // Intrinsic (SSE2).
        if (imm == 0) {
          _sseMovX86(dst, src);
          return;
        }
        if (imm == 63) {
          _emitX86(X86InstId.kPshufd, [dst, src, Imm(_shufImm4(3, 3, 1, 1))]);
          _emitX86(X86InstId.kPsrad, [dst, Imm(31)]);
          return;
        }
        final tmp = _newSimilarRegX86(dst, '@tmp');
        if (imm <= 32 && hasSse41) {
          _sseMovX86(dst, src);
          _sseMovX86(tmp, src is BaseReg ? src : dst);
          _emitX86(X86InstId.kPsrad, [tmp, Imm(math.min(imm, 31))]);
          _emitX86(X86InstId.kPsrlq, [dst, Imm(imm)]);
          _emitX86(X86InstId.kPblendw, [dst, tmp, Imm(0xCC)]);
          return;
        }
        _sseMovX86(dst, src);
        _emitX86(X86InstId.kPshufd,
            [tmp, src is BaseReg ? src : dst, Imm(_shufImm4(3, 3, 1, 1))]);
        _emitX86(X86InstId.kPsrad, [tmp, Imm(31)]);
        _emitX86(X86InstId.kPsrlq, [dst, Imm(imm)]);
        _emitX86(X86InstId.kPsllq, [tmp, Imm(64 - imm)]);
        _emitX86(X86InstId.kPor, [dst, tmp]);
        return;

      case UniOpVVI.swizzleU16x4:
        // Intrinsic (SSE2).
        final shufImm = _shufImm4FromSwizzle4(imm);
        _emitX86(X86InstId.kPshuflw, [dst, src, Imm(shufImm)]);
        _emitX86(X86InstId.kPshufhw, [dst, dst, Imm(shufImm)]);
        return;

      case UniOpVVI.swizzleLoU16x4:
      case UniOpVVI.swizzleHiU16x4:
      case UniOpVVI.swizzleU32x4:
        // Intrinsic (SSE2).
        _emitX86(instId, [dst, src, Imm(_shufImm4FromSwizzle4(imm))]);
        return;

      case UniOpVVI.swizzleU64x2:
        // Intrinsic (SSE2 | SSE3).
        if (imm == _swz10) {
          _sseMovX86(dst, src);
        } else if (imm == _swz00 && hasSse3) {
          _emitX86(X86InstId.kMovddup, [dst, src]);
        } else if (imm == _swz00 && _isSameVecX86(dst, src)) {
          _emitX86(X86InstId.kPunpcklqdq, [dst, src]);
        } else if (imm == _swz11 && _isSameVecX86(dst, src)) {
          _emitX86(X86InstId.kPunpckhqdq, [dst, src]);
        } else {
          _emitX86(
              X86InstId.kPshufd, [dst, src, Imm(_shufImm4FromSwizzle2(imm))]);
        }
        return;

      case UniOpVVI.swizzleF32x4:
        // Intrinsic (SSE2).
        final shufImm = _shufImm4FromSwizzle4(imm);
        if (_isSameVecX86(dst, src)) {
          _emitX86(X86InstId.kShufps, [dst, dst, Imm(shufImm)]);
        } else {
          _emitX86(X86InstId.kPshufd, [dst, src, Imm(shufImm)]);
        }
        return;

      case UniOpVVI.swizzleF64x2:
        // Intrinsic (SSE2 | SSE3).
        if (imm == _swz10) {
          _sseMovX86(dst, src);
        } else if (imm == _swz00 && hasSse3) {
          _emitX86(X86InstId.kMovddup, [dst, src]);
        } else if (imm == _swz00 && _isSameVecX86(dst, src)) {
          _emitX86(X86InstId.kUnpcklpd, [dst, src]);
        } else if (imm == _swz11 && _isSameVecX86(dst, src)) {
          _emitX86(X86InstId.kUnpckhpd, [dst, src]);
        } else if (_isSameVecX86(dst, src)) {
          _emitX86(
              X86InstId.kShufpd, [dst, dst, Imm(_shufImm2FromSwizzle2(imm))]);
        } else {
          _emitX86(
              X86InstId.kPshufd, [dst, src, Imm(_shufImm4FromSwizzle2(imm))]);
        }
        return;

      default:
        // Not supported in SSE mode (256/512-bit swizzles and extracts).
        throw _requiresX86(op, 'AVX');
    }
  }

  void _emit3viX86(
      UniOpVVVI op, Operand dst, Operand src1, Operand src2, int imm) {
    if (dst is! BaseReg || src1 is! BaseReg) {
      throw ArgumentError('SIMD operands must be registers');
    }
    switch (op) {
      case UniOpVVVI.interleaveShuffleU32x4:
      case UniOpVVVI.interleaveShuffleF32x4:
      case UniOpVVVI.interleaveShuffleU64x2:
      case UniOpVVVI.interleaveShuffleF64x2:
        // SHUFPS/SHUFPD: low half from src1, high half from src2.
        final ps = op == UniOpVVVI.interleaveShuffleU32x4 ||
            op == UniOpVVVI.interleaveShuffleF32x4;
        final r = _copyVecX86(src1);
        _sseOpImmX86(ps ? X86InstId.kShufps : X86InstId.kShufpd, r, src2, imm);
        _vMovX86(dst, r);
        break;
      case UniOpVVVI.alignrU128 when !hasAvx && !hasSsse3:
        // SSE2: dst = (src2 >> imm bytes) | (src1 << (16 - imm) bytes).
        if (imm == 0) {
          _vMovX86(dst, src2);
          break;
        }
        final lo = _copyVecX86(src2);
        _sseShiftImmX86(X86InstId.kPsrldq, lo, imm);
        final hi = _copyVecX86(src1);
        _sseShiftImmX86(X86InstId.kPslldq, hi, 16 - imm);
        _sseOpX86(X86InstId.kPor, lo, hi);
        _vMovX86(dst, lo);
        break;
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
      case UniOpVVVV.mAddU16:
      case UniOpVVVV.mAddU32:
        // dst = a * b + c (no FMA for integers).
        final r = _tmpVecX86();
        if (op == UniOpVVVV.mAddU16) {
          _vMovX86(r, src1);
          _sseOpX86(X86InstId.kPmullw, r, src2);
          _sseOpX86(X86InstId.kPaddw, r, src3);
        } else {
          _emit3vX86(UniOpVVV.mulU32, r, src1, src2);
          _sseOpX86(X86InstId.kPaddd, r, src3);
        }
        _vMovX86(dst, r);
        break;
      case UniOpVVVV.mAddF32:
      case UniOpVVVV.mAddF64:
      case UniOpVVVV.mSubF32:
      case UniOpVVVV.mSubF64:
      case UniOpVVVV.mAddF32S:
      case UniOpVVVV.mAddF64S:
      case UniOpVVVV.mSubF32S:
      case UniOpVVVV.mSubF64S:
        // dst = a * b +/- c (separate multiply and add; no FMA encoding yet).
        final n = op.name;
        final f64 = n.contains('F64');
        final scalar = n.endsWith('S');
        final isSub = n.startsWith('mSub');
        final mul = scalar
            ? (f64 ? X86InstId.kMulsd : X86InstId.kMulss)
            : (f64 ? X86InstId.kMulpd : X86InstId.kMulps);
        final addSub = scalar
            ? (f64
                ? (isSub ? X86InstId.kSubsd : X86InstId.kAddsd)
                : (isSub ? X86InstId.kSubss : X86InstId.kAddss))
            : (f64
                ? (isSub ? X86InstId.kSubpd : X86InstId.kAddpd)
                : (isSub ? X86InstId.kSubps : X86InstId.kAddps));
        final r = _copyVecX86(src1);
        _sseOpX86(mul, r, src2);
        _sseOpX86(addSub, r, src3);
        _vMovX86(dst, r);
        break;
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

/// Row of `sse_float_inst` (unicompiler_x86.cpp) used by the SSE rounding
/// helpers.
class _X86FloatInst {
  final int fmovs, fand, for_, fxor, fandn, fadd, fsub, fcmp, fround;
  final int psrl, psll, fmovu, fmul, fdiv;
  int get fmova => X86InstId.kMovaps;

  const _X86FloatInst(
      this.fmovs,
      this.fand,
      this.for_,
      this.fxor,
      this.fandn,
      this.fadd,
      this.fsub,
      this.fcmp,
      this.fround,
      this.psrl,
      this.psll,
      this.fmovu,
      this.fmul,
      this.fdiv);
}
