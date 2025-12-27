/// AsmJit Type System
///
/// Port of asmjit/core/type.h - provides type identifiers for registers,
/// function arguments, and SIMD vectors.

/// Type identifier that provides a minimalist type system for AsmJit.
///
/// Used to describe value types of physical or virtual registers,
/// and for function signature descriptions.
enum TypeId {
  /// Void type.
  void_(0),

  /// Abstract signed integer with native size.
  intPtr(32),

  /// Abstract unsigned integer with native size.
  uintPtr(33),

  /// 8-bit signed integer.
  int8(34),

  /// 8-bit unsigned integer.
  uint8(35),

  /// 16-bit signed integer.
  int16(36),

  /// 16-bit unsigned integer.
  uint16(37),

  /// 32-bit signed integer.
  int32(38),

  /// 32-bit unsigned integer.
  uint32(39),

  /// 64-bit signed integer.
  int64(40),

  /// 64-bit unsigned integer.
  uint64(41),

  /// 32-bit floating point.
  float32(42),

  /// 64-bit floating point.
  float64(43),

  /// 80-bit floating point (x87).
  float80(44),

  /// 8-bit mask register (K).
  mask8(45),

  /// 16-bit mask register (K).
  mask16(46),

  /// 32-bit mask register (K).
  mask32(47),

  /// 64-bit mask register (K).
  mask64(48),

  /// 64-bit MMX register (32-bit usage).
  mmx32(49),

  /// 64-bit MMX register.
  mmx64(50),

  // 32-bit vectors
  /// int8x4 packed.
  int8x4(51),
  uint8x4(52),
  int16x2(53),
  uint16x2(54),
  int32x1(55),
  uint32x1(56),
  float32x1(59),

  // 64-bit vectors
  int8x8(61),
  uint8x8(62),
  int16x4(63),
  uint16x4(64),
  int32x2(65),
  uint32x2(66),
  int64x1(67),
  uint64x1(68),
  float32x2(69),
  float64x1(70),

  // 128-bit vectors (SSE/XMM)
  int8x16(71),
  uint8x16(72),
  int16x8(73),
  uint16x8(74),
  int32x4(75),
  uint32x4(76),
  int64x2(77),
  uint64x2(78),
  float32x4(79),
  float64x2(80),

  // 256-bit vectors (AVX/YMM)
  int8x32(81),
  uint8x32(82),
  int16x16(83),
  uint16x16(84),
  int32x8(85),
  uint32x8(86),
  int64x4(87),
  uint64x4(88),
  float32x8(89),
  float64x4(90),

  // 512-bit vectors (AVX-512/ZMM)
  int8x64(91),
  uint8x64(92),
  int16x32(93),
  uint16x32(94),
  int32x16(95),
  uint32x16(96),
  int64x8(97),
  uint64x8(98),
  float32x16(99),
  float64x8(100);

  /// Numeric value of the type id.
  final int value;

  const TypeId(this.value);

  // Range constants
  static const int _baseStart = 32;
  static const int _baseEnd = 44;
  static const int _intStart = 32;
  static const int _intEnd = 41;
  static const int _floatStart = 42;
  static const int _floatEnd = 44;
  static const int _maskStart = 45;
  static const int _maskEnd = 48;
  static const int _mmxStart = 49;
  static const int _mmxEnd = 50;
  static const int _vec32Start = 51;
  static const int _vec32End = 60;
  static const int _vec64Start = 61;
  static const int _vec64End = 70;
  static const int _vec128Start = 71;
  static const int _vec128End = 80;
  static const int _vec256Start = 81;
  static const int _vec256End = 90;
  static const int _vec512Start = 91;
  static const int _vec512End = 100;
}

/// Type utilities for TypeId.
extension TypeUtils on TypeId {
  /// Size in bytes for each type.
  int get sizeInBytes => _typeSizes[value] ?? 0;

  /// Check if this is void.
  bool get isVoid => this == TypeId.void_;

  /// Check if this is a valid non-void type.
  bool get isValid => value >= TypeId._intStart && value <= TypeId._vec512End;

  /// Check if this is a scalar type (not vector).
  bool get isScalar => value >= TypeId._baseStart && value <= TypeId._baseEnd;

  /// Check if this is abstract (intPtr/uintPtr).
  bool get isAbstract => this == TypeId.intPtr || this == TypeId.uintPtr;

  /// Check if this is any integer type.
  bool get isInt => value >= TypeId._intStart && value <= TypeId._intEnd;

  /// Check if this is any float type.
  bool get isFloat => value >= TypeId._floatStart && value <= TypeId._floatEnd;

  /// Check if this is a mask register type.
  bool get isMask => value >= TypeId._maskStart && value <= TypeId._maskEnd;

  /// Check if this is an MMX type.
  bool get isMmx => value >= TypeId._mmxStart && value <= TypeId._mmxEnd;

  /// Check if this is any vector type.
  bool get isVec => value >= TypeId._vec32Start && value <= TypeId._vec512End;

  /// Check if this is a 32-bit vector.
  bool get isVec32 => value >= TypeId._vec32Start && value <= TypeId._vec32End;

  /// Check if this is a 64-bit vector.
  bool get isVec64 => value >= TypeId._vec64Start && value <= TypeId._vec64End;

  /// Check if this is a 128-bit vector (XMM).
  bool get isVec128 =>
      value >= TypeId._vec128Start && value <= TypeId._vec128End;

