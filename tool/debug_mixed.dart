import 'dart:ffi';
import 'dart:io';
import 'package:asmjit/asmjit.dart';

void main() async {
  final runtime = JitRuntime();
  final code = CodeHolder(env: runtime.environment);
  final cc =
      UniCompiler(X86Compiler(env: code.env, labelManager: code.labelManager));

  // Build function: double f(double a, int b, double c) => a + b + c;
  cc.addFunc(FuncSignature.build(
      [TypeId.float64, TypeId.intPtr, TypeId.float64],
      TypeId.float64,
      CallConvId.x64Windows));

  final a = cc.newVec('a');
  final b = cc.newGpPtr('b');
  final c = cc.newVec('c');
  cc.setArg(0, a);
  cc.setArg(1, b);
  cc.setArg(2, c);

  final tmp = cc.newVec('tmp');
  final bDouble = cc.newVec('bDouble');
  cc.emitCV(UniOpCV.cvtI2D, bDouble, b);
  cc.emit3v(UniOpVVV.addF64S, tmp, a, bDouble);
  cc.emit3v(UniOpVVV.addF64S, tmp, tmp, c);
  cc.ret([tmp]);
  cc.endFunc();

  cc.finalize();
  final assembler = X86Assembler(code);
  cc.serializeToAssembler(assembler);

  final bytes = code.text.buffer.bytes;
  final outFile = File('mixed.bin');
  await outFile.writeAsBytes(bytes);
  print('Wrote mixed.bin (${bytes.length} bytes)');

  // Run the JITed function to verify the result matches expectations.
  final fn = runtime.add(code);
  final callable = fn.pointer
      .cast<NativeFunction<Double Function(Double, IntPtr, Double)>>()
      .asFunction<double Function(double, int, double)>();
  final result = callable(10.5, 20, 30.5);
  print('JIT result: $result');

  // Try objdump if available in PATH or typical MinGW location.
  final objdumpCandidates = ['C:/gcc/bin/objdump.exe'];

  for (final bin in objdumpCandidates) {
    try {
      final res = await Process.run(bin,
          ['-D', '-b', 'binary', '-m', 'i386:x86-64', '-Mintel', 'mixed.bin']);
      if (res.exitCode == 0) {
        print('objdump from $bin');
        stdout.write(res.stdout);
        break;
      }
    } catch (_) {
      // ignore
    }
  }
}
