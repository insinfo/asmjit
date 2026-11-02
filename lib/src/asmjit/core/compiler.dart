/// AsmJit Compiler Infrastructure
///
/// Port of asmjit/core/compiler.h
///
/// Compiler is a high-level code-generation tool that provides register allocation
/// and automatic handling of function calling conventions.

import 'environment.dart';
import 'func.dart';
import 'globals.dart';
import 'labels.dart';
import 'error.dart';
import 'builder.dart';
import 'reg_utils.dart';
import 'arch.dart';
import 'const_pool.dart';
import 'type.dart';
import 'support.dart' as support;
import 'emitter.dart';
import 'raarch.dart';

export 'builder.dart';
export 'emitter.dart';

/// Scope of a constant (`ConstPoolScope`).
enum ConstPoolScope {
  /// Local constant, emitted at the end of the current function.
  local,

  /// Global constant, emitted at the end of the code.
  global,
}

/// Jump annotation used to annotate jumps.
class JumpAnnotation {
  final BaseCompiler compiler;
  final int annotationId;
  final List<int> labelIds = [];

  JumpAnnotation(this.compiler, this.annotationId);

  bool hasLabel(Label label) => hasLabelId(label.id);
  bool hasLabelId(int labelId) => labelIds.contains(labelId);

  AsmJitError addLabel(Label label) => addLabelId(label.id);
  AsmJitError addLabelId(int labelId) {
    labelIds.add(labelId);
    return AsmJitError.ok;
  }
}

/// Jump instruction with [JumpAnnotation].
class JumpNode extends InstNode {
  JumpAnnotation? annotation;

  JumpNode(int instId, List<Operand> operands,
      {int options = 0, this.annotation})
      : super(instId, operands, options: options, type: NodeType.jump);
}

/// Virtual Register Data.
class VirtReg {
  /// Virtual ID.
  final int id;

  /// Operand signature.
  final OperandSignature signature;

  /// Virtual size (in bytes).
  int size;

  /// Alignment (in bytes).
  int alignment;

  /// Type ID.
  final TypeId typeId;

  /// Name (optional).
  String? name;

  /// Internal flags.
  int flags;

  /// Back-reference to RAWorkReg (during RA).
  Object? workReg;

  // Helpers
  bool get isStack => (flags & kIsStack) != 0;

  // Flags constants
  static const int kIsStack = 0x1;

  VirtReg(this.id, this.signature, this.size, this.alignment, this.typeId,
      {this.name, this.flags = 0});
}

/// Function node represents a function used by [BaseCompiler].
class FuncNode extends LabelNode {
  final FuncDetail funcDetail = FuncDetail();
  final FuncFrame funcFrame = FuncFrame();
  LabelNode? exitNode;
  SentinelNode? end;

  /// Arguments mapped to virtual registers.
  /// Each argument index maps to a list of registers (ArgPack in C++).
  List<FuncValuePack>? _argPacks;

  FuncNode([int labelId = Globals.kInvalidId])
      : super(Label(labelId), type: NodeType.func);

  LabelNode? get exitNodeVal => exitNode;

  Label get exitLabel => exitNode!.label;

  SentinelNode? get endNode => end;

  FuncDetail get detail => funcDetail;

  FuncFrame get frame => funcFrame;

  FuncFrameAttributes get attributes =>
      FuncFrameAttributes(attributes: funcFrame.attributes);

  void addAttributes(int attrs) => funcFrame.addAttributes(attrs);

  int get argCount => funcDetail.argCount;

  List<FuncValuePack>? get argPacks => _argPacks;

  bool get hasRet => funcDetail.hasRet();

  FuncValuePack argPack(int argIndex) {
    if (_argPacks == null || argIndex >= _argPacks!.length) {
      throw RangeError.index(argIndex, _argPacks ?? [], "argPacks");
    }
    return _argPacks![argIndex];
  }

  void setArg(int argIndex, int valueIndex, BaseReg virtReg) {
    if (_argPacks == null) return;
    _argPacks![argIndex]
        .assignReg(valueIndex, Reg(regType: virtReg.type, id: virtReg.id));
  }

  // _initArgs removed as it was unused and implemented differently in C++ (via addFunc logic)
}