  /// Check if this is a 256-bit vector (YMM).
  bool get isVec256 =>
      value >= TypeId._vec256Start && value <= TypeId._vec256End;

  /// Check if this is a 512-bit vector (ZMM).
  bool get isVec512 =>
      value >= TypeId._vec512Start && value <= TypeId._vec512End;

  /// Check if this is a signed integer.
  bool get isSigned {
    return this == TypeId.int8 ||
        this == TypeId.int16 ||
        this == TypeId.int32 ||
        this == TypeId.int64 ||
        this == TypeId.intPtr;
  }

  /// Check if this is an unsigned integer.
  bool get isUnsigned {
    return this == TypeId.uint8 ||
        this == TypeId.uint16 ||
        this == TypeId.uint32 ||
        this == TypeId.uint64 ||
        this == TypeId.uintPtr;
  }

  /// Get the scalar type for a vector type.
  TypeId get scalarType => _scalarTypes[value] ?? TypeId.void_;

  /// Deabstract this type to a concrete type based on register size.
  TypeId deabstract(int registerSizeBytes) {
    if (!isAbstract) return this;
    if (registerSizeBytes >= 8) {
      return this == TypeId.intPtr ? TypeId.int64 : TypeId.uint64;
    } else {
      return this == TypeId.intPtr ? TypeId.int32 : TypeId.uint32;
    }
  }
}

/// Size lookup table.
const Map<int, int> _typeSizes = {
  0: 0, // void
  32: 0, // intPtr (abstract)
  33: 0, // uintPtr (abstract)
  34: 1, // int8
  35: 1, // uint8
  36: 2, // int16
  37: 2, // uint16
  38: 4, // int32
  39: 4, // uint32
  40: 8, // int64
  41: 8, // uint64
  42: 4, // float32
  43: 8, // float64
  44: 10, // float80
  45: 1, // mask8
  46: 2, // mask16
  47: 4, // mask32
  48: 8, // mask64
  49: 8, // mmx32
  50: 8, // mmx64
  // 32-bit vectors
  51: 4, 52: 4, 53: 4, 54: 4, 55: 4, 56: 4, 59: 4,
  // 64-bit vectors
  61: 8, 62: 8, 63: 8, 64: 8, 65: 8, 66: 8, 67: 8, 68: 8, 69: 8, 70: 8,
  // 128-bit vectors
  71: 16, 72: 16, 73: 16, 74: 16, 75: 16, 76: 16, 77: 16, 78: 16, 79: 16,
  80: 16,
  // 256-bit vectors
  81: 32, 82: 32, 83: 32, 84: 32, 85: 32, 86: 32, 87: 32, 88: 32, 89: 32,
  90: 32,
  // 512-bit vectors
  91: 64, 92: 64, 93: 64, 94: 64, 95: 64, 96: 64, 97: 64, 98: 64, 99: 64,
  100: 64,
};

/// Scalar type lookup table.
const Map<int, TypeId> _scalarTypes = {
  // Scalars map to themselves
  34: TypeId.int8,
  35: TypeId.uint8,
  36: TypeId.int16,
  37: TypeId.uint16,
  38: TypeId.int32,
  39: TypeId.uint32,
  40: TypeId.int64,
  41: TypeId.uint64,
  42: TypeId.float32,
  43: TypeId.float64,
  44: TypeId.float80,

  // 32-bit vectors
  51: TypeId.int8, 52: TypeId.uint8,
  53: TypeId.int16, 54: TypeId.uint16,
  55: TypeId.int32, 56: TypeId.uint32,
  59: TypeId.float32,

  // 64-bit vectors
  61: TypeId.int8, 62: TypeId.uint8,
  63: TypeId.int16, 64: TypeId.uint16,
  65: TypeId.int32, 66: TypeId.uint32,
  67: TypeId.int64, 68: TypeId.uint64,
  69: TypeId.float32, 70: TypeId.float64,

  // 128-bit vectors
  71: TypeId.int8, 72: TypeId.uint8,
  73: TypeId.int16, 74: TypeId.uint16,
  75: TypeId.int32, 76: TypeId.uint32,
  77: TypeId.int64, 78: TypeId.uint64,
  79: TypeId.float32, 80: TypeId.float64,

  // 256-bit vectors
  81: TypeId.int8, 82: TypeId.uint8,
  83: TypeId.int16, 84: TypeId.uint16,
  85: TypeId.int32, 86: TypeId.uint32,
  87: TypeId.int64, 88: TypeId.uint64,
  89: TypeId.float32, 90: TypeId.float64,

  // 512-bit vectors
  91: TypeId.int8, 92: TypeId.uint8,
  93: TypeId.int16, 94: TypeId.uint16,
  95: TypeId.int32, 96: TypeId.uint32,
  97: TypeId.int64, 98: TypeId.uint64,
  99: TypeId.float32, 100: TypeId.float64,
};

/// Helper to get TypeId from Dart runtime types.
TypeId typeIdFromDart<T>() {
  if (T == int) return TypeId.int64;
  if (T == double) return TypeId.float64;
  if (T == bool) return TypeId.uint8;
  return TypeId.void_;
}

/// Helper to get the element count in a vector type.
int vectorElementCount(TypeId typeId) {
  if (!typeId.isVec) return 1;
  final size = typeId.sizeInBytes;
  final scalar = typeId.scalarType;
  final scalarSize = scalar.sizeInBytes;
  if (scalarSize == 0) return 0;
  return size ~/ scalarSize;
}
