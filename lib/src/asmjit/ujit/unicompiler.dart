/// Universal Compiler
///
/// Ported from asmjit/ujit/unicompiler.h

import '../core/compiler.dart';
import '../core/reg_type.dart';
import '../core/type.dart';
import '../core/arch.dart';
import '../core/labels.dart';
import '../core/error.dart';
import '../core/func.dart';
import '../core/reg_utils.dart';
import '../runtime/cpuinfo.dart';

import '../x86/x86.dart';
import '../x86/x86_operands.dart';
import '../x86/x86_simd.dart';
import '../x86/x86_inst_db.g.dart';
import 'ujitbase.dart';
import 'vecconsttable.dart';
import 'uniop.dart';
import 'unicondition.dart';
import '../core/condcode.dart';

part 'unicompiler_x86.dart';

// ============================================================================
// [X86 Extension Enums]
// ============================================================================

/// General purpose extension flags (X86).
enum GPExt {
  kADX,
  kBMI,
  kBMI2,
  kLZCNT,
  kMOVBE,
  kPOPCNT,
  kIntrin,
}

/// SSE extension flags (X86).
enum SSEExt {
  kSSE2,
  kSSE3,
  kSSSE3,
  kSSE4_1,
  kSSE4_2,
  kPCLMULQDQ,
  kIntrin,
}

/// AVX extension flags (X86).
enum AVXExt {
  kAVX,
  kAVX2,
  kF16C,
  kFMA,
  kGFNI,
  kVAES,
  kVPCLMULQDQ,
  kAVX_IFMA,
  kAVX_NE_CONVERT,
  kAVX_VNNI,
  kAVX_VNNI_INT8,
  kAVX_VNNI_INT16,
  kAVX512,
  kAVX512_BF16,
  kAVX512_BITALG,
  kAVX512_FP16,
  kAVX512_IFMA,
  kAVX512_VBMI,
  kAVX512_VBMI2,
  kAVX512_VNNI,
  kAVX512_VPOPCNTDQ,
  kIntrin,
}

// ============================================================================
// [X86Vec - Common base for vector registers in UniCompiler context]
// ============================================================================

/// Abstract base for X86 vector registers used by UniCompiler.
abstract class X86Vec extends BaseReg {
  /// The XMM version of this register.
  X86Xmm get xmm;

  /// The YMM version of this register.
  X86Ymm get ymm;

  /// The ZMM version of this register.
  X86Zmm get zmm;
}

// ============================================================================
// [UniCompilerBase]
// ============================================================================

/// Base class for UniCompiler holding state and common logic.
abstract class UniCompilerBase {
  static const int kMaxKRegConstCount = 4;

  final BaseCompiler cc;

  // Extension masks
  int _gpExtMask = 0;
  int _sseExtMask = 0;
  int _avxExtMask = 0;
  int _asimdExtMask = 0;

  // Behavior settings
  ScalarOpBehavior _scalarOpBehavior = ScalarOpBehavior.zeroing;
  FMinFMaxOpBehavior _fMinFMaxOpBehavior = FMinFMaxOpBehavior.finiteValue;
  FMAddOpBehavior _fMAddOpBehavior = FMAddOpBehavior.noFMA;
  FloatToIntOutsideRangeBehavior _floatToIntBehavior =
      FloatToIntOutsideRangeBehavior.smallestValue;

  CpuFeatures _features = const CpuFeatures();

  int _vecRegCount = 0;
  VecWidth _vecWidth = VecWidth.k128;
  int _vecMultiplier = 1;
  RegType _vecRegType = RegType.vec128;
  TypeId _vecTypeId = TypeId.void_;

  // Constant table
  VecConstTableRef? _ctRef;

  // Function hook
  BaseNode? _funcInitHook;

  UniCompilerBase(this.cc);

  // ============================================================================
  // [Architecture Queries]
  // ============================================================================

  bool get is32Bit => cc.environment.is32Bit;
  bool get is64Bit => cc.environment.is64Bit;
  int get registerSize => is64Bit ? 8 : 4;
  Arch get arch => cc.environment.arch;
  bool get isX86 => arch == Arch.x86;
  bool get isX64 => arch == Arch.x64;
  bool get isX86Family => isX86 || isX64;
  bool get isArm32 => arch == Arch.arm;
  bool get isArm64 => arch == Arch.aarch64;
  bool get isArmFamily => isArm32 || isArm64;

  // ============================================================================
  // [Extension Queries (X86)]
  // ============================================================================

  bool hasGpExt(GPExt ext) => (_gpExtMask & (1 << ext.index)) != 0;
  bool hasSseExt(SSEExt ext) => (_sseExtMask & (1 << ext.index)) != 0;
  bool hasAvxExt(AVXExt ext) => (_avxExtMask & (1 << ext.index)) != 0;

  // Convenience
  bool get hasAdx => hasGpExt(GPExt.kADX);
  bool get hasBmi => hasGpExt(GPExt.kBMI);
  bool get hasBmi2 => hasGpExt(GPExt.kBMI2);
  bool get hasLzcnt => hasGpExt(GPExt.kLZCNT);
  bool get hasMovbe => hasGpExt(GPExt.kMOVBE);
  bool get hasPopcnt => hasGpExt(GPExt.kPOPCNT);

  bool get hasSse2 => hasSseExt(SSEExt.kSSE2);
  bool get hasSse3 => hasSseExt(SSEExt.kSSE3);
  bool get hasSsse3 => hasSseExt(SSEExt.kSSSE3);
  bool get hasSse41 => hasSseExt(SSEExt.kSSE4_1);
  bool get hasSse42 => hasSseExt(SSEExt.kSSE4_2);
  bool get hasPclmulqdq => hasSseExt(SSEExt.kPCLMULQDQ);

