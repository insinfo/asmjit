/// AsmJit Virtual Memory Management
///
/// Cross-platform virtual memory allocation for executable code.
/// Ported from asmjit/core/virtmem.h and virtmem.cpp (`VirtMem` namespace).
///
/// The OS calls are made through `dart:ffi`. The upstream compile-time
/// platform selection (`_WIN32`, `__APPLE__`, `__linux__`, `ASMJIT_ARCH_X86`,
/// ...) is made at run time from [Platform] and [Abi.current].
///
/// Not ported (no Dart VM runs there): the NetBSD `mremap(MAP_REMAPDUP)` dual
/// mapping, the FreeBSD `shm_open(SHM_ANON)` / `getpagesizes()` paths and
/// `PROT_MAX` / `PROT_MPROTECT` maximum protections (only defined on the BSDs,
/// so `mm_max_prot_from_memory_flags()` is 0 on every supported platform).
library;

import 'dart:ffi';
import 'dart:io' show File, Platform;

import 'package:ffi/ffi.dart' as pffi;

import '../core/error.dart';
import 'libc.dart' as libc;

// =============================================================================
// Host detection (upstream compile-time macros)
// =============================================================================

/// `ASMJIT_ARCH_X86` (x86 or x86-64 host).
final bool _hostIsX86 = const [
  Abi.linuxX64,
  Abi.linuxIA32,
  Abi.macosX64,
  Abi.windowsX64,
  Abi.windowsIA32,
  Abi.androidX64,
  Abi.androidIA32,
  Abi.fuchsiaX64,
].contains(Abi.current());

/// `ASMJIT_ARCH_ARM >= 64` (AArch64 host).
final bool _hostIsArm64 = const [
  Abi.linuxArm64,
  Abi.macosArm64,
  Abi.iosArm64,
  Abi.windowsArm64,
  Abi.androidArm64,
  Abi.fuchsiaArm64,
].contains(Abi.current());

/// `defined(__APPLE__)`.
final bool _isApple = Platform.isMacOS || Platform.isIOS;

/// `defined(__APPLE__) && TARGET_OS_OSX`.
final bool _isMacOS = Platform.isMacOS;

/// `defined(__linux__)` (also defined on Android).
final bool _isLinux = Platform.isLinux || Platform.isAndroid;

/// `defined(__BIONIC__)`.
final bool _isBionic = Platform.isAndroid;

/// `ASMJIT_HAS_SHM_OPEN`: Android NDK doesn't provide `shm_open()`.
final bool _hasShmOpen = !_isBionic;

/// `ASMJIT_VM_SHM_DETECT`.
final bool _vmShmDetect = !(_isApple || _isBionic || !_hasShmOpen);

/// `ASMJIT_ANONYMOUS_MEMORY_USE_MACH_VM_REMAP`: macOS on X86 hardware.
final bool _useMachVmRemap = _isMacOS && _hostIsX86;

/// `ASMJIT_HAS_PTHREAD_JIT_WRITE_PROTECT_NP`: macOS on AArch64 hardware.
final bool _hasPthreadJitWriteProtectNp = _isMacOS && _hostIsArm64;

/// `ASMJIT_NO_DUAL_MAPPING`: Apple platforms on non-X86 hardware.
final bool _noDualMapping = _isApple && !_hostIsX86;

// =============================================================================
// Platform constants
// =============================================================================

// POSIX - mmap() / mprotect().
const int _kProtRead = 0x1;
const int _kProtWrite = 0x2;
const int _kProtExec = 0x4;

const int _kMapShared = 0x01;
const int _kMapPrivate = 0x02;
final int _kMapAnonymous = _isApple ? 0x1000 : 0x20;
const int _kMapJit = 0x800;
const int _kMapHugeTlb = 0x40000;
const int _kMapHugeShift = 26;
const int _kMadvHugePage = 14;

/// `MAP_FAILED` (`(void*)-1`) as a [Pointer.address]: on a 32-bit process
/// the address is the unsigned 0xFFFFFFFF, not -1.
final int _kMapFailed = Pointer<Void>.fromAddress(-1).address;

// Linux - memfd_create().
const int _kMfdCloexec = 0x0001;
const int _kMfdExec = 0x0010;

// Linux - open() / shm_open() flags (only used by the file based dual mapping,
// which Apple platforms never use).
const int _kORdWr = 0x2;
const int _kOCreat = 0x40;
const int _kOExcl = 0x80;
const int _kSIRUsrIWUsr = 0x180; // S_IRUSR | S_IWUSR

// errno values.
const int _kEPerm = 1;
const int _kENoMem = 12;
const int _kEAcces = 13;
const int _kEExist = 17;
const int _kENoDev = 19;
const int _kEInval = 22;
const int _kENFile = 23;
const int _kEMFile = 24;
const int _kEFBig = 27;
final int _kEAgain = _isApple ? 35 : 11;
final int _kENoSys = _isApple ? 78 : 38;
final int _kEOverflow = _isApple ? 84 : 75;

// Windows - VirtualAlloc() / VirtualProtect() / MapViewOfFile().
const int _kMemCommit = 0x1000;
const int _kMemReserve = 0x2000;
const int _kMemRelease = 0x8000;
const int _kMemLargePages = 0x20000000;

const int _kPageNoAccess = 0x01;
const int _kPageReadOnly = 0x02;
const int _kPageReadWrite = 0x04;
const int _kPageExecuteRead = 0x20;
const int _kPageExecuteReadWrite = 0x40;

const int _kFileMapWrite = 0x0002;
const int _kFileMapRead = 0x0004;
const int _kFileMapExecute = 0x0020;

// macOS - Mach VM.
const int _kVmProtRead = 0x1;
const int _kVmProtWrite = 0x2;
const int _kVmProtExecute = 0x4;
const int _kVmFlagsAnywhere = 0x0001;
const int _kVmFlagsRandomAddr = 0x0008;
const int _kVmInheritDefault = 1; // VM_INHERIT_COPY
const int _kKernSuccess = 0;
const int _kKernProtectionFailure = 2;
const int _kKernNoSpace = 3;
const int _kKernInvalidArgument = 4;

// =============================================================================
// Native bindings (resolved lazily, only on the platform that uses them)
// =============================================================================

DynamicLibrary? _kernel32Lib;
DynamicLibrary get _kernel32 => _kernel32Lib ??= DynamicLibrary.open(
      'kernel32.dll',
    );

/// Windows `SYSTEM_INFO`.
final class _SystemInfo extends Struct {
  @Uint16()
  external int wProcessorArchitecture;
  @Uint16()
  external int wReserved;
  @Uint32()
  external int dwPageSize;
  external Pointer<Void> lpMinimumApplicationAddress;
  external Pointer<Void> lpMaximumApplicationAddress;
  @UintPtr()
  external int dwActiveProcessorMask;
  @Uint32()
  external int dwNumberOfProcessors;
  @Uint32()
  external int dwProcessorType;
  @Uint32()
  external int dwAllocationGranularity;
  @Uint16()
  external int wProcessorLevel;
  @Uint16()
  external int wProcessorRevision;
}

// Windows.
final _getSystemInfo = _kernel32.lookupFunction<
    Void Function(Pointer<_SystemInfo>),
    void Function(Pointer<_SystemInfo>)>('GetSystemInfo');
final _getLargePageMinimum = _kernel32
    .lookupFunction<UintPtr Function(), int Function()>('GetLargePageMinimum');
