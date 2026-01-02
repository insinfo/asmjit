/// AsmJit Condition Codes.
///
/// Ported from asmjit/core/condcode.h

/// Condition code.
///
/// A uniform condition code representation used by AsmJit.
class CondCode {
  // Constants
  static const int kEqual = 0x00;
  static const int kNotEqual = 0x01;
  static const int kSignedLT = 0x02;
  static const int kSignedGE = 0x03;
  static const int kSignedLE = 0x04;
  static const int kSignedGT = 0x05;
  static const int kUnsignedLT = 0x06;
  static const int kUnsignedGE = 0x07;
  static const int kUnsignedLE = 0x08;
  static const int kUnsignedGT = 0x09;
  static const int kOverflow = 0x0A;
  static const int kNotOverflow = 0x0B;
  static const int kSign = 0x0C;
  static const int kNotSign = 0x0D;
  static const int kParityEven = 0x0E;
  static const int kParityOdd = 0x0F;

  // Aliases
  static const int kZero = 0x00;
  static const int kNotZero = 0x01;
  static const int kNegative = 0x0C;
  static const int kPositive = 0x0D;
  static const int kCarry = 0x06;
  static const int kNotCarry = 0x07;
  static const int kBelow = 0x06;
  static const int kAboveEqual = 0x07;
  static const int kBelowEqual = 0x08;
  static const int kAbove = 0x09;
  static const int kLess = 0x02;
  static const int kGreaterEqual = 0x03;
  static const int kLessEqual = 0x04;
  static const int kGreater = 0x05;

  // Mask
  static const int kValueMask = 0x0F;

  // Bit Test (x86 specific usually, but used in UJIT)
  // These might not be standard x86 CCs, but UJIT uses them. Alternatively, they map to Carry/NotCarry.
  // In x86, BT sets CF. BT Zero means CF=0 (NotCarry). BT NonZero means CF=1 (Carry).
  // uniCondition.h: bt_z -> kBTZero, bt_nz -> kBTNotZero.
  // We will define them if UJIT uses them.
  static const int kBTZero = kNotCarry; // bit == 0 -> CF=0
  static const int kBTNotZero = kCarry; // bit == 1 -> CF=1

  final int id;
  const CondCode(this.id);

  /// Negates the condition code.
  static int negate(int cc) {
    return cc ^ 1;
  }
}
