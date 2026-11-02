import 'package:asmjit/asmjit.dart';

// Rebuilds the "Pointer Access (Context)" function from
// test/problema/integration_abi_test.dart and hexdumps the machine code.
void main() {
  final runtime = JitRuntime();
  final code = CodeHolder(env: runtime.environment);
  final archCompiler =
      X86Compiler(env: code.env, labelManager: code.labelManager);
  final cc = UniCompiler(archCompiler);

  cc.addFunc(FuncSignature.build(
      [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.x64Windows));

  final ctx = cc.newGpPtr('ctx');
  final val = cc.newGpPtr('val');
  cc.setArg(0, ctx);
  cc.setArg(1, val);

  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx, 0)), val);
  cc.emit3i(UniOpRRR.add, val, val, Imm(1));
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx, 4)), val);

  cc.ret();
  cc.endFunc();

  archCompiler.finalize();
  final assembler = X86Assembler(code);
  archCompiler.serializeToAssembler(assembler);

  final finalized = code.finalize();
  final bytes = finalized.textBytes;

  final sb = StringBuffer();
  for (int i = 0; i < bytes.length; i++) {
    sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    sb.write(' ');
    if ((i + 1) % 16 == 0) sb.writeln();
  }
  print(sb);
}
