/// ChaCha20 Benchmark - Compara 6 implementações diferentes
///
/// 1. C puro (DLL)
/// 2. Dart puro (baseline)
/// 3. Dart otimizado (Uint8List/ByteData/unroll)
/// 4. Dart usando somente ponteiros FFI
/// 5. Dart "inline asm" via shellcode + VirtualAlloc/mmap
/// 6. Dart com asmjit gerando código dinâmico
/// 7. Dart com asmjit otimizado
/// Uso: dart run benchmark/chacha20_benchmark.dart [--quick]


import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'chacha20_impl/chacha20_baseline.dart';
import 'chacha20_impl/chacha20_optimized.dart';
import 'chacha20_impl/chacha20_ffi_pointer.dart';
import 'chacha20_impl/chacha20_inline_asm.dart';
import 'chacha20_impl/chacha20_asmjit.dart';
import 'chacha20_impl/chacha20_c_ffi.dart';
import 'chacha20_impl/chacha20_asmjit_optimized.dart';

/// Resultado de um benchmark
class BenchResult {
  final String name;
  final String category;
  final int iterations;
  final int bytes;
  final double nsPerOp;
  final double mibPerSec;
  final bool success;
  final String? error;

  BenchResult({
    required this.name,
    required this.category,
    required this.iterations,
    required this.bytes,
    required this.nsPerOp,
    required this.mibPerSec,
    this.success = true,
    this.error,
  });

  BenchResult.failed(this.name, this.category, this.error)
      : iterations = 0,
        bytes = 0,
        nsPerOp = 0,
        mibPerSec = 0,
        success = false;

  void print() {
    if (!success) {
      stdout.writeln('  ${name.padRight(40)} | FAILED: $error');
      return;
    }
    final ns = nsPerOp.toStringAsFixed(1).padLeft(10);
    final mib =
        mibPerSec > 0 ? mibPerSec.toStringAsFixed(1).padLeft(10) : '       N/A';
    stdout.writeln('  ${name.padRight(40)} | $ns ns/op | $mib MiB/s');
  }
}

/// Executa um benchmark
BenchResult runBench(
  String name,
  String category,
  int iterations,
  int bytesPerIter,
  void Function() fn,
) {
  //try {
    // Warmup
    for (var i = 0; i < min(100, iterations ~/ 10); i++) {
      fn();
    }

    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      fn();
    }
    sw.stop();

    final totalNs = sw.elapsedMicroseconds * 1000.0;
    final nsPerOp = totalNs / iterations;
    final mibPerSec = bytesPerIter > 0
        ? (bytesPerIter * iterations) / (1024 * 1024) / (totalNs / 1e9)
        : 0.0;

    return BenchResult(
      name: name,
      category: category,
      iterations: iterations,
      bytes: bytesPerIter,
      nsPerOp: nsPerOp,
      mibPerSec: mibPerSec,
    );
  // } catch (e) {
  //   return BenchResult.failed(name, category, e.toString());
  // }
  //return BenchResult.failed(name, category, 'e.toString()');
}

/// Gera dados de teste
Uint8List generateTestData(int length) {
  final rng = Random(42);
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}

/// Gera chave de 32 bytes
Uint8List generateKey() {
  return Uint8List.fromList(List.generate(32, (i) => i));
}

/// Gera nonce de 12 bytes
Uint8List generateNonce() {
  return Uint8List.fromList(List.generate(12, (i) => i * 3));
}

