import 'dart:math';
import 'package:asmjit/asmjit.dart' as asmjit;
import 'package:asmjit/src/asmjit/x86/x86_compiler.dart';
import 'package:asmjit/src/asmjit/x86/x86_assembler.dart';
import 'package:asmjit/src/asmjit/arm/a64_compiler.dart';
import 'package:asmjit/src/asmjit/arm/a64_assembler.dart';

const int kLocalRegCount = 4;
const int kLocalOpCount = 13;

void emitCodeX86(X86Compiler cc, int complexity, int regCount) {
  final rnd = Random(0x1234);

  final labels = <asmjit.Label>[];
  final usedLabels = List<int>.filled(complexity, 0);
  final virtRegs = <asmjit.X86Xmm>[];

  final argPtr = cc.newGpPtr("arg_ptr");
  final counter = cc.newGpPtr("counter");

  for (var i = 0; i < complexity; i++) {
    labels.add(cc.newLabel());
  }

  for (var i = 0; i < regCount; i++) {
    virtRegs.add(cc.newXmmF64x1("v$i"));
  }

  final func = cc.addFunc(asmjit.FuncSignature.build(
      [asmjit.TypeId.intPtr, asmjit.TypeId.intPtr], asmjit.TypeId.void_));

  // Fix: setArg takes (argIndex, valueIndex, reg)
  func.setArg(0, 0, counter);
  func.setArg(1, 0, argPtr);

  for (var i = 0; i < regCount; i++) {
    final offset = i * 8;
    final mem = asmjit.X86Mem.base(argPtr, disp: offset);
    cc.vmovsd(virtRegs[i], mem);
  }

  asmjit.Label nextLabel() {
    var id = rnd.nextInt(complexity);
    if (usedLabels[id] > 1) {
      id = 0;
      do {
        if (++id >= complexity) id = 0;
      } while (usedLabels[id] != 0);
    }
    usedLabels[id]++;
    return labels[id];
  }

  for (var i = 0; i < labels.length; i++) {
    cc.bind(labels[i]);

    final locals = List<asmjit.X86Xmm>.generate(
        kLocalRegCount, (j) => cc.newXmmF64x1("local$j"));

    final localOpThreshold = kLocalOpCount - kLocalRegCount;

    for (var j = 0; j < 15; j++) {
      final op = rnd.nextInt(6);
      final id1 = rnd.nextInt(regCount);
      final id2 = rnd.nextInt(regCount);

      var v0 = virtRegs[id1];
      var v1 = virtRegs[id1];
      var v2 = virtRegs[id2];

      if (j < kLocalRegCount) {
        v0 = locals[j];
      }

      if (j >= localOpThreshold && (j - localOpThreshold) < kLocalRegCount) {
        v2 = locals[j - localOpThreshold];
      }

      switch (op) {
        case 0:
          cc.vaddsd(v0, v1, v2);
          break;
        case 1:
          cc.vsubsd(v0, v1, v2);
          break;
        case 2:
          cc.vmulsd(v0, v1, v2);
          break;
        case 3:
          cc.vdivsd(v0, v1, v2);
          break;
        case 4:
          cc.vminsd(v0, v1, v2);
          break;
        case 5:
          cc.vmaxsd(v0, v1, v2);
          break;
      }
    }

    cc.sub(counter, asmjit.Imm(1));
    cc.jns(nextLabel());
  }

  for (var i = 0; i < regCount; i++) {
    final offset = i * 8;
    cc.vmovsd(asmjit.X86Mem.base(argPtr, disp: offset), virtRegs[i]);
  }

  cc.endFunc();
}