/// Function return, used by [BaseCompiler].
class FuncRetNode extends InstNode {
  FuncRetNode(List<Operand> operands)
      : super(0 /* kIdAbstract */, operands, type: NodeType.funcRet);
}

/// Function invocation, used by [BaseCompiler] (`InvokeNode`).
///
/// Operand 0 is the call target (an immediate address, a label, a register
/// or a memory operand); the arguments and return values are operand packs
/// (`OperandPack`) that the register allocator assigns to the locations
/// given by the [detail] of the signature.
class InvokeNode extends InstNode {
  final FuncDetail funcDetail = FuncDetail();

  /// Function return value(s) (`_rets`).
  final List<Operand> _rets =
      List<Operand>.filled(Globals.kMaxValuePack, const NoneOperand());

  /// Function arguments (`_args`), one operand pack per argument.
  List<List<Operand>> _args = const [];

  InvokeNode(int instId, List<Operand> operands, {int options = 0})
      : super(instId, operands, options: options, type: NodeType.invoke) {
    flags |= NodeFlags.isRemovable;
  }

  AsmJitError init(FuncSignature signature, Environment env) {
    final err = funcDetail.init(signature, env);
    if (err == AsmJitError.ok) {
      _args = List.generate(
          funcDetail.argCount,
          (_) =>
              List<Operand>.filled(Globals.kMaxValuePack, const NoneOperand()));
    }
    return err;
  }

  FuncDetail get detail => funcDetail;

  Operand get target => operands[0];

  bool get hasRet => funcDetail.hasRet();
  int get argCount => funcDetail.argCount;

  /// `ret(value_index)`.
  Operand ret([int valueIndex = 0]) => _rets[valueIndex];

  /// `arg(arg_index, value_index)`.
  Operand arg(int argIndex, [int valueIndex = 0]) =>
      _args[argIndex][valueIndex];

  /// `set_ret(value_index, reg)`.
  void setRet(int valueIndex, BaseReg reg) => _rets[valueIndex] = reg;

  /// `set_arg(arg_index, reg_or_imm)`: [op] is a register or an [Imm].
  void setArg(int argIndex, Operand op) => _args[argIndex][0] = op;

  /// `set_arg(arg_index, value_index, reg_or_imm)`.
  void setArgValue(int argIndex, int valueIndex, Operand op) =>
      _args[argIndex][valueIndex] = op;
}

/// Basic Block node (Dart specific for now, pending C++ parity research).
/// Represents a block in the CFG.
class BlockNode extends LabelNode {
  final List<BlockNode> predecessors = [];
  final List<BlockNode> successors = [];

  // Liveness analysis sets
  final Set<BaseReg> use = {};
  final Set<BaseReg> def = {};
  final Set<BaseReg> liveIn = {};
  final Set<BaseReg> liveOut = {};

  BlockNode(Label label) : super(label);

  void addSuccessor(BlockNode block) {
    if (!successors.contains(block)) {
      successors.add(block);
      if (!block.predecessors.contains(this)) {
        block.predecessors.add(this);
      }
    }
  }

  void resetLiveness() {
    use.clear();
    def.clear();
    liveIn.clear();
    liveOut.clear();
  }

  @override
  String toString() =>
      'BlockNode(L${label.id}, preds:${predecessors.length}, succs:${successors.length})';

  BaseNode? get lastNode {
    BaseNode? node = this;
    while (node?.next != null && node?.next is! BlockNode) {
      node = node!.next;
    }
    return node;
  }
}

/// Abstract Compiler Pass.
abstract class CompilerPass {
  final BaseCompiler compiler;
  CompilerPass(this.compiler);
  void run(NodeList nodes);
}

/// Interface for instruction analysis.
abstract class InstructionAnalyzer {
  bool isJoin(InstNode node);
  bool isJump(InstNode node);
  bool isUnconditionalJump(InstNode node);
  bool isReturn(InstNode node);
  Label? getJumpTarget(InstNode node);
  void analyze(BaseNode node, Set<BaseReg> def, Set<BaseReg> use);
}

/// BaseCompiler implementation.
class BaseCompiler extends BaseBuilder {
  FuncNode? _func;
  Environment _env;

  /// Stores array of virtual registers.
  final List<VirtReg> _virtRegs = [];

  /// Stores jump annotations.
  final List<JumpAnnotation> _jumpAnnotations = [];