final _virtualAlloc = _kernel32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, UintPtr, Uint32, Uint32),
    Pointer<Void> Function(Pointer<Void>, int, int, int)>('VirtualAlloc');
final _virtualFree = _kernel32.lookupFunction<
    Int32 Function(Pointer<Void>, UintPtr, Uint32),
    int Function(Pointer<Void>, int, int)>('VirtualFree');
final _virtualProtect = _kernel32.lookupFunction<
    Int32 Function(Pointer<Void>, UintPtr, Uint32, Pointer<Uint32>),
    int Function(Pointer<Void>, int, int, Pointer<Uint32>)>('VirtualProtect');
final _createFileMappingW = _kernel32.lookupFunction<
    Pointer<Void> Function(
        Pointer<Void>, Pointer<Void>, Uint32, Uint32, Uint32, Pointer<Uint16>),
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, int, int,
        Pointer<Uint16>)>('CreateFileMappingW');
final _mapViewOfFile = _kernel32.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Uint32, Uint32, Uint32, UintPtr),
    Pointer<Void> Function(Pointer<Void>, int, int, int, int)>('MapViewOfFile');
final _unmapViewOfFile = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'UnmapViewOfFile',
);
final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('CloseHandle');
final _flushInstructionCacheWin = _kernel32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>, UintPtr),
    int Function(Pointer<Void>, Pointer<Void>, int)>('FlushInstructionCache');
final _getCurrentProcess = _kernel32.lookupFunction<Pointer<Void> Function(),
    Pointer<Void> Function()>('GetCurrentProcess');

// POSIX.
final _mmap = libc.libc.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, Long),
    Pointer<Void> Function(Pointer<Void>, int, int, int, int, int)>('mmap');
final _munmap = libc.libc.lookupFunction<Int32 Function(Pointer<Void>, IntPtr),
    int Function(Pointer<Void>, int)>('munmap');
final _mprotect = libc.libc.lookupFunction<
    Int32 Function(Pointer<Void>, IntPtr, Int32),
    int Function(Pointer<Void>, int, int)>('mprotect');
final _madvise = libc.libc.lookupFunction<
    Int32 Function(Pointer<Void>, IntPtr, Int32),
    int Function(Pointer<Void>, int, int)>('madvise');
final _getpagesize =
    libc.libc.lookupFunction<Int32 Function(), int Function()>('getpagesize');
final _uname = libc.libc.lookupFunction<Int32 Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('uname');
final _close =
    libc.libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
final _unlink = libc.libc.lookupFunction<Int32 Function(Pointer<pffi.Utf8>),
    int Function(Pointer<pffi.Utf8>)>('unlink');

/// `ASMJIT_FILE64_API(open)`: `open64()` on Linux, `open()` elsewhere.
final _open = libc.libc.lookupFunction<
    Int32 Function(Pointer<pffi.Utf8>, Int32, VarArgs<(Uint32,)>),
    int Function(Pointer<pffi.Utf8>, int, int)>(
  _isLinux && libc.libc.providesSymbol('open64') ? 'open64' : 'open',
);

/// `ASMJIT_FILE64_API(ftruncate)`: `ftruncate64()` on Linux.
final _ftruncate = libc.libc
    .lookupFunction<Int32 Function(Int32, Int64), int Function(int, int)>(
  _isLinux && libc.libc.providesSymbol('ftruncate64')
      ? 'ftruncate64'
      : 'ftruncate',
);

/// `syscall()` (variadic), used for `memfd_create` exactly as upstream.
final _syscallMemfd = libc.libc.lookupFunction<
    Long Function(Long, VarArgs<(Pointer<pffi.Utf8>, Uint32)>),
    int Function(int, Pointer<pffi.Utf8>, int)>('syscall');

DynamicLibrary _shmLibrary() {
  // glibc >= 2.34 provides shm_open() in libc, older versions in librt.
  if (libc.libc.providesSymbol('shm_open')) return libc.libc;
  return DynamicLibrary.open('librt.so.1');
}

final _shmLib = _shmLibrary();
final _shmOpen = _shmLib.lookupFunction<
    Int32 Function(Pointer<pffi.Utf8>, Int32, Uint32),
    int Function(Pointer<pffi.Utf8>, int, int)>('shm_open');
final _shmUnlink = _shmLib.lookupFunction<Int32 Function(Pointer<pffi.Utf8>),
    int Function(Pointer<pffi.Utf8>)>('shm_unlink');

final _errnoLocation = libc.libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
  _isApple
      ? '__error'
      : _isBionic
          ? '__errno'
          : '__errno_location',
);

/// Reads `errno` of the calling thread.
///
/// The Dart VM gives no guarantee that `errno` is preserved between two FFI
/// calls; it's read right after the failing call, which is the best that can
/// be done from Dart.
int _errno() => _errnoLocation().value;

// Apple.
final _pthreadJitWriteProtectNp = DynamicLibrary.process()
    .lookupFunction<Void Function(Int32), void Function(int)>(
  'pthread_jit_write_protect_np',
);
final _sysIcacheInvalidate = DynamicLibrary.process().lookupFunction<
    Void Function(Pointer<Void>, IntPtr),
    void Function(Pointer<Void>, int)>('sys_icache_invalidate');
final _machTaskSelf =
    DynamicLibrary.process().lookup<Uint32>('mach_task_self_');
final _machVmRemap = DynamicLibrary.process().lookupFunction<
    Int32 Function(Uint32, Pointer<Uint64>, Uint64, Uint64, Int32, Uint32,
        Uint64, Int32, Pointer<Int32>, Pointer<Int32>, Uint32),
    int Function(int, Pointer<Uint64>, int, int, int, int, int, int,
        Pointer<Int32>, Pointer<Int32>, int)>('mach_vm_remap');
final _vmProtect = DynamicLibrary.process().lookupFunction<
    Int32 Function(Uint32, UintPtr, UintPtr, Int32, Int32),
    int Function(int, int, int, int, int)>('vm_protect');

/// Linux `__builtin___clear_cache()`: Dart cannot emit the builtin, so the
/// libgcc implementation (`__clear_cache`) is called instead.
final void Function(Pointer<Void>, Pointer<Void>) _clearCache =
    _resolveClearCache();

void Function(Pointer<Void>, Pointer<Void>) _resolveClearCache() {
  // `__clear_cache` lives in libgcc; it is usually already loaded into the
  // process, otherwise fall back to opening libgcc_s explicitly.
  for (final open in <DynamicLibrary Function()>[
    DynamicLibrary.process,
    () => DynamicLibrary.open('libgcc_s.so.1'),
  ]) {
    try {
      final lib = open();
      if (lib.providesSymbol('__clear_cache')) {
        return lib.lookupFunction<Void Function(Pointer<Void>, Pointer<Void>),
            void Function(Pointer<Void>, Pointer<Void>)>('__clear_cache');
      }
    } catch (_) {
      // Try the next candidate.
    }
  }
  throw AsmJitException(
    AsmJitError.invalidState,
    'Unable to resolve __clear_cache for instruction cache maintenance',
  );
}

/// `__NR_memfd_create` of the host architecture (0 if unknown).
int get _nrMemfdCreate {
  switch (Abi.current()) {
    case Abi.linuxX64:
    case Abi.androidX64:
      return 319;
    case Abi.linuxIA32:
    case Abi.androidIA32:
      return 356;
    case Abi.linuxArm64:
    case Abi.androidArm64:
    case Abi.linuxRiscv64:
      return 279;
    case Abi.linuxArm:
    case Abi.androidArm:
      return 385;
    default:
      return 0;
  }
}