void emitCodeA64(A64Compiler cc, int complexity, int regCount) {
  final rnd = Random(0x1234);

  final labels = <asmjit.Label>[];
  final usedLabels = List<int>.filled(complexity, 0);
  final virtRegs = <asmjit.A64Vec>[];

  final argPtr = cc.newGpPtr("arg_ptr");
  final counter = cc.newGpPtr("counter");

  for (var i = 0; i < complexity; i++) {
    labels.add(cc.newLabel());
  }

  for (var i = 0; i < regCount; i++) {
    virtRegs.add(cc.newVecD("v$i"));
  }

  final func = cc.addFunc(asmjit.FuncSignature.build(
      [asmjit.TypeId.intPtr, asmjit.TypeId.intPtr], asmjit.TypeId.void_));

  // Fix: setArg takes (argIndex, valueIndex, reg)
  func.setArg(0, 0, counter);
  func.setArg(1, 0, argPtr);

  for (var i = 0; i < regCount; i++) {
    final offset = (i * 8) & 1023;
    cc.ldr(virtRegs[i], argPtr, asmjit.Imm(offset));
  }

  asmjit.Label nextLabel() {
    var id = rnd.nextInt(complexity);
    if (usedLabels[id] > 1) {
      id = 0;
      do {
        if (++id >= complexity) id = 0;
      } while (usedLabels[id] != 0);
    }
    usedLabels[id]++;
    return labels[id];
  }

  for (var i = 0; i < labels.length; i++) {
    cc.bind(labels[i]);

    final locals = List<asmjit.A64Vec>.generate(
        kLocalRegCount, (j) => cc.newVecD("local$j"));

    final localOpThreshold = kLocalOpCount - kLocalRegCount;

    for (var j = 0; j < 15; j++) {
      final op = rnd.nextInt(6);
      final id1 = rnd.nextInt(regCount);
      final id2 = rnd.nextInt(regCount);

      var v0 = virtRegs[id1];
      var v1 = virtRegs[id1];
      var v2 = virtRegs[id2];

      if (j < kLocalRegCount) {
        v0 = locals[j];
      }

      if (j >= localOpThreshold && (j - localOpThreshold) < kLocalRegCount) {
        v2 = locals[j - localOpThreshold];
      }

      switch (op) {
        case 0:
          cc.fadd(v0, v1, v2);
          break;
        case 1:
          cc.fsub(v0, v1, v2);
          break;
        case 2:
          cc.fmul(v0, v1, v2);
          break;
        case 3:
          cc.fdiv(v0, v1, v2);
          break;
        case 4:
          cc.fmin(v0, v1, v2);
          break;
        case 5:
          cc.fmax(v0, v1, v2);
          break;
      }
    }

    cc.subs(counter, counter, asmjit.Imm(1));
    cc.bHi(nextLabel());
  }

  for (var i = 0; i < regCount; i++) {
    final offset = (i * 8) & 1023;
    cc.str(virtRegs[i], argPtr, asmjit.Imm(offset));
  }

  cc.endFunc();
}

void main() {
  final numIterations = 10;
  final complexity = 64;
  final regCount = 16;

  try {
    final env = asmjit.Environment.x64Windows();
    final code = asmjit.CodeHolder(env: env);

    print("Benchmarking X86 RegAlloc...");
    final timer = Stopwatch();
    timer.start();
    for (var i = 0; i < numIterations; i++) {
      code.reset();
      final asm = X86Assembler(code);
      final cc = X86Compiler(env: env, labelManager: code.labelManager);
      emitCodeX86(cc, complexity, regCount);
      cc.finalize();
      cc.serializeToAssembler(asm);
    }
    timer.stop();
    print("X86 Time: ${timer.elapsedMilliseconds} ms");
  } catch (e) {
    print("Skipping X86: $e");
  }

  try {
    final env = asmjit.Environment.aarch64(); // Fixed
    final code = asmjit.CodeHolder(env: env);

    print("Benchmarking AArch64 RegAlloc...");
    final timer = Stopwatch();
    timer.start();
    for (var i = 0; i < numIterations; i++) {
      code.reset();
      final asm = A64Assembler(code);
      final cc = A64Compiler(env: env, labelManager: code.labelManager);
      emitCodeA64(cc, complexity, regCount);
      cc.finalize();
      cc.serializeToAssembler(asm);
    }
    timer.stop();
    print("A64 Time: ${timer.elapsedMilliseconds} ms");
  } catch (e) {
    print("Skipping A64: $e");
  }
}
