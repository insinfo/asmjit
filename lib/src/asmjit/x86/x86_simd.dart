/// AsmJit x86 SIMD Registers
///
/// Defines XMM, YMM, and ZMM registers for SSE/AVX operations.

import '../core/operand.dart';
import '../core/reg_type.dart';

/// XMM register (128-bit SSE/AVX).
class X86Xmm extends BaseReg {
  @override
  final int id;

  const X86Xmm(this.id);

  @override
  RegType get type => RegType.vec128;

  @override
  int get size => 16; // 128 bits = 16 bytes

  @override
  RegGroup get group => RegGroup.vec;

  /// Whether this register uses the extended encoding (XMM8-XMM15).
  bool get isExtended => id >= 8;

  /// Gets the 3-bit encoding for ModR/M.
  int get encoding => id & 0x7;

  /// Returns the YMM version of this register.
  X86Ymm get ymm => X86Ymm(id);

  /// Returns the ZMM version of this register.
  X86Zmm get zmm => X86Zmm(id);

  @override
  String toString() => 'xmm$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is X86Xmm && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// YMM register (256-bit AVX).
class X86Ymm extends BaseReg {
  @override
  final int id;

  const X86Ymm(this.id);

  @override
  RegType get type => RegType.vec256;

  @override
  int get size => 32; // 256 bits = 32 bytes

  @override
  RegGroup get group => RegGroup.vec;

  /// Whether this register uses the extended encoding (YMM8-YMM15).
  bool get isExtended => id >= 8;

  /// Gets the 3-bit encoding for ModR/M.
  int get encoding => id & 0x7;

  /// Returns the XMM version of this register.
  X86Xmm get xmm => X86Xmm(id);

  /// Returns the ZMM version of this register.
  X86Zmm get zmm => X86Zmm(id);

  @override
  String toString() => 'ymm$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is X86Ymm && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// ZMM register (512-bit AVX-512).
class X86Zmm extends BaseReg {
  @override
  final int id;

  const X86Zmm(this.id);

  @override
  RegType get type => RegType.vec512;

  @override
  int get size => 64; // 512 bits = 64 bytes

  @override
  RegGroup get group => RegGroup.vec;

  /// Whether this register uses the extended encoding.
  bool get isExtended => id >= 8;

  /// Whether this register uses EVEX-only high 16 range (ZMM16-ZMM31).
  bool get isHigh16 => id >= 16;

  /// Gets the 3-bit encoding for ModR/M (low 3 bits).
  int get encoding => id & 0x7;

  /// Returns the XMM version of this register.
  X86Xmm get xmm => X86Xmm(id);

  /// Returns the YMM version of this register.
  X86Ymm get ymm => X86Ymm(id);

  @override
  String toString() => 'zmm$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is X86Zmm && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Opmask register (k0-k7) for AVX-512.
class X86KReg extends BaseReg {
  @override
  final int id;

  const X86KReg(this.id);

  @override
  RegType get type => RegType.mask;

  @override
  int get size => 8; // 64 bits (max mask size)

  @override
  RegGroup get group => RegGroup.mask;

  /// Whether this register uses the extended encoding (k8-k15).
  bool get isExtended => id >= 8;

  /// Gets the 3-bit encoding for ModR/M.
  int get encoding => id & 0x7;

