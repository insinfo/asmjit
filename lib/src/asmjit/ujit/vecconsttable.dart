/// Vector Constants Table
///
/// Ported from asmjit/ujit/vecconsttable.h

import 'dart:typed_data';
import 'dart:ffi'; // For Pointer, Uint8
import 'package:ffi/ffi.dart'; // For calloc

/// A vector constant.
///
/// Represents data that can be embedded into the instruction stream or constant pool.
class VecConst {
  final int width; // Width in bytes (16 for 128-bit, 32 for 256-bit)
  final Uint8List data;

  const VecConst(this.width, this.data);

  // Helper to create 128-bit constant from 64-bit values (repeated 2 times)
  factory VecConst.u64x2(int v0, int v1) {
    final data = ByteData(16);
    data.setUint64(0, v0, Endian.little);
    data.setUint64(8, v1, Endian.little);
    return VecConst(16, data.buffer.asUint8List());
  }

  // Repeated value
  factory VecConst.splat64(int v) {
    // For 256-bit (32 bytes)
    final data = ByteData(32);
    for (int i = 0; i < 4; i++) {
      data.setUint64(i * 8, v, Endian.little);
    }
    // Defaulting to 256 for "Native" on x86/64
    return VecConst(32, data.buffer.asUint8List());
  }

  factory VecConst.splat64_128(int v) {
    final data = ByteData(16);
    data.setUint64(0, v, Endian.little);
    data.setUint64(8, v, Endian.little);
    return VecConst(16, data.buffer.asUint8List());
  }

  // TODO: Add more helpers as needed.
}

/// A table of common vector constants.
class VecConstTable {
  static const int kSize = 512; // Enough space for common constants
  static Pointer<Uint8>? _memory;
  static int _alignedAddress = 0;

  static final Map<VecConst, int> _offsets = {};

  // Standard constants
  static final VecConst p_0000000000000000 = _register(VecConst.splat64(0));
  static final VecConst p_FFFFFFFFFFFFFFFF = _register(VecConst.splat64(-1));

  // Float32 Neg/Abs
  static final VecConst p_8000000080000000 =
      _register(VecConst.splat64(0x8000000080000000));
  static final VecConst p_7FFFFFFF7FFFFFFF =
      _register(VecConst.splat64(0x7FFFFFFF7FFFFFFF));

  // Float64 Neg/Abs
  static final VecConst p_8000000000000000 =
      _register(VecConst.splat64(0x8000000000000000));
  static final VecConst p_7FFFFFFFFFFFFFFF =
      _register(VecConst.splat64(0x7FFFFFFFFFFFFFFF));

  static int _currentOffset = 0;

  static VecConst _register(VecConst vc) {
    if (_currentOffset + vc.width > kSize) {
      throw StateError('VecConstTable overflow');
    }
    _offsets[vc] = _currentOffset;
    _currentOffset += vc.width;
    // Align next to 32 bytes to be safe/perf friendly
    if (_currentOffset % 32 != 0) {
      _currentOffset = (_currentOffset + 31) & ~31;
    }
    return vc;
  }

  /// Returns the offset of the constant in the table.
  static int getOffset(VecConst c) {
    if (!_offsets.containsKey(c)) {
      // Ideally we should support ad-hoc registration, but for now specific constants only
      throw ArgumentError('VecConst not registered in table');
    }
    return _offsets[c]!;
  }

  /// Returns the base address of the table (aligned).
  /// Initializes memory on first call.
  static int getAddress() {
    if (_memory == null) {
      // Allocate with padding for alignment (64 bytes alignment)
      final totalSize = kSize + 64;
      _memory = calloc.allocate<Uint8>(totalSize);

      int addr = _memory!.address;
      // Align to 64 bytes
      _alignedAddress = (addr + 63) & ~63;

      // Populate
      final view =
          Pointer<Uint8>.fromAddress(_alignedAddress).asTypedList(kSize);
      // We can't use view.setRange efficiently strictly with typed_data without copy
      // But we can iterate.

      _offsets.forEach((vc, offset) {
        final data = vc.data;
        for (int i = 0; i < vc.width; i++) {
          // Safe because we registered them and checked bounds
          view[offset + i] = data[i];
        }
      });
    }
    return _alignedAddress;
  }
}

class VecConstTableRef {
  final VecConstTable? table;
  final int size; // Size in bytes

  const VecConstTableRef(this.table, this.size);
}
