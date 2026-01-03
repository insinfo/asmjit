import 'dart:ffi' as ffi;
import 'package:asmjit/asmjit.dart';

void main() {
  print('Testing simple UJIT function...');
  
  final runtime = JitRuntime();
  final code = CodeHolder(env: runtime.environment);
  final x86cc = X86Compiler(env: code.env, labelManager: code.labelManager);
  final cc = UniCompiler(x86cc);

  // Simple function: void test(ptr, ptr, int, ptr) - just returns
  cc.addFunc(FuncSignature.build(
      [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr, TypeId.intPtr],
      TypeId.void_,
      CallConvId.x64Windows));

  final arg0 = cc.newGpPtr('arg0');
  final arg1 = cc.newGpPtr('arg1');
  final arg2 = cc.newGpz('arg2');
  final arg3 = cc.newGpPtr('arg3');

  cc.setArg(0, arg0);
  cc.setArg(1, arg1);
  cc.setArg(2, arg2);
  cc.setArg(3, arg3);

  // Explicitly return
  cc.ret();
  
  cc.endFunc();

  x86cc.finalize();
  
  final asm = X86Assembler(code);
  x86cc.serializeToAssembler(asm);
  
  print('Generated ${code.text.buffer.length} bytes');
  
  // Print hex dump
  final bytes = code.text.buffer.bytes;
  print('Hex: ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  
  final fn = runtime.add(code);
  
  final funcPtr = fn.pointer.cast<
      ffi.NativeFunction<
          ffi.Void Function(
            ffi.Pointer<ffi.Uint8>,
            ffi.Pointer<ffi.Uint8>,
            ffi.IntPtr,
            ffi.Pointer<ffi.Uint8>,
          )>>();
  final dartFunc = funcPtr.asFunction<
      void Function(
        ffi.Pointer<ffi.Uint8>,
        ffi.Pointer<ffi.Uint8>,
        int,
        ffi.Pointer<ffi.Uint8>,
      )>();

  print('Calling function...');
  dartFunc(ffi.nullptr, ffi.nullptr, 0, ffi.nullptr);
  print('✓ Success!');
  
  fn.dispose();
  runtime.dispose();
}
