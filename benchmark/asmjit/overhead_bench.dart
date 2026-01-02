import 'dart:io';
import 'package:asmjit/asmjit.dart' as asmjit;

enum InitStrategy { kInitReset, kReinit }

void benchCodeHolder(InitStrategy strategy, int count) {
  final env = asmjit.Environment.host();

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
  if (emitter is asmjit.X86Assembler) {
    emitter.mov(asmjit.eax, 0);
    emitter.ret();
  } else if (emitter is asmjit.A64Assembler) {
    emitter.movz(asmjit.w0, 0);
    emitter.ret(asmjit.x30);
  }
}

void compileRawFunc(asmjit.BaseCompiler cc) {
  if (cc is asmjit.X86Compiler) {
    final r = cc.newGp32();
    cc.mov(r, asmjit.Imm(0));
    cc.ret();
  } else if (cc is asmjit.A64Compiler) {
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
        asmjit.X86Assembler(code);
      } else {
        asmjit.A64Assembler(code);
      }
      code.reset();
    }
  } else {
    final code = asmjit.CodeHolder(env: env);
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      asmjit.X86Assembler(code);
    } else {
      asmjit.A64Assembler(code);
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
        a = asmjit.X86Assembler(code);
      } else {
        a = asmjit.A64Assembler(code);
      }
      emitRawFunc(a);
      code.reset();
    }
  } else {
    final code = asmjit.CodeHolder(env: env);
    final asmjit.BaseEmitter a;
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      a = asmjit.X86Assembler(code);
    } else {
      a = asmjit.A64Assembler(code);
    }
    for (var i = 0; i < count; i++) {
      code.reinit();
      emitRawFunc(a);
    }
  }
}

void benchAssemblerFuncRT(InitStrategy strategy, int count, asmjit.Arch arch,
    asmjit.Environment env) {
  final rt = asmjit.JitRuntime(environment: env);

  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final code = asmjit.CodeHolder(env: env);
      final asmjit.BaseEmitter a;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        a = asmjit.X86Assembler(code);
      } else {
        a = asmjit.A64Assembler(code);
      }
      emitRawFunc(a);

      final fn = rt.add(code);
      fn.dispose();

      code.reset();
    }
  } else {
    final code = asmjit.CodeHolder(env: env);
    final asmjit.BaseEmitter a;
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      a = asmjit.X86Assembler(code);
    } else {
      a = asmjit.A64Assembler(code);
    }

    for (var i = 0; i < count; i++) {
      code.reinit();
      emitRawFunc(a);

      final fn = rt.add(code);
      fn.dispose();
    }
  }
}

void benchCompiler(InitStrategy strategy, int count, asmjit.Arch arch,
    asmjit.Environment env) {
  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final asmjit.BaseCompiler cc;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        cc = asmjit.X86Compiler(env: env);
      } else {
        cc = asmjit.A64Compiler(env: env);
      }
      cc.clear();
    }
  } else {
    final asmjit.BaseCompiler cc;
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      cc = asmjit.X86Compiler(env: env);
    } else {
      cc = asmjit.A64Compiler(env: env);
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
        cc = asmjit.X86Compiler(env: env);
      } else {
        cc = asmjit.A64Compiler(env: env);
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
      cc = asmjit.X86Compiler(env: env);
    } else {
      cc = asmjit.A64Compiler(env: env);
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

void benchCompilerFuncRT(InitStrategy strategy, int count, asmjit.Arch arch,
    asmjit.Environment env) {
  final rt = asmjit.JitRuntime(environment: env);

  if (strategy == InitStrategy.kInitReset) {
    for (var i = 0; i < count; i++) {
      final asmjit.BaseCompiler cc;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        cc = asmjit.X86Compiler(env: env);
      } else {
        cc = asmjit.A64Compiler(env: env);
      }

      cc.addFunc(asmjit.FuncSignature.noArgs(ret: asmjit.TypeId.int32));
      compileRawFunc(cc);
      cc.endFunc();
      cc.finalize();

      final code = asmjit.CodeHolder(env: env);
      final asmjit.BaseEmitter a;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        a = asmjit.X86Assembler(code);
      } else {
        a = asmjit.A64Assembler(code);
      }
      cc.serializeToAssembler(a);

      final fn = rt.add(code);
      fn.dispose();

      cc.clear();
    }
  } else {
    final asmjit.BaseCompiler cc;
    if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
      cc = asmjit.X86Compiler(env: env);
    } else {
      cc = asmjit.A64Compiler(env: env);
    }

    for (var i = 0; i < count; i++) {
      cc.clear();

      cc.addFunc(asmjit.FuncSignature.noArgs(ret: asmjit.TypeId.int32));
      compileRawFunc(cc);
      cc.endFunc();
      cc.finalize();

      final code = asmjit.CodeHolder(env: env);
      final asmjit.BaseEmitter a;
      if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
        a = asmjit.X86Assembler(code);
      } else {
        a = asmjit.A64Assembler(code);
      }
      cc.serializeToAssembler(a);

      final fn = rt.add(code);
      fn.dispose();
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
  final hostArch = asmjit.Arch.host;
  final env = asmjit.Environment.host();

  testPerf("CodeHolder (Only)", strategy, n, (s, n) => benchCodeHolder(s, n));

  testPerf(
      "Assembler", strategy, n, (s, n) => benchAssembler(s, n, hostArch, env));
  testPerf("Assembler + Func", strategy, n,
      (s, n) => benchAssemblerFunc(s, n, hostArch, env));
  testPerf("Assembler + Func + RT", strategy, n,
      (s, n) => benchAssemblerFuncRT(s, n, hostArch, env));

  testPerf(
      "Compiler", strategy, n, (s, n) => benchCompiler(s, n, hostArch, env));
  testPerf("Compiler + Func", strategy, n,
      (s, n) => benchCompilerFunc(s, n, hostArch, env, false));
  testPerf("Compiler + Func + Finalize", strategy, n,
      (s, n) => benchCompilerFunc(s, n, hostArch, env, true));
  testPerf("Compiler + Func + Finalize + RT", strategy, n,
      (s, n) => benchCompilerFuncRT(s, n, hostArch, env));
}

void main(List<String> args) {
  int n = 1000;
  if (args.contains("--count")) {
    final idx = args.indexOf("--count");
    if (idx + 1 < args.length) {
      n = int.tryParse(args[idx + 1]) ?? n;
    }
  } else if (args.any((a) => a.startsWith("--count="))) {
    final arg = args.firstWhere((a) => a.startsWith("--count="));
    n = int.tryParse(arg.substring(8)) ?? n;
  }

  stdout.writeln("AsmJit Benchmark Overhead [Arch=${asmjit.Arch.host.name}]");
  stdout.writeln("Iterations: $n\n");

  testPerfAll(InitStrategy.kInitReset, n);
  stdout.writeln();
  testPerfAll(InitStrategy.kReinit, n);
}