  bool get hasAvx => hasAvxExt(AVXExt.kAVX);
  bool get hasAvx2 => hasAvxExt(AVXExt.kAVX2);
  bool get hasF16c => hasAvxExt(AVXExt.kF16C);
  bool get hasFma => hasAvxExt(AVXExt.kFMA);
  bool get hasGfni => hasAvxExt(AVXExt.kGFNI);
  bool get hasVpclmulqdq => hasAvxExt(AVXExt.kVPCLMULQDQ);
  bool get hasAvx512 => hasAvxExt(AVXExt.kAVX512);

  bool get hasNonDestructiveSrc => hasAvx;

  // ============================================================================
  // [Behavior Queries]
  // ============================================================================

  ScalarOpBehavior get scalarOpBehavior => _scalarOpBehavior;
  FMinFMaxOpBehavior get fMinFMaxOpBehavior => _fMinFMaxOpBehavior;
  FMAddOpBehavior get fMAddOpBehavior => _fMAddOpBehavior;
  FloatToIntOutsideRangeBehavior get floatToIntBehavior => _floatToIntBehavior;

  bool get isScalarOpZeroing => _scalarOpBehavior == ScalarOpBehavior.zeroing;
  bool get isScalarOpPreservingVec128 =>
      _scalarOpBehavior == ScalarOpBehavior.preservingVec128;
  bool get isFMinFMaxFinite =>
      _fMinFMaxOpBehavior == FMinFMaxOpBehavior.finiteValue;
  bool get isFMinFMaxTernary =>
      _fMinFMaxOpBehavior == FMinFMaxOpBehavior.ternaryLogic;
  bool get isFMAddFused => _fMAddOpBehavior != FMAddOpBehavior.noFMA;

  // ============================================================================
  // [SIMD Width]
  // ============================================================================

  /// Provides access to ASIMD extension mask (for ARM).
  int get asimdExtMask => _asimdExtMask;

  /// Provides access to TypeId for current vector type.
  TypeId get vecTypeId => _vecTypeId;

  int get vecRegCount => _vecRegCount;
  VecWidth get vecWidth => _vecWidth;
  int get vecMultiplier => _vecMultiplier;
  bool get use256BitSimd => _vecWidth.id >= VecWidth.k256.id;
  bool get use512BitSimd => _vecWidth.id >= VecWidth.k512.id;

  /// Initialize vector width based on features and desired width.
  void initVecWidth(VecWidth vw) {
    _vecWidth = vw;
    _vecMultiplier = 1 << vw.id;
    _vecRegType = RegType.values[RegType.vec128.index + vw.id];

    switch (_vecRegType) {
      case RegType.vec128:
        _vecTypeId = TypeId.int8x16;
        break;
      case RegType.vec256:
        _vecTypeId = TypeId.int8x32;
        break;
      case RegType.vec512:
        _vecTypeId = TypeId.int8x64;
        break;
      default:
        _vecTypeId = TypeId.void_;
    }
  }

  // ============================================================================
  // [Labels]
  // ============================================================================

  Label newLabel() => cc.newLabel();

  void bind(Label label) => cc.bind(label);
}

// ============================================================================
// [UniCompiler]
// ============================================================================

/// Universal compiler.
///
/// Provides a cross-platform JIT compilation API that abstracts architecture
/// differences.
class UniCompiler extends UniCompilerBase with UniCompilerX86 {
  UniCompiler(BaseCompiler cc, {CpuFeatures? features, VecConstTableRef? ctRef})
      : super(cc) {
    if (features != null) {
      setFeatures(features);
    }
    _ctRef = ctRef;
    _initDefaults();
  }

  /// Access to constant table reference.
  VecConstTableRef? get ctRef => _ctRef;

  void _initDefaults() {
    if (isX86Family) {
      _vecRegCount = isX86 ? 8 : 16;
      _scalarOpBehavior = ScalarOpBehavior.preservingVec128;
      _fMinFMaxOpBehavior = FMinFMaxOpBehavior.ternaryLogic;
    } else if (isArmFamily) {
      _vecRegCount = 32;
      _scalarOpBehavior = ScalarOpBehavior.zeroing;
      _fMinFMaxOpBehavior = FMinFMaxOpBehavior.finiteValue;
    }
  }

  /// Sets CPU features and updates extension masks.
  void setFeatures(CpuFeatures features) {
    _features = features;
    if (isX86Family) {
      _updateX86Features();
    }
  }

  // ============================================================================
  // [Virtual Register Creation]
  // ============================================================================

  /// Creates a new 32-bit general purpose register.
  X86Gp newGp32([String? name]) {
    final vreg = cc.newVirtReg(TypeId.int32,
        OperandSignature.fromRegTypeAndGroup(RegType.gp32, RegGroup.gp), name);
    return X86Gp.r32(vreg.id);
  }

  /// Creates a new 64-bit general purpose register.
  X86Gp newGp64([String? name]) {
    final vreg = cc.newVirtReg(TypeId.int64,
        OperandSignature.fromRegTypeAndGroup(RegType.gp64, RegGroup.gp), name);
    return X86Gp.r64(vreg.id);
  }

  /// Creates a native-sized GP register.
  X86Gp newGpz([String? name]) => is64Bit ? newGp64(name) : newGp32(name);

  /// Creates a pointer-sized GP register.
  X86Gp newGpPtr([String? name]) => newGpz(name);

  /// Creates a new XMM register (128-bit).
  X86Xmm newXmm([String? name]) {
    final vreg = cc.newVirtReg(
        TypeId.int8x16,
        OperandSignature.fromRegTypeAndGroup(RegType.vec128, RegGroup.vec),
        name);
    return X86Xmm(vreg.id);
  }

  /// Creates a new YMM register (256-bit).
  X86Ymm newYmm([String? name]) {
    final vreg = cc.newVirtReg(
        TypeId.int8x32,
        OperandSignature.fromRegTypeAndGroup(RegType.vec256, RegGroup.vec),
        name);
    return X86Ymm(vreg.id);
  }

