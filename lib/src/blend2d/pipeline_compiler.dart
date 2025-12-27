import 'package:asmjit/asmjit.dart';
import 'pipeline_ops.dart';

/// Blend2D pipeline compiler.
///
/// Builds a cached JIT stub from a list of pipeline ops.
class PipelineCompiler {
  final Environment env;

  PipelineCompiler({Environment? env}) : env = env ?? Environment.host();

  /// Compile a pipeline into executable code and cache it in [runtime].
  JitFunction compile(
    JitRuntime runtime,
    List<PipelineOp> ops, {
    FuncSignature? signature,
    String? cacheKey,
    FuncFrameAttr? frameAttrHint,
  }) {
    final builder = X86CodeBuilder.create(env: env);
    final sig = signature ?? _defaultSignature();

    builder.addFunc(sig, name: 'blend2d_pipeline');
    _emitOps(builder, ops);
    builder.endFunc();

    return builder.build(
      runtime,
      frameAttrHint: frameAttrHint,
      useCache: true,
      cacheKey: cacheKey ?? _defaultCacheKey(sig, ops),
    );
  }

  FuncSignature _defaultSignature() {
    return FuncSignature(
      retType: TypeId.void_,
      args: const [
        TypeId.intPtr, // dst
        TypeId.intPtr, // src
        TypeId.int32, // width
        TypeId.int32, // height
        TypeId.int32, // dstStride
        TypeId.int32, // srcStride
        TypeId.uint32, // color
      ],
    );
  }

  String _defaultCacheKey(FuncSignature sig, List<PipelineOp> ops) {
    final kinds = ops.map((op) => op.kind.name).join(',');
    return 'blend2d:${sig.argCount}:$kinds';
  }

  void _emitOps(X86CodeBuilder builder, List<PipelineOp> ops) {
    final dstArg = builder.getArgReg(0);
    final srcArg = builder.getArgReg(1);
    final widthArg = builder.getArgReg(2);
    final heightArg = builder.getArgReg(3);
    final dstStrideArg = builder.getArgReg(4);
    final srcStrideArg = builder.getArgReg(5);
    final colorArg = builder.getArgReg(6);

    for (final op in ops) {
      final width = op.width;
      final height = op.height;
      final dstStride = op.dstStride;
      final srcStride = op.srcStride;
      final color = op.color;

      switch (op.kind) {
        case PipelineOpKind.copy:
        case PipelineOpKind.blit:
          _emitCopy(
            builder,
            dstArg,
            srcArg,
            widthArg,
            heightArg,
            dstStrideArg,
            srcStrideArg,
            width: width,
            height: height,
            dstStride: dstStride,
            srcStride: srcStride,
          );
        case PipelineOpKind.fill:
          _emitFill(
            builder,
            dstArg,
            widthArg,
            heightArg,
            dstStrideArg,
            colorArg,
            width: width,
            height: height,
            dstStride: dstStride,
            color: color,
          );
        case PipelineOpKind.compSrcOver:
          _emitSrcOver(
            builder,
            dstArg,
            srcArg,
            widthArg,
            heightArg,
            dstStrideArg,
            srcStrideArg,
            width: width,
            height: height,
            dstStride: dstStride,
            srcStride: srcStride,
          );
      }
    }
  }
}

void _emitCopy(
  X86CodeBuilder b,
  VirtReg dst,
  VirtReg src,
  VirtReg width,
  VirtReg height,
  VirtReg dstStride,
  VirtReg srcStride, {
  int width = 0,
  int height = 0,
  int dstStride = 0,
  int srcStride = 0,
}
) {
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(size: 4);

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadInt(b, rowBytes, width, width);
  b.shl(rowBytes, 2);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  _cmpInt(b, height, height);
  b.je(done);

  _loadInt(b, xCount, width, width);
  b.label(loopX);
  b.cmp(xCount, 0);
  b.je(endRow);

  b.mov(pixel, X86Mem.baseDisp(rowSrc, 0, size: 4));
  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), pixel);
  b.add(rowSrc, 4);
  b.add(rowDst, 4);
  b.dec(xCount);
  b.jmp(loopX);

  b.label(endRow);
  b.mov(tmp, srcStride);
  b.sub(tmp, rowBytes);
  b.add(rowSrc, tmp);
  b.mov(tmp, dstStride);
  b.sub(tmp, rowBytes);
  b.add(rowDst, tmp);
  b.dec(height);
  b.jmp(loopY);

  b.label(done);
}

