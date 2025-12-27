/// AsmJit libc FFI Bindings
///
/// Provides FFI bindings to libc/CRT functions for memory management.
/// Used for heap allocations (non-executable memory).

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

/// Opens the appropriate C library for the current platform.
DynamicLibrary _openCLib() {
  if (Platform.isWindows) {
    // Try ucrtbase first (Universal CRT), fall back to msvcrt
    try {
      return DynamicLibrary.open('ucrtbase.dll');
    } catch (_) {
      return DynamicLibrary.open('msvcrt.dll');
    }
  }
  if (Platform.isMacOS) {
    return DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libc.so.6');
  }
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libc.so');
  }
  // Fallback: try process symbols
  return DynamicLibrary.process();
}

/// The C library instance.
final DynamicLibrary libc = _openCLib();

// Native function typedefs
typedef _MallocNative = Pointer<Void> Function(IntPtr size);
typedef _FreeNative = Void Function(Pointer<Void> ptr);
typedef _ReallocNative = Pointer<Void> Function(Pointer<Void> ptr, IntPtr size);
typedef _CallocNative = Pointer<Void> Function(IntPtr num, IntPtr size);
typedef _MemcpyNative = Pointer<Void> Function(
    Pointer<Void> dst, Pointer<Void> src, IntPtr n);
typedef _MemsetNative = Pointer<Void> Function(
    Pointer<Void> ptr, Int32 value, IntPtr n);
typedef _MemmoveNative = Pointer<Void> Function(
    Pointer<Void> dst, Pointer<Void> src, IntPtr n);
typedef _MemcmpNative = Int32 Function(
    Pointer<Void> ptr1, Pointer<Void> ptr2, IntPtr n);

// Dart function typedefs
typedef MallocDart = Pointer<Void> Function(int size);
typedef FreeDart = void Function(Pointer<Void> ptr);
typedef ReallocDart = Pointer<Void> Function(Pointer<Void> ptr, int size);
typedef CallocDart = Pointer<Void> Function(int num, int size);
typedef MemcpyDart = Pointer<Void> Function(
    Pointer<Void> dst, Pointer<Void> src, int n);
typedef MemsetDart = Pointer<Void> Function(
    Pointer<Void> ptr, int value, int n);
typedef MemcmpDart = int Function(
    Pointer<Void> ptr1, Pointer<Void> ptr2, int n);

/// Allocates [size] bytes of memory.
///
/// Returns a null pointer if allocation fails.
final MallocDart malloc = libc
    .lookup<NativeFunction<_MallocNative>>('malloc')
    .asFunction<MallocDart>();

/// Frees memory previously allocated by [malloc], [calloc], or [realloc].
final FreeDart free =
    libc.lookup<NativeFunction<_FreeNative>>('free').asFunction<FreeDart>();

/// Reallocates memory to [size] bytes.
///
/// Returns a null pointer if allocation fails.
final ReallocDart realloc = libc
    .lookup<NativeFunction<_ReallocNative>>('realloc')
    .asFunction<ReallocDart>();

/// Allocates [num] * [size] bytes of zero-initialized memory.
///
/// Returns a null pointer if allocation fails.
final CallocDart calloc = libc
    .lookup<NativeFunction<_CallocNative>>('calloc')
    .asFunction<CallocDart>();

/// Copies [n] bytes from [src] to [dst].
///
/// The memory areas must not overlap.
final MemcpyDart memcpy = libc
    .lookup<NativeFunction<_MemcpyNative>>('memcpy')
    .asFunction<MemcpyDart>();

/// Sets [n] bytes of memory to [value].
final MemsetDart memset = libc
    .lookup<NativeFunction<_MemsetNative>>('memset')
    .asFunction<MemsetDart>();

/// Copies [n] bytes from [src] to [dst].
///
/// The memory areas may overlap.
final MemcpyDart memmove = libc
    .lookup<NativeFunction<_MemmoveNative>>('memmove')
    .asFunction<MemcpyDart>();

/// Compares [n] bytes of two memory regions.
///
/// Returns 0 if equal, negative if ptr1 < ptr2, positive if ptr1 > ptr2.
final MemcmpDart memcmp = libc
    .lookup<NativeFunction<_MemcmpNative>>('memcmp')
    .asFunction<MemcmpDart>();

