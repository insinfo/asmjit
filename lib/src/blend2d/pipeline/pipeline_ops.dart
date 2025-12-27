/// Blend2D pipeline ops used by the JIT compiler.
import 'pipeline_types.dart';

enum PixelFormat {
  prgb32,
  xrgb32,
  a8,
}

enum PipelineOpKind {
  copy,
  fill,
  blit,
  compSrcOver,
}

class PipelineOp {
  final PipelineOpKind kind;
  final Object? dst;
  final Object? src;
  final int width;
  final int height;
  final int dstStride;
  final int srcStride;
  final int color;
  final PixelFormat dstFormat;
  final PixelFormat srcFormat;
  final int globalAlpha;
  final PipelineMask? mask;
  final int maskStride;

  const PipelineOp._(
    this.kind, {
    this.dst,
    this.src,
    this.width = 0,
    this.height = 0,
    this.dstStride = 0,
    this.srcStride = 0,
    this.color = 0,
    this.dstFormat = PixelFormat.prgb32,
    this.srcFormat = PixelFormat.prgb32,
    this.globalAlpha = 0,
    this.mask,
    this.maskStride = 0,
  });

  const PipelineOp.copy({
    Object? dst,
    Object? src,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
    PixelFormat dstFormat = PixelFormat.prgb32,
    PixelFormat srcFormat = PixelFormat.prgb32,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskStride = 0,
  }) : this._(
          PipelineOpKind.copy,
          dst: dst,
          src: src,
          width: width,
          height: height,
          dstStride: dstStride,
          srcStride: srcStride,
          dstFormat: dstFormat,
          srcFormat: srcFormat,
          globalAlpha: globalAlpha,
          mask: mask,
          maskStride: maskStride,
        );

  const PipelineOp.fill({
    Object? dst,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int color = 0,
    PixelFormat dstFormat = PixelFormat.prgb32,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskStride = 0,
  }) : this._(
          PipelineOpKind.fill,
          dst: dst,
          width: width,
          height: height,
          dstStride: dstStride,
          color: color,
          dstFormat: dstFormat,
          globalAlpha: globalAlpha,
          mask: mask,
          maskStride: maskStride,
        );

  const PipelineOp.blit({
    Object? dst,
    Object? src,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
    PixelFormat dstFormat = PixelFormat.prgb32,
    PixelFormat srcFormat = PixelFormat.prgb32,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskStride = 0,
  }) : this._(
          PipelineOpKind.blit,
          dst: dst,
          src: src,
          width: width,
          height: height,
          dstStride: dstStride,
          srcStride: srcStride,
          dstFormat: dstFormat,
          srcFormat: srcFormat,
          globalAlpha: globalAlpha,
          mask: mask,
          maskStride: maskStride,
        );

  const PipelineOp.compSrcOver({
    Object? dst,
    Object? src,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
    PixelFormat dstFormat = PixelFormat.prgb32,
    PixelFormat srcFormat = PixelFormat.prgb32,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskStride = 0,
  }) : this._(
          PipelineOpKind.compSrcOver,
          dst: dst,
          src: src,
          width: width,
          height: height,
          dstStride: dstStride,
          srcStride: srcStride,
          dstFormat: dstFormat,
          srcFormat: srcFormat,
          globalAlpha: globalAlpha,
          mask: mask,
          maskStride: maskStride,
        );

  @override
  String toString() =>
      'PipelineOp(${kind.name}, w:$width, h:$height, dstStride:$dstStride, '
      'srcStride:$srcStride, dstFmt:${dstFormat.name}, srcFmt:${srcFormat.name})';
}
