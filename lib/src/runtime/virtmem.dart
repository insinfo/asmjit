/// AsmJit Virtual Memory Management
///
/// Provides cross-platform virtual memory allocation for executable code.
/// Ported from asmjit/core/virtmem.h and virtmem.cpp

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import '../core/error.dart';
import 'libc.dart' as libc;

// =============================================================================
// Platform-specific APIs
// =============================================================================

/// Opens the kernel32 library on Windows.
DynamicLibrary? _kernel32;
DynamicLibrary get kernel32 {
  _kernel32 ??= DynamicLibrary.open('kernel32.dll');
  return _kernel32!;
}

// Windows constants
const int _MEM_COMMIT = 0x1000;
const int _MEM_RESERVE = 0x2000;
const int _MEM_RELEASE = 0x8000;

const int _PAGE_NOACCESS = 0x01;
const int _PAGE_READONLY = 0x02;
const int _PAGE_READWRITE = 0x04;
const int _PAGE_EXECUTE_READ = 0x20;
const int _PAGE_EXECUTE_READWRITE = 0x40;

// POSIX constants
const int _PROT_NONE = 0x0;
const int _PROT_READ = 0x1;
const int _PROT_WRITE = 0x2;
const int _PROT_EXEC = 0x4;

const int _MAP_PRIVATE = 0x02;
final int _MAP_ANONYMOUS = Platform.isMacOS ? 0x1000 : 0x20;
const int _MAP_FAILED = -1;

// Windows native function types
typedef _VirtualAllocNative = Pointer<Void> Function(Pointer<Void> lpAddress,
    IntPtr dwSize, Uint32 flAllocationType, Uint32 flProtect);
typedef _VirtualAllocDart = Pointer<Void> Function(
    Pointer<Void> lpAddress, int dwSize, int flAllocationType, int flProtect);

typedef _VirtualFreeNative = Int32 Function(
    Pointer<Void> lpAddress, IntPtr dwSize, Uint32 dwFreeType);
typedef _VirtualFreeDart = int Function(
    Pointer<Void> lpAddress, int dwSize, int dwFreeType);

typedef _VirtualProtectNative = Int32 Function(Pointer<Void> lpAddress,
    IntPtr dwSize, Uint32 flNewProtect, Pointer<Uint32> lpflOldProtect);
typedef _VirtualProtectDart = int Function(Pointer<Void> lpAddress, int dwSize,
    int flNewProtect, Pointer<Uint32> lpflOldProtect);

typedef _FlushInstructionCacheNative = Int32 Function(
    IntPtr hProcess, Pointer<Void> lpBaseAddress, IntPtr dwSize);
typedef _FlushInstructionCacheDart = int Function(
    int hProcess, Pointer<Void> lpBaseAddress, int dwSize);

typedef _GetCurrentProcessNative = IntPtr Function();
typedef _GetCurrentProcessDart = int Function();

typedef _GetSystemInfoNative = Void Function(Pointer<Void> lpSystemInfo);
typedef _GetSystemInfoDart = void Function(Pointer<Void> lpSystemInfo);

// POSIX native function types
typedef _MmapNative = Pointer<Void> Function(Pointer<Void> addr, IntPtr length,
    Int32 prot, Int32 flags, Int32 fd, IntPtr offset);
typedef _MmapDart = Pointer<Void> Function(
    Pointer<Void> addr, int length, int prot, int flags, int fd, int offset);

typedef _MunmapNative = Int32 Function(Pointer<Void> addr, IntPtr length);
typedef _MunmapDart = int Function(Pointer<Void> addr, int length);

typedef _MprotectNative = Int32 Function(
    Pointer<Void> addr, IntPtr len, Int32 prot);
typedef _MprotectDart = int Function(Pointer<Void> addr, int len, int prot);

typedef _SysconfNative = IntPtr Function(Int32 name);
typedef _SysconfDart = int Function(int name);

