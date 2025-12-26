/// AsmJit Dart - Overhead Benchmark
///
/// Port of asmjit-testing/bench/asmjit_bench_overhead.cpp
/// Benchmarks the cost of initialization, reset, and code execution.
// TODO: Align with C++ overhead bench (code.reset/init vs reinit semantics,
// error handler attachment, compiler paths, and RT coverage parity).

import 'dart:io';
import 'package:asmjit/asmjit.dart';

const int kDefaultIterations = 1000000;
const int kQuickIterations = 10000;

void main(List<String> args) {
  final quick = args.contains('--quick');
  final iterations = args.contains('--count')
      ? int.tryParse(args[args.indexOf('--count') + 1]) ?? kDefaultIterations
      : (quick ? kQuickIterations : kDefaultIterations);

  printAppInfo(iterations);

  print('X86/X64 Benchmarks:');
  print('=' * 60);
  runX86Benchmarks(iterations);

  print('');
  print('AArch64 Benchmarks:');
  print('=' * 60);
  runA64Benchmarks(iterations);
}

void printAppInfo(int n) {
  print('AsmJit Dart Benchmark Overhead v1.0.0 [Arch=X64] [Mode=Release]');
  print('');
  print(
      'This benchmark was designed to benchmark the cost of initialization and');
  print(
      'reset (or reinitialization) of CodeHolder and Emitters; and the cost of');
  print(
      'moving a minimal assembled function to executable memory. Each output line');
  print(
      'uses "<Test> [Func] [Finalize] [RT]" format, with the following meaning:');
  print('');
  print(
      '  - <Test>     - test case name - either \'CodeHolder\' only or an emitter');
  print('  - [Func]     - function was assembled');
  print('  - [Finalize] - function was finalized (Builder/Compiler)');
  print(
      '  - [RT]       - function was added to JitRuntime and then removed from it');
  print('');
  print('Essentially the output provides an insight into the cost of reusing');
  print(
      'CodeHolder and other emitters, and the cost of assembling, finalizing,');
  print(
      'and moving the assembled code into executable memory by separating each');
  print('phase.');
  print('');
  print('The number of iterations benchmarked: $n (override by --count=n)');
  print('');
}

void runX86Benchmarks(int n) {
  // CodeHolder only (init/reset)
  testPerf('CodeHolder (Only)', 'init/reset', n, () {
    final env = Environment.host();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      // reset is implicit when code goes out of scope
      code.text.buffer.length; // touch it
    }
  });

  // Assembler (init/reset)
  testPerf('Assembler', 'init/reset', n, () {
    final env = Environment.host();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);
      asm.offset; // touch it
    }
  });

  // Assembler + Func (init/reset)
  testPerf('Assembler + Func', 'init/reset', n, () {
    final env = Environment.host();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);
      asm.movRI(eax, 0);
      asm.ret();
    }
  });

  // Assembler + Func + RT (init/reset)
  testPerf('Assembler + Func + RT', 'init/reset', n, () {
    final env = Environment.host();
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);
      asm.movRI(eax, 0);
      asm.ret();
      final fn = runtime.add(code);
      runtime.release(fn);
    }
    runtime.dispose();
  });

  // Builder (init/reset)
  testPerf('Builder', 'init/reset', n, () {
    for (var i = 0; i < n; i++) {
      final builder = X86CodeBuilder.create();
      builder.offset; // touch it
    }
  });

  // Builder + Func (init/reset)
  testPerf('Builder + Func', 'init/reset', n, () {
    for (var i = 0; i < n; i++) {
      final builder = X86CodeBuilder.create();
      builder.mov(eax, 0);
      builder.ret();
    }
  });

  // Builder + Func + Finalize (init/reset)
  testPerf('Builder + Func + Finalize', 'init/reset', n, () {
    for (var i = 0; i < n; i++) {
      final builder = X86CodeBuilder.create();
      builder.mov(eax, 0);
      builder.ret();
      builder.finalize();
    }
  });

  // Builder + Func + Finalize + RT (init/reset)
  testPerf('Builder + Func + Finalize + RT', 'init/reset', n, () {
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      final builder = X86CodeBuilder.create();
      builder.mov(eax, 0);
      builder.ret();
      final fn = builder.build(runtime);
      fn.dispose();
    }
    runtime.dispose();
  });

  print('');

  // Reinit benchmarks (reuse same CodeHolder)
  testPerf('CodeHolder (Only)', 'reinit', n, () {
    final env = Environment.host();
    final code = CodeHolder(env: env);
    for (var i = 0; i < n; i++) {
      code.reinit();
    }
  });

  // Assembler reinit
  testPerf('Assembler', 'reinit', n, () {
    final env = Environment.host();
    final code = CodeHolder(env: env);
    final asm = X86Assembler(code);
    for (var i = 0; i < n; i++) {
      code.reinit();
      asm.offset; // touch it
    }
  });

  // Assembler + Func reinit
  testPerf('Assembler + Func', 'reinit', n, () {
    final env = Environment.host();
    final code = CodeHolder(env: env);
    final asm = X86Assembler(code);
    for (var i = 0; i < n; i++) {
      code.reinit();
      asm.movRI(eax, 0);
      asm.ret();
    }
  });

  // Assembler + Func + RT reinit
  testPerf('Assembler + Func + RT', 'reinit', n, () {
    final env = Environment.host();
    final code = CodeHolder(env: env);
    final asm = X86Assembler(code);
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      code.reinit();
      asm.movRI(eax, 0);
      asm.ret();
      final fn = runtime.add(code);
      runtime.release(fn);
    }
    runtime.dispose();
  });
}

