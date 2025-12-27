import 'dart:typed_data';

import '../pipeline_ops.dart';
import '../reference/pipeline_reference_bytes.dart';
import '../pipeline_types.dart';

enum PipelineBackend {
  auto,
  jitX86,
  jitA64,
  reference,
  js,
}

class PipelineProgram {
  final PipelineBackend backend;
  final List<PipelineOp> _ops;
  final PipelineReferenceBytes _reference = PipelineReferenceBytes();

  PipelineProgram._reference(this._ops) : backend = PipelineBackend.js;

  void executeBytes({
    required Uint8List dst,
    required int dstOffset,
    required Uint8List src,
    required int srcOffset,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
    int color = 0,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskOffset = 0,
    int maskStride = 0,
  }) {
    _reference.execute(
      _ops,
      dst: dst,
      dstOffset: dstOffset,
      src: src,
      srcOffset: srcOffset,
      width: width,
      height: height,
      dstStride: dstStride,
      srcStride: srcStride,
      color: color,
      globalAlpha: globalAlpha,
      mask: mask,
      maskOffset: maskOffset,
      maskStride: maskStride,
    );
  }

  void dispose() {}
}

class PipelineCompiler {
  PipelineCompiler();

  dynamic compile(
    Object? runtime,
    List<PipelineOp> ops, {
    Object? signature,
    String? cacheKey,
    Object? frameAttrHint,
  }) {
    throw UnsupportedError('JIT pipeline is not available on web');
  }

  PipelineProgram compileProgram(
    Object? runtime,
    List<PipelineOp> ops, {
    PipelineBackend backend = PipelineBackend.auto,
    String? cacheKey,
  }) {
    return PipelineProgram._reference(ops);
  }
}