// Late-initialized Windows functions
late final _VirtualAllocDart _virtualAlloc;
late final _VirtualFreeDart _virtualFree;
late final _VirtualProtectDart _virtualProtect;
late final _FlushInstructionCacheDart _flushInstructionCache;
late final _GetCurrentProcessDart _getCurrentProcess;
late final _GetSystemInfoDart _getSystemInfo;

// Late-initialized POSIX functions
late final _MmapDart _mmap;
late final _MunmapDart _munmap;
late final _MprotectDart _mprotect;
late final _SysconfDart _sysconf;

bool _initialized = false;

void _initPlatformFunctions() {
  if (_initialized) return;

  if (Platform.isWindows) {
    _virtualAlloc = kernel32
        .lookup<NativeFunction<_VirtualAllocNative>>('VirtualAlloc')
        .asFunction<_VirtualAllocDart>();
    _virtualFree = kernel32
        .lookup<NativeFunction<_VirtualFreeNative>>('VirtualFree')
        .asFunction<_VirtualFreeDart>();
    _virtualProtect = kernel32
        .lookup<NativeFunction<_VirtualProtectNative>>('VirtualProtect')
        .asFunction<_VirtualProtectDart>();
    _flushInstructionCache = kernel32
        .lookup<NativeFunction<_FlushInstructionCacheNative>>(
            'FlushInstructionCache')
        .asFunction<_FlushInstructionCacheDart>();
    _getCurrentProcess = kernel32
        .lookup<NativeFunction<_GetCurrentProcessNative>>('GetCurrentProcess')
        .asFunction<_GetCurrentProcessDart>();
    _getSystemInfo = kernel32
        .lookup<NativeFunction<_GetSystemInfoNative>>('GetSystemInfo')
        .asFunction<_GetSystemInfoDart>();
  } else {
    _mmap = libc.libc
        .lookup<NativeFunction<_MmapNative>>('mmap')
        .asFunction<_MmapDart>();
    _munmap = libc.libc
        .lookup<NativeFunction<_MunmapNative>>('munmap')
        .asFunction<_MunmapDart>();
    _mprotect = libc.libc
        .lookup<NativeFunction<_MprotectNative>>('mprotect')
        .asFunction<_MprotectDart>();
    _sysconf = libc.libc
        .lookup<NativeFunction<_SysconfNative>>('sysconf')
        .asFunction<_SysconfDart>();
  }

  _initialized = true;
}

// =============================================================================
// Public API
// =============================================================================

/// Virtual memory access flags.
enum MemoryFlags {
  /// No access.
  none,

  /// Read access.
  read,

  /// Read + Write access.
  readWrite,

  /// Read + Execute access.
  readExecute,

  /// Read + Write + Execute access.
  ///
  /// WARNING: Avoid using RWX - prefer W^X (write XOR execute).
  /// Allocate as RW, write code, then protect as RX.
  readWriteExecute,
}

/// Flush instruction cache mode.
enum FlushMode {
  /// Default: decide based on platform.
  defaultMode,

  /// Always flush after write.
  flushAfterWrite,

  /// Never flush.
  neverFlush,
}

/// Information about virtual memory.
class VirtMemInfo {
  /// Page size in bytes.
  final int pageSize;

  /// Page granularity (allocation granularity).
  final int pageGranularity;

  const VirtMemInfo({
    required this.pageSize,
    required this.pageGranularity,
  });

  /// Aligns [size] up to page boundary.
  int alignToPage(int size) {
    return (size + pageSize - 1) & ~(pageSize - 1);
  }

  /// Aligns [size] up to granularity boundary.
  int alignToGranularity(int size) {
    return (size + pageGranularity - 1) & ~(pageGranularity - 1);
  }
}

/// A block of virtual memory.
class VirtMemBlock {
  /// Pointer to the memory.
  final Pointer<Uint8> ptr;

  /// Size of the block in bytes.
  final int size;

  /// Current memory flags.
  final MemoryFlags flags;

  const VirtMemBlock({
    required this.ptr,
    required this.size,
    required this.flags,
  });

