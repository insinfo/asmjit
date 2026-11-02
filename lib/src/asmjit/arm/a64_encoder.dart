/// AArch64 immediate encoding helpers.
///
/// The instructions themselves are encoded by `A64Emitter` (a64_emit.dart,
/// the port of `a64::Assembler::_emit()`); these are the immediate encoders
/// it shares with the UJIT compiler.
library;

/// Logical (bitmask) immediates and MOVZ/MOVN/MOVK sequences
/// (upstream `encode_logical_imm()` and `encode_mov_sequence_{32,64}()`).
abstract final class A64Encoder {
  /// Encodes [value] as a logical (bitmask) immediate of a [width]-bit
  /// operation: returns `N:immr:imms` (13 bits), or null when the value is
  /// not a rotated run of ones repeated in 2/4/8/16/32/64-bit elements.
  static int? encodeLogicalImm(int value, int width) {
    if (width == 32) value &= 0xFFFFFFFF;
    final mask = width == 64 ? -1 : 0xFFFFFFFF;
    if (value == 0 || value == mask) return null;
    // Smallest element size the value repeats with.
    var size = width;
    while (size > 2) {
      final half = size ~/ 2;
      final m = (1 << half) - 1;
      if ((value & m) != ((value >>> half) & m)) break;
      size = half;
    }
    final emask = size == 64 ? -1 : (1 << size) - 1;
    final elt = value & emask;
    // Rotate right until the run of ones starts at bit 0.
    var rot = 0;
    var e = elt;
    int rotr(int v, int n) =>
        n == 0 ? v : (((v >>> n) | (v << (size - n))) & emask);
    while (rot < size) {
      e = rotr(elt, rot);
      // A contiguous run from bit 0: e + 1 is a power of two (no wrap).
      if ((e & 1) == 1 && ((e + 1) & e) == 0) break;
      rot++;
    }
    if (rot == size) return null;
    final ones = e.bitLength;
    if (ones >= size) return null;
    final immr = (size - rot) % size;
    final n = size == 64 ? 1 : 0;
    final imms = ((~(size * 2 - 1)) & 0x3F) | (ones - 1);
    return (n << 12) | (immr << 6) | (imms & 0x3F);
  }

  static int _countZeroHalfWords64(int imm) =>
      ((imm & 0xFFFF) == 0 ? 1 : 0) +
      ((imm & 0xFFFF0000) == 0 ? 1 : 0) +
      ((imm & 0xFFFF00000000) == 0 ? 1 : 0) +
      ((imm & -0x1000000000000) == 0 ? 1 : 0);

  /// `encode_mov_sequence_32()`.
  static List<int> encodeMovSequence32(int imm, int rd, int x) {
    final kMovZ = 0x52800000 | (x << 31);
    const kMovN = 0x12800000;
    const kMovK = 0x72800000;
    imm &= 0xFFFFFFFF;

    if ((imm & 0xFFFF0000) == 0) {
      return [kMovZ | ((imm & 0xFFFF) << 5) | rd];
    }
    if ((imm & 0xFFFF0000) == 0xFFFF0000) {
      return [kMovN | ((~imm & 0xFFFF) << 5) | rd];
    }
    if ((imm & 0xFFFF) == 0) {
      return [kMovZ | (1 << 21) | ((imm >> 16) << 5) | rd];
    }
    if ((imm & 0xFFFF) == 0xFFFF) {
      return [kMovN | (1 << 21) | (((~imm >> 16) & 0xFFFF) << 5) | rd];
    }
    return [
      kMovZ | ((imm & 0xFFFF) << 5) | rd,
      kMovK | (1 << 21) | ((imm >> 16) << 5) | rd,
    ];
  }

  /// `encode_mov_sequence_64()`.
  static List<int> encodeMovSequence64(int imm, int rd, int x) {
    const kMovZ = 0xD2800000;
    const kMovN = 0x92800000;
    const kMovK = 0xF2800000;

    if (imm >= 0 && imm <= 0xFFFFFFFF) return encodeMovSequence32(imm, rd, x);

    final zhw = _countZeroHalfWords64(imm);
    final ohw = _countZeroHalfWords64(~imm);
    final out = <int>[];

    if (zhw >= ohw) {
      var op = kMovZ;
      for (var hw = 0; hw < 4; hw++, imm >>>= 16) {
        final hwImm = imm & 0xFFFF;
        if (hwImm == 0) continue;
        out.add(op | (hw << 21) | (hwImm << 5) | rd);
        op = kMovK;
      }
    } else {
      var op = kMovN;
      var negMask = 0xFFFF;
      for (var hw = 0; hw < 4; hw++, imm >>>= 16) {
        final hwImm = imm & 0xFFFF;
        if (hwImm == 0xFFFF) continue;
        out.add(op | (hw << 21) | ((hwImm ^ negMask) << 5) | rd);
        op = kMovK;
        negMask = 0;
      }
      if (out.isEmpty) out.add(kMovN | ((0xFFFF ^ negMask) << 5) | rd);
    }
    return out;
  }
}
