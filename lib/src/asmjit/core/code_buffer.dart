/// AsmJit Code Buffer
///
/// A growable buffer for emitting machine code bytes.
/// Ported from asmjit/core/codebuffer.h

import 'dart:typed_data';

/// A buffer for emitting machine code.
///
/// Provides efficient methods for writing bytes, integers,
/// and other data in the correct endianness.
class CodeBuffer {
  Uint8List _data;
  int _length = 0;

  /// Creates a new code buffer.
  ///
  /// [initialCapacity] is the initial size of the internal buffer.
  CodeBuffer([int initialCapacity = 256]) : _data = Uint8List(initialCapacity);

  /// The current length of the buffer (bytes written).
  int get length => _length;

  /// Whether the buffer is empty.
  bool get isEmpty => _length == 0;

  /// Whether the buffer is not empty.
  bool get isNotEmpty => _length > 0;

  /// The current capacity of the internal buffer.
  int get capacity => _data.length;

  /// Returns the current offset (same as length).
  int get offset => _length;

  /// Returns the buffer contents as a [Uint8List].
  ///
  /// This creates a view of the used portion of the buffer.
  Uint8List get bytes => Uint8List.sublistView(_data, 0, _length);

  /// Gets a byte data view of the buffer for reading.
  ByteData get byteData => ByteData.sublistView(_data, 0, _length);

  /// Clears the buffer.
  void clear() {
    _length = 0;
  }

  /// Resets the buffer, optionally keeping capacity.
  void reset({bool keepCapacity = true}) {
    _length = 0;
    if (!keepCapacity) {
      _data = Uint8List(256);
    }
  }

  /// Ensures there is room for [extra] more bytes.
  void _ensure(int extra) {
    final needed = _length + extra;
    if (needed <= _data.length) return;

    // Grow the buffer
    var newCapacity = _data.length;
    while (newCapacity < needed) {
      newCapacity = newCapacity < 1024 ? newCapacity * 2 : newCapacity + 1024;
    }

    final newData = Uint8List(newCapacity);
    newData.setRange(0, _length, _data);
    _data = newData;
  }

  /// Emits a single byte.
  void emit8(int value) {
    _ensure(1);
    _data[_length++] = value & 0xFF;
  }

  /// Alias for [emit8].
  void emitByte(int value) => emit8(value);

  /// Emits a 16-bit value (little-endian).
  void emit16(int value) {
    _ensure(2);
    _data[_length++] = value & 0xFF;
    _data[_length++] = (value >> 8) & 0xFF;
  }

  /// Alias for [emit16].
  void emitWord(int value) => emit16(value);

  /// Emits a 32-bit value (little-endian).
  void emit32(int value) {
    _ensure(4);
    _data[_length++] = value & 0xFF;
    _data[_length++] = (value >> 8) & 0xFF;
    _data[_length++] = (value >> 16) & 0xFF;
    _data[_length++] = (value >> 24) & 0xFF;
  }

  /// Alias for [emit32].
  void emitDWord(int value) => emit32(value);

  /// Alias for [emit32].
  void emitI32(int value) => emit32(value);

  /// Alias for [emit32].
  void emitU32(int value) => emit32(value);

  /// Emits a 64-bit value (little-endian).
  void emit64(int value) {
    _ensure(8);
    var v = value;
    for (int i = 0; i < 8; i++) {
      _data[_length++] = v & 0xFF;
      v >>= 8;
    }
  }

  /// Alias for [emit64].
  void emitQWord(int value) => emit64(value);

  /// Alias for [emit64].
  void emitI64(int value) => emit64(value);

  /// Alias for [emit64].
  void emitU64(int value) => emit64(value);

  /// Emits a list of bytes.
  void emitBytes(List<int> data) {
    _ensure(data.length);
    for (final b in data) {
      _data[_length++] = b & 0xFF;
    }
  }

  /// Emits data from a Uint8List.
  void emitData(Uint8List data) {
    _ensure(data.length);
    _data.setRange(_length, _length + data.length, data);
    _length += data.length;
  }