  /// The address of the memory block.
  int get address => ptr.address;

  /// Whether this block has execute permission.
  bool get isExecutable =>
      flags == MemoryFlags.readExecute || flags == MemoryFlags.readWriteExecute;

  /// Whether this block has write permission.
  bool get isWritable =>
      flags == MemoryFlags.readWrite || flags == MemoryFlags.readWriteExecute;

  /// Whether this block has read permission.
  bool get isReadable => flags != MemoryFlags.none;
}

/// Virtual memory management.
///
/// Provides cross-platform virtual memory allocation for JIT code.
abstract class VirtMem {
  const VirtMem._();

  /// Returns virtual memory information.
  static VirtMemInfo info() {
    _initPlatformFunctions();

    if (Platform.isWindows) {
      // SYSTEM_INFO structure is 48 bytes on x64
      final sysInfo = libc.NativeHeap.allocZeroed(48);
      try {
        _getSystemInfo(sysInfo.cast<Void>());
        // dwPageSize is at offset 4
        final pageSize = (sysInfo.cast<Uint32>() + 1).value;
        // dwAllocationGranularity is at offset 28 on x64
        final granularity = (sysInfo.cast<Uint32>() + 7).value;
        return VirtMemInfo(
          pageSize: pageSize,
          pageGranularity: granularity,
        );
      } finally {
        libc.NativeHeap.release(sysInfo);
      }
    } else {
      // _SC_PAGESIZE = 30 on Linux, 29 on macOS
      final scPageSize = Platform.isMacOS ? 29 : 30;
      final pageSize = _sysconf(scPageSize);
      return VirtMemInfo(
        pageSize: pageSize > 0 ? pageSize : 4096,
        pageGranularity: pageSize > 0 ? pageSize : 4096,
      );
    }
  }

  /// Allocates virtual memory with the specified flags.
  ///
  /// The [size] should be page-aligned. Use [VirtMemInfo.alignToPage].
  static VirtMemBlock alloc(int size, MemoryFlags flags) {
    _initPlatformFunctions();

    if (size <= 0) {
      throw AsmJitException.invalidArgument('Size must be positive');
    }

    Pointer<Void> ptr;

    if (Platform.isWindows) {
      final protect = _memoryFlagsToWindows(flags);
      ptr = _virtualAlloc(
        nullptr,
        size,
        _MEM_COMMIT | _MEM_RESERVE,
        protect,
      );
      if (ptr == nullptr) {
        throw AsmJitException(
          AsmJitError.failedToMapVirtMem,
          'VirtualAlloc failed for $size bytes with flags $flags',
        );
      }
    } else {
      final prot = _memoryFlagsToPosix(flags);
      ptr = _mmap(
        nullptr,
        size,
        prot,
        _MAP_PRIVATE | _MAP_ANONYMOUS,
        -1,
        0,
      );
      if (ptr.address == _MAP_FAILED || ptr == nullptr) {
        throw AsmJitException(
          AsmJitError.failedToMapVirtMem,
          'mmap failed for $size bytes with flags $flags',
        );
      }
    }

    return VirtMemBlock(
      ptr: ptr.cast<Uint8>(),
      size: size,
      flags: flags,
    );
  }

  /// Allocates RW memory (for writing code before making it executable).
  static VirtMemBlock allocRW(int size) => alloc(size, MemoryFlags.readWrite);

  /// Releases virtual memory.
  static void release(VirtMemBlock block) {
    _initPlatformFunctions();

    if (Platform.isWindows) {
      final result = _virtualFree(block.ptr.cast<Void>(), 0, _MEM_RELEASE);
      if (result == 0) {
        throw AsmJitException(
          AsmJitError.unknown,
          'VirtualFree failed for block at ${block.address}',
        );
      }
    } else {
      final result = _munmap(block.ptr.cast<Void>(), block.size);
      if (result != 0) {
        throw AsmJitException(
          AsmJitError.unknown,
          'munmap failed for block at ${block.address}',
        );
      }
    }
  }