  @override
  String toString() => 'k$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is X86KReg && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// =============================================================================
// Predefined XMM registers (SSE/AVX 128-bit)
// =============================================================================

const xmm0 = X86Xmm(0);
const xmm1 = X86Xmm(1);
const xmm2 = X86Xmm(2);
const xmm3 = X86Xmm(3);
const xmm4 = X86Xmm(4);
const xmm5 = X86Xmm(5);
const xmm6 = X86Xmm(6);
const xmm7 = X86Xmm(7);
const xmm8 = X86Xmm(8);
const xmm9 = X86Xmm(9);
const xmm10 = X86Xmm(10);
const xmm11 = X86Xmm(11);
const xmm12 = X86Xmm(12);
const xmm13 = X86Xmm(13);
const xmm14 = X86Xmm(14);
const xmm15 = X86Xmm(15);

// =============================================================================
// Predefined YMM registers (AVX 256-bit)
// =============================================================================

const ymm0 = X86Ymm(0);
const ymm1 = X86Ymm(1);
const ymm2 = X86Ymm(2);
const ymm3 = X86Ymm(3);
const ymm4 = X86Ymm(4);
const ymm5 = X86Ymm(5);
const ymm6 = X86Ymm(6);
const ymm7 = X86Ymm(7);
const ymm8 = X86Ymm(8);
const ymm9 = X86Ymm(9);
const ymm10 = X86Ymm(10);
const ymm11 = X86Ymm(11);
const ymm12 = X86Ymm(12);
const ymm13 = X86Ymm(13);
const ymm14 = X86Ymm(14);
const ymm15 = X86Ymm(15);

// =============================================================================
// Predefined ZMM registers (AVX-512 512-bit)
// =============================================================================

const zmm0 = X86Zmm(0);
const zmm1 = X86Zmm(1);
const zmm2 = X86Zmm(2);
const zmm3 = X86Zmm(3);
const zmm4 = X86Zmm(4);
const zmm5 = X86Zmm(5);
const zmm6 = X86Zmm(6);
const zmm7 = X86Zmm(7);
const zmm8 = X86Zmm(8);
const zmm9 = X86Zmm(9);
const zmm10 = X86Zmm(10);
const zmm11 = X86Zmm(11);
const zmm12 = X86Zmm(12);
const zmm13 = X86Zmm(13);
const zmm14 = X86Zmm(14);
const zmm15 = X86Zmm(15);

// Extended ZMM registers (AVX-512)
const zmm16 = X86Zmm(16);
const zmm17 = X86Zmm(17);
const zmm18 = X86Zmm(18);
const zmm19 = X86Zmm(19);
const zmm20 = X86Zmm(20);
const zmm21 = X86Zmm(21);
const zmm22 = X86Zmm(22);
const zmm23 = X86Zmm(23);
const zmm24 = X86Zmm(24);
const zmm25 = X86Zmm(25);
const zmm26 = X86Zmm(26);
const zmm27 = X86Zmm(27);
const zmm28 = X86Zmm(28);
const zmm29 = X86Zmm(29);
const zmm30 = X86Zmm(30);
const zmm31 = X86Zmm(31);

// =============================================================================
// Predefined Opmask registers (AVX-512)
// =============================================================================

const k0 = X86KReg(0);
const k1 = X86KReg(1);
const k2 = X86KReg(2);
const k3 = X86KReg(3);
const k4 = X86KReg(4);
const k5 = X86KReg(5);
const k6 = X86KReg(6);
const k7 = X86KReg(7);

// =============================================================================
// SSE/AVX Constants
// =============================================================================

/// Rounding modes for SSE/AVX operations.
enum RoundingMode {
  /// Round to nearest (even).
  nearest(0),

  /// Round toward negative infinity.
  down(1),

  /// Round toward positive infinity.
  up(2),

  /// Round toward zero (truncate).
  truncate(3);

  final int code;
  const RoundingMode(this.code);
}

/// Comparison predicates for SSE/AVX compare instructions.
enum CmpPredicate {
  /// Equal (ordered, non-signaling).
  eq(0),

  /// Less than (ordered, signaling).
  lt(1),

  /// Less than or equal (ordered, signaling).
  le(2),

  /// Unordered (non-signaling).
  unord(3),

  /// Not equal (unordered, non-signaling).
  neq(4),

  /// Not less than (unordered, signaling).
  nlt(5),

  /// Not less than or equal (unordered, signaling).
  nle(6),

  /// Ordered (non-signaling).
  ord(7);

  final int code;
  const CmpPredicate(this.code);
}
