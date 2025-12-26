/// AsmJit Compiler Infrastructure
///
/// Provides passes for Control Flow Graph (CFG) construction and analysis.

import 'builder.dart';
import 'labels.dart';
import 'operand.dart';

/// A compiler pass that operates on the instruction stream.
abstract class CompilerPass {
  /// Run the pass on the given node list.
  void run(NodeList nodes);
}

/// Interface for instruction analysis required by CFG builder.
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
}

/// Builds the Control Flow Graph (CFG) by linking BlockNodes.
///
/// Iterates through the node list, identifies Basic Blocks, and
/// links them via predecessors and successors.
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
    // Clear existing connections
    var node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        node.predecessors.clear();
        node.successors.clear();
      }
      node = node.next;
    }
  }

  void _buildBlocks(NodeList nodes) {
    // In AsmJit Dart, we iterate and ensure BlockNodes exist where needed.
    // For now, we assume the user (or a previous pass) inserted BlockNodes.
    // We just map Labels to Blocks.
  }

  void _linkBlocks(NodeList nodes) {
    BlockNode? currentBlock;

    // Map of Label ID to BlockNode
    final labelMap = <int, BlockNode>{};

    // First pass: Index blocks
    var node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        labelMap[node.label.id] = node;
      }
      node = node.next;
    }

    // Second pass: Link
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

        // Handle Fallthrough (for conditional jumps or normal instructions)
        if (!analyzer.isUnconditionalJump(node) && !analyzer.isReturn(node)) {
          _addFallthroughSuccessor(currentBlock, node, labelMap);
        }
      }
      node = node.next;
    }

    // Handle fallthrough for non-jump instructions at end of block
    // This is tricky if blocks are not contiguous.
    // Usually valid code has jumps or fallthrough.
  }

  void _addFallthroughSuccessor(
      BlockNode current, BaseNode node, Map<int, BlockNode> labelMap) {
    // Look ahead for the next block
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
    // Ensure CFG is up to date
    _cfgBuilder.run(nodes);

    // 1) Collect BlockNodes and reset liveness info.
    final blocks = <BlockNode>[];
    var node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        node.resetLiveness();
        blocks.add(node);
      }
      node = node.next;
    }

    // 2) Compute Def/Use sets per block by scanning instructions inside it.
    BlockNode? current;
    node = nodes.first;
    while (node != null) {
      if (node is BlockNode) {
        current = node;
      } else if (node is InstNode && current != null) {
        _accumulateDefUse(current, node);
      }
      node = node.next;
    }

    // 3) Iterate to fixed point for LiveIn/LiveOut.
    var changed = true;
    while (changed) {
      changed = false;
      for (final block in blocks.reversed) {
        final liveOut = <BaseReg>{};
        for (final succ in block.successors) {
          liveOut.addAll(succ.liveIn);
        }

        final liveIn = <BaseReg>{}..addAll(block.use)
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

  void _accumulateDefUse(BlockNode block, InstNode inst) {
    if (inst.operands.isEmpty) return;

    // Heuristic: first reg operand is treated as def (dest); others as use.
    bool destHandled = false;
    for (final op in inst.operands) {
      if (op is RegOperand) {
        final reg = op.reg;
        if (!reg.isPhysical && !destHandled) {
          block.def.add(reg);
          destHandled = true;
          continue;
        }
        if (!reg.isPhysical) block.use.add(reg);
      } else if (op is MemOperand) {
        _scanMemForUse(block, op);
      }
    }
  }

  void _scanMemForUse(BlockNode block, MemOperand memOp) {
    final mem = memOp.mem;
    if (mem is BaseMem) {
      final base = mem.base;
      final index = mem.index;
      if (base is BaseReg && !base.isPhysical) block.use.add(base);
      if (index is BaseReg && !index.isPhysical) block.use.add(index);
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