// =============================================================================
// Public API - Types
// =============================================================================

/// Describes whether instruction cache should be flushed after a write
/// operation (`VirtMem::CachePolicy`).
enum CachePolicy {
  /// Default policy.
  ///
  /// In some places this would mean [flushAfterWrite] and in some places it
  /// would mean [neverFlush]. For example if it's known that an address has
  /// never been used before to execute code.
  defaultPolicy,

  /// Flush instruction cache after a write operation.
  flushAfterWrite,

  /// Avoid flushing instruction cache after a write operation.
  neverFlush,
}

/// Virtual memory information (`VirtMem::Info`).
class VirtMemInfo {
  /// Virtual memory page size.
  final int pageSize;

  /// Virtual memory page granularity.
  final int pageGranularity;

  const VirtMemInfo({
    required this.pageSize,
    required this.pageGranularity,
  });

  /// Aligns [size] up to page boundary.
  int alignToPage(int size) => (size + pageSize - 1) & ~(pageSize - 1);

  /// Aligns [size] up to granularity boundary.
  int alignToGranularity(int size) =>
      (size + pageGranularity - 1) & ~(pageGranularity - 1);
}

/// Virtual memory access and mmap-specific flags (`VirtMem::MemoryFlags`).
abstract final class MemoryFlags {
  /// No flags.
  static const int kNone = 0;

  /// Memory is readable.
  static const int kAccessRead = 0x00000001;

  /// Memory is writable.
  static const int kAccessWrite = 0x00000002;

  /// Memory is executable.
  static const int kAccessExecute = 0x00000004;

  /// A combination of [kAccessRead] and [kAccessWrite].
  static const int kAccessReadWrite = kAccessRead | kAccessWrite;

  /// A combination of [kAccessRead], [kAccessWrite].
  static const int kAccessRW = kAccessRead | kAccessWrite;

  /// A combination of [kAccessRead] and [kAccessExecute].
  static const int kAccessRX = kAccessRead | kAccessExecute;

  /// A combination of [kAccessRead], [kAccessWrite], and [kAccessExecute].
  static const int kAccessRWX = kAccessRead | kAccessWrite | kAccessExecute;

  /// Use a `MAP_JIT` flag available on Apple platforms (introduced by Mojave),
  /// which allows JIT code to be executed in a MAC bundle.
  ///
  /// This flag may be turned on by the allocator if there is no other way of
  /// allocating executable memory.
  ///
  /// Can only be used with [VirtMem.alloc], `MAP_JIT` only works on OSX and
  /// not on iOS. When a process uses `fork()` the child process has no access
  /// to the pages mapped with `MAP_JIT`.
  static const int kMMapEnableMapJit = 0x00000010;

  /// Pass `PROT_MAX(PROT_READ)` or `PROT_MPROTECT(PROT_READ)` to `mmap()` on
  /// platforms that support it.
  static const int kMMapMaxAccessRead = 0x00000020;

  /// Pass `PROT_MAX(PROT_WRITE)` or `PROT_MPROTECT(PROT_WRITE)` to `mmap()` on
  /// platforms that support it.
  static const int kMMapMaxAccessWrite = 0x00000040;

  /// Pass `PROT_MAX(PROT_EXEC)` or `PROT_MPROTECT(PROT_EXEC)` to `mmap()` on
  /// platforms that support it.
  static const int kMMapMaxAccessExecute = 0x00000080;

  /// A combination of [kMMapMaxAccessRead] and [kMMapMaxAccessWrite].
  static const int kMMapMaxAccessReadWrite =
      kMMapMaxAccessRead | kMMapMaxAccessWrite;

  /// A combination of [kMMapMaxAccessRead] and [kMMapMaxAccessWrite].
  static const int kMMapMaxAccessRW = kMMapMaxAccessRead | kMMapMaxAccessWrite;

  /// A combination of [kMMapMaxAccessRead] and [kMMapMaxAccessExecute].
  static const int kMMapMaxAccessRX =
      kMMapMaxAccessRead | kMMapMaxAccessExecute;

  /// A combination of [kMMapMaxAccessRead], [kMMapMaxAccessWrite],
  /// [kMMapMaxAccessExecute].
  static const int kMMapMaxAccessRWX =
      kMMapMaxAccessRead | kMMapMaxAccessWrite | kMMapMaxAccessExecute;

  /// Use `MAP_SHARED` when calling mmap().
  ///
  /// In some cases `MAP_SHARED` may be set automatically. For example, some
  /// dual mapping implementations must use `MAP_SHARED` instead of
  /// `MAP_PRIVATE` to ensure that the OS would not apply copy on write on RW
  /// page, which would cause RX page not having the updated content.
  static const int kMapShared = 0x00000100;

  /// Request large memory mapped pages.
  ///
  /// If this option is used and large page(s) cannot be mapped, the
  /// allocation will fail. Fallback to regular pages must be done by the user
  /// in this case. Higher level API such as `JitAllocator` provides an
  /// additional mechanism to allocate regular page(s) when large page(s)
  /// allocation fails.
  static const int kMMapLargePages = 0x00000200;

  /// Not an access flag, only used by [VirtMem.allocDualMapping] to override
  /// the default allocation strategy to always use a 'tmp' directory instead
  /// of "/dev/shm" (on POSIX platforms). Ignored if the operating system
  /// allows to allocate an executable memory by a different API than `open()`
  /// or `shm_open()` (on Linux `memfd_create()` is preferred).
  static const int kMappingPreferTmp = 0x80000000;
}

/// Dual memory mapping used to map an anonymous memory into two memory
/// regions where one region is read-only, but executable, and the second
/// region is read+write, but not executable (`VirtMem::DualMapping`).
class DualMapping {
  /// Pointer to data with 'Read+Execute' access (this memory is not writable).
  Pointer<Void> rx;

  /// Pointer to data with 'Read+Write' access (this memory is not executable).
  Pointer<Void> rw;

  DualMapping([Pointer<Void>? rx, Pointer<Void>? rw])
      : rx = rx ?? nullptr,
        rw = rw ?? nullptr;
}

/// Hardened runtime flags (`VirtMem::HardenedRuntimeFlags`).
abstract final class HardenedRuntimeFlags {
  /// No flags.
  static const int kNone = 0;

  /// Hardened runtime is enabled - it's not possible to have "Write & Execute"
  /// memory protection. The runtime enforces W^X (either write or execute).
  ///
  /// If the runtime is hardened it means that an operating system specific
  /// protection is used. For example on Apple OSX it's possible to allocate
  /// memory with MAP_JIT flag and then use `pthread_jit_write_protect_np()` to
  /// temporarily swap access permissions for the current thread. Dual mapping
  /// is also a possibility on X86/X64 architecture.
  static const int kEnabled = 0x00000001;

  /// Read+Write+Execute can only be allocated with MAP_JIT flag (Apple
  /// specific, only available on Apple platforms).
  static const int kMapJit = 0x00000002;

  /// Read+Write+Execute can be allocated with dual mapping approach (one
  /// region with RW and the other with RX).
  static const int kDualMapping = 0x00000004;
}

/// Hardened runtime information (`VirtMem::HardenedRuntimeInfo`).
class HardenedRuntimeInfo {
  /// Hardened runtime flags, see [HardenedRuntimeFlags].
  final int flags;

  const HardenedRuntimeInfo(this.flags);

