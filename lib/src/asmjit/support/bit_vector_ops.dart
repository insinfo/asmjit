/// Bit-vector operations over arrays of bit words.
///
/// Ported from asmjit/support/support.h (`Support::bit_vector_get_bit()`,
/// `bit_vector_set_bit()`, `bit_vector_fill()`, `bit_vector_clear()`,
/// `bit_vector_index_of()`).
///
/// Upstream templates these on the bit word type `T`; the Dart port takes a
/// [BitWordType] describing it (32-bit or 64-bit words stored in a
/// `List<int>`, e.g. `Uint32List` / `Uint64List`). `Support::BitWord` is
/// `uintptr_t`, which is [BitWordType.u64] on the 64-bit hosts the port
/// targets.
library;

/// Describes the bit word `T` of a bit vector.
final class BitWordType {
  /// Number of bits of the word (`Support::bit_size_of<T>`).
  final int bitSize;

  /// All bits of the word set (`Support::bit_ones<T>`).
  final int ones;

  const BitWordType._(this.bitSize, this.ones);

  /// `uint32_t`.
  static const BitWordType u32 = BitWordType._(32, 0xFFFFFFFF);

  /// `uint64_t` (also `Support::BitWord` on 64-bit hosts).
  static const BitWordType u64 = BitWordType._(64, -1);

  /// `~x` truncated to the word size.
  int not(int x) => ~x & ones;

  /// `x << n` truncated to the word size.
  int shl(int x, int n) => n >= bitSize ? 0 : (x << n) & ones;

  /// `x >> n` (logical) of a word.
  int shr(int x, int n) => n >= bitSize ? 0 : (x & ones) >>> n;
}

/// `Support::ctz()` of a non-zero word.
int bitWordCtz(int x) {
  var n = 0;
  if ((x & 0xFFFFFFFF) == 0) {
    n += 32;
    x >>>= 32;
  }
  if ((x & 0xFFFF) == 0) {
    n += 16;
    x >>>= 16;
  }
  if ((x & 0xFF) == 0) {
    n += 8;
    x >>>= 8;
  }
  if ((x & 0xF) == 0) {
    n += 4;
    x >>>= 4;
  }
  if ((x & 0x3) == 0) {
    n += 2;
    x >>>= 2;
  }
  if ((x & 0x1) == 0) n += 1;
  return n;
}

void _bitVectorOp(
    List<int> buf, int index, int count, BitWordType t, bool fill) {
  if (count == 0) return;

  final bitSize = t.bitSize;
  var wordIndex = index ~/ bitSize; // T[]
  final bitIndex = index % bitSize; // T[][]

  // The first BitWord requires special handling to preserve bits outside the
  // fill region.
  final fillMask = t.ones;
  final firstNBits =
      (bitSize - bitIndex) < count ? (bitSize - bitIndex) : count;

  var mask = t.shl(t.shr(fillMask, bitSize - firstNBits), bitIndex);
  buf[wordIndex] = fill ? (buf[wordIndex] | mask) : (buf[wordIndex] & ~mask);
  wordIndex++;
  count -= firstNBits;

  // All bits between the first and last affected BitWords can be just filled.
  while (count >= bitSize) {
    buf[wordIndex] = fill ? fillMask : 0;
    wordIndex++;
    count -= bitSize;
  }

  // The last BitWord requires special handling as well
  if (count != 0) {
    mask = t.shr(fillMask, bitSize - count);
    buf[wordIndex] = fill ? (buf[wordIndex] | mask) : (buf[wordIndex] & ~mask);
  }
}

/// Returns bit in a bit-vector `buf` at `index`.
bool bitVectorGetBit(List<int> buf, int index,
    [BitWordType t = BitWordType.u64]) {
  final wordIndex = index ~/ t.bitSize;
  final bitIndex = index % t.bitSize;
  return ((buf[wordIndex] >>> bitIndex) & 0x1) != 0;
}

/// Sets bit in a bit-vector `buf` at `index` to `value`.
void bitVectorSetBit(List<int> buf, int index, bool value,
    [BitWordType t = BitWordType.u64]) {
  final wordIndex = index ~/ t.bitSize;
  final bitIndex = index % t.bitSize;

  final clearMask = 1 << bitIndex;
  final setMask = (value ? 1 : 0) << bitIndex;

  buf[wordIndex] = ((buf[wordIndex] & ~clearMask) | setMask) & t.ones;
}

/// Fills `count` bits in bit-vector `buf` starting at bit-index `index`.
void bitVectorFill(List<int> buf, int index, int count,
        [BitWordType t = BitWordType.u64]) =>
    _bitVectorOp(buf, index, count, t, true);

/// Clears `count` bits in bit-vector `buf` starting at bit-index `index`.
void bitVectorClear(List<int> buf, int index, int count,
        [BitWordType t = BitWordType.u64]) =>
    _bitVectorOp(buf, index, count, t, false);

/// Returns the index of the first bit equal to `value` at or after `start`.
///
/// As upstream, a bit equal to `value` must exist.
int bitVectorIndexOf(List<int> buf, int start, bool value,
    [BitWordType t = BitWordType.u64]) {
  var wordIndex = start ~/ t.bitSize; // T[]
  final bitIndex = start % t.bitSize; // T[][]

  // We always look for zeros, if value is `true` we have to flip all bits
  // before the search.
  final fillMask = t.ones;
  final flipMask = value ? 0 : fillMask;

  // The first BitWord requires special handling as there are some bits we
  // want to ignore.
  var bits =
      ((buf[wordIndex] ^ flipMask) & t.shl(fillMask, bitIndex)) & fillMask;
  for (;;) {
    if (bits != 0) return wordIndex * t.bitSize + bitWordCtz(bits);
    bits = (buf[++wordIndex] ^ flipMask) & fillMask;
  }
}
