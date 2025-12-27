import 'dart:ffi';
import 'package:asmjit/src/asmjit/runtime/ffi_utils/allocation.dart' as ffi;
import 'package:asmjit/asmjit.dart';

typedef _NativeFn = Int32 Function(
  IntPtr dst,
  IntPtr src,
  Int32 width,
  Int32 height,
  Int32 dstStride,
  Int32 srcStride,
  Uint32 color,
);
typedef _DartFn = int Function(
  int dst,
  int src,
  int width,
  int height,
  int dstStride,
  int srcStride,
  int color,
);

void main() {
  final runtime = JitRuntime();
  final builder = X86CodeBuilder.create();
  final sig = FuncSignature(
    callConvId: CallConvId.x64Windows,
    retType: TypeId.int32,
    args: const [
      TypeId.intPtr,
      TypeId.intPtr,
      TypeId.int32,
      TypeId.int32,
      TypeId.int32,
      TypeId.int32,
      TypeId.uint32,
    ],
  );

  builder.addFunc(sig, name: 'load_dword7');
  final dst = builder.getArgReg(0);
  builder.mov(eax, X86Mem.baseDisp(dst, 0, size: 4));
  builder.ret();

  final fn = builder.build(runtime);
  final entry = fn.pointer.cast<NativeFunction<_NativeFn>>();
  final call = entry.asFunction<_DartFn>();

  final buf = ffi.calloc<Uint32>(1);
  try {
    buf.value = 0xAABBCCDD;
    final got = call(buf.address, 0, 0, 0, 0, 0, 0);
    print('got=0x${got.toRadixString(16)}');
  } finally {
    ffi.calloc.free(buf);
    fn.dispose();
    runtime.dispose();
  }
}