void main(List<String> args) {
  final quick = args.contains('--quick');
  final filter = args
      .firstWhere((a) => a.startsWith('--filter='), orElse: () => '')
      .replaceAll('--filter=', '');
  // final verbose = args.contains('--verbose') || args.contains('-v');

  // Configurações de benchmark
  final smallSize = 64; // 1 bloco
  final mediumSize = 1024; // 16 blocos
  final largeSize = 65536; // 1024 blocos

  final smallIters = quick ? 10000 : 100000;
  final mediumIters = quick ? 5000 : 50000;
  final largeIters = quick ? 500 : 5000;

  final key = generateKey();
  final nonce = generateNonce();
  final smallData = generateTestData(smallSize);
  final mediumData = generateTestData(mediumSize);
  final largeData = generateTestData(largeSize);

  printHeader(quick);

  final results = <BenchResult>[];

  bool shouldRun(String name) =>
      filter.isEmpty || name.toLowerCase().contains(filter.toLowerCase());

  // ============================================================
  // 1. C PURO (DLL)
  // ============================================================
  if (shouldRun('C DLL')) {
    stdout.writeln('\n${'=' * 70}');
    stdout.writeln('1. C PURO (DLL via FFI)');
    stdout.writeln('${'=' * 70}');

    if (ChaCha20DLL.load()) {
      stdout.writeln('DLL loaded successfully');

      final cLib = ChaCha20CLib(key, nonce);
      final cLibPooled =
          ChaCha20CLibPooled(key, nonce, maxBufferSize: largeSize);
      final outputSmall = Uint8List(smallSize);
      final outputMedium = Uint8List(mediumSize);
      final outputLarge = Uint8List(largeSize);

      results.add(runBench('C DLL (64B)', 'C', smallIters, smallSize, () {
        cLib.cryptInto(smallData, outputSmall);
      })
        ..print());

      results.add(runBench('C DLL (1KB)', 'C', mediumIters, mediumSize, () {
        cLib.cryptInto(mediumData, outputMedium);
      })
        ..print());

      results.add(runBench('C DLL (64KB)', 'C', largeIters, largeSize, () {
        cLib.cryptInto(largeData, outputLarge);
      })
        ..print());

      results
          .add(runBench('C DLL Pooled (64KB)', 'C', largeIters, largeSize, () {
        cLibPooled.cryptInto(largeData, outputLarge);
      })
            ..print());

      // FFI call overhead
      results
          .add(runBench('C DLL noop() overhead', 'C', smallIters * 10, 0, () {
        ChaCha20DLL.noop!();
      })
            ..print());

      cLib.dispose();
      cLibPooled.dispose();
    } else {
      stdout.writeln('DLL not found: ${ChaCha20DLL.loadError}');
      stdout.writeln(
          'Build with: powershell benchmark/native/build_chacha20_impl.ps1');
      results.add(BenchResult.failed('C DLL', 'C', ChaCha20DLL.loadError));
    }
  }

  // ============================================================
  // 2. DART PURO (BASELINE)
  // ============================================================
  if (shouldRun('Dart Baseline')) {
    stdout.writeln('\n${'=' * 70}');
    stdout.writeln('2. DART PURO (Baseline - List<int>)');
    stdout.writeln('${'=' * 70}');

    {
      final baseline = ChaCha20Baseline(key, nonce);
      final outputSmall = Uint8List(smallSize);
      final outputMedium = Uint8List(mediumSize);
      final outputLarge = Uint8List(largeSize);

      results.add(runBench(
          'Dart Baseline (64B)', 'Dart Baseline', smallIters, smallSize, () {
        baseline.cryptInto(smallData, outputSmall);
      })
        ..print());

      results.add(runBench(
          'Dart Baseline (1KB)', 'Dart Baseline', mediumIters, mediumSize, () {
        baseline.cryptInto(mediumData, outputMedium);
      })
        ..print());

      results.add(runBench(
          'Dart Baseline (64KB)', 'Dart Baseline', largeIters, largeSize, () {
        baseline.cryptInto(largeData, outputLarge);
      })
        ..print());
    }
  }

  // ============================================================
  // 3. DART OTIMIZADO (Uint32List, ByteData, Unroll)
  // ============================================================
  if (shouldRun('Dart Optimized')) {
    stdout.writeln('\n${'=' * 70}');
    stdout.writeln('3. DART OTIMIZADO (Uint32List, ByteData, Unroll)');
    stdout.writeln('${'=' * 70}');

    {
      final optimized = ChaCha20Optimized(key, nonce);
      final unrolled = ChaCha20OptimizedUnroll(key, nonce);
      final outputSmall = Uint8List(smallSize);
      final outputMedium = Uint8List(mediumSize);
      final outputLarge = Uint8List(largeSize);

      results.add(runBench(
          'Dart Optimized (64B)', 'Dart Optimized', smallIters, smallSize, () {
        optimized.cryptInto(smallData, outputSmall);
      })
        ..print());

      results.add(runBench(
          'Dart Optimized (1KB)', 'Dart Optimized', mediumIters, mediumSize,
          () {
        optimized.cryptInto(mediumData, outputMedium);
      })
        ..print());

      results.add(runBench(
          'Dart Optimized (64KB)', 'Dart Optimized', largeIters, largeSize, () {
        optimized.cryptInto(largeData, outputLarge);
      })
        ..print());

      results.add(runBench(
          'Dart Unrolled (64B)', 'Dart Optimized', smallIters, smallSize, () {
        unrolled.cryptInto(smallData, outputSmall);
      })
        ..print());

      results.add(runBench(
          'Dart Unrolled (1KB)', 'Dart Optimized', mediumIters, mediumSize, () {
        unrolled.cryptInto(mediumData, outputMedium);
      })
        ..print());

      results.add(runBench(
          'Dart Unrolled (64KB)', 'Dart Optimized', largeIters, largeSize, () {
        unrolled.cryptInto(largeData, outputLarge);
      })
        ..print());
    }
  }

  // ============================================================
  // 4. DART FFI POINTER (C-style)
  // ============================================================
  if (shouldRun('Dart FFI')) {
    stdout.writeln('\n${'=' * 70}');
    stdout.writeln('4. DART FFI POINTER (Pointer<T> direto)');
    stdout.writeln('${'=' * 70}');

    {
      final ffiPointer = ChaCha20FFIPointer(key, nonce);
      final ffiPointerOpt = ChaCha20FFIPointerOptimized(key, nonce);
      final outputSmall = Uint8List(smallSize);
      final outputMedium = Uint8List(mediumSize);
      final outputLarge = Uint8List(largeSize);

      results.add(runBench(
          'Dart FFI Pointer (64B)', 'Dart FFI', smallIters, smallSize, () {
        ffiPointer.cryptInto(smallData, outputSmall);
      })
        ..print());

      results.add(runBench(
          'Dart FFI Pointer (1KB)', 'Dart FFI', mediumIters, mediumSize, () {
        ffiPointer.cryptInto(mediumData, outputMedium);
      })
        ..print());

      results.add(runBench(
          'Dart FFI Pointer (64KB)', 'Dart FFI', largeIters, largeSize, () {
        ffiPointer.cryptInto(largeData, outputLarge);
      })
        ..print());

      results.add(runBench(
          'Dart FFI Ptr Opt (64B)', 'Dart FFI', smallIters, smallSize, () {
        ffiPointerOpt.cryptInto(smallData, outputSmall);
      })
        ..print());

      results.add(runBench(
          'Dart FFI Ptr Opt (1KB)', 'Dart FFI', mediumIters, mediumSize, () {
        ffiPointerOpt.cryptInto(mediumData, outputMedium);
      })
        ..print());

      results.add(runBench(
          'Dart FFI Ptr Opt (64KB)', 'Dart FFI', largeIters, largeSize, () {
        ffiPointerOpt.cryptInto(largeData, outputLarge);
      })
        ..print());

      ffiPointer.dispose();
      ffiPointerOpt.dispose();
    }
  }

  // ============================================================
  // 5. INLINE ASM (Shellcode SSE2)
  // ============================================================
  if (shouldRun('Inline ASM')) {
    stdout.writeln('\n${'=' * 70}');
    stdout.writeln('5. INLINE ASM (Shellcode SSE2 + VirtualAlloc)');
    stdout.writeln('${'=' * 70}');

    if (ChaCha20InlineAsmSupport.isSSE2Supported) {
      stdout.writeln('SSE2 supported: yes');

      try {
        final inlineAsm = ChaCha20InlineAsm(key, nonce);
        final outputSmall = Uint8List(smallSize);
        final outputMedium = Uint8List(mediumSize);
        final outputLarge = Uint8List(largeSize);

        results.add(runBench(
            'Inline ASM SSE2 (64B)', 'Inline ASM', smallIters, smallSize, () {
          inlineAsm.cryptInto(smallData, outputSmall);
        })
          ..print());

        results.add(runBench(
            'Inline ASM SSE2 (1KB)', 'Inline ASM', mediumIters, mediumSize, () {
          inlineAsm.cryptInto(mediumData, outputMedium);
        })
          ..print());

        results.add(runBench(
            'Inline ASM SSE2 (64KB)', 'Inline ASM', largeIters, largeSize, () {
          inlineAsm.cryptInto(largeData, outputLarge);
        })
          ..print());

        inlineAsm.dispose();
      } catch (e) {
        stdout.writeln('Inline ASM failed: $e');
        results
            .add(BenchResult.failed('Inline ASM', 'Inline ASM', e.toString()));
      }
    } else {
      stdout.writeln('SSE2 not supported on this platform');
      results.add(
          BenchResult.failed('Inline ASM', 'Inline ASM', 'SSE2 not supported'));
    }
  }

  // ============================================================
  // 6. ASMJIT (Código gerado dinamicamente)
  // ============================================================
  if (shouldRun('AsmJit SSE2')) {
    stdout.writeln('\n${'=' * 70}');
    stdout.writeln('6. ASMJIT (Código SSE2 gerado em runtime)');
    stdout.writeln('${'=' * 70}');

    try {
      final asmjit = ChaCha20AsmJit(key, nonce);
      final outputSmall = Uint8List(smallSize);
      final outputMedium = Uint8List(mediumSize);
      final outputLarge = Uint8List(largeSize);

      results.add(
          runBench('AsmJit SSE2 (64B)', 'AsmJit', smallIters, smallSize, () {
        asmjit.cryptInto(smallData, outputSmall);
      })
            ..print());

      results.add(
          runBench('AsmJit SSE2 (1KB)', 'AsmJit', mediumIters, mediumSize, () {
        asmjit.cryptInto(mediumData, outputMedium);
      })
            ..print());

      results.add(
          runBench('AsmJit SSE2 (64KB)', 'AsmJit', largeIters, largeSize, () {
        asmjit.cryptInto(largeData, outputLarge);
      })
            ..print());

      asmjit.dispose();
    } catch (e) {
      stdout.writeln('AsmJit failed: $e');
      results.add(BenchResult.failed('AsmJit', 'AsmJit', e.toString()));
    }
  }

  // ============================================================
  // 7. ASMJIT OPTIMIZED (Scalar Unrolled Port)
  // ============================================================
  if (shouldRun('AsmJit Opt')) {
    stdout.writeln('\n${'=' * 70}');
    stdout.writeln('7. ASMJIT OPTIMIZED (Scalar Unrolled Port)');
    stdout.writeln('${'=' * 70}');

    
      final asmjitOpt = ChaCha20AsmJitOptimized(key, nonce);
      final outputSmall = Uint8List(smallSize);
      final outputMedium = Uint8List(mediumSize);
      final outputLarge = Uint8List(largeSize);

      results.add(runBench(
          'AsmJit SCALAR (64B)', 'AsmJit Opt', smallIters, smallSize, () {
        asmjitOpt.cryptInto(smallData, outputSmall);
      })
        ..print());

      results.add(runBench(
          'AsmJit SCALAR (1KB)', 'AsmJit Opt', mediumIters, mediumSize, () {
        asmjitOpt.cryptInto(mediumData, outputMedium);
      })
        ..print());

      results.add(runBench(
          'AsmJit SCALAR (64KB)', 'AsmJit Opt', largeIters, largeSize, () {
        asmjitOpt.cryptInto(largeData, outputLarge);
      })
        ..print());

      asmjitOpt.dispose();
      ChaCha20AsmJitOptimized.disposeStatic();
   
  }

  // ============================================================
  // RESUMO E ANÁLISE
  // ============================================================
  printSummary(results);
  printOptimizationStrategies();

  // Cleanup
  ChaCha20AsmJit.disposeStatic();
  // ChaCha20AsmJitBuilder.disposeStatic();
}

