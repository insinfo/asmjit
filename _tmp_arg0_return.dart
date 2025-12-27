import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;
import 'package:asmjit/asmjit.dart';

typedef _NativeFn = IntPtr Function(
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
    retType: TypeId.intPtr,
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

  builder.addFunc(sig, name: 'return_arg0');
  final a0 = builder.getArgReg(0);
  builder.mov(rax, a0);
  builder.ret();

  final fn = builder.build(runtime);
  final entry = fn.pointer.cast<NativeFunction<_NativeFn>>();
  final call = entry.asFunction<_DartFn>();
  final bytes = Pointer<Uint8>.fromAddress(fn.address).asTypedList(fn.size);
  File('_tmp_arg0_return.bin').writeAsBytesSync(bytes);

  final dst = ffi.calloc<Uint8>(64);
  try {
    final got = call(
      dst.address,
      0,
      10,
      10,
      40,
      0,
      0,
    );
    print('dst=0x${dst.address.toRadixString(16)}');
    print('got=0x${got.toRadixString(16)}');
  } finally {
    ffi.calloc.free(dst);
    fn.dispose();
    runtime.dispose();
  }
}
