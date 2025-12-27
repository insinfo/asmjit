/// AsmJit CPU Info
///
/// Detects CPU features for x86/x64.
/// Uses CPUID instruction via a small JIT-compiled helper.

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'virtmem.dart';

/// CPU feature flags.
class CpuFeatures {
  // Basic features (CPUID.1:ECX)
  final bool sse3;
  final bool pclmulqdq;
  final bool ssse3;
  final bool fma;
  final bool sse41;
  final bool sse42;
  final bool popcnt;
  final bool aesni;
  final bool avx;
  final bool f16c;
  final bool rdrand;

  // Basic features (CPUID.1:EDX)
  final bool fpu;
  final bool cmov;
  final bool mmx;
  final bool fxsr;
  final bool sse;
  final bool sse2;

  // Extended features (CPUID.7.0:EBX)
  final bool bmi1;
  final bool avx2;
  final bool bmi2;
  final bool erms;
  final bool avx512f;
  final bool avx512dq;
  final bool rdseed;
  final bool adx;
  final bool avx512bw;
  final bool avx512vl;

  // Extended features (CPUID.7.0:ECX)
  final bool vaes;
  final bool vpclmulqdq;
  final bool avx512vnni;

  // Extended features (CPUID.80000001h:ECX)
  final bool lzcnt;
  final bool abm; // Advanced Bit Manipulation (LZCNT + POPCNT)

  // Extended features (CPUID.80000001h:EDX)
  final bool x64;

  const CpuFeatures({
    // ECX from CPUID.1
    this.sse3 = false,
    this.pclmulqdq = false,
    this.ssse3 = false,
    this.fma = false,
    this.sse41 = false,
    this.sse42 = false,
    this.popcnt = false,
    this.aesni = false,
    this.avx = false,
    this.f16c = false,
    this.rdrand = false,
    // EDX from CPUID.1
    this.fpu = false,
    this.cmov = false,
    this.mmx = false,
    this.fxsr = false,
    this.sse = false,
    this.sse2 = false,
    // EBX from CPUID.7.0
    this.bmi1 = false,
    this.avx2 = false,
    this.bmi2 = false,
    this.erms = false,
    this.avx512f = false,
    this.avx512dq = false,
    this.rdseed = false,
    this.adx = false,
    this.avx512bw = false,
    this.avx512vl = false,
    // ECX from CPUID.7.0
    this.vaes = false,
    this.vpclmulqdq = false,
    this.avx512vnni = false,
    // Extended
    this.lzcnt = false,
    this.abm = false,
    this.x64 = false,
  });

  /// Creates a CpuFeatures with all features enabled (for testing).
  const CpuFeatures.all()
      : sse3 = true,
        pclmulqdq = true,
        ssse3 = true,
        fma = true,
        sse41 = true,
        sse42 = true,
        popcnt = true,
        aesni = true,
        avx = true,
        f16c = true,
        rdrand = true,
        fpu = true,
        cmov = true,
        mmx = true,
        fxsr = true,
        sse = true,
        sse2 = true,
        bmi1 = true,
        avx2 = true,
        bmi2 = true,
        erms = true,
        avx512f = true,
        avx512dq = true,
        rdseed = true,
        adx = true,
        avx512bw = true,
        avx512vl = true,
        vaes = true,
        vpclmulqdq = true,
        avx512vnni = true,
        lzcnt = true,
        abm = true,
        x64 = true;

  /// Creates CpuFeatures with baseline x86-64 features.
  const CpuFeatures.baseline()
      : sse3 = false,
        pclmulqdq = false,
        ssse3 = false,
        fma = false,
        sse41 = false,
        sse42 = false,
        popcnt = false,
        aesni = false,
        avx = false,
        f16c = false,
        rdrand = false,
        fpu = true, // x86-64 always has FPU
        cmov = true, // x86-64 always has CMOV
        mmx = true, // x86-64 always has MMX
        fxsr = true, // x86-64 always has FXSR
        sse = true, // x86-64 always has SSE
        sse2 = true, // x86-64 always has SSE2
        bmi1 = false,
        avx2 = false,
        bmi2 = false,
        erms = false,
        avx512f = false,
        avx512dq = false,
        rdseed = false,
        adx = false,
        avx512bw = false,
        avx512vl = false,
        vaes = false,
        vpclmulqdq = false,
        avx512vnni = false,
        lzcnt = false,
        abm = false,
        x64 = true; // We're x86-64