  /// Instruction analyzer of the architecture (set by [CFGBuilder]).
  InstructionAnalyzer? instructionAnalyzer;

  /// Local and global constant pools.
  late final ConstPool? _constPools;

  BaseCompiler({Environment? env, LabelManager? labelManager})
      : _env = env ?? Environment.host(),
        super(labelManager: labelManager ?? LabelManager()) {
    _constPools = ConstPool(this.labelManager!);
  }

  /// Finalizes the compiler (runs passes).
  void finalize() {
    runPasses();
  }

  /// Architecture hooks used by the register allocator ([RAPass]).
  RAArch createRAArch() {
    throw UnimplementedError('createRAArch not implemented for $arch');
  }

  /// Serializes the builder's IR to an assembler.
  void serializeToAssembler(BaseEmitter assembler) {
    throw UnimplementedError(
        "serializeToAssembler not implemented in BaseCompiler");
  }

  Environment get environment => _env;
  Environment get env => _env;
  Arch get arch => _env.arch;

  FuncNode? get func => _func;

  /// Get virtual registers.
  List<VirtReg> get virtRegs => List.unmodifiable(_virtRegs);

  /// The virtual register with the operand id [id] (`virt_reg_by_id()`), or
  /// null if [id] is not a virtual register of this compiler.
  VirtReg? virtRegById(int id) {
    final index = id - Globals.kMinVirtId;
    return index >= 0 && index < _virtRegs.length ? _virtRegs[index] : null;
  }

  /// Sets function argument pack.
  void setArg(int argIndex, BaseReg reg) {
    if (_func == null) throw AsmJitError.invalidState; // Must be in function
    _func!.setArg(argIndex, 0, reg);
  }

  /// Get jump annotations.
  List<JumpAnnotation> get jumpAnnotations =>
      List.unmodifiable(_jumpAnnotations);

  /// Get constant pools.
  ConstPool? get constPools => _constPools;

  /// The local and global constant pools being filled (`_const_pools`).
  final List<ConstPoolNode?> _constPoolNodes = [null, null];

  /// Adds the constant [data] to the pool of [scope] (`_new_const()`) and
  /// returns the pool label and the offset of the constant in it; the
  /// architecture makes the memory operand `[label + offset]`.
  (Label, int) newConstData(ConstPoolScope scope, List<int> data) {
    final pool = _constPoolNodes[scope.index] ??= ConstPoolNode(newLabel());
    return (pool.label, pool.add(data));
  }

  /// `GlobalConstPoolPass`: flushes the global constant pool at the end of
  /// the code.
  void flushGlobalConstPool() {
    final pool = _constPoolNodes[ConstPoolScope.global.index];
    if (pool != null) {
      nodes.append(pool);
      _constPoolNodes[ConstPoolScope.global.index] = null;
    }
  }

  /// internal
  int _virtIdCounter = Globals.kMinVirtId;

  int _newVirtId() {
    // Create a simplified VirtReg for raw ID requests (legacy support)
    // Ideally we shouldn't use this.
    final id = _virtIdCounter++;
    // We must push a placeholder to _virtRegs to keep indices in sync
    _virtRegs.add(VirtReg(id, OperandSignature(0), 0, 0, TypeId.void_));
    return id;
  }

  // Legacy alias for compatibility during porting
  int newVirtId() => _newVirtId();

  VirtReg newVirtReg(TypeId typeId, OperandSignature signature,
      [String? name]) {
    final id = _virtIdCounter++;
    int size = typeId.sizeInBytes;
    // Default alignment based on size
    int alignment = size > 0 ? support.min(size, 64) : 1;
    // Ensure power of 2
    if (!support.isPowerOf2(alignment)) {
      alignment = 1; // Fallback
    }

    final vReg = VirtReg(id, signature, size, alignment, typeId, name: name);
    // Explicitly handle array growth? List does it automatically.
    _virtRegs.add(vReg);
    return vReg;
  }

