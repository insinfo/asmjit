import '../core/compiler.dart';
import '../core/builder.dart';
import '../core/code_builder.dart';
import '../core/code_holder.dart';
import '../core/emitter.dart';
import '../core/environment.dart';
import '../core/formatter.dart';
import '../core/labels.dart';
import '../core/operand.dart';
import '../core/regalloc.dart';
import '../runtime/jit_runtime.dart';

import 'x86_inst_db.g.dart'; // generated IDs
import 'x86_assembler.dart';
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

/// SIMD vector widths used by the compiler.
enum VecWidth {
  k128(16),
  k256(32),
  k512(64);

  final int bytes;
  const VecWidth(this.bytes);
}

/// X86 compiler wrapper that owns a builder and exposes compiler-style entry points.
class X86Compiler {
  final X86CodeBuilder _builder;
  VecWidth _vecWidth = VecWidth.k128;

  X86Compiler._(this._builder);

  factory X86Compiler.create({Environment? env}) {
    return X86Compiler._(X86CodeBuilder.create(env: env));
  }

  /// Access to the underlying builder for instruction emission.
  X86CodeBuilder get builder => _builder;

  /// Current code holder.
  CodeHolder get code => _builder.code;

  /// Active SIMD vector width used by new_vec().
  VecWidth get vecWidth => _vecWidth;
  set vecWidth(VecWidth width) => _vecWidth = width;

  /// Adds a function with the given signature.
  FuncNode addFunc(FuncSignature signature, {String name = 'func'}) {
    return _builder.addFunc(signature, name: name);
  }

  /// Ends the current function.
  void endFunc() => _builder.endFunc();

  /// Emits a raw instruction by ID.
  void emit(int instId,
      [Object? op1, Object? op2, Object? op3, Object? op4, Object? op5]) {
    final ops = <Object>[];
    if (op1 != null) ops.add(op1);
    if (op2 != null) ops.add(op2);
    if (op3 != null) ops.add(op3);
    if (op4 != null) ops.add(op4);
    if (op5 != null) ops.add(op5);
    _builder.emitInst(instId, ops);
  }

  /// Emits an invocation node (call with signature).
  InvokeNode invoke(Object target, FuncSignature signature,
      {List<Object> args = const [], BaseReg? ret}) {
    return _builder.invoke(target, signature, args: args, ret: ret);
  }

  /// Creates a new 32-bit GP virtual register.
  VirtReg newGp32([String? name]) {
    return _builder.newGpReg(size: 4);
  }

  /// Creates a new 64-bit GP virtual register.
  VirtReg newGp64([String? name]) {
    return _builder.newGpReg(size: 8);
  }

  /// Creates a new pointer-size GP virtual register.
  VirtReg newGpz([String? name]) {
    return _builder.newGpReg(size: _builder.is64Bit ? 8 : 4);
  }

  /// Creates a new vector register using the active SIMD width.
  VirtReg newVec([String? name]) => newVecWithWidth(_vecWidth, name);

  /// Creates a new vector register with the specified SIMD width.
  VirtReg newVecWithWidth(VecWidth width, [String? name]) {
    switch (width) {
      case VecWidth.k128:
        return _builder.newXmmReg();
      case VecWidth.k256:
        return _builder.newYmmReg();
      case VecWidth.k512:
        return _builder.newZmmReg();
    }
  }

  /// Creates a new 128-bit vector register.
  VirtReg newVec128([String? name]) => _builder.newXmmReg();

  /// Creates a new 256-bit vector register.
  VirtReg newVec256([String? name]) => _builder.newYmmReg();

  /// Creates a new 512-bit vector register.
  VirtReg newVec512([String? name]) => _builder.newZmmReg();

  /// Creates a new 128-bit vector register (float64x2 signature).
  VirtReg newVec128F64x2([String? name]) => _builder.newXmmReg();

  /// Creates a list of vector registers.
  List<VirtReg> newVecArray(int count, VecWidth width, [String? name]) {
    return List<VirtReg>.generate(count, (_) => newVecWithWidth(width));
  }

  /// Creates a list of 128-bit vector registers.
  List<VirtReg> newVec128Array(int count, [String? name]) {
    return List<VirtReg>.generate(count, (_) => newVec128());
  }

  /// Creates a list of 256-bit vector registers.
  List<VirtReg> newVec256Array(int count, [String? name]) {
    return List<VirtReg>.generate(count, (_) => newVec256());
  }