void runA64Benchmarks(int n) {
  // CodeHolder only (init/reset)
  testPerf('CodeHolder (Only)', 'init/reset', n, () {
    final env = Environment.aarch64();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      code.text.buffer.length; // touch it
    }
  });

  // Assembler (init/reset)
  testPerf('A64Assembler', 'init/reset', n, () {
    final env = Environment.aarch64();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);
      asm.offset; // touch it
    }
  });

  // Assembler + Func (init/reset)
  testPerf('A64Assembler + Func', 'init/reset', n, () {
    final env = Environment.aarch64();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);
      asm.movz(w0, 0);
      asm.ret();
    }
  });

  // Builder (init/reset)
  testPerf('A64Builder', 'init/reset', n, () {
    final env = Environment.aarch64();
    for (var i = 0; i < n; i++) {
      final builder = A64CodeBuilder.create(env: env);
      builder.offset; // touch it
    }
  });

  // Builder + Func (init/reset)
  testPerf('A64Builder + Func', 'init/reset', n, () {
    final env = Environment.aarch64();
    for (var i = 0; i < n; i++) {
      final builder = A64CodeBuilder.create(env: env);
      builder.mov(w0, xzr);
      builder.ret();
    }
  });

  // Builder + Func + Finalize (init/reset)
  testPerf('A64Builder + Func + Finalize', 'init/reset', n, () {
    final env = Environment.aarch64();
    for (var i = 0; i < n; i++) {
      final builder = A64CodeBuilder.create(env: env);
      builder.mov(w0, xzr);
      builder.ret();
      builder.finalize();
    }
  });

  print('');

  // Reinit benchmarks
  testPerf('CodeHolder (Only)', 'reinit', n, () {
    final env = Environment.aarch64();
    final code = CodeHolder(env: env);
    for (var i = 0; i < n; i++) {
      code.reinit();
    }
  });

  // A64Assembler reinit
  testPerf('A64Assembler', 'reinit', n, () {
    final env = Environment.aarch64();
    final code = CodeHolder(env: env);
    final asm = A64Assembler(code);
    for (var i = 0; i < n; i++) {
      code.reinit();
      asm.offset; // touch it
    }
  });

  // A64Assembler + Func reinit
  testPerf('A64Assembler + Func', 'reinit', n, () {
    final env = Environment.aarch64();
    final code = CodeHolder(env: env);
    final asm = A64Assembler(code);
    for (var i = 0; i < n; i++) {
      code.reinit();
      asm.movz(w0, 0);
      asm.ret();
    }
  });
}

void testPerf(
    String benchName, String strategyName, int n, void Function() fn) {
  final sw = Stopwatch()..start();
  fn();
  sw.stop();
  final ms = sw.elapsedMilliseconds;
  stdout.writeln(
      '${benchName.padRight(32)} [$strategyName]: ${ms.toString().padLeft(8)} [ms]');
}
