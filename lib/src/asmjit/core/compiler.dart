/// AsmJit Compiler Infrastructure
///
/// Provides passes for Control Flow Graph (CFG) construction and analysis.

import 'builder.dart';
import 'labels.dart';
import 'operand.dart';

export 'builder.dart'
    show BaseBuilder, FuncNode, BlockNode, InstNode, LabelNode,
        RegOperand, ImmOperand, MemOperand, FuncRetNode, InvokeNode;

/// A compiler pass that operates on the instruction stream.
abstract class CompilerPass {
  /// Run the pass on the given node list.
  void run(NodeList nodes);
}

/// Interface for instruction analysis required by CFG builder and Liveness Analysis.
abstract class InstructionAnalyzer {
  /// Is the instruction a control flow change?
  bool isJoin(InstNode node); // Label/Block

  /// Is the instruction a jump/branch?
  bool isJump(InstNode node);

  /// Is the instruction an unconditional jump?
  bool isUnconditionalJump(InstNode node);

  /// Is the instruction a return?
  bool isReturn(InstNode node);

  /// Get the target label of a jump (if direct).
  Label? getJumpTarget(InstNode node);

  /// Analyze instruction register usage (Def/Use).
  void analyze(BaseNode node, Set<BaseReg> def, Set<BaseReg> use);
}

/// Builds the Control Flow Graph (CFG) by linking BlockNodes.
///
/// Iterates through the node list, ensures blocks exist for labels,
/// and links them via predecessors and successors.
class CFGBuilder extends CompilerPass {
  final InstructionAnalyzer analyzer;

  CFGBuilder(this.analyzer);

  @override
  void run(NodeList nodes) {
    _resetGraph(nodes);
    _buildBlocks(nodes);
    _linkBlocks(nodes);
  }

  void _resetGraph(NodeList nodes) {
    var node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        node.predecessors.clear();
        node.successors.clear();
        // Custom fields reset if necessary
      }
      node = node.next;
    }
  }

  void _buildBlocks(NodeList nodes) {
    // Pass 1: Ensure BlockNodes exist for all Labels used as jump targets or block entries.
    // In strict mode, we expect BlockNodes to be emitted by the code builder.
    // If we were to promote LabelNodes, we'd do it here, but creating new nodes in-place is complex.
    // We assume the upstream builder uses 'block()' for key labels.
  }

  void _linkBlocks(NodeList nodes) {
    // Map of Label ID to BlockNode
    final labelMap = <int, BlockNode>{};

    var node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        labelMap[node.label.id] = node;
      }
      node = node.next;
    }

    BlockNode? currentBlock;
    node = nodes.first;
    while (node != null) {
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
      node = node.next;
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
/// Computes live-in and live-out sets for each block.
class LivenessAnalysis extends CompilerPass {
  final CFGBuilder _cfgBuilder;

  LivenessAnalysis(this._cfgBuilder);

  @override
  void run(NodeList nodes) {
    _cfgBuilder.run(nodes);

    final blocks = <BlockNode>[];
    var node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        node.resetLiveness();
        blocks.add(node);
      }
      node = node.next;
    }

    BlockNode? current;
    node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        current = node;
      } else if (node is InstNode && current != null) {
        // Use the analyzer from CFGBuilder
        _accumulateDefUse(_cfgBuilder.analyzer, current, node);
      }
      node = node.next;
    }

    var changed = true;
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
          block.liveOut
            ..clear()
            ..addAll(liveOut);
          changed = true;
        }
        if (!_setEquals(block.liveIn, liveIn)) {
          block.liveIn
            ..clear()
            ..addAll(liveIn);
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
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }
}
