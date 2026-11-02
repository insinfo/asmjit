/// AsmJit offset formats.
///
/// Ported from asmjit/core/fixup.h (`OffsetType`, `OffsetFormat`). The
/// AArch32/Thumb offset types are not ported: the port has no 32-bit ARM
/// backend.
library;

/// Offset format type, used by [OffsetFormat] (`OffsetType`).
abstract final class OffsetType {
  /// A value having `immBitCount` bits and shifted by `immBitShift`.
  static const int kSignedOffset = 0;

  /// An unsigned value having `immBitCount` bits and shifted by
  /// `immBitShift`.
  static const int kUnsignedOffset = 1;

  /// AArch64 ADR format of `[.|immlo:2|.....|immhi:19|.....]`.
  static const int kAArch64_ADR = 2;

  /// AArch64 ADRP format of `[.|immlo:2|.....|immhi:19|.....]` (4kB pages).
  static const int kAArch64_ADRP = 3;
}

/// Provides information about formatting offsets, absolute addresses, or
/// their parts; used by `RelocEntry` and label fixups (`OffsetFormat`).
///
/// The region is the whole unit (usually an instruction) and the value is
/// the word inside it that is patched, at [valueOffset].
final class OffsetFormat {
  int _type = OffsetType.kSignedOffset;
  int _flags = 0;
  int _regionSize = 0;
  int _valueSize = 0;
  int _valueOffset = 0;
  int _immBitCount = 0;
  int _immBitShift = 0;
  int _immDiscardLsb = 0;

  /// Type of the offset ([OffsetType]).
  int type() => _type;

  /// Encoding flags.
  int flags() => _flags;

  /// Size of the region (instruction) where the offset is encoded.
  int regionSize() => _regionSize;

  /// Offset of the patched word relative to the start of the region.
  int valueOffset() => _valueOffset;

  /// Size of the patched word, in bytes (1, 2, 4, or 8).
  int valueSize() => _valueSize;

  /// Count of bits of the offset value in the patched word.
  int immBitCount() => _immBitCount;

  /// Bit-shift of the offset value in the patched word.
  int immBitShift() => _immBitShift;

  /// Number of least significant bits that must be zero and are not encoded.
  int immDiscardLsb() => _immDiscardLsb;

  /// Resets this offset format to a simple data value of [valueSize] bytes.
  void resetToSimpleValue(int type, int valueSize) {
    assert(valueSize <= 8);
    _type = type;
    _flags = 0;
    _regionSize = valueSize;
    _valueSize = valueSize;
    _valueOffset = 0;
    _immBitCount = valueSize * 8;
    _immBitShift = 0;
    _immDiscardLsb = 0;
  }

  void resetToImmValue(int type, int valueSize, int immBitShift,
      int immBitCount, int immDiscardLsb) {
    assert(valueSize <= 8);
    assert(immBitShift < valueSize * 8);
    assert(immBitCount <= 64);
    assert(immDiscardLsb <= 64);
    _type = type;
    _flags = 0;
    _regionSize = valueSize;
    _valueSize = valueSize;
    _valueOffset = 0;
    _immBitCount = immBitCount;
    _immBitShift = immBitShift;
    _immDiscardLsb = immDiscardLsb;
  }

  /// Sets the number of discarded least significant bits (upstream writes
  /// `_imm_discard_lsb` directly).
  void setImmDiscardLsb(int immDiscardLsb) => _immDiscardLsb = immDiscardLsb;

  void setRegion(int regionSize, int valueOffset) {
    _regionSize = regionSize;
    _valueOffset = valueOffset;
  }

  void setLeadingAndTrailingSize(int leadingSize, int trailingSize) {
    _regionSize = leadingSize + trailingSize + _valueSize;
    _valueOffset = leadingSize;
  }

  /// A copy of this format.
  OffsetFormat copy() => OffsetFormat()
    .._type = _type
    .._flags = _flags
    .._regionSize = _regionSize
    .._valueSize = _valueSize
    .._valueOffset = _valueOffset
    .._immBitCount = _immBitCount
    .._immBitShift = _immBitShift
    .._immDiscardLsb = _immDiscardLsb;
}