/// Wrapper class for native heap allocations.
///
/// Provides a higher-level API and integrates with Dart's finalizer.
class NativeHeap {
  /// Allocates [size] bytes of memory.
  ///
  /// Throws if allocation fails.
  static Pointer<Uint8> alloc(int size) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive');
    }
    final ptr = malloc(size);
    if (ptr == nullptr) {
      throw OutOfMemoryError();
    }
    return ptr.cast<Uint8>();
  }

  /// Allocates [count] Uint32 elements.
  static Pointer<Uint32> allocUint32(int count) {
    return alloc(count * 4).cast<Uint32>();
  }

  /// Allocates [count] Uint64 elements.
  static Pointer<Uint64> allocUint64(int count) {
    return alloc(count * 8).cast<Uint64>();
  }

  /// Allocates [count] Int32 elements.
  static Pointer<Int32> allocInt32(int count) {
    return alloc(count * 4).cast<Int32>();
  }

  /// Allocates [count] Int64 elements.
  static Pointer<Int64> allocInt64(int count) {
    return alloc(count * 8).cast<Int64>();
  }

  /// Allocates [size] bytes of zero-initialized memory.
  ///
  /// Throws if allocation fails.
  static Pointer<Uint8> allocZeroed(int size) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive');
    }
    final ptr = calloc(size, 1);
    if (ptr == nullptr) {
      throw OutOfMemoryError();
    }
    return ptr.cast<Uint8>();
  }

  /// Reallocates memory to [newSize] bytes.
  ///
  /// Throws if reallocation fails.
  static Pointer<Uint8> resize(Pointer<Uint8> ptr, int newSize) {
    if (newSize <= 0) {
      throw ArgumentError.value(newSize, 'newSize', 'Must be positive');
    }
    final newPtr = realloc(ptr.cast<Void>(), newSize);
    if (newPtr == nullptr) {
      throw OutOfMemoryError();
    }
    return newPtr.cast<Uint8>();
  }

  /// Frees memory allocated by [alloc], [allocZeroed], or [resize].
  static void release(Pointer<Uint8> ptr) {
    if (ptr != nullptr) {
      free(ptr.cast<Void>());
    }
  }

  /// Copies bytes from a Dart [Uint8List] to native memory.
  static void copyFrom(Pointer<Uint8> dst, Uint8List src, [int offset = 0]) {
    final srcPtr = alloc(src.length);
    try {
      srcPtr.asTypedList(src.length).setAll(0, src);
      memcpy((dst + offset).cast<Void>(), srcPtr.cast<Void>(), src.length);
    } finally {
      release(srcPtr);
    }
  }

  /// Copies bytes from native memory to a Dart [Uint8List].
  static Uint8List copyTo(Pointer<Uint8> src, int length) {
    final result = Uint8List(length);
    result.setAll(0, src.asTypedList(length));
    return result;
  }
}

/// A native buffer that automatically frees its memory when disposed.
class NativeBuffer {
  Pointer<Uint8>? _ptr;
  final int _size;

  /// Creates a new native buffer of [size] bytes.
  NativeBuffer(int size)
      : _size = size,
        _ptr = NativeHeap.alloc(size);

  /// Creates a new zero-initialized native buffer of [size] bytes.
  NativeBuffer.zeroed(int size)
      : _size = size,
        _ptr = NativeHeap.allocZeroed(size);

  /// Creates a native buffer from a Dart [Uint8List].
  factory NativeBuffer.fromBytes(Uint8List bytes) {
    final buffer = NativeBuffer(bytes.length);
    buffer.ptr.asTypedList(bytes.length).setAll(0, bytes);
    return buffer;
  }

  /// Whether this buffer has been disposed.
  bool get isDisposed => _ptr == null;

  /// The pointer to the buffer.
  ///
  /// Throws if the buffer has been disposed.
  Pointer<Uint8> get ptr {
    if (_ptr == null) {
      throw StateError('NativeBuffer has been disposed');
    }
    return _ptr!;
  }

  /// The size of the buffer in bytes.
  int get size => _size;

  /// Returns this buffer as a typed list view.
  ///
  /// The view is only valid while the buffer has not been disposed.
  Uint8List asTypedList() => ptr.asTypedList(_size);

  /// Disposes the buffer, freeing native memory.
  void dispose() {
    if (_ptr != null) {
      NativeHeap.release(_ptr!);
      _ptr = null;
    }
  }
}
