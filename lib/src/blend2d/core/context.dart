// Blend2D Rendering Context
// Port of blend2d/core/context.h (partial)

import 'dart:ffi';

import 'image.dart';
import 'format.dart';
import 'rgba.dart';
import '../geometry/types.dart';
import '../pipeline/jit/pipeline_compiler.dart';
import '../pipeline/pipeline_ops.dart';

import '../../asmjit/runtime/jit_runtime.dart';

/// Composition operator.
///
/// See [PipelineOpKind] for mapping.
enum BLCompOp {
  srcOver,
  srcCopy,
  srcIn,
  srcOut,
  srcAtop,
  dstOver,
  dstCopy,
  dstIn,
  dstOut,
  dstAtop,
  xor,
  plus,
  minus,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
}

/// Rendering context.
class BLContext {
  BLImage? _target;
  final JitRuntime _jitRuntime;
  final PipelineCompiler _compiler;
  final Map<String, PipelineProgram> _pipelineCache = {};

  // -- State --
  BLCompOp _compOp = BLCompOp.srcOver;
  double _globalAlpha = 1.0;
  BLRgba32 _fillStyle = BLRgba32(0xFF, 0xFF, 0xFF, 0xFF);
  int _fillStyleInt = 0xFFFFFFFF; // Pre-calculated

  BLContext(this._target, {JitRuntime? runtime})
      : _jitRuntime = runtime ?? JitRuntime(),
        _compiler = PipelineCompiler();

  /// Target image.
  BLImage? get target => _target;

  /// Current global alpha [0.0, 1.0].
  double get globalAlpha => _globalAlpha;
  set globalAlpha(double value) {
    _globalAlpha = value.clamp(0.0, 1.0);
  }

  /// Current composition operator.
  BLCompOp get compOp => _compOp;
  set compOp(BLCompOp value) {
    _compOp = value;
  }

  /// Current fill style (solid color).
  BLRgba32 get fillStyle => _fillStyle;
  set fillStyle(BLRgba32 color) {
    _fillStyle = color;
    _fillStyleInt = color.value; // Store as ARGB32
    if (_target?.format == BLFormat.prgb32) {
      _fillStyleInt = color.premultiplied().value;
    } else if (_target?.format == BLFormat.xrgb32) {
      _fillStyleInt = color.value | 0xFF000000;
    }
  }

  /// Dispose resources.
  ///
  /// Note: The JitRuntime is NOT disposed here unless we own it (TODO),
  /// but we do clear the cached programs.
  void dispose() {
    for (final program in _pipelineCache.values) {
      program.dispose();
    }
    _pipelineCache.clear();
  }

  // -- Drawing Operations --

  /// Fill the entire image with the current fill style.
  void fillAll() {
    if (_target == null) return;

    // Optimization: If compOp is SrcCopy, just fill memory
    if (_compOp == BLCompOp.srcCopy && _globalAlpha == 1.0) {
      _target!.fillAll(_fillStyle);
      return;
    }

    final rect = BLRectI(0, 0, _target!.width, _target!.height);
    fillRect(rect);
  }

  /// Fill a rectangle.
  void fillRect(BLRectI rect) {
    if (_target == null) return;

    final intersect =
        rect.intersection(BLRectI(0, 0, _target!.width, _target!.height));

    if (intersect == null) return;

    final w = intersect.w;
    final h = intersect.h;
    if (w <= 0 || h <= 0) return;

    // Resolve pipeline
    // 1. FillSolid
    // 2. CompOp
    final op = PipelineOp(
      kind: _resolveFillCompOp(_compOp),
      dstFormat: _formatFromBL(_target!.format),
      srcFormat:
          PixelFormat.none, // Solid fill has no src format in this context
      width: w,
      height: h,
      dstStride: _target!.stride,
      color: _fillStyleInt,
      globalAlpha: (_globalAlpha * 255).round(),
    );

    final program = _getOrCompile([op]);

    // Calculate pointers
    // Dst pointer needs to be offset by x,y
    final dstPtr = _target!.data! +
        (intersect.y * _target!.stride) +
        (intersect.x * _target!.format.depth);

    program.execute(
      dst: dstPtr,
      src: nullptr, // Not used for solid fill
      width: w,
      height: h,
      dstStride: _target!.stride,
      color: _fillStyleInt,
    );
  }

