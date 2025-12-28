import 'dart:typed_data';

/// Faithful port from asmjit/support/support.h.

// Support - Byte Order
// ====================

enum ByteOrder {
  kLE(0),
  kBE(1);

  final int value;
  const ByteOrder(this.value);

  static ByteOrder get kNative =>
      Endian.host == Endian.little ? ByteOrder.kLE : ByteOrder.kBE;
}

// Support - Min & Max
// ===================
// Relaxed constraints to allow int/num types which implement Comparable<num>.
T min<T extends Comparable>(T a, T b) => a.compareTo(b) < 0 ? a : b;
T max<T extends Comparable>(T a, T b) => a.compareTo(b) > 0 ? a : b;

T max3<T extends Comparable>(T a, T b, T c) => max(a, max(b, c));

// Support - Is Between
// ====================

bool isBetween<T extends Comparable>(T value, T a, T b) =>
    value.compareTo(a) >= 0 && value.compareTo(b) <= 0;

// Support - Test
// ==============

bool test(int a, int b) => (a & b) != 0;

// Support - Bit Size
// ==================

const int bitSizeOfInt8 = 8;
const int bitSizeOfInt16 = 16;
const int bitSizeOfInt32 = 32;
const int bitSizeOfInt64 = 64;

// Support - Bit Ones
// ==================

const int bitOnes = -1;

// Support - Bit Test
// ==================

bool bitTest(int value, int n) => (value & (1 << n)) != 0;

// Support - Bit Shift and Rotation
// ================================

int shl(int value, int n) => value << n;
int shr(int value, int n) => value >>> n;
int sar(int value, int n) => value >> n;

int ror(int value, int n, int bitSize) {
  return (value >>> n) | (value << (bitSize - n));
}

// Support - CLZ & CTZ
// ===================

int clz(int value) {
  if (value == 0) return 64;
  int n = 0;
  if ((value & 0xFFFFFFFF00000000) == 0) {
    n += 32;
    value <<= 32;
  }
  if ((value & 0xFFFF000000000000) == 0) {
    n += 16;
    value <<= 16;
  }
  if ((value & 0xFF00000000000000) == 0) {
    n += 8;
    value <<= 8;
  }
  if ((value & 0xF000000000000000) == 0) {
    n += 4;
    value <<= 4;
  }
  if ((value & 0xC000000000000000) == 0) {
    n += 2;
    value <<= 2;
  }
  if ((value & 0x8000000000000000) == 0) {
    n += 1;
  }
  return n;
}

int ctz(int value) {
  if (value == 0) return 64;
  int n = 0;
  if ((value & 0xFFFFFFFF) == 0) {
    n += 32;
    value >>>= 32;
  }
  if ((value & 0xFFFF) == 0) {
    n += 16;
    value >>>= 16;
  }
  if ((value & 0xFF) == 0) {
    n += 8;
    value >>>= 8;
  }
  if ((value & 0xF) == 0) {
    n += 4;
    value >>>= 4;
  }
  if ((value & 0x3) == 0) {
    n += 2;
    value >>>= 2;
  }
  if ((value & 0x1) == 0) {
    n += 1;
  }
  return n;
}

// Support - Pop Count & Has At Least 2 Bits Set
// =============================================

int popcnt(int value) {
  var v = value;
  v = v - ((v >>> 1) & 0x5555555555555555);
  v = (v & 0x3333333333333333) + ((v >>> 2) & 0x3333333333333333);
  return (((v + (v >>> 4)) & 0x0F0F0F0F0F0F0F0F) * 0x0101010101010101) >>> 56;
}

bool hasAtLeast2BitsSet(int value) {
  return (value & (value - 1)) != 0;
}

// Support - Bit Utilities
// =======================

int blsi(int value) => value & -value;

int lsbMask(int n) {
  if (n == 0) return 0;
  if (n >= 64) return -1;
  return (1 << n) - 1;
}

int msbMask(int n) {
  if (n == 0) return 0;
  if (n >= 64) return -1;
  return ~((1 << (64 - n)) - 1);
}

int bitMask(int idx) => 1 << idx;

int bitMaskMany(List<int> indices) {
  int mask = 0;
  for (final idx in indices) {
    mask |= (1 << idx);
  }
  return mask;
}

int fillTrailingBits(int value) {
  if (value == 0) return 1;
  int leadingCount = clz(value);
  return (-1 >>> leadingCount) | value;
}

// Support - Is LSB & Consecutive Mask
// ===================================

bool isLsbMask(int x) {
  return x != 0 && ((x + 1) & x) == 0;
}

bool isConsecutiveMask(int value) {
  return value != 0 && isLsbMask((value - 1) | value);
}

// Support - Is Power of 2
// =======================

bool isPowerOf2(int x) {
  return x > 0 && (x & (x - 1)) == 0;
}

bool isZeroOrPowerOf2(int x) {
  return (x & (x - 1)) == 0;
}

int bitMaskRange(int hi, int lo) {
  if (hi < lo) return 0;
  if (lo < 0 || hi < 0) return 0;
  if (hi >= 64) {
    final lowerMask = lo == 0 ? 0 : (1 << lo) - 1;
    return -1 & ~lowerMask;
  }
  final width = hi - lo + 1;
  final mask =
      width >= 64 ? -1 : ((1 << width) - 1); // width <= 64 here
  return mask << lo;
}

// Support - Is Int
// ================

bool isIntN(int x, int n) {
  if (n >= 64) return true;
  int mask = (1 << (n - 1)) - 1;
  int min = -mask - 1;
  int max = mask;
  return x >= min && x <= max;
}

bool isUintN(int x, int n) {
  if (n >= 64) return x >= 0;
  if (x < 0) return false;
  return x <= ((1 << n) - 1);
}

// Support - Alignment
// ===================

bool isAligned(int base, int alignment) {
  return (base % alignment) == 0;
}

int alignUp(int x, int alignment) {
  return (x + (alignment - 1)) & ~(alignment - 1);
}

int alignUpDiff(int x, int alignment) {
  return alignUp(x, alignment) - x;
}

int alignUpPowerOf2(int x) {
  if (x <= 1) return 1;
  return 1 << (64 - clz(x - 1));
}

// Support - BytePack
// ==================

int bytepack32_4x8(int a, int b, int c, int d) {
  return (a & 0xFF) |
      ((b & 0xFF) << 8) |
      ((c & 0xFF) << 16) |
      ((d & 0xFF) << 24);
}

bool testFlags(int value, int flags) => (value & flags) != 0;
