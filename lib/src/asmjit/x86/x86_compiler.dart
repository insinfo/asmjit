import '../core/compiler.dart';
import '../core/builder.dart';
import '../core/operand.dart';
import '../core/labels.dart';
import 'x86_inst_db.g.dart'; // For instructions

/// X86 Compiler.
class X86Compiler extends BaseCompiler {
  X86Compiler() : super();

  // ===========================================================================
  // Basic instructions
  // ===========================================================================

  void ret() => inst(X86InstId.kRet, []);
  void retImm(int imm16) => inst(X86InstId.kRet, [Imm(imm16)]);
  void nop() => inst(X86InstId.kNop, []);
  void int3() => inst(X86InstId.kInt3, []);

  // ===========================================================================
  // MOV / Data Transfer
  // ===========================================================================

  void mov(Operand dst, Operand src) => inst(X86InstId.kMov, [dst, src]);
  void movsx(Operand dst, Operand src) => inst(X86InstId.kMovsx, [dst, src]);
  void movzx(Operand dst, Operand src) => inst(X86InstId.kMovzx, [dst, src]);
  void lea(Operand dst, Operand src) => inst(X86InstId.kLea, [dst, src]);
  void xchg(Operand dst, Operand src) => inst(X86InstId.kXchg, [dst, src]);

  // ===========================================================================
  // Arithmetic
  // ===========================================================================

  void add(Operand dst, Operand src) => inst(X86InstId.kAdd, [dst, src]);
  void sub(Operand dst, Operand src) => inst(X86InstId.kSub, [dst, src]);
  void mul(Operand src) =>
      inst(X86InstId.kMul, [src]); // Unsigned multiply (ax/dx implied)
  void imul(Operand dst, Operand src) => inst(X86InstId.kImul, [dst, src]);
  void div(Operand src) => inst(X86InstId.kDiv, [src]);
  void idiv(Operand src) => inst(X86InstId.kIdiv, [src]);

  void inc(Operand dst) => inst(X86InstId.kInc, [dst]);
  void dec(Operand dst) => inst(X86InstId.kDec, [dst]);
  void neg(Operand dst) => inst(X86InstId.kNeg, [dst]);
  void not(Operand dst) => inst(X86InstId.kNot, [dst]);

  // ===========================================================================
  // Logic
  // ===========================================================================

  void and_(Operand dst, Operand src) => inst(X86InstId.kAnd, [dst, src]);
  void or_(Operand dst, Operand src) => inst(X86InstId.kOr, [dst, src]);
  void xor_(Operand dst, Operand src) => inst(X86InstId.kXor, [dst, src]);

  // ===========================================================================
  // Comparison & Test
  // ===========================================================================

  void cmp(Operand dst, Operand src) => inst(X86InstId.kCmp, [dst, src]);
  void test(Operand dst, Operand src) => inst(X86InstId.kTest, [dst, src]);

  // ===========================================================================
  // Stack
  // ===========================================================================

  void push(Operand src) => inst(X86InstId.kPush, [src]);
  void pop(Operand dst) => inst(X86InstId.kPop, [dst]);

  // ===========================================================================
  // Control Flow
  // ===========================================================================

  void jmp(Label target) => inst(X86InstId.kJmp, [LabelOp(target)]);
  void call(Label target) => inst(X86InstId.kCall, [LabelOp(target)]);

  void je(Label target) => inst(X86InstId.kJz, [LabelOp(target)]);
  void jz(Label target) => inst(X86InstId.kJz, [LabelOp(target)]);
  void jne(Label target) => inst(X86InstId.kJnz, [LabelOp(target)]);
  void jnz(Label target) => inst(X86InstId.kJnz, [LabelOp(target)]);

  void jl(Label target) => inst(X86InstId.kJl, [LabelOp(target)]);
  void jle(Label target) => inst(X86InstId.kJle, [LabelOp(target)]);
  void jg(Label target) => inst(X86InstId.kJnle, [LabelOp(target)]);
  void jge(Label target) => inst(X86InstId.kJnl, [LabelOp(target)]);

  void jb(Label target) => inst(X86InstId.kJb, [LabelOp(target)]);
  void jbe(Label target) => inst(X86InstId.kJbe, [LabelOp(target)]);
  void ja(Label target) => inst(X86InstId.kJnbe, [LabelOp(target)]);
  void jae(Label target) => inst(X86InstId.kJnb, [LabelOp(target)]);

  // ===========================================================================
  // Shifts / Rotates
  // ===========================================================================

  void shl(Operand dst, Operand count) => inst(X86InstId.kShl, [dst, count]);
  void shr(Operand dst, Operand count) => inst(X86InstId.kShr, [dst, count]);
  void sar(Operand dst, Operand count) => inst(X86InstId.kSar, [dst, count]);
  void rol(Operand dst, Operand count) => inst(X86InstId.kRol, [dst, count]);
  void ror(Operand dst, Operand count) => inst(X86InstId.kRor, [dst, count]);
  // ===========================================================================
  // RA Emission Interface Implementation
  // ===========================================================================

  @override
  void emitMove(Operand dst, Operand src) {
    if (dst is BaseReg && src is BaseReg) {
      if (dst.group == src.group) {
        // Simple register move
        inst(X86InstId.kMov, [dst, src]);
        return;
      }
      // TODO: Handle cross-group moves if necessary (e.g. MOVD/MOVQ)
    }
    // Handle memory operands
    inst(X86InstId.kMov, [dst, src]);
  }

  @override
  void emitSwap(Operand a, Operand b) {
    inst(X86InstId.kXchg, [a, b]);
  }
}

/// X86 Instruction Analyzer.
class X86InstructionAnalyzer extends InstructionAnalyzer {
  @override
  bool isJoin(InstNode node) {
    // Only basic check for now.
    return false;
  }

  @override
  bool isJump(InstNode node) {
    final id = node.instId;
    return (id >= X86InstId.kJb && id <= X86InstId.kJz) || id == X86InstId.kJmp;
  }

  @override
  bool isUnconditionalJump(InstNode node) {
    return node.instId == X86InstId.kJmp;
  }

  @override
  bool isReturn(InstNode node) {
    return node.instId == X86InstId.kRet;
  }

  @override
  Label? getJumpTarget(InstNode node) {
    if (isJump(node) && node.opCount > 0 && node.operands[0] is LabelOp) {
      return (node.operands[0] as LabelOp).label;
    }
    return null;
  }

  @override
  void analyze(BaseNode node, Set<BaseReg> def, Set<BaseReg> use) {
    if (node is! InstNode) return;

    // Simplistic analysis (read/write definitions):
    // Needs full opcode database access to know which ops read/write.
    // For now, assume dst is write, srcs are read.
    // X86: op0 is dst (usually RW), op1 is src (R).
    // This is VERY rough. Real impl needs Inst RWInfo.
    if (node.opCount > 0) {
      if (node.operands[0] is BaseReg) {
        final r = node.operands[0] as BaseReg;
        def.add(r);
        use.add(r); // Usually R/W
      }
    }
    for (var i = 1; i < node.opCount; i++) {
      if (node.operands[i] is BaseReg) {
        use.add(node.operands[i] as BaseReg);
      }
    }
  }
}