  @override
  String toString() {
    final features = <String>[];
    if (x64) features.add('x64');
    if (fpu) features.add('FPU');
    if (cmov) features.add('CMOV');
    if (mmx) features.add('MMX');
    if (sse) features.add('SSE');
    if (sse2) features.add('SSE2');
    if (sse3) features.add('SSE3');
    if (ssse3) features.add('SSSE3');
    if (sse41) features.add('SSE4.1');
    if (sse42) features.add('SSE4.2');
    if (popcnt) features.add('POPCNT');
    if (lzcnt) features.add('LZCNT');
    if (avx) features.add('AVX');
    if (avx2) features.add('AVX2');
    if (fma) features.add('FMA');
    if (bmi1) features.add('BMI1');
    if (bmi2) features.add('BMI2');
    if (adx) features.add('ADX');
    if (aesni) features.add('AES-NI');
    if (pclmulqdq) features.add('PCLMULQDQ');
    if (avx512f) features.add('AVX-512F');
    return 'CpuFeatures(${features.join(', ')})';
  }
}

/// CPU information detector.
class CpuInfo {
  /// Detected CPU features.
  final CpuFeatures features;

  /// CPU vendor string (e.g., "GenuineIntel", "AuthenticAMD").
  final String vendor;

  /// CPU brand string.
  final String brand;

  /// Number of logical processors.
  final int logicalProcessors;

  CpuInfo._({
    required this.features,
    required this.vendor,
    required this.brand,
    required this.logicalProcessors,
  });

  /// Cached host CPU info.
  static CpuInfo? _host;

  /// Gets the CPU info for the host machine.
  static CpuInfo host() {
    return _host ??= _detectHost();
  }

  /// Detects the host CPU features.
  static CpuInfo _detectHost() {
    // If not x86-64, return baseline
    if (!_isX86_64()) {
      return CpuInfo._(
        features: const CpuFeatures.baseline(),
        vendor: 'Unknown',
        brand: 'Unknown',
        logicalProcessors: Platform.numberOfProcessors,
      );
    }

    try {
      return _detectWithCpuid();
    } catch (e) {
      // Fallback to baseline if CPUID detection fails
      return CpuInfo._(
        features: const CpuFeatures.baseline(),
        vendor: 'Unknown',
        brand: 'Unknown (CPUID failed: $e)',
        logicalProcessors: Platform.numberOfProcessors,
      );
    }
  }

