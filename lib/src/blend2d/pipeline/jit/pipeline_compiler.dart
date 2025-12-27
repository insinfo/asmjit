import 'dart:ffi';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import '../pipeline_ops.dart';
import '../reference/pipeline_reference.dart';
import '../pipeline_types.dart';

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

  PipelineProgram._jit(this.backend, JitFunction jit, List<PipelineOp> ops)
      : _ops = ops,
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
          'JIT pipeline does not accept runtime global alpha/mask overrides',
        );
      }
      final baked = _ops.isNotEmpty ? _ops.first : null;
      width = width != 0 ? width : (baked?.width ?? 0);
      height = height != 0 ? height : (baked?.height ?? 0);
      dstStride = dstStride != 0 ? dstStride : (baked?.dstStride ?? 0);
      srcStride = srcStride != 0 ? srcStride : (baked?.srcStride ?? 0);
      color = color != 0 ? color : (baked?.color ?? 0);
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
        return PipelineProgram._jit(PipelineBackend.jitX86, fn, ops);
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
    return false;
  }

  FuncSignature _defaultSignature() {
    final callConv = env.callingConvention == CallingConvention.win64
        ? CallConvId.x64Windows
        : CallConvId.x64SystemV;
    return FuncSignature(
      callConvId: callConv,
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
      // If the caller passes zero for baked constants, replace with the
      // compile-time value so cached pipelines work without explicit params.
      if (op.width != 0) {
        builder.mov(widthArg, op.width);
      }
      if (op.height != 0) {
        builder.mov(heightArg, op.height);
      }
      if (op.dstStride != 0) {
        builder.mov(dstStrideArg, op.dstStride);
      }
      if (op.srcStride != 0) {
        builder.mov(srcStrideArg, op.srcStride);
      }
      if (op.color != 0) {
        builder.mov(colorArg, op.color);
      }

      final widthConst = op.width;
      final heightConst = op.height;
      final dstStrideConst = op.dstStride;
      final srcStrideConst = op.srcStride;
      final colorConst = op.color;
      final dstFormat = op.dstFormat;
      final srcFormat = op.srcFormat;
      final globalAlphaConst = op.globalAlpha;
      final maskConst = op.mask as Pointer<Uint8>?;
      final maskStrideConst = op.maskStride;

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
            dstFormat: dstFormat,
            srcFormat: srcFormat,
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
            dstFormat: dstFormat,
            globalAlphaConst: globalAlphaConst,
            maskConst: maskConst,
            maskStrideConst: maskStrideConst,
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
            dstFormat: dstFormat,
            srcFormat: srcFormat,
            globalAlphaConst: globalAlphaConst,
            maskConst: maskConst,
            maskStrideConst: maskStrideConst,
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
      if (op.width != 0) {
        builder.movImm32(widthArg, op.width);
      }
      if (op.height != 0) {
        builder.movImm32(heightArg, op.height);
      }
      if (op.dstStride != 0) {
        builder.movImm32(dstStrideArg, op.dstStride);
      }
      if (op.srcStride != 0) {
        builder.movImm32(srcStrideArg, op.srcStride);
      }
      if (op.color != 0) {
        builder.movImm32(colorArg, op.color);
      }

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
            widthConst: op.width,
            heightConst: op.height,
            dstStrideConst: op.dstStride,
            srcStrideConst: op.srcStride,
            dstFormat: op.dstFormat,
            srcFormat: op.srcFormat,
          );
        case PipelineOpKind.fill:
          _emitFillA64(
            builder,
            dstArg,
            widthArg,
            heightArg,
            dstStrideArg,
            colorArg,
            dstFormat: op.dstFormat,
            colorConst: op.color,
            globalAlphaConst: op.globalAlpha,
            maskConst: op.mask as Pointer<Uint8>?,
            maskStrideConst: op.maskStride,
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
            widthConst: op.width,
            heightConst: op.height,
            dstStrideConst: op.dstStride,
            srcStrideConst: op.srcStride,
            dstFormat: op.dstFormat,
            srcFormat: op.srcFormat,
            globalAlphaConst: op.globalAlpha,
            maskConst: op.mask as Pointer<Uint8>?,
            maskStrideConst: op.maskStride,
          );
      }
    }

    builder.ret();
    final fn = builder.build(runtime, useCache: true, cacheKey: cacheKey);
    return PipelineProgram._jit(PipelineBackend.jitA64, fn, ops);
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
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
}) {
  final isA8 = dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8;
  final bpp = isA8 ? 1 : 4;
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(size: isA8 ? 1 : 4);

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadInt(b, rowBytes, widthConst, width);
  if (!isA8) {
    b.shl(rowBytes, 2);
  }
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

  b.mov(pixel, X86Mem.baseDisp(rowSrc, 0, size: bpp));
  if (!isA8 &&
      (srcFormat == PixelFormat.xrgb32 || dstFormat == PixelFormat.xrgb32)) {
    b.or(pixel, 0xFF000000);
  }
  b.mov(X86Mem.baseDisp(rowDst, 0, size: bpp), pixel);
  b.add(rowSrc, bpp);
  b.add(rowDst, bpp);
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
  required PixelFormat dstFormat,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  if (globalAlphaConst == 0) {
    return;
  }
  final isA8 = dstFormat == PixelFormat.a8;
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

  if (isA8) {
    final rowDst = b.newGpReg();
    final xCount = b.newGpReg();
    final yCount = b.newGpReg();
    final rowBytes = b.newGpReg();
    final tmp = b.newGpReg(size: 4);
    final base = b.newGpReg(size: 4);
    final s = b.newGpReg(size: 4);
    final d = b.newGpReg(size: 4);
    final inv = b.newGpReg(size: 4);
    final m = b.newGpReg(size: 4);
    final rowMask = b.newGpReg();
    final maskStep = b.newGpReg();
    final maskBytes = b.newGpReg();

    b.mov(rowDst, dst);
    _loadInt(b, rowBytes, widthConst, width);
    _loadInt(b, base, colorConst, color);
    b.and(base, 0xFF);
    _loadInt(b, yCount, heightConst, height);
    if (hasMask) {
      b.mov(rowMask, maskConst.address);
      _loadInt(b, maskBytes, widthConst, width);
      if (maskStrideConst != 0) {
        b.mov(maskStep, maskStrideConst);
        b.sub(maskStep, maskBytes);
      } else {
        b.mov(maskStep, 0);
      }
    }

    final loopY = b.newLabel();
    final loopX = b.newLabel();
    final endRow = b.newLabel();
    final storeSrc = b.newLabel();
    final skipStore = b.newLabel();
    final skipMask = b.newLabel();
    final storeDone = b.newLabel();
    final done = b.newLabel();

    b.label(loopY);
    b.cmp(yCount, 0);
    b.je(done);

    _loadInt(b, xCount, widthConst, width);
    b.label(loopX);
    b.cmp(xCount, 0);
    b.je(endRow);

    b.mov(s, base);
    if (needsMasking) {
      if (hasMask) {
        b.movzx(m, X86Mem.baseDisp(rowMask, 0, size: 1));
        if (hasGlobalAlpha) {
          b.imul(m, globalAlphaConst);
          _mulDiv255ScalarX86(b, m, tmp);
        }
        b.add(rowMask, 1);
      } else {
        b.mov(m, globalAlphaConst);
      }
      b.cmp(m, 0);
      b.je(skipStore);
      b.cmp(m, 255);
      b.je(skipMask);
      b.imul(s, m);
      _mulDiv255ScalarX86(b, s, tmp);
    }

    b.label(skipMask);
    b.movzx(d, X86Mem.baseDisp(rowDst, 0, size: 1));
    b.cmp(s, 0);
    b.je(skipStore);
    b.cmp(s, 255);
    b.je(storeSrc);
    b.mov(inv, 255);
    b.sub(inv, s);
    b.imul(d, inv);
    _mulDiv255ScalarX86(b, d, tmp);
    b.add(s, d);

    b.label(storeSrc);
    b.mov(X86Mem.baseDisp(rowDst, 0, size: 1), s);
    b.jmp(storeDone);

    b.label(skipStore);
    b.label(storeDone);

    b.add(rowDst, 1);
    b.dec(xCount);
    b.jmp(loopX);

    b.label(endRow);
    _loadInt(b, tmp, dstStrideConst, dstStride);
    b.sub(tmp, rowBytes);
    b.add(rowDst, tmp);
    if (hasMask) {
      b.add(rowMask, maskStep);
    }
    b.dec(yCount);
    b.jmp(loopY);

    b.label(done);
    return;
  }

  final rowDst = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg(size: 4);
  final tmp64 = b.newGpReg();
  final base = b.newGpReg(size: 4);
  final s = b.newGpReg(size: 4);
  final d = b.newGpReg(size: 4);
  final sa = b.newGpReg(size: 4);
  final inv = b.newGpReg(size: 4);
  final rb = b.newGpReg(size: 4);
  final ag = b.newGpReg(size: 4);
  final m = b.newGpReg(size: 4);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg();
  final maskBytes = b.newGpReg();

  b.mov(rowDst, dst);
  _loadInt(b, rowBytes, widthConst, width);
  b.shl(rowBytes, 2);
  _loadInt(b, base, colorConst, color);
  if (dstFormat == PixelFormat.xrgb32) {
    b.or(base, 0xFF000000);
  }
  _loadInt(b, yCount, heightConst, height);
  if (hasMask) {
    b.mov(rowMask, maskConst.address);
    _loadInt(b, maskBytes, widthConst, width);
    if (maskStrideConst != 0) {
      b.mov(maskStep, maskStrideConst);
      b.sub(maskStep, maskBytes);
    } else {
      b.mov(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final storeSrc = b.newLabel();
  final skipStore = b.newLabel();
  final skipMask = b.newLabel();
  final storeDone = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cmp(yCount, 0);
  b.je(done);

  _loadInt(b, xCount, widthConst, width);
  b.label(loopX);
  b.cmp(xCount, 0);
  b.je(endRow);

  b.mov(s, base);
  if (needsMasking) {
    if (hasMask) {
      b.movzx(m, X86Mem.baseDisp(rowMask, 0, size: 1));
      if (hasGlobalAlpha) {
        b.imul(m, globalAlphaConst);
        _mulDiv255ScalarX86(b, m, tmp);
      }
      b.add(rowMask, 1);
    } else {
      b.mov(m, globalAlphaConst);
    }
    b.cmp(m, 0);
    b.je(skipStore);
    b.cmp(m, 255);
    b.je(skipMask);
    _applyMaskPRGB32X86(b, s, m, tmp, rb, ag);
  }

  b.label(skipMask);
  b.mov(d, X86Mem.baseDisp(rowDst, 0, size: 4));
  if (dstFormat == PixelFormat.xrgb32) {
    b.or(d, 0xFF000000);
  }
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
  b.and(ag, 0xFF00FF00);
  b.and(rb, 0x00FF00FF);
  b.or(ag, rb);
  b.add(ag, s);
  if (dstFormat == PixelFormat.xrgb32) {
    b.or(ag, 0xFF000000);
  }
  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), ag);
  b.jmp(storeDone);

  b.label(storeSrc);
  if (dstFormat == PixelFormat.xrgb32) {
    b.or(s, 0xFF000000);
  }
  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), s);
  b.jmp(storeDone);

  b.label(skipStore);
  b.label(storeDone);

  b.add(rowDst, 4);
  b.dec(xCount);
  b.jmp(loopX);

  b.label(endRow);
  _loadInt(b, tmp64, dstStrideConst, dstStride);
  b.sub(tmp64, rowBytes);
  b.add(rowDst, tmp64);
  if (hasMask) {
    b.add(rowMask, maskStep);
  }
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
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  if (globalAlphaConst == 0) {
    return;
  }
  final isA8 = dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8;
  if (isA8) {
    if (widthConst > 0 && widthConst <= 4) {
      _emitSrcOverA8X86FixedWidth(
        b,
        dst,
        src,
        height,
        dstStride,
        srcStride,
        widthConst: widthConst,
        heightConst: heightConst,
        dstStrideConst: dstStrideConst,
        srcStrideConst: srcStrideConst,
        globalAlphaConst: globalAlphaConst,
        maskConst: maskConst,
        maskStrideConst: maskStrideConst,
      );
      return;
    }
    _emitSrcOverA8X86(
      b,
      dst,
      src,
      width,
      height,
      dstStride,
      srcStride,
      widthConst: widthConst,
      heightConst: heightConst,
      dstStrideConst: dstStrideConst,
      srcStrideConst: srcStrideConst,
      globalAlphaConst: globalAlphaConst,
      maskConst: maskConst,
      maskStrideConst: maskStrideConst,
    );
    return;
  }
  if (widthConst > 0 && widthConst <= 4) {
    _emitSrcOver32X86FixedWidth(
      b,
      dst,
      src,
      height,
      dstStride,
      srcStride,
      widthConst: widthConst,
      heightConst: heightConst,
      dstStrideConst: dstStrideConst,
      srcStrideConst: srcStrideConst,
      dstFormat: dstFormat,
      srcFormat: srcFormat,
      globalAlphaConst: globalAlphaConst,
      maskConst: maskConst,
      maskStrideConst: maskStrideConst,
    );
    return;
  }
  _emitSrcOver32X86(
    b,
    dst,
    src,
    width,
    height,
    dstStride,
    srcStride,
    widthConst: widthConst,
    heightConst: heightConst,
    dstStrideConst: dstStrideConst,
    srcStrideConst: srcStrideConst,
    dstFormat: dstFormat,
    srcFormat: srcFormat,
    globalAlphaConst: globalAlphaConst,
    maskConst: maskConst,
    maskStrideConst: maskStrideConst,
  );
}