  /// Blit an image at (x, y).
  void blitImage(int x, int y, BLImage src) {
    if (_target == null) return;

    var srcRect = BLRectI(0, 0, src.width, src.height);
    var dstRect = BLRectI(x, y, src.width, src.height);

    // Clip to destination
    final targetRect = BLRectI(0, 0, _target!.width, _target!.height);
    final visibleDst = dstRect.intersection(targetRect);

    if (visibleDst == null) return;

    // Adjust srcRect based on clipping
    final dx = visibleDst.x - dstRect.x;
    final dy = visibleDst.y - dstRect.y;

    // New width/height
    final w = visibleDst.w;
    final h = visibleDst.h;

    if (w <= 0 || h <= 0) return;

    // Calculate offsets
    final dstOffset = (visibleDst.y * _target!.stride) +
        (visibleDst.x * _target!.format.depth);
    final srcOffset =
        ((srcRect.y + dy) * src.stride) + ((srcRect.x + dx) * src.format.depth);

    final op = PipelineOp(
      kind: _resolveBlitCompOp(_compOp),
      dstFormat: _formatFromBL(_target!.format),
      srcFormat: _formatFromBL(src.format),
      width: w,
      height: h,
      dstStride: _target!.stride,
      srcStride: src.stride,
      globalAlpha: (_globalAlpha * 255).round(),
    );

    final program = _getOrCompile([op]);

    program.execute(
      dst: _target!.data! + dstOffset,
      src: src.data! + srcOffset,
      width: w,
      height: h,
      dstStride: _target!.stride,
      srcStride: src.stride,
    );
  }

  // -- Helpers --

  PipelineProgram _getOrCompile(List<PipelineOp> ops) {
    // Naive caching based on op composition
    // Ideally we serialize ops to a string key
    final sb = StringBuffer();
    for (final op in ops) {
      sb.write(
          '${op.kind.index}:${op.dstFormat.index}:${op.srcFormat.index}:${op.width}:${op.globalAlpha}|');
    }
    final key = sb.toString();

    if (_pipelineCache.containsKey(key)) {
      return _pipelineCache[key]!;
    }

    // Compile
    // TODO: Determine backend strategy (auto/JIT if possible)
    final program = _compiler.compileProgram(
      _jitRuntime,
      ops,
      backend: PipelineBackend.auto,
      cacheKey: key,
    );

    _pipelineCache[key] = program;
    return program;
  }

  PipelineOpKind _resolveFillCompOp(BLCompOp op) {
    // For solid fills, basic mapping
    switch (op) {
      case BLCompOp.srcCopy:
        return PipelineOpKind.fill; // Optimized Copy for Solid is Fill
      case BLCompOp.srcOver:
        // Fill doesn't have srcOver variant in PipelineOpKind yet,
        // we use Fill with flags or dedicated opcode?
        // Actually PipelineOpKind has: fill, copy, blit, compSrcOver.
        // For Solid SrcOver, we might need a specific op kind or reuse compSrcOver with special flags?
        // OR, we just use 'fill' if alpha is 1.0.
        // If alpha < 1.0, we need composition.
        // Current PipelineOpKind.fill does NOT support composition (it's a rewrite).
        // Current JIT only supports: copy, blit, fill, compSrcOver.
        // compSrcOver implies (dst, src).
        // We lack "FillSrcOver" (Solid + Dst).
        // Fallback: Use 'fill' for now, acting as SrcCopy.
        // TODO: Implement 'SolidCompOp' in pipeline.
        return PipelineOpKind.fill;
      default:
        return PipelineOpKind.fill;
    }
  }

  PipelineOpKind _resolveBlitCompOp(BLCompOp op) {
    switch (op) {
      case BLCompOp.srcCopy:
        return PipelineOpKind.blit; // or copy
      case BLCompOp.srcOver:
        return PipelineOpKind.compSrcOver;
      default:
        return PipelineOpKind.blit;
    }
  }

  PixelFormat _formatFromBL(BLFormat diff) {
    switch (diff) {
      case BLFormat.prgb32:
        return PixelFormat.prgb32;
      case BLFormat.xrgb32:
        return PixelFormat.xrgb32;
      case BLFormat.a8:
        return PixelFormat.a8;
      default:
        return PixelFormat.none;
    }
  }
}

extension on BLRectI {
  BLRectI? intersection(BLRectI other) {
    final l = (x > other.x) ? x : other.x;
    final t = (y > other.y) ? y : other.y;
    final r = (x + w < other.x + other.w) ? (x + w) : (other.x + other.w);
    final b = (y + h < other.y + other.h) ? (y + h) : (other.y + other.h);

    if (l < r && t < b) {
      return BLRectI(l, t, r - l, b - t);
    }
    return null;
  }
}
