part of 'unicompiler.dart';

/// X86-specific functionality for UniCompiler.
mixin UniCompilerX86 on UniCompilerBase {
  /// Updates X86 extension masks based on CpuFeatures.
  void _updateX86Features() {
    if (!isX86Family) return;

    // Reset masks
    _gpExtMask = 0;
    _sseExtMask = 0;
    _avxExtMask = 0;

    // Map CpuFeatures to extension masks
    final features = _features;

    // GP Extensions
    if (features.adx) _gpExtMask |= (1 << GPExt.kADX.index);
    if (features.bmi1) _gpExtMask |= (1 << GPExt.kBMI.index);
    if (features.bmi2) _gpExtMask |= (1 << GPExt.kBMI2.index);
    if (features.lzcnt) _gpExtMask |= (1 << GPExt.kLZCNT.index);
    // Note: CpuFeatures doesn't have movbe - use CPU detection or add later
    if (features.popcnt) _gpExtMask |= (1 << GPExt.kPOPCNT.index);

    // SSE Extensions (SSE2 is baseline for x64)
    _sseExtMask |= (1 << SSEExt.kSSE2.index); // Always on for x64
    if (features.sse3) _sseExtMask |= (1 << SSEExt.kSSE3.index);
    if (features.ssse3) _sseExtMask |= (1 << SSEExt.kSSSE3.index);
    if (features.sse41) _sseExtMask |= (1 << SSEExt.kSSE4_1.index);
    if (features.sse42) _sseExtMask |= (1 << SSEExt.kSSE4_2.index);
    if (features.pclmulqdq) _sseExtMask |= (1 << SSEExt.kPCLMULQDQ.index);

    // AVX Extensions
    if (features.avx) _avxExtMask |= (1 << AVXExt.kAVX.index);
    if (features.avx2) _avxExtMask |= (1 << AVXExt.kAVX2.index);
    if (features.f16c) _avxExtMask |= (1 << AVXExt.kF16C.index);
    if (features.fma) _avxExtMask |= (1 << AVXExt.kFMA.index);
    // Note: GFNI not in current CpuFeatures
    if (features.vpclmulqdq) _avxExtMask |= (1 << AVXExt.kVPCLMULQDQ.index);

    // AVX-512 (check all required extensions)
    if (features.avx512f &&
        features.avx512bw &&
        features.avx512dq &&
        features.avx512vl) {
      _avxExtMask |= (1 << AVXExt.kAVX512.index);
    }

    // Set FMA behavior
    if (features.fma) {
      _fMAddOpBehavior = FMAddOpBehavior.fmaStoreToAny;
    }

    // Update vec reg count based on AVX-512
    if (hasAvx512) {
      _vecRegCount = 32;
    }
  }

  /// Gets the maximum vector width supported by CPU features.
  VecWidth maxVecWidthFromCpuFeatures() {
    if (hasAvx512) return VecWidth.k512;
    if (hasAvx2 || hasAvx) return VecWidth.k256;
    return VecWidth.k128;
  }
}
