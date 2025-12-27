import 'dart:typed_data';

import 'pipeline_ops.dart';
import 'pipeline_types.dart';

/// Reference pipeline implementation for JS/wasm (no dart:ffi).
class PipelineReferenceBytes {
  void execute(
    List<PipelineOp> ops, {
    required Uint8List dst,
    required int dstOffset,
    required Uint8List src,
    required int srcOffset,
    required int width,
    required int height,
    required int dstStride,
    required int srcStride,
    required int color,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskOffset = 0,
    int maskStride = 0,
  }) {
    final dstData = ByteData.sublistView(dst);
    final srcData = ByteData.sublistView(src);
    final maskList = mask;

    for (final op in ops) {
      final w = op.width != 0 ? op.width : width;
      final h = op.height != 0 ? op.height : height;
      final dstStep = op.dstStride != 0 ? op.dstStride : dstStride;
      final srcStep = op.srcStride != 0 ? op.srcStride : srcStride;
      final fillColor = op.color != 0 ? op.color : color;
      final dstFormat = op.dstFormat;
      final srcFormat = op.srcFormat;
      final ga = op.globalAlpha != 0 ? op.globalAlpha : globalAlpha;
      final maskData = op.mask ?? maskList;
      final maskBase = op.mask != null ? 0 : maskOffset;
      final maskStep = op.maskStride != 0 ? op.maskStride : maskStride;

      switch (op.kind) {
        case PipelineOpKind.copy:
        case PipelineOpKind.blit:
          if (dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8) {
            _copyA8Bytes(
              dst: dst,
              src: src,
              dstOffset: dstOffset,
              srcOffset: srcOffset,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
            );
          } else {
            _copy32Bytes(
              dst: dstData,
              src: srcData,
              dstOffset: dstOffset,
              srcOffset: srcOffset,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
            );
          }
        case PipelineOpKind.fill:
          if (dstFormat == PixelFormat.a8) {
            _fillA8Bytes(
              dst: dst,
              dstOffset: dstOffset,
              width: w,
              height: h,
              dstStride: dstStep,
              alpha: fillColor & 0xFF,
            );
          } else {
            final color32 = dstFormat == PixelFormat.xrgb32
                ? 0xFF000000 | (fillColor & 0x00FFFFFF)
                : fillColor;
            _fill32Bytes(
              dst: dstData,
              dstOffset: dstOffset,
              width: w,
              height: h,
              dstStride: dstStep,
              color: color32,
            );
          }
        case PipelineOpKind.compSrcOver:
          if (dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8) {
            _srcOverA8Bytes(
              dst: dst,
              src: src,
              dstOffset: dstOffset,
              srcOffset: srcOffset,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
              globalAlpha: ga,
              mask: maskData,
              maskOffset: maskBase,
              maskStride: maskStep,
            );
          } else {
            _srcOver32Bytes(
              dst: dstData,
              src: srcData,
              dstOffset: dstOffset,
              srcOffset: srcOffset,
              width: w,
              height: h,
              dstStride: dstStep,
              srcStride: srcStep,
              dstFormat: dstFormat,
              srcFormat: srcFormat,
              globalAlpha: ga,
              mask: maskData,
              maskOffset: maskBase,
              maskStride: maskStep,
            );
          }
      }
    }
  }
}

void _copy32Bytes({
  required ByteData dst,
  required ByteData src,
  required int dstOffset,
  required int srcOffset,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
}) {
  final rowBytes = width * 4;
  if (dstStride == rowBytes && srcStride == rowBytes) {
    final total = width * height;
    var dstPixel = dstOffset;
    var srcPixel = srcOffset;
    var i = 0;
    final limit = total & ~3;
    while (i < limit) {
      final v0 = src.getUint32(srcPixel, Endian.little);
      final v1 = src.getUint32(srcPixel + 4, Endian.little);
      final v2 = src.getUint32(srcPixel + 8, Endian.little);
      final v3 = src.getUint32(srcPixel + 12, Endian.little);
      dst.setUint32(dstPixel, v0, Endian.little);
      dst.setUint32(dstPixel + 4, v1, Endian.little);
      dst.setUint32(dstPixel + 8, v2, Endian.little);
      dst.setUint32(dstPixel + 12, v3, Endian.little);
      srcPixel += 16;
      dstPixel += 16;
      i += 4;
    }
    while (i < total) {
      final value = src.getUint32(srcPixel, Endian.little);
      dst.setUint32(dstPixel, value, Endian.little);
      srcPixel += 4;
      dstPixel += 4;
      i++;
    }
    return;
  }
  var dstRow = dstOffset;
  var srcRow = srcOffset;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    var x = 0;
    final limit = width & ~3;
    while (x < limit) {
      final v0 = src.getUint32(srcPixel, Endian.little);
      final v1 = src.getUint32(srcPixel + 4, Endian.little);
      final v2 = src.getUint32(srcPixel + 8, Endian.little);
      final v3 = src.getUint32(srcPixel + 12, Endian.little);
      dst.setUint32(dstPixel, v0, Endian.little);
      dst.setUint32(dstPixel + 4, v1, Endian.little);
      dst.setUint32(dstPixel + 8, v2, Endian.little);
      dst.setUint32(dstPixel + 12, v3, Endian.little);
      srcPixel += 16;
      dstPixel += 16;
      x += 4;
    }
    while (x < width) {
      final value = src.getUint32(srcPixel, Endian.little);
      dst.setUint32(dstPixel, value, Endian.little);
      srcPixel += 4;
      dstPixel += 4;
      x++;
    }
    dstRow += dstStride;
    srcRow += srcStride;
  }
}