  /// Creates a new ZMM register (512-bit).
  X86Zmm newZmm([String? name]) {
    final vreg = cc.newVirtReg(
        TypeId.int8x64,
        OperandSignature.fromRegTypeAndGroup(RegType.vec512, RegGroup.vec),
        name);
    return X86Zmm(vreg.id);
  }

  /// Creates a vector register with the current SIMD width.
  BaseReg newVec([String? name]) {
    switch (_vecWidth) {
      case VecWidth.k128:
        return newXmm(name);
      case VecWidth.k256:
        return newYmm(name);
      case VecWidth.k512:
        return newZmm(name);
      default:
        return newXmm(name);
    }
  }

  /// Creates a vector register with specified width.
  BaseReg newVecWithWidth(VecWidth vw, [String? name]) {
    switch (vw) {
      case VecWidth.k128:
        return newXmm(name);
      case VecWidth.k256:
        return newYmm(name);
      case VecWidth.k512:
        return newZmm(name);
      default:
        return newXmm(name);
    }
  }

  // ============================================================================
  // [Function Management]
  // ============================================================================

  /// Returns the current function being generated.
  FuncNode? get func => cc.func;

  /// Returns the function init hook node.
  BaseNode? get funcInitHook => _funcInitHook;

  /// Hooks the current function for UniCompiler-specific initialization.
  void hookFunc() {
    _funcInitHook = cc.cursor;
  }

  /// Unhooks the current function.
  void unhookFunc() {
    _funcInitHook = null;
  }

  /// Adds a function with the given signature.
  FuncNode addFunc(FuncSignature signature) {
    final node = cc.addFunc(signature);
    hookFunc();
    return node;
  }

  /// Ends the current function.
  AsmJitError endFunc() {
    unhookFunc();
    return cc.endFunc();
  }

  /// Emits a return.
  void ret() {
    cc.ret();
  }

  // ============================================================================
  // [GP Instruction Emission (Low-Level)]
  // ============================================================================

  /// Emits a MOV instruction (register/immediate to register).
  void emitMov(X86Gp dst, Operand src) {
    if (src is Imm && src.value == 0) {
      // Optimize: xor reg, reg for zeroing
      final r32 = X86Gp.r32(dst.id);
      cc.addNode(InstNode(X86InstId.kXor, [r32, r32]));
    } else {
      cc.addNode(InstNode(X86InstId.kMov, [dst, src]));
    }
  }

  /// Emits a 2-operand GP instruction.
  void emit2(int instId, Operand dst, Operand src) {
    cc.addNode(InstNode(instId, [dst, src]));
  }

  /// Emits a 3-operand GP instruction (dst = src1 op src2).
  /// For x86, this typically requires: if dst != src1: mov dst, src1; then op dst, src2
  void emit3(int instId, X86Gp dst, Operand src1, Operand src2) {
    if (src1 is X86Gp && dst.id != src1.id) {
      emitMov(dst, src1);
    }
    cc.addNode(InstNode(instId, [dst, src2]));
  }

  // ============================================================================
  // [GP Instruction Wrappers (3-operand style)]
  // ============================================================================

