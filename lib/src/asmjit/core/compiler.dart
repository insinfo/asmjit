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
import 'operand.dart';
import 'error.dart';
import 'builder.dart';
import 'reg_utils.dart';

export 'builder.dart';

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

  bool get hasAnnotation => annotation != null;
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

  BaseCompiler();

  FuncNode? get func => _func;

  FuncNode newFunc(FuncSignature signature) {
    final func = FuncNode();
    // Initialize func detail with signature...
    // Requires Environment. Using host for now or need to pass it.
    // C++ add_func uses internal state.
    // We should implement fully later.
    return func;
  }

  FuncNode addFunc(FuncNode func) {
    addNode(func);
    // Add logic to insert ExitLabel and EndFunc
    final exitNode = LabelNode(newLabel());
    final endNode = SentinelNode(SentinelType.funcEnd);

    func.exitNode = exitNode;
    func.end = endNode;

    _func = func;
    return func;
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