void _copyA8Bytes({
  required Uint8List dst,
  required Uint8List src,
  required int dstOffset,
  required int srcOffset,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
}) {
  final rowBytes = width;
  if (dstStride == rowBytes && srcStride == rowBytes) {
    final total = width * height;
    var dstPixel = dstOffset;
    var srcPixel = srcOffset;
    var i = 0;
    final limit = total & ~3;
    while (i < limit) {
      dst[dstPixel] = src[srcPixel];
      dst[dstPixel + 1] = src[srcPixel + 1];
      dst[dstPixel + 2] = src[srcPixel + 2];
      dst[dstPixel + 3] = src[srcPixel + 3];
      srcPixel += 4;
      dstPixel += 4;
      i += 4;
    }
    while (i < total) {
      dst[dstPixel] = src[srcPixel];
      srcPixel += 1;
      dstPixel += 1;
      i++;
    }
    return;
  }
  var dstRow = dstOffset;
  var srcRow = srcOffset;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    var x = 0;
    final limit = width & ~3;
    while (x < limit) {
      dst[dstPixel] = src[srcPixel];
      dst[dstPixel + 1] = src[srcPixel + 1];
      dst[dstPixel + 2] = src[srcPixel + 2];
      dst[dstPixel + 3] = src[srcPixel + 3];
      srcPixel += 4;
      dstPixel += 4;
      x += 4;
    }
    while (x < width) {
      dst[dstPixel] = src[srcPixel];
      srcPixel += 1;
      dstPixel += 1;
      x++;
    }
    dstRow += dstStride;
    srcRow += srcStride;
  }
}

void _fill32Bytes({
  required ByteData dst,
  required int dstOffset,
  required int width,
  required int height,
  required int dstStride,
  required int color,
}) {
  final rowBytes = width * 4;
  if (dstStride == rowBytes) {
    final total = width * height;
    var dstPixel = dstOffset;
    var i = 0;
    final limit = total & ~3;
    while (i < limit) {
      dst.setUint32(dstPixel, color, Endian.little);
      dst.setUint32(dstPixel + 4, color, Endian.little);
      dst.setUint32(dstPixel + 8, color, Endian.little);
      dst.setUint32(dstPixel + 12, color, Endian.little);
      dstPixel += 16;
      i += 4;
    }
    while (i < total) {
      dst.setUint32(dstPixel, color, Endian.little);
      dstPixel += 4;
      i++;
    }
    return;
  }
  var dstRow = dstOffset;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var x = 0;
    final limit = width & ~3;
    while (x < limit) {
      dst.setUint32(dstPixel, color, Endian.little);
      dst.setUint32(dstPixel + 4, color, Endian.little);
      dst.setUint32(dstPixel + 8, color, Endian.little);
      dst.setUint32(dstPixel + 12, color, Endian.little);
      dstPixel += 16;
      x += 4;
    }
    while (x < width) {
      dst.setUint32(dstPixel, color, Endian.little);
      dstPixel += 4;
      x++;
    }
    dstRow += dstStride;
  }
}

void _fillA8Bytes({
  required Uint8List dst,
  required int dstOffset,
  required int width,
  required int height,
  required int dstStride,
  required int alpha,
}) {
  final rowBytes = width;
  if (dstStride == rowBytes) {
    final total = width * height;
    var dstPixel = dstOffset;
    var i = 0;
    final limit = total & ~3;
    while (i < limit) {
      dst[dstPixel] = alpha;
      dst[dstPixel + 1] = alpha;
      dst[dstPixel + 2] = alpha;
      dst[dstPixel + 3] = alpha;
      dstPixel += 4;
      i += 4;
    }
    while (i < total) {
      dst[dstPixel] = alpha;
      dstPixel += 1;
      i++;
    }
    return;
  }
  var dstRow = dstOffset;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var x = 0;
    final limit = width & ~3;
    while (x < limit) {
      dst[dstPixel] = alpha;
      dst[dstPixel + 1] = alpha;
      dst[dstPixel + 2] = alpha;
      dst[dstPixel + 3] = alpha;
      dstPixel += 4;
      x += 4;
    }
    while (x < width) {
      dst[dstPixel] = alpha;
      dstPixel += 1;
      x++;
    }
    dstRow += dstStride;
  }
}