void printHeader(bool quick) {
  stdout.writeln('');
  stdout.writeln(
      '╔═══════════════════════════════════════════════════════════════════════╗');
  stdout.writeln(
      '║               ChaCha20 Benchmark - 7 Implementações                    ║');
  stdout.writeln(
      '╠═══════════════════════════════════════════════════════════════════════╣');
  stdout.writeln(
      '║  1. C puro (DLL)                                                       ║');
  stdout.writeln(
      '║  2. Dart puro (baseline) - List<int>                                   ║');
  stdout.writeln(
      '║  3. Dart otimizado - Uint32List/ByteData/Unroll                        ║');
  stdout.writeln(
      '║  4. Dart FFI Pointer - Pointer<T> direto                               ║');
  stdout.writeln(
      '║  5. Inline ASM - Shellcode SSE2 + VirtualAlloc                         ║');
  stdout.writeln(
      '║  6. AsmJit - Código SSE2 gerado em runtime                             ║');
  stdout.writeln(
      '║  7. AsmJit Optimized - Scalar Unrolled (New)                           ║');
  stdout.writeln(
      '╚═══════════════════════════════════════════════════════════════════════╝');
  stdout.writeln('');
  stdout.writeln('Mode: ${quick ? "Quick" : "Full"}');
  stdout.writeln('Platform: ${Platform.operatingSystem} (${Platform.version})');
  stdout.writeln('');
}

