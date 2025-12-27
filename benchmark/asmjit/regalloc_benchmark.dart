/// AsmJit Dart - Register Allocation Benchmark
///
/// Port of asmjit-testing/bench/asmjit_bench_regalloc.cpp
/// Benchmarks the performance of register allocation with varying complexity.

import 'package:asmjit/asmjit.dart';

const int kDefaultMaxComplexity = 65536;
const int kQuickMaxComplexity = 1024;

void main(List<String> args) {
  final quick = args.contains('--quick');
  final verbose = args.contains('--verbose');
  final maxComplexity = args.contains('--complexity')
      ? int.tryParse(args[args.indexOf('--complexity') + 1]) ??
          kDefaultMaxComplexity
      : (quick ? kQuickMaxComplexity : kDefaultMaxComplexity);

  print('AsmJit Dart Benchmark RegAlloc v1.0.0 [Arch=X64] [Mode=Release]');
  print('');
  print('Usage:');
  print('  asmjit_bench_regalloc [arguments]');
  print('');
  print('Arguments:');
  print('  --help           Show usage only');
  print('  --arch=<NAME>    Select architecture to run (\'all\' by default)');
  print('  --verbose        Verbose output');
  print('  --complexity=<n> Maximum complexity to test ($maxComplexity)');
  print('');

  if (args.contains('--help')) {
    return;
  }

  print(_tableHeader());
  print(_tableSeparator());

  // Run benchmarks with increasing complexity
  for (var complexity = 1; complexity <= maxComplexity; complexity *= 2) {
    final result = runRegAllocBenchmark(complexity, verbose);
    print(result.toTableRow());
  }

  print(_tableSeparator());
  print('');

  // Run A64 benchmarks
  print('');
  print(_tableHeader());
  print(_tableSeparator());

  for (var complexity = 1; complexity <= maxComplexity; complexity *= 2) {
    final result = runA64RegAllocBenchmark(complexity, verbose);
    print(result.toTableRow());
  }

  print(_tableSeparator());
}

String _tableHeader() {
  return '''
+-----------------------------------------+-----------+-----------------------------------+--------------+--------------+
|           Input Configuration           |   Output  |        Reserved Memory [KiB]      |      Time Elapsed [ms]      |
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+
| Arch   | Complexity | Labels | RegCount |  CodeSize | Code Hold.| Compiler  | Pass Temp.|   Emit Time  |  Reg. Alloc  |
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+''';
}

String _tableSeparator() {
  return '+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+';
}

class RegAllocBenchResult {
  final String arch;
  final int complexity;
  final int labelCount;
  final int regCount;
  final int codeSize;
  final double codeHolderKiB;
  final double compilerKiB;
  final double passTempKiB;
  final double emitTimeMs;
  final double regAllocTimeMs;
  final String? error;

  RegAllocBenchResult({
    required this.arch,
    required this.complexity,
    required this.labelCount,
    required this.regCount,
    required this.codeSize,
    required this.codeHolderKiB,
    required this.compilerKiB,
    required this.passTempKiB,
    required this.emitTimeMs,
    required this.regAllocTimeMs,
    this.error,
  });

  String toTableRow() {
    final errorStr = error != null ? ' (err: $error)' : '';
    return '| ${arch.padRight(6)} | ${complexity.toString().padLeft(10)} | ${labelCount.toString().padLeft(6)} | ${regCount.toString().padLeft(8)} | ${codeSize.toString().padLeft(9)} | ${codeHolderKiB.toStringAsFixed(1).padLeft(9)} | ${compilerKiB.toStringAsFixed(1).padLeft(9)} | ${passTempKiB.toStringAsFixed(1).padLeft(9)} | ${emitTimeMs.toStringAsFixed(3).padLeft(12)} | ${regAllocTimeMs.toStringAsFixed(3).padLeft(12)} |$errorStr';
  }
}