  /// Allocates a new virtual stack slot.
  ///
  /// Returns the [VirtReg] representing the stack slot.
  /// The caller should create the appropriate Memory Operand (e.g. X86Mem).
  VirtReg createStackVirtReg(int size, int alignment, [String? name]) {
    if (size == 0) throw ArgumentError("Size must be > 0");
    if (!support.isZeroOrPowerOf2(alignment))
      throw ArgumentError("Alignment must be power of 2");

    if (alignment == 0) alignment = 1;
    if (alignment > 64) alignment = 64;

    // Create VirtReg for stack
    // Stack slots have TypeId.void_ usually, or specific if known.
    final vReg = newVirtReg(TypeId.void_, OperandSignature(0), name);
    vReg.size = size;
    vReg.alignment = alignment;
    vReg.flags |= VirtReg.kIsStack;

    return vReg;
  }

  FuncNode newFunc(FuncSignature signature) {
    // As `new_func_node()`, which registers a label for the function node.
    final func = FuncNode(newLabel().id);
    final err = func.funcDetail.init(signature, _env);
    if (err != AsmJitError.ok) {
      throw AsmJitException(err, "Failed to initialize function detail");
    }

    // Initialize frame with details from function
    final frameErr = func.frame.init(func.funcDetail);
    if (frameErr != AsmJitError.ok) {
      throw AsmJitException(frameErr, "Failed to initialize function frame");
    }

    // Initialize arg packs
    func._argPacks = List.generate(func.argCount, (_) => FuncValuePack());

    return func;
  }

  FuncNode addFunc(FuncSignature signature) {
    final func = newFunc(signature);
    return addFuncNode(func);
  }

  /// Adds [func] (`add_func_node()`): the function node, its entry block,
  /// its exit label and its end sentinel; the cursor is left after the entry
  /// block, so the body goes between the entry and the exit label.
  FuncNode addFuncNode(FuncNode func) {
    _func = func;
    addNode(func);

    // Create and add entry block
    final entryBlock = BlockNode(newLabel());
    addNode(entryBlock);

    final exitNode = LabelNode(newLabel());
    final endNode = SentinelNode(SentinelType.funcEnd);
    func.exitNode = exitNode;
    func.end = endNode;

    final prev = cursor;
    addNode(exitNode); // Function exit label.
    addNode(endNode); // Function end sentinel.
    setCursor(prev);
    return func;
  }

  void ret([List<Operand> operands = const []]) {
    addNode(FuncRetNode(operands));
  }

  @override
  void bind(Label label) {
    addNode(BlockNode(label));
  }

  final List<CompilerPass> _passes = [];

  /// Adds a jump to [target] (a label, register or memory operand) whose
  /// possible targets are [annotation] (`emit_annotated_jump()`).
  JumpNode emitAnnotatedJump(int instId, Operand target,
      [JumpAnnotation? annotation]) {
    final node =
        JumpNode(instId, [target], options: instOptions, annotation: annotation)
          ..extraReg = extraReg;
    instOptions = 0;
    extraReg = null;
    addNode(node);
    return node;
  }

  void addPass(CompilerPass pass) {
    _passes.add(pass);
  }

  void runPasses() {
    for (final pass in _passes) {
      pass.run(nodes);
    }
    flushGlobalConstPool();
  }

  /// Ends the current function (`end_func()`); the cursor moves to its end
  /// sentinel.
  AsmJitError endFunc() {
    final func = _func;
    if (func == null) return AsmJitError.invalidState;

    // Upstream emits the epilog once, at the exit label, so a function whose
    // body can fall through its end returns there; the port emits the epilog
    // at each return, so such a function gets an explicit return.
    final exitNode = func.exitNode!;
    final last = exitNode.prev;
    final analyzer = instructionAnalyzer;
    final fallsThrough = !(last is FuncRetNode ||
        (last is InstNode &&
            analyzer != null &&
            (analyzer.isUnconditionalJump(last) || analyzer.isReturn(last))));
    if (fallsThrough) nodes.insertBefore(FuncRetNode(const []), exitNode);

    // Add the local constant pool at the end of the function (if exists).
    final localPool = _constPoolNodes[ConstPoolScope.local.index];
    if (localPool != null) {
      nodes.insertBefore(localPool, func.end!);
      _constPoolNodes[ConstPoolScope.local.index] = null;
    }

    _func = null;
    setCursor(func.end);
    return AsmJitError.ok;
  }

  /// Create new FuncRetNode.
  FuncRetNode newFuncRetNode(Operand o0, Operand o1) {
    return FuncRetNode([o0, o1]);
  }