  /// Changes memory protection flags.
  static VirtMemBlock protect(VirtMemBlock block, MemoryFlags newFlags) {
    _initPlatformFunctions();

    if (Platform.isWindows) {
      final oldProtect = libc.NativeHeap.allocUint32(1);
      try {
        final protect = _memoryFlagsToWindows(newFlags);
        final result = _virtualProtect(
          block.ptr.cast<Void>(),
          block.size,
          protect,
          oldProtect,
        );
        if (result == 0) {
          throw AsmJitException(
            AsmJitError.unknown,
            'VirtualProtect failed to change protection to $newFlags',
          );
        }
      } finally {
        libc.NativeHeap.release(oldProtect.cast<Uint8>());
      }
    } else {
      final prot = _memoryFlagsToPosix(newFlags);
      final result = _mprotect(block.ptr.cast<Void>(), block.size, prot);
      if (result != 0) {
        throw AsmJitException(
          AsmJitError.unknown,
          'mprotect failed to change protection to $newFlags',
        );
      }
    }

    return VirtMemBlock(
      ptr: block.ptr,
      size: block.size,
      flags: newFlags,
    );
  }

  /// Makes memory executable (changes RW to RX).
  ///
  /// This is the W^X (Write XOR Execute) pattern.
  static VirtMemBlock protectRX(VirtMemBlock block) {
    return protect(block, MemoryFlags.readExecute);
  }

  /// Flushes the instruction cache.
  ///
  /// This is necessary on some architectures (ARM) after writing code
  /// to ensure the CPU sees the new instructions.
  /// On x86/x64, this is usually a no-op but good practice to call.
  static void flushInstructionCache(Pointer<Void> addr, int size) {
    _initPlatformFunctions();

    if (Platform.isWindows) {
      final hProcess = _getCurrentProcess();
      _flushInstructionCache(hProcess, addr, size);
    } else {
      // On POSIX, use __builtin___clear_cache or cacheflush.
      // For x86/x64 this is typically not needed.
      // For ARM, we'd need to call appropriate syscall.
      // For now, we skip on POSIX x86/x64.
    }
  }

  /// Writes bytes to virtual memory.
  ///
  /// The block must have write permission.
  static void writeBytes(VirtMemBlock block, Uint8List bytes,
      [int offset = 0]) {
    if (!block.isWritable) {
      throw AsmJitException(
        AsmJitError.invalidState,
        'Block is not writable. Allocate as RW, write, then protect as RX.',
      );
    }
    if (offset < 0 || offset + bytes.length > block.size) {
      throw AsmJitException(
        AsmJitError.invalidArgument,
        'writeBytes out of range: offset=$offset, len=${bytes.length}, size=${block.size}',
      );
    }

    // Copy directly
    (block.ptr + offset).asTypedList(bytes.length).setAll(0, bytes);
  }
}

// Helper functions to convert flags

int _memoryFlagsToWindows(MemoryFlags flags) {
  switch (flags) {
    case MemoryFlags.none:
      return _PAGE_NOACCESS;
    case MemoryFlags.read:
      return _PAGE_READONLY;
    case MemoryFlags.readWrite:
      return _PAGE_READWRITE;
    case MemoryFlags.readExecute:
      return _PAGE_EXECUTE_READ;
    case MemoryFlags.readWriteExecute:
      return _PAGE_EXECUTE_READWRITE;
  }
}

int _memoryFlagsToPosix(MemoryFlags flags) {
  switch (flags) {
    case MemoryFlags.none:
      return _PROT_NONE;
    case MemoryFlags.read:
      return _PROT_READ;
    case MemoryFlags.readWrite:
      return _PROT_READ | _PROT_WRITE;
    case MemoryFlags.readExecute:
      return _PROT_READ | _PROT_EXEC;
    case MemoryFlags.readWriteExecute:
      return _PROT_READ | _PROT_WRITE | _PROT_EXEC;
  }
}
