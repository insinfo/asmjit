import '../core/compiler.dart';
import '../core/builder.dart';
import '../core/labels.dart';

import 'x86_inst_db.g.dart'; // generated IDs

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