  static bool _isX86_64() {
    // Check if we're on x86-64 based on platform
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return true;
    }
    return false;
  }

  /// Detects CPU features using CPUID instruction.
  static CpuInfo _detectWithCpuid() {
    // CPUID shellcode that returns EAX, EBX, ECX, EDX
    // Input: RCX = CPUID leaf, RDX = subleaf
    // Output: RAX = result pointer (filled with EAX, EBX, ECX, EDX)
    //
    // Windows x64 ABI: RCX = arg0 (output ptr), RDX = arg1 (leaf), R8 = arg2 (subleaf)
    // SysV ABI: RDI = arg0 (output ptr), RSI = arg1 (leaf), RDX = arg2 (subleaf)

    final Uint8List cpuidCode;

    if (Platform.isWindows) {
      // Windows x64:
      // push rbx             ; 53
      // mov r10, rcx         ; 49 89 CA (save output ptr)
      // mov eax, edx         ; 89 D0 (leaf)
      // mov ecx, r8d         ; 44 89 C1 (subleaf)
      // cpuid                ; 0F A2
      // mov [r10], eax       ; 41 89 02
      // mov [r10+4], ebx     ; 41 89 5A 04
      // mov [r10+8], ecx     ; 41 89 4A 08
      // mov [r10+12], edx    ; 41 89 52 0C
      // pop rbx              ; 5B
      // ret                  ; C3
      cpuidCode = Uint8List.fromList([
        0x53, // push rbx
        0x49, 0x89, 0xCA, // mov r10, rcx (save output ptr)
        0x89, 0xD0, // mov eax, edx (leaf)
        0x44, 0x89, 0xC1, // mov ecx, r8d (subleaf)
        0x0F, 0xA2, // cpuid
        0x41, 0x89, 0x02, // mov [r10], eax
        0x41, 0x89, 0x5A, 0x04, // mov [r10+4], ebx
        0x41, 0x89, 0x4A, 0x08, // mov [r10+8], ecx
        0x41, 0x89, 0x52, 0x0C, // mov [r10+12], edx
        0x5B, // pop rbx
        0xC3, // ret
      ]);
    } else {
      // SysV ABI:
      // push rbx             ; 53
      // mov r10, rdi         ; 49 89 FA (save output ptr)
      // mov eax, esi         ; 89 F0 (leaf)
      // mov ecx, edx         ; 89 D1 (subleaf)
      // cpuid                ; 0F A2
      // mov [r10], eax       ; 41 89 02
      // mov [r10+4], ebx     ; 41 89 5A 04
      // mov [r10+8], ecx     ; 41 89 4A 08
      // mov [r10+12], edx    ; 41 89 52 0C
      // pop rbx              ; 5B
      // ret                  ; C3
      cpuidCode = Uint8List.fromList([
        0x53, // push rbx
        0x49, 0x89, 0xFA, // mov r10, rdi (save output ptr)
        0x89, 0xF0, // mov eax, esi (leaf)
        0x89, 0xD1, // mov ecx, edx (subleaf)
        0x0F, 0xA2, // cpuid
        0x41, 0x89, 0x02, // mov [r10], eax
        0x41, 0x89, 0x5A, 0x04, // mov [r10+4], ebx
        0x41, 0x89, 0x4A, 0x08, // mov [r10+8], ecx
        0x41, 0x89, 0x52, 0x0C, // mov [r10+12], edx
        0x5B, // pop rbx
        0xC3, // ret
      ]);
    }

    // Allocate executable memory
    final info = VirtMem.info();
    final alignedSize = info.alignToPage(cpuidCode.length);
    final mem = VirtMem.allocRW(alignedSize);

    try {
      // Copy code
      VirtMem.writeBytes(mem, cpuidCode);

      // Make executable
      final execMem = VirtMem.protectRX(mem);

      // Create callable
      final cpuidFn = execMem.ptr
          .cast<NativeFunction<Void Function(Pointer<Uint32>, Int32, Int32)>>()
          .asFunction<void Function(Pointer<Uint32>, int, int)>();

      // Allocate result buffer (4 x 32-bit values)
      final result = _allocUint32(4);
      try {
        // Execute CPUID leaf 0 to get max leaf and vendor
        cpuidFn(result, 0, 0);
        final maxLeaf = result[0];
        final ebx0 = result[1];
        final ecx0 = result[2];
        final edx0 = result[3];

        // Vendor string: EBX + EDX + ECX (note the order!)
        final vendorBytes = Uint8List(12);
        final view = ByteData.view(vendorBytes.buffer);
        view.setUint32(0, ebx0, Endian.little);
        view.setUint32(4, edx0, Endian.little);
        view.setUint32(8, ecx0, Endian.little);
        final vendor = String.fromCharCodes(vendorBytes);

        // Basic features from leaf 1
        int ecx1 = 0, edx1 = 0;
        if (maxLeaf >= 1) {
          cpuidFn(result, 1, 0);
          ecx1 = result[2];
          edx1 = result[3];
        }

        // Extended features from leaf 7
        int ebx7 = 0, ecx7 = 0;
        if (maxLeaf >= 7) {
          cpuidFn(result, 7, 0);
          ebx7 = result[1];
          ecx7 = result[2];
        }

        // Extended CPUID (0x80000000)
        cpuidFn(result, 0x80000000, 0);
        final maxExtLeaf = result[0];

        int ecxExt1 = 0, edxExt1 = 0;
        if (maxExtLeaf >= 0x80000001) {
          cpuidFn(result, 0x80000001, 0);
          ecxExt1 = result[2];
          edxExt1 = result[3];
        }

        // Brand string (0x80000002 - 0x80000004)
        var brand = '';
        if (maxExtLeaf >= 0x80000004) {
          final brandBytes = Uint8List(48);
          final brandView = ByteData.view(brandBytes.buffer);
          for (int leaf = 0x80000002; leaf <= 0x80000004; leaf++) {
            cpuidFn(result, leaf, 0);
            final offset = (leaf - 0x80000002) * 16;
            brandView.setUint32(offset, result[0], Endian.little);
            brandView.setUint32(offset + 4, result[1], Endian.little);
            brandView.setUint32(offset + 8, result[2], Endian.little);
            brandView.setUint32(offset + 12, result[3], Endian.little);
          }
          brand =
              String.fromCharCodes(brandBytes).replaceAll('\x00', '').trim();
        }

        // Extract feature bits
        final features = CpuFeatures(
          // CPUID.1:ECX
          sse3: (ecx1 & (1 << 0)) != 0,
          pclmulqdq: (ecx1 & (1 << 1)) != 0,
          ssse3: (ecx1 & (1 << 9)) != 0,
          fma: (ecx1 & (1 << 12)) != 0,
          sse41: (ecx1 & (1 << 19)) != 0,
          sse42: (ecx1 & (1 << 20)) != 0,
          popcnt: (ecx1 & (1 << 23)) != 0,
          aesni: (ecx1 & (1 << 25)) != 0,
          avx: (ecx1 & (1 << 28)) != 0,
          f16c: (ecx1 & (1 << 29)) != 0,
          rdrand: (ecx1 & (1 << 30)) != 0,
          // CPUID.1:EDX
          fpu: (edx1 & (1 << 0)) != 0,
          cmov: (edx1 & (1 << 15)) != 0,
          mmx: (edx1 & (1 << 23)) != 0,
          fxsr: (edx1 & (1 << 24)) != 0,
          sse: (edx1 & (1 << 25)) != 0,
          sse2: (edx1 & (1 << 26)) != 0,
          // CPUID.7.0:EBX
          bmi1: (ebx7 & (1 << 3)) != 0,
          avx2: (ebx7 & (1 << 5)) != 0,
          bmi2: (ebx7 & (1 << 8)) != 0,
          erms: (ebx7 & (1 << 9)) != 0,
          avx512f: (ebx7 & (1 << 16)) != 0,
          avx512dq: (ebx7 & (1 << 17)) != 0,
          rdseed: (ebx7 & (1 << 18)) != 0,
          adx: (ebx7 & (1 << 19)) != 0,
          avx512bw: (ebx7 & (1 << 30)) != 0,
          avx512vl: (ebx7 & (1 << 31)) != 0,
          // CPUID.7.0:ECX
          vaes: (ecx7 & (1 << 9)) != 0,
          vpclmulqdq: (ecx7 & (1 << 10)) != 0,
          avx512vnni: (ecx7 & (1 << 11)) != 0,
          // CPUID.80000001h:ECX
          lzcnt: (ecxExt1 & (1 << 5)) != 0,
          abm: (ecxExt1 & (1 << 5)) != 0, // LZCNT implies ABM
          // CPUID.80000001h:EDX
          x64: (edxExt1 & (1 << 29)) != 0,
        );

        return CpuInfo._(
          features: features,
          vendor: vendor,
          brand: brand,
          logicalProcessors: Platform.numberOfProcessors,
        );
      } finally {
        _freeUint32(result);
      }
    } finally {
      VirtMem.release(mem);
    }
  }

  @override
  String toString() {
    return 'CpuInfo(\n'
        '  vendor: $vendor,\n'
        '  brand: $brand,\n'
        '  processors: $logicalProcessors,\n'
        '  features: $features\n'
        ')';
  }
}

// Native allocator helper using libc
final DynamicLibrary _libc = Platform.isWindows
    ? DynamicLibrary.open('msvcrt.dll')
    : DynamicLibrary.process();

final Pointer<Void> Function(int) _malloc = _libc
    .lookup<NativeFunction<Pointer<Void> Function(IntPtr)>>('malloc')
    .asFunction();

final void Function(Pointer<Void>) _free = _libc
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>('free')
    .asFunction();

Pointer<Uint32> _allocUint32(int count) {
  final size = count * 4; // sizeof(uint32_t) = 4
  final ptr = _malloc(size);
  if (ptr == nullptr) {
    throw StateError('Failed to allocate $size bytes');
  }
  // Zero-initialize
  ptr.cast<Uint8>().asTypedList(size).fillRange(0, size, 0);
  return ptr.cast<Uint32>();
}

void _freeUint32(Pointer<Uint32> ptr) {
  _free(ptr.cast<Void>());
}