  /// Tests whether the hardened runtime `flag` is set.
  bool hasFlag(int flag) => (flags & flag) != 0;
}

/// Values that can be used with [VirtMem.protectJitMemory]
/// (`VirtMem::ProtectJitAccess`).
enum ProtectJitAccess {
  /// Protect JIT memory with Read+Write permissions.
  readWrite(0),

  /// Protect JIT memory with Read+Execute permissions.
  readExecute(1);

  const ProtectJitAccess(this.value);

  /// The value passed to `pthread_jit_write_protect_np()`.
  final int value;
}

/// JIT protection scope that prepares the given memory block to be written to
/// in the current thread (`VirtMem::ProtectJitReadWriteScope`).
///
/// It calls `VirtMem.protectJitMemory(ProtectJitAccess.readWrite)` at
/// construction time and `VirtMem.protectJitMemory(ProtectJitAccess.readExecute)`
/// combined with [VirtMem.flushInstructionCache] in [close] (the upstream
/// destructor). Dart has no destructors, so always pair it with `try/finally`:
///
/// ```dart
/// final scope = ProtectJitReadWriteScope(rx, size);
/// try {
///   // write to the RW pointer
/// } finally {
///   scope.close();
/// }
/// ```
///
/// The code between the constructor and [close] must be synchronous: the
/// write protection is per thread, and an isolate only stays on the same OS
/// thread while it doesn't yield to the event loop.
final class ProtectJitReadWriteScope {
  final Pointer<Void> _rxPtr;
  final int _size;
  final CachePolicy _policy;

  /// Makes the given memory block RW protected.
  ProtectJitReadWriteScope(
    this._rxPtr,
    this._size, [
    this._policy = CachePolicy.defaultPolicy,
  ]) {
    VirtMem.protectJitMemory(ProtectJitAccess.readWrite);
  }

  /// Makes the memory block RX protected again and flushes instruction cache.
  void close() {
    VirtMem.protectJitMemory(ProtectJitAccess.readExecute);

    if (_policy != CachePolicy.neverFlush) {
      VirtMem.flushInstructionCache(_rxPtr, _size);
    }
  }
}

// =============================================================================
// Virtual Memory Utilities
// =============================================================================

const List<int> _dualMappingFilter = [
  MemoryFlags.kAccessWrite | MemoryFlags.kMMapMaxAccessWrite,
  MemoryFlags.kAccessExecute | MemoryFlags.kMMapMaxAccessExecute,
];

bool _test(int a, int b) => (a & b) != 0;

bool _isPowerOf2(int x) => x != 0 && (x & (x - 1)) == 0;

int _alignUpPowerOf2(int x) {
  var v = x - 1;
  v |= v >> 1;
  v |= v >> 2;
  v |= v >> 4;
  v |= v >> 8;
  v |= v >> 16;
  v |= v >> 32;
  return v + 1;
}

int _ctz(int x) {
  var n = 0;
  while ((x & 1) == 0) {
    x >>>= 1;
    n++;
  }
  return n;
}

// =============================================================================
// Virtual Memory [Windows]
// =============================================================================

VirtMemInfo _detectVmInfoWindows() {
  final systemInfo = pffi.calloc<_SystemInfo>();
  try {
    _getSystemInfo(systemInfo);
    return VirtMemInfo(
      pageSize: _alignUpPowerOf2(systemInfo.ref.dwPageSize),
      pageGranularity: systemInfo.ref.dwAllocationGranularity,
    );
  } finally {
    pffi.calloc.free(systemInfo);
  }
}

/// Returns windows-specific protect flags from [MemoryFlags].
int _protectFlagsFromMemoryFlags(int memoryFlags) {
  int protectFlags;

  // READ|WRITE|EXECUTE.
  if (_test(memoryFlags, MemoryFlags.kAccessExecute)) {
    protectFlags = _test(memoryFlags, MemoryFlags.kAccessWrite)
        ? _kPageExecuteReadWrite
        : _kPageExecuteRead;
  } else if (_test(memoryFlags, MemoryFlags.kAccessRW)) {
    protectFlags = _test(memoryFlags, MemoryFlags.kAccessWrite)
        ? _kPageReadWrite
        : _kPageReadOnly;
  } else {
    protectFlags = _kPageNoAccess;
  }

  // Any other flags to consider?
  return protectFlags;
}

int _desiredAccessFromMemoryFlags(int memoryFlags) {
  var access = _test(memoryFlags, MemoryFlags.kAccessWrite)
      ? _kFileMapWrite
      : _kFileMapRead;
  if (_test(memoryFlags, MemoryFlags.kAccessExecute)) {
    access |= _kFileMapExecute;
  }
  return access;
}

(AsmJitError, Pointer<Void>) _allocWindows(int size, int memoryFlags) {
  if (size == 0) return (AsmJitError.invalidArgument, nullptr);

  var allocationType = _kMemCommit | _kMemReserve;
  final protectFlags = _protectFlagsFromMemoryFlags(memoryFlags);

  if (_test(memoryFlags, MemoryFlags.kMMapLargePages)) {
    final lpSize = VirtMem.largePageSize();

    // Does it make sense to call VirtualAlloc() if we failed to query large
    // page size?
    if (lpSize == 0) return (AsmJitError.featureNotEnabled, nullptr);
    if (size % lpSize != 0) return (AsmJitError.invalidArgument, nullptr);

    allocationType |= _kMemLargePages;
  }

  final result = _virtualAlloc(nullptr, size, allocationType, protectFlags);
  if (result == nullptr) return (AsmJitError.outOfMemory, nullptr);

  return (AsmJitError.ok, result);
}

AsmJitError _releaseWindows(Pointer<Void> p, int size) {
  // NOTE: If the `dwFreeType` parameter is MEM_RELEASE, `size` parameter must
  // be zero.
  if (_virtualFree(p, 0, _kMemRelease) == 0) {
    return AsmJitError.invalidArgument;
  }
  return AsmJitError.ok;
}

AsmJitError _protectWindows(Pointer<Void> p, int size, int memoryFlags) {
  final protectFlags = _protectFlagsFromMemoryFlags(memoryFlags);
  final oldFlags = pffi.calloc<Uint32>();
  try {
    if (_virtualProtect(p, size, protectFlags, oldFlags) != 0) {
      return AsmJitError.ok;
    }
    return AsmJitError.invalidArgument;
  } finally {
    pffi.calloc.free(oldFlags);
  }
}

AsmJitError _allocDualMappingWindows(
    DualMapping dm, int size, int memoryFlags) {
  dm.rx = nullptr;
  dm.rw = nullptr;

  if (size == 0) return AsmJitError.invalidArgument;

  // ScopedHandle.
  final handle = _createFileMappingW(
    Pointer<Void>.fromAddress(-1), // INVALID_HANDLE_VALUE
    nullptr,
    _kPageExecuteReadWrite,
    (size >>> 32) & 0xFFFFFFFF,
    size & 0xFFFFFFFF,
    nullptr,
  );

  if (handle == nullptr) return AsmJitError.outOfMemory;

  try {
    final ptr = <Pointer<Void>>[nullptr, nullptr];
    for (var i = 0; i < 2; i++) {
      final accessFlags = memoryFlags & ~_dualMappingFilter[i];
      final desiredAccess = _desiredAccessFromMemoryFlags(accessFlags);
      ptr[i] = _mapViewOfFile(handle, desiredAccess, 0, 0, size);

      if (ptr[i] == nullptr) {
        if (i == 1) _unmapViewOfFile(ptr[0]);
        return AsmJitError.outOfMemory;
      }
    }

    dm.rx = ptr[0];
    dm.rw = ptr[1];
    return AsmJitError.ok;
  } finally {
    _closeHandle(handle);
  }
}

