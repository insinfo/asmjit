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

  /// Vector view of [reg] with exactly [bits] bits (keeps the register id).
  A64Vec _vecView(BaseReg reg, int bits) => A64Vec(reg.id, bits);

  /// Memory access size in bits of plain vector loads (`vec_load_mem`).
  static int? _vmLoadBits(UniOpVM op) {
    switch (op) {
      case UniOpVM.load8:
        return 8;
      case UniOpVM.load16U16:
        return 16;
      case UniOpVM.load32U32:
      case UniOpVM.load32F32:
        return 32;
      case UniOpVM.load64U32:
      case UniOpVM.load64U64:
      case UniOpVM.load64F32:
      case UniOpVM.load64F64:
        return 64;
      case UniOpVM.load128U32:
      case UniOpVM.load128U64:
      case UniOpVM.load128F32:
      case UniOpVM.load128F64:
      case UniOpVM.loadNU32:
      case UniOpVM.loadNU64:
      case UniOpVM.loadNF32:
      case UniOpVM.loadNF64:
        return 128;
      default:
        return null;
    }
  }

  void _emitVMA64(
      UniOpVM op, BaseReg dst, A64Mem src, Alignment alignment, int idx) {
    if (!dst.isVec) {
      throw ArgumentError('_emitVMA64 expects a vector destination: $dst');
    }

    // Plain loads read exactly the access size (narrow loads zero the rest),
    // mirroring `vec_load_mem()` in unicompiler_a64.cpp.
    final bits = _vmLoadBits(op);
    if (bits != null) {
      cc.addNode(InstNode(A64InstId.kLdr, [_vecView(dst, bits), src]));
      return;
    }

    // loadCvt*: load exactly the source bytes, then widen in registers
    // (vec_load_mem + emit_2v(cvt) in unicompiler_a64.cpp).
    final cvt =
        RegExp(r'^loadCvt(16|32|64|128|N)([IU])(8|16|32)To[IU](16|32|64)$')
            .firstMatch(op.name);
    if (cvt != null) {
      final memBits = cvt.group(1) == 'N' ? 64 : int.parse(cvt.group(1)!);
      if (memBits > 64) {
        throw UnimplementedError('_emitVMA64: $op (NEON vectors are 128-bit)');
      }
      cc.addNode(InstNode(A64InstId.kLdr, [_vecView(dst, memBits), src]));
      final sign = cvt.group(2)!;
      for (int w = int.parse(cvt.group(3)!);
          w < int.parse(cvt.group(4)!);
          w *= 2) {
        (this as UniCompiler).emit2v(
            UniOpVV.values.byName('cvt$sign${w}LoTo$sign${w * 2}'), dst, dst);
      }
      return;
    }

    // loadInsert*: load one element and insert it into lane [idx].
    final ins = const {
      UniOpVM.loadInsertU8: 0,
      UniOpVM.loadInsertU16: 1,
      UniOpVM.loadInsertU32: 2,
      UniOpVM.loadInsertF32: 2,
      UniOpVM.loadInsertU64: 3,
      UniOpVM.loadInsertF64: 3,
      UniOpVM.loadInsertF32x2: 3,
    }[op];
    if (ins != null) {
      final tmp = newVecWithWidth(VecWidth.k128, '@ins');
      cc.addNode(InstNode(A64InstId.kLdr, [_vecView(tmp, 8 << ins), src]));
      cc.addNode(InstNode(A64InstId.kMov,
          [_vArr(dst, ins), Imm(idx), _vArr(tmp, ins), Imm(0)]));
      return;
    }

    switch (op) {
      case UniOpVM.loadDup16:
        cc.addNode(
            InstNode(A64InstId.kLd1r, [_toA64Vec(dst, A64Layout.h8), src]));
        return;
      case UniOpVM.loadDup32:
        cc.addNode(
            InstNode(A64InstId.kLd1r, [_toA64Vec(dst, A64Layout.s4), src]));
        return;
      case UniOpVM.loadDup64:
        cc.addNode(
            InstNode(A64InstId.kLd1r, [_toA64Vec(dst, A64Layout.d2), src]));
        return;
      default:
        throw UnimplementedError('_emitVMA64: $op not implemented');
    }
  }

  void _emitMVA64(
      UniOpMV op, A64Mem dst, BaseReg src, Alignment alignment, int idx) {
    if (!src.isVec) {
      throw ArgumentError('_emitMVA64 expects a vector source: $src');
    }
    // storeExtract*: store lane [idx] (moved to lane 0 of a temporary first).
    final ext = const {
      UniOpMV.storeExtractU16: 1,
      UniOpMV.storeExtractU32: 2,
      UniOpMV.storeExtractU64: 3,
    }[op];
    if (ext != null) {
      var from = src;
      if (idx != 0) {
        from = newVecWithWidth(VecWidth.k128, '@ext');
        cc.addNode(InstNode(A64InstId.kMov,
            [_vArr(from, ext), Imm(0), _vArr(src, ext), Imm(idx)]));
      }
      cc.addNode(InstNode(A64InstId.kStr, [_vecView(from, 8 << ext), dst]));
      return;
    }

    // Stores write exactly the access size (emit_mv in unicompiler_a64.cpp).
    final int bits;
    switch (op) {
      case UniOpMV.store8:
        bits = 8;
      case UniOpMV.store16U16:
        bits = 16;
      case UniOpMV.store32U32:
      case UniOpMV.store32F32:
        bits = 32;
      case UniOpMV.store64U32:
      case UniOpMV.store64U64:
      case UniOpMV.store64F32:
      case UniOpMV.store64F64:
        bits = 64;
      case UniOpMV.store128U32:
      case UniOpMV.store128U64:
      case UniOpMV.store128F32:
      case UniOpMV.store128F64:
      case UniOpMV.storeNU32:
      case UniOpMV.storeNU64:
      case UniOpMV.storeNF32:
      case UniOpMV.storeNF64:
        bits = 128;
      default:
        throw UnimplementedError('_emitMVA64: $op not implemented');
    }
    cc.addNode(InstNode(A64InstId.kStr, [_vecView(src, bits), dst]));
  }

  /// Port of `UniCompiler::emit_rm()` (unicompiler_a64.cpp).
  void _emitRMA64(UniOpRM op, BaseReg dst, A64Mem src) {
    if (dst is! A64Gp) {
      throw ArgumentError('_emitRMA64 expects a GP destination: $dst');
    }
    switch (op) {
      case UniOpRM.loadReg:
        cc.addNode(InstNode(A64InstId.kLdr, [dst, src]));
      case UniOpRM.loadI8:
        cc.addNode(InstNode(A64InstId.kLdrsb, [dst, src]));
      case UniOpRM.loadU8:
        cc.addNode(InstNode(A64InstId.kLdrb, [dst.w, src]));
      case UniOpRM.loadI16:
        cc.addNode(InstNode(A64InstId.kLdrsh, [dst, src]));
      case UniOpRM.loadU16:
        cc.addNode(InstNode(A64InstId.kLdrh, [dst.w, src]));
      case UniOpRM.loadI32:
        cc.addNode(InstNode(
            dst.is64Bit ? A64InstId.kLdrsw : A64InstId.kLdr, [dst, src]));
      case UniOpRM.loadU32:
        cc.addNode(InstNode(A64InstId.kLdr, [dst.w, src]));
      case UniOpRM.loadI64:
      case UniOpRM.loadU64:
        cc.addNode(InstNode(A64InstId.kLdr, [dst.x, src]));
      case UniOpRM.loadShiftU8:
      case UniOpRM.loadShiftU16:
      case UniOpRM.loadMergeU8:
      case UniOpRM.loadMergeU16:
        final isU8 = op == UniOpRM.loadShiftU8 || op == UniOpRM.loadMergeU8;
        final tmp = (cc as A64Compiler).newGp(dst.type, '@tmp');
        cc.addNode(
            InstNode(isU8 ? A64InstId.kLdrb : A64InstId.kLdrh, [tmp.w, src]));
        if (op == UniOpRM.loadShiftU8 || op == UniOpRM.loadShiftU16) {
          // dst = tmp | (dst << size)
          cc.addNode(InstNode(A64InstId.kLsl, [dst, dst, Imm(isU8 ? 8 : 16)]));
        }
        cc.addNode(InstNode(A64InstId.kOrr, [dst, dst, tmp]));
    }
  }

  /// Port of `UniCompiler::emit_mr()` (unicompiler_a64.cpp).
  void _emitMRA64(UniOpMR op, A64Mem dst, BaseReg src) {
    if (src is! A64Gp) {
      throw ArgumentError('_emitMRA64 expects a GP source: $src');
    }
    final (int storeId, int size, bool add) = switch (op) {
      UniOpMR.storeReg => (A64InstId.kStr, 0, false),
      UniOpMR.storeU8 => (A64InstId.kStrb, 1, false),
      UniOpMR.storeU16 => (A64InstId.kStrh, 2, false),
      UniOpMR.storeU32 => (A64InstId.kStr, 4, false),
      UniOpMR.storeU64 => (A64InstId.kStr, 8, false),
      UniOpMR.addReg => (A64InstId.kStr, 0, true),
      UniOpMR.addU8 => (A64InstId.kStrb, 1, true),
      UniOpMR.addU16 => (A64InstId.kStrh, 2, true),
      UniOpMR.addU32 => (A64InstId.kStr, 4, true),
      UniOpMR.addU64 => (A64InstId.kStr, 8, true),
    };
    final r = (size >= 1 && size <= 4) ? src.w : (size == 8 ? src.x : src);

    if (!add) {
      cc.addNode(InstNode(storeId, [r, dst]));
      return;
    }
    final tmp = (cc as A64Compiler).newGp(r.type, '@tmp');
    final loadId = switch (size) {
      1 => A64InstId.kLdrb,
      2 => A64InstId.kLdrh,
      _ => A64InstId.kLdr,
    };
    cc.addNode(InstNode(loadId, [tmp, dst]));
    cc.addNode(InstNode(A64InstId.kAdd, [tmp, tmp, r]));
    cc.addNode(InstNode(storeId, [tmp, dst]));
  }

  void _emitMA64(UniOpM op, A64Mem dst) {
    // Use ID 31 for Zero Register (WZR/XZR)
    // Note: A64Gp(id, size) - assuming constructor availability
    // If unavailable, we might need a different approach.
    // Since we are inside the package, we hopefully have access.
    // But A64Gp might depend on `a64_operand.dart`.
    // Let's just create placeholder objects if needed or assume standard construction.
    // A64Gp(31) usually means SP or ZR. In Stores it's ZR.

    // We'll trust the assembler to interpret Reg 31 as ZR for STR instructions.

    final wzr = A64Gp(31, 32);
    final xzr = A64Gp(31, 64);

    switch (op) {
      case UniOpM.storeZeroU8:
        cc.addNode(InstNode(A64InstId.kStrb, [wzr, dst]));
        break;
      case UniOpM.storeZeroU16:
        cc.addNode(InstNode(A64InstId.kStrh, [wzr, dst]));
        break;
      case UniOpM.storeZeroU32:
        cc.addNode(InstNode(A64InstId.kStr, [wzr, dst]));
        break;
      case UniOpM.storeZeroU64:
        cc.addNode(InstNode(A64InstId.kStr, [xzr, dst]));
        break;
      case UniOpM.prefetch:
        // Default prefetch PLDL1KEEP (0) ? or passed in op?
        // UniOpM.prefetch is generic.
        // PRFM pldl1keep, [addr]
        // 0 is PLDL1KEEP
        cc.addNode(InstNode(A64InstId.kPrfm, [Imm(0), dst]));
        break;
      default:
        throw UnimplementedError('_emitMA64: $op not implemented');
    }
  }

  // ============================================================================
  // [A64 SIMD Helpers]
  // ============================================================================

  A64Vec _toA64Vec(BaseReg reg, [A64Layout layout = A64Layout.none]) {
    if (reg is A64Vec) {
      return (layout != A64Layout.none && reg.layout != layout)
          ? reg.cloneWithLayout(layout)
          : reg;
    }
    if (reg.isVec) {
      return A64Vec(reg.id, 128, layout);
    }
    throw ArgumentError('Expected vector register, got $reg');
  }

  void _vZeroA64(BaseReg dst) {
    if (dst.isVec) {
      final v = _toA64Vec(dst, A64Layout.b16);
      cc.addNode(InstNode(A64InstId.kEor, [v, v, v]));
    } else {
      throw ArgumentError('vZero expects Vector, got $dst');
    }
  }

  void _vLoadAA64(BaseReg dst, A64Mem src) {
    cc.addNode(InstNode(A64InstId.kLdr, [dst, src]));
  }

  void _vMovA64(BaseReg dst, Operand src) {
    if (dst.isVec && src is BaseReg && src.isVec) {
      if (dst.id == src.id) return;
      final d = _toA64Vec(dst, A64Layout.b16);
      final s = _toA64Vec(src, A64Layout.b16);
      cc.addNode(InstNode(A64InstId.kOrr, [d, s, s]));
    } else {
      if (src is A64Mem) {
        cc.addNode(InstNode(A64InstId.kLdr, [dst, src]));
      } else {
        cc.addNode(InstNode(A64InstId.kMov, [dst, src]));
      }
    }
  }

  void _vXorA64(BaseReg dst, BaseReg a, Operand b) {
    if (dst.isVec && a.isVec && (b is BaseReg && b.isVec)) {
      final d = _toA64Vec(dst, A64Layout.b16);
      final s1 = _toA64Vec(a, A64Layout.b16);
      final s2 = _toA64Vec(b, A64Layout.b16);
      cc.addNode(InstNode(A64InstId.kEor, [d, s1, s2]));
    } else {
      throw UnimplementedError('_vXorA64: operands must be Vectors');
    }
  }

  void _vOrA64(BaseReg dst, BaseReg a, Operand b) {
    if (dst.isVec && a.isVec && (b is BaseReg && b.isVec)) {
      final d = _toA64Vec(dst, A64Layout.b16);
      final s1 = _toA64Vec(a, A64Layout.b16);
      final s2 = _toA64Vec(b, A64Layout.b16);
      cc.addNode(InstNode(A64InstId.kOrr, [d, s1, s2]));
    } else {
      throw UnimplementedError('_vOrA64: operands must be Vectors');
    }
  }

  void _vAndA64(BaseReg dst, BaseReg a, Operand b) {
    if (dst.isVec && a.isVec && (b is BaseReg && b.isVec)) {
      final d = _toA64Vec(dst, A64Layout.b16);
      final s1 = _toA64Vec(a, A64Layout.b16);
      final s2 = _toA64Vec(b, A64Layout.b16);
      cc.addNode(InstNode(A64InstId.kAnd, [d, s1, s2]));
    } else {
      throw UnimplementedError('_vAndA64: operands must be Vectors');
    }
  }

  void _vAndNotA64(BaseReg dst, BaseReg a, Operand b) {
    if (dst.isVec && a.isVec && (b is BaseReg && b.isVec)) {
      final d = _toA64Vec(dst, A64Layout.b16);
      final s1 = _toA64Vec(a, A64Layout.b16);
      final s2 = _toA64Vec(b, A64Layout.b16);
      cc.addNode(InstNode(A64InstId.kBic, [d, s1, s2]));
    } else {
      throw UnimplementedError('_vAndNotA64: operands must be Vectors');
    }
  }

  // TBL (Table Lookup for Shuffle)
  // ZIP1/ZIP2 (Interleave)
  // SQXTN (Signed Saturating Narrow) - for Packing
  // SQXTN2 (Signed Saturating Narrow High)
  // UQXTN (Unsigned Saturating Narrow)
  // UQXTN2
  // ============================================================================
  // [Dispatchers]
  // ============================================================================

  /// Port of `UniCompiler::emit_2v()` (unicompiler_a64.cpp).
  void _emit2vA64(UniOpVV op, Operand dst_, Operand src_) {
    final dst = dst_ as BaseReg;
    final info = kA64OpcodeInfo2v[op.index];
    final name = op.name;

    switch (op) {
      case UniOpVV.mov:
        _vMovA64(dst, src_);
        return;

      case UniOpVV.movU64:
        // dst.d[0] = src.d[0], upper half zeroed (MOV Vd.8B, Vn.8B).
        final src = _asVecA64(src_, dst, kFmF64S);
        final d = A64Vec(dst.id, 64, A64Layout.b8);
        final n = A64Vec(src.id, 64, A64Layout.b8);
        cc.addNode(InstNode(A64InstId.kOrr, [d, n, n]));
        return;

      case UniOpVV.broadcastU8Z:
      case UniOpVV.broadcastU16Z:
      case UniOpVV.broadcastU8:
      case UniOpVV.broadcastU16:
      case UniOpVV.broadcastU32:
      case UniOpVV.broadcastF32:
      case UniOpVV.broadcastU64:
      case UniOpVV.broadcastF64:
        final el = info.dstElement;
        final d = _vArr(dst, el);
        if (src_ is A64Gp) {
          cc.addNode(InstNode(A64InstId.kDup, [d, el <= 2 ? src_.w : src_.x]));
          return;
        }
        BaseReg src;
        if (src_ is A64Mem) {
          // Load exactly one element, then duplicate it.
          src = newVecWithWidth(VecWidth.k128, '@bcst');
          cc.addNode(InstNode(A64InstId.kLdr, [A64Vec(src.id, 8 << el), src_]));
        } else {
          src = src_ as BaseReg;
        }
        cc.addNode(InstNode(A64InstId.kDup, [d, _vArr(src, el), Imm(0)]));
        return;

      case UniOpVV.broadcastV128U32:
      case UniOpVV.broadcastV128U64:
      case UniOpVV.broadcastV128F32:
      case UniOpVV.broadcastV128F64:
        // 128-bit broadcast is a plain move (NEON vectors are 128-bit).
        _vMovA64(dst, src_);
        return;

      case UniOpVV.cvtI8ToI32:
      case UniOpVV.cvtU8ToU32:
        final src = _asVecA64(src_, dst, kFmNone);
        cc.addNode(InstNode(info.instId,
            [_vArr(dst, 1), A64Vec(src.id, 64, A64Layout.b8), Imm(0)]));
        cc.addNode(InstNode(info.instId,
            [_vArr(dst, 2), A64Vec(dst.id, 64, A64Layout.h4), Imm(0)]));
        return;

      case UniOpVV.rcpF32:
      case UniOpVV.rcpF64:
        // Intrinsic (emit_2v): dst = 1.0 / src.
        final f32 = op == UniOpVV.rcpF32;
        final one = (this as UniCompiler).simdConst(
            f32 ? VecConstTable.f32_1 : VecConstTable.f64_1,
            Bcst.kNA_Unique,
            VecWidth.k128) as BaseReg;
        final src = _asVecA64(src_, dst, kFmNone);
        final el = f32 ? 2 : 3;
        cc.addNode(InstNode(
            A64InstId.kFdiv, [_vArr(dst, el), _vArr(one, el), _vArr(src, el)]));
        return;

      case UniOpVV.roundHalfUpF32S:
      case UniOpVV.roundHalfUpF64S:
      case UniOpVV.roundHalfUpF32:
      case UniOpVV.roundHalfUpF64:
        // Intrinsic (emit_2v): dst = floor(src + (0.5 - 1ulp)).
        final f32 =
            op == UniOpVV.roundHalfUpF32S || op == UniOpVV.roundHalfUpF32;
        final scalar =
            op == UniOpVV.roundHalfUpF32S || op == UniOpVV.roundHalfUpF64S;
        final half = (this as UniCompiler).simdConst(
            f32
                ? VecConstTable.f32_0_5_minus_1ulp
                : VecConstTable.f64_0_5_minus_1ulp,
            Bcst.kNA_Unique,
            VecWidth.k128) as BaseReg;
        final src = _asVecA64(src_, dst, kFmNone);
        A64Vec view(BaseReg r) =>
            scalar ? A64Vec(r.id, f32 ? 32 : 64) : _vArr(r, f32 ? 2 : 3);
        cc.addNode(
            InstNode(A64InstId.kFadd, [view(dst), view(src), view(half)]));
        cc.addNode(InstNode(A64InstId.kFrintm, [view(dst), view(dst)]));
        return;

      case UniOpVV.cvtF32ToF64S:
      case UniOpVV.cvtF64ToF32S:
        final src = _asVecA64(src_, dst, kFmNone);
        final toDouble = op == UniOpVV.cvtF32ToF64S;
        cc.addNode(InstNode(A64InstId.kFcvt, [
          A64Vec(dst.id, toDouble ? 64 : 32),
          A64Vec(src.id, toDouble ? 32 : 64)
        ]));
        return;

      case UniOpVV.cvtI32LoToF64:
      case UniOpVV.cvtI32HiToF64:
        final src = _asVecA64(src_, dst, kFmNone);
        final lo = info.srcPart == kPartLo;
        cc.addNode(InstNode(lo ? A64InstId.kSshll : A64InstId.kSshll2,
            [_vArr(dst, 3), _vArr(src, 2, lo: lo), Imm(0)]));
        cc.addNode(InstNode(A64InstId.kScvtf, [_vArr(dst, 3), _vArr(dst, 3)]));
        return;

      case UniOpVV.cvtTruncF64ToI32Lo:
      case UniOpVV.cvtRoundF64ToI32Lo:
      case UniOpVV.cvtTruncF64ToI32Hi:
      case UniOpVV.cvtRoundF64ToI32Hi:
        final src = _asVecA64(src_, dst, kFmNone);
        final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
        cc.addNode(InstNode(info.instId, [_vArr(tmp, 3), _vArr(src, 3)]));
        if (info.dstPart == kPartLo) {
          cc.addNode(InstNode(
              A64InstId.kSqxtn, [_vArr(dst, 2, lo: true), _vArr(tmp, 3)]));
        } else {
          cc.addNode(
              InstNode(A64InstId.kSqxtn2, [_vArr(dst, 2), _vArr(tmp, 3)]));
        }
        return;

      default:
        break;
    }

    // Widening integer conversions (SSHLL/USHLL[2] #0).
    if (name.startsWith('cvt') &&
        (info.instId == A64InstId.kSshll ||
            info.instId == A64InstId.kUshll ||
            info.instId == A64InstId.kSshll2 ||
            info.instId == A64InstId.kUshll2)) {
      final lo = info.srcPart == kPartLo;
      final src = _asVecA64(src_, dst, kFmNone);
      cc.addNode(InstNode(info.instId, [
        _vArr(dst, info.dstElement),
        _vArr(src, info.srcElement, lo: lo),
        Imm(0)
      ]));
      return;
    }

    if (!info.asimd || info.instId < 0) {
      throw UnimplementedError('_emit2vA64: $op');
    }

    final src = _asVecA64(src_, dst, info.floatMode);
    switch (info.floatMode) {
      case kFmF32S:
        cc.addNode(
            InstNode(info.instId, [A64Vec(dst.id, 32), A64Vec(src.id, 32)]));
      case kFmF64S:
        cc.addNode(
            InstNode(info.instId, [A64Vec(dst.id, 64), A64Vec(src.id, 64)]));
      default:
        // FCVTL/FCVTN read/write a 64-bit half.
        cc.addNode(InstNode(info.instId, [
          _vArr(dst, info.dstElement, lo: info.dstPart == kPartLo),
          _vArr(src, info.srcElement, lo: info.srcPart == kPartLo)
        ]));
    }
  }

  static const _fullLayouts = [
    A64Layout.b16,
    A64Layout.h8,
    A64Layout.s4,
    A64Layout.d2
  ];
  static const _loLayouts = [
    A64Layout.b8,
    A64Layout.h4,
    A64Layout.s2,
    A64Layout.d1
  ];

  /// View of [reg] with element size [el] (0..3), optionally the low half.
  A64Vec _vArr(BaseReg reg, int el, {bool lo = false}) =>
      A64Vec(reg.id, lo ? 64 : 128, (lo ? _loLayouts : _fullLayouts)[el]);

  /// `as_vec()`: [op] as a vector register, loading it when it's memory.
  BaseReg _asVecA64(Operand op, BaseReg ref, int floatMode) {
    if (op is BaseReg) return op;
    if (op is A64Mem) {
      final tmp = newVecWithWidth(VecWidth.k128, '@src');
      final bits = floatMode == kFmF32S
          ? 32
          : floatMode == kFmF64S
              ? 64
              : 128;
      cc.addNode(InstNode(A64InstId.kLdr, [A64Vec(tmp.id, bits), op]));
      return tmp;
    }
    throw ArgumentError('Expected vector register or memory: $op');
  }

  /// `emit_3v_op()`: emits [instId] with the arrangement described by [info].
  void _emit3vOpA64(
      int instId, BaseReg dst, BaseReg src1, Operand src2_, A64UniOpVInfo info,
      {bool reverse = false}) {
    final src2 = _asVecA64(src2_, dst, info.floatMode);
    A64Vec d, s1, s2;
    switch (info.floatMode) {
      case kFmF32S:
        d = A64Vec(dst.id, 32);
        s1 = A64Vec(src1.id, 32);
        s2 = A64Vec(src2.id, 32);
      case kFmF64S:
        d = A64Vec(dst.id, 64);
        s1 = A64Vec(src1.id, 64);
        s2 = A64Vec(src2.id, 64);
      default:
        d = _vArr(dst, info.dstElement, lo: info.dstPart == kPartLo);
        s1 = _vArr(src1, info.srcElement, lo: info.srcPart == kPartLo);
        s2 = _vArr(src2, info.srcElement, lo: info.srcPart == kPartLo);
    }
    cc.addNode(InstNode(instId, reverse ? [d, s2, s1] : [d, s1, s2]));
  }

  /// `vec_neg()`: bitwise NOT of the scalar/vector value.
  void _vecNotA64(BaseReg dst, BaseReg src, int floatMode) {
    final A64Vec d, s;
    if (floatMode == kFmF32S || floatMode == kFmF64S) {
      // MVN only exists as a vector op; operate on the low 64 bits.
      d = A64Vec(dst.id, 64, A64Layout.b8);
      s = A64Vec(src.id, 64, A64Layout.b8);
    } else {
      d = A64Vec(dst.id, 128, A64Layout.b16);
      s = A64Vec(src.id, 128, A64Layout.b16);
    }
    cc.addNode(InstNode(A64InstId.kMvn, [d, s]));
  }

  /// Port of `UniCompiler::emit_3v()` (unicompiler_a64.cpp).
  void _emit3vA64(UniOpVVV op, Operand dst_, Operand src1_, Operand src2_) {
    final dst = dst_ as BaseReg;
    final src1 = src1_ as BaseReg;
    final info = kA64OpcodeInfo3v[op.index];

    if (src2_ is BaseReg && src2_.id == src1.id) {
      switch (info.sameVecOp) {
        case kSameZero:
          cc.addNode(InstNode(A64InstId.kMovi, [_vArr(dst, 0), Imm(0)]));
          return;
        case kSameOnes:
          cc.addNode(InstNode(A64InstId.kMovi, [_vArr(dst, 0), Imm(0xFF)]));
          return;
        case kSameSrc:
          _vMovA64(dst, src1);
          return;
      }
    }

    switch (op) {
      case UniOpVVV.minI64:
      case UniOpVVV.minU64:
      case UniOpVVV.maxI64:
      case UniOpVVV.maxU64:
        var a = src1;
        var b = _asVecA64(src2_, dst, kFmNone);
        // Min/max is commutative: make dst overlap only src1.
        if (dst.id == b.id) {
          final t = a;
          a = b;
          b = t;
        }
        final tmp =
            dst.id == a.id ? newVecWithWidth(VecWidth.k128, '@tmp') : dst;
        if (op == UniOpVVV.maxU64) {
          cc.addNode(InstNode(
              A64InstId.kUqsub, [_vArr(tmp, 3), _vArr(a, 3), _vArr(b, 3)]));
          cc.addNode(InstNode(
              A64InstId.kAdd, [_vArr(dst, 3), _vArr(tmp, 3), _vArr(b, 3)]));
          return;
        }
        cc.addNode(
            InstNode(info.instId, [_vArr(tmp, 3), _vArr(a, 3), _vArr(b, 3)]));
        // Select with the compare mask (imm=1 swaps the inputs for max).
        _blendvU8A64(dst, info.imm != 0 ? b : a, info.imm != 0 ? a : b, tmp);
        return;

      case UniOpVVV.cmpNeF32S:
      case UniOpVVV.cmpNeF64S:
      case UniOpVVV.cmpNeF32:
      case UniOpVVV.cmpNeF64:
        _emit3vOpA64(info.instId, dst, src1, src2_, info);
        _vecNotA64(dst, dst, info.floatMode);
        return;

      case UniOpVVV.cmpOrdF32S:
      case UniOpVVV.cmpOrdF64S:
      case UniOpVVV.cmpOrdF32:
      case UniOpVVV.cmpOrdF64:
      case UniOpVVV.cmpUnordF32S:
      case UniOpVVV.cmpUnordF64S:
      case UniOpVVV.cmpUnordF32:
      case UniOpVVV.cmpUnordF64:
        if (src2_ is BaseReg && src2_.id == src1.id) {
          _emit3vOpA64(A64InstId.kFcmeq, dst, src1, src1, info);
        } else {
          final src2 = _asVecA64(src2_, dst, info.floatMode);
          _emit3vOpA64(A64InstId.kFmin, dst, src1, src2, info);
          _emit3vOpA64(A64InstId.kFcmeq, dst, dst, dst, info);
        }
        if (info.imm != 0) _vecNotA64(dst, dst, info.floatMode);
        return;

      case UniOpVVV.hAddF64:
        final src2 = _asVecA64(src2_, dst, kFmNone);
        final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
        if (src1.id == src2.id) {
          cc.addNode(InstNode(A64InstId.kExt,
              [_vArr(tmp, 0), _vArr(src1, 0), _vArr(src1, 0), Imm(8)]));
          cc.addNode(InstNode(
              A64InstId.kFadd, [_vArr(dst, 3), _vArr(src1, 3), _vArr(tmp, 3)]));
        } else {
          cc.addNode(InstNode(A64InstId.kZip1,
              [_vArr(tmp, 3), _vArr(src1, 3), _vArr(src2, 3)]));
          cc.addNode(InstNode(A64InstId.kZip2,
              [_vArr(dst, 3), _vArr(src1, 3), _vArr(src2, 3)]));
          cc.addNode(InstNode(
              A64InstId.kFadd, [_vArr(dst, 3), _vArr(dst, 3), _vArr(tmp, 3)]));
        }
        return;

      case UniOpVVV.combineLoHiU64:
      case UniOpVVV.combineLoHiF64:
        // dst = {src1.u64[0], src2.u64[1]}: EXT dst, src2, src1, #8.
        final src2 = _asVecA64(src2_, dst, kFmNone);
        cc.addNode(InstNode(A64InstId.kExt,
            [_vArr(dst, 0), _vArr(src2, 0), _vArr(src1, 0), Imm(8)]));
        return;

      case UniOpVVV.packsI16I8:
      case UniOpVVV.packsI16U8:
      case UniOpVVV.packsI32I16:
      case UniOpVVV.packsI32U16:
        // Signed -> signed uses SQXTN, signed -> unsigned uses SQXTUN.
        final unsigned =
            op == UniOpVVV.packsI16U8 || op == UniOpVVV.packsI32U16;
        final lo = unsigned ? A64InstId.kSqxtun : A64InstId.kSqxtn;
        final hi = unsigned ? A64InstId.kSqxtun2 : A64InstId.kSqxtn2;
        final src2 = _asVecA64(src2_, dst, kFmNone);
        final se = info.srcElement, de = info.dstElement;
        if (src1.id == src2.id) {
          cc.addNode(InstNode(lo, [_vArr(dst, de, lo: true), _vArr(src1, se)]));
          cc.addNode(InstNode(hi, [_vArr(dst, de), _vArr(src1, se)]));
          return;
        }
        final tmp = (dst.id == src1.id || dst.id == src2.id)
            ? newVecWithWidth(VecWidth.k128, '@tmp')
            : dst;
        cc.addNode(InstNode(lo, [_vArr(tmp, de, lo: true), _vArr(src1, se)]));
        cc.addNode(InstNode(hi, [_vArr(tmp, de), _vArr(src2, se)]));
        if (tmp.id != dst.id) _vMovA64(dst, tmp);
        return;

      default:
        if (!info.asimd || info.instId < 0) {
          throw UnimplementedError('_emit3vA64: $op');
        }
        _emit3vOpA64(info.instId, dst, src1, src2_, info,
            reverse: info.reverse != 0);
    }
  }

  /// `v_blendv_u8(dst, a, b, mask)`: dst = mask ? b : a (bitwise).
  void _blendvU8A64(BaseReg dst, BaseReg a, BaseReg b, BaseReg mask) {
    final d = _vArr(dst, 0), va = _vArr(a, 0), vb = _vArr(b, 0);
    final m = _vArr(mask, 0);
    if (dst.id == a.id) {
      cc.addNode(InstNode(A64InstId.kBit, [d, vb, m]));
    } else if (dst.id == b.id) {
      cc.addNode(InstNode(A64InstId.kBif, [d, va, m]));
    } else {
      _vMovA64(dst, mask);
      cc.addNode(InstNode(A64InstId.kBsl, [d, vb, va]));
    }
  }

  void _emit5vA64(UniOpVVVVV op, Operand dst, Operand src1, Operand src2,
      Operand src3, Operand src4) {
    throw UnimplementedError('_emit5vA64');
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
    throw UnimplementedError('_emit9vA64');
  }

  void _emitCmovA64(UniCondition cond, BaseReg dst, Operand src) {
    // dst = cond ? src : dst
    if (src is BaseReg) {
      cc.addNode(InstNode(
          A64InstId.kCsel, [dst, src, dst, Imm(_condToA64(cond.cond))]));
    } else {
      throw UnimplementedError('Memory cmov not supported for A64');
    }
  }

  void _emitSelectA64(
      UniCondition cond, BaseReg dst, Operand src1, Operand src2) {
    // dst = cond ? src1 : src2
    if (src1 is BaseReg && src2 is BaseReg) {
      cc.addNode(InstNode(
          A64InstId.kCsel, [dst, src1, src2, Imm(_condToA64(cond.cond))]));
    } else {
      throw UnimplementedError('Memory select not supported for A64');
    }
  }

  /// Port of `UniCompiler::emit_2vi()` (unicompiler_a64.cpp).
  void _emit2viA64(UniOpVVI op, Operand dst_, Operand src_, int imm) {
    final dst = dst_ as BaseReg;
    final src = _asVecA64(src_, dst, kFmNone);

    switch (op) {
      case UniOpVVI.sllbU128:
      case UniOpVVI.srlbU128:
        if (imm < 0 || imm > 15) throw ArgumentError('byte shift $imm');
        if (imm == 0) {
          _vMovA64(dst, src);
          return;
        }
        final zero = newVecWithWidth(VecWidth.k128, '@zero');
        cc.addNode(InstNode(A64InstId.kMovi, [_vArr(zero, 0), Imm(0)]));
        // EXT d, n, m, #i -> d = m:n >> (8 * i).
        cc.addNode(InstNode(
            A64InstId.kExt,
            op == UniOpVVI.sllbU128
                ? [_vArr(dst, 0), _vArr(zero, 0), _vArr(src, 0), Imm(16 - imm)]
                : [_vArr(dst, 0), _vArr(src, 0), _vArr(zero, 0), Imm(imm)]));
        return;

      case UniOpVVI.swizzleU32x4:
      case UniOpVVI.swizzleF32x4:
        // dst.s[i] = src.s[(imm >> 2i) & 3] (same encoding as PSHUFD).
        final idx = [for (int i = 0; i < 4; i++) (imm >> (2 * i)) & 3];
        if (idx[0] == 0 && idx[1] == 1 && idx[2] == 2 && idx[3] == 3) {
          _vMovA64(dst, src);
          return;
        }
        final out =
            dst.id == src.id ? newVecWithWidth(VecWidth.k128, '@swz') : dst;
        for (int i = 0; i < 4; i++) {
          cc.addNode(InstNode(A64InstId.kMov,
              [_vArr(out, 2), Imm(i), _vArr(src, 2), Imm(idx[i])]));
        }
        if (out.id != dst.id) _vMovA64(dst, out);
        return;

      case UniOpVVI.swizzleU64x2:
      case UniOpVVI.swizzleF64x2:
        final i0 = imm & 1, i1 = (imm >> 1) & 1;
        if (i0 == 0 && i1 == 1) {
          _vMovA64(dst, src);
        } else if (i0 == 1 && i1 == 0) {
          cc.addNode(InstNode(A64InstId.kExt,
              [_vArr(dst, 0), _vArr(src, 0), _vArr(src, 0), Imm(8)]));
        } else {
          final out =
              dst.id == src.id ? newVecWithWidth(VecWidth.k128, '@swz') : dst;
          cc.addNode(InstNode(
              A64InstId.kMov, [_vArr(out, 3), Imm(0), _vArr(src, 3), Imm(i0)]));
          cc.addNode(InstNode(
              A64InstId.kMov, [_vArr(out, 3), Imm(1), _vArr(src, 3), Imm(i1)]));
          if (out.id != dst.id) _vMovA64(dst, out);
        }
        return;

      default:
        if (op.index >= kA64OpcodeInfo2vi.length) {
          throw UnimplementedError('_emit2viA64: $op');
        }
        final info = kA64OpcodeInfo2vi[op.index];
        if (!info.asimd || info.instId < 0) {
          throw UnimplementedError('_emit2viA64: $op');
        }
        // Narrowing shifts write the low (SHRN) or high (SHRN2) half.
        final d = _vArr(dst, info.dstElement,
            lo: info.dstPart == kPartLo ||
                (info.srcPart == kPartLo && info.dstElement < info.srcElement));
        final s = _vArr(src, info.srcElement);
        cc.addNode(InstNode(info.instId, [d, s, Imm(imm)]));
    }
  }

  void _vExtA64(
      BaseReg dst, BaseReg src1, BaseReg src2, int imm, A64Layout layout) {
    cc.addNode(InstNode(A64InstId.kExt, [
      _toA64Vec(dst, layout),
      _toA64Vec(src1, layout),
      _toA64Vec(src2, layout),
      Imm(imm)
    ]));
  }

  void _emit3viA64(
      UniOpVVVI op, Operand dst, Operand src1, Operand src2, int imm) {
    final d = dst as BaseReg;
    final s1 = src1 as BaseReg;
    final s2 = src2 as BaseReg;

    switch (op) {
      case UniOpVVVI.alignrU128:
        // PALIGNR semantics (src1 high, src2 low): EXT dst, src2, src1, #imm.
        if (imm == 0) {
          _vMovA64(d, s2);
        } else {
          _vExtA64(d, s2, s1, imm, A64Layout.b16);
        }
        break;
      case UniOpVVVI.interleaveShuffleU32x4:
      case UniOpVVVI.interleaveShuffleF32x4:
        final mask = Uint8List(16);
        for (int i = 0; i < 4; i++) {
          int sel = (imm >> (i * 2)) & 3;
          int base = (i < 2) ? 0 : 16;
          int byteIndex = base + sel * 4;
          mask[i * 4 + 0] = byteIndex + 0;
          mask[i * 4 + 1] = byteIndex + 1;
          mask[i * 4 + 2] = byteIndex + 2;
          mask[i * 4 + 3] = byteIndex + 3;
        }
        _emitTbl2(d, s1, s2, mask);
        break;

      case UniOpVVVI.interleaveShuffleU64x2:
      case UniOpVVVI.interleaveShuffleF64x2:
        final mask = Uint8List(16);
        for (int i = 0; i < 2; i++) {
          int sel = (imm >> i) & 1;
          int base = (i == 0) ? 0 : 16;
          int byteIndex = base + sel * 8;
          for (int j = 0; j < 8; j++) {
            mask[i * 8 + j] = byteIndex + j;
          }
        }
        _emitTbl2(d, s1, s2, mask);
        break;

      default:
        throw UnimplementedError('_emit3viA64: $op');
    }
  }

  void _emitTbl2(BaseReg d, BaseReg s1, BaseReg s2, Uint8List mask) {
    final mask1Bytes = Uint8List(16);
    final mask2Bytes = Uint8List(16);

    for (int i = 0; i < 16; i++) {
      int idx = mask[i];
      if (idx < 16) {
        mask1Bytes[i] = idx;
        mask2Bytes[i] = 0xFF;
      } else {
        mask1Bytes[i] = 0xFF;
        mask2Bytes[i] = idx - 16;
      }
    }

    final vc1 = VecConst(16, mask1Bytes);
    final vc2 = VecConst(16, mask2Bytes);

    final m1 = _newVecConst(vc1, true);
    final m2 = _newVecConst(vc2, true);

    final tmp = newVecWithWidth(_vecWidth, "tmp_tbl");

    // TBL d, {s1}, m1
    cc.addNode(InstNode(A64InstId.kTbl, [d, s1, m1]));
    // TBL tmp, {s2}, m2
    cc.addNode(InstNode(A64InstId.kTbl, [tmp, s2, m2]));
    // ORR d, d, tmp
    _vOrA64(d, d, tmp);
  }

  /// Port of `UniCompiler::emit_4v()` (unicompiler_a64.cpp).
  void _emit4vA64(
      UniOpVVVV op, Operand dst_, Operand src1_, Operand src2_, Operand src3_) {
    final dst = dst_ as BaseReg;
    final s1 = _asVecA64(src1_, dst, kFmNone);
    final s2 = _asVecA64(src2_, dst, kFmNone);
    final s3 = _asVecA64(src3_, dst, kFmNone);

    switch (op) {
      case UniOpVVVV.blendvU8:
        _blendvU8A64(dst, s1, s2, s3);
        return;

      case UniOpVVVV.mAddF32S:
      case UniOpVVVV.mAddF64S:
      case UniOpVVVV.mSubF32S:
      case UniOpVVVV.mSubF64S:
        final bits = op.name.contains('F32') ? 32 : 64;
        final isSub = op.name.startsWith('mSub');
        cc.addNode(InstNode(isSub ? A64InstId.kFnmsub : A64InstId.kFmadd, [
          A64Vec(dst.id, bits),
          A64Vec(s1.id, bits),
          A64Vec(s2.id, bits),
          A64Vec(s3.id, bits)
        ]));
        return;

      case UniOpVVVV.mAddU16:
      case UniOpVVVV.mAddU32:
      case UniOpVVVV.mAddF32:
      case UniOpVVVV.mAddF64:
      case UniOpVVVV.mSubF32:
      case UniOpVVVV.mSubF64:
        final (int el, bool fp) = switch (op) {
          UniOpVVVV.mAddU16 => (1, false),
          UniOpVVVV.mAddU32 => (2, false),
          UniOpVVVV.mAddF32 || UniOpVVVV.mSubF32 => (2, true),
          _ => (3, true),
        };
        final isSub = op == UniOpVVVV.mSubF32 || op == UniOpVVVV.mSubF64;
        // The accumulator must not alias a multiplicand.
        final acc = (dst.id == s1.id || dst.id == s2.id)
            ? newVecWithWidth(VecWidth.k128, '@acc')
            : dst;
        if (isSub) {
          // a * b - c = (-c) + a * b
          cc.addNode(
              InstNode(A64InstId.kFneg, [_vArr(acc, el), _vArr(s3, el)]));
        } else if (acc.id != s3.id) {
          _vMovA64(acc, s3);
        }
        cc.addNode(InstNode(fp ? A64InstId.kFmla : A64InstId.kMla,
            [_vArr(acc, el), _vArr(s1, el), _vArr(s2, el)]));
        if (acc.id != dst.id) _vMovA64(dst, acc);
        return;
    }
  }

  void _emitRRRA64(UniOpRRR op, BaseReg dst, BaseReg src1, BaseReg src2) {
    if (dst is! A64Gp || src1 is! A64Gp || src2 is! A64Gp) {
      throw ArgumentError('emitRRR expects A64Gp operands');
    }
    final d = dst.is64Bit ? dst.x : dst.w;
    final s1 = src1.is64Bit ? src1.x : src1.w;
    final s2 = src2.is64Bit ? src2.x : src2.w;

    switch (op) {
      case UniOpRRR.add:
        cc.addNode(InstNode(A64InstId.kAdd, [d, s1, s2]));
        break;
      case UniOpRRR.sub:
        cc.addNode(InstNode(A64InstId.kSub, [d, s1, s2]));
        break;
      case UniOpRRR.and:
        cc.addNode(InstNode(A64InstId.kAnd, [d, s1, s2]));
        break;
      case UniOpRRR.or:
        cc.addNode(InstNode(A64InstId.kOrr, [d, s1, s2]));
        break;
      case UniOpRRR.xor:
        cc.addNode(InstNode(A64InstId.kEor, [d, s1, s2]));
        break;
      case UniOpRRR.bic:
        cc.addNode(InstNode(A64InstId.kBic, [d, s1, s2]));
        break;
      case UniOpRRR.mul:
        cc.addNode(InstNode(A64InstId.kMul, [d, s1, s2]));
        break;
      case UniOpRRR.sll:
        cc.addNode(InstNode(A64InstId.kLsl, [d, s1, s2]));
        break;
      case UniOpRRR.srl:
        cc.addNode(InstNode(A64InstId.kLsr, [d, s1, s2]));
        break;
      case UniOpRRR.sra:
        cc.addNode(InstNode(A64InstId.kAsr, [d, s1, s2]));
        break;
      case UniOpRRR.ror:
        cc.addNode(InstNode(A64InstId.kRor, [d, s1, s2]));
        break;
      default:
        throw UnimplementedError('_emitRRRA64: $op');
    }
  }

  void _emitRRIA64(UniOpRRR op, BaseReg dst, BaseReg src1, int imm) {
    if (dst is! A64Gp || src1 is! A64Gp) {
      throw ArgumentError('emitRRI expects A64Gp operands');
    }
    final d = dst.is64Bit ? dst.x : dst.w;
    final s1 = src1.is64Bit ? src1.x : src1.w;
    final i = Imm(imm);

    switch (op) {
      case UniOpRRR.add:
        cc.addNode(InstNode(A64InstId.kAdd, [d, s1, i]));
        break;
      case UniOpRRR.sub:
        cc.addNode(InstNode(A64InstId.kSub, [d, s1, i]));
        break;
      case UniOpRRR.and:
        cc.addNode(InstNode(A64InstId.kAnd, [d, s1, i]));
        break;
      case UniOpRRR.or:
        cc.addNode(InstNode(A64InstId.kOrr, [d, s1, i]));
        break;
      case UniOpRRR.xor:
        cc.addNode(InstNode(A64InstId.kEor, [d, s1, i]));
        break;
      case UniOpRRR.sll:
        cc.addNode(InstNode(A64InstId.kLsl, [d, s1, i]));
        break;
      case UniOpRRR.srl:
        cc.addNode(InstNode(A64InstId.kLsr, [d, s1, i]));
        break;
      case UniOpRRR.sra:
        cc.addNode(InstNode(A64InstId.kAsr, [d, s1, i]));
        break;
      case UniOpRRR.ror:
        cc.addNode(InstNode(A64InstId.kRor, [d, s1, i]));
        break;
      default:
        throw UnimplementedError('_emitRRIA64: $op');
    }
  }

  void emitJIfA64Impl(Label label, UniCondition cond) {
    if (cond.op == UniOpCond.bitTest) {
      // Bit Test and Branch (TBZ/TBNZ)
      // cond.b must be immediate bit index for standard TBZ/TBNZ?
      // Or if register, we need TST (reg, 1<<n)
      if (cond.b is Imm) {
        // Optimize for TBZ/TBNZ
        final imm = (cond.b as Imm).value;
        // Check condition: Equal (Zero) -> TBZ, NotEqual (Set) -> TBNZ
        if (cond.cond == CondCode.kEqual) {
          cc.addNode(
              InstNode(A64InstId.kTbz, [LabelOp(label), cond.a, Imm(imm)]));
          return;
        } else if (cond.cond == CondCode.kNotEqual) {
          cc.addNode(
              InstNode(A64InstId.kTbnz, [LabelOp(label), cond.a, Imm(imm)]));
          return;
        }
      }
      // Fallback for register bit or non-EQ/NE conditions: TST + B.cond
      // TST is alias for ANDS (discard result)
      // TST reg, (1<<imm) hard to generate here if imm is reg.
      // General case:
    }

    // Standard Compare/Test
    _emitConditionTestA64(cond);

    // Branch
    cc.addNode(InstNode(
        A64InstId.kB_cond, [LabelOp(label), Imm(_condToA64(cond.cond))]));
  }

  void _emitConditionTestA64(UniCondition cond) {
    final op = cond.op;
    final a = cond.a as BaseReg; // Should be reg
    final b = cond.b;

    switch (op) {
      case UniOpCond.compare:
        // CMP (subs)
        // Check operands. A64 CMP supports Reg, Imm, ShiftedReg
        cc.addNode(InstNode(A64InstId.kCmp, [a, b]));
        break;
      case UniOpCond.test:
        // TST (ands)
        cc.addNode(InstNode(A64InstId.kTst, [a, b]));
        break;
      case UniOpCond.bitTest:
        // Handle TST a, (1<<b) logic if not handled by TBZ/TBNZ
        // For general bit test using TST: TST a, (1<<b) -- requires shifting 1 if b is reg, or imm mask if b is imm.
        // If b is Imm(bitIndex), we construct a mask.
        if (b is Imm) {
          final mask = 1 << b.value;
          // Valid immediate for logical?
          // A64 logical immediates valid?
          cc.addNode(InstNode(A64InstId.kTst, [a, Imm(mask)]));
        } else {
          // Register shift: LSL tmp, 1, val?
          // Without temporary, we can't easily construct mask.
          // Assume TST supports register? TST x0, x1.
          // But bitTest implies b is INDEX. We want mask = 1 << index.
          // This requires lowering.
          throw UnimplementedError(
              'BitTest with register index requires scratch reg');
        }
        break;
      default:
        throw UnimplementedError('_emitConditionTestA64: $op');
    }
  }
}