void printSummary(List<BenchResult> results) {
  stdout.writeln('\n');
  stdout.writeln(
      '╔═══════════════════════════════════════════════════════════════════════╗');
  stdout.writeln(
      '║                           RESUMO COMPARATIVO                           ║');
  stdout.writeln(
      '╚═══════════════════════════════════════════════════════════════════════╝');
  stdout.writeln('');

  // Agrupa por tamanho
  final sizes = ['64B', '1KB', '64KB'];

  for (final size in sizes) {
    stdout.writeln('[$size]');
    final sizeResults =
        results.where((r) => r.name.contains(size) && r.success).toList();

    if (sizeResults.isEmpty) continue;

    // Ordena por throughput
    sizeResults.sort((a, b) => b.mibPerSec.compareTo(a.mibPerSec));

    final best = sizeResults.first;

    for (final r in sizeResults) {
      final speedup = best.mibPerSec > 0
          ? (r.mibPerSec / best.mibPerSec * 100).toStringAsFixed(1)
          : 'N/A';
      final indicator = r == best ? ' ★ FASTEST' : '';
      stdout.writeln(
          '  ${r.name.padRight(35)} ${r.mibPerSec.toStringAsFixed(1).padLeft(10)} MiB/s  ($speedup%)$indicator');
    }
    stdout.writeln('');
  }

  // Calcula overhead FFI
  stdout.writeln('FFI OVERHEAD ANALYSIS:');

  final cResults = results
      .where((r) => r.category == 'C' && r.success && r.name.contains('64KB'))
      .toList();
  final dartOptResults = results
      .where((r) =>
          r.category == 'Dart Optimized' &&
          r.success &&
          r.name.contains('64KB'))
      .toList();

  if (cResults.isNotEmpty && dartOptResults.isNotEmpty) {
    final cBest = cResults.first;
    final dartBest = dartOptResults.first;

    final overhead =
        ((cBest.nsPerOp - dartBest.nsPerOp).abs() / dartBest.nsPerOp * 100);

    if (cBest.nsPerOp < dartBest.nsPerOp) {
      stdout.writeln(
          '  C é ${(dartBest.nsPerOp / cBest.nsPerOp).toStringAsFixed(2)}x mais rápido que Dart otimizado');
      stdout.writeln('  FFI overhead compensado pelo código C otimizado');
    } else {
      stdout.writeln(
          '  Dart otimizado é ${(cBest.nsPerOp / dartBest.nsPerOp).toStringAsFixed(2)}x mais rápido');
      stdout.writeln(
          '  FFI overhead: ~${overhead.toStringAsFixed(1)}% do tempo total');
    }
  }

  // Noop overhead
  final noopResult = results.where((r) => r.name.contains('noop')).firstOrNull;
  if (noopResult != null && noopResult.success) {
    stdout.writeln(
        '  FFI call overhead (noop): ${noopResult.nsPerOp.toStringAsFixed(1)} ns/call');
  }
}

