import '../core/compiler.dart';
import '../core/builder.dart';
import '../core/code_builder.dart';
import '../core/code_holder.dart';
import '../core/environment.dart';
import '../core/labels.dart';
import '../runtime/jit_runtime.dart';

import 'x86_inst_db.g.dart'; // generated IDs
import 'x86_func.dart';

/// Analyzes x86 instructions for CFG construction.
class X86InstructionAnalyzer implements InstructionAnalyzer {
  static const _jccIds = <int>{
    X86InstId.kJo, X86InstId.kJno,
    X86InstId.kJb, X86InstId.kJnb,
    X86InstId.kJz, X86InstId.kJnz,
    X86InstId.kJbe, X86InstId.kJnbe,
    X86InstId.kJs, X86InstId.kJns,
    X86InstId.kJp, X86InstId.kJnp,
    X86InstId.kJl, X86InstId.kJnl,
    X86InstId.kJle, X86InstId.kJnle,
    // Note: Canonical IDs are used.
    // Aliases like kJae map to kJnb in some DBs, or exist separately.
    // Assuming canonical coverage here.
  };

  @override
  Label? getJumpTarget(InstNode node) {
    if (node.operands.isNotEmpty) {
      final op = node.operands[0];
      if (op is LabelOperand) {
        return op.label;
      }
    }
    return null;
  }

  @override
  bool isJoin(InstNode node) {
    return false; // Labels/Blocks handled separately
  }

  @override
  bool isJump(InstNode node) {
    return _jccIds.contains(node.instId) || node.instId == X86InstId.kJmp;
  }

  @override
  bool isReturn(InstNode node) {
    return node.instId == X86InstId.kRet;
  }

  @override
  bool isUnconditionalJump(InstNode node) {
    return node.instId == X86InstId.kJmp;
  }
}

/// X86 compiler wrapper that owns a builder and exposes compiler-style entry points.
class X86Compiler {
  final X86CodeBuilder _builder;

  X86Compiler._(this._builder);

  factory X86Compiler.create({Environment? env}) {
    return X86Compiler._(X86CodeBuilder.create(env: env));
  }

  /// Access to the underlying builder for instruction emission.
  X86CodeBuilder get builder => _builder;

  /// Current code holder.
  CodeHolder get code => _builder.code;

  /// Configure function frame attributes before finalize/build.
  void configureFrameAttr(FuncFrameAttr attr) {
    _builder.configureFrameAttr(attr);
  }

  /// Finalize the compiler output without allocating executable memory.
  FinalizedCode finalize({FuncFrameAttr? frameAttrHint}) {
    return _builder.finalize(frameAttrHint: frameAttrHint);
  }

  /// Build and allocate executable memory in the given runtime.
  JitFunction build(
    JitRuntime runtime, {
    FuncFrameAttr? frameAttrHint,
    bool useCache = false,
    String? cacheKey,
  }) {
    return _builder.build(
      runtime,
      frameAttrHint: frameAttrHint,
      useCache: useCache,
      cacheKey: cacheKey,
    );
  }
}