/// Generates a complex function with many virtual registers to stress the RA.
RegAllocBenchResult runRegAllocBenchmark(int complexity, bool verbose) {
  final labelCount = 3 + complexity;
  final regCount = 10 + complexity * 3;

  final emitSw = Stopwatch()..start();

  final builder = X86CodeBuilder.create();
  final regs = <VirtReg>[];

  // Create labels
  final labels = <Label>[];
  for (var i = 0; i < labelCount; i++) {
    labels.add(builder.newLabel());
  }
  final boundLabels = <Label>{};

  // Create virtual registers
  for (var i = 0; i < regCount; i++) {
    regs.add(builder.newGpReg());
  }

  // Initialize registers
  for (var i = 0; i < regs.length; i++) {
    builder.mov(regs[i], i);
  }

  // Generate some computation
  for (var i = 0; i < complexity; i++) {
    final a = regs[i % regs.length];
    final b = regs[(i + 1) % regs.length];
    final c = regs[(i + 2) % regs.length];

    builder.add(a, b);
    builder.sub(b, c);
    builder.xor(c, a);

    if (i % 16 == 0 && labels.isNotEmpty) {
      final labelIdx = (i ~/ 16) % labels.length;
      final label = labels[labelIdx];
      builder.jmp(label);
      if (!boundLabels.contains(label)) {
        builder.label(label);
        boundLabels.add(label);
      }
    }
  }

  // Bind remaining labels
  for (var i = 0; i < labels.length; i++) {
    if (!boundLabels.contains(labels[i])) {
      builder.label(labels[i]);
      boundLabels.add(labels[i]);
    }
  }

  // Return sum
  final sum = builder.newGpReg();
  builder.mov(sum, 0);
  for (var i = 0; i < (regs.length > 20 ? 20 : regs.length); i++) {
    builder.add(sum, regs[i]);
  }
  builder.mov(rax, sum);
  builder.ret();

  emitSw.stop();
  final emitTimeMs = emitSw.elapsedMicroseconds / 1000.0;

  // Now run RA and finalize
  final raSw = Stopwatch()..start();

  String? error;
  int codeSize = 0;
  double codeHolderKiB = 0;
  double compilerKiB = 0;
  double passTempKiB = 0;

  try {
    final finalized = builder.finalize();
    codeSize = finalized.textBytes.length;
    codeHolderKiB = builder.code.text.buffer.length / 1024.0;
    compilerKiB = builder.nodeCount * 64 / 1024.0;
  } catch (e, st) {
    error = e.toString().split(':').first;
    codeSize = builder.code.text.buffer.length;
    codeHolderKiB = builder.code.text.buffer.length / 1024.0;
    compilerKiB = builder.nodeCount * 64 / 1024.0;
    if (verbose) {
      // Ignore: debugging bench failures only.
      // ignore: avoid_print
      print('[X64] RegAlloc error: $e');
      // ignore: avoid_print
      print(st);
    }
  }

  raSw.stop();
  final regAllocTimeMs = raSw.elapsedMicroseconds / 1000.0;

  return RegAllocBenchResult(
    arch: 'X64',
    complexity: complexity,
    labelCount: labelCount,
    regCount: regCount,
    codeSize: codeSize,
    codeHolderKiB: codeHolderKiB,
    compilerKiB: compilerKiB,
    passTempKiB: passTempKiB,
    emitTimeMs: emitTimeMs,
    regAllocTimeMs: regAllocTimeMs,
    error: error,
  );
}

/// Generates a complex A64 function with many virtual registers to stress the RA.
RegAllocBenchResult runA64RegAllocBenchmark(int complexity, bool verbose) {
  final labelCount = 3 + complexity;
  final regCount = 10 + complexity * 3;

  final emitSw = Stopwatch()..start();

  final env = Environment.aarch64();
  final builder = A64CodeBuilder.create(env: env);
  builder.setStackSize(regCount * 8); // Ensure enough stack space

  final regs = <A64Gp>[];

  // Create labels
  final labels = <Label>[];
  for (var i = 0; i < labelCount; i++) {
    labels.add(builder.newLabel());
  }
  final boundLabels = <Label>{};

  // Create virtual registers
  for (var i = 0; i < regCount; i++) {
    regs.add(builder.newGpReg());
  }

  // Initialize registers
  for (var i = 0; i < regs.length; i++) {
    builder.mov(regs[i], x0);
    builder.add(regs[i], regs[i], i);
  }

  // Generate some computation
  for (var i = 0; i < complexity; i++) {
    final a = regs[i % regs.length];
    final b = regs[(i + 1) % regs.length];
    final c = regs[(i + 2) % regs.length];

    builder.add(a, a, b);
    builder.sub(b, b, c);
    builder.eor(c, c, a);

    if (i % 16 == 0 && labels.isNotEmpty) {
      final labelIdx = (i ~/ 16) % labels.length;
      final label = labels[labelIdx];
      builder.b(label);
      if (!boundLabels.contains(label)) {
        builder.label(label);
        boundLabels.add(label);
      }
    }
  }

  // Bind remaining labels
  for (var i = 0; i < labels.length; i++) {
    if (!boundLabels.contains(labels[i])) {
      builder.label(labels[i]);
      boundLabels.add(labels[i]);
    }
  }

  // Return sum
  final sum = builder.newGpReg();
  builder.mov(sum, xzr);
  for (var i = 0; i < (regs.length > 20 ? 20 : regs.length); i++) {
    builder.add(sum, sum, regs[i]);
  }
  builder.mov(x0, sum);
  builder.ret();

  emitSw.stop();
  final emitTimeMs = emitSw.elapsedMicroseconds / 1000.0;

  // Now run RA and finalize
  final raSw = Stopwatch()..start();

  String? error;
  int codeSize = 0;
  double codeHolderKiB = 0;
  double compilerKiB = 0;
  double passTempKiB = 0;

  try {
    final finalized = builder.finalize();
    codeSize = finalized.textBytes.length;
    codeHolderKiB = builder.code.text.buffer.length / 1024.0;
    compilerKiB = builder.nodeCount * 64 / 1024.0;
  } catch (e, st) {
    error = e.toString().split(':').first;
    codeSize = builder.code.text.buffer.length;
    codeHolderKiB = builder.code.text.buffer.length / 1024.0;
    compilerKiB = builder.nodeCount * 64 / 1024.0;
    if (verbose) {
      // Ignore: debugging bench failures only.
      // ignore: avoid_print
      print('[AArch64] RegAlloc error: $e');
      // ignore: avoid_print
      print(st);
    }
  }

  raSw.stop();
  final regAllocTimeMs = raSw.elapsedMicroseconds / 1000.0;

  return RegAllocBenchResult(
    arch: 'AArch64',
    complexity: complexity,
    labelCount: labelCount,
    regCount: regCount,
    codeSize: codeSize,
    codeHolderKiB: codeHolderKiB,
    compilerKiB: compilerKiB,
    passTempKiB: passTempKiB,
    emitTimeMs: emitTimeMs,
    regAllocTimeMs: regAllocTimeMs,
    error: error,
  );
}
