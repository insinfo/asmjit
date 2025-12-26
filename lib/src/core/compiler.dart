/// AsmJit Compiler Infrastructure
///
/// Provides passes for Control Flow Graph (CFG) construction and analysis.

import 'builder.dart';
import 'labels.dart';

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

    // TODO: Implement liveness computation
    // 1. Initialize bitsets for LiveIn/LiveOut/Def/Use
    // 2. Compute Def/Use sets for each block (scan instructions)
    // 3. Iterate backwards to compute LiveIn/LiveOut until convergence
  }
}
