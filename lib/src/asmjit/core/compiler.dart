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

export 'builder.dart';
export 'emitter.dart';

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

/// Function invocation, used by [BaseCompiler].
class InvokeNode extends InstNode {
  final FuncDetail funcDetail = FuncDetail();

  /// Function return value(s).
  final FuncValuePack rets = FuncValuePack();

  /// Function arguments.
  List<FuncValuePack>? _argPacks;

  InvokeNode(int instId, List<Operand> operands, {int options = 0})
      : super(instId, operands, options: options, type: NodeType.invoke) {
    flags |= NodeFlags.isRemovable;
  }

  AsmJitError init(FuncSignature signature, Environment env) {
    final err = funcDetail.init(signature, env);
    if (err == AsmJitError.ok) {
      if (funcDetail.argCount > 0) {
        _argPacks = List.generate(funcDetail.argCount, (_) => FuncValuePack());
      }
    }
    return err;
  }

  FuncDetail get detail => funcDetail;

  Operand get target => operands[0];

  bool get hasRet => funcDetail.hasRet();
  int get argCount => funcDetail.argCount;

  FuncValuePack get retPack => rets;

  FuncValuePack? argPack(int index) => _argPacks?[index];
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

  /// Sets function argument pack.
  void setArg(int argIndex, BaseReg reg) {
    if (_func == null) throw AsmJitError.invalidState; // Must be in function
    // For now simple implementation: just mapping.
    // In full implementation, this updates FuncNode._argPacks.
    // TODO: Implement full FuncValuePack logic
    // We need to map argument index to virtual register.
    // For now, ignoring or using rudimentary mapping if available.
  }

  /// Get jump annotations.
  List<JumpAnnotation> get jumpAnnotations =>
      List.unmodifiable(_jumpAnnotations);

  /// Get constant pools.
  ConstPool? get constPools => _constPools;

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
    final func = FuncNode();
    final err = func.funcDetail.init(signature, _env);
    if (err != AsmJitError.ok) {
      throw AsmJitException(err, "Failed to initialize function detail");
    }

    // Initialize frame with details from function
    final frameErr = func.frame.init(func.funcDetail);
    if (frameErr != AsmJitError.ok) {
      throw AsmJitException(frameErr, "Failed to initialize function frame");
    }

    return func;
  }

  FuncNode addFunc(FuncSignature signature) {
    final func = newFunc(signature);
    return addFuncNode(func);
  }

  FuncNode addFuncNode(FuncNode func) {
    addNode(func);

    // Create and add entry block
    final entryBlock = BlockNode(newLabel());
    addNode(entryBlock);

    // Add logic to insert ExitLabel and EndFunc
    final exitNode = LabelNode(newLabel());
    final endNode = SentinelNode(SentinelType.funcEnd);

    func.exitNode = exitNode;
    func.end = endNode;

    _func = func;
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

  void addPass(CompilerPass pass) {
    _passes.add(pass);
  }

  void runPasses() {
    for (final pass in _passes) {
      pass.run(nodes);
    }
  }

  AsmJitError endFunc() {
    if (_func == null) return AsmJitError.invalidState;

    // Add exit label
    addNode(_func!.exitNode!);
    // Add sentinel
    addNode(_func!.end!);

    _func = null;
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

  /// Create new InvokeNode.
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

  CFGBuilder(BaseCompiler compiler, this.analyzer) : super(compiler);

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

  void _buildBlocks(NodeList nodes) {
    // In C++, blocks are usually built by identifying labels and jumps.
    // If we rely on BlockNode being present (as labels), we iterate labels.
    // If BlockNodes are constructed here, we'd need to replace LabelNodes with BlockNodes.
    // For now assuming BlockNodes are already in the stream (emitted by user) or we treat LabelNodes as Blocks?
    // The previous Dart implementation assumed BlockNodes.
  }

  void _linkBlocks(NodeList nodes) {
    final labelMap = <int, BlockNode>{};
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        labelMap[node.label.id] = node;
      }
    }

    BlockNode? currentBlock;
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        currentBlock = node;
      } else if (node is InstNode && currentBlock != null) {
        if (analyzer.isJump(node)) {
          final target = analyzer.getJumpTarget(node);
          if (target != null) {
            final targetBlock = labelMap[target.id];
            if (targetBlock != null) {
              currentBlock.addSuccessor(targetBlock);
            }
          }
        }
        if (!analyzer.isUnconditionalJump(node) && !analyzer.isReturn(node)) {
          _addFallthroughSuccessor(currentBlock, node, labelMap);
        }
      }
    }
  }

  void _addFallthroughSuccessor(
      BlockNode current, BaseNode node, Map<int, BlockNode> labelMap) {
    var next = node.next;
    while (next != null) {
      if (next is BlockNode) {
        current.addSuccessor(next);
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
