import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'pipeline_ops.dart';
import 'pipeline_reference.dart';
import 'pipeline_types.dart';

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
  final PipelineReference? _reference;
  final JitFunction? _jit;
  final _DartPipeline? _entry;

  PipelineProgram._reference(this._ops)
      : backend = PipelineBackend.reference,
        _reference = PipelineReference(),
        _jit = null,
        _entry = null;

  PipelineProgram._jit(this.backend, JitFunction jit)
      : _ops = const [],
        _reference = null,
        _jit = jit,
        _entry = jit.pointer
            .cast<NativeFunction<_NativePipeline>>()
            .asFunction<_DartPipeline>();

  void execute({
    required Pointer<Uint8> dst,
    required Pointer<Uint8> src,
    int width = 0,
    int height = 0,
    int dstStride = 0,
    int srcStride = 0,
    int color = 0,
    int globalAlpha = 0,
    PipelineMask? mask,
    int maskStride = 0,
  }) {
    final entry = _entry;
    if (entry != null) {
      if (globalAlpha != 0 || mask != null || maskStride != 0) {
        throw UnsupportedError(
          'JIT pipeline does not support global alpha/mask yet',
        );
      }
      entry(
        dst.address,
        src.address,
        width,
        height,
        dstStride,
        srcStride,
        color,
      );
      return;
    }
    _reference!.execute(
      _ops,
      dst: dst,
      src: src,
      width: width,
      height: height,
      dstStride: dstStride,
      srcStride: srcStride,
      color: color,
      globalAlpha: globalAlpha,
      mask: mask,
      maskStride: maskStride,
    );
  }

  void dispose() {
    _jit?.dispose();
  }
}

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
    if (!env.isX86Family) {
      throw UnsupportedError(
        'X86 JIT pipeline requires an x86 environment',
      );
    }
    if (_requiresReference(ops)) {
      throw UnsupportedError('X86 JIT does not support mask/alpha/formats');
    }
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

  /// Compile a pipeline with selectable backend.
  PipelineProgram compileProgram(
    JitRuntime runtime,
    List<PipelineOp> ops, {
    PipelineBackend backend = PipelineBackend.auto,
    String? cacheKey,
  }) {
    if (backend == PipelineBackend.auto && _requiresReference(ops)) {
      return PipelineProgram._reference(ops);
    }
    final resolved = _resolveBackend(backend);
    switch (resolved) {
      case PipelineBackend.jitX86:
        if (_requiresReference(ops)) {
          throw UnsupportedError('X86 JIT does not support mask/alpha/formats');
        }
        final fn = compile(
          runtime,
          ops,
          cacheKey: cacheKey,
        );
        return PipelineProgram._jit(PipelineBackend.jitX86, fn);
      case PipelineBackend.jitA64:
        if (_requiresReference(ops)) {
          throw UnsupportedError('A64 JIT does not support mask/alpha/formats');
        }
        return _compileA64(runtime, ops, cacheKey: cacheKey);
      case PipelineBackend.reference:
      case PipelineBackend.js:
        return PipelineProgram._reference(ops);
      case PipelineBackend.auto:
        return PipelineProgram._reference(ops);
    }
  }

  PipelineBackend _resolveBackend(PipelineBackend backend) {
    if (backend == PipelineBackend.js) {
      return PipelineBackend.reference;
    }
    if (backend != PipelineBackend.auto) {
      return backend;
    }
    if (env.isX86Family) {
      return PipelineBackend.jitX86;
    }
    if (env.arch == Arch.aarch64) {
      return PipelineBackend.jitA64;
    }
    return PipelineBackend.reference;
  }

  bool _requiresReference(List<PipelineOp> ops) {
    for (final op in ops) {
      if (op.dstFormat != PixelFormat.prgb32 ||
          op.srcFormat != PixelFormat.prgb32) {
        return true;
      }
      if (op.globalAlpha != 0 || op.mask != null || op.maskStride != 0) {
        return true;
      }
    }
    return false;
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
      final widthConst = op.width;
      final heightConst = op.height;
      final dstStrideConst = op.dstStride;
      final srcStrideConst = op.srcStride;
      final colorConst = op.color;

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
            widthConst: widthConst,
            heightConst: heightConst,
            dstStrideConst: dstStrideConst,
            srcStrideConst: srcStrideConst,
          );
        case PipelineOpKind.fill:
          _emitFill(
            builder,
            dstArg,
            widthArg,
            heightArg,
            dstStrideArg,
            colorArg,
            widthConst: widthConst,
            heightConst: heightConst,
            dstStrideConst: dstStrideConst,
            colorConst: colorConst,
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
            widthConst: widthConst,
            heightConst: heightConst,
            dstStrideConst: dstStrideConst,
            srcStrideConst: srcStrideConst,
          );
      }
    }
  }

  PipelineProgram _compileA64(
    JitRuntime runtime,
    List<PipelineOp> ops, {
    String? cacheKey,
  }) {
    if (env.arch != Arch.aarch64) {
      throw UnsupportedError('A64 JIT pipeline requires AArch64 environment');
    }

    final builder = A64CodeBuilder.create(env: env);
    final dstArg = builder.getArgReg(0);
    final srcArg = builder.getArgReg(1);
    final widthArg = builder.getArgReg(2);
    final heightArg = builder.getArgReg(3);
    final dstStrideArg = builder.getArgReg(4);
    final srcStrideArg = builder.getArgReg(5);
    final colorArg = builder.getArgReg(6);

    for (final op in ops) {
      switch (op.kind) {
        case PipelineOpKind.copy:
        case PipelineOpKind.blit:
          _emitCopyA64(
            builder,
            dstArg,
            srcArg,
            widthArg,
            heightArg,
            dstStrideArg,
            srcStrideArg,
          );
        case PipelineOpKind.fill:
          _emitFillA64(
            builder,
            dstArg,
            widthArg,
            heightArg,
            dstStrideArg,
            colorArg,
          );
        case PipelineOpKind.compSrcOver:
          _emitSrcOverA64(
            builder,
            dstArg,
            srcArg,
            widthArg,
            heightArg,
            dstStrideArg,
            srcStrideArg,
          );
      }
    }

    builder.ret();
    final fn = builder.build(runtime, useCache: true, cacheKey: cacheKey);
    return PipelineProgram._jit(PipelineBackend.jitA64, fn);
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
  int widthConst = 0,
  int heightConst = 0,
  int dstStrideConst = 0,
  int srcStrideConst = 0,
}
) {
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(size: 4);

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadInt(b, rowBytes, widthConst, width);
  b.shl(rowBytes, 2);
  _loadInt(b, yCount, heightConst, height);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cmp(yCount, 0);
  b.je(done);

  _loadInt(b, xCount, widthConst, width);
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
  _loadInt(b, tmp, srcStrideConst, srcStride);
  b.sub(tmp, rowBytes);
  b.add(rowSrc, tmp);
  _loadInt(b, tmp, dstStrideConst, dstStride);
  b.sub(tmp, rowBytes);
  b.add(rowDst, tmp);
  b.dec(yCount);
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
  int widthConst = 0,
  int heightConst = 0,
  int dstStrideConst = 0,
  int colorConst = 0,
}
) {
  final rowDst = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(size: 4);

  b.mov(rowDst, dst);
  _loadInt(b, rowBytes, widthConst, width);
  b.shl(rowBytes, 2);
  _loadInt(b, pixel, colorConst, color);
  _loadInt(b, yCount, heightConst, height);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cmp(yCount, 0);
  b.je(done);

  _loadInt(b, xCount, widthConst, width);
  b.label(loopX);
  b.cmp(xCount, 0);
  b.je(endRow);

  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), pixel);
  b.add(rowDst, 4);
  b.dec(xCount);
  b.jmp(loopX);

  b.label(endRow);
  _loadInt(b, tmp, dstStrideConst, dstStride);
  b.sub(tmp, rowBytes);
  b.add(rowDst, tmp);
  b.dec(yCount);
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
  int widthConst = 0,
  int heightConst = 0,
  int dstStrideConst = 0,
  int srcStrideConst = 0,
}
) {
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
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
  _loadInt(b, rowBytes, widthConst, width);
  b.shl(rowBytes, 2);
  _loadInt(b, yCount, heightConst, height);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final storeSrc = b.newLabel();
  final skipStore = b.newLabel();
  final storeDone = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cmp(yCount, 0);
  b.je(done);

  _loadInt(b, xCount, widthConst, width);
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
  _loadInt(b, tmp64, srcStrideConst, srcStride);
  b.sub(tmp64, rowBytes);
  b.add(rowSrc, tmp64);
  _loadInt(b, tmp64, dstStrideConst, dstStride);
  b.sub(tmp64, rowBytes);
  b.add(rowDst, tmp64);
  b.dec(yCount);
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

void _emitCopyA64(
  A64CodeBuilder b,
  A64Gp dst,
  A64Gp src,
  A64Gp width,
  A64Gp height,
  A64Gp dstStride,
  A64Gp srcStride,
) {
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(sizeBits: 32);

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  b.mov(rowBytes, width);
  b.add(rowBytes, rowBytes, width);
  b.add(rowBytes, rowBytes, rowBytes);
  b.mov(yCount, height);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  b.mov(xCount, width);
  b.label(loopX);
  b.cbz(xCount, endRow);

  b.ldr(pixel, rowSrc, 0);
  b.str(pixel, rowDst, 0);
  b.add(rowSrc, rowSrc, 4);
  b.add(rowDst, rowDst, 4);
  b.sub(xCount, xCount, 1);
  b.b(loopX);

  b.label(endRow);
  b.mov(tmp, srcStride);
  b.sub(tmp, tmp, rowBytes);
  b.add(rowSrc, rowSrc, tmp);
  b.mov(tmp, dstStride);
  b.sub(tmp, tmp, rowBytes);
  b.add(rowDst, rowDst, tmp);
  b.sub(yCount, yCount, 1);
  b.b(loopY);

  b.label(done);
}

void _emitFillA64(
  A64CodeBuilder b,
  A64Gp dst,
  A64Gp width,
  A64Gp height,
  A64Gp dstStride,
  A64Gp color,
) {
  final rowDst = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(sizeBits: 32);

  b.mov(rowDst, dst);
  b.mov(rowBytes, width);
  b.add(rowBytes, rowBytes, width);
  b.add(rowBytes, rowBytes, rowBytes);
  b.mov(yCount, height);
  b.mov(pixel, color);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  b.mov(xCount, width);
  b.label(loopX);
  b.cbz(xCount, endRow);

  b.str(pixel, rowDst, 0);
  b.add(rowDst, rowDst, 4);
  b.sub(xCount, xCount, 1);
  b.b(loopX);

  b.label(endRow);
  b.mov(tmp, dstStride);
  b.sub(tmp, tmp, rowBytes);
  b.add(rowDst, rowDst, tmp);
  b.sub(yCount, yCount, 1);
  b.b(loopY);

  b.label(done);
}

void _emitSrcOverA64(
  A64CodeBuilder b,
  A64Gp dst,
  A64Gp src,
  A64Gp width,
  A64Gp height,
  A64Gp dstStride,
  A64Gp srcStride,
) {
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg(sizeBits: 32);
  final yCount = b.newGpReg(sizeBits: 32);
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg(sizeBits: 32);
  final tmp2 = b.newGpReg(sizeBits: 32);
  final s = b.newGpReg(sizeBits: 32);
  final d = b.newGpReg(sizeBits: 32);
  final sa = b.newGpReg(sizeBits: 32);
  final inv = b.newGpReg(sizeBits: 32);
  final rb = b.newGpReg(sizeBits: 32);
  final ag = b.newGpReg(sizeBits: 32);
  final maskRB = b.newGpReg(sizeBits: 32);
  final maskAG = b.newGpReg(sizeBits: 32);
  final round = b.newGpReg(sizeBits: 32);
  final const255 = b.newGpReg(sizeBits: 32);

  b.movImm32(maskRB, 0x00FF00FF);
  b.movImm32(maskAG, 0xFF00FF00);
  b.movImm32(round, 0x00800080);
  b.movImm32(const255, 255);

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  b.mov(rowBytes, width);
  b.add(rowBytes, rowBytes, width);
  b.add(rowBytes, rowBytes, rowBytes);
  b.mov(yCount, height.w);

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final storeSrc = b.newLabel();
  final skipStore = b.newLabel();
  final storeDone = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  b.mov(xCount, width.w);
  b.label(loopX);
  b.cbz(xCount, endRow);

  b.ldr(s, rowSrc, 0);
  b.ldr(d, rowDst, 0);
  b.lsr(sa, s, 24);
  b.cbz(sa, skipStore);
  b.eor(tmp, sa, const255);
  b.cbz(tmp, storeSrc);

  b.sub(inv, const255, sa);

  b.and(rb, d, maskRB);
  b.lsr(ag, d, 8);
  b.and(ag, ag, maskRB);

  b.mul(rb, rb, inv);
  b.mul(ag, ag, inv);
  b.add(rb, rb, round);
  b.add(ag, ag, round);

  b.lsr(tmp, rb, 8);
  b.and(tmp, tmp, maskRB);
  b.add(rb, rb, tmp);
  b.lsr(rb, rb, 8);

  b.lsr(tmp, ag, 8);
  b.and(tmp, tmp, maskRB);
  b.add(ag, ag, tmp);
  b.lsr(ag, ag, 8);
  b.lsl(ag, ag, 8);
  b.and(ag, ag, maskAG);
  b.and(rb, rb, maskRB);
  b.orr(ag, ag, rb);
  b.add(ag, ag, s);
  b.str(ag, rowDst, 0);
  b.b(storeDone);

  b.label(storeSrc);
  b.str(s, rowDst, 0);
  b.b(storeDone);

  b.label(skipStore);
  b.label(storeDone);

  b.add(rowSrc, rowSrc, 4);
  b.add(rowDst, rowDst, 4);
  b.sub(xCount, xCount, 1);
  b.b(loopX);

  b.label(endRow);
  b.mov(tmp2, srcStride.w);
  b.sub(tmp2, tmp2, rowBytes.w);
  b.add(rowSrc, rowSrc, tmp2.x);
  b.mov(tmp2, dstStride.w);
  b.sub(tmp2, tmp2, rowBytes.w);
  b.add(rowDst, rowDst, tmp2.x);
  b.sub(yCount, yCount, 1);
  b.b(loopY);

  b.label(done);
}