void _emitFill(
  X86CodeBuilder b,
  VirtReg dst,
  VirtReg width,
  VirtReg height,
  VirtReg dstStride,
  VirtReg color, {
  int width = 0,
  int height = 0,
  int dstStride = 0,
  int color = 0,
}
) {
  final rowDst = b.newGpReg();
  final xCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(size: 4);

  b.mov(rowDst, dst);
  _loadInt(b, rowBytes, width, width);
  b.shl(rowBytes, 2);
  _loadInt(b, pixel, color, color);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  _cmpInt(b, height, height);
  b.je(done);

  _loadInt(b, xCount, width, width);
  b.label(loopX);
  b.cmp(xCount, 0);
  b.je(endRow);

  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), pixel);
  b.add(rowDst, 4);
  b.dec(xCount);
  b.jmp(loopX);

  b.label(endRow);
  b.mov(tmp, dstStride);
  b.sub(tmp, rowBytes);
  b.add(rowDst, tmp);
  b.dec(height);
  b.jmp(loopY);

  b.label(done);
}

void _emitSrcOver(
  X86CodeBuilder b,
  VirtReg dst,
  VirtReg src,
  VirtReg width,
  VirtReg height,
  VirtReg dstStride,
  VirtReg srcStride, {
  int width = 0,
  int height = 0,
  int dstStride = 0,
  int srcStride = 0,
}
) {
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg(size: 4);
  final tmp64 = b.newGpReg();
  final s = b.newGpReg(size: 4);
  final d = b.newGpReg(size: 4);
  final sa = b.newGpReg(size: 4);
  final inv = b.newGpReg(size: 4);
  final rb = b.newGpReg(size: 4);
  final ag = b.newGpReg(size: 4);

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadInt(b, rowBytes, width, width);
  b.shl(rowBytes, 2);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final storeSrc = b.newLabel();
  final skipStore = b.newLabel();
  final storeDone = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  _cmpInt(b, height, height);
  b.je(done);

  _loadInt(b, xCount, width, width);
  b.label(loopX);
  b.cmp(xCount, 0);
  b.je(endRow);

  b.mov(s, X86Mem.baseDisp(rowSrc, 0, size: 4));
  b.mov(d, X86Mem.baseDisp(rowDst, 0, size: 4));
  b.mov(sa, s);
  b.shr(sa, 24);
  b.cmp(sa, 0);
  b.je(skipStore);
  b.cmp(sa, 255);
  b.je(storeSrc);

  b.mov(inv, 255);
  b.sub(inv, sa);

  b.mov(rb, d);
  b.and(rb, 0x00FF00FF);
  b.mov(ag, d);
  b.shr(ag, 8);
  b.and(ag, 0x00FF00FF);
  b.imul(rb, inv);
  b.imul(ag, inv);
  b.add(rb, 0x00800080);
  b.add(ag, 0x00800080);
  b.mov(tmp, rb);
  b.shr(tmp, 8);
  b.and(tmp, 0x00FF00FF);
  b.add(rb, tmp);
  b.shr(rb, 8);
  b.mov(tmp, ag);
  b.shr(tmp, 8);
  b.and(tmp, 0x00FF00FF);
  b.add(ag, tmp);
  b.shr(ag, 8);
  b.shl(ag, 8);
  b.and(rb, 0x00FF00FF);
  b.or(ag, rb);
  b.add(ag, s);
  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), ag);
  b.jmp(storeDone);

  b.label(storeSrc);
  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), s);
  b.jmp(storeDone);

  b.label(skipStore);
  b.label(storeDone);

  b.add(rowSrc, 4);
  b.add(rowDst, 4);
  b.dec(xCount);
  b.jmp(loopX);

  b.label(endRow);
  b.mov(tmp64, srcStride);
  b.sub(tmp64, rowBytes);
  b.add(rowSrc, tmp64);
  b.mov(tmp64, dstStride);
  b.sub(tmp64, rowBytes);
  b.add(rowDst, tmp64);
  b.dec(height);
  b.jmp(loopY);

  b.label(done);
}

void _loadInt(X86CodeBuilder b, VirtReg dst, int constant, Object fallback) {
  if (constant != 0) {
    b.mov(dst, constant);
  } else {
    b.mov(dst, fallback);
  }
}

void _cmpInt(X86CodeBuilder b, VirtReg reg, int constant) {
  if (constant != 0) {
    b.cmp(reg, constant);
  } else {
    b.cmp(reg, 0);
  }
}