AsmJitError _releaseDualMappingWindows(DualMapping dm, int size) {
  var failed = false;

  if (_unmapViewOfFile(dm.rx) == 0) failed = true;
  if (dm.rx != dm.rw && _unmapViewOfFile(dm.rw) == 0) failed = true;

  if (failed) return AsmJitError.invalidArgument;

  dm.rx = nullptr;
  dm.rw = nullptr;
  return AsmJitError.ok;
}

// =============================================================================
// Virtual Memory [Unix] - Utilities
// =============================================================================

/// Kernel version as returned by `uname()` (`KernelVersion`).
final class _KernelVersion {
  final int major;
  final int minor;

  const _KernelVersion(this.major, this.minor);

  bool ge(int major, int minor) =>
      this.major > major || (this.major == major && this.minor >= minor);
}

_KernelVersion _getKernelVersion() {
  // `struct utsname` has 5 fields of 256 characters on Apple platforms and 6
  // fields of 65 characters on Linux; `release` is the third field.
  final fieldSize = _isApple ? 256 : 65;
  final buf = pffi.calloc<Uint8>(fieldSize * 6);
  final ver = [0, 0];
  try {
    _uname(buf);

    final release = buf + fieldSize * 2;
    var p = 0;
    var i = 0;

    while (p < fieldSize && release[p] != 0 && i < 2) {
      final c = release[p];
      if (c >= 0x30 && c <= 0x39) {
        // strtol(p, &p, 10)
        var value = 0;
        while (p < fieldSize && release[p] >= 0x30 && release[p] <= 0x39) {
          value = value * 10 + (release[p] - 0x30);
          p++;
        }
        ver[i++] = value;
        continue;
      }
      p++;
    }
  } finally {
    pffi.calloc.free(buf);
  }
  return _KernelVersion(ver[0], ver[1]);
}

/// Translates libc errors specific to VirtualMemory mapping to [AsmJitError].
AsmJitError _asmjitErrorFromErrno(int e) {
  if (e == _kEAcces || e == _kEAgain || e == _kENoDev || e == _kEPerm) {
    return AsmJitError.invalidState;
  }
  if (e == _kEFBig || e == _kENoMem || e == _kEOverflow) {
    return AsmJitError.outOfMemory;
  }
  if (e == _kEMFile || e == _kENFile) {
    return AsmJitError.tooManyHandles;
  }
  return AsmJitError.invalidArgument;
}

/// Returns `mmap()` protection flags from [MemoryFlags].
int _mmProtFromMemoryFlags(int memoryFlags) {
  var protection = 0;
  if (_test(memoryFlags, MemoryFlags.kAccessRead)) protection |= _kProtRead;
  if (_test(memoryFlags, MemoryFlags.kAccessWrite)) {
    protection |= _kProtRead | _kProtWrite;
  }
  if (_test(memoryFlags, MemoryFlags.kAccessExecute)) {
    protection |= _kProtRead | _kProtExec;
  }
  return protection;
}

/// Returns maximum protection flags from `memoryFlags`.
///
/// Upstream uses `PROT_MPROTECT()` on NetBSD and `PROT_MAX()` on other BSDs;
/// neither is defined on the platforms the Dart VM supports, so this is
/// always 0 (as upstream on Linux and Apple platforms).
int _mmMaxProtFromMemoryFlags(int memoryFlags) => 0;

VirtMemInfo _detectVmInfoPosix() {
  final pageSize = _getpagesize();
  return VirtMemInfo(
    pageSize: pageSize,
    pageGranularity: pageSize > 65536 ? pageSize : 65536,
  );
}

int _detectLargePageSize() {
  if (Platform.isWindows) return _getLargePageMinimum();

  // `defined(__APPLE__) && defined(VM_FLAGS_SUPERPAGE_SIZE_2MB) && X86`.
  if (_isApple && _hostIsX86) return 2 * 1024 * 1024;

  if (_isLinux) {
    // OSUtils::read_file(path, storage, 16).
    List<int> storage;
    try {
      storage = File('/sys/kernel/mm/transparent_hugepage/hpage_pmd_size')
          .readAsBytesSync();
    } catch (_) {
      return 0;
    }
    if (storage.isEmpty) return 0;
    if (storage.length > 16) storage = storage.sublist(0, 16);

    // The first value should be the size of the page (hpage_pmd_size).
    var largePageSize = 0;
    for (final c in storage) {
      final digit = c - 0x30;
      if (digit < 0 || digit >= 10) break;
      largePageSize = largePageSize * 10 + digit;
    }

    return _isPowerOf2(largePageSize) ? largePageSize : 0;
  }

  return 0;
}

// =============================================================================
// Virtual Memory [Posix] - Anonymous Memory
// =============================================================================

/// Some operating systems don't allow /dev/shm to be executable. On Linux
/// this happens when /dev/shm is mounted with 'noexec', which is enforced by
/// systemd. Other operating systems like MacOS also restrict executable
/// permissions regarding /dev/shm, so we use a runtime detection before
/// attempting to allocate executable memory.
enum _AnonymousMemoryStrategy { unknown, devShm, tmpDir }

String _getTmpDir() => Platform.environment['TMPDIR'] ?? '/tmp';

/// 0 = unknown, 1 = MFD_EXEC not supported, 2 = supported.
int _cachedMfdExecSupported = 0;

int _getMfdExecFlag() {
  var val = _cachedMfdExecSupported;
  if (val == 0) {
    final ver = _getKernelVersion();
    val = (ver.ge(6, 3) ? 1 : 0) + 1;
    _cachedMfdExecSupported = val;
  }
  return val == 2 ? _kMfdExec : 0;
}

int _randomBitsCounter = 0;

/// It's not fully random, just to avoid collisions when opening TMP or SHM
/// file (`generate_random_bits()`).
///
/// Upstream mixes the stack pointer with `rdtsc` (x86) or `gettimeofday()`;
/// Dart has neither the stack pointer nor `rdtsc`, so an identity hash of the
/// calling object and the current time are used.
int _generateRandomBits(int stackPtr, int attempt) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final mix = (now % 1000000) ^ (now ~/ 1000000);

  var bits = (stackPtr & 0x1010505000055590) - mix * 773703683;
  bits = (bits >>> 33) ^ (bits << 7) ^ (attempt * 87178291199);
  return bits + (++_randomBitsCounter) * 10619863;
}