void printOptimizationStrategies() {
  stdout.writeln('\n');
  stdout.writeln(
      '╔═══════════════════════════════════════════════════════════════════════╗');
  stdout.writeln(
      '║                     ESTRATÉGIAS DE OTIMIZAÇÃO                          ║');
  stdout.writeln(
      '╚═══════════════════════════════════════════════════════════════════════╝');
  stdout.writeln('''

1. DART PURO:
   - Use Uint32List ao invés de List<int> para arrays de inteiros
   - Use ByteData para conversões endian
   - Pré-aloque buffers e reutilize-os
   - Use loop unrolling manual para hot loops
   - Evite criar objetos temporários em loops internos

2. FFI POINTER:
   - Minimize o número de chamadas FFI (batch operations)
   - Use Pointer.asTypedList() para views sem cópia
   - Pré-aloque ponteiros nativos e reutilize-os
   - Evite conversões Dart ↔ Native em loops

3. INLINE ASM:
   - Use SIMD (SSE2/AVX) para processar múltiplos dados
   - Agrupe operações em blocos maiores
   - Use registros ao invés de memória quando possível
   - Considere cache line alignment

4. ASMJIT:
   - Gere código especializado para o caso específico
   - Evite branches condicionais em hot paths
   - Use instruções SIMD quando disponíveis
   - Cache funções geradas para reutilização

5. QUANDO USAR CADA ABORDAGEM:
   ┌───────────────────┬────────────────────────────────────────────────┐
   │ Abordagem         │ Quando usar                                    │
   ├───────────────────┼────────────────────────────────────────────────┤
   │ Dart puro         │ Portabilidade, manutenção, dados pequenos     │
   │ Dart otimizado    │ Performance sem dependências, dados médios    │
   │ FFI Pointer       │ Integração com C existente, dados grandes     │
   │ C DLL             │ Máxima performance, código crítico            │
   │ Inline ASM        │ Controle total, SIMD manual                   │
   │ AsmJit            │ Código adaptativo, JIT especializado          │
   └───────────────────┴────────────────────────────────────────────────┘
''');
}
