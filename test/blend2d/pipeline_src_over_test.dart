import 'dart:ffi';

import 'package:ffi/ffi.dart' as ffi;
import 'package:test/test.dart';

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/blend2d.dart';

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
  test('PipelineCompiler src-over blends premultiplied pixels', () {
    const width = 3;
    const height = 2;
    const strideBytes = width * 4;
    const pixelCount = width * height;

    final src = ffi.calloc<Uint32>(pixelCount);
    final dst = ffi.calloc<Uint32>(pixelCount);
    final srcList = src.asTypedList(pixelCount);
    final dstList = dst.asTypedList(pixelCount);

    try {
      srcList.setAll(0, const [
        0x00000000,
        0xFF112233,
        0x80402010,
        0x40101010,
        0x20080808,
        0xFF00FF00,
      ]);
      dstList.setAll(0, const [
        0xFF000000,
        0x80112233,
        0xFFFFFFFF,
        0x10203040,
        0xA0B0C0D0,
        0x00000000,
      ]);

      final expected = List<int>.from(dstList);
      for (var i = 0; i < pixelCount; i++) {
        expected[i] = _blendSrcOver(srcList[i], expected[i]);
      }

      final runtime = JitRuntime();
      final compiler = PipelineCompiler();
      final fn = compiler.compile(
        runtime,
        const [
          PipelineOp.compSrcOver(
            width: width,
            height: height,
            dstStride: strideBytes,
            srcStride: strideBytes,
          ),
        ],
      );

      try {
        final entry = fn.pointer.cast<NativeFunction<_NativePipeline>>();
        final func = entry.asFunction<_DartPipeline>();
        func(
          dst.address,
          src.address,
          0,
          0,
          0,
          0,
          0,
        );
      } finally {
        fn.dispose();
        runtime.dispose();
      }

      expect(dstList, expected);
    } finally {
      ffi.calloc.free(src);
      ffi.calloc.free(dst);
    }
  });
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