String _formatShmId(int bits) {
  final hi = (bits >>> 32).toRadixString(16).padLeft(8, '0');
  final lo = (bits & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '/shm-id-${(hi + lo).toUpperCase()}';
}

/// Zero initialized, if ever changed to `true` that would mean the syscall is
/// not available and we must use `shm_open()` and `shm_unlink()` (or regular
/// `open()`).
bool _memfdCreateNotSupported = false;

enum _FileType { none, shm, tmp }

final class _AnonymousMemory {
  int _fd = -1;
  _FileType _fileType = _FileType.none;
  String _tmpName = '';

  int get fd => _fd;

  /// The upstream destructor.
  void dispose() {
    unlink();
    close();
  }

  AsmJitError open(bool preferTmpOverDevShm) {
    if (_isLinux && _nrMemfdCreate != 0) {
      // Linux specific 'memfd_create' - if the syscall returns `ENOSYS` it
      // means it's not available and we will never call it again (would be
      // pointless).
      if (!_memfdCreateNotSupported) {
        final name = 'vmem'.toNativeUtf8();
        try {
          _fd = _syscallMemfd(
              _nrMemfdCreate, name, _kMfdCloexec | _getMfdExecFlag());
          if (_fd >= 0) return AsmJitError.ok;

          final e = _errno();
          if (e == _kENoSys) {
            _memfdCreateNotSupported = true;
          } else {
            return _asmjitErrorFromErrno(e);
          }
        } finally {
          pffi.malloc.free(name);
        }
      }
    }

    // POSIX API. We have to generate somehow a unique name, so use
    // `_generateRandomBits()` helper. To prevent having file collisions we use
    // `shm_open()` with flags that require creation of the file so we never
    // open an existing shared memory.
    const retryCount = 100;

    for (var i = 0; i < retryCount; i++) {
      final useTmp = !_vmShmDetect || preferTmpOverDevShm;
      final bits = _generateRandomBits(identityHashCode(this), i);

      if (useTmp) {
        _tmpName = _getTmpDir() + _formatShmId(bits);
        final name = _tmpName.toNativeUtf8();
        try {
          _fd = _open(name, _kORdWr | _kOCreat | _kOExcl, 0);
        } finally {
          pffi.malloc.free(name);
        }
        if (_fd >= 0) {
          _fileType = _FileType.tmp;
          return AsmJitError.ok;
        }
      } else if (_hasShmOpen) {
        _tmpName = _formatShmId(bits);
        final name = _tmpName.toNativeUtf8();
        try {
          _fd = _shmOpen(name, _kORdWr | _kOCreat | _kOExcl, _kSIRUsrIWUsr);
        } finally {
          pffi.malloc.free(name);
        }
        if (_fd >= 0) {
          _fileType = _FileType.shm;
          return AsmJitError.ok;
        }
      }

      final e = _errno();
      if (e != _kEExist) return _asmjitErrorFromErrno(e);
    }

    return AsmJitError.failedToOpenAnonymousMemory;
  }

  void unlink() {
    final type = _fileType;
    _fileType = _FileType.none;

    if (type == _FileType.none) return;

    final name = _tmpName.toNativeUtf8();
    try {
      if (_hasShmOpen && type == _FileType.shm) {
        _shmUnlink(name);
        return;
      }
      if (type == _FileType.tmp) {
        _unlink(name);
        return;
      }
    } finally {
      pffi.malloc.free(name);
    }
  }

  void close() {
    if (_fd >= 0) {
      _close(_fd);
      _fd = -1;
    }
  }

  AsmJitError allocate(int size) {
    // TODO: Improve this by using `posix_fallocate()` when available.
    if (_ftruncate(_fd, size) != 0) {
      return _asmjitErrorFromErrno(_errno());
    }
    return AsmJitError.ok;
  }
}

(AsmJitError, _AnonymousMemoryStrategy) _detectAnonymousMemoryStrategy() {
  final anonMem = _AnonymousMemory();
  try {
    final vmInfo = VirtMem.info();

    var err = anonMem.open(false);
    if (err != AsmJitError.ok) return (err, _AnonymousMemoryStrategy.unknown);
    err = anonMem.allocate(vmInfo.pageSize);
    if (err != AsmJitError.ok) return (err, _AnonymousMemoryStrategy.unknown);

    final ptr = _mmap(nullptr, vmInfo.pageSize, _kProtRead | _kProtExec,
        _kMapShared, anonMem.fd, 0);
    if (ptr.address == _kMapFailed) {
      final e = _errno();
      if (e == _kEInval) {
        return (AsmJitError.ok, _AnonymousMemoryStrategy.tmpDir);
      }
      return (_asmjitErrorFromErrno(e), _AnonymousMemoryStrategy.unknown);
    } else {
      _munmap(ptr, vmInfo.pageSize);
      return (AsmJitError.ok, _AnonymousMemoryStrategy.devShm);
    }
  } finally {
    anonMem.dispose();
  }
}

_AnonymousMemoryStrategy _cachedStrategy = _AnonymousMemoryStrategy.unknown;

(AsmJitError, _AnonymousMemoryStrategy) _getAnonymousMemoryStrategy() {
  if (_vmShmDetect) {
    // Initially don't assume anything. It has to be tested whether
    // '/dev/shm' was mounted with 'noexec' flag or not.
    var strategy = _cachedStrategy;
    if (strategy == _AnonymousMemoryStrategy.unknown) {
      final (err, detected) = _detectAnonymousMemoryStrategy();
      if (err != AsmJitError.ok) return (err, strategy);
      strategy = detected;
      _cachedStrategy = strategy;
    }
    return (AsmJitError.ok, strategy);
  }
  return (AsmJitError.ok, _AnonymousMemoryStrategy.tmpDir);
}

// =============================================================================
// Virtual Memory [Posix] - Hardened Runtime & MAP_JIT
// =============================================================================

/// 0 = unknown, 1 = disabled, 2 = enabled.
int _cachedHardenedFlag = 0;

/// Detects whether the current process is hardened, which means that pages
/// that have WRITE and EXECUTABLE flags cannot be normally allocated. On OSX
/// + AArch64 such allocation requires MAP_JIT flag, other platforms don't
/// support this combination.
bool _hasHardenedRuntime() {
  // OSX on AArch64 has always hardened runtime enabled.
  if (_isMacOS && _hostIsArm64) return true;

  const hfUnknown = 0;
  const hfDisabled = 1;
  const hfEnabled = 2;

  var flag = _cachedHardenedFlag;
  if (flag == hfUnknown) {
    final pageSize = _getpagesize();
    final ptr = _mmap(nullptr, pageSize, _kProtRead | _kProtWrite | _kProtExec,
        _kMapPrivate | _kMapAnonymous, -1, 0);

    if (ptr.address == _kMapFailed) {
      flag = hfEnabled;
    } else {
      flag = hfDisabled;
      _munmap(ptr, pageSize);
    }

    _cachedHardenedFlag = flag;
  }

  return flag == hfEnabled;
}

/// 0 = unknown, 1 = not supported, 2 = supported.
int _cachedMapJitSupport = 0;

/// Detects whether MAP_JIT is available.
bool _hasMapJitSupport() {
  if (_isMacOS && !_hostIsX86) {
    // Apple platforms always use hardened runtime + MAP_JIT on non-x86
    // hardware:
    // https://developer.apple.com/documentation/apple_silicon/porting_just-in-time_compilers_to_apple_silicon
    return true;
  }

  if (_isMacOS) {
    // MAP_JIT flag required to run unsigned JIT code is only supported by
    // kernel version 10.14+ (Mojave).
    var val = _cachedMapJitSupport;
    if (val == 0) {
      final ver = _getKernelVersion();
      val = (ver.ge(18, 0) ? 1 : 0) + 1;
      _cachedMapJitSupport = val;
    }
    return val == 2;
  }

  // MAP_JIT is not available (it's only available on OSX).
  return false;
}

/// Returns either MAP_JIT or 0 based on `memoryFlags` and the host operating
/// system.
int _mmMapJitFromMemoryFlags(int memoryFlags) {
  if (!_isApple) return 0;

  // Always use MAP_JIT flag if user asked for it (could be used for testing on
  // non-hardened processes) and detect whether it must be used when the
  // process is actually hardened (in that case it doesn't make sense to rely
  // on user `memoryFlags`).
  //
  // MAP_JIT is not required when dual-mapping memory and is incompatible with
  // MAP_SHARED, so it will not be added when the latter is enabled.
  final useMapJit = (_test(memoryFlags, MemoryFlags.kMMapEnableMapJit) ||
          _hasHardenedRuntime()) &&
      !_test(memoryFlags, MemoryFlags.kMapShared);

  if (useMapJit) return _hasMapJitSupport() ? _kMapJit : 0;
  return 0;
}

bool _hasDualMappingSupport() {
  if (Platform.isWindows) {
    // TODO: This assumption works on X86 platforms, this may not work on
    // AArch64.
    return true;
  }
  return !_noDualMapping;
}

int _getHardenedRuntimeFlags() {
  var flags = HardenedRuntimeFlags.kNone;

  if (Platform.isWindows) {
    if (_hasDualMappingSupport()) flags |= HardenedRuntimeFlags.kDualMapping;
    return flags;
  }

  if (_hasHardenedRuntime()) flags |= HardenedRuntimeFlags.kEnabled;
  if (_hasMapJitSupport()) flags |= HardenedRuntimeFlags.kMapJit;
  if (_hasDualMappingSupport()) flags |= HardenedRuntimeFlags.kDualMapping;

  return flags;
}

(AsmJitError, Pointer<Void>) _mapMemory(int size, int memoryFlags,
    [int fd = -1, int offset = 0]) {
  if (size == 0) return (AsmJitError.invalidArgument, nullptr);

  final protection = _mmProtFromMemoryFlags(memoryFlags) |
      _mmMaxProtFromMemoryFlags(memoryFlags);
  var mmFlags = _mmMapJitFromMemoryFlags(memoryFlags);

  mmFlags |=
      _test(memoryFlags, MemoryFlags.kMapShared) ? _kMapShared : _kMapPrivate;
  if (fd == -1) mmFlags |= _kMapAnonymous;

  final useLargePages = _test(memoryFlags, MemoryFlags.kMMapLargePages);

  if (useLargePages) {
    if (_isLinux) {
      final lpSize = VirtMem.largePageSize();
      if (lpSize == 0) return (AsmJitError.featureNotEnabled, nullptr);
      if (size % lpSize != 0) return (AsmJitError.invalidArgument, nullptr);

      final lpSizeLog2 = _ctz(lpSize);
      mmFlags |= _kMapHugeTlb | (lpSizeLog2 << _kMapHugeShift);
    } else {
      return (AsmJitError.featureNotEnabled, nullptr);
    }
  }

  final ptr = _mmap(nullptr, size, protection, mmFlags, fd, offset);
  if (ptr.address == _kMapFailed) {
    return (_asmjitErrorFromErrno(_errno()), nullptr);
  }

  // `#if defined(MADV_HUGEPAGE)` - Linux.
  if (useLargePages && _isLinux) _madvise(ptr, size, _kMadvHugePage);

  return (AsmJitError.ok, ptr);
}

AsmJitError _unmapMemory(Pointer<Void> p, int size) {
  if (_munmap(p, size) != 0) return _asmjitErrorFromErrno(_errno());
  return AsmJitError.ok;
}

// =============================================================================
// Virtual Memory [Posix] - Dual Mapping
// =============================================================================

AsmJitError _unmapDualMapping(DualMapping dm, int size) {
  final err1 = _unmapMemory(dm.rx, size);
  var err2 = AsmJitError.ok;

  if (dm.rx != dm.rw) err2 = _unmapMemory(dm.rw, size);

  // We can report only one error, so report the first...
  if (err1 != AsmJitError.ok || err2 != AsmJitError.ok) {
    return err1 != AsmJitError.ok ? err1 : err2;
  }

  dm.rx = nullptr;
  dm.rw = nullptr;
  return AsmJitError.ok;
}

AsmJitError _asmjitErrorFromKernResult(int result) {
  switch (result) {
    case _kKernProtectionFailure:
      return AsmJitError.protectionFailure;
    case _kKernNoSpace:
      return AsmJitError.outOfMemory;
    case _kKernInvalidArgument:
      return AsmJitError.invalidArgument;
    default:
      return AsmJitError.invalidState;
  }
}

AsmJitError _allocDualMappingUsingMachVmRemap(
    DualMapping dmOut, int size, int memoryFlags) {
  final dm = DualMapping();
  final mmapFlags =
      MemoryFlags.kAccessReadWrite | (memoryFlags & MemoryFlags.kMapShared);

  final (mapErr, rx) = _mapMemory(size, mmapFlags);
  if (mapErr != AsmJitError.ok) return mapErr;
  dm.rx = rx;

  final curProt = pffi.calloc<Int32>();
  final maxProt = pffi.calloc<Int32>();
  final remappedAddr = pffi.calloc<Uint64>();

  try {
    const rwProtectFlags = _kVmProtRead | _kVmProtWrite;
    var rxProtectFlags = _kVmProtRead;

    if (_test(memoryFlags, MemoryFlags.kAccessExecute)) {
      rxProtectFlags |= _kVmProtExecute;
    }

    var result = _kKernSuccess;
    do {
      final task = _machTaskSelf.value;
      remappedAddr.value = 0;

      const remapFlags = _kVmFlagsAnywhere | _kVmFlagsRandomAddr;

      // Try to remap the existing memory into a different address.
      result = _machVmRemap(
        task, // target_task
        remappedAddr, // target_address
        size, // size
        0, // mask
        remapFlags, // flags
        task, // src_task
        dm.rx.address, // src_address
        0, // copy
        curProt, // cur_protection
        maxProt, // max_protection
        _kVmInheritDefault, // inheritance
      );

      if (result != _kKernSuccess) break;

      dm.rw = Pointer<Void>.fromAddress(remappedAddr.value);

      // Now, try to change permissions of both map regions into RW and RX.
      // The vm_protect() API is used twice as we also want to set maximum
      // permissions, so nobody would be allowed to change the RX region back
      // to RW or RWX (if RWX is allowed).
      for (var i = 0; i < 2; i++) {
        final setMaximum = i == 0 ? 1 : 0;

        result = _vmProtect(task, dm.rx.address, size, setMaximum,
            rxProtectFlags); // target_task, address, size, set_maximum, prot
        if (result != _kKernSuccess) break;

        result = _vmProtect(task, dm.rw.address, size, setMaximum,
            rwProtectFlags); // target_task, address, size, set_maximum, prot
        if (result != _kKernSuccess) break;
      }
    } while (false);

    if (result != _kKernSuccess) {
      _unmapDualMapping(dm, size);
      return _asmjitErrorFromKernResult(result);
    }

    dmOut.rx = dm.rx;
    dmOut.rw = dm.rw;
    return AsmJitError.ok;
  } finally {
    pffi.calloc.free(curProt);
    pffi.calloc.free(maxProt);
    pffi.calloc.free(remappedAddr);
  }
}

AsmJitError _allocDualMappingUsingFile(
    DualMapping dm, int size, int memoryFlags) {
  var preferTmpOverDevShm = _test(memoryFlags, MemoryFlags.kMappingPreferTmp);
  if (!preferTmpOverDevShm) {
    final (err, strategy) = _getAnonymousMemoryStrategy();
    if (err != AsmJitError.ok) return err;
    preferTmpOverDevShm = strategy == _AnonymousMemoryStrategy.tmpDir;
  }

  final anonMem = _AnonymousMemory();
  try {
    var err = anonMem.open(preferTmpOverDevShm);
    if (err != AsmJitError.ok) return err;
    err = anonMem.allocate(size);
    if (err != AsmJitError.ok) return err;

    final ptr = <Pointer<Void>>[nullptr, nullptr];
    for (var i = 0; i < 2; i++) {
      final restrictedMemoryFlags = memoryFlags & ~_dualMappingFilter[i];
      final (mapErr, p) = _mapMemory(
          size, restrictedMemoryFlags | MemoryFlags.kMapShared, anonMem.fd, 0);
      if (mapErr != AsmJitError.ok) {
        if (i == 1) _unmapMemory(ptr[0], size);
        return mapErr;
      }
      ptr[i] = p;
    }

    dm.rx = ptr[0];
    dm.rw = ptr[1];
    return AsmJitError.ok;
  } finally {
    anonMem.dispose();
  }
}

// =============================================================================
// Public API - VirtMem
// =============================================================================

/// Virtual memory management (`VirtMem` namespace).
abstract final class VirtMem {
  static VirtMemInfo? _vmInfo;

  /// Cached large page size, `1` means "not available".
  static int _largePageSize = 0;

  /// Flushes instruction cache in the given region.
  ///
  /// Only useful on non-x86 architectures, however, it's a good practice to
  /// call it on any platform to make your code more portable.
  static void flushInstructionCache(Pointer<Void> p, int size) {
    if (_hostIsX86) {
      // X86|X86_64 architecture doesn't require to do anything to flush
      // instruction cache.
      return;
    }

    if (_isApple) {
      _sysIcacheInvalidate(p, size);
    } else if (Platform.isWindows) {
      // Windows has a built-in support in `kernel32.dll`.
      _flushInstructionCacheWin(_getCurrentProcess(), p, size);
    } else {
      _clearCache(p, Pointer<Void>.fromAddress(p.address + size));
    }
  }

  /// Returns virtual memory information, see [VirtMemInfo] for more details.
  static VirtMemInfo info() => _vmInfo ??=
      Platform.isWindows ? _detectVmInfoWindows() : _detectVmInfoPosix();

  /// Returns the size of the smallest large page supported.
  ///
  /// AsmJit only uses the smallest large page at the moment as these are
  /// usually perfectly sized for executable memory allocation (standard size
  /// is 2MB, but different sizes are possible).
  ///
  /// Returns either the detected large page size or 0, if large page support
  /// is either not supported by AsmJit or not accessible to the process.
  static int largePageSize() {
    const notAvailable = 1;

    var size = _largePageSize;
    if (size > notAvailable) return size;
    if (size == notAvailable) return 0;

    size = _detectLargePageSize();
    _largePageSize = size != 0 ? size : notAvailable;
    return size;
  }

  /// Allocates virtual memory by either using `mmap()` (POSIX) or
  /// `VirtualAlloc()` (Windows).
  ///
  /// `size` should be aligned to page size, use [VirtMem.info] to obtain it.
  /// Invalid size will not be corrected by the implementation and the
  /// allocation would not succeed in such case.
  ///
  /// Returns the error code and the allocated pointer (`nullptr` on failure).
  static (AsmJitError, Pointer<Void>) alloc(int size, int memoryFlags) {
    if (Platform.isWindows) return _allocWindows(size, memoryFlags);
    return _mapMemory(size, memoryFlags);
  }

  /// Releases virtual memory previously allocated by [VirtMem.alloc].
  ///
  /// The size must be the same as used by [VirtMem.alloc]. If the size is not
  /// the same value the call will fail on any POSIX system, but pass on
  /// Windows, because it's implemented differently.
  static AsmJitError release(Pointer<Void> p, int size) {
    if (Platform.isWindows) return _releaseWindows(p, size);
    return _unmapMemory(p, size);
  }

  /// A cross-platform wrapper around `mprotect()` (POSIX) and
  /// `VirtualProtect()` (Windows).
  static AsmJitError protect(Pointer<Void> p, int size, int memoryFlags) {
    if (Platform.isWindows) return _protectWindows(p, size, memoryFlags);

    final protection = _mmProtFromMemoryFlags(memoryFlags);
    if (_mprotect(p, size, protection) == 0) return AsmJitError.ok;
    return _asmjitErrorFromErrno(_errno());
  }

  /// Allocates virtual memory and creates two views of it where the first
  /// view has no write access. This is an addition to the API that should be
  /// used in cases in which the operating system either enforces W^X security
  /// policy or the application wants to use this policy by default to improve
  /// security and prevent an accidental (or purposed) self-modifying code.
  ///
  /// The memory returned in the `dm` are two independent mappings of the same
  /// shared memory region. You must use [VirtMem.releaseDualMapping] to
  /// release it when it's no longer needed. Never use [VirtMem.release] to
  /// release the memory returned by `allocDualMapping()` as that would fail on
  /// Windows.
  ///
  /// Both pointers in `dm` would be set to `nullptr` if the function fails.
  static AsmJitError allocDualMapping(
      DualMapping dm, int size, int memoryFlags) {
    dm.rx = nullptr;
    dm.rw = nullptr;

    if (Platform.isWindows) {
      return _allocDualMappingWindows(dm, size, memoryFlags);
    }

    if (_noDualMapping) return AsmJitError.featureNotEnabled;

    if (size <= 0) {
      return size == 0 ? AsmJitError.invalidArgument : AsmJitError.tooLarge;
    }

    if (_useMachVmRemap) {
      return _allocDualMappingUsingMachVmRemap(dm, size, memoryFlags);
    }
    return _allocDualMappingUsingFile(dm, size, memoryFlags);
  }

  /// Releases virtual memory mapping previously allocated by
  /// [VirtMem.allocDualMapping].
  ///
  /// Both pointers in `dm` would be set to `nullptr` if the function succeeds.
  static AsmJitError releaseDualMapping(DualMapping dm, int size) {
    if (Platform.isWindows) return _releaseDualMappingWindows(dm, size);
    if (_noDualMapping) return AsmJitError.featureNotEnabled;
    return _unmapDualMapping(dm, size);
  }

  /// Returns runtime features provided by the OS.
  static HardenedRuntimeInfo hardenedRuntimeInfo() =>
      HardenedRuntimeInfo(_getHardenedRuntimeFlags());

  /// Protects access of memory mapped with MAP_JIT flag for the current
  /// thread.
  ///
  /// This feature is only available on Apple hardware (AArch64) at the moment
  /// and uses a non-portable `pthread_jit_write_protect_np()` call when
  /// available.
  ///
  /// This function must be called before and after a memory mapped with
  /// MAP_JIT flag is modified. Example:
  ///
  /// ```dart
  /// VirtMem.protectJitMemory(ProtectJitAccess.readWrite);
  /// codePtr.asTypedList(size).setAll(0, source);
  /// VirtMem.protectJitMemory(ProtectJitAccess.readExecute);
  /// VirtMem.flushInstructionCache(codePtr.cast(), size);
  /// ```
  ///
  /// See [ProtectJitReadWriteScope], which makes it simpler than the code
  /// above.
  ///
  /// The permission is per thread: code between the two calls must not yield
  /// to the event loop (it must be synchronous). The Dart VM's own code is
  /// not affected (it is not mapped RWX), which has been verified on the
  /// Apple Silicon SDKs this package is tested with.
  static void protectJitMemory(ProtectJitAccess access) {
    if (_hasPthreadJitWriteProtectNp) {
      _pthreadJitWriteProtectNp(access.value);
    }
  }
}
