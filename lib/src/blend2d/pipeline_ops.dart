/// Blend2D pipeline ops used by the JIT compiler.

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

  const PipelineOp._(
    this.kind, {
    this.dst,
    this.src,
    this.width = 0,
    this.height = 0,
    this.dstStride = 0,
    this.srcStride = 0,
    this.color = 0,
  });

  const PipelineOp.copy({
    Object? dst,
    Object? src,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
  }) : this._(
          PipelineOpKind.copy,
          dst: dst,
          src: src,
          width: width,
          height: height,
          dstStride: dstStride,
          srcStride: srcStride,
        );

  const PipelineOp.fill({
    Object? dst,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int color = 0,
  }) : this._(
          PipelineOpKind.fill,
          dst: dst,
          width: width,
          height: height,
          dstStride: dstStride,
          color: color,
        );

  const PipelineOp.blit({
    Object? dst,
    Object? src,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
  }) : this._(
          PipelineOpKind.blit,
          dst: dst,
          src: src,
          width: width,
          height: height,
          dstStride: dstStride,
          srcStride: srcStride,
        );

  const PipelineOp.compSrcOver({
    Object? dst,
    Object? src,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
  }) : this._(
          PipelineOpKind.compSrcOver,
          dst: dst,
          src: src,
          width: width,
          height: height,
          dstStride: dstStride,
          srcStride: srcStride,
        );

  @override
  String toString() =>
      'PipelineOp(${kind.name}, w:$width, h:$height, dstStride:$dstStride, srcStride:$srcStride)';
}
