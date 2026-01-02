/// Vector Constants Table
///
/// Ported from asmjit/ujit/vecconsttable.h

import 'dart:typed_data';

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
  // We can initialize these lazily or statically.
  // Using 256-bit generally for x86 compatibility.

  static final VecConst p_0000000000000000 = VecConst.splat64(0);
  static final VecConst p_FFFFFFFFFFFFFFFF = VecConst.splat64(-1); // 0xFF...

  // ... Add more as needed by UniCompiler implementation
}

class VecConstTableRef {
  final VecConstTable? table;
  final int size; // Size in bytes

  const VecConstTableRef(this.table, this.size);
}