  /// Add FuncRetNode to instruction stream.
  FuncRetNode addFuncRetNode(Operand o0, Operand o1) {
    final node = newFuncRetNode(o0, o1);
    addNode(node);
    return node;
  }

  /// Add return instruction.
  AsmJitError addRet(Operand o0, Operand o1) {
    addFuncRetNode(o0, o1);
    return AsmJitError.ok;
  }

  /// Create new InvokeNode (`new_invoke_node()`).
  InvokeNode newInvokeNode(
      int instId, Operand target, FuncSignature signature) {
    final node = InvokeNode(instId, [target]);
    final err = node.init(signature, _env);
    if (err != AsmJitError.ok) {
      throw AsmJitException(err, "Failed to initialize invoke node");
    }
    return node;
  }

  /// Add InvokeNode to instruction stream.
  InvokeNode addInvokeNode(
      int instId, Operand target, FuncSignature signature) {
    final node = newInvokeNode(instId, target, signature);
    addNode(node);
    return node;
  }

  /// Create new jump annotation.
  JumpAnnotation newJumpAnnotation() {
    final annotation = JumpAnnotation(this, _jumpAnnotations.length);
    _jumpAnnotations.add(annotation);
    return annotation;
  }
  // ===========================================================================
  // RA Emission Interface
  // ===========================================================================

  void emitMove(Operand dst, Operand src) {
    throw UnimplementedError('emitMove not implemented for this architecture');
  }

  void emitSwap(Operand a, Operand b) {
    throw UnimplementedError('emitSwap not implemented for this architecture');
  }

  void emitLoad(Operand dst, Operand src) {
    // Usually same as move, but semantic difference for RA
    emitMove(dst, src);
  }

  void emitSave(Operand dst, Operand src) {
    // Usually same as move
    emitMove(dst, src);
  }

  BaseMem newStackSlot(int baseId, int offset, int size) {
    throw UnimplementedError();
  }
}

/// CFG Builder Pass.
class CFGBuilder extends CompilerPass {
  final InstructionAnalyzer analyzer;

  CFGBuilder(BaseCompiler compiler, this.analyzer) : super(compiler) {
    compiler.instructionAnalyzer = analyzer;
  }

  @override
  void run(NodeList nodes) {
    _resetGraph(nodes);
    _buildBlocks(nodes);
    _linkBlocks(nodes);
  }

