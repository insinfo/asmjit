import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:asmjit/asmjit.dart';
import 'dart:io';

void main() {
  print('Debugging AsmJit Win64 Register Scan...');
  print('OS: ${Platform.operatingSystem}');

  final runtime = JitRuntime();
  final env = Environment.host();
  final code = CodeHolder(env: env);
  final cc = X86Compiler(env: env, labelManager: code.labelManager);

  cc.addFunc(FuncSignature(
    args: [],
    retType: TypeId.int64, // Return Int64
    callConvId: CallConvId.cdecl,
  ));

  // Return RCX
  cc.mov(X86Gp.rax, X86Gp.rcx);

  cc.ret();
  cc.endFunc();
  cc.finalize();

  final asm = X86Assembler(code);
  cc.serializeToAssembler(asm);
  final func = runtime.add(code);

  final nativeFunc = func.pointer.cast<
      ffi.NativeFunction<
          ffi.Int64 Function(ffi.Pointer<ffi.Int64>, ffi.Int64, ffi.Int64,
              ffi.Int64, ffi.Int64)>>();

  final dartFunc = nativeFunc
      .asFunction<int Function(ffi.Pointer<ffi.Int64>, int, int, int, int)>();

  final outBuffer = pkgffi.calloc<ffi.Int64>(1);

  print('Calling JIT function...');
  final result = dartFunc(outBuffer, 2, 3, 4, 0);
  print('Returned: 0x${result.toRadixString(16)}');
  print('Expected (outBuffer): 0x${outBuffer.address.toRadixString(16)}');

  if (result == outBuffer.address) {
    print('SUCCESS: Arg 1 is in RCX (Win64)');
  } else {
    print('FAILURE: Arg 1 is NOT RCX');
  }

  pkgffi.calloc.free(outBuffer);
}
