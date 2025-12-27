/// AsmJit Dart - Overhead Benchmark
///
/// Port of asmjit-testing/bench/asmjit_bench_overhead.cpp
/// Benchmarks the cost of initialization, reset, and code execution.

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
      _emitX86RawFunc(asm);
    }
  });

  // Assembler + Func + RT (init/reset)
  testPerf('Assembler + Func + RT', 'init/reset', n, () {
    final env = Environment.host();
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);
      _emitX86RawFunc(asm);
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
      _emitX86BuilderRaw(builder);
    }
  });

  // Builder + Func + Finalize (init/reset)
  testPerf('Builder + Func + Finalize', 'init/reset', n, () {
    for (var i = 0; i < n; i++) {
      final builder = X86CodeBuilder.create();
      _emitX86BuilderRaw(builder);
      builder.finalize();
    }
  });

  // Builder + Func + Finalize + RT (init/reset)
  testPerf('Builder + Func + Finalize + RT', 'init/reset', n, () {
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      final builder = X86CodeBuilder.create();
      _emitX86BuilderRaw(builder);
      final fn = builder.build(runtime);
      fn.dispose();
    }
    runtime.dispose();
  });

  // Compiler (init/reset)
  testPerf('Compiler', 'init/reset', n, () {
    for (var i = 0; i < n; i++) {
      final compiler = X86Compiler.create();
      compiler.code.text.buffer.length; // touch it
    }
  });

  // Compiler + Func (init/reset)
  testPerf('Compiler + Func', 'init/reset', n, () {
    for (var i = 0; i < n; i++) {
      final compiler = X86Compiler.create();
      _emitX86CompilerRaw(compiler);
    }
  });

  // Compiler + Func + Finalize (init/reset)
  testPerf('Compiler + Func + Finalize', 'init/reset', n, () {
    for (var i = 0; i < n; i++) {
      final compiler = X86Compiler.create();
      _emitX86CompilerRaw(compiler);
      compiler.finalize();
    }
  });

  // Compiler + Func + Finalize + RT (init/reset)
  testPerf('Compiler + Func + Finalize + RT', 'init/reset', n, () {
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      final compiler = X86Compiler.create();
      _emitX86CompilerRaw(compiler);
      final fn = compiler.build(runtime);
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
      _emitX86RawFunc(asm);
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
      _emitX86RawFunc(asm);
      final fn = runtime.add(code);
      runtime.release(fn);
    }
    runtime.dispose();
  });

  // Builder reinit
  testPerf('Builder', 'reinit', n, () {
    final builder = X86CodeBuilder.create();
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      builder.offset; // touch it
    }
  });

  // Builder + Func reinit
  testPerf('Builder + Func', 'reinit', n, () {
    final builder = X86CodeBuilder.create();
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      _emitX86BuilderRaw(builder);
    }
  });

  // Builder + Func + Finalize reinit
  testPerf('Builder + Func + Finalize', 'reinit', n, () {
    final builder = X86CodeBuilder.create();
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      _emitX86BuilderRaw(builder);
      builder.finalize();
    }
  });

  // Builder + Func + Finalize + RT reinit
  testPerf('Builder + Func + Finalize + RT', 'reinit', n, () {
    final runtime = JitRuntime();
    final builder = X86CodeBuilder.create();
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      _emitX86BuilderRaw(builder);
      final fn = builder.build(runtime);
      fn.dispose();
    }
    runtime.dispose();
  });

  // Compiler reinit
  testPerf('Compiler', 'reinit', n, () {
    final compiler = X86Compiler.create();
    for (var i = 0; i < n; i++) {
      compiler.code.reinit();
      compiler.builder.clear();
      compiler.code.text.buffer.length; // touch it
    }
  });

  // Compiler + Func reinit
  testPerf('Compiler + Func', 'reinit', n, () {
    final compiler = X86Compiler.create();
    for (var i = 0; i < n; i++) {
      compiler.code.reinit();
      compiler.builder.clear();
      _emitX86CompilerRaw(compiler);
    }
  });

  // Compiler + Func + Finalize reinit
  testPerf('Compiler + Func + Finalize', 'reinit', n, () {
    final compiler = X86Compiler.create();
    for (var i = 0; i < n; i++) {
      compiler.code.reinit();
      compiler.builder.clear();
      _emitX86CompilerRaw(compiler);
      compiler.finalize();
    }
  });

  // Compiler + Func + Finalize + RT reinit
  testPerf('Compiler + Func + Finalize + RT', 'reinit', n, () {
    final runtime = JitRuntime();
    final compiler = X86Compiler.create();
    for (var i = 0; i < n; i++) {
      compiler.code.reinit();
      compiler.builder.clear();
      _emitX86CompilerRaw(compiler);
      final fn = compiler.build(runtime);
      fn.dispose();
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
      _emitA64RawFunc(asm);
    }
  });

  // Assembler + Func + RT (init/reset)
  testPerf('A64Assembler + Func + RT', 'init/reset', n, () {
    final env = Environment.aarch64();
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);
      _emitA64RawFunc(asm);
      final fn = runtime.add(code);
      runtime.release(fn);
    }
    runtime.dispose();
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
      _emitA64BuilderRaw(builder);
    }
  });

  // Builder + Func + Finalize (init/reset)
  testPerf('A64Builder + Func + Finalize', 'init/reset', n, () {
    final env = Environment.aarch64();
    for (var i = 0; i < n; i++) {
      final builder = A64CodeBuilder.create(env: env);
      _emitA64BuilderRaw(builder);
      builder.finalize();
    }
  });

  // Builder + Func + Finalize + RT (init/reset)
  testPerf('A64Builder + Func + Finalize + RT', 'init/reset', n, () {
    final env = Environment.aarch64();
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      final builder = A64CodeBuilder.create(env: env);
      _emitA64BuilderRaw(builder);
      final fn = builder.build(runtime);
      fn.dispose();
    }
    runtime.dispose();
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
      _emitA64RawFunc(asm);
    }
  });

  // A64Assembler + Func + RT reinit
  testPerf('A64Assembler + Func + RT', 'reinit', n, () {
    final env = Environment.aarch64();
    final code = CodeHolder(env: env);
    final asm = A64Assembler(code);
    final runtime = JitRuntime();
    for (var i = 0; i < n; i++) {
      code.reinit();
      _emitA64RawFunc(asm);
      final fn = runtime.add(code);
      runtime.release(fn);
    }
    runtime.dispose();
  });

  // A64Builder reinit
  testPerf('A64Builder', 'reinit', n, () {
    final env = Environment.aarch64();
    final builder = A64CodeBuilder.create(env: env);
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      builder.offset; // touch it
    }
  });

  // A64Builder + Func reinit
  testPerf('A64Builder + Func', 'reinit', n, () {
    final env = Environment.aarch64();
    final builder = A64CodeBuilder.create(env: env);
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      _emitA64BuilderRaw(builder);
    }
  });

  // A64Builder + Func + Finalize reinit
  testPerf('A64Builder + Func + Finalize', 'reinit', n, () {
    final env = Environment.aarch64();
    final builder = A64CodeBuilder.create(env: env);
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      _emitA64BuilderRaw(builder);
      builder.finalize();
    }
  });

  // A64Builder + Func + Finalize + RT reinit
  testPerf('A64Builder + Func + Finalize + RT', 'reinit', n, () {
    final env = Environment.aarch64();
    final runtime = JitRuntime();
    final builder = A64CodeBuilder.create(env: env);
    for (var i = 0; i < n; i++) {
      builder.code.reinit();
      builder.clear();
      _emitA64BuilderRaw(builder);
      final fn = builder.build(runtime);
      fn.dispose();
    }
    runtime.dispose();
  });
}

void _emitX86RawFunc(X86Assembler asm) {
  asm.movRI(eax, 0);
  asm.ret();
}

void _emitX86BuilderRaw(X86CodeBuilder builder) {
  builder.mov(eax, 0);
  builder.ret();
}

void _emitX86CompilerRaw(X86Compiler compiler) {
  compiler.addFunc(FuncSignature.noArgs(ret: TypeId.int32));
  compiler.endFunc();
}

void _emitA64RawFunc(A64Assembler asm) {
  asm.movz(w0, 0);
  asm.ret();
}

void _emitA64BuilderRaw(A64CodeBuilder builder) {
  builder.mov(w0, xzr);
  builder.ret();
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
