import '../core/compiler.dart';
import 'a64_assembler.dart';
import '../core/labels.dart';
import '../core/rapass.dart';
import '../core/environment.dart';
import 'a64_inst_db.g.dart';
import 'a64.dart';
import '../core/reg_type.dart';
import '../core/builder.dart' as ir;
import 'a64_serializer.dart';
import '../core/emitter.dart';

/// AArch64 Instruction Analyzer.
class A64InstructionAnalyzer extends InstructionAnalyzer {
  @override
  bool isJoin(ir.InstNode node) {
    return false; // Basic implementation
  }

  @override
  bool isJump(ir.InstNode node) {
    final id = node.instId;
    return id == A64InstId.kB ||
        id == A64InstId.kBl ||
        id == A64InstId.kBr ||
        id == A64InstId.kBlr ||
        id == A64InstId.kRet ||
        id == A64InstId.kCbz ||
        id == A64InstId.kCbnz ||
        id == A64InstId.kTbz ||
        id == A64InstId.kTbnz;
  }

  @override
  bool isUnconditionalJump(ir.InstNode node) {
    final id = node.instId;
    return id == A64InstId.kB || id == A64InstId.kBr || id == A64InstId.kRet;
  }

  @override
  bool isReturn(ir.InstNode node) {
    return node.instId == A64InstId.kRet;
  }

  @override
  Label? getJumpTarget(ir.InstNode node) {
    // Check operands for label
    if (node.hasNoOperands) return null;
    final op = node.operands[0];
    if (op is ir.LabelOp) {
      return op.label;
    }
    // For CBZ/CBNZ target is usually second operand
    if (node.operands.length > 1 && node.operands.last is ir.LabelOp) {
      return (node.operands.last as ir.LabelOp).label;
    }
    return null;
  }

  @override
  void analyze(ir.BaseNode node, Set<BaseReg> def, Set<BaseReg> use) {
    if (node is! ir.InstNode) return;

    // Very basic analysis for MVP register allocation.
    // 1. Destination is usually operand 0 (Def).
    // 2. Sources are usually operands 1..N (Use).
    // EXCEPTIONS:
    // - STR (Store): Op0 is source (Use), Op1 is address (Use).
    // - CMP (Observe): All operands are Use.

    final id = node.instId;
    final ops = node.operands;

    if (ops.isEmpty) return;

    bool isStore =
        id == A64InstId.kStr || id == A64InstId.kStp || id == A64InstId.kSt1;
    bool isCmp =
        id == A64InstId.kCmp || id == A64InstId.kCmn || id == A64InstId.kTst;

    if (isStore || isCmp) {
      for (final op in ops) {
        if (op is BaseReg) use.add(op);
        if (op is A64Mem) {
          if (op.base != null) use.add(op.base!);
          if (op.index != null) use.add(op.index!);
        }
      }
      return;
    }

    // Default Case: Op0 is Def, rest are Use.
    final op0 = ops[0];
    if (op0 is BaseReg) {
      def.add(op0);
    }

    for (var i = 1; i < ops.length; i++) {
      final op = ops[i];
      if (op is BaseReg) use.add(op);
      if (op is A64Mem) {
        if (op.base != null) use.add(op.base!);
        if (op.index != null) use.add(op.index!);
      }
    }
  }
}

/// AArch64 Compiler.
class A64Compiler extends BaseCompiler {
  @override
  BaseMem newStackSlot(int baseId, int offset, int size) {
    return A64Mem.baseOffset(sp, offset);
  }

  A64Compiler({Environment? env, LabelManager? labelManager})
      : super(env: env, labelManager: labelManager) {
    // addPass(CFGBuilder(this, A64InstructionAnalyzer()));
    addPass(RAPass(this));
  }

  A64Gp newGp(RegType type, [String? name]) {
    final id = newVirtId();
    if (type == RegType.gp32) return A64Gp(id, 32);
    if (type == RegType.gp64) return A64Gp(id, 64);
    return A64Gp(id, 64);
  }

  A64Gp newGp32([String? name]) => newGp(RegType.gp32, name);
  A64Gp newGp64([String? name]) => newGp(RegType.gp64, name);

  // AArch64 usually uses 64-bit pointers
  A64Gp newGpPtr([String? name]) => newGp(RegType.gp64, name);

  A64Vec newVec([String? name]) => A64Vec(newVirtId(), 128);

  // Aliases for typed vectors
  A64Vec newVecB([String? name]) => A64Vec(newVirtId(), 8);
  A64Vec newVecH([String? name]) => A64Vec(newVirtId(), 16);
  A64Vec newVecS([String? name]) => A64Vec(newVirtId(), 32);
  A64Vec newVecD([String? name]) => A64Vec(newVirtId(), 64);
  A64Vec newVecQ([String? name]) => A64Vec(newVirtId(), 128);

  void finalize() {
    runPasses();
  }

  @override
  void serializeToAssembler(BaseEmitter assembler) {
    if (assembler is! A64Assembler) {
      throw ArgumentError('A64Compiler requires A64Assembler');
    }
    final serializer = A64Serializer(assembler as A64Assembler);
    ir.serializeNodes(nodes, serializer);
  }
}
