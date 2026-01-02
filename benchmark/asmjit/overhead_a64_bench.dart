import 'dart:io';
import 'package:asmjit/asmjit.dart' as asmjit;
import 'package:asmjit/src/asmjit/x86/x86_compiler.dart';
import 'package:asmjit/src/asmjit/x86/x86_assembler.dart';
import 'package:asmjit/src/asmjit/arm/a64_compiler.dart';
import 'package:asmjit/src/asmjit/arm/a64_assembler.dart';

enum InitStrategy { kInitReset, kReinit }

void benchCodeHolder(InitStrategy strategy, int count, asmjit.Environment env) {
  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final code = asmjit.CodeHolder(env: env);
      code.reset();
    }
  } else {
    final code = asmjit.CodeHolder(env: env);
    for (var i = 0; i < count; i++) {
      code.reinit();
    }
  }
}

void emitRawFunc(asmjit.BaseEmitter emitter) {
  if (emitter is X86Assembler) {
    emitter.mov(asmjit.eax, 0);
    emitter.ret();
  } else if (emitter is A64Assembler) {
    emitter.movz(asmjit.w0, 0);
    emitter.ret(asmjit.x30);
  }
}

void compileRawFunc(asmjit.BaseCompiler cc) {
  if (cc is X86Compiler) {
    final r = cc.newGp32();
    cc.mov(r, asmjit.Imm(0));
    cc.ret();
  } else if (cc is A64Compiler) {
    final r = cc.newGp32();
    cc.mov(r, asmjit.Imm(0));
    cc.ret();
  }
}

void benchAssembler(InitStrategy strategy, int count, asmjit.Arch arch,
    asmjit.Environment env) {
  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final code = asmjit.CodeHolder(env: env);
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        X86Assembler(code);
      } else {
        A64Assembler(code);
      }
      code.reset();
    }
  } else {
    final code = asmjit.CodeHolder(env: env);
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      X86Assembler(code);
    } else {
      A64Assembler(code);
    }
    for (var i = 0; i < count; i++) {
      code.reinit();
    }
  }
}

void benchAssemblerFunc(InitStrategy strategy, int count, asmjit.Arch arch,
    asmjit.Environment env) {
  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final code = asmjit.CodeHolder(env: env);
      final asmjit.BaseEmitter a;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        a = X86Assembler(code);
      } else {
        a = A64Assembler(code);
      }
      emitRawFunc(a);
      code.reset();
    }
  } else {
    final code = asmjit.CodeHolder(env: env);
    final asmjit.BaseEmitter a;
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      a = X86Assembler(code);
    } else {
      a = A64Assembler(code);
    }
    for (var i = 0; i < count; i++) {
      code.reinit();
      emitRawFunc(a);
    }
  }
}

void benchCompiler(InitStrategy strategy, int count, asmjit.Arch arch,
    asmjit.Environment env) {
  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final asmjit.BaseCompiler cc;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        cc = X86Compiler(env: env);
      } else {
        cc = A64Compiler(env: env);
      }
      cc.clear();
    }
  } else {
    final asmjit.BaseCompiler cc;
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      cc = X86Compiler(env: env);
    } else {
      cc = A64Compiler(env: env);
    }
    for (var i = 0; i < count; i++) {
      cc.clear();
    }
  }
}

void benchCompilerFunc(InitStrategy strategy, int count, asmjit.Arch arch,
    asmjit.Environment env, bool finalize) {
  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final asmjit.BaseCompiler cc;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        cc = X86Compiler(env: env);
      } else {
        cc = A64Compiler(env: env);
      }

      cc.addFunc(asmjit.FuncSignature.noArgs(ret: asmjit.TypeId.int32));
      compileRawFunc(cc);
      cc.endFunc();

      if (finalize) {
        cc.finalize();
      }

      cc.clear();
    }
  } else {
    final asmjit.BaseCompiler cc;
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      cc = X86Compiler(env: env);
    } else {
      cc = A64Compiler(env: env);
    }

    for (var i = 0; i < count; i++) {
      cc.clear();

      cc.addFunc(asmjit.FuncSignature.noArgs(ret: asmjit.TypeId.int32));
      compileRawFunc(cc);
      cc.endFunc();

      if (finalize) {
        cc.finalize();
      }
    }
  }
}

void testPerf(String benchName, InitStrategy strategy, int n,
    void Function(InitStrategy, int) fn) {
  final strategyName =
      strategy == InitStrategy.kInitReset ? "init/reset" : "reinit    ";

  final sw = Stopwatch()..start();
  fn(strategy, n);
  sw.stop();

  final durationMs = sw.elapsedMicroseconds / 1000.0;
  stdout.writeln(
      '${benchName.padRight(31)} [$strategyName]: ${durationMs.toStringAsFixed(3).padLeft(8)} [ms]');
}

void testPerfAll(InitStrategy strategy, int n) {
  final targetArch = asmjit.Arch.aarch64;
  final env = asmjit.Environment.aarch64();

  testPerf(
      "CodeHolder (Only)", strategy, n, (s, n) => benchCodeHolder(s, n, env));

  testPerf("Assembler", strategy, n,
      (s, n) => benchAssembler(s, n, targetArch, env));
  testPerf("Assembler + Func", strategy, n,
      (s, n) => benchAssemblerFunc(s, n, targetArch, env));
//   testPerf("Assembler + Func + RT", strategy, n,
//       (s, n) => benchAssemblerFuncRT(s, n, targetArch, env));

  testPerf(
      "Compiler", strategy, n, (s, n) => benchCompiler(s, n, targetArch, env));
  testPerf("Compiler + Func", strategy, n,
      (s, n) => benchCompilerFunc(s, n, targetArch, env, false));
  testPerf("Compiler + Func + Finalize", strategy, n,
      (s, n) => benchCompilerFunc(s, n, targetArch, env, true));
//   testPerf("Compiler + Func + Finalize + RT", strategy, n,
//       (s, n) => benchCompilerFuncRT(s, n, targetArch, env));
}

void main(List<String> args) {
  int n = 10000; // Increased count to measure overhead better
  if (args.contains("--count")) {
    final idx = args.indexOf("--count");
    if (idx + 1 < args.length) {
      n = int.tryParse(args[idx + 1]) ?? n;
    }
  } else if (args.any((a) => a.startsWith("--count="))) {
    final arg = args.firstWhere((a) => a.startsWith("--count="));
    n = int.tryParse(arg.substring(8)) ?? n;
  }

  stdout.writeln("AsmJit Benchmark Overhead [Arch=AArch64 (forced)]");
  stdout.writeln("Iterations: $n\n");

  testPerfAll(InitStrategy.kInitReset, n);
  stdout.writeln();
  testPerfAll(InitStrategy.kReinit, n);
}
