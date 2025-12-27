import 'dart:ffi';

import '../pipeline_ops.dart';
import '../pipeline_types.dart';

/// Reference (pure Dart) with ffi Pointer<Uint8> pipeline implementation.
/// uso de aritmetica de ponteiros para performace e gerenciamento de memoria manual para performace
class PipelineReference {
  void execute(
    List<PipelineOp> ops, {
    required Pointer<Uint8> dst,
    required Pointer<Uint8> src,
    required int width,
    required int height,
    required int dstStride,
    required int srcStride,
    required int color,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskStride = 0,
  }) {
    for (final op in ops) {
      final w = op.width != 0 ? op.width : width;
      final h = op.height != 0 ? op.height : height;
      final dstStep = op.dstStride != 0 ? op.dstStride : dstStride;
      final srcStep = op.srcStride != 0 ? op.srcStride : srcStride;
      final fillColor = op.color != 0 ? op.color : color;
      final dstFormat = op.dstFormat;
      final srcFormat = op.srcFormat;
      final ga = op.globalAlpha != 0 ? op.globalAlpha : globalAlpha;
      final maskPtr = op.mask ?? mask;
      final maskStep = op.maskStride != 0 ? op.maskStride : maskStride;

      switch (op.kind) {
        case PipelineOpKind.copy:
        case PipelineOpKind.blit:
          if (dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8) {
            _copyA8(
              dst: dst,
              src: src,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
            );
          } else {
            _copy32(
              dst: dst,
              src: src,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
            );
          }
        case PipelineOpKind.fill:
          if (dstFormat == PixelFormat.a8) {
            _fillA8(
              dst: dst,
              width: w,
              height: h,
              dstStride: dstStep,
              alpha: fillColor & 0xFF,
            );
          } else {
            final color32 = dstFormat == PixelFormat.xrgb32
                ? 0xFF000000 | (fillColor & 0x00FFFFFF)
                : fillColor;
            _fill32(
              dst: dst,
              width: w,
              height: h,
              dstStride: dstStep,
              color: color32,
            );
          }
        case PipelineOpKind.compSrcOver:
          if (dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8) {
            _srcOverA8(
              dst: dst,
              src: src,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
              globalAlpha: ga,
              mask: maskPtr,
              maskStride: maskStep,
            );
          } else {
            _srcOver32(
              dst: dst,
              src: src,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
              dstFormat: dstFormat,
              srcFormat: srcFormat,
              globalAlpha: ga,
              mask: maskPtr,
              maskStride: maskStep,
            );
          }
      }
    }
  }
}

void _copy32({
  required Pointer<Uint8> dst,
  required Pointer<Uint8> src,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
}) {
  var dstRow = dst.address;
  var srcRow = src.address;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    for (var x = 0; x < width; x++) {
      final value = Pointer<Uint32>.fromAddress(srcPixel).value;
      Pointer<Uint32>.fromAddress(dstPixel).value = value;
      srcPixel += 4;
      dstPixel += 4;
    }
    dstRow += dstStride;
    srcRow += srcStride;
  }
}

void _copyA8({
  required Pointer<Uint8> dst,
  required Pointer<Uint8> src,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
}) {
  var dstRow = dst.address;
  var srcRow = src.address;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    for (var x = 0; x < width; x++) {
      final value = Pointer<Uint8>.fromAddress(srcPixel).value;
      Pointer<Uint8>.fromAddress(dstPixel).value = value;
      srcPixel += 1;
      dstPixel += 1;
    }
    dstRow += dstStride;
    srcRow += srcStride;
  }
}

void _fill32({
  required Pointer<Uint8> dst,
  required int width,
  required int height,
  required int dstStride,
  required int color,
}) {
  var dstRow = dst.address;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    for (var x = 0; x < width; x++) {
      Pointer<Uint32>.fromAddress(dstPixel).value = color;
      dstPixel += 4;
    }
    dstRow += dstStride;
  }
}

void _fillA8({
  required Pointer<Uint8> dst,
  required int width,
  required int height,
  required int dstStride,
  required int alpha,
}) {
  var dstRow = dst.address;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    for (var x = 0; x < width; x++) {
      Pointer<Uint8>.fromAddress(dstPixel).value = alpha;
      dstPixel += 1;
    }
    dstRow += dstStride;
  }
}

