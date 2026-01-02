/// AsmJit Constant Pool
///
/// Manages constant data that needs to be embedded in the code section.
/// Provides RIP-relative access to constants on x86-64.

import 'dart:typed_data';

import 'labels.dart';
import 'code_buffer.dart';

/// Alignment for constant pool entries.
enum ConstPoolAlign {
  byte(1),
  word(2),
  dword(4),
  qword(8),
  xmm(16),
  ymm(32),
  zmm(64);

  final int bytes;
  const ConstPoolAlign(this.bytes);
}

/// A reference to a constant in the pool.
class ConstRef {
  /// The label pointing to this constant.
  final Label label;

  /// The size of the constant in bytes.
  final int size;

  /// The alignment of the constant.
  final ConstPoolAlign align;

  const ConstRef({
    required this.label,
    required this.size,
    required this.align,
  });
}

/// Constant Pool Entry.
class _ConstEntry {
  final Uint8List data;
  final Label label;
  final ConstPoolAlign align;
  int? offset; // Set when pool is finalized

  _ConstEntry({
    required this.data,
    required this.label,
    required this.align,
  });

  int get size => data.length;
}

/// Manages a pool of constants for embedding in code.
///
/// Constants are emitted at the end of the code section after
/// all instructions have been generated. Labels are used to
/// reference constants via RIP-relative addressing.
class ConstPool {
  final LabelManager labelManager;
  final List<_ConstEntry> _entries = [];

  ConstPool(this.labelManager);

  /// Number of constants in the pool.
  int get length => _entries.length;

  /// Whether the pool is empty.
  bool get isEmpty => _entries.isEmpty;

  /// Whether the pool has constants.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// Adds a 32-bit signed integer constant.
  ConstRef addInt32(int value) {
    final data = Uint8List(4);
    final view = ByteData.view(data.buffer);
    view.setInt32(0, value, Endian.little);
    return _add(data, ConstPoolAlign.dword);
  }

  /// Adds a 64-bit signed integer constant.
  ConstRef addInt64(int value) {
    final data = Uint8List(8);
    final view = ByteData.view(data.buffer);
    view.setInt64(0, value, Endian.little);
    return _add(data, ConstPoolAlign.qword);
  }

  /// Adds a 32-bit floating-point constant.
  ConstRef addFloat32(double value) {
    final data = Uint8List(4);
    final view = ByteData.view(data.buffer);
    view.setFloat32(0, value, Endian.little);
    return _add(data, ConstPoolAlign.dword);
  }

  /// Adds a 64-bit floating-point constant.
  ConstRef addFloat64(double value) {
    final data = Uint8List(8);
    final view = ByteData.view(data.buffer);
    view.setFloat64(0, value, Endian.little);
    return _add(data, ConstPoolAlign.qword);
  }

  /// Adds raw bytes with specified alignment.
  ConstRef addBytes(Uint8List bytes,
      {ConstPoolAlign align = ConstPoolAlign.byte}) {
    return _add(Uint8List.fromList(bytes), align);
  }

  /// Adds a 128-bit value (for XMM constants).
  ConstRef addXmm(Uint8List bytes) {
    if (bytes.length != 16) {
      throw ArgumentError('XMM constant must be exactly 16 bytes');
    }
    return _add(Uint8List.fromList(bytes), ConstPoolAlign.xmm);
  }

  /// Internal add method.
  ConstRef _add(Uint8List data, ConstPoolAlign align) {
    // Check for duplicate constants (deduplication)
    for (final entry in _entries) {
      if (entry.align == align && _bytesEqual(entry.data, data)) {
        return ConstRef(
            label: entry.label, size: entry.size, align: entry.align);
      }
    }

    final label = labelManager.newLabel();
    final entry = _ConstEntry(data: data, label: label, align: align);
    _entries.add(entry);

    return ConstRef(label: label, size: data.length, align: align);
  }

  /// Checks if two byte arrays are equal.
  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Emits the constant pool to the code buffer.
  ///
  /// Returns a map of label ID to offset for fixup resolution.
  /// The pool should be emitted after all code has been generated.
  Map<int, int> emit(CodeBuffer buffer, LabelManager labelManager) {
    final labelOffsets = <int, int>{};

    // Sort by alignment (largest first) to minimize padding
    final sorted = List<_ConstEntry>.from(_entries);
    sorted.sort((a, b) => b.align.bytes.compareTo(a.align.bytes));

    for (final entry in sorted) {
      // Align the buffer
      final padding = buffer.alignWithNops(entry.align.bytes);
      if (padding > 0) {
        // Actually use zeros for data, not NOPs
        for (int i = buffer.length - padding; i < buffer.length; i++) {
          buffer[i] = 0x00;
        }
      }

      // Record the offset
      entry.offset = buffer.length;
      labelOffsets[entry.label.id] = buffer.length;

      // Bind the label if we have a label manager
      labelManager.bind(entry.label, buffer.length);

      // Emit the data
      buffer.emitBytes(entry.data);
    }

    return labelOffsets;
  }

  /// Clears all constants.
  void clear() {
    _entries.clear();
  }

  /// Gets the total size of the pool (including alignment padding).
  int estimateSize() {
    if (_entries.isEmpty) return 0;

    // Sort by alignment
    final sorted = List<_ConstEntry>.from(_entries);
    sorted.sort((a, b) => b.align.bytes.compareTo(a.align.bytes));

    int size = 0;
    for (final entry in sorted) {
      // Add padding for alignment
      final remainder = size % entry.align.bytes;
      if (remainder != 0) {
        size += entry.align.bytes - remainder;
      }
      size += entry.size;
    }

    return size;
  }
}