void _emitSrcOver32X86FixedWidth(
  X86CodeBuilder b,
  VirtReg dst,
  VirtReg src,
  VirtReg height,
  VirtReg dstStride,
  VirtReg srcStride, {
  required int widthConst,
  required int heightConst,
  required int dstStrideConst,
  required int srcStrideConst,
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
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
  final m = b.newGpReg(size: 4);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg();
  final maskBytes = b.newGpReg();

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  b.mov(rowBytes, widthConst * 4);
  _loadInt(b, yCount, heightConst, height);
  if (hasMask) {
    b.mov(rowMask, maskConst.address);
    b.mov(maskBytes, widthConst);
    if (maskStrideConst != 0) {
      b.mov(maskStep, maskStrideConst);
      b.sub(maskStep, maskBytes);
    } else {
      b.mov(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cmp(yCount, 0);
  b.je(done);

  for (var i = 0; i < widthConst; i++) {
    final storeSrc = b.newLabel();
    final skipStore = b.newLabel();
    final skipMask = b.newLabel();
    final storeDone = b.newLabel();

    b.mov(s, X86Mem.baseDisp(rowSrc, 0, size: 4));
    if (srcFormat == PixelFormat.xrgb32) {
      b.or(s, 0xFF000000);
    }
    b.mov(d, X86Mem.baseDisp(rowDst, 0, size: 4));
    if (dstFormat == PixelFormat.xrgb32) {
      b.or(d, 0xFF000000);
    }
    if (needsMasking) {
      if (hasMask) {
        b.movzx(m, X86Mem.baseDisp(rowMask, 0, size: 1));
        if (hasGlobalAlpha) {
          b.imul(m, globalAlphaConst);
          _mulDiv255ScalarX86(b, m, tmp);
        }
        b.add(rowMask, 1);
      } else {
        b.mov(m, globalAlphaConst);
      }
      b.cmp(m, 0);
      b.je(skipStore);
      b.cmp(m, 255);
      b.je(skipMask);
      _applyMaskPRGB32X86(b, s, m, tmp, rb, ag);
    }

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
    b.and(ag, 0xFF00FF00);
    b.and(rb, 0x00FF00FF);
    b.or(ag, rb);
    b.add(ag, s);
    if (dstFormat == PixelFormat.xrgb32) {
      b.or(ag, 0xFF000000);
    }
    b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), ag);
    b.jmp(storeDone);

    b.label(skipMask);

    b.label(storeSrc);
    if (dstFormat == PixelFormat.xrgb32) {
      b.or(s, 0xFF000000);
    }
    b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), s);
    b.jmp(storeDone);

    b.label(skipStore);
    b.label(storeDone);

    b.add(rowSrc, 4);
    b.add(rowDst, 4);
  }

  _loadInt(b, tmp64, srcStrideConst, srcStride);
  b.sub(tmp64, rowBytes);
  b.add(rowSrc, tmp64);
  _loadInt(b, tmp64, dstStrideConst, dstStride);
  b.sub(tmp64, rowBytes);
  b.add(rowDst, tmp64);
  if (hasMask) {
    b.add(rowMask, maskStep);
  }
  b.dec(yCount);
  b.jmp(loopY);

  b.label(done);
}