  /// Emits zeros (for padding or initialization).
  void emitZeros(int count) {
    _ensure(count);
    for (int i = 0; i < count; i++) {
      _data[_length++] = 0;
    }
  }

  /// Emits a fill byte pattern.
  void emitFill(int count, int value) {
    _ensure(count);
    final byte = value & 0xFF;
    for (int i = 0; i < count; i++) {
      _data[_length++] = byte;
    }
  }

  /// Aligns the buffer to [alignment] bytes, filling with [fill].
  ///
  /// [alignment] must be a power of 2.
  /// Returns the number of bytes added.
  int align(int alignment, [int fill = 0x00]) {
    final mask = alignment - 1;
    final padding = (alignment - (_length & mask)) & mask;
    if (padding > 0) {
      emitFill(padding, fill);
    }
    return padding;
  }

  /// Aligns to [alignment] with NOP instructions (0x90 for x86).
  int alignWithNops(int alignment) => align(alignment, 0x90);

  /// Patches a byte at [offset].
  void patch8(int offset, int value) {
    if (offset < 0 || offset >= _length) {
      throw RangeError.range(offset, 0, _length - 1, 'offset');
    }
    _data[offset] = value & 0xFF;
  }

  /// Patches a 16-bit value at [offset] (little-endian).
  void patch16(int offset, int value) {
    if (offset < 0 || offset + 2 > _length) {
      throw RangeError.range(offset, 0, _length - 2, 'offset');
    }
    _data[offset] = value & 0xFF;
    _data[offset + 1] = (value >> 8) & 0xFF;
  }

  /// Patches a 32-bit value at [offset] (little-endian).
  void patch32(int offset, int value) {
    if (offset < 0 || offset + 4 > _length) {
      throw RangeError.range(offset, 0, _length - 4, 'offset');
    }
    _data[offset] = value & 0xFF;
    _data[offset + 1] = (value >> 8) & 0xFF;
    _data[offset + 2] = (value >> 16) & 0xFF;
    _data[offset + 3] = (value >> 24) & 0xFF;
  }

  /// Alias for [patch32].
  void patchI32(int offset, int value) => patch32(offset, value);

  /// Patches a 64-bit value at [offset] (little-endian).
  void patch64(int offset, int value) {
    if (offset < 0 || offset + 8 > _length) {
      throw RangeError.range(offset, 0, _length - 8, 'offset');
    }
    var v = value;
    for (int i = 0; i < 8; i++) {
      _data[offset + i] = v & 0xFF;
      v >>= 8;
    }
  }

  /// Reserves space for [count] bytes, returning the starting offset.
  ///
  /// The bytes are initialized to zero.
  int reserve(int count) {
    final startOffset = _length;
    emitZeros(count);
    return startOffset;
  }

  /// Gets a byte at [offset].
  int operator [](int offset) {
    if (offset < 0 || offset >= _length) {
      throw RangeError.range(offset, 0, _length - 1, 'offset');
    }
    return _data[offset];
  }

  /// Sets a byte at [offset].
  void operator []=(int offset, int value) {
    if (offset < 0 || offset >= _length) {
      throw RangeError.range(offset, 0, _length - 1, 'offset');
    }
    _data[offset] = value & 0xFF;
  }

  /// Reads a 32-bit value at [offset] (little-endian).
  int read32At(int offset) {
    if (offset < 0 || offset + 4 > _length) {
      throw RangeError.range(offset, 0, _length - 4, 'offset');
    }
    return _data[offset] |
        (_data[offset + 1] << 8) |
        (_data[offset + 2] << 16) |
        (_data[offset + 3] << 24);
  }

  /// Writes a 32-bit value at [offset] (little-endian).
  /// Alias for patch32.
  void write32At(int offset, int value) => patch32(offset, value);

  @override
  String toString() =>
      'CodeBuffer(length: $_length, capacity: ${_data.length})';
}
