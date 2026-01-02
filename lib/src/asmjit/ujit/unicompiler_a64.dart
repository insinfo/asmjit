part of 'unicompiler.dart';

/// AArch64-specific functionality for UniCompiler.
mixin UniCompilerA64 on UniCompilerBase {
  // ============================================================================
  // [A64 Internal Dispatchers]
  // ============================================================================

  /// Maps UniCondition/CondCode to AArch64 condition code.
  int _condToA64(int cc) {
    switch (cc) {
      case CondCode.kEqual:
        return 0; // EQ
      case CondCode.kNotEqual:
        return 1; // NE
      case CondCode.kSignedLT:
        return 11; // LT
      case CondCode.kSignedGE:
        return 10; // GE
      case CondCode.kSignedLE:
        return 13; // LE
      case CondCode.kSignedGT:
        return 12; // GT
      case CondCode.kUnsignedLT:
        return 3; // CC/LO
      case CondCode.kUnsignedGE:
        return 2; // CS/HS
      case CondCode.kUnsignedLE:
        return 9; // LS
      case CondCode.kUnsignedGT:
        return 8; // HI
      case CondCode.kOverflow:
        return 6; // VS
      case CondCode.kNotOverflow:
        return 7; // VC
      case CondCode.kSign:
        return 4; // MI
      case CondCode.kNotSign:
        return 5; // PL
      case CondCode.kParityEven:
        return 6; // VS (Unordered)
      case CondCode.kParityOdd:
        return 7; // VC (Ordered)
      default:
        return 14; // AL (Always)
    }
  }

  void _emitVMA64(
      UniOpVM op, BaseReg dst, A64Mem src, Alignment alignment, int idx) {
    if (dst is A64Vec) {
      // Map UniOpVM to A64 Load instructions
      // For now, mapping everything to LDR
      // Ideally loadDup* should use LD1R (load and replicate)
      switch (op) {
        // Standard Loads (128-bit usually for A64Vec)
        case UniOpVM.load128U32:
        case UniOpVM.load128U64:
        case UniOpVM.load128F32:
        case UniOpVM.load128F64:
          cc.addNode(InstNode(A64InstId.kLdr, [dst, src]));
          return;

        // Broadcast Loads (load scalar and duplicate)
        case UniOpVM.loadDup16:
          // Assume 16-bit element
          cc.addNode(InstNode(A64InstId.kLd1r, [dst.h8, src]));
          return;
        case UniOpVM.loadDup32:
          // Assume 32-bit element
          cc.addNode(InstNode(A64InstId.kLd1r, [dst.s4, src]));
          return;
        case UniOpVM.loadDup64:
          // Assume 64-bit element
          cc.addNode(InstNode(A64InstId.kLd1r, [dst.d2, src]));
          return;

        default:
          // Simple loads fallback
          if (op.toString().contains('load')) {
            cc.addNode(InstNode(A64InstId.kLdr, [dst, src]));
            return;
          }
      }
    } else if (dst is A64Gp) {
      // GP Load
      cc.addNode(InstNode(A64InstId.kLdr, [dst, src]));
      return;
    }

    throw UnimplementedError('_emitVMA64: $op not implemented');
  }

  void _emitMVA64(
      UniOpMV op, A64Mem dst, BaseReg src, Alignment alignment, int idx) {
    if (src is A64Vec) {
      switch (op) {
        case UniOpMV.store128U32:
        case UniOpMV.store128U64:
        case UniOpMV.store128F32:
        case UniOpMV.store128F64:
          cc.addNode(InstNode(A64InstId.kStr, [src, dst]));
          return;
        default:
          break;
      }
    }
    throw UnimplementedError('_emitMVA64: $op not implemented');
  }

  void _emit2vA64(UniOpVV op, Operand dst, Operand src) {
    if (op == UniOpVV.mov) {
      if (dst is A64Vec && src is A64Vec) {
        cc.addNode(InstNode(A64InstId.kOrr, [dst, src, src]));
      } else if (dst is A64Gp && src is A64Gp) {
        cc.addNode(InstNode(A64InstId.kMov, [dst, src]));
      }
      return;
    }

    // Broadcasts
    if (src is A64Gp) {
      if (op == UniOpVV.broadcastU8 ||
          op == UniOpVV.broadcastU16 ||
          op == UniOpVV.broadcastU32 ||
          op == UniOpVV.broadcastU64) {
        cc.addNode(InstNode(A64InstId.kDup, [dst, src]));
        return;
      }
    }

    if (dst is A64Vec && src is A64Vec) {
      switch (op) {
        case UniOpVV.notU32:
        case UniOpVV.notU64:
          cc.addNode(InstNode(A64InstId.kMvn, [dst, src]));
          return;

        case UniOpVV.negF32:
        case UniOpVV.negF64:
          cc.addNode(InstNode(A64InstId.kFneg, [dst, src]));
          return;

        case UniOpVV.absF32:
        case UniOpVV.absF64:
          cc.addNode(InstNode(A64InstId.kFabs, [dst, src]));
          return;

        case UniOpVV.sqrtF32:
        case UniOpVV.sqrtF64:
          cc.addNode(InstNode(A64InstId.kFsqrt, [dst, src]));
          return;

        case UniOpVV.absI8:
        case UniOpVV.absI16:
        case UniOpVV.absI32:
        case UniOpVV.absI64:
          cc.addNode(InstNode(A64InstId.kAbs, [dst, src]));
          return;

        // Conversions
        case UniOpVV.cvtI32ToF32:
        case UniOpVV.cvtI32LoToF64:
          cc.addNode(InstNode(A64InstId.kScvtf, [dst, src]));
          return;

        case UniOpVV.cvtTruncF32ToI32:
        case UniOpVV.cvtTruncF64ToI32Lo:
        case UniOpVV.cvtTruncF64ToI32Hi:
          cc.addNode(InstNode(A64InstId.kFcvtzs, [dst, src]));
          return;

        case UniOpVV.cvtF32LoToF64:
        case UniOpVV.cvtF64ToF32Lo:
          cc.addNode(InstNode(A64InstId.kFcvt, [dst, src]));
          return;

        default:
          break;
      }
    }

    throw UnimplementedError('_emit2vA64: $op not implemented');
  }

  void _emit3vA64(UniOpVVV op, Operand dst, Operand src1, Operand src2) {
    if (dst is A64Vec && src1 is A64Vec && src2 is A64Vec) {
      switch (op) {
        // Bitwise ops
        case UniOpVVV.andU32:
        case UniOpVVV.andU64:
        case UniOpVVV.andF32:
        case UniOpVVV.andF64:
          cc.addNode(InstNode(A64InstId.kAnd, [dst, src1, src2]));
          return;

        case UniOpVVV.orU32:
        case UniOpVVV.orU64:
        case UniOpVVV.orF32:
        case UniOpVVV.orF64:
          cc.addNode(InstNode(A64InstId.kOrr, [dst, src1, src2]));
          return;

        case UniOpVVV.xorU32:
        case UniOpVVV.xorU64:
        case UniOpVVV.xorF32:
        case UniOpVVV.xorF64:
          cc.addNode(InstNode(A64InstId.kEor, [dst, src1, src2]));
          return;

        case UniOpVVV.bicU32:
        case UniOpVVV.bicU64:
        case UniOpVVV.bicF32:
        case UniOpVVV.bicF64:
        case UniOpVVV.andnU32:
        case UniOpVVV.andnU64:
        case UniOpVVV.andnF32:
        case UniOpVVV.andnF64:
          cc.addNode(InstNode(A64InstId.kBic, [dst, src1, src2]));
          return;

        // Integer Arithmetic
        case UniOpVVV.addU8:
        case UniOpVVV.addU16:
        case UniOpVVV.addU32:
        case UniOpVVV.addU64:
          cc.addNode(InstNode(A64InstId.kAdd, [dst, src1, src2]));
          return;

        case UniOpVVV.subU8:
        case UniOpVVV.subU16:
        case UniOpVVV.subU32:
        case UniOpVVV.subU64:
          cc.addNode(InstNode(A64InstId.kSub, [dst, src1, src2]));
          return;

        case UniOpVVV.mulU16:
        case UniOpVVV.mulU32:
          cc.addNode(InstNode(A64InstId.kMul, [dst, src1, src2]));
          return;

        // Floating Point Arithmetic
        case UniOpVVV.addF32:
        case UniOpVVV.addF64:
          cc.addNode(InstNode(A64InstId.kFadd, [dst, src1, src2]));
          return;

        case UniOpVVV.subF32:
        case UniOpVVV.subF64:
          cc.addNode(InstNode(A64InstId.kFsub, [dst, src1, src2]));
          return;

        case UniOpVVV.mulF32:
        case UniOpVVV.mulF64:
          cc.addNode(InstNode(A64InstId.kFmul, [dst, src1, src2]));
          return;

        case UniOpVVV.divF32:
        case UniOpVVV.divF64:
          cc.addNode(InstNode(A64InstId.kFdiv, [dst, src1, src2]));
          return;

        // Min/Max
        case UniOpVVV.minU8:
        case UniOpVVV.minU16:
        case UniOpVVV.minU32:
          cc.addNode(InstNode(A64InstId.kUmin, [dst, src1, src2]));
          return;

        case UniOpVVV.minI8:
        case UniOpVVV.minI16:
        case UniOpVVV.minI32:
          cc.addNode(InstNode(A64InstId.kSmin, [dst, src1, src2]));
          return;

        case UniOpVVV.maxU8:
        case UniOpVVV.maxU16:
        case UniOpVVV.maxU32:
          cc.addNode(InstNode(A64InstId.kUmax, [dst, src1, src2]));
          return;

        case UniOpVVV.maxI8:
        case UniOpVVV.maxI16:
        case UniOpVVV.maxI32:
          cc.addNode(InstNode(A64InstId.kSmax, [dst, src1, src2]));
          return;

        case UniOpVVV.minF32:
        case UniOpVVV.minF64:
          cc.addNode(InstNode(A64InstId.kFmin, [dst, src1, src2]));
          return;

        case UniOpVVV.maxF32:
        case UniOpVVV.maxF64:
          cc.addNode(InstNode(A64InstId.kFmax, [dst, src1, src2]));
          return;

        // Shuffles / Permutes
        case UniOpVVV.interleaveLoU8:
        case UniOpVVV.interleaveLoU16:
        case UniOpVVV.interleaveLoU32:
        case UniOpVVV.interleaveLoU64:
          cc.addNode(InstNode(A64InstId.kZip1, [dst, src1, src2]));
          return;

        case UniOpVVV.interleaveHiU8:
        case UniOpVVV.interleaveHiU16:
        case UniOpVVV.interleaveHiU32:
        case UniOpVVV.interleaveHiU64:
          cc.addNode(InstNode(A64InstId.kZip2, [dst, src1, src2]));
          return;

        case UniOpVVV.swizzlevU8:
          // TBL dst, {src1}, src2 (table). A64 TBL inputs are Table, Indices.
          // UniOp swizzlevU8 (dst, vec, indices) -> TBL dst, {vec}, indices
          // TBL takes a List of registers for the table. Here just 1.
          // We need TBL instruction support. Assuming kTbl exists.
          // TBL syntax: TBL Vd.Ta, {Vn.16B}, Vm.16B
          cc.addNode(InstNode(A64InstId.kTbl, [dst, src1, src2]));
          return;

        // Comparisons (Equal)
        case UniOpVVV.cmpEqU8:
        case UniOpVVV.cmpEqU16:
        case UniOpVVV.cmpEqU32:
        case UniOpVVV.cmpEqU64:
          cc.addNode(InstNode(A64InstId.kCmeq, [dst, src1, src2]));
          return;

        // Comparisons (Greater Than Signed)
        case UniOpVVV.cmpGtI8:
        case UniOpVVV.cmpGtI16:
        case UniOpVVV.cmpGtI32:
        case UniOpVVV.cmpGtI64:
          cc.addNode(InstNode(A64InstId.kCmgt, [dst, src1, src2]));
          return;

        // Comparisons (Greater Than Unsigned)
        case UniOpVVV.cmpGtU8:
        case UniOpVVV.cmpGtU16:
        case UniOpVVV.cmpGtU32:
        case UniOpVVV.cmpGtU64:
          cc.addNode(InstNode(A64InstId.kCmhi, [dst, src1, src2]));
          return;

        // Comparisons (Greater or Equal Signed)
        case UniOpVVV.cmpGeI8:
        case UniOpVVV.cmpGeI16:
        case UniOpVVV.cmpGeI32:
        case UniOpVVV.cmpGeI64:
          cc.addNode(InstNode(A64InstId.kCmge, [dst, src1, src2]));
          return;

        // Comparisons (Greater or Equal Unsigned)
        case UniOpVVV.cmpGeU8:
        case UniOpVVV.cmpGeU16:
        case UniOpVVV.cmpGeU32:
        case UniOpVVV.cmpGeU64:
          cc.addNode(InstNode(A64InstId.kCmhs, [dst, src1, src2]));
          return;

        // Average (unsigned rounded)
        case UniOpVVV.avgrU8:
        case UniOpVVV.avgrU16:
          cc.addNode(InstNode(A64InstId.kUrhadd, [dst, src1, src2]));
          return;

        // Saturating Add/Sub
        case UniOpVVV.addsI8:
        case UniOpVVV.addsI16:
          cc.addNode(InstNode(A64InstId.kSqadd, [dst, src1, src2]));
          return;
        case UniOpVVV.addsU8:
        case UniOpVVV.addsU16:
          cc.addNode(InstNode(A64InstId.kUqadd, [dst, src1, src2]));
          return;
        case UniOpVVV.subsI8:
        case UniOpVVV.subsI16:
          cc.addNode(InstNode(A64InstId.kSqsub, [dst, src1, src2]));
          return;
        case UniOpVVV.subsU8:
        case UniOpVVV.subsU16:
          cc.addNode(InstNode(A64InstId.kUqsub, [dst, src1, src2]));
          return;

        default:
          break;
      }
    }

    throw UnimplementedError('_emit3vA64: $op not implemented');
  }

  void _emit2viA64(UniOpVVI op, Operand dst, Operand src, int imm) {
    if (dst is A64Vec && src is A64Vec) {
      switch (op) {
        // Logical Shift Left
        case UniOpVVI.sllU16:
        case UniOpVVI.sllU32:
        case UniOpVVI.sllU64:
          cc.addNode(InstNode(A64InstId.kShl, [dst, src, Imm(imm)]));
          return;

        // Logical Shift Right (Unsigned)
        case UniOpVVI.srlU16:
        case UniOpVVI.srlU32:
        case UniOpVVI.srlU64:
          cc.addNode(InstNode(A64InstId.kUshr, [dst, src, Imm(imm)]));
          return;

        // Arithmetic Shift Right (Signed)
        case UniOpVVI.sraI16:
        case UniOpVVI.sraI32:
        case UniOpVVI.sraI64:
          cc.addNode(InstNode(A64InstId.kSshr, [dst, src, Imm(imm)]));
          return;

        // Byte Shifts (Whole vector)
        // AArch64 doesn't have direct whole-vector shift by bytes instruction except via EXT (for right shift).
        // Left shift bytes (sllb) can be done with EXT if we zero-extend?
        // DST = EXT(SRC, ZERO, 16 - imm) ?
        // Usually handled by specific helper or EXT.
        // For now, leaving sllb/srlb unimplemented or stubbed.

        default:
          break;
      }
    }

    throw UnimplementedError('_emit2viA64: $op not implemented');
  }

  void _emit3viA64(
      UniOpVVVI op, Operand dst, Operand src1, Operand src2, int imm) {
    if (dst is A64Vec && src1 is A64Vec && src2 is A64Vec) {
      if (op == UniOpVVVI.alignrU128) {
        // alignr (x86: palignr) concatenates src1:src2 and extracts.
        // x86: palignr dst, src, imm -> dst = (src:dst) >> (imm*8)
        // A64 EXT: ext dst, src1, src2, imm -> dst = (src1:src2) >> (imm*8) ??
        // Need to check operand order.
        // A64 EXT Rd, Rn, Rm, imm:  Rd = (Rm:Rn) >> (imm*8). (Low bits are Rn, High bits are Rm).
        // Wait, AsmJit usually maps src1, src2.
        // If UJIT semantics follow x86 palignr: "concatenates dest and src".
        // In UJIT emit3vi: dst, src1, src2.
        // So likely: dst = (src1:src2) shifted.
        cc.addNode(InstNode(A64InstId.kExt, [dst, src1, src2, Imm(imm)]));
        return;
      }
    }
    throw UnimplementedError('_emit3viA64: $op not implemented');
  }

  void _emit4vA64(
      UniOpVVVV op, Operand dst, Operand src1, Operand src2, Operand src3) {
    if (dst is A64Vec && src1 is A64Vec && src2 is A64Vec && src3 is A64Vec) {
      // FMA: dst = src1 * src2 + src3
      // A64 FMADD: Rd = Rn * Rm + Ra
      // Mapping: Rd=dst, Rn=src1, Rm=src2, Ra=src3.

      switch (op) {
        case UniOpVVVV.mAddF32:
        case UniOpVVVV.mAddF64:
          cc.addNode(InstNode(A64InstId.kFmadd, [dst, src1, src2, src3]));
          return;

        case UniOpVVVV.mSubF32:
        case UniOpVVVV.mSubF64:
          cc.addNode(InstNode(A64InstId.kFmsub, [dst, src1, src2, src3]));
          return;

        default:
          break;
      }
    }
    throw UnimplementedError('_emit4vA64: $op not implemented');
  }

  void _emit5vA64(UniOpVVVVV op, Operand dst, Operand src1, Operand src2,
      Operand src3, Operand src4) {
    throw UnimplementedError('_emit5vA64: $op not implemented');
  }

  void _emit9vA64(
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
    throw UnimplementedError('_emit9vA64: $op not implemented');
  }

  void _emitCmovA64(UniCondition cond, BaseReg dst, Operand src) {
    if (src is BaseReg) {
      // CSEL dst, src, dst, cond
      // cond is UniCondition. cond.cond is the CondCode int.
      cc.addNode(InstNode(
          A64InstId.kCsel, [dst, src, dst, Imm(_condToA64(cond.cond))]));
      return;
    }
    throw UnimplementedError('_emitCmovA64 not implemented');
  }

  void _emitSelectA64(
      UniCondition cond, BaseReg dst, Operand src1, Operand src2) {
    // dst = cond ? src1 : src2
    // CSEL dst, src1, src2, cond
    cc.addNode(InstNode(
        A64InstId.kCsel, [dst, src1, src2, Imm(_condToA64(cond.cond))]));
    return;
  }
}