void _emitSrcOver32X86(
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
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

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
  final m = b.newGpReg(size: 4);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg();
  final maskBytes = b.newGpReg();

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadInt(b, rowBytes, widthConst, width);
  b.shl(rowBytes, 2);
  _loadInt(b, yCount, heightConst, height);
  if (hasMask) {
    b.mov(rowMask, maskConst.address);
    _loadInt(b, maskBytes, widthConst, width);
    if (maskStrideConst != 0) {
      b.mov(maskStep, maskStrideConst);
      b.sub(maskStep, maskBytes);
    } else {
      b.mov(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final storeSrc = b.newLabel();
  final skipStore = b.newLabel();
  final skipMask = b.newLabel();
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
  if (srcFormat == PixelFormat.xrgb32) {
    b.or(s, 0xFF000000);
  }
  b.mov(d, X86Mem.baseDisp(rowDst, 0, size: 4));
  if (dstFormat == PixelFormat.xrgb32) {
    b.or(d, 0xFF000000);
  }
  if (needsMasking) {
    if (hasMask) {
      b.movzx(m, X86Mem.baseDisp(rowMask, 0, size: 1));
      if (hasGlobalAlpha) {
        b.imul(m, globalAlphaConst);
        _mulDiv255ScalarX86(b, m, tmp);
      }
      b.add(rowMask, 1);
    } else {
      b.mov(m, globalAlphaConst);
    }
    b.cmp(m, 0);
    b.je(skipStore);
    b.cmp(m, 255);
    b.je(skipMask);
    _applyMaskPRGB32X86(b, s, m, tmp, rb, ag);
  }

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
  b.and(ag, 0xFF00FF00);
  b.and(rb, 0x00FF00FF);
  b.or(ag, rb);
  b.add(ag, s);
  if (dstFormat == PixelFormat.xrgb32) {
    b.or(ag, 0xFF000000);
  }
  b.mov(X86Mem.baseDisp(rowDst, 0, size: 4), ag);
  b.jmp(storeDone);

  b.label(skipMask);

  b.label(storeSrc);
  if (dstFormat == PixelFormat.xrgb32) {
    b.or(s, 0xFF000000);
  }
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
  if (hasMask) {
    b.add(rowMask, maskStep);
  }
  b.dec(yCount);
  b.jmp(loopY);

  b.label(done);
}

void _emitSrcOverA8X86FixedWidth(
  X86CodeBuilder b,
  VirtReg dst,
  VirtReg src,
  VirtReg height,
  VirtReg dstStride,
  VirtReg srcStride, {
  required int widthConst,
  required int heightConst,
  required int dstStrideConst,
  required int srcStrideConst,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg(size: 4);
  final tmp64 = b.newGpReg();
  final s8 = b.newGpReg(size: 1);
  final d8 = b.newGpReg(size: 1);
  final s = b.newGpReg(size: 4);
  final d = b.newGpReg(size: 4);
  final inv = b.newGpReg(size: 4);
  final out8 = b.newGpReg(size: 1);
  final m = b.newGpReg(size: 4);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg();
  final maskBytes = b.newGpReg();

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  b.mov(rowBytes, widthConst);
  _loadInt(b, yCount, heightConst, height);
  if (hasMask) {
    b.mov(rowMask, maskConst.address);
    b.mov(maskBytes, widthConst);
    if (maskStrideConst != 0) {
      b.mov(maskStep, maskStrideConst);
      b.sub(maskStep, maskBytes);
    } else {
      b.mov(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cmp(yCount, 0);
  b.je(done);

  for (var i = 0; i < widthConst; i++) {
    final skipStore = b.newLabel();
    final storeDone = b.newLabel();

    b.mov(s8, X86Mem.baseDisp(rowSrc, 0, size: 1));
    b.mov(d8, X86Mem.baseDisp(rowDst, 0, size: 1));
    b.movzx(s, s8);
    b.movzx(d, d8);

    if (needsMasking) {
      if (hasMask) {
        b.movzx(m, X86Mem.baseDisp(rowMask, 0, size: 1));
        if (hasGlobalAlpha) {
          b.imul(m, globalAlphaConst);
          _mulDiv255ScalarX86(b, m, tmp);
        }
        b.add(rowMask, 1);
      } else {
        b.mov(m, globalAlphaConst);
      }
      b.cmp(m, 0);
      b.je(skipStore);
      b.cmp(m, 255);
      b.je(storeDone);
      b.imul(s, m);
      _mulDiv255ScalarX86(b, s, tmp);
    }

    b.cmp(s, 0);
    b.je(skipStore);
    b.cmp(s, 255);
    b.je(storeDone);
    b.mov(inv, 255);
    b.sub(inv, s);
    b.imul(d, inv);
    _mulDiv255ScalarX86(b, d, tmp);
    b.add(s, d);

    b.label(storeDone);
    b.mov(out8, s);
    b.mov(X86Mem.baseDisp(rowDst, 0, size: 1), out8);

    b.label(skipStore);
    b.add(rowSrc, 1);
    b.add(rowDst, 1);
  }

  _loadInt(b, tmp64, srcStrideConst, srcStride);
  b.sub(tmp64, rowBytes);
  b.add(rowSrc, tmp64);
  _loadInt(b, tmp64, dstStrideConst, dstStride);
  b.sub(tmp64, rowBytes);
  b.add(rowDst, tmp64);
  if (hasMask) {
    b.add(rowMask, maskStep);
  }
  b.dec(yCount);
  b.jmp(loopY);

  b.label(done);
}

void _emitSrcOverA8X86(
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
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg(size: 4);
  final tmp64 = b.newGpReg();
  final s8 = b.newGpReg(size: 1);
  final d8 = b.newGpReg(size: 1);
  final s = b.newGpReg(size: 4);
  final d = b.newGpReg(size: 4);
  final inv = b.newGpReg(size: 4);
  final out8 = b.newGpReg(size: 1);
  final m = b.newGpReg(size: 4);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg();
  final maskBytes = b.newGpReg();

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadInt(b, rowBytes, widthConst, width);
  _loadInt(b, yCount, heightConst, height);
  if (hasMask) {
    b.mov(rowMask, maskConst.address);
    _loadInt(b, maskBytes, widthConst, width);
    if (maskStrideConst != 0) {
      b.mov(maskStep, maskStrideConst);
      b.sub(maskStep, maskBytes);
    } else {
      b.mov(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
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

  b.mov(s8, X86Mem.baseDisp(rowSrc, 0, size: 1));
  b.mov(d8, X86Mem.baseDisp(rowDst, 0, size: 1));
  b.movzx(s, s8);
  b.movzx(d, d8);

  if (needsMasking) {
    if (hasMask) {
      b.movzx(m, X86Mem.baseDisp(rowMask, 0, size: 1));
      if (hasGlobalAlpha) {
        b.imul(m, globalAlphaConst);
        _mulDiv255ScalarX86(b, m, tmp);
      }
      b.add(rowMask, 1);
    } else {
      b.mov(m, globalAlphaConst);
    }
    b.cmp(m, 0);
    b.je(skipStore);
    b.cmp(m, 255);
    b.je(storeDone);
    b.imul(s, m);
    _mulDiv255ScalarX86(b, s, tmp);
  }

  b.cmp(s, 0);
  b.je(skipStore);
  b.cmp(s, 255);
  b.je(storeDone);
  b.mov(inv, 255);
  b.sub(inv, s);
  b.imul(d, inv);
  _mulDiv255ScalarX86(b, d, tmp);
  b.add(s, d);

  b.label(storeDone);
  b.mov(out8, s);
  b.mov(X86Mem.baseDisp(rowDst, 0, size: 1), out8);

  b.label(skipStore);
  b.add(rowSrc, 1);
  b.add(rowDst, 1);
  b.dec(xCount);
  b.jmp(loopX);

  b.label(endRow);
  _loadInt(b, tmp64, srcStrideConst, srcStride);
  b.sub(tmp64, rowBytes);
  b.add(rowSrc, tmp64);
  _loadInt(b, tmp64, dstStrideConst, dstStride);
  b.sub(tmp64, rowBytes);
  b.add(rowDst, tmp64);
  if (hasMask) {
    b.add(rowMask, maskStep);
  }
  b.dec(yCount);
  b.jmp(loopY);

  b.label(done);
}

void _mulDiv255ScalarX86(X86CodeBuilder b, VirtReg reg, VirtReg tmp) {
  b.add(reg, 128);
  b.mov(tmp, reg);
  b.shr(tmp, 8);
  b.add(reg, tmp);
  b.shr(reg, 8);
}

void _applyMaskPRGB32X86(
  X86CodeBuilder b,
  VirtReg s,
  VirtReg m,
  VirtReg tmp,
  VirtReg rb,
  VirtReg ag,
) {
  b.mov(rb, s);
  b.and(rb, 0x00FF00FF);
  b.mov(ag, s);
  b.shr(ag, 8);
  b.and(ag, 0x00FF00FF);
  b.imul(rb, m);
  b.imul(ag, m);
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
  b.and(ag, 0xFF00FF00);
  b.and(rb, 0x00FF00FF);
  b.or(ag, rb);
  b.mov(s, ag);
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
  A64Gp srcStride, {
  int widthConst = 0,
  int heightConst = 0,
  int dstStrideConst = 0,
  int srcStrideConst = 0,
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
}) {
  final isA8 = dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8;
  final needAlpha = !isA8 &&
      (dstFormat == PixelFormat.xrgb32 || srcFormat == PixelFormat.xrgb32);
  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg();
  final yCount = b.newGpReg();
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg();
  final pixel = b.newGpReg(sizeBits: 32);
  final alphaMask = needAlpha ? b.newGpReg(sizeBits: 32) : null;

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadIntA64(b, rowBytes, widthConst, width);
  if (!isA8) {
    b.add(rowBytes, rowBytes, width);
    b.add(rowBytes, rowBytes, rowBytes);
  }
  _loadIntA64(b, yCount, heightConst, height.w);
  if (needAlpha) {
    b.movImm32(alphaMask!, 0xFF000000);
  }

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  _loadIntA64(b, xCount, widthConst, width);
  b.label(loopX);
  b.cbz(xCount, endRow);

  if (isA8) {
    b.ldrb(pixel, rowSrc, 0);
    b.strb(pixel, rowDst, 0);
    b.add(rowSrc, rowSrc, 1);
    b.add(rowDst, rowDst, 1);
  } else {
    b.ldr(pixel, rowSrc, 0);
    if (needAlpha) {
      b.orr(pixel, pixel, alphaMask!);
    }
    b.str(pixel, rowDst, 0);
    b.add(rowSrc, rowSrc, 4);
    b.add(rowDst, rowDst, 4);
  }
  b.sub(xCount, xCount, 1);
  b.b(loopX);

  b.label(endRow);
  _loadIntA64(b, tmp, srcStrideConst, srcStride);
  b.sub(tmp, tmp, rowBytes);
  b.add(rowSrc, rowSrc, tmp);
  _loadIntA64(b, tmp, dstStrideConst, dstStride);
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
  A64Gp color, {
  required PixelFormat dstFormat,
  required int colorConst,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  if (globalAlphaConst == 0) {
    return;
  }
  final isA8 = dstFormat == PixelFormat.a8;
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

  if (isA8) {
    final rowDst = b.newGpReg();
    final xCount = b.newGpReg(sizeBits: 32);
    final yCount = b.newGpReg(sizeBits: 32);
    final rowBytes = b.newGpReg(sizeBits: 32);
    final tmp = b.newGpReg(sizeBits: 32);
    final tmp2 = b.newGpReg(sizeBits: 32);
    final base = b.newGpReg(sizeBits: 32);
    final s = b.newGpReg(sizeBits: 32);
    final d = b.newGpReg(sizeBits: 32);
    final inv = b.newGpReg(sizeBits: 32);
    final m = b.newGpReg(sizeBits: 32);
    final rowMask = b.newGpReg();
    final maskStep = b.newGpReg(sizeBits: 32);
    final maskBytes = b.newGpReg(sizeBits: 32);
    final const255 = b.newGpReg(sizeBits: 32);
    final byteMask = b.newGpReg(sizeBits: 32);
    final globalAlpha = hasGlobalAlpha ? b.newGpReg(sizeBits: 32) : null;

    b.mov(rowDst, dst);
    b.mov(rowBytes, width.w);
    b.mov(yCount, height.w);
    if (colorConst != 0) {
      b.movImm32(base, colorConst);
    } else {
      b.mov(base, color.w);
    }
    b.movImm32(byteMask, 0xFF);
    b.and(base, base, byteMask);
    b.movImm32(const255, 255);
    if (hasGlobalAlpha) {
      b.movImm32(globalAlpha!, globalAlphaConst);
    }
    if (hasMask) {
      _movImmPtrA64(b, rowMask, maskConst.address);
      b.mov(maskBytes, width.w);
      if (maskStrideConst != 0) {
        b.movImm32(maskStep, maskStrideConst);
        b.sub(maskStep, maskStep, maskBytes);
      } else {
        b.movImm32(maskStep, 0);
      }
    }

    final loopY = b.newLabel();
    final loopX = b.newLabel();
    final endRow = b.newLabel();
    final storeSrc = b.newLabel();
    final skipStore = b.newLabel();
    final skipMask = b.newLabel();
    final storeDone = b.newLabel();
    final done = b.newLabel();

    b.label(loopY);
    b.cbz(yCount, done);

    b.mov(xCount, width.w);
    b.label(loopX);
    b.cbz(xCount, endRow);

    b.mov(s, base);
    if (needsMasking) {
      if (hasMask) {
        b.ldrb(m, rowMask, 0);
        if (hasGlobalAlpha) {
          b.mul(m, m, globalAlpha!);
          _mulDiv255ScalarA64(b, m, tmp);
        }
        b.add(rowMask, rowMask, 1);
      } else {
        b.movImm32(m, globalAlphaConst);
      }
      b.cbz(m, skipStore);
      b.eor(tmp, m, const255);
      b.cbz(tmp, skipMask);
      b.mul(s, s, m);
      _mulDiv255ScalarA64(b, s, tmp);
    }

    b.label(skipMask);
    b.ldrb(d, rowDst, 0);
    b.cbz(s, skipStore);
    b.eor(tmp, s, const255);
    b.cbz(tmp, storeSrc);
    b.sub(inv, const255, s);
    b.mul(d, d, inv);
    _mulDiv255ScalarA64(b, d, tmp);
    b.add(s, s, d);

    b.label(storeSrc);
    b.strb(s, rowDst, 0);
    b.b(storeDone);

    b.label(skipStore);
    b.label(storeDone);

    b.add(rowDst, rowDst, 1);
    b.sub(xCount, xCount, 1);
    b.b(loopX);

    b.label(endRow);
    b.mov(tmp2, dstStride.w);
    b.sub(tmp2, tmp2, rowBytes);
    b.add(rowDst, rowDst, tmp2.x);
    if (hasMask) {
      b.add(rowMask, rowMask, maskStep);
    }
    b.sub(yCount, yCount, 1);
    b.b(loopY);

    b.label(done);
    return;
  }

  final rowDst = b.newGpReg();
  final xCount = b.newGpReg(sizeBits: 32);
  final yCount = b.newGpReg(sizeBits: 32);
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg(sizeBits: 32);
  final tmp2 = b.newGpReg(sizeBits: 32);
  final base = b.newGpReg(sizeBits: 32);
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
  final alphaMask = dstFormat == PixelFormat.xrgb32
      ? b.newGpReg(sizeBits: 32)
      : null;
  final m = b.newGpReg(sizeBits: 32);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg(sizeBits: 32);
  final maskBytes = b.newGpReg(sizeBits: 32);
  final globalAlpha = hasGlobalAlpha ? b.newGpReg(sizeBits: 32) : null;

  b.movImm32(maskRB, 0x00FF00FF);
  b.movImm32(maskAG, 0xFF00FF00);
  b.movImm32(round, 0x00800080);
  b.movImm32(const255, 255);
  if (alphaMask != null) {
    b.movImm32(alphaMask, 0xFF000000);
  }
  if (hasGlobalAlpha) {
    b.movImm32(globalAlpha!, globalAlphaConst);
  }

  b.mov(rowDst, dst);
  b.mov(rowBytes, width);
  b.add(rowBytes, rowBytes, width);
  b.add(rowBytes, rowBytes, rowBytes);
  b.mov(yCount, height.w);
  if (colorConst != 0) {
    b.movImm32(base, colorConst);
  } else {
    b.mov(base, color.w);
  }
  if (alphaMask != null) {
    b.orr(base, base, alphaMask);
  }
  if (hasMask) {
    _movImmPtrA64(b, rowMask, maskConst.address);
    b.mov(maskBytes, width.w);
    if (maskStrideConst != 0) {
      b.movImm32(maskStep, maskStrideConst);
      b.sub(maskStep, maskStep, maskBytes);
    } else {
      b.movImm32(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final storeSrc = b.newLabel();
  final skipStore = b.newLabel();
  final skipMask = b.newLabel();
  final storeDone = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  b.mov(xCount, width.w);
  b.label(loopX);
  b.cbz(xCount, endRow);

  b.mov(s, base);
  if (needsMasking) {
    if (hasMask) {
      b.ldrb(m, rowMask, 0);
      if (hasGlobalAlpha) {
        b.mul(m, m, globalAlpha!);
        _mulDiv255ScalarA64(b, m, tmp);
      }
      b.add(rowMask, rowMask, 1);
    } else {
      b.movImm32(m, globalAlphaConst);
    }
    b.cbz(m, skipStore);
    b.eor(tmp, m, const255);
    b.cbz(tmp, skipMask);
    _applyMaskPRGB32A64(b, s, m, tmp, rb, ag, maskRB, round, maskAG);
  }

  b.label(skipMask);
  b.ldr(d, rowDst, 0);
  if (alphaMask != null) {
    b.orr(d, d, alphaMask);
  }
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
  if (alphaMask != null) {
    b.orr(ag, ag, alphaMask);
  }
  b.str(ag, rowDst, 0);
  b.b(storeDone);

  b.label(storeSrc);
  if (alphaMask != null) {
    b.orr(s, s, alphaMask);
  }
  b.str(s, rowDst, 0);
  b.b(storeDone);

  b.label(skipStore);
  b.label(storeDone);

  b.add(rowDst, rowDst, 4);
  b.sub(xCount, xCount, 1);
  b.b(loopX);

  b.label(endRow);
  b.mov(tmp2, dstStride.w);
  b.sub(tmp2, tmp2, rowBytes.w);
  b.add(rowDst, rowDst, tmp2.x);
  if (hasMask) {
    b.add(rowMask, rowMask, maskStep);
  }
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
  A64Gp srcStride, {
  required int widthConst,
  required int heightConst,
  required int dstStrideConst,
  required int srcStrideConst,
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  if (globalAlphaConst == 0) {
    return;
  }
  final isA8 = dstFormat == PixelFormat.a8 || srcFormat == PixelFormat.a8;
  if (isA8) {
    if (widthConst > 0 && widthConst <= 4) {
      _emitSrcOverA8A64FixedWidth(
        b,
        dst,
        src,
        height,
        dstStride,
        srcStride,
        widthConst: widthConst,
        heightConst: heightConst,
        dstStrideConst: dstStrideConst,
        srcStrideConst: srcStrideConst,
        globalAlphaConst: globalAlphaConst,
        maskConst: maskConst,
        maskStrideConst: maskStrideConst,
      );
      return;
    }
    _emitSrcOverA8A64(
      b,
      dst,
      src,
      width,
      height,
      dstStride,
      srcStride,
      widthConst: widthConst,
      heightConst: heightConst,
      dstStrideConst: dstStrideConst,
      srcStrideConst: srcStrideConst,
      globalAlphaConst: globalAlphaConst,
      maskConst: maskConst,
      maskStrideConst: maskStrideConst,
    );
    return;
  }
  if (widthConst > 0 && widthConst <= 4) {
    _emitSrcOver32A64FixedWidth(
      b,
      dst,
      src,
      height,
      dstStride,
      srcStride,
      widthConst: widthConst,
      heightConst: heightConst,
      dstStrideConst: dstStrideConst,
      srcStrideConst: srcStrideConst,
      dstFormat: dstFormat,
      srcFormat: srcFormat,
      globalAlphaConst: globalAlphaConst,
      maskConst: maskConst,
      maskStrideConst: maskStrideConst,
    );
    return;
  }
  _emitSrcOver32A64(
    b,
    dst,
    src,
    width,
    height,
    dstStride,
    srcStride,
    widthConst: widthConst,
    heightConst: heightConst,
    dstStrideConst: dstStrideConst,
    srcStrideConst: srcStrideConst,
    dstFormat: dstFormat,
    srcFormat: srcFormat,
    globalAlphaConst: globalAlphaConst,
    maskConst: maskConst,
    maskStrideConst: maskStrideConst,
  );
}

void _emitSrcOver32A64FixedWidth(
  A64CodeBuilder b,
  A64Gp dst,
  A64Gp src,
  A64Gp height,
  A64Gp dstStride,
  A64Gp srcStride, {
  required int widthConst,
  required int heightConst,
  required int dstStrideConst,
  required int srcStrideConst,
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;
  final needAlpha =
      dstFormat == PixelFormat.xrgb32 || srcFormat == PixelFormat.xrgb32;

  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final yCount = b.newGpReg(sizeBits: 32);
  final rowBytes = b.newGpReg(sizeBits: 32);
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
  final alphaMask = needAlpha ? b.newGpReg(sizeBits: 32) : null;
  final globalAlpha = hasGlobalAlpha ? b.newGpReg(sizeBits: 32) : null;
  final m = b.newGpReg(sizeBits: 32);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg(sizeBits: 32);
  final maskBytes = b.newGpReg(sizeBits: 32);

  b.movImm32(maskRB, 0x00FF00FF);
  b.movImm32(maskAG, 0xFF00FF00);
  b.movImm32(round, 0x00800080);
  b.movImm32(const255, 255);
  if (needAlpha) {
    b.movImm32(alphaMask!, 0xFF000000);
  }
  if (hasGlobalAlpha) {
    b.movImm32(globalAlpha!, globalAlphaConst);
  }

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  b.movImm32(rowBytes, widthConst * 4);
  _loadIntA64(b, yCount, heightConst, height);
  if (hasMask) {
    _movImmPtrA64(b, rowMask, maskConst.address);
    b.movImm32(maskBytes, widthConst);
    if (maskStrideConst != 0) {
      b.movImm32(maskStep, maskStrideConst);
      b.sub(maskStep, maskStep, maskBytes);
    } else {
      b.movImm32(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  for (var i = 0; i < widthConst; i++) {
    final storeSrc = b.newLabel();
    final skipStore = b.newLabel();
    final skipMask = b.newLabel();
    final storeDone = b.newLabel();

    b.ldr(s, rowSrc, 0);
    if (srcFormat == PixelFormat.xrgb32) {
      b.orr(s, s, alphaMask!);
    }
    b.ldr(d, rowDst, 0);
    if (dstFormat == PixelFormat.xrgb32) {
      b.orr(d, d, alphaMask!);
    }
    if (needsMasking) {
      if (hasMask) {
        b.ldrb(m, rowMask, 0);
        if (hasGlobalAlpha) {
          b.mul(m, m, globalAlpha!);
          _mulDiv255ScalarA64(b, m, tmp);
        }
        b.add(rowMask, rowMask, 1);
      } else {
        b.movImm32(m, globalAlphaConst);
      }
      b.cbz(m, skipStore);
      b.eor(tmp, m, const255);
      b.cbz(tmp, skipMask);
      _applyMaskPRGB32A64(b, s, m, tmp, rb, ag, maskRB, round, maskAG);
    }

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
    if (dstFormat == PixelFormat.xrgb32) {
      b.orr(ag, ag, alphaMask!);
    }
    b.str(ag, rowDst, 0);
    b.b(storeDone);

    b.label(skipMask);

    b.label(storeSrc);
    if (dstFormat == PixelFormat.xrgb32) {
      b.orr(s, s, alphaMask!);
    }
    b.str(s, rowDst, 0);
    b.b(storeDone);

    b.label(skipStore);
    b.label(storeDone);

    b.add(rowSrc, rowSrc, 4);
    b.add(rowDst, rowDst, 4);
  }

  _loadIntA64(b, tmp2, srcStrideConst, srcStride);
  b.sub(tmp2, tmp2, rowBytes);
  b.add(rowSrc, rowSrc, tmp2);
  _loadIntA64(b, tmp2, dstStrideConst, dstStride);
  b.sub(tmp2, tmp2, rowBytes);
  b.add(rowDst, rowDst, tmp2);
  if (hasMask) {
    b.add(rowMask, rowMask, maskStep);
  }
  b.sub(yCount, yCount, 1);
  b.b(loopY);

  b.label(done);
}

void _emitSrcOver32A64(
  A64CodeBuilder b,
  A64Gp dst,
  A64Gp src,
  A64Gp width,
  A64Gp height,
  A64Gp dstStride,
  A64Gp srcStride, {
  int widthConst = 0,
  int heightConst = 0,
  int dstStrideConst = 0,
  int srcStrideConst = 0,
  required PixelFormat dstFormat,
  required PixelFormat srcFormat,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;
  final needAlpha =
      dstFormat == PixelFormat.xrgb32 || srcFormat == PixelFormat.xrgb32;

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
  final alphaMask = needAlpha ? b.newGpReg(sizeBits: 32) : null;
  final globalAlpha = hasGlobalAlpha ? b.newGpReg(sizeBits: 32) : null;
  final m = b.newGpReg(sizeBits: 32);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg();
  final maskBytes = b.newGpReg();

  b.movImm32(maskRB, 0x00FF00FF);
  b.movImm32(maskAG, 0xFF00FF00);
  b.movImm32(round, 0x00800080);
  b.movImm32(const255, 255);
  if (needAlpha) {
    b.movImm32(alphaMask!, 0xFF000000);
  }
  if (hasGlobalAlpha) {
    b.movImm32(globalAlpha!, globalAlphaConst);
  }

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadIntA64(b, rowBytes, widthConst, width);
  b.add(rowBytes, rowBytes, width);
  b.add(rowBytes, rowBytes, rowBytes);
  _loadIntA64(b, yCount, heightConst, height);
  if (hasMask) {
    _movImmPtrA64(b, rowMask, maskConst.address);
    _loadIntA64(b, maskBytes, widthConst, width.w);
    if (maskStrideConst != 0) {
      b.movImm32(maskStep, maskStrideConst);
      b.sub(maskStep, maskStep, maskBytes);
    } else {
      b.movImm32(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final storeSrc = b.newLabel();
  final skipStore = b.newLabel();
  final skipMask = b.newLabel();
  final storeDone = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  _loadIntA64(b, xCount, widthConst, width.w);
  b.label(loopX);
  b.cbz(xCount, endRow);

  b.ldr(s, rowSrc, 0);
  if (srcFormat == PixelFormat.xrgb32) {
    b.orr(s, s, alphaMask!);
  }
  b.ldr(d, rowDst, 0);
  if (dstFormat == PixelFormat.xrgb32) {
    b.orr(d, d, alphaMask!);
  }
  if (needsMasking) {
    if (hasMask) {
      b.ldrb(m, rowMask, 0);
      if (hasGlobalAlpha) {
        b.mul(m, m, globalAlpha!);
        _mulDiv255ScalarA64(b, m, tmp);
      }
      b.add(rowMask, rowMask, 1);
    } else {
      b.movImm32(m, globalAlphaConst);
    }
    b.cbz(m, skipStore);
    b.eor(tmp, m, const255);
    b.cbz(tmp, skipMask);
    _applyMaskPRGB32A64(b, s, m, tmp, rb, ag, maskRB, round, maskAG);
  }

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
  if (dstFormat == PixelFormat.xrgb32) {
    b.orr(ag, ag, alphaMask!);
  }
  b.str(ag, rowDst, 0);
  b.b(storeDone);

  b.label(skipMask);

  b.label(storeSrc);
  if (dstFormat == PixelFormat.xrgb32) {
    b.orr(s, s, alphaMask!);
  }
  b.str(s, rowDst, 0);
  b.b(storeDone);

  b.label(skipStore);
  b.label(storeDone);

  b.add(rowSrc, rowSrc, 4);
  b.add(rowDst, rowDst, 4);
  b.sub(xCount, xCount, 1);
  b.b(loopX);

  b.label(endRow);
  _loadIntA64(b, tmp2, srcStrideConst, srcStride);
  b.sub(tmp2, tmp2, rowBytes.w);
  b.add(rowSrc, rowSrc, tmp2.x);
  _loadIntA64(b, tmp2, dstStrideConst, dstStride);
  b.sub(tmp2, tmp2, rowBytes.w);
  b.add(rowDst, rowDst, tmp2.x);
  if (hasMask) {
    b.add(rowMask, rowMask, maskStep);
  }
  b.sub(yCount, yCount, 1);
  b.b(loopY);

  b.label(done);
}

void _emitSrcOverA8A64FixedWidth(
  A64CodeBuilder b,
  A64Gp dst,
  A64Gp src,
  A64Gp height,
  A64Gp dstStride,
  A64Gp srcStride, {
  required int widthConst,
  required int heightConst,
  required int dstStrideConst,
  required int srcStrideConst,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final yCount = b.newGpReg(sizeBits: 32);
  final rowBytes = b.newGpReg(sizeBits: 32);
  final tmp = b.newGpReg(sizeBits: 32);
  final tmp2 = b.newGpReg(sizeBits: 32);
  final s = b.newGpReg(sizeBits: 32);
  final d = b.newGpReg(sizeBits: 32);
  final inv = b.newGpReg(sizeBits: 32);
  final const255 = b.newGpReg(sizeBits: 32);
  final globalAlpha = hasGlobalAlpha ? b.newGpReg(sizeBits: 32) : null;
  final m = b.newGpReg(sizeBits: 32);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg(sizeBits: 32);
  final maskBytes = b.newGpReg(sizeBits: 32);

  b.movImm32(const255, 255);
  if (hasGlobalAlpha) {
    b.movImm32(globalAlpha!, globalAlphaConst);
  }

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  b.movImm32(rowBytes, widthConst);
  _loadIntA64(b, yCount, heightConst, height);
  if (hasMask) {
    _movImmPtrA64(b, rowMask, maskConst.address);
    b.movImm32(maskBytes, widthConst);
    if (maskStrideConst != 0) {
      b.movImm32(maskStep, maskStrideConst);
      b.sub(maskStep, maskStep, maskBytes);
    } else {
      b.movImm32(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  for (var i = 0; i < widthConst; i++) {
    final skipStore = b.newLabel();
    final storeDone = b.newLabel();

    b.ldrb(s, rowSrc, 0);
    b.ldrb(d, rowDst, 0);

    if (needsMasking) {
      if (hasMask) {
        b.ldrb(m, rowMask, 0);
        if (hasGlobalAlpha) {
          b.mul(m, m, globalAlpha!);
          _mulDiv255ScalarA64(b, m, tmp);
        }
        b.add(rowMask, rowMask, 1);
      } else {
        b.movImm32(m, globalAlphaConst);
      }
      b.cbz(m, skipStore);
      b.eor(tmp, m, const255);
      b.cbz(tmp, storeDone);
      b.mul(s, s, m);
      _mulDiv255ScalarA64(b, s, tmp);
    }

    b.cbz(s, skipStore);
    b.eor(tmp, s, const255);
    b.cbz(tmp, storeDone);
    b.sub(inv, const255, s);
    b.mul(d, d, inv);
    _mulDiv255ScalarA64(b, d, tmp);
    b.add(s, s, d);

    b.label(storeDone);
    b.strb(s, rowDst, 0);

    b.label(skipStore);
    b.add(rowSrc, rowSrc, 1);
    b.add(rowDst, rowDst, 1);
  }

  _loadIntA64(b, tmp2, srcStrideConst, srcStride);
  b.sub(tmp2, tmp2, rowBytes);
  b.add(rowSrc, rowSrc, tmp2);
  _loadIntA64(b, tmp2, dstStrideConst, dstStride);
  b.sub(tmp2, tmp2, rowBytes);
  b.add(rowDst, rowDst, tmp2);
  if (hasMask) {
    b.add(rowMask, rowMask, maskStep);
  }
  b.sub(yCount, yCount, 1);
  b.b(loopY);

  b.label(done);
}

void _emitSrcOverA8A64(
  A64CodeBuilder b,
  A64Gp dst,
  A64Gp src,
  A64Gp width,
  A64Gp height,
  A64Gp dstStride,
  A64Gp srcStride, {
  int widthConst = 0,
  int heightConst = 0,
  int dstStrideConst = 0,
  int srcStrideConst = 0,
  required int globalAlphaConst,
  required Pointer<Uint8>? maskConst,
  required int maskStrideConst,
}) {
  final hasMask = maskConst != null;
  final hasGlobalAlpha = globalAlphaConst != 255;
  final needsMasking = hasMask || hasGlobalAlpha;

  final rowDst = b.newGpReg();
  final rowSrc = b.newGpReg();
  final xCount = b.newGpReg(sizeBits: 32);
  final yCount = b.newGpReg(sizeBits: 32);
  final rowBytes = b.newGpReg();
  final tmp = b.newGpReg(sizeBits: 32);
  final tmp2 = b.newGpReg(sizeBits: 32);
  final s = b.newGpReg(sizeBits: 32);
  final d = b.newGpReg(sizeBits: 32);
  final inv = b.newGpReg(sizeBits: 32);
  final const255 = b.newGpReg(sizeBits: 32);
  final globalAlpha = hasGlobalAlpha ? b.newGpReg(sizeBits: 32) : null;
  final m = b.newGpReg(sizeBits: 32);
  final rowMask = b.newGpReg();
  final maskStep = b.newGpReg();
  final maskBytes = b.newGpReg();

  b.movImm32(const255, 255);
  if (hasGlobalAlpha) {
    b.movImm32(globalAlpha!, globalAlphaConst);
  }

  b.mov(rowDst, dst);
  b.mov(rowSrc, src);
  _loadIntA64(b, rowBytes, widthConst, width);
  _loadIntA64(b, yCount, heightConst, height.w);
  if (hasMask) {
    _movImmPtrA64(b, rowMask, maskConst.address);
    _loadIntA64(b, maskBytes, widthConst, width.w);
    if (maskStrideConst != 0) {
      b.movImm32(maskStep, maskStrideConst);
      b.sub(maskStep, maskStep, maskBytes);
    } else {
      b.movImm32(maskStep, 0);
    }
  }

  final loopY = b.newLabel();
  final loopX = b.newLabel();
  final endRow = b.newLabel();
  final skipStore = b.newLabel();
  final storeDone = b.newLabel();
  final done = b.newLabel();

  b.label(loopY);
  b.cbz(yCount, done);

  _loadIntA64(b, xCount, widthConst, width.w);
  b.label(loopX);
  b.cbz(xCount, endRow);

  b.ldrb(s, rowSrc, 0);
  b.ldrb(d, rowDst, 0);

  if (needsMasking) {
    if (hasMask) {
      b.ldrb(m, rowMask, 0);
      if (hasGlobalAlpha) {
        b.mul(m, m, globalAlpha!);
        _mulDiv255ScalarA64(b, m, tmp);
      }
      b.add(rowMask, rowMask, 1);
    } else {
      b.movImm32(m, globalAlphaConst);
    }
    b.cbz(m, skipStore);
    b.eor(tmp, m, const255);
    b.cbz(tmp, storeDone);
    b.mul(s, s, m);
    _mulDiv255ScalarA64(b, s, tmp);
  }

  b.cbz(s, skipStore);
  b.eor(tmp, s, const255);
  b.cbz(tmp, storeDone);
  b.sub(inv, const255, s);
  b.mul(d, d, inv);
  _mulDiv255ScalarA64(b, d, tmp);
  b.add(s, s, d);

  b.label(storeDone);
  b.strb(s, rowDst, 0);

  b.label(skipStore);
  b.add(rowSrc, rowSrc, 1);
  b.add(rowDst, rowDst, 1);
  b.sub(xCount, xCount, 1);
  b.b(loopX);

  b.label(endRow);
  _loadIntA64(b, tmp2, srcStrideConst, srcStride.w);
  b.sub(tmp2, tmp2, rowBytes.w);
  b.add(rowSrc, rowSrc, tmp2.x);
  _loadIntA64(b, tmp2, dstStrideConst, dstStride.w);
  b.sub(tmp2, tmp2, rowBytes.w);
  b.add(rowDst, rowDst, tmp2.x);
  if (hasMask) {
    b.add(rowMask, rowMask, maskStep);
  }
  b.sub(yCount, yCount, 1);
  b.b(loopY);

  b.label(done);
}

void _mulDiv255ScalarA64(A64CodeBuilder b, A64Gp reg, A64Gp tmp) {
  b.add(reg, reg, 128);
  b.lsr(tmp, reg, 8);
  b.add(reg, reg, tmp);
  b.lsr(reg, reg, 8);
}

void _movImmPtrA64(A64CodeBuilder b, A64Gp rd, int value) {
  final imm = value & 0xFFFFFFFFFFFFFFFF;
  b.movz(rd, imm & 0xFFFF);
  final part16 = (imm >> 16) & 0xFFFF;
  if (part16 != 0) {
    b.movk(rd, part16, shift: 16);
  }
  final part32 = (imm >> 32) & 0xFFFF;
  if (part32 != 0) {
    b.movk(rd, part32, shift: 32);
  }
  final part48 = (imm >> 48) & 0xFFFF;
  if (part48 != 0) {
    b.movk(rd, part48, shift: 48);
  }
}

void _loadIntA64(A64CodeBuilder b, A64Gp dst, int constant, A64Gp fallback) {
  if (constant != 0) {
    b.movImm32(dst, constant);
  } else {
    b.mov(dst, fallback);
  }
}

void _applyMaskPRGB32A64(
  A64CodeBuilder b,
  A64Gp s,
  A64Gp m,
  A64Gp tmp,
  A64Gp rb,
  A64Gp ag,
  A64Gp maskRB,
  A64Gp round,
  A64Gp maskAG,
) {
  b.and(rb, s, maskRB);
  b.lsr(ag, s, 8);
  b.and(ag, ag, maskRB);
  b.mul(rb, rb, m);
  b.mul(ag, ag, m);
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
  b.mov(s, ag);
}