void _srcOver32({
  required Pointer<Uint8> dst,
  required Pointer<Uint8> src,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlpha,
  required PipelineMask? mask,
  required int maskStride,
}) {
  var dstRow = dst.address;
  var srcRow = src.address;
  var maskRow = (mask as Pointer<Uint8>?)?.address ?? 0;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    var maskPixel = maskRow;
    for (var x = 0; x < width; x++) {
      var s = Pointer<Uint32>.fromAddress(srcPixel).value;
      var d = Pointer<Uint32>.fromAddress(dstPixel).value;
      if (srcFormat == PixelFormat.xrgb32) {
        s = 0xFF000000 | (s & 0x00FFFFFF);
      }
      if (dstFormat == PixelFormat.xrgb32) {
        d = 0xFF000000 | (d & 0x00FFFFFF);
      }

      var m = globalAlpha != 0 ? globalAlpha : 255;
      if (maskPixel != 0) {
        final maskValue = Pointer<Uint8>.fromAddress(maskPixel).value;
        m = _mulDiv255(maskValue * m);
        maskPixel += 1;
      }

      if (m != 255) {
        s = _applyMaskPRGB32(s, m);
      }

      var out = _blendSrcOver(s, d);
      if (dstFormat == PixelFormat.xrgb32) {
        out = 0xFF000000 | (out & 0x00FFFFFF);
      }
      Pointer<Uint32>.fromAddress(dstPixel).value = out;
      srcPixel += 4;
      dstPixel += 4;
    }
    dstRow += dstStride;
    srcRow += srcStride;
    if (maskRow != 0) {
      maskRow += maskStride;
    }
  }
}

void _srcOverA8({
  required Pointer<Uint8> dst,
  required Pointer<Uint8> src,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
  required int globalAlpha,
  required PipelineMask? mask,
  required int maskStride,
}) {
  var dstRow = dst.address;
  var srcRow = src.address;
  var maskRow = (mask as Pointer<Uint8>?)?.address ?? 0;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    var maskPixel = maskRow;
    for (var x = 0; x < width; x++) {
      final s = Pointer<Uint8>.fromAddress(srcPixel).value;
      final d = Pointer<Uint8>.fromAddress(dstPixel).value;
      var m = globalAlpha != 0 ? globalAlpha : 255;
      if (maskPixel != 0) {
        final maskValue = Pointer<Uint8>.fromAddress(maskPixel).value;
        m = _mulDiv255(maskValue * m);
        maskPixel += 1;
      }
      final sMasked = m == 255 ? s : _mulDiv255(s * m);
      final out = _srcOverA8Pixel(sMasked, d);
      Pointer<Uint8>.fromAddress(dstPixel).value = out;
      srcPixel += 1;
      dstPixel += 1;
    }
    dstRow += dstStride;
    srcRow += srcStride;
    if (maskRow != 0) {
      maskRow += maskStride;
    }
  }
}

int _srcOverA8Pixel(int s, int d) {
  if (s == 0) {
    return d & 0xFF;
  }
  if (s == 255) {
    return 255;
  }
  final inv = 255 - s;
  final out = s + _mulDiv255(d * inv);
  return out & 0xFF;
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

int _applyMaskPRGB32(int s, int m) {
  var rb = s & 0x00FF00FF;
  var ag = (s >> 8) & 0x00FF00FF;
  rb = rb * m;
  ag = ag * m;
  rb += 0x00800080;
  ag += 0x00800080;
  var tmp = (rb >> 8) & 0x00FF00FF;
  rb = (rb + tmp) >> 8;
  tmp = (ag >> 8) & 0x00FF00FF;
  ag = (ag + tmp) >> 8;
  ag = (ag << 8) & 0xFF00FF00;
  rb &= 0x00FF00FF;
  return (ag | rb) & 0xFFFFFFFF;
}

int _mulDiv255(int x) {
  final t = x + 128;
  return (t + (t >> 8)) >> 8;
}
