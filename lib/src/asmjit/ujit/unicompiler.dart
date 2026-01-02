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
import '../arm/a64.dart';
import '../arm/a64_inst_db.g.dart';
import 'ujitbase.dart';
import 'vecconsttable.dart';
import 'uniop.dart';
import 'unicondition.dart';
import '../core/condcode.dart';

part 'unicompiler_x86.dart';
part 'unicompiler_a64.dart';

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

class VecConstData {
  final VecConst constant;
  final int virtRegId;
  const VecConstData(this.constant, this.virtRegId);
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
  final List<VecConstData> _vecConsts = [];
  final List<BaseReg?> _kReg = List.generate(kMaxKRegConstCount, (_) => null);
  final List<int> _kImm = List.generate(kMaxKRegConstCount, (_) => 0);
  BaseReg? _commonTablePtr;

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
class UniCompiler extends UniCompilerBase with UniCompilerX86, UniCompilerA64 {
  UniCompiler(BaseCompiler cc, {CpuFeatures? features, VecConstTableRef? ctRef})
      : super(cc) {
    if (features != null) {
      setFeatures(features);
    }
    _ctRef = ctRef;
    _initDefaults();
    if (isX86Family) {
      _updateX86Features();
    }
  }

  /// Access to constant table reference.
  VecConstTableRef? get ctRef => _ctRef;

  void _initDefaults() {
    initVecWidth(VecWidth.k128);
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

  /// Finalizes the compiler (runs passes like register allocation).
  void finalize() {
    cc.finalize();
  }

  /// Serializes the intermediate representation to an assembler.
  void serializeToAssembler(BaseEmitter assembler) {
    cc.serializeToAssembler(assembler);
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
    if (isX86Family) {
      _vLoadAX86(dst, src);
    } else {
      throw UnimplementedError('vLoadA not implemented for $arch');
    }
  }

  /// Emit unaligned vector load: dst = *mem (unaligned)
  void vLoadU(BaseReg dst, X86Mem src) {
    if (isX86Family) {
      _vLoadUX86(dst, src);
    } else {
      throw UnimplementedError('vLoadU not implemented for $arch');
    }
  }

  /// Emit aligned vector store: *mem = src (aligned)
  void vStoreA(X86Mem dst, BaseReg src) {
    if (isX86Family) {
      _vStoreAX86(dst, src);
    } else {
      throw UnimplementedError('vStoreA not implemented for $arch');
    }
  }

  /// Emit unaligned vector store: *mem = src (unaligned)
  void vStoreU(X86Mem dst, BaseReg src) {
    if (isX86Family) {
      _vStoreUX86(dst, src);
    } else {
      throw UnimplementedError('vStoreU not implemented for $arch');
    }
  }

  /// Emit vector move: dst = src
  void vMov(BaseReg dst, BaseReg src) {
    if (isX86Family) {
      _vMovX86(dst, src);
    } else {
      throw UnimplementedError('vMov not implemented for $arch');
    }
  }

  /// Emit vector zero: dst = 0
  void vZero(BaseReg dst) {
    if (isX86Family) {
      _vZeroX86(dst);
    } else {
      throw UnimplementedError('vZero not implemented for $arch');
    }
  }

  /// Emit vector XOR: dst = a ^ b
  void vXor(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vXorX86(dst, a, b);
    } else {
      throw UnimplementedError('vXor not implemented for $arch');
    }
  }

  /// Emit vector OR: dst = a | b
  void vOr(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vOrX86(dst, a, b);
    } else {
      throw UnimplementedError('vOr not implemented for $arch');
    }
  }

