import 'package:asmjit/asmjit.dart';
import 'package:asmjit/blend2d.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'dart:ffi';
import 'dart:io';

typedef _NativePipeline = Void Function(
  IntPtr dst,
  IntPtr src,
  Int32 width,
  Int32 height,
  Int32 dstStride,
  Int32 srcStride,
  Uint32 color,
);

typedef _DartPipeline = void Function(
  int dst,
  int src,
  int width,
  int height,
  int dstStride,
  int srcStride,
  int color,
);

void main() {
  const width = 10;
  const height = 10;
  const strideBytes = width * 4;
  final env = Environment.host();
  final runtime = JitRuntime(environment: env);
  final compiler = PipelineCompiler();
  final fn = compiler.compile(runtime, const [
    PipelineOp.fill(
      width: width,
      height: height,
      dstStride: strideBytes,
      color: 0xFFFF0000,
    ),
  ]);

  print('addr=0x${fn.address.toRadixString(16)} size=${fn.size}');
  final bytes = Pointer<Uint8>.fromAddress(fn.address).asTypedList(fn.size);
  File('_tmp_dump.bin').writeAsBytesSync(bytes);

  final pixelCount = width * height;
  final dst = ffi.calloc<Uint32>(pixelCount);
  try {
    print('dst=0x${dst.address.toRadixString(16)}');
  } finally {
    ffi.calloc.free(dst);
  }

  fn.dispose();
  runtime.dispose();
}

int _blendSrcOver(int s, int d) {
  final sa = (s >> 24) & 0xFF;
  if (sa == 0) {
    return d & 0xFFFFFFFF;
  }
  if (sa == 255) {
    return s & 0xFFFFFFFF;
  }
  final inv = 255 - sa;
  var rb = d & 0x00FF00FF;
  var ag = (d >> 8) & 0x00FF00FF;
  rb = rb * inv;
  ag = ag * inv;
  rb += 0x00800080;
  ag += 0x00800080;
  var tmp = (rb >> 8) & 0x00FF00FF;
  rb = (rb + tmp) >> 8;
  tmp = (ag >> 8) & 0x00FF00FF;
  ag = (ag + tmp) >> 8;
  ag = (ag << 8) & 0xFF00FF00;
  rb &= 0x00FF00FF;
  final result = (ag | rb) + s;
  return result & 0xFFFFFFFF;
}
