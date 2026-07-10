// Stress reproducer for intermittent crash in Mixed Int/Float with XMM spill.
// Spawns isolates to compile/execute the same JIT function many times.
// Usage: dart run tool/repro_mixed_spill_stress.dart [iters] [workers]
// Defaults: iters=50, workers=4.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:asmjit/asmjit.dart';

Future<void> main(List<String> args) async {
  final iters = args.isNotEmpty ? int.tryParse(args[0]) ?? 50 : 50;
  final workers = args.length > 1 ? int.tryParse(args[1]) ?? 4 : 4;

  stdout.writeln('Running $iters iterations per worker across $workers workers...');

  await Future.wait(List.generate(workers, (idx) {
    final dump = idx == 0; // dump code from first worker for disassembly.
    return Isolate.run(() => _runWorker(idx, iters, dumpOnce: dump));
  }));

  stdout.writeln('Done. If a crash did not occur, try increasing iters/workers.');
}

Future<void> _runWorker(int id, int iterations, {bool dumpOnce = false}) async {
  for (var i = 0; i < iterations; i++) {
    final runtime = JitRuntime();
    final code = CodeHolder(env: runtime.environment);

    final cc = UniCompiler.auto(
      code: code,
      ctRef: const VecConstTableRef(null, VecConstTable.kSize),
    );

    cc.addFunc(
      FuncSignature.build(
        [TypeId.float64, TypeId.intPtr, TypeId.float64],
        TypeId.float64,
        CallConvId.x64Windows,
      ),
    );

    final a = cc.newVec('a');
    final b = cc.newGpPtr('b');
    final c = cc.newVec('c');

    cc.setArg(0, a);
    cc.setArg(1, b);
    cc.setArg(2, c);

    final bDouble = cc.newVec('bDouble');
    cc.emitCV(UniOpCV.cvtI2D, bDouble, b);

    final tmp = cc.newVec('tmp');
    cc.emit3v(UniOpVVV.addF64S, tmp, a, c);

    const tempCount = 12;
    final temps = <BaseReg>[];
    for (int t = 0; t < tempCount; t++) {
      final reg = cc.newVec('t$t');
      temps.add(reg);
      cc.emit3v(UniOpVVV.addF64S, reg, a, c);
    }

    for (final reg in temps) {
      cc.emit3v(UniOpVVV.addF64S, tmp, tmp, reg);
    }

    cc.emit3v(UniOpVVV.addF64S, tmp, tmp, bDouble);

    cc.ret([tmp]);
    cc.endFunc();

    cc.cc.finalize();

    if (code.env.arch == Arch.x64) {
      final asm = X86Assembler(code);
      cc.cc.serializeToAssembler(asm);
    } else {
      final asm = A64Assembler(code);
      cc.cc.serializeToAssembler(asm);
    }

    final finalized = code.finalize();
    if (dumpOnce) {
      dumpOnce = false;
      final bytes = finalized.textBytes;
      final out = File('build/repro_mixed_spill_worker$id.bin');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytes, flush: true);
      stdout.writeln('Worker $id dumped code to ${out.path}');
    }

    final fn = runtime.addBytes(finalized.textBytes);

    final func = fn.pointer
        .cast<NativeFunction<Double Function(Double, IntPtr, Double)>>()
        .asFunction<double Function(double, int, double)>();

    const aVal = 1.5;
    const cVal = 2.5;
    const bVal = 3;
    final expected = (aVal + cVal) * (tempCount + 1) + bVal;
    final result = func(aVal, bVal, cVal);

    if ((result - expected).abs() > 0.0001) {
      throw StateError('Worker $id iter $i mismatch: $result != $expected');
    }
  }
}