  /// Emit vector AND: dst = a & b
  void vAnd(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vAndX86(dst, a, b);
    } else {
      throw UnimplementedError('vAnd not implemented for $arch');
    }
  }

  /// Emit vector ANDN: dst = a & ~b
  void vAndNot(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vAndNotX86(dst, a, b);
    } else {
      throw UnimplementedError('vAndNot not implemented for $arch');
    }
  }

  /// Emit packed add bytes: dst = a + b (i8)
  void vAddI8(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vAddI8X86(dst, a, b);
    } else {
      throw UnimplementedError('vAddI8 not implemented for $arch');
    }
  }

  /// Emit packed add words: dst = a + b (i16)
  void vAddI16(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vAddI16X86(dst, a, b);
    } else {
      throw UnimplementedError('vAddI16 not implemented for $arch');
    }
  }

  /// Emit packed add dwords: dst = a + b (i32)
  void vAddI32(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vAddI32X86(dst, a, b);
    } else {
      throw UnimplementedError('vAddI32 not implemented for $arch');
    }
  }

  /// Emit packed sub bytes: dst = a - b (i8)
  void vSubI8(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vSubI8X86(dst, a, b);
    } else {
      throw UnimplementedError('vSubI8 not implemented for $arch');
    }
  }

  /// Emit packed sub words: dst = a - b (i16)
  void vSubI16(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vSubI16X86(dst, a, b);
    } else {
      throw UnimplementedError('vSubI16 not implemented for $arch');
    }
  }

  /// Emit packed sub dwords: dst = a - b (i32)
  void vSubI32(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vSubI32X86(dst, a, b);
    } else {
      throw UnimplementedError('vSubI32 not implemented for $arch');
    }
  }

  /// Emit packed multiply low words: dst = (a * b) & 0xFFFF (i16)
  void vMulLoI16(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vMulLoI16X86(dst, a, b);
    } else {
      throw UnimplementedError('vMulLoI16 not implemented for $arch');
    }
  }

  /// Emit packed multiply high words signed: dst = (a * b) >> 16 (i16)
  void vMulHiI16(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vMulHiI16X86(dst, a, b);
    } else {
      throw UnimplementedError('vMulHiI16 not implemented for $arch');
    }
  }

  /// Emit packed multiply high words unsigned: dst = (a * b) >> 16 (u16)
  void vMulHiU16(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vMulHiU16X86(dst, a, b);
    } else {
      throw UnimplementedError('vMulHiU16 not implemented for $arch');
    }
  }

  /// Emit packed shuffle bytes: dst = shuffle(a, b)
  void vShufB(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vShufBX86(dst, a, b);
    } else {
      throw UnimplementedError('vShufB not implemented for $arch');
    }
  }

  /// Emit pack signed words with saturation: dst = pack_sat(a, b) -> u8
  void vPackUSWB(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vPackUSWBX86(dst, a, b);
    } else {
      throw UnimplementedError('vPackUSWB not implemented for $arch');
    }
  }

  /// Emit pack signed dwords with saturation: dst = pack_sat(a, b) -> i16
  void vPackSSDW(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vPackSSDWX86(dst, a, b);
    } else {
      throw UnimplementedError('vPackSSDW not implemented for $arch');
    }
  }

  /// Emit blend instruction: dst = src1 blended with src2 (i16)
  void vBlend(BaseReg dst, BaseReg src1, Operand src2, int imm) {
    if (isX86Family) {
      _vBlendX86(dst, src1, src2, imm);
    } else {
      throw UnimplementedError('vBlend not implemented for $arch');
    }
  }

  /// Emit variable blend instruction: dst = src1 blended with src2 by mask (i8)
  void vBlendV(BaseReg dst, BaseReg src1, Operand src2, BaseReg mask) {
    if (isX86Family) {
      _vBlendVX86(dst, src1, src2, mask);
    } else {
      throw UnimplementedError('vBlendV not implemented for $arch');
    }
  }

  /// Emit unpack low bytes: dst = interleave_lo(a, b)
  void vUnpackLoI8(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vUnpackLoI8X86(dst, a, b);
    } else {
      throw UnimplementedError('vUnpackLoI8 not implemented for $arch');
    }
  }

  /// Emit unpack high bytes: dst = interleave_hi(a, b)
  void vUnpackHiI8(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vUnpackHiI8X86(dst, a, b);
    } else {
      throw UnimplementedError('vUnpackHiI8 not implemented for $arch');
    }
  }

  /// Emit compare equal bytes: dst = (a == b) ? 0xFF : 0x00
  void vCmpEqI8(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vCmpEqI8X86(dst, a, b);
    } else {
      throw UnimplementedError('vCmpEqI8 not implemented for $arch');
    }
  }

  /// Emit compare equal words: dst = (a == b) ? 0xFFFF : 0x0000
  void vCmpEqI16(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vCmpEqI16X86(dst, a, b);
    } else {
      throw UnimplementedError('vCmpEqI16 not implemented for $arch');
    }
  }

  /// Emit compare greater than signed bytes: dst = (a > b) ? 0xFF : 0x00
  void vCmpGtI8(BaseReg dst, BaseReg a, Operand b) {
    if (isX86Family) {
      _vCmpGtI8X86(dst, a, b);
    } else {
      throw UnimplementedError('vCmpGtI8 not implemented for $arch');
    }
  }

  /// Emit shift left logical words: dst = a << imm (i16)
  void vSllI16(BaseReg dst, BaseReg src, int imm) {
    if (isX86Family) {
      _vSllI16X86(dst, src, imm);
    } else {
      throw UnimplementedError('vSllI16 not implemented for $arch');
    }
  }

  /// Emit shift right logical words: dst = a >> imm (u16)
  void vSrlI16(BaseReg dst, BaseReg src, int imm) {
    if (isX86Family) {
      _vSrlI16X86(dst, src, imm);
    } else {
      throw UnimplementedError('vSrlI16 not implemented for $arch');
    }
  }

  /// Emit shift right arithmetic words: dst = a >> imm (i16)
  void vSraI16(BaseReg dst, BaseReg src, int imm) {
    if (isX86Family) {
      _vSraI16X86(dst, src, imm);
    } else {
      throw UnimplementedError('vSraI16 not implemented for $arch');
    }
  }

  /// Load 64-bit from memory to vector.
  void vLoad64(BaseReg dst, X86Mem src) {
    if (isX86Family) {
      _vLoad64X86(dst, src);
    } else {
      throw UnimplementedError('vLoad64 not implemented for $arch');
    }
  }

  /// Store 64-bit from vector to memory.
  void vStore64(X86Mem dst, BaseReg src) {
    if (isX86Family) {
      _vStore64X86(dst, src);
    } else {
      throw UnimplementedError('vStore64 not implemented for $arch');
    }
  }

  /// Load 32-bit from memory to vector.
  void vLoad32(BaseReg dst, X86Mem src) {
    if (isX86Family) {
      _vLoad32X86(dst, src);
    } else {
      throw UnimplementedError('vLoad32 not implemented for $arch');
    }
  }

  /// Store 32-bit from vector to memory.
  void vStore32(X86Mem dst, BaseReg src) {
    if (isX86Family) {
      _vStore32X86(dst, src);
    } else {
      throw UnimplementedError('vStore32 not implemented for $arch');
    }
  }

  /// Emit scalar move: dst = src (first element)
  void sMov(BaseReg dst, BaseReg src) {
    if (isX86Family) {
      _sMovX86(dst, src);
    } else {
      throw UnimplementedError('sMov not implemented for $arch');
    }
  }

  /// Emit extract 16-bit word: dst = src[imm] (u16)
  void sExtractU16(Operand dst, BaseReg src, int imm) {
    if (isX86Family) {
      _sExtractU16X86(dst, src, imm);
    } else {
      throw UnimplementedError('sExtractU16 not implemented for $arch');
    }
  }

  /// Emit insert 16-bit word: dst = src, dst[imm] = val
  void sInsertU16(BaseReg dst, BaseReg src, Operand val, int imm) {
    if (isX86Family) {
      _sInsertU16X86(dst, src, val, imm);
    } else {
      throw UnimplementedError('sInsertU16 not implemented for $arch');
    }
  }

  /// Non-temporal store (bypass cache).
  void vStoreNT(X86Mem dst, BaseReg src) {
    if (isX86Family) {
      _vStoreNTX86(dst, src);
    } else {
      throw UnimplementedError('vStoreNT not implemented for $arch');
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
  // [High-Level SIMD Operations]
  // ============================================================================

  /// Emit instruction with [vec, mem] operands.
  void emitVM(UniOpVM op, BaseReg dst, BaseMem src,
      {Alignment alignment = Alignment.none, int idx = 0}) {
    if (isX86Family) {
      if (src is! X86Mem) throw ArgumentError('X86 requires X86Mem');
      _emitVMX86(op, dst, src, alignment, idx);
    } else if (isArm64) {
      if (src is! A64Mem) throw ArgumentError('A64 requires A64Mem');
      _emitVMA64(op, dst, src, alignment, idx);
    } else {
      throw UnimplementedError('emitVM not implemented for $arch');
    }
  }

  /// Emit instruction with [mem, vec] operands.
  void emitMV(UniOpMV op, BaseMem dst, BaseReg src,
      {Alignment alignment = Alignment.none, int idx = 0}) {
    if (isX86Family) {
      if (dst is! X86Mem) throw ArgumentError('X86 requires X86Mem');
      _emitMVX86(op, dst, src, alignment, idx);
    } else if (isArm64) {
      if (dst is! A64Mem) throw ArgumentError('A64 requires A64Mem');
      _emitMVA64(op, dst, src, alignment, idx);
    } else {
      throw UnimplementedError('emitMV not implemented for $arch');
    }
  }

  /// Emit 2-operand vector instruction.
  void emit2v(UniOpVV op, Operand dst, Operand src) {
    if (isX86Family) {
      _emit2vX86(op, dst, src);
    } else if (isArm64) {
      _emit2vA64(op, dst, src);
    } else {
      throw UnimplementedError('emit2v not implemented for $arch');
    }
  }

  /// Emit 3-operand vector instruction.
  void emit3v(UniOpVVV op, Operand dst, Operand src1, Operand src2) {
    if (isX86Family) {
      _emit3vX86(op, dst, src1, src2);
    } else if (isArm64) {
      _emit3vA64(op, dst, src1, src2);
    } else {
      throw UnimplementedError('emit3v not implemented for $arch');
    }
  }

  /// Emit instruction with [vec, vec, imm] operands.
  void emit2vi(UniOpVVI op, Operand dst, Operand src, int imm) {
    if (isX86Family) {
      _emit2viX86(op, dst, src, imm);
    } else if (isArm64) {
      _emit2viA64(op, dst, src, imm);
    } else {
      throw UnimplementedError('emit2vi not implemented for $arch');
    }
  }

  /// Emit instruction with [vec, vec, vec, imm] operands.
  void emit3vi(UniOpVVVI op, Operand dst, Operand src1, Operand src2, int imm) {
    if (isX86Family) {
      _emit3viX86(op, dst, src1, src2, imm);
    } else if (isArm64) {
      _emit3viA64(op, dst, src1, src2, imm);
    } else {
      throw UnimplementedError('emit3vi not implemented for $arch');
    }
  }

  /// Emit instruction with 4 vector operands.
  void emit4v(
      UniOpVVVV op, Operand dst, Operand src1, Operand src2, Operand src3) {
    if (isX86Family) {
      _emit4vX86(op, dst, src1, src2, src3);
    } else if (isArm64) {
      _emit4vA64(op, dst, src1, src2, src3);
    } else {
      throw UnimplementedError('emit4v not implemented for $arch');
    }
  }

  /// Emit instruction with 5 vector operands.
  void emit5v(UniOpVVVVV op, Operand dst, Operand src1, Operand src2,
      Operand src3, Operand src4) {
    if (isX86Family) {
      _emit5vX86(op, dst, src1, src2, src3, src4);
    } else if (isArm64) {
      _emit5vA64(op, dst, src1, src2, src3, src4);
    } else {
      throw UnimplementedError('emit5v not implemented for $arch');
    }
  }

  /// Emit instruction with 9 vector operands.
  void emit9v(
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
    if (isX86Family) {
      _emit9vX86(op, dst, src1, src2, src3, src4, src5, src6, src7, src8);
    } else if (isArm64) {
      _emit9vA64(op, dst, src1, src2, src3, src4, src5, src6, src7, src8);
    } else {
      throw UnimplementedError('emit9v not implemented for $arch');
    }
  }

  // ============================================================================
  // [High-Level SIMD Operations]
  // ============================================================================

  /// Emit conditional move: dst = cond ? src : dst
  void emitCmov(UniCondition cond, BaseReg dst, Operand src) {
    if (isX86Family) {
      _emitCmovX86(cond, dst, src);
    } else if (isArm64) {
      _emitCmovA64(cond, dst, src);
    } else {
      throw UnimplementedError('emitCmov not implemented for $arch');
    }
  }

  /// Emit conditional selection: dst = cond ? src1 : src2
  void emitSelect(UniCondition cond, BaseReg dst, Operand src1, Operand src2) {
    if (isX86Family) {
      _emitSelectX86(cond, dst, src1, src2);
    } else if (isArm64) {
      _emitSelectA64(cond, dst, src1, src2);
    } else {
      throw UnimplementedError('emitSelect not implemented for $arch');
    }
  }

  // ============================================================================
  // [Constants]
  // ============================================================================

  void _initVecConstTablePtr() {
    if (_commonTablePtr == null && _ctRef != null) {
      final prev = cc.cursor;
      cc.setCursor(_funcInitHook!);
      _commonTablePtr = (cc as X86Compiler).newGpPtr("common_table_ptr");
      // Placeholder for actual address loading
      cc.addNode(InstNode(X86InstId.kMov, [_commonTablePtr!, Imm(0)]));
      _funcInitHook = cc.cursor;
      cc.setCursor(prev);
    }
  }

  BaseReg kConst(int value) {
    for (int i = 0; i < UniCompilerBase.kMaxKRegConstCount; i++) {
      if (_kReg[i] != null && _kImm[i] == value) {
        return _kReg[i]!;
      }
    }

    int slot = -1;
    for (int i = 0; i < UniCompilerBase.kMaxKRegConstCount; i++) {
      if (_kReg[i] == null) {
        slot = i;
        break;
      }
    }

    final prev = cc.cursor;
    cc.setCursor(_funcInitHook!);

    final kReg = (cc as X86Compiler)
        .newKReg("k0x${value.toRadixString(16).toUpperCase()}");

    if (value > 0xFFFFFFFF || value < 0) {
      final tmp = (cc as X86Compiler).newGp64("kTmp");
      cc.addNode(InstNode(X86InstId.kMov, [tmp, Imm(value)]));
      cc.addNode(InstNode(X86InstId.kKmovq, [kReg, tmp]));
    } else {
      final tmp = (cc as X86Compiler).newGp32("kTmp");
      cc.addNode(InstNode(X86InstId.kMov, [tmp, Imm(value)]));
      cc.addNode(InstNode(X86InstId.kKmovd, [kReg, tmp]));
    }

    _funcInitHook = cc.cursor;
    cc.setCursor(prev);

    if (slot != -1) {
      _kReg[slot] = kReg;
      _kImm[slot] = value;
    }

    return kReg;
  }

  Operand simdConst(VecConst c, Bcst bcstWidth, VecWidth constWidth) {
    for (final vc in _vecConsts) {
      if (vc.constant == c) {
        final sig = VecWidthUtils.signatureOf(constWidth);
        return BaseReg_fromSigId(sig, vc.virtRegId);
      }
    }

    if (!hasAvx512) {
      if (c != VecConstTable.p_0000000000000000) {
        return simdMemConst(c, bcstWidth, constWidth);
      }
    }

    return _newVecConst(c, bcstWidth == Bcst.kNA_Unique)
        .cloneAsWidth(constWidth);
  }

  Operand simdConstSimilarTo(VecConst c, Bcst bcstWidth, BaseReg similarTo) {
    return simdConst(c, bcstWidth, VecWidthUtils.vecWidthOf(similarTo));
  }

  BaseReg simdVecConst(VecConst c, Bcst bcstWidth, VecWidth constWidth) {
    for (final vc in _vecConsts) {
      if (vc.constant == c) {
        final sig = VecWidthUtils.signatureOf(constWidth);
        return BaseReg_fromSigId(sig, vc.virtRegId);
      }
    }
    return _newVecConst(c, bcstWidth == Bcst.kNA_Unique)
        .cloneAsWidth(constWidth);
  }

  X86Mem simdMemConst(VecConst c, Bcst bcstWidth, VecWidth constWidth) {
    final m = _getMemConst(c);
    return m;
  }

  X86Mem _getMemConst(VecConst c) {
    _initVecConstTablePtr();
    if (_commonTablePtr != null) {
      return X86Mem.base(_commonTablePtr!, disp: 0, size: c.width);
    }
    return X86Mem.abs(0, size: c.width);
  }

  BaseReg _newVecConst(VecConst c, bool isUnique) {
    final prev = cc.cursor;
    cc.setCursor(_funcInitHook!);

    final vec = newVecWithWidth(_vecWidth, "vec_const");
    _vecConsts.add(VecConstData(c, vec.id));

    if (c == VecConstTable.p_0000000000000000) {
      vZero(vec);
    } else {
      final m = _getMemConst(c);
      if (isX86Family) {
        _vLoadAX86(vec, m);
      }
    }

    _funcInitHook = cc.cursor;
    cc.setCursor(prev);

    return vec;
  }
}

/// Helper to create a register from signature and ID (Internal to UniCompiler)
BaseReg BaseReg_fromSigId(OperandSignature sig, int id) {
  // This is a bit hacky but works for the current port
  if (sig.isX86Xmm) return X86Xmm(id);
  if (sig.isX86Ymm) return X86Ymm(id);
  if (sig.isX86Zmm) return X86Zmm(id);
  throw UnimplementedError('Unsupported register signature: $sig');
}

extension BaseRegUniExt on BaseReg {
  BaseReg cloneAsWidth(VecWidth vw) {
    final sig = VecWidthUtils.signatureOf(vw);
    return BaseReg_fromSigId(sig, id);
  }
}

/// Operand array, mostly used for code generation that uses SIMD.
class OpArray {
  /// Maximum number of active operands [OpArray] can hold.
  static const int kMaxSize = 8;

  int _size = 0;
  final List<Operand> _v = List.generate(kMaxSize, (_) => NoneOperand.instance);

  OpArray() : _size = 0;

  OpArray.from1(Operand op0) : _size = 1 {
    _v[0] = op0;
  }

  OpArray.fromList(List<Operand> list) : _size = list.length {
    if (_size > kMaxSize) throw ArgumentError('OpArray size too large');
    for (int i = 0; i < _size; i++) {
      _v[i] = list[i];
    }
  }

  int get size => _size;
  bool get isEmpty => _size == 0;
  bool get isScalar => _size == 1;
  bool get isVector => _size > 1;

  Operand operator [](int index) {
    if (index >= _size) throw RangeError.index(index, _v);
    return _v[index];
  }

  OpArray lo() => _subset(0, 1, (_size + 1) ~/ 2);
  OpArray hi() => _subset(_size > 1 ? (_size + 1) ~/ 2 : 0, 1, _size);
  OpArray even() => _subset(0, 2, _size);
  OpArray odd() => _subset(_size > 1 ? 1 : 0, 2, _size);

  OpArray _subset(int from, int inc, int limit) {
    final result = OpArray();
    int di = 0;
    for (int si = from; si < limit; si += inc) {
      result._v[di++] = _v[si];
    }
    result._size = di;
    return result;
  }
}

/// Vector operand array.
class VecArray extends OpArray {
  VecArray() : super();

  VecArray.from1(BaseReg op0) : super.from1(op0);

  @override
  BaseReg operator [](int index) => super[index] as BaseReg;

  VecWidth get vecWidth => VecWidthUtils.vecWidthOf(this[0]);

  VecArray cloneAs(VecWidth vw) {
    final result = VecArray();
    result._size = _size;
    for (int i = 0; i < _size; i++) {
      result._v[i] = this[i].cloneAsWidth(vw);
    }
    return result;
  }
}
