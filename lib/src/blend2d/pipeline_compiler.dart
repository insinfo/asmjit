import 'package:asmjit/asmjit.dart';
import 'package:asmjit/blend2d.dart';

/// TODO Blend2D pipeline compiler (stub).
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
    for (final op in ops) {
      // TODO: Lower Blend2D pipeline ops to real codegen.
      builder.comment('pipeline ${op.kind.name}');
      builder.mov(rax, rax);
    }
  }
}
