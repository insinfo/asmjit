/// AsmJit Code Writer
///
/// Minimal port of asmjit/core/codewriter.* that wraps a CodeHolder and
/// provides sequential byte emission.
// TODO concluir o port
import 'dart:typed_data';

import 'code_buffer.dart';
import 'code_holder.dart';
import 'fixup.dart';

class CodeWriter {
  final CodeHolder code;
  Section _section;

  CodeWriter(this.code) : _section = code.text;

  /// Current section.
  Section get section => _section;

  /// Switch to a different section.
  void setSection(Section section) {
    _section = section;
  }

  /// Current offset in the active section.
  int get offset => _section.buffer.length;

  /// Access to the active buffer.
  CodeBuffer get buffer => _section.buffer;

  /// Emits raw bytes into the active section.
  void emitBytes(List<int> bytes) => buffer.emitBytes(bytes);

  /// Emits a single byte.
  void emit8(int value) => buffer.emit8(value);

  /// Emits a 16-bit value.
  void emit16(int value) => buffer.emit16(value);

  /// Emits a 32-bit value.
  void emit32(int value) => buffer.emit32(value);

  /// Emits a 64-bit value.
  void emit64(int value) => buffer.emit64(value);

  /// Clears the active section buffer.
  void reset() => buffer.clear();
}

/// `CodeWriterUtils` (asmjit/core/codewriter.cpp): encodes offsets by an
/// [OffsetFormat]. The AArch32/Thumb formats are not ported.
abstract final class CodeWriterUtils {
  static int _lsbMask(int n) => n >= 64 ? -1 : (1 << n) - 1;

  /// `EmitterUtils::is_encodable_offset_32()`.
  static bool _isEncodableOffset32(int offset, int nBits) {
    final nRev = 32 - nBits;
    return ((offset << nRev).toSigned(32) >> nRev) == offset;
  }

  /// `EmitterUtils::is_encodable_offset_64()`.
  static bool _isEncodableOffset64(int offset, int nBits) {
    final nRev = 64 - nBits;
    return ((offset << nRev) >> nRev) == offset;
  }

  /// Encodes [offset64] by [format] into a 32-bit mask, or null when it is
  /// not encodable (`encode_offset32`).
  static int? encodeOffset32(int offset64, OffsetFormat format) {
    final bitCount = format.immBitCount();
    final bitShift = format.immBitShift();
    final discardLsb = format.immDiscardLsb();

    // Invalid offset (should not happen).
    if (bitCount == 0 || bitCount > format.valueSize() * 8) return null;

    int value;
    if (format.type() == OffsetType.kUnsignedOffset) {
      if (discardLsb != 0) {
        assert(discardLsb <= 32);
        if ((offset64 & _lsbMask(discardLsb)) != 0) return null;
        offset64 = offset64 >>> discardLsb;
      }
      value = offset64 & _lsbMask(bitCount) & 0xFFFFFFFF;
      if (value != offset64) return null;
    } else {
      // The rest of OffsetType options are all signed.
      if (discardLsb != 0) {
        assert(discardLsb <= 32);
        if ((offset64 & _lsbMask(discardLsb)) != 0) return null;
        offset64 >>= discardLsb;
      }
      if (offset64 != offset64.toSigned(32)) return null;
      value = offset64.toSigned(32);
      if (!_isEncodableOffset32(value, bitCount)) return null;
      value &= 0xFFFFFFFF;
    }

    switch (format.type()) {
      case OffsetType.kSignedOffset:
      case OffsetType.kUnsignedOffset:
        return ((value & _lsbMask(bitCount)) << bitShift) & 0xFFFFFFFF;
      case OffsetType.kAArch64_ADR:
      case OffsetType.kAArch64_ADRP:
        // Sanity checks.
        if (format.valueSize() != 4 || bitCount != 21 || bitShift != 5) {
          return null;
        }
        final immLo = value & 0x3;
        final immHi = (value >>> 2) & _lsbMask(19);
        return (immLo << 29) | (immHi << 5);
      default:
        return null;
    }
  }

  /// Encodes [offset64] by [format] into a 64-bit mask, or null when it is
  /// not encodable (`encode_offset64`).
  static int? encodeOffset64(int offset64, OffsetFormat format) {
    final bitCount = format.immBitCount();
    final discardLsb = format.immDiscardLsb();

    if (bitCount == 0 || bitCount > format.valueSize() * 8) return null;

    int value;
    if (format.type() == OffsetType.kUnsignedOffset) {
      if (discardLsb != 0) {
        assert(discardLsb <= 32);
        if ((offset64 & _lsbMask(discardLsb)) != 0) return null;
        offset64 = offset64 >>> discardLsb;
      }
      value = offset64 & _lsbMask(bitCount);
      if (value != offset64) return null;
    } else {
      if (discardLsb != 0) {
        assert(discardLsb <= 32);
        if ((offset64 & _lsbMask(discardLsb)) != 0) return null;
        offset64 >>= discardLsb;
      }
      if (!_isEncodableOffset64(offset64, bitCount)) return null;
      value = offset64;
    }

    switch (format.type()) {
      case OffsetType.kSignedOffset:
      case OffsetType.kUnsignedOffset:
        return (value & _lsbMask(bitCount)) << format.immBitShift();
      default:
        return null;
    }
  }

  /// ORs [offset64] encoded by [format] into the region of [buffer] that
  /// starts at [at] (`write_offset`). Returns false if not encodable.
  static bool writeOffset(
      CodeBuffer buffer, int at, int offset64, OffsetFormat format) {
    // Offset the destination by ValueOffset so it points to the patched
    // word instead of the beginning of the patched region.
    at += format.valueOffset();

    switch (format.valueSize()) {
      case 1:
        final mask = encodeOffset32(offset64, format);
        if (mask == null) return false;
        buffer.patch8(at, buffer[at] | mask);
        return true;
      case 2:
        final mask = encodeOffset32(offset64, format);
        if (mask == null) return false;
        buffer.patch16(at, buffer.byteData.getUint16(at, Endian.little) | mask);
        return true;
      case 4:
        final mask = encodeOffset32(offset64, format);
        if (mask == null) return false;
        buffer.write32At(at, buffer.read32At(at) | mask);
        return true;
      case 8:
        final mask = encodeOffset64(offset64, format);
        if (mask == null) return false;
        buffer.patch64(at, buffer.byteData.getUint64(at, Endian.little) | mask);
        return true;
      default:
        return false;
    }
  }
}
