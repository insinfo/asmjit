import 'dart:ffi';
import 'package:ffi/ffi.dart' as ffi;
import 'package:asmjit/asmjit.dart';

typedef _NativeFn = Void Function(IntPtr a0, IntPtr out);
typedef _DartFn = void Function(int a0, int out);

void main() {
  final runtime = JitRuntime();
  final builder = X86CodeBuilder.create();
  final sig = FuncSignature(
    callConvId: CallConvId.x64Windows,
    retType: TypeId.void_,
    args: const [TypeId.intPtr, TypeId.intPtr],
  );

  builder.addFunc(sig, name: 'store_arg0');
  final a0 = builder.getArgReg(0);
  final out = builder.getArgReg(1);

  // store *out = a0
  builder.mov(X86Mem.baseDisp(out, 0, size: 8), a0);
  builder.endFunc();

  final fn = builder.build(runtime);
  final entry = fn.pointer.cast<NativeFunction<_NativeFn>>();
  final call = entry.asFunction<_DartFn>();

  final outPtr = ffi.calloc<Int64>();
  try {
    final value = 0x1122334455667788;
    call(value, outPtr.address);
    print('out=0x${outPtr.value.toRadixString(16)}');
  } finally {
    ffi.calloc.free(outPtr);
    fn.dispose();
    runtime.dispose();
  }
}
