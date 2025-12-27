import 'dart:ffi';
import 'package:asmjit/src/asmjit/runtime/ffi_utils/allocation.dart' as ffi;
import 'package:asmjit/asmjit.dart';

typedef _NativeFn = Int32 Function(IntPtr dst);
typedef _DartFn = int Function(int dst);

void main() {
  final runtime = JitRuntime();
  final builder = X86CodeBuilder.create();
  final sig = FuncSignature(
    callConvId: CallConvId.x64Windows,
    retType: TypeId.int32,
    args: const [TypeId.intPtr],
  );

  builder.addFunc(sig, name: 'load_dword');
  final dst = builder.getArgReg(0);
  builder.mov(eax, X86Mem.baseDisp(dst, 0, size: 4));
  builder.ret();

  final fn = builder.build(runtime);
  final entry = fn.pointer.cast<NativeFunction<_NativeFn>>();
  final call = entry.asFunction<_DartFn>();

  final buf = ffi.calloc<Uint32>(1);
  try {
    buf.value = 0xAABBCCDD;
    final got = call(buf.address);
    print('got=0x${got.toRadixString(16)}');
  } finally {
    ffi.calloc.free(buf);
    fn.dispose();
    runtime.dispose();
  }
}