void _srcOver32Bytes({
  required ByteData dst,
  required ByteData src,
  required int dstOffset,
  required int srcOffset,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlpha,
  required Uint8List? mask,
  required int maskOffset,
  required int maskStride,
}) {
  final rowBytes = width * 4;
  final tight =
      dstStride == rowBytes && srcStride == rowBytes && maskStride == rowBytes;
  var dstRow = dstOffset;
  var srcRow = srcOffset;
  var maskRow = mask != null ? maskOffset : 0;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    var maskPixel = maskRow;
    var x = 0;
    final limit = width & ~3;
    while (x < limit) {
      for (var i = 0; i < 4; i++) {
        var s = src.getUint32(srcPixel, Endian.little);
        var d = dst.getUint32(dstPixel, Endian.little);
        if (srcFormat == PixelFormat.xrgb32) {
          s = 0xFF000000 | (s & 0x00FFFFFF);
        }
        if (dstFormat == PixelFormat.xrgb32) {
          d = 0xFF000000 | (d & 0x00FFFFFF);
        }

        var m = globalAlpha != 0 ? globalAlpha : 255;
        if (mask != null) {
          final maskValue = mask[maskPixel];
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
        dst.setUint32(dstPixel, out, Endian.little);
        srcPixel += 4;
        dstPixel += 4;
      }
      x += 4;
    }
    while (x < width) {
      var s = src.getUint32(srcPixel, Endian.little);
      var d = dst.getUint32(dstPixel, Endian.little);
      if (srcFormat == PixelFormat.xrgb32) {
        s = 0xFF000000 | (s & 0x00FFFFFF);
      }
      if (dstFormat == PixelFormat.xrgb32) {
        d = 0xFF000000 | (d & 0x00FFFFFF);
      }

      var m = globalAlpha != 0 ? globalAlpha : 255;
      if (mask != null) {
        final maskValue = mask[maskPixel];
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
      dst.setUint32(dstPixel, out, Endian.little);
      srcPixel += 4;
      dstPixel += 4;
      x++;
    }
    dstRow += dstStride;
    srcRow += srcStride;
    if (mask != null) {
      maskRow += maskStride;
    }
    if (tight) {
      dstRow = dstOffset + (y + 1) * rowBytes;
      srcRow = srcOffset + (y + 1) * rowBytes;
      if (mask != null) {
        maskRow = maskOffset + (y + 1) * maskStride;
      }
    }
  }
}

void _srcOverA8Bytes({
  required Uint8List dst,
  required Uint8List src,
  required int dstOffset,
  required int srcOffset,
  required int width,
  required int height,
  required int dstStride,
  required int srcStride,
  required int globalAlpha,
  required Uint8List? mask,
  required int maskOffset,
  required int maskStride,
}) {
  final rowBytes = width;
  final tight =
      dstStride == rowBytes && srcStride == rowBytes && maskStride == rowBytes;
  var dstRow = dstOffset;
  var srcRow = srcOffset;
  var maskRow = mask != null ? maskOffset : 0;
  for (var y = 0; y < height; y++) {
    var dstPixel = dstRow;
    var srcPixel = srcRow;
    var maskPixel = maskRow;
    var x = 0;
    final limit = width & ~3;
    while (x < limit) {
      for (var i = 0; i < 4; i++) {
        final s = src[srcPixel];
        final d = dst[dstPixel];
        var m = globalAlpha != 0 ? globalAlpha : 255;
        if (mask != null) {
          final maskValue = mask[maskPixel];
          m = _mulDiv255(maskValue * m);
          maskPixel += 1;
        }
        final sMasked = m == 255 ? s : _mulDiv255(s * m);
        final out = _srcOverA8Pixel(sMasked, d);
        dst[dstPixel] = out;
        srcPixel += 1;
        dstPixel += 1;
      }
      x += 4;
    }
    while (x < width) {
      final s = src[srcPixel];
      final d = dst[dstPixel];
      var m = globalAlpha != 0 ? globalAlpha : 255;
      if (mask != null) {
        final maskValue = mask[maskPixel];
        m = _mulDiv255(maskValue * m);
        maskPixel += 1;
      }
      final sMasked = m == 255 ? s : _mulDiv255(s * m);
      final out = _srcOverA8Pixel(sMasked, d);
      dst[dstPixel] = out;
      srcPixel += 1;
      dstPixel += 1;
      x++;
    }
    dstRow += dstStride;
    srcRow += srcStride;
    if (mask != null) {
      maskRow += maskStride;
    }
    if (tight) {
      dstRow = dstOffset + (y + 1) * rowBytes;
      srcRow = srcOffset + (y + 1) * rowBytes;
      if (mask != null) {
        maskRow = maskOffset + (y + 1) * maskStride;
      }
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