  void _resetGraph(NodeList nodes) {
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        node.predecessors.clear();
        node.successors.clear();
      }
    }
  }

  /// Blocks start at [BlockNode]s (bound labels). As in upstream
  /// `RACFGBuilderT`, a jump also ends its block: the code after a jump that
  /// is not already a block gets a new [BlockNode], so the register
  /// assignment at the jump is the exit assignment of its block (the state
  /// both edges see).
  void _buildBlocks(NodeList nodes) {
    compiler.instructionAnalyzer = analyzer;
    for (final node in nodes.nodes.toList()) {
      if (node is! InstNode || node is FuncRetNode) continue;
      // Jumps to a label and jumps through a register or memory operand
      // (jump tables) end the block.
      if (!analyzer.isJump(node) ||
          (analyzer.getJumpTarget(node) == null &&
              !analyzer.isUnconditionalJump(node))) {
        continue;
      }
      final next = node.next;
      // A BlockNode (or the function's exit label) already starts a block.
      if (next == null || next is LabelNode || next is SentinelNode) continue;
      nodes.insertAfter(BlockNode(compiler.newLabel()), node);
    }
  }

  void _linkBlocks(NodeList nodes) {
    final labelMap = <int, BlockNode>{};
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        labelMap[node.label.id] = node;
      }
    }

    BlockNode? currentBlock;
    // Blocks of the current function and the blocks ending with a jump
    // whose targets are unknown (`blocks_with_unknown_jumps`).
    var funcBlocks = <BlockNode>[];
    final unknownJumps = <(BlockNode, List<BlockNode>)>[];
    for (final node in nodes.nodes) {
      if (node is FuncNode) {
        funcBlocks = [];
      } else if (node is BlockNode) {
        currentBlock = node;
        funcBlocks.add(node);
      } else if (node is InstNode && currentBlock != null) {
        // An unfollowed jump (`kUnfollow`) has no successors.
        if (analyzer.isJump(node) &&
            (node.options & kInstOptionUnfollow) == 0) {
          final target = analyzer.getJumpTarget(node);
          if (target != null) {
            final targetBlock = labelMap[target.id];
            if (targetBlock != null) {
              currentBlock.addSuccessor(targetBlock);
            }
          } else if (analyzer.isUnconditionalJump(node) &&
              !analyzer.isReturn(node)) {
            // A jump through a register or memory operand: its annotation
            // lists the targets, otherwise it can reach any block.
            final annotation = node is JumpNode ? node.annotation : null;
            if (annotation != null) {
              for (final id in annotation.labelIds) {
                final targetBlock = labelMap[id];
                if (targetBlock != null &&
                    !currentBlock.successors.contains(targetBlock)) {
                  currentBlock.addSuccessor(targetBlock);
                }
              }
            } else {
              unknownJumps.add((currentBlock, funcBlocks));
            }
          }
        }
        // A function return (`FuncRetNode`) ends the flow like `ret`.
        if (!analyzer.isUnconditionalJump(node) &&
            !analyzer.isReturn(node) &&
            node is! FuncRetNode) {
          _addFallthroughSuccessor(currentBlock, node, labelMap);
        }
      }
    }

    // `handle_block_with_unknown_jump()`: every block of the function except
    // the entry block (it holds the prolog) and the consecutive block.
    for (final (block, blocks) in unknownJumps) {
      final consecutive = _nextBlockAfter(block);
      for (final candidate in blocks.skip(1)) {
        if (identical(candidate, consecutive) ||
            block.successors.contains(candidate)) {
          continue;
        }
        block.addSuccessor(candidate);
      }
    }
  }

  static BlockNode? _nextBlockAfter(BlockNode block) {
    var next = block.next;
    while (next != null && next is! BlockNode) {
      if (next is SentinelNode) return null;
      next = next.next;
    }
    return next as BlockNode?;
  }

  void _addFallthroughSuccessor(
      BlockNode current, BaseNode node, Map<int, BlockNode> labelMap) {
    var next = node.next;
    while (next != null) {
      if (next is BlockNode) {
        current.addSuccessor(next);
        break;
      }
      // The flow never falls through the end of a function.
      if (next is SentinelNode && next.sentinelType == SentinelType.funcEnd) {
        break;
      }
      next = next.next;
    }
  }
}

/// Liveness Analysis Pass.
class LivenessAnalysis extends CompilerPass {
  final CFGBuilder cfgBuilder;

  LivenessAnalysis(BaseCompiler compiler, this.cfgBuilder) : super(compiler);

  @override
  void run(NodeList nodes) {
    cfgBuilder.run(nodes);

    final blocks = <BlockNode>[];
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        node.resetLiveness();
        blocks.add(node);
      }
    }

    BlockNode? current;
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        current = node;
      } else if (node is InstNode && current != null) {
        _accumulateDefUse(cfgBuilder.analyzer, current, node);
      }
    }

    bool changed = true;
    while (changed) {
      changed = false;
      for (final block in blocks.reversed) {
        final liveOut = <BaseReg>{};
        for (final succ in block.successors) {
          liveOut.addAll(succ.liveIn);
        }

        final liveIn = <BaseReg>{}
          ..addAll(block.use)
          ..addAll(liveOut.where((r) => !block.def.contains(r)));

        if (!_setEquals(block.liveOut, liveOut)) {
          block.liveOut.clear();
          block.liveOut.addAll(liveOut);
          changed = true;
        }
        if (!_setEquals(block.liveIn, liveIn)) {
          block.liveIn.clear();
          block.liveIn.addAll(liveIn);
          changed = true;
        }
      }
    }
  }

  void _accumulateDefUse(
      InstructionAnalyzer analyzer, BlockNode block, InstNode inst) {
    final instDef = <BaseReg>{};
    final instUse = <BaseReg>{};
    analyzer.analyze(inst, instDef, instUse);

    for (final u in instUse) {
      if (!block.def.contains(u)) {
        block.use.add(u);
      }
    }
    for (final d in instDef) {
      block.def.add(d);
    }
  }

  bool _setEquals(Set<BaseReg> a, Set<BaseReg> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
