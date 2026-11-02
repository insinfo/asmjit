part of 'unicompiler.dart';

/// AArch64-specific functionality for UniCompiler.
mixin UniCompilerA64 on UniCompilerBase {
  // ============================================================================
  // [A64 Internal Dispatchers]
  // ============================================================================

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
      cc.addNode(InstNode(
          A64InstId.kMov, [_vElem(dst, ins, idx), _vElem(tmp, ins, 0)]));
      return;
    }

    // Dart conveniences (not upstream ops): broadcast loads, lowered like
    // upstream's `v_broadcast_u16/u32/u64(dst, mem)`. (LD1R has no offset
    // addressing mode.)
    switch (op) {
      case UniOpVM.loadDup16:
        _emit2vA64(UniOpVV.broadcastU16, dst, src);
        return;
      case UniOpVM.loadDup32:
        _emit2vA64(UniOpVV.broadcastU32, dst, src);
        return;
      case UniOpVM.loadDup64:
        _emit2vA64(UniOpVV.broadcastU64, dst, src);
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
        cc.addNode(InstNode(
            A64InstId.kMov, [_vElem(from, ext, 0), _vElem(src, ext, idx)]));
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
        cc.addNode(InstNode(A64InstId.kDup, [d, _vElem(src, el, 0)]));
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
  void _a64(int instId, List<Operand> ops) => cc.addNode(InstNode(instId, ops));

  /// Element [index] of [reg] (upstream `v.b(i)`, `h(i)`, `s(i)`, `d(i)`);
  /// [el] is the element size log2 (0 = B ... 3 = D).
  A64Vec _vElem(BaseReg reg, int el, int index) =>
      A64Vec(reg.id, 128).at(el + 1, index);

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
      // dst = a - (trunc(a / b) * b).
      case UniOpVVV.modF32S:
      case UniOpVVV.modF64S:
      case UniOpVVV.modF32:
      case UniOpVVV.modF64:
        final src2 = _asVecA64(src2_, dst, info.floatMode);
        final tmp = newVecWithWidth(VecWidth.k128, '@tmp1');
        final off = op.index - UniOpVVV.modF32S.index;
        _emit3vA64(
            UniOpVVV.values[UniOpVVV.divF32S.index + off], tmp, src1, src2);
        _emit2vA64(UniOpVV.values[UniOpVV.truncF32S.index + off], tmp, tmp);
        _emit3vA64(
            UniOpVVV.values[UniOpVVV.mulF32S.index + off], tmp, tmp, src2);
        _emit3vA64(
            UniOpVVV.values[UniOpVVV.subF32S.index + off], dst, src1, tmp);
        return;

      case UniOpVVV.mulU64:
        final src2 = _asVecA64(src2_, dst, kFmNone);
        final tmp1 = newVecWithWidth(VecWidth.k128, '@tmp1');
        final tmp2 = newVecWithWidth(VecWidth.k128, '@tmp2');
        final tmp3 = newVecWithWidth(VecWidth.k128, '@tmp3');
        _a64(A64InstId.kRev64, [_vArr(tmp1, 2), _vArr(src1, 2)]);
        _a64(A64InstId.kXtn, [_vArr(tmp2, 2, lo: true), _vArr(src1, 3)]);
        _a64(A64InstId.kMul, [_vArr(tmp1, 2), _vArr(tmp1, 2), _vArr(src2, 2)]);
        _a64(A64InstId.kXtn, [_vArr(tmp3, 2, lo: true), _vArr(src2, 3)]);
        _a64(A64InstId.kUaddlp, [_vArr(tmp1, 3), _vArr(tmp1, 2)]);
        _a64(A64InstId.kShl, [_vArr(dst, 3), _vArr(tmp1, 3), Imm(32)]);
        _a64(A64InstId.kUmlal, [
          _vArr(dst, 3),
          _vArr(tmp2, 2, lo: true),
          _vArr(tmp3, 2, lo: true)
        ]);
        return;

      case UniOpVVV.mulhI16:
      case UniOpVVV.mulhU16:
        final src2 = _asVecA64(src2_, dst, kFmNone);
        final tmp = newVecWithWidth(VecWidth.k128, '@tmp');
        final signed = op == UniOpVVV.mulhI16;
        _a64(signed ? A64InstId.kSmull : A64InstId.kUmull, [
          _vArr(tmp, 2),
          _vArr(src1, 1, lo: true),
          _vArr(src2, 1, lo: true)
        ]);
        _a64(signed ? A64InstId.kSmull2 : A64InstId.kUmull2,
            [_vArr(dst, 2), _vArr(src1, 1), _vArr(src2, 1)]);
        _a64(A64InstId.kUzp2, [_vArr(dst, 1), _vArr(tmp, 1), _vArr(dst, 1)]);
        return;

      case UniOpVVV.mulU64LoU32:
        final src2 = _asVecA64(src2_, dst, kFmNone);
        final tmp1 = newVecWithWidth(VecWidth.k128, '@tmp1');
        final tmp2 = newVecWithWidth(VecWidth.k128, '@tmp2');
        final tmp3 = dst.id == src1.id || dst.id == src2.id
            ? newVecWithWidth(VecWidth.k128, '@tmp3')
            : dst;
        _a64(A64InstId.kXtn, [_vArr(tmp1, 2, lo: true), _vArr(src1, 3)]);
        _a64(A64InstId.kShl, [_vArr(tmp3, 3), _vArr(src2, 3), Imm(32)]);
        _a64(A64InstId.kXtn, [_vArr(tmp2, 2, lo: true), _vArr(src2, 3)]);
        _a64(A64InstId.kMul, [_vArr(dst, 2), _vArr(tmp3, 2), _vArr(src1, 2)]);
        _a64(A64InstId.kUmlal, [
          _vArr(dst, 3),
          _vArr(tmp1, 2, lo: true),
          _vArr(tmp2, 2, lo: true)
        ]);
        return;

      case UniOpVVV.mHAddI16I32:
        final src2 = _asVecA64(src2_, dst, kFmNone);
        final al = newVecWithWidth(VecWidth.k128, '@al');
        final ah = newVecWithWidth(VecWidth.k128, '@ah');
        final bl = newVecWithWidth(VecWidth.k128, '@bl');
        final bh = newVecWithWidth(VecWidth.k128, '@bh');
        _a64(A64InstId.kXtn, [_vArr(al, 1, lo: true), _vArr(src1, 2)]);
        _a64(A64InstId.kXtn, [_vArr(bl, 1, lo: true), _vArr(src2, 2)]);
        _a64(
            A64InstId.kShrn, [_vArr(ah, 1, lo: true), _vArr(src1, 2), Imm(16)]);
        _a64(
            A64InstId.kShrn, [_vArr(bh, 1, lo: true), _vArr(src2, 2), Imm(16)]);
        _a64(A64InstId.kSmull,
            [_vArr(dst, 2), _vArr(al, 1, lo: true), _vArr(bl, 1, lo: true)]);
        _a64(A64InstId.kSmlal,
            [_vArr(dst, 2), _vArr(ah, 1, lo: true), _vArr(bh, 1, lo: true)]);
        return;

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

      case UniOpVVV.combineHiLoU64:
      case UniOpVVV.combineHiLoF64:
        // dst = {src1.u64[1], src2.u64[0]}.
        final src2 = _asVecA64(src2_, dst, kFmNone);
        void movD0(BaseReg to, BaseReg from, int i) =>
            _a64(A64InstId.kMov, [_vElem(to, 3, i), _vElem(from, 3, i)]);
        if (dst.id == src1.id) {
          if (dst.id == src2.id) return;
          movD0(dst, src2, 0);
        } else if (dst.id == src2.id) {
          movD0(dst, src1, 1);
        } else {
          _vMovA64(dst, src1);
          movD0(dst, src2, 0);
        }
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

  /// Port of `UniCompiler::emit_2vi()` (unicompiler_a64.cpp). Swizzle
  /// immediates are [Swizzle2] / [Swizzle4] values, as in upstream.
  void _emit2viA64(UniOpVVI op, Operand dst_, Operand src_, int imm) {
    final dst = dst_ as BaseReg;

    switch (op) {
      case UniOpVVI.sllbU128:
      case UniOpVVI.srlbU128:
        if (imm < 0 || imm > 15) throw ArgumentError('byte shift $imm');
        final src = _asVecA64(src_, dst, kFmNone);

        // If the shift is used to extract a high 64-bit element and zero the
        // rest of the register.
        if (op == UniOpVVI.srlbU128 && imm == 8) {
          _a64(A64InstId.kDup, [A64Vec(dst.id, 64), _vElem(src, 3, 1)]);
          return;
        }

        // If the shift is used to extract the last 32-bit element and zero
        // the rest of the register.
        if (op == UniOpVVI.srlbU128 && imm == 12) {
          _a64(A64InstId.kDup, [A64Vec(dst.id, 32), _vElem(src, 2, 3)]);
          return;
        }

        // Deviation from upstream, which emits `ext dst, zero, src, #16` for
        // sllbU128 by 0 (running it reports InvalidImmediate).
        if (op == UniOpVVI.sllbU128 && imm == 0) {
          _vMovA64(dst, src);
          return;
        }

        final zero = newVecWithWidth(VecWidth.k128, '@zero');
        _a64(A64InstId.kMovi, [_vArr(zero, 0), Imm(0)]);
        // `EXT dst, a, b, #n` -> `dst = b:a >> #n*8`.
        if (op == UniOpVVI.sllbU128) {
          _a64(A64InstId.kExt,
              [_vArr(dst, 0), _vArr(zero, 0), _vArr(src, 0), Imm(16 - imm)]);
        } else {
          _a64(A64InstId.kExt,
              [_vArr(dst, 0), _vArr(src, 0), _vArr(zero, 0), Imm(imm)]);
        }
        return;

      case UniOpVVI.swizzleU16x4:
      case UniOpVVI.swizzleLoU16x4:
      case UniOpVVI.swizzleHiU16x4:
        final src = _asVecA64(src_, dst, kFmNone);
        final pred = Uint8List.fromList(List.generate(16, (i) => i));
        final d = (imm >> 23) & 6;
        final c = (imm >> 15) & 6;
        final b = (imm >> 7) & 6;
        final a = (imm << 1) & 6;
        if (op != UniOpVVI.swizzleHiU16x4) {
          pred.setAll(0, [a, a + 1, b, b + 1, c, c + 1, d, d + 1]);
        }
        if (op != UniOpVVI.swizzleLoU16x4) {
          pred.setAll(
              8, [a + 8, a + 9, b + 8, b + 9, c + 8, c + 9, d + 8, d + 9]);
        }
        final predReg = (this as UniCompiler)
            .simdVecConst(VecConst(16, pred), Bcst.kNA_Unique, VecWidth.k128);
        _a64(A64InstId.kTbl, [_vArr(dst, 0), _vArr(src, 0), _vArr(predReg, 0)]);
        return;

      case UniOpVVI.swizzleU32x4:
      case UniOpVVI.swizzleF32x4:
        _emitSwizzle32A64(dst, _asVecA64(src_, dst, kFmNone), imm);
        return;

      case UniOpVVI.swizzleU64x2:
      case UniOpVVI.swizzleF64x2:
        final src = _asVecA64(src_, dst, kFmNone);
        // Use `dup` to broadcast one 64-bit element.
        if (imm == swizzle2(0, 0).value || imm == swizzle2(1, 1).value) {
          _a64(A64InstId.kDup, [_vArr(dst, 3), _vElem(src, 3, imm & 1)]);
          return;
        }
        // Use `ext` to swap two 64-bit elements.
        if (imm == swizzle2(0, 1).value) {
          _a64(A64InstId.kExt,
              [_vArr(dst, 0), _vArr(src, 0), _vArr(src, 0), Imm(8)]);
          return;
        }
        // NOP...
        if (imm == swizzle2(1, 0).value) {
          _vMovA64(dst, src);
          return;
        }
        throw ArgumentError(
            'invalid Swizzle2 value 0x${imm.toRadixString(16)}');

      case UniOpVVI.swizzleF64x4:
      case UniOpVVI.swizzleU64x4:
      case UniOpVVI.extractV128I32:
      case UniOpVVI.extractV128I64:
      case UniOpVVI.extractV128F32:
      case UniOpVVI.extractV128F64:
      case UniOpVVI.extractV256I32:
      case UniOpVVI.extractV256I64:
      case UniOpVVI.extractV256F32:
      case UniOpVVI.extractV256F64:
        throw UnsupportedError(
            'UniCompiler A64: $op (NEON has only 128-bit vectors)');

      default:
        if (op.index >= kA64OpcodeInfo2vi.length) {
          throw UnimplementedError('_emit2viA64: $op');
        }
        final info = kA64OpcodeInfo2vi[op.index];
        if (!info.asimd || info.instId < 0) {
          throw UnimplementedError('_emit2viA64: $op');
        }
        final src = _asVecA64(src_, dst, kFmNone);
        // Deviation from upstream: USHR/SSHR cannot encode a shift by 0 and
        // upstream reports InvalidImmediate (`ushr v0.4s, v0.4s, 0`) for an
        // op the x86 backend accepts; a shift by 0 is a move.
        if (imm == 0 &&
            op.index >= UniOpVVI.srlU16.index &&
            op.index <= UniOpVVI.sraI64.index) {
          _vMovA64(dst, src);
          return;
        }
        // Narrowing shifts write the low (SHRN) or high (SHRN2) half.
        final d = _vArr(dst, info.dstElement,
            lo: info.dstPart == kPartLo ||
                (info.srcPart == kPartLo && info.dstElement < info.srcElement));
        final s = _vArr(src, info.srcElement);
        cc.addNode(InstNode(info.instId, [d, s, Imm(imm)]));
    }
  }

  /// Port of `emit_swizzle32_impl()` (unicompiler_a64.cpp): a 32-bit swizzle
  /// as up to three moves, inserts, DUP, EXT, REV64 or ZIP/UZP/TRN
  /// operations taken from [kA64Swizzle32Data].
  void _emitSwizzle32A64(BaseReg dst, BaseReg src, int imm) {
    if ((imm & 0xFCFCFCFC) != 0) {
      throw ArgumentError('invalid Swizzle4 value 0x${imm.toRadixString(16)}');
    }
    final tableIndex = ((imm & 0x03000000) >> (24 - 6)) |
        ((imm & 0x00030000) >> (16 - 4)) |
        ((imm & 0x00000300) >> (8 - 2)) |
        (imm & 0x00000003);
    final swiz = kA64Swizzle32Data[tableIndex];

    const zipUnzipInst = [
      A64InstId.kZip1,
      A64InstId.kZip2,
      A64InstId.kUzp1,
      A64InstId.kUzp2,
      A64InstId.kTrn1,
      A64InstId.kTrn2,
    ];

    final opSrc = [src, src];
    for (var i = 0; i < 3; i++) {
      final op = (swiz >> (i * 8)) & 0xFF;
      final target = (swiz >> (24 + i * 2)) & 3;
      if (op == 0) break;

      final opDst = target == 0 ? dst : newVecWithWidth(VecWidth.k128, '@tmp');
      switch (op & 0xF) {
        case 1: // kMov
          _vMovA64(opDst, opSrc[0]);
        case 2: // kIns: always the last operation, on the destination only.
          final srcLane = (op >> 4) & 3, dstLane = (op >> 6) & 3;
          _a64(A64InstId.kMov,
              [_vElem(opDst, 2, dstLane), _vElem(opDst, 2, srcLane)]);
        case 3: // kDup: broadcast of a single element.
          _a64(A64InstId.kDup,
              [_vArr(opDst, 2), _vElem(opSrc[0], 2, (op >> 4) & 3)]);
        case 4: // kExt: rotation.
          _a64(A64InstId.kExt, [
            _vArr(opDst, 0),
            _vArr(opSrc[0], 0),
            _vArr(opSrc[1], 0),
            Imm((op >> 2) & 0xC)
          ]);
        case 5: // kRev64: swaps lo/hi elements of 64-bit lanes.
          _a64(A64InstId.kRev64, [_vArr(opDst, 2), _vArr(opSrc[0], 2)]);
        case 7: // kZipUnzip
          final instId = zipUnzipInst[(op >> 4) & 7];
          final el = (op & 0x80) == 0 ? 2 : 3;
          _a64(instId,
              [_vArr(opDst, el), _vArr(opSrc[0], el), _vArr(opSrc[1], el)]);
        default:
          throw StateError(
              'invalid swizzle operation 0x${op.toRadixString(16)}');
      }

      if ((target & 1) != 0) opSrc[0] = opDst;
      if ((target & 2) != 0) opSrc[1] = opDst;
    }
  }

  /// Port of `emit_3vi()` (unicompiler_a64.cpp). Interleaved shuffle
  /// immediates are [Swizzle4] / [Swizzle2] values, as in upstream.
  void _emit3viA64(
      UniOpVVVI op, Operand dst_, Operand src1_, Operand src2_, int imm) {
    final dst = dst_ as BaseReg;
    final src1 = src1_ as BaseReg;

    switch (op) {
      case UniOpVVVI.alignrU128:
        if (imm < 0 || imm > 15) throw ArgumentError('alignr imm $imm');
        if (imm == 0) {
          _vMovA64(dst, src2_);
          return;
        }
        final src2 = _asVecA64(src2_, dst, kFmNone);
        _a64(A64InstId.kExt,
            [_vArr(dst, 0), _vArr(src2, 0), _vArr(src1, 0), Imm(imm)]);
        return;

      case UniOpVVVI.interleaveShuffleU32x4:
      case UniOpVVVI.interleaveShuffleF32x4:
        if ((imm & 0xFCFCFCFC) != 0) {
          throw ArgumentError(
              'invalid Swizzle4 value 0x${imm.toRadixString(16)}');
        }
        _emitInterleavedShuffle32A64(
            dst, src1, _asVecA64(src2_, dst, kFmNone), imm);
        return;

      case UniOpVVVI.interleaveShuffleU64x2:
      case UniOpVVVI.interleaveShuffleF64x2:
        if ((imm & 0xFFFCFEFE) != 0) {
          throw ArgumentError(
              'invalid Swizzle2 value 0x${imm.toRadixString(16)}');
        }
        final src2 = _asVecA64(src2_, dst, kFmNone);
        if (src1.id == src2.id) {
          _emit2viA64(UniOpVVI.swizzleU64x2, dst, src1, imm);
        } else if (imm == swizzle2(0, 0).value) {
          _a64(
              A64InstId.kZip1, [_vArr(dst, 3), _vArr(src1, 3), _vArr(src2, 3)]);
        } else if (imm == swizzle2(1, 1).value) {
          _a64(
              A64InstId.kZip2, [_vArr(dst, 3), _vArr(src1, 3), _vArr(src2, 3)]);
        } else if (imm == swizzle2(1, 0).value) {
          _emit3vA64(UniOpVVV.combineHiLoU64, dst, src2, src1);
        } else {
          _emit3vA64(UniOpVVV.combineLoHiU64, dst, src2, src1);
        }
        return;

      default:
        throw UnsupportedError(
            'UniCompiler A64: $op (NEON has only 128-bit vectors)');
    }
  }

  /// Port of `emit_interleaved_shuffle32_impl()` (unicompiler_a64.cpp): the
  /// low two lanes are picked from [src1] and the high two from [src2] by up
  /// to three operations taken from [kA64InterleavedShuffle32Ops] (or the
  /// table that avoids inserting into `src2` when it is the destination).
  void _emitInterleavedShuffle32A64(
      BaseReg dst, BaseReg src1, BaseReg src2, int imm) {
    if (src1.id == src2.id) {
      _emitSwizzle32A64(dst, src1, imm);
      return;
    }

    final tableIndex = ((imm & 0x03000000) >> (24 - 6)) |
        ((imm & 0x00030000) >> (16 - 4)) |
        ((imm & 0x00000300) >> (8 - 2)) |
        (imm & 0x00000003);
    final ops = dst.id != src2.id
        ? kA64InterleavedShuffle32Ops[tableIndex]
        : kA64InterleavedShuffle32OpsDstSameAsB[tableIndex];

    const kOpRev64 = 0, kOpInsS = 1, kOpInsD = 2, kOpPerm = 3, kOpDup = 4;
    int opAt(int i) => (ops >> (i * 11)) & 0x7FF;
    bool isIns(int op) => (op >> 8) == kOpInsS || (op >> 8) == kOpInsD;

    final count = 1 + (opAt(1) != 0 ? 1 : 0) + ((ops >> 22) != 0 ? 1 : 0);
    final regs = <BaseReg?>[src1, src2, null, null, null];
    final srcUseMask = [0, 0, 0, 0];
    var dstIndex = count - 1;

    var allUseMask = 0;
    for (var i = count - 1; i >= 0; i--) {
      final op = opAt(i);
      allUseMask |= 1 << ((op >> 4) & 3);
      allUseMask |= 1 << ((op >> 6) & 3);
      srcUseMask[i] = allUseMask;
      // The last destination would be the previous operation (if not
      // another insert).
      if (isIns(op)) dstIndex = i - 1;
    }

    const permInst = [
      A64InstId.kZip1,
      A64InstId.kZip2,
      A64InstId.kUzp1,
      A64InstId.kUzp2,
      A64InstId.kTrn1,
      A64InstId.kTrn2,
      A64InstId.kExt,
      A64InstId.kExt,
    ];

    var opIndex = 2;
    BaseReg? finalDst;

    for (var i = 0; i < count; i++) {
      final op = opAt(i);
      if (i > 0 && !isIns(op)) opIndex++;

      final BaseReg opDst;
      if (i < dstIndex) {
        opDst = regs[opIndex] ?? newVecWithWidth(VecWidth.k128, '@shuf_tmp');
      } else {
        if (finalDst == null) {
          final msk = dst.id == src1.id
              ? 0x1
              : dst.id == src2.id
                  ? 0x2
                  : 0;
          // A destination in conflict with a source still to be read gets a
          // new register that is moved to `dst` at the end.
          finalDst = (srcUseMask[i + 1] & msk) != 0
              ? newVecWithWidth(VecWidth.k128, '@shuf_dst')
              : dst;
        }
        opDst = finalDst;
      }

      final a = regs[(op >> 4) & 3]!;
      final b = regs[(op >> 6) & 3];
      switch (op >> 8) {
        case kOpInsS:
          _a64(A64InstId.kMov,
              [_vElem(opDst, 2, (op >> 2) & 3), _vElem(a, 2, op & 3)]);
        case kOpInsD:
          _a64(A64InstId.kMov,
              [_vElem(opDst, 3, (op >> 2) & 3), _vElem(a, 3, op & 3)]);
        case kOpPerm:
          final instId = permInst[op & 7];
          if (instId == A64InstId.kExt) {
            _a64(A64InstId.kExt, [
              _vArr(opDst, 0),
              _vArr(a, 0),
              _vArr(b!, 0),
              Imm(((op & 0x1) << 2) + (op & 0x8))
            ]);
          } else {
            final el = (op & 0x8) == 0 ? 2 : 3;
            _a64(instId, [_vArr(opDst, el), _vArr(a, el), _vArr(b!, el)]);
          }
        case kOpRev64:
          _a64(A64InstId.kRev64, [_vArr(opDst, 2), _vArr(a, 2)]);
        case kOpDup:
          _a64(A64InstId.kDup, [_vArr(opDst, 2), _vElem(a, 2, op & 3)]);
        default:
          throw StateError(
              'invalid shuffle operation 0x${op.toRadixString(16)}');
      }
      regs[opIndex] = opDst;
    }

    _vMovA64(dst, finalDst!);
  }

  /// `opcode_info_4v` (unicompiler_a64.cpp): (instruction, float mode,
  /// element size, negate accumulator).
  static const _a64OpcodeInfo4v = <(int, int, int, int)>[
    (A64InstId.kBsl, kFmNone, 0, 0), // blendvU8
    (A64InstId.kMla, kFmNone, 1, 0), // mAddU16
    (A64InstId.kMla, kFmNone, 2, 0), // mAddU32
    (A64InstId.kFmadd, kFmF32S, 2, 0), // mAddF32S
    (A64InstId.kFmadd, kFmF64S, 3, 0), // mAddF64S
    (A64InstId.kFmla, kFmF32V, 2, 0), // mAddF32
    (A64InstId.kFmla, kFmF64V, 3, 0), // mAddF64
    (A64InstId.kFnmsub, kFmF32S, 2, 0), // mSubF32S
    (A64InstId.kFnmsub, kFmF64S, 3, 0), // mSubF64S
    (A64InstId.kFmla, kFmF32V, 2, 1), // mSubF32
    (A64InstId.kFmla, kFmF64V, 3, 1), // mSubF64
    (A64InstId.kFmsub, kFmF32S, 2, 0), // nmAddF32S
    (A64InstId.kFmsub, kFmF64S, 3, 0), // nmAddF64S
    (A64InstId.kFmls, kFmF32V, 2, 0), // nmAddF32
    (A64InstId.kFmls, kFmF64V, 3, 0), // nmAddF64
    (A64InstId.kFnmadd, kFmF32S, 2, 0), // nmSubF32S
    (A64InstId.kFnmadd, kFmF64S, 3, 0), // nmSubF64S
    (A64InstId.kFmls, kFmF32V, 2, 1), // nmSubF32
    (A64InstId.kFmls, kFmF64V, 3, 1), // nmSubF64
  ];

  /// Port of `UniCompiler::emit_4v()` (unicompiler_a64.cpp).
  void _emit4vA64(
      UniOpVVVV op, Operand dst_, Operand src1_, Operand src2_, Operand src3_) {
    final dst = dst_ as BaseReg;
    final src1 = src1_ as BaseReg;
    final (instId, floatMode, element, negate) = _a64OpcodeInfo4v[op.index];

    if (op == UniOpVVVV.blendvU8) {
      _blendvU8A64(dst, src1, _asVecA64(src2_, dst, kFmNone),
          _asVecA64(src3_, dst, kFmNone));
      return;
    }

    if (floatMode == kFmF32S || floatMode == kFmF64S) {
      final bits = floatMode == kFmF32S ? 32 : 64;
      final src2 = _asVecA64(src2_, dst, floatMode);
      final src3 = _asVecA64(src3_, dst, floatMode);
      _a64(instId, [
        A64Vec(dst.id, bits),
        A64Vec(src1.id, bits),
        A64Vec(src2.id, bits),
        A64Vec(src3.id, bits)
      ]);
      return;
    }

    final src2 = _asVecA64(src2_, dst, kFmNone);
    final negateAcc = negate != 0;
    final dstOverlaps = dst.id == src1.id || dst.id == src2.id;
    final destructible =
        (src3_ is BaseReg && src3_.id == dst.id) || src3_ is! BaseReg;

    final BaseReg src3;
    if (!dstOverlaps && src3_ is A64Mem) {
      _a64(A64InstId.kLdr, [A64Vec(dst.id, 128), src3_]);
      src3 = dst;
    } else {
      src3 = _asVecA64(src3_, dst, kFmNone);
    }

    if (destructible) {
      if (negateAcc) {
        _a64(A64InstId.kFneg, [_vArr(src3, element), _vArr(src3, element)]);
      }
      _a64(instId,
          [_vArr(src3, element), _vArr(src1, element), _vArr(src2, element)]);
      if (dst.id != src3.id) _vMovA64(dst, src3);
      return;
    }

    final tmp = dstOverlaps ? newVecWithWidth(VecWidth.k128, '@tmp') : dst;
    if (negateAcc) {
      _a64(A64InstId.kFneg, [_vArr(tmp, element), _vArr(src3, element)]);
    } else {
      _vMovA64(tmp, src3);
    }
    _a64(instId,
        [_vArr(tmp, element), _vArr(src1, element), _vArr(src2, element)]);
    if (dst.id != tmp.id) _vMovA64(dst, tmp);
  }

  // ---------------------------------------------------------------------------
  // General purpose instructions: port of gp_emit_mem_op/gp_force_reg,
  // ConditionApplier, emit_mov/emit_m/emit_rm/emit_mr/emit_cmov/emit_select/
  // emit_2i/emit_3i/emit_j_if (ujit/unicompiler_a64.cpp).
  //
  // The port has no CSSC detection (`has_cssc()` is false), so the CSSC
  // forms (abs, ctz, smin/smax/umin/umax) are not emitted.
  // ---------------------------------------------------------------------------

  /// `Inst::kIdNone` (the generated A64 database has no such id).
  static const _kInstNoneA64 = -1;

  static A64Gp _gpAs(BaseReg r, A64Gp ref) => A64Gp(r.id, ref.sizeBits);

  static A64Gp _gpZeroAs(A64Gp ref) => ref.is64Bit ? xzr : wzr;

  A64Gp _newSimilarGpA64(A64Gp ref, [String? name]) =>
      (cc as A64Compiler).newGp(ref.type, name);

  /// `gp_emit_mem_op()`: a shifted index must match the access size, other
  /// shifts are applied to a temporary address.
  void _gpEmitMemOpA64(A64Gp r, A64Mem m, int instId, int memSize) {
    if (m.index != null && m.shift != 0) {
      final size = memSize != 0 ? memSize : r.size;
      if (size != 1 << m.shift) {
        final tmp = _newSimilarGpA64(xzr, '@mem_addr');
        _a64(A64InstId.kAdd, [
          tmp,
          m.base!,
          m.index!,
          A64ShiftOp(A64Shift.lsl, m.shift),
        ]);
        m = A64Mem.base(tmp);
      }
    }
    _a64(instId, [r, m]);
  }

  /// `gp_force_reg()`: [op] as a register of the size of [ref].
  A64Gp _gpForceRegA64(Operand op, A64Gp ref) {
    if (op is BaseReg) return _gpAs(op, ref);
    if (op is Imm && op.value == 0) return _gpZeroAs(ref);

    final reg = _newSimilarGpA64(ref, '@tmp');
    if (op is A64Mem) {
      _gpEmitMemOpA64(reg, op, A64InstId.kLdr, reg.size);
    } else {
      _a64(A64InstId.kMov, [reg, op]);
    }
    return reg;
  }

  /// `a64::Utils::is_logical_imm()`.
  static bool _isLogicalImm(int value, int width) =>
      A64Encoder.encodeLogicalImm(value, width) != null;

  /// `a64::Utils::is_add_sub_imm()` (the value as an unsigned 64-bit
  /// integer).
  static bool _isAddSubImm(int value) =>
      (value >= 0 && value <= 0xFFF) || (value & ~0xFFF000) == 0;

  /// The AArch64 condition of a [CondCode] value.
  static A64Cond _a64Cond(int cond) => switch (cond) {
        CondCode.kEqual => A64Cond.eq,
        CondCode.kNotEqual => A64Cond.ne,
        CondCode.kSignedLT => A64Cond.lt,
        CondCode.kSignedGE => A64Cond.ge,
        CondCode.kSignedLE => A64Cond.le,
        CondCode.kSignedGT => A64Cond.gt,
        CondCode.kUnsignedLT => A64Cond.cc,
        CondCode.kUnsignedGE => A64Cond.cs,
        CondCode.kUnsignedLE => A64Cond.ls,
        CondCode.kUnsignedGT => A64Cond.hi,
        CondCode.kOverflow => A64Cond.vs,
        CondCode.kNotOverflow => A64Cond.vc,
        CondCode.kSign => A64Cond.mi,
        CondCode.kNotSign => A64Cond.pl,
        _ => throw ArgumentError('No AArch64 condition for CondCode $cond'),
      };

  /// `ConditionApplier::optimize()` + `emit()`: emits the instruction that
  /// sets the flags and returns the condition to test.
  int _applyConditionA64(UniCondition condition) {
    var op = condition.op;
    var cond = condition.cond;
    final a = condition.a as A64Gp;
    var b = condition.b;
    final width = a.sizeBits;

    // The Dart CondCode is shared by both backends and its kBTZero /
    // kBTNotZero are the x86 carry conditions; on AArch64 (as in upstream
    // `arm::CondCode`) they are kZero / kNotZero.
    if (op == UniOpCond.bitTest) {
      cond = cond == CondCode.kBTNotZero ? CondCode.kNotZero : CondCode.kZero;
    }

    // optimize()
    switch (op) {
      case UniOpCond.compare:
        // `reverse_cond()` keeps EQ / NE.
        if (b is Imm &&
            b.value == 0 &&
            (cond == CondCode.kEqual || cond == CondCode.kNotEqual)) {
          op = UniOpCond.test;
          b = a;
        }
      case UniOpCond.bitTest:
        if (b is Imm) {
          // Deviation from upstream, which computes the mask as the 32-bit
          // `1u << bit_index`; running upstream with bt_nz(a, Imm(40))
          // emits `tst x0, 256` (bit 8).
          op = UniOpCond.test;
          b = Imm(1 << b.value);
        }
      default:
        break;
    }

    // emit()
    switch (op) {
      case UniOpCond.assignAnd:
        if (b is Imm && _isLogicalImm(b.value, width)) {
          _a64(A64InstId.kAnds, [a, a, b]);
        } else {
          _a64(A64InstId.kAnds, [a, a, _gpForceRegA64(b, a)]);
        }
      case UniOpCond.assignAdd:
      case UniOpCond.assignSub:
        final instId =
            op == UniOpCond.assignAdd ? A64InstId.kAdds : A64InstId.kSubs;
        if (b is Imm && _isAddSubImm(b.value)) {
          _a64(instId, [a, a, b]);
        } else {
          _a64(instId, [a, a, _gpForceRegA64(b, a)]);
        }
      case UniOpCond.assignXor:
      case UniOpCond.assignOr:
        if (op == UniOpCond.assignXor &&
            b is Imm &&
            (b.value == -1 || (width == 32 && b.value == 0xFFFFFFFF))) {
          _a64(A64InstId.kMvn, [a, a]);
          _a64(A64InstId.kTst, [a, a]);
          return cond;
        }
        final instId =
            op == UniOpCond.assignOr ? A64InstId.kOrr : A64InstId.kEor;
        if (b is Imm && _isLogicalImm(b.value, width)) {
          _a64(instId, [a, a, b]);
        } else {
          _a64(instId, [a, a, _gpForceRegA64(b, a)]);
        }
        _a64(A64InstId.kTst, [a, a]);
      case UniOpCond.assignShr:
        if (b is Imm) {
          _a64(A64InstId.kAdds, [
            a,
            _gpZeroAs(a),
            a,
            A64ShiftOp(A64Shift.lsr, b.value & 0xFFFFFFFF),
          ]);
        } else {
          _a64(A64InstId.kLsr, [a, a, _gpForceRegA64(b, a)]);
          _a64(A64InstId.kTst, [a, a]);
        }
      case UniOpCond.test:
        if (b is Imm && _isLogicalImm(b.value, width)) {
          _a64(A64InstId.kTst, [a, b]);
        } else {
          _a64(A64InstId.kTst, [a, _gpForceRegA64(b, a)]);
        }
      case UniOpCond.compare:
        if (b is Imm && _isAddSubImm(b.value)) {
          _a64(A64InstId.kCmp, [a, b]);
        } else {
          _a64(A64InstId.kCmp, [a, _gpForceRegA64(b, a)]);
        }
      case UniOpCond.bitTest:
        final tmp = _newSimilarGpA64(a);
        _a64(A64InstId.kLsr, [tmp, a, _gpForceRegA64(b, a)]);
        _a64(A64InstId.kTst, [tmp, Imm(1)]);
    }
    return cond;
  }

  /// `emit_mov()`.
  void _emitMovA64(BaseReg dst_, Operand src) {
    final dst = dst_ as A64Gp;
    if (src is A64Mem) {
      _gpEmitMemOpA64(dst, src, A64InstId.kLdr, dst.size);
    } else {
      _a64(A64InstId.kMov, [dst, src is BaseReg ? _gpAs(src, dst) : src]);
    }
  }

  /// `emit_m()`.
  void _emitMA64(UniOpM op, A64Mem m) {
    const stInst = [
      (_kInstNoneA64, 0), // prefetch
      (A64InstId.kStr, 0), // storeZeroReg
      (A64InstId.kStrb, 1), // storeZeroU8
      (A64InstId.kStrh, 2), // storeZeroU16
      (A64InstId.kStr, 4), // storeZeroU32
      (A64InstId.kStr, 8), // storeZeroU64
    ];
    final zero =
        op == UniOpM.storeZeroReg || op == UniOpM.storeZeroU64 ? xzr : wzr;
    final (instId, memSize) = stInst[op.index];
    if (instId == _kInstNoneA64) return;
    _gpEmitMemOpA64(zero, m, instId, memSize);
  }

  /// `emit_rm()`.
  void _emitRMA64(UniOpRM op, BaseReg dst, A64Mem src) {
    const ldInst = [
      (A64InstId.kLdr, 0), // loadReg
      (A64InstId.kLdrsb, 1), // loadI8
      (A64InstId.kLdrb, 1), // loadU8
      (A64InstId.kLdrsh, 2), // loadI16
      (A64InstId.kLdrh, 2), // loadU16
      (A64InstId.kLdr, 4), // loadI32
      (A64InstId.kLdr, 4), // loadU32
      (A64InstId.kLdr, 8), // loadI64
      (A64InstId.kLdr, 8), // loadU64
      (A64InstId.kLdrb, 1), // loadMergeU8
      (A64InstId.kLdrb, 1), // loadShiftU8
      (A64InstId.kLdrh, 2), // loadMergeU16
      (A64InstId.kLdrh, 2), // loadShiftU16
    ];
    var r = dst as A64Gp;
    var (instId, memSize) = ldInst[op.index];

    switch (op) {
      case UniOpRM.loadShiftU8:
      case UniOpRM.loadShiftU16:
        final tmp = _newSimilarGpA64(r);
        _gpEmitMemOpA64(tmp.w, src, instId, memSize);
        _a64(
            A64InstId.kOrr, [r, tmp, r, A64ShiftOp(A64Shift.lsl, memSize * 8)]);
      case UniOpRM.loadMergeU8:
      case UniOpRM.loadMergeU16:
        final tmp = _newSimilarGpA64(r);
        _gpEmitMemOpA64(tmp.w, src, instId, memSize);
        _a64(A64InstId.kOrr, [r, r, tmp]);
      default:
        if (op == UniOpRM.loadI32 && r.is64Bit) instId = A64InstId.kLdrsw;
        if (op == UniOpRM.loadU8 ||
            op == UniOpRM.loadU16 ||
            op == UniOpRM.loadU32) {
          r = r.w;
        }
        _gpEmitMemOpA64(r, src, instId, memSize);
    }
  }

  /// `emit_mr()`.
  void _emitMRA64(UniOpMR op, A64Mem m, BaseReg src) {
    const opInfo = [
      (_kInstNoneA64, A64InstId.kStr, 0), // storeReg
      (_kInstNoneA64, A64InstId.kStrb, 1), // storeU8
      (_kInstNoneA64, A64InstId.kStrh, 2), // storeU16
      (_kInstNoneA64, A64InstId.kStr, 4), // storeU32
      (_kInstNoneA64, A64InstId.kStr, 8), // storeU64
      (A64InstId.kAdd, A64InstId.kStr, 0), // addReg
      (A64InstId.kAdd, A64InstId.kStrb, 1), // addU8
      (A64InstId.kAdd, A64InstId.kStrh, 2), // addU16
      (A64InstId.kAdd, A64InstId.kStr, 4), // addU32
      (A64InstId.kAdd, A64InstId.kStr, 8), // addU64
    ];
    var r = src as A64Gp;
    final (opInst, storeInst, size) = opInfo[op.index];
    if (size >= 1 && size <= 4) r = r.w;

    if (opInst == _kInstNoneA64) {
      _a64(storeInst, [r, m]);
      return;
    }
    final tmp = _newSimilarGpA64(r, '@tmp');
    switch (size) {
      case 0:
        _emitRMA64(UniOpRM.loadReg, tmp, m);
      case 1:
        _emitRMA64(UniOpRM.loadU8, tmp, m);
      case 2:
        _emitRMA64(UniOpRM.loadU16, tmp, m);
      case 4:
        _emitRMA64(UniOpRM.loadU32, tmp, m);
      case 8:
        _emitRMA64(UniOpRM.loadU64, tmp, m);
    }
    _a64(opInst, [tmp, tmp, r]);
    _a64(storeInst, [tmp, m]);
  }

  /// `emit_cmov()`.
  void _emitCmovA64(UniCondition condition, BaseReg dst_, Operand sel) {
    final dst = dst_ as A64Gp;
    final cond = _applyConditionA64(condition);
    _a64(A64InstId.kCsel,
        [dst, _gpForceRegA64(sel, dst), dst, A64CondOp(_a64Cond(cond))]);
  }

  /// `emit_select()`.
  void _emitSelectA64(
      UniCondition condition, BaseReg dst_, Operand sel1_, Operand sel2_) {
    final dst = dst_ as A64Gp;
    final cond = _applyConditionA64(condition);
    final sel1 = _gpForceRegA64(sel1_, dst);
    final sel2 = _gpForceRegA64(sel2_, dst);
    _a64(A64InstId.kCsel, [dst, sel1, sel2, A64CondOp(_a64Cond(cond))]);
  }

  /// `emit_j_if()`.
  void _emitJIfA64Impl(Label target, UniCondition condition) {
    final cond = _applyConditionA64(condition);
    _a64(A64InstId.kB_cond, [LabelOp(target), A64CondOp(_a64Cond(cond))]);
  }

  /// `emit_2i()`.
  void _emit2iA64(UniOpRR op, BaseReg dst_, Operand src_) {
    final dst = dst_ as A64Gp;
    if (op == UniOpRR.mov) {
      // Dart convenience (not an upstream op).
      _emitMovA64(dst, src_);
      return;
    }
    if (src_ is! BaseReg && src_ is! A64Mem) {
      throw ArgumentError('emit_2i: $op with $src_');
    }
    final src = _gpForceRegA64(src_, dst);

    switch (op) {
      case UniOpRR.abs:
        _a64(A64InstId.kCmp, [src, Imm(0)]);
        _a64(A64InstId.kCneg, [dst, src, const A64CondOp(A64Cond.mi)]);
      case UniOpRR.neg:
        _a64(A64InstId.kNeg, [dst, src]);
      case UniOpRR.not:
        _a64(A64InstId.kMvn, [dst, src]);
      case UniOpRR.bSwap:
        _a64(A64InstId.kRev, [dst, src]);
      case UniOpRR.clz:
        _a64(A64InstId.kClz, [dst, src]);
      case UniOpRR.ctz:
        _a64(A64InstId.kRbit, [dst, src]);
        _a64(A64InstId.kClz, [dst, dst]);
      case UniOpRR.reflect:
        _a64(A64InstId.kEor,
            [dst, src, src, A64ShiftOp(A64Shift.asr, dst.sizeBits - 1)]);
      case UniOpRR.mov:
        break;
    }
  }

  static bool _isOp3iCommutativeA64(UniOpRRR op) =>
      op == UniOpRRR.and ||
      op == UniOpRRR.or ||
      op == UniOpRRR.xor ||
      op == UniOpRRR.add ||
      op == UniOpRRR.mul ||
      op == UniOpRRR.sMin ||
      op == UniOpRRR.sMax ||
      op == UniOpRRR.uMin ||
      op == UniOpRRR.uMax;

  static const _logicalInst = [
    A64InstId.kAnd,
    A64InstId.kOrr,
    A64InstId.kEor,
    A64InstId.kBic,
  ];

  static const _shiftInst = [A64InstId.kLsl, A64InstId.kLsr, A64InstId.kAsr];

  /// `emit_3i()`.
  void _emit3iA64(UniOpRRR op, BaseReg dst_, Operand src1, Operand src2) {
    final dst = dst_ as A64Gp;
    final width = dst.sizeBits;

    if (src1 is! BaseReg) {
      if (src2 is BaseReg && _isOp3iCommutativeA64(op)) {
        final t = src1;
        src1 = src2;
        src2 = t;
      } else {
        src1 = _gpForceRegA64(src1, dst);
      }
    }

    // ArithOp Reg, Reg, Imm
    if (src2 is Imm) {
      final a = _gpAs(src1, dst);
      final b = src2;

      switch (op) {
        case UniOpRRR.xor:
        case UniOpRRR.and:
        case UniOpRRR.or:
        case UniOpRRR.bic:
          if (op == UniOpRRR.xor &&
              (b.value == -1 ||
                  ((b.value & 0xFFFFFFFF) == 0xFFFFFFFF && width == 32))) {
            _a64(A64InstId.kMvn, [dst, a]);
            return;
          }
          if (_isLogicalImm(b.value, width)) {
            _a64(_logicalInst[op.index - UniOpRRR.and.index], [dst, a, b]);
            return;
          }
        case UniOpRRR.add:
        case UniOpRRR.sub:
          var value = b.value;
          var reverse = value < 0;
          if (reverse) value = -value;
          if (op == UniOpRRR.sub) reverse = !reverse;
          // The upstream "post-index patching" experiment (marked TODO) is
          // not ported.
          if (value >= 0 && value <= 0xFFF) {
            _a64(reverse ? A64InstId.kSub : A64InstId.kAdd,
                [dst, a, Imm(value)]);
            return;
          }
        case UniOpRRR.mul:
          var value = b.value;
          // `value > 0u` on the unsigned 64-bit value.
          if (value != 0) {
            if (value & (value - 1) == 0) {
              _a64(A64InstId.kLsl, [dst, a, Imm(_ctz64(value))]);
              return;
            }
            // Multiplication with `power_of_2 + 1`.
            value--;
            if (value != 0 && value & (value - 1) == 0) {
              _a64(A64InstId.kAdd,
                  [dst, a, a, A64ShiftOp(A64Shift.lsl, _ctz64(value))]);
              return;
            }
          }
        case UniOpRRR.sMin:
        case UniOpRRR.sMax:
          final value = b.value;
          if (value == 0 || value == -1) {
            // smin(a, 0) == and(a, expand_msb(a)), smin(a, -1) == orn(...),
            // smax(a, 0) == bic(...), smax(a, -1) == orr(...).
            //
            // Deviation from upstream, whose table has ORR for smin(a, -1)
            // and ORN for smax(a, -1). Running upstream on AArch64 gives
            // smin(7, -1) = 7, smin(-5, -1) = -1, smax(7, -1) = -1 and
            // smax(-5, -1) = -5.
            const instTable = [
              A64InstId.kAnd,
              A64InstId.kOrn,
              A64InstId.kBic,
              A64InstId.kOrr,
            ];
            final instId = instTable[
                (op.index - UniOpRRR.sMin.index) * 2 + (value == -1 ? 1 : 0)];
            _a64(instId, [dst, a, a, A64ShiftOp(A64Shift.asr, width - 1)]);
            return;
          }
        case UniOpRRR.sll:
        case UniOpRRR.srl:
        case UniOpRRR.sra:
          _a64(_shiftInst[op.index - UniOpRRR.sll.index], [dst, a, b]);
          return;
        case UniOpRRR.rol:
        case UniOpRRR.ror:
          var value = b.value & (width - 1);
          // Deviation from upstream, which emits `ror dst, a, #width` for a
          // rotation left by 0 (`width - 0`); running upstream fails with
          // InvalidImmediate. The rotation amount is taken modulo `width`.
          if (op == UniOpRRR.rol) value = (width - value) & (width - 1);
          _a64(A64InstId.kRor, [dst, a, Imm(value)]);
          return;
        default:
          // Unhandled instruction means to use a register instead of
          // immediate.
          break;
      }
    }

    // ArithOp Reg, Reg, Reg
    final a = _gpAs(src1, dst);
    final b = _gpForceRegA64(src2, dst);

    switch (op) {
      case UniOpRRR.and:
      case UniOpRRR.or:
      case UniOpRRR.xor:
      case UniOpRRR.bic:
        _a64(_logicalInst[op.index - UniOpRRR.and.index], [dst, a, b]);
      case UniOpRRR.add:
        _a64(A64InstId.kAdd, [dst, a, b]);
      case UniOpRRR.sub:
        _a64(A64InstId.kSub, [dst, a, b]);
      case UniOpRRR.mul:
        _a64(A64InstId.kMul, [dst, a, b]);
      case UniOpRRR.uDiv:
        _a64(A64InstId.kUdiv, [dst, a, b]);
      case UniOpRRR.uMod:
        final tmp = _newSimilarGpA64(dst, '@tmp');
        _a64(A64InstId.kUdiv, [tmp, a, b]);
        _a64(A64InstId.kMul, [tmp, tmp, b]);
        _a64(A64InstId.kSub, [dst, a, tmp]);
      case UniOpRRR.sMin:
      case UniOpRRR.sMax:
      case UniOpRRR.uMin:
      case UniOpRRR.uMax:
        final cond = switch (op) {
          UniOpRRR.sMin => A64Cond.lt,
          UniOpRRR.sMax => A64Cond.gt,
          UniOpRRR.uMin => A64Cond.cc,
          _ => A64Cond.hi,
        };
        _a64(A64InstId.kCmp, [a, b]);
        _a64(A64InstId.kCsel, [dst, a, b, A64CondOp(cond)]);
      case UniOpRRR.sll:
      case UniOpRRR.srl:
      case UniOpRRR.sra:
        _a64(_shiftInst[op.index - UniOpRRR.sll.index], [dst, a, b]);
      case UniOpRRR.rol:
        final tmp = _newSimilarGpA64(dst, '@rol_rev');
        _a64(A64InstId.kNeg, [tmp, b]);
        _a64(A64InstId.kRor, [dst, a, tmp]);
      case UniOpRRR.ror:
        _a64(A64InstId.kRor, [dst, a, b]);
      case UniOpRRR.sBound:
        // Deviation from upstream, which writes `bic dst, a, a, asr` before
        // the `csel` that reads `b`; with `dst == b` running upstream gives
        // sbound(7, 3) = 7. The BIC result goes to a temporary then.
        final t = dst.id == b.id ? _newSimilarGpA64(dst, '@tmp') : dst;
        _a64(A64InstId.kCmp, [a, b]);
        _a64(A64InstId.kBic, [t, a, a, A64ShiftOp(A64Shift.asr, width - 1)]);
        _a64(A64InstId.kCsel, [dst, t, b, const A64CondOp(A64Cond.lt)]);
    }
  }

  static int _ctz64(int v) {
    var n = 0;
    while (v & 1 == 0) {
      v = v >>> 1;
      n++;
    }
    return n;
  }
}