  /// Creates a list of 512-bit vector registers.
  List<VirtReg> newVec512Array(int count, [String? name]) {
    return List<VirtReg>.generate(count, (_) => newVec512());
  }

  /// Configure function frame attributes before finalize/build.
  void configureFrameAttr(FuncFrameAttr attr) {
    _builder.configureFrameAttr(attr);
  }

  /// Sets a logger for diagnostic output.
  void setLogger(BaseLogger logger) {
    _builder.code.setLogger(logger);
  }

  /// Adds encoding options (placeholder).
  void addEncodingOptions(int options) {
    _builder.encodingOptions |= options;
  }

  /// Adds diagnostic options (placeholder).
  void addDiagnosticOptions(int options) {
    _builder.diagnosticOptions |= options;
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

/// IR compiler backend that lowers Func/Invoke nodes into assembler output.
///
/// This allows using `builder.dart` IR with the same pipeline as X86CodeBuilder.
class X86IrCompiler {
  final Environment env;
  final int encodingOptions;
  final int diagnosticOptions;

  X86IrCompiler({
    Environment? env,
    this.encodingOptions = EncodingOptions.kNone,
    this.diagnosticOptions = DiagnosticOptions.kNone,
  }) : env = env ?? Environment.host();

  /// Finalizes code for the given [nodes] in a fresh [CodeHolder].
  FinalizedCode finalize(NodeList nodes, {FuncFrameAttr? frameAttrHint}) {
    final code = CodeHolder(env: env);
    final asm = X86Assembler(code);
    emit(nodes, asm, frameAttrHint: frameAttrHint);
    return code.finalize();
  }

  /// Builds and allocates executable memory for [nodes].
  JitFunction build(
    NodeList nodes,
    JitRuntime runtime, {
    FuncFrameAttr? frameAttrHint,
    bool useCache = false,
    String? cacheKey,
  }) {
    final code = CodeHolder(env: env);
    final asm = X86Assembler(code);
    emit(nodes, asm, frameAttrHint: frameAttrHint);
    if (useCache) {
      return runtime.addCached(code, key: cacheKey);
    }
    return runtime.add(code);
  }

  /// Emits [nodes] to the given [asm] using the full pipeline.
  void emit(NodeList nodes, X86Assembler asm,
      {FuncFrameAttr? frameAttrHint}) {
    _ensureLabels(nodes, asm.code);

    final analyzer = X86InstructionAnalyzer();
    final cfgBuilder = CFGBuilder(analyzer);
    final liveness = LivenessAnalysis(cfgBuilder);

    while (nodes.isNotEmpty) {
      final segment = _extractFuncSegment(nodes);
      if (segment.isEmpty) break;

      // Compute CFG/liveness for the current function segment.
      liveness.run(segment);

      final builder = X86CodeBuilder.forCodeHolder(asm.code)
        ..encodingOptions = encodingOptions
        ..diagnosticOptions = diagnosticOptions;

      builder.importNodes(segment);
      builder.emitToAssembler(asm, frameAttrHint: frameAttrHint);
    }
  }

  /// Emits nodes from a [BaseBuilder] instance.
  void emitBuilder(BaseBuilder builder, X86Assembler asm,
      {FuncFrameAttr? frameAttrHint}) {
    emit(builder.nodes, asm, frameAttrHint: frameAttrHint);
  }

  void _ensureLabels(NodeList nodes, CodeHolder code) {
    var maxId = -1;
    for (final node in nodes.nodes) {
      if (node is LabelNode) {
        if (node.label.id > maxId) maxId = node.label.id;
      } else if (node is InstNode) {
        for (final op in node.operands) {
          if (op is LabelOperand) {
            if (op.label.id > maxId) maxId = op.label.id;
          }
        }
      } else if (node is InvokeNode) {
        final target = node.target;
        if (target is Label) {
          if (target.id > maxId) maxId = target.id;
        } else if (target is LabelOperand) {
          if (target.label.id > maxId) maxId = target.label.id;
        }
      }
    }

    if (maxId >= 0) {
      code.ensureLabelCount(maxId + 1);
    }
  }

  NodeList _extractFuncSegment(NodeList nodes) {
    final segment = NodeList();
    var node = nodes.first;
    var started = false;

    while (node != null) {
      final next = node.next;
      if (node is FuncNode && started) {
        break;
      }
      started = true;
      nodes.remove(node);
      segment.append(node);
      node = next;
    }

    return segment;
  }
}