  /// Add: dst = src1 + src2
  void add(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kAdd, dst, src1, src2);
  }

  /// Sub: dst = src1 - src2
  void sub(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kSub, dst, src1, src2);
  }

  /// And: dst = src1 & src2
  void and_(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kAnd, dst, src1, src2);
  }

  /// Or: dst = src1 | src2
  void or_(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kOr, dst, src1, src2);
  }

  /// Xor: dst = src1 ^ src2
  void xor_(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kXor, dst, src1, src2);
  }

  /// Shift left: dst = src1 << src2
  void shl(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kShl, dst, src1, src2);
  }

  /// Shift right (logical): dst = src1 >> src2
  void shr(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kShr, dst, src1, src2);
  }

  /// Shift right (arithmetic): dst = src1 >> src2 (signed)
  void sar(X86Gp dst, Operand src1, Operand src2) {
    emit3(X86InstId.kSar, dst, src1, src2);
  }

  // ============================================================================
  // [GP Instruction Wrappers (2-operand/1-operand)]
  // ============================================================================

  /// Increment register.
  void inc(X86Gp dst) {
    cc.addNode(InstNode(X86InstId.kInc, [dst]));
  }

  /// Decrement register.
  void dec(X86Gp dst) {
    cc.addNode(InstNode(X86InstId.kDec, [dst]));
  }

  /// Negate register: dst = -src
  void neg(X86Gp dst, Operand src) {
    if (src is X86Gp && dst.id != src.id) {
      emitMov(dst, src);
    }
    cc.addNode(InstNode(X86InstId.kNeg, [dst]));
  }

  /// Bitwise NOT: dst = ~src
  void not_(X86Gp dst, Operand src) {
    if (src is X86Gp && dst.id != src.id) {
      emitMov(dst, src);
    }
    cc.addNode(InstNode(X86InstId.kNot, [dst]));
  }

  /// Byte swap: dst = bswap(src)
  void bswap(X86Gp dst, Operand src) {
    if (src is X86Gp && dst.id != src.id) {
      emitMov(dst, src);
    }
    cc.addNode(InstNode(X86InstId.kBswap, [dst]));
  }

  // ============================================================================
  // [SIMD Instruction Emission]
  // ============================================================================

  /// Emit aligned vector load: dst = *mem (aligned)
  void vLoadA(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqa, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
    }
  }

  /// Emit unaligned vector load: dst = *mem (unaligned)
  void vLoadU(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqu, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqu, [dst, src]));
    }
  }

  /// Emit aligned vector store: *mem = src (aligned)
  void vStoreA(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqa, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
    }
  }

  /// Emit unaligned vector store: *mem = src (unaligned)
  void vStoreU(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqu, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqu, [dst, src]));
    }
  }

  /// Emit vector move: dst = src
  void vMov(BaseReg dst, BaseReg src) {
    if (dst.id == src.id) return;
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovdqa, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
    }
  }

  /// Emit vector zero: dst = 0
  void vZero(BaseReg dst) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpxor, [dst, dst, dst]));
    } else {
      cc.addNode(InstNode(X86InstId.kPxor, [dst, dst]));
    }
  }

  /// Emit vector XOR: dst = a ^ b
  void vXor(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpxor, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPxor, [dst, b]));
    }
  }

  /// Emit vector OR: dst = a | b
  void vOr(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpor, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPor, [dst, b]));
    }
  }

  /// Emit vector AND: dst = a & b
  void vAnd(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpand, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPand, [dst, b]));
    }
  }

  /// Emit vector ANDN: dst = a & ~b
  void vAndNot(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(
          InstNode(X86InstId.kVpandn, [dst, b, a])); // Note: reversed operands
    } else {
      if (b is BaseReg && dst.id != b.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, b]));
      } else if (b is! BaseReg) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, b]));
      }
      cc.addNode(InstNode(X86InstId.kPandn, [dst, a]));
    }
  }

  /// Emit packed add bytes: dst = a + b (i8)
  void vAddI8(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpaddb, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPaddb, [dst, b]));
    }
  }

  /// Emit packed add words: dst = a + b (i16)
  void vAddI16(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpaddw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPaddw, [dst, b]));
    }
  }

  /// Emit packed add dwords: dst = a + b (i32)
  void vAddI32(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpaddd, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPaddd, [dst, b]));
    }
  }

  /// Emit packed sub bytes: dst = a - b (i8)
  void vSubI8(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsubb, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPsubb, [dst, b]));
    }
  }

  /// Emit packed sub words: dst = a - b (i16)
  void vSubI16(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsubw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPsubw, [dst, b]));
    }
  }

  /// Emit packed sub dwords: dst = a - b (i32)
  void vSubI32(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsubd, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPsubd, [dst, b]));
    }
  }

  /// Emit packed multiply low words: dst = (a * b) & 0xFFFF (i16)
  void vMulLoI16(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpmullw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPmullw, [dst, b]));
    }
  }

  /// Emit packed multiply high words signed: dst = (a * b) >> 16 (i16)
  void vMulHiI16(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpmulhw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPmulhw, [dst, b]));
    }
  }

  /// Emit packed multiply high words unsigned: dst = (a * b) >> 16 (u16)
  void vMulHiU16(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpmulhuw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPmulhuw, [dst, b]));
    }
  }

  /// Emit packed shuffle bytes: dst = shuffle(a, b)
  void vShufB(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpshufb, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPshufb, [dst, b]));
    }
  }

  /// Emit pack signed words with saturation: dst = pack_sat(a, b) -> u8
  void vPackUSWB(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpackuswb, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPackuswb, [dst, b]));
    }
  }

  /// Emit pack signed dwords with saturation: dst = pack_sat(a, b) -> i16
  void vPackSSDW(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpackssdw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPackssdw, [dst, b]));
    }
  }

  /// Emit unpack low bytes: dst = interleave_lo(a, b)
  void vUnpackLoI8(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpunpcklbw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPunpcklbw, [dst, b]));
    }
  }

  /// Emit unpack high bytes: dst = interleave_hi(a, b)
  void vUnpackHiI8(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpunpckhbw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPunpckhbw, [dst, b]));
    }
  }

  /// Emit compare equal bytes: dst = (a == b) ? 0xFF : 0x00
  void vCmpEqI8(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpcmpeqb, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPcmpeqb, [dst, b]));
    }
  }

  /// Emit compare equal words: dst = (a == b) ? 0xFFFF : 0x0000
  void vCmpEqI16(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpcmpeqw, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPcmpeqw, [dst, b]));
    }
  }

  /// Emit compare greater than signed bytes: dst = (a > b) ? 0xFF : 0x00
  void vCmpGtI8(BaseReg dst, BaseReg a, Operand b) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpcmpgtb, [dst, a, b]));
    } else {
      if (dst.id != a.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, a]));
      }
      cc.addNode(InstNode(X86InstId.kPcmpgtb, [dst, b]));
    }
  }

  /// Emit shift left logical words: dst = a << imm (i16)
  void vSllI16(BaseReg dst, BaseReg src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsllw, [dst, src, Imm(imm)]));
    } else {
      if (dst.id != src.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
      }
      cc.addNode(InstNode(X86InstId.kPsllw, [dst, Imm(imm)]));
    }
  }

  /// Emit shift right logical words: dst = a >> imm (u16)
  void vSrlI16(BaseReg dst, BaseReg src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsrlw, [dst, src, Imm(imm)]));
    } else {
      if (dst.id != src.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
      }
      cc.addNode(InstNode(X86InstId.kPsrlw, [dst, Imm(imm)]));
    }
  }

  /// Emit shift right arithmetic words: dst = a >> imm (i16)
  void vSraI16(BaseReg dst, BaseReg src, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpsraw, [dst, src, Imm(imm)]));
    } else {
      if (dst.id != src.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
      }
      cc.addNode(InstNode(X86InstId.kPsraw, [dst, Imm(imm)]));
    }
  }

  // ============================================================================
  // [Jump/Branch Instructions]
  // ============================================================================

  // NOTE: Jump instructions are handled by the underlying BaseCompiler/X86Compiler
  // which have proper jmp(), jcc() methods. UniCompiler wraps these for convenience.

  /// Emit unconditional jump.
  void emitJ(Operand target) {
    cc.addNode(InstNode(X86InstId.kJmp, [target]));
  }

  /// Emit conditional jump based on UniCondition.
  void emitJIf(Label target, UniCondition condition) {
    // First emit the condition test
    _emitConditionTest(condition);
    // Then emit the conditional jump
    final jccId = _condCodeToJcc(condition.cond);
    cc.addNode(InstNode(jccId, [LabelOp(target)]));
  }

  void _emitConditionTest(UniCondition cond) {
    final instId = _condOpToInstId(cond.op);
    cc.addNode(InstNode(instId, [cond.a, cond.b]));
  }

  int _condOpToInstId(UniOpCond op) {
    switch (op) {
      case UniOpCond.assignAnd:
        return X86InstId.kAnd;
      case UniOpCond.assignOr:
        return X86InstId.kOr;
      case UniOpCond.assignXor:
        return X86InstId.kXor;
      case UniOpCond.assignAdd:
        return X86InstId.kAdd;
      case UniOpCond.assignSub:
        return X86InstId.kSub;
      case UniOpCond.assignShr:
        return X86InstId.kShr;
      case UniOpCond.test:
        return X86InstId.kTest;
      case UniOpCond.bitTest:
        return X86InstId.kBt;
      case UniOpCond.compare:
        return X86InstId.kCmp;
    }
  }

  int _condCodeToJcc(int cond) {
    // Map CondCode constants to x86 Jcc instruction IDs
    switch (cond) {
      case CondCode.kEqual: // kZero
        return X86InstId.kJz;
      case CondCode.kNotEqual: // kNotZero
        return X86InstId.kJnz;
      case CondCode.kSignedLT: // kLess
        return X86InstId.kJl;
      case CondCode.kSignedGE: // kGreaterEqual
        return X86InstId.kJnl;
      case CondCode.kSignedLE: // kLessEqual
        return X86InstId.kJle;
      case CondCode.kSignedGT: // kGreater
        return X86InstId.kJnle;
      case CondCode.kUnsignedLT: // kBelow, kCarry
        return X86InstId.kJb;
      case CondCode.kUnsignedGE: // kAboveEqual, kNotCarry
        return X86InstId.kJnb;
      case CondCode.kUnsignedLE: // kBelowEqual
        return X86InstId.kJbe;
      case CondCode.kUnsignedGT: // kAbove
        return X86InstId.kJnbe;
      case CondCode.kOverflow:
        return X86InstId.kJo;
      case CondCode.kNotOverflow:
        return X86InstId.kJno;
      case CondCode.kSign: // kNegative
        return X86InstId.kJs;
      case CondCode.kNotSign: // kPositive
        return X86InstId.kJns;
      case CondCode.kParityEven:
        return X86InstId.kJp;
      case CondCode.kParityOdd:
        return X86InstId.kJnp;
      default:
        return X86InstId.kJmp;
    }
  }

  // ============================================================================
  // [High-Level SIMD Operations - emit_2v]
  // ============================================================================

  /// Emit 2-operand vector instruction based on UniOpVV.
  void emit2v(UniOpVV op, Operand dst, Operand src) {
    switch (op) {
      case UniOpVV.mov:
        vMov(dst as BaseReg, src as BaseReg);
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
          if (dst != src) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPabsb, [dst, dst]));
        }
        break;
      case UniOpVV.absI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsw, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPabsw, [dst, dst]));
        }
        break;
      case UniOpVV.absI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpabsd, [dst, src]));
        } else if (hasSsse3) {
          if (dst != src) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPabsd, [dst, dst]));
        }
        break;
      case UniOpVV.notU32:
      case UniOpVV.notU64:
        // NOT = XOR with all ones
        if (hasAvx) {
          // Create all-ones mask and XOR
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
          // SSE2 fallback: unpack with zero
          vZero(dst as BaseReg);
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
          // SSE2 fallback: unpack with zero
          vZero(dst as BaseReg);
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
          // SSE2 fallback: unpack with zero
          vZero(dst as BaseReg);
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
      // Floating point operations
      case UniOpVV.sqrtF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsqrtps, [dst, src]));
        } else {
          if (dst != src) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kSqrtps, [dst, dst]));
        }
        break;
      case UniOpVV.sqrtF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsqrtpd, [dst, src]));
        } else {
          if (dst != src) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kSqrtpd, [dst, dst]));
        }
        break;
      case UniOpVV.rcpF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVrcpps, [dst, src]));
        } else {
          if (dst != src) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kRcpps, [dst, dst]));
        }
        break;
      case UniOpVV.cvtI32ToF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcvtdq2ps, [dst, src]));
        } else {
          cc.addNode(InstNode(X86InstId.kCvtdq2ps, [dst, src]));
        }
        break;
      case UniOpVV.cvtF32LoToF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcvtps2pd, [dst, src]));
        } else {
          cc.addNode(InstNode(X86InstId.kCvtps2pd, [dst, src]));
        }
        break;
      case UniOpVV.cvtTruncF32ToI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVcvttps2dq, [dst, src]));
        } else {
          cc.addNode(InstNode(X86InstId.kCvttps2dq, [dst, src]));
        }
        break;
      case UniOpVV.truncF32:
        if (hasAvx) {
          cc.addNode(InstNode(
              X86InstId.kVroundps, [dst, src, Imm(3)])); // 3 = truncate mode
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(3)]));
        }
        break;
      case UniOpVV.truncF64:
        if (hasAvx) {
          cc.addNode(InstNode(
              X86InstId.kVroundpd, [dst, src, Imm(3)])); // 3 = truncate mode
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(3)]));
        }
        break;
      case UniOpVV.floorF32:
        if (hasAvx) {
          cc.addNode(InstNode(
              X86InstId.kVroundps, [dst, src, Imm(1)])); // 1 = floor mode
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(1)]));
        }
        break;
      case UniOpVV.floorF64:
        if (hasAvx) {
          cc.addNode(InstNode(
              X86InstId.kVroundpd, [dst, src, Imm(1)])); // 1 = floor mode
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(1)]));
        }
        break;
      case UniOpVV.ceilF32:
        if (hasAvx) {
          cc.addNode(InstNode(
              X86InstId.kVroundps, [dst, src, Imm(2)])); // 2 = ceil mode
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundps, [dst, src, Imm(2)]));
        }
        break;
      case UniOpVV.ceilF64:
        if (hasAvx) {
          cc.addNode(InstNode(
              X86InstId.kVroundpd, [dst, src, Imm(2)])); // 2 = ceil mode
        } else if (hasSse41) {
          cc.addNode(InstNode(X86InstId.kRoundpd, [dst, src, Imm(2)]));
        }
        break;
      default:
        throw UnimplementedError('emit2v: $op not implemented');
    }
  }

  // ============================================================================
  // [High-Level SIMD Operations - emit_3v]
  // ============================================================================

  /// Emit 3-operand vector instruction based on UniOpVVV.
  void emit3v(UniOpVVV op, Operand dst, Operand src1, Operand src2) {
    switch (op) {
      case UniOpVVV.andU32:
      case UniOpVVV.andU64:
        vAnd(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.orU32:
      case UniOpVVV.orU64:
        vOr(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.xorU32:
      case UniOpVVV.xorU64:
        vXor(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.andnU32:
      case UniOpVVV.andnU64:
        vAndNot(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.addU8:
        vAddI8(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.addU16:
        vAddI16(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.addU32:
        vAddI32(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.addU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddq, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPaddq, [dst, src2]));
        }
        break;
      case UniOpVVV.subU8:
        vSubI8(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.subU16:
        vSubI16(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.subU32:
        vSubI32(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.subU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubq, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPsubq, [dst, src2]));
        }
        break;
      // Saturating arithmetic operations
      case UniOpVVV.addsI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddsb, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPaddsb, [dst, src2]));
        }
        break;
      case UniOpVVV.addsU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddusb, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPaddusb, [dst, src2]));
        }
        break;
      case UniOpVVV.addsI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddsw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPaddsw, [dst, src2]));
        }
        break;
      case UniOpVVV.addsU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpaddusw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPaddusw, [dst, src2]));
        }
        break;
      case UniOpVVV.subsI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubsb, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPsubsb, [dst, src2]));
        }
        break;
      case UniOpVVV.subsU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubusb, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPsubusb, [dst, src2]));
        }
        break;
      case UniOpVVV.subsI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubsw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPsubsw, [dst, src2]));
        }
        break;
      case UniOpVVV.subsU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsubusw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPsubusw, [dst, src2]));
        }
        break;
      // BIC (bit clear) - dst = a & ~b
      case UniOpVVV.bicU32:
      case UniOpVVV.bicU64:
        // BIC is ANDN with reversed operands
        vAndNot(dst as BaseReg, src2 as BaseReg, src1);
        break;
      // Average operations (rounded)
      case UniOpVVV.avgrU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpavgb, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPavgb, [dst, src2]));
        }
        break;
      case UniOpVVV.avgrU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpavgw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPavgw, [dst, src2]));
        }
        break;
      case UniOpVVV.mulU16:
        vMulLoI16(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.mulhI16:
        vMulHiI16(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.mulhU16:
        vMulHiU16(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.mulU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmulld, [dst, src1, src2]));
        } else if (hasSse41) {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPmulld, [dst, src2]));
        }
        break;
      case UniOpVVV.cmpEqU8:
        vCmpEqI8(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.cmpEqU16:
        vCmpEqI16(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.cmpEqU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpcmpeqd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPcmpeqd, [dst, src2]));
        }
        break;
      case UniOpVVV.cmpGtI8:
        vCmpGtI8(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.cmpGtI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpcmpgtw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPcmpgtw, [dst, src2]));
        }
        break;
      case UniOpVVV.cmpGtI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpcmpgtd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPcmpgtd, [dst, src2]));
        }
        break;
      case UniOpVVV.minI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminsb, [dst, src1, src2]));
        } else if (hasSse41) {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPminsb, [dst, src2]));
        }
        break;
      case UniOpVVV.minU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminub, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPminub, [dst, src2]));
        }
        break;
      case UniOpVVV.minI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminsw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPminsw, [dst, src2]));
        }
        break;
      case UniOpVVV.minU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpminuw, [dst, src1, src2]));
        } else if (hasSse41) {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPminuw, [dst, src2]));
        }
        break;
      case UniOpVVV.maxI8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxsb, [dst, src1, src2]));
        } else if (hasSse41) {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPmaxsb, [dst, src2]));
        }
        break;
      case UniOpVVV.maxU8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxub, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPmaxub, [dst, src2]));
        }
        break;
      case UniOpVVV.maxI16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxsw, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPmaxsw, [dst, src2]));
        }
        break;
      case UniOpVVV.maxU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaxuw, [dst, src1, src2]));
        } else if (hasSse41) {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPmaxuw, [dst, src2]));
        }
        break;
      case UniOpVVV.packsI16I8:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpacksswb, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPacksswb, [dst, src2]));
        }
        break;
      case UniOpVVV.packsI16U8:
        vPackUSWB(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.packsI32I16:
        vPackSSDW(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.interleaveLoU8:
        vUnpackLoI8(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.interleaveHiU8:
        vUnpackHiI8(dst as BaseReg, src1 as BaseReg, src2);
        break;
      case UniOpVVV.interleaveLoU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpcklwd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPunpcklwd, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveHiU16:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckhwd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPunpckhwd, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveLoU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckldq, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPunpckldq, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveHiU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckhdq, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPunpckhdq, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveLoU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpcklqdq, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPunpcklqdq, [dst, src2]));
        }
        break;
      case UniOpVVV.interleaveHiU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpunpckhqdq, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPunpckhqdq, [dst, src2]));
        }
        break;
      case UniOpVVV.swizzlevU8:
        vShufB(dst as BaseReg, src1 as BaseReg, src2);
        break;
      // Floating point operations

      case UniOpVVV.addF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVaddps, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kAddps, [dst, src2]));
        }
        break;
      case UniOpVVV.addF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVaddpd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kAddpd, [dst, src2]));
        }
        break;
      case UniOpVVV.subF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsubps, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kSubps, [dst, src2]));
        }
        break;
      case UniOpVVV.subF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVsubpd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kSubpd, [dst, src2]));
        }
        break;
      case UniOpVVV.mulF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmulps, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMulps, [dst, src2]));
        }
        break;
      case UniOpVVV.mulF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmulpd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMulpd, [dst, src2]));
        }
        break;
      case UniOpVVV.divF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVdivps, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kDivps, [dst, src2]));
        }
        break;
      case UniOpVVV.divF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVdivpd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kDivpd, [dst, src2]));
        }
        break;
      case UniOpVVV.minF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVminps, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMinps, [dst, src2]));
        }
        break;
      case UniOpVVV.minF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVminpd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMinpd, [dst, src2]));
        }
        break;
      case UniOpVVV.maxF32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmaxps, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMaxps, [dst, src2]));
        }
        break;
      case UniOpVVV.maxF64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVmaxpd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMaxpd, [dst, src2]));
        }
        break;
      default:
        throw UnimplementedError('emit3v: $op not implemented');
    }
  }

  // ============================================================================
  // [High-Level SIMD Operations - emit_2vi (shift with immediate)]
  // ============================================================================

  /// Emit 2-operand vector instruction with immediate based on UniOpVVI.
  void emit2vi(UniOpVVI op, Operand dst, Operand src, int imm) {
    switch (op) {
      case UniOpVVI.sllU16:
        vSllI16(dst as BaseReg, src as BaseReg, imm);
        break;
      case UniOpVVI.sllU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpslld, [dst, src, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPslld, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.sllU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsllq, [dst, src, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPsllq, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.srlU16:
        vSrlI16(dst as BaseReg, src as BaseReg, imm);
        break;
      case UniOpVVI.srlU32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsrld, [dst, src, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPsrld, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.srlU64:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsrlq, [dst, src, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPsrlq, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.sraI16:
        vSraI16(dst as BaseReg, src as BaseReg, imm);
        break;
      case UniOpVVI.sraI32:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsrad, [dst, src, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPsrad, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.sllbU128:
        // Shift left bytes
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpslldq, [dst, src, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPslldq, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.srlbU128:
        // Shift right bytes
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpsrldq, [dst, src, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src]));
          }
          cc.addNode(InstNode(X86InstId.kPsrldq, [dst, Imm(imm)]));
        }
        break;
      case UniOpVVI.swizzleU32x4:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpshufd, [dst, src, Imm(imm)]));
        } else {
          cc.addNode(InstNode(X86InstId.kPshufd, [dst, src, Imm(imm)]));
        }
        break;
      case UniOpVVI.swizzleLoU16x4:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpshuflw, [dst, src, Imm(imm)]));
        } else {
          cc.addNode(InstNode(X86InstId.kPshuflw, [dst, src, Imm(imm)]));
        }
        break;
      case UniOpVVI.swizzleHiU16x4:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpshufhw, [dst, src, Imm(imm)]));
        } else {
          cc.addNode(InstNode(X86InstId.kPshufhw, [dst, src, Imm(imm)]));
        }
        break;
      default:
        throw UnimplementedError('emit2vi: $op not implemented');
    }
  }

  // ============================================================================
  // [High-Level SIMD Operations - emit_3vi (shuffle/blend with immediate)]
  // ============================================================================

  /// Emit 3-operand vector instruction with immediate based on UniOpVVVI.
  void emit3vi(UniOpVVVI op, Operand dst, Operand src1, Operand src2, int imm) {
    switch (op) {
      case UniOpVVVI.alignrU128:
        if (hasAvx) {
          cc.addNode(
              InstNode(X86InstId.kVpalignr, [dst, src1, src2, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPalignr, [dst, src2, Imm(imm)]));
        }
        break;
      case UniOpVVVI.interleaveShuffleU32x4:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVshufps, [dst, src1, src2, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kShufps, [dst, src2, Imm(imm)]));
        }
        break;
      case UniOpVVVI.interleaveShuffleF64x2:
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVshufpd, [dst, src1, src2, Imm(imm)]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kShufpd, [dst, src2, Imm(imm)]));
        }
        break;
      default:
        throw UnimplementedError('emit3vi: $op not implemented');
    }
  }

  // ============================================================================
  // [Scalar Vector Operations]
  // ============================================================================

  /// Move GP to/from vector scalar.
  void sMov(Operand dst, Operand src) {
    if (dst is X86Gp && src is BaseReg) {
      // Vec -> GP
      if (hasAvx) {
        cc.addNode(InstNode(X86InstId.kVmovd, [dst, src]));
      } else {
        cc.addNode(InstNode(X86InstId.kMovd, [dst, src]));
      }
    } else if (dst is BaseReg && src is X86Gp) {
      // GP -> Vec
      if (hasAvx) {
        cc.addNode(InstNode(X86InstId.kVmovd, [dst, src]));
      } else {
        cc.addNode(InstNode(X86InstId.kMovd, [dst, src]));
      }
    }
  }

  /// Extract u16 from vector at index.
  void sExtractU16(X86Gp dst, BaseReg src, int idx) {
    if (hasSse41 || hasAvx) {
      if (hasAvx) {
        cc.addNode(InstNode(X86InstId.kVpextrw, [dst, src, Imm(idx)]));
      } else {
        cc.addNode(InstNode(X86InstId.kPextrw, [dst, src, Imm(idx)]));
      }
    } else {
      cc.addNode(InstNode(X86InstId.kPextrw, [dst, src, Imm(idx)]));
    }
  }

  /// Insert u16 into vector at index.
  void sInsertU16(BaseReg dst, X86Gp src, int idx) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpinsrw, [dst, dst, src, Imm(idx)]));
    } else {
      cc.addNode(InstNode(X86InstId.kPinsrw, [dst, src, Imm(idx)]));
    }
  }

  // ============================================================================
  // [Blend Operations]
  // ============================================================================

  /// Blend vector elements based on immediate mask.
  void vBlend(BaseReg dst, BaseReg src1, Operand src2, int imm) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpblendw, [dst, src1, src2, Imm(imm)]));
    } else if (hasSse41) {
      if (dst.id != src1.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
      }
      cc.addNode(InstNode(X86InstId.kPblendw, [dst, src2, Imm(imm)]));
    }
  }

  /// Variable blend (using mask in XMM0 for SSE4.1).
  void vBlendV(BaseReg dst, BaseReg src1, Operand src2, BaseReg mask) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVpblendvb, [dst, src1, src2, mask]));
    } else if (hasSse41) {
      // SSE4.1 pblendvb implicitly uses XMM0 as mask
      // Need to move mask to XMM0 first
      if (dst.id != src1.id) {
        cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
      }
      cc.addNode(InstNode(X86InstId.kPblendvb, [dst, src2]));
    }
  }

  // ============================================================================
  // [High-Level SIMD Operations - emit_4v (FMA operations)]
  // ============================================================================

  /// Emit 4-operand vector instruction based on UniOpVVVV.
  void emit4v(
      UniOpVVVV op, Operand dst, Operand src1, Operand src2, Operand src3) {
    switch (op) {
      case UniOpVVVV.blendvU8:
        vBlendV(dst as BaseReg, src1 as BaseReg, src2, src3 as BaseReg);
        break;
      case UniOpVVVV.mAddU16:
        // Madd = Multiply and Add for integers (pmaddwd)
        if (hasAvx) {
          cc.addNode(InstNode(X86InstId.kVpmaddwd, [dst, src1, src2]));
        } else {
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovdqa, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kPmaddwd, [dst, src2]));
        }
        break;
      case UniOpVVVV.mAddF32S:
      case UniOpVVVV.mAddF32:
        // FMA: dst = src1 * src2 + src3
        if (hasFma) {
          cc.addNode(InstNode(X86InstId.kVfmadd213ps, [dst, src1, src2]));
        } else if (hasAvx) {
          // Fallback: mul then add
          final temp = newVec();
          cc.addNode(InstNode(X86InstId.kVmulps, [temp, src1, src2]));
          cc.addNode(InstNode(X86InstId.kVaddps, [dst, temp, src3]));
        } else {
          // SSE fallback
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMulps, [dst, src2]));
          cc.addNode(InstNode(X86InstId.kAddps, [dst, src3]));
        }
        break;
      case UniOpVVVV.mAddF64S:
      case UniOpVVVV.mAddF64:
        // FMA: dst = src1 * src2 + src3
        if (hasFma) {
          cc.addNode(InstNode(X86InstId.kVfmadd213pd, [dst, src1, src2]));
        } else if (hasAvx) {
          // Fallback: mul then add
          final temp = newVec();
          cc.addNode(InstNode(X86InstId.kVmulpd, [temp, src1, src2]));
          cc.addNode(InstNode(X86InstId.kVaddpd, [dst, temp, src3]));
        } else {
          // SSE fallback
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMulpd, [dst, src2]));
          cc.addNode(InstNode(X86InstId.kAddpd, [dst, src3]));
        }
        break;
      case UniOpVVVV.mSubF32S:
      case UniOpVVVV.mSubF32:
        // FMS: dst = src1 * src2 - src3
        if (hasFma) {
          cc.addNode(InstNode(X86InstId.kVfmsub213ps, [dst, src1, src2]));
        } else if (hasAvx) {
          // Fallback: mul then sub
          final temp = newVec();
          cc.addNode(InstNode(X86InstId.kVmulps, [temp, src1, src2]));
          cc.addNode(InstNode(X86InstId.kVsubps, [dst, temp, src3]));
        } else {
          // SSE fallback
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovaps, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMulps, [dst, src2]));
          cc.addNode(InstNode(X86InstId.kSubps, [dst, src3]));
        }
        break;
      case UniOpVVVV.mSubF64S:
      case UniOpVVVV.mSubF64:
        // FMS: dst = src1 * src2 - src3
        if (hasFma) {
          cc.addNode(InstNode(X86InstId.kVfmsub213pd, [dst, src1, src2]));
        } else if (hasAvx) {
          // Fallback: mul then sub
          final temp = newVec();
          cc.addNode(InstNode(X86InstId.kVmulpd, [temp, src1, src2]));
          cc.addNode(InstNode(X86InstId.kVsubpd, [dst, temp, src3]));
        } else {
          // SSE fallback
          if ((dst as BaseReg).id != (src1 as BaseReg).id) {
            cc.addNode(InstNode(X86InstId.kMovapd, [dst, src1]));
          }
          cc.addNode(InstNode(X86InstId.kMulpd, [dst, src2]));
          cc.addNode(InstNode(X86InstId.kSubpd, [dst, src3]));
        }
        break;
      default:
        throw UnimplementedError('emit4v: $op not implemented');
    }
  }

  // ============================================================================
  // [Memory Operations with Vector]
  // ============================================================================

  /// Load 64-bit from memory to vector.
  void vLoad64(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovq, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovq, [dst, src]));
    }
  }

  /// Store 64-bit from vector to memory.
  void vStore64(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovq, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovq, [dst, src]));
    }
  }

  /// Load 32-bit from memory to vector.
  void vLoad32(BaseReg dst, X86Mem src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovd, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovd, [dst, src]));
    }
  }

  /// Store 32-bit from vector to memory.
  void vStore32(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovd, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovd, [dst, src]));
    }
  }

  /// Non-temporal store (bypass cache).
  void vStoreNT(X86Mem dst, BaseReg src) {
    if (hasAvx) {
      cc.addNode(InstNode(X86InstId.kVmovntdq, [dst, src]));
    } else {
      cc.addNode(InstNode(X86InstId.kMovntdq, [dst, src]));
    }
  }
}
