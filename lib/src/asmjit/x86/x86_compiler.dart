import '../core/builder.dart';
import '../core/compiler.dart';
import 'x86_assembler.dart';
import '../core/labels.dart';
import '../core/rapass.dart';
import '../core/environment.dart';
import 'x86_inst_db.g.dart';
import 'x86.dart';
import 'x86_operands.dart';
import 'x86_simd.dart';
import '../core/reg_type.dart';
import '../core/operand.dart';

/// X86 Compiler.
class X86Compiler extends BaseCompiler {
  @override
  BaseMem newStackSlot(int baseId, int offset, int size) {
    // Assuming baseId is SP/FP which are usually 64-bit in 64-bit mode.
    // Ideally use ArchTraits to know size? Or assume standard stack pointer size.
    final base = X86Gp.r64(baseId);
    return X86Mem.base(base, disp: offset, size: size);
  }

  X86Compiler({Environment? env, LabelManager? labelManager})
      : super(env: env, labelManager: labelManager) {
    // Passes must be ordered!
    addPass(CFGBuilder(this, X86InstructionAnalyzer()));
    addPass(RAPass(this));
  }

  X86Gp newGp(RegType type, [String? name]) {
    final id = newVirtId();
    if (type == RegType.gp32) return X86Gp.r32(id);
    if (type == RegType.gp64) return X86Gp.r64(id);
    if (type == RegType.gp16) return X86Gp.r16(id);
    return X86Gp.r32(id);
  }

  X86Gp newGp32([String? name]) => newGp(RegType.gp32, name);
  X86Gp newGp64([String? name]) => newGp(RegType.gp64, name);
  X86Gp newGpPtr([String? name]) =>
      newGp(arch.is64Bit ? RegType.gp64 : RegType.gp32, name);

  X86Xmm newXmm([String? name]) => X86Xmm(newVirtId());
  X86Ymm newYmm([String? name]) => X86Ymm(newVirtId());
  X86Zmm newZmm([String? name]) => X86Zmm(newVirtId());
  
  /// Create new 128-bit vector register (XMM).
  X86Xmm newXmmF32x1([String? name]) => newXmm(name);
  X86Xmm newXmmF64x1([String? name]) => newXmm(name);
  X86Xmm newXmmF32x4([String? name]) => newXmm(name);
  X86Xmm newXmmF64x2([String? name]) => newXmm(name);
  X86Xmm newXmmInt32x4([String? name]) => newXmm(name);
  X86Xmm newXmmInt64x2([String? name]) => newXmm(name);
  X86Xmm newXmmInt8x16([String? name]) => newXmm(name);
  X86Xmm newXmmInt16x8([String? name]) => newXmm(name);
  
  /// Create new 256-bit vector register (YMM).
  X86Ymm newYmmF32x8([String? name]) => newYmm(name);
  X86Ymm newYmmF64x4([String? name]) => newYmm(name);
  X86Ymm newYmmInt32x8([String? name]) => newYmm(name);
  X86Ymm newYmmInt64x4([String? name]) => newYmm(name);
  X86Ymm newYmmInt8x32([String? name]) => newYmm(name);
  X86Ymm newYmmInt16x16([String? name]) => newYmm(name);
  
  /// Create new 512-bit vector register (ZMM).
  X86Zmm newZmmF32x16([String? name]) => newZmm(name);
  X86Zmm newZmmF64x8([String? name]) => newZmm(name);
  X86Zmm newZmmInt32x16([String? name]) => newZmm(name);
  X86Zmm newZmmInt64x8([String? name]) => newZmm(name);
  X86Zmm newZmmInt8x64([String? name]) => newZmm(name);
  X86Zmm newZmmInt16x32([String? name]) => newZmm(name);
  
  /// Create new stack allocation.
  X86Mem newStack(int size, [int alignment = 1]) {
    // TODO: Implement proper stack allocation with alignment
    return X86Mem.base(X86Gp.rsp, disp: -size);
  }
  
  /// Create new memory operand with index.
  X86Mem newMemWithIndex(X86Mem base, X86Gp index, [int shift = 0]) {
    return X86Mem.baseIndexScale(
        base.base ?? X86Gp.rsp, 
        index, 
        shift > 0 ? shift : 1, 
        disp: base.displacement, 
        size: base.size);
  }

  void finalize() {
    runPasses();
  }

  void serializeToAssembler(X86Assembler assembler) {
    for (final node in nodes.nodes) {
      if (node is InstNode) {
        if (node.nodeType == NodeType.inst) {
          assembler.emit(node.instId, node.operands);
        } else if (node.nodeType == NodeType.jump) {
          assembler.emit(node.instId, node.operands);
        } else if (node.nodeType == NodeType.funcRet) {
          // Abstract Ret handling: translates to actual epilog + ret
          // For now simple ret
          assembler.ret();
        }
      } else if (node is LabelNode && node.nodeType == NodeType.label) {
        assembler.bind(node.label);
      }
      // Handle other node types if needed
    }
  }

  // ===========================================================================
  // Basic instructions
  // ===========================================================================

  @override
  void ret([List<Operand> operands = const []]) {
    addNode(FuncRetNode(operands));
  }

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

  void jmp(Label target) =>
      inst(X86InstId.kJmp, [LabelOp(target)], type: NodeType.jump);
  void call(Label target) => inst(X86InstId.kCall, [LabelOp(target)]);

  void je(Label target) =>
      inst(X86InstId.kJz, [LabelOp(target)], type: NodeType.jump);
  void jz(Label target) =>
      inst(X86InstId.kJz, [LabelOp(target)], type: NodeType.jump);
  void jne(Label target) =>
      inst(X86InstId.kJnz, [LabelOp(target)], type: NodeType.jump);
  void jnz(Label target) =>
      inst(X86InstId.kJnz, [LabelOp(target)], type: NodeType.jump);

  void jl(Label target) =>
      inst(X86InstId.kJl, [LabelOp(target)], type: NodeType.jump);
  void jle(Label target) =>
      inst(X86InstId.kJle, [LabelOp(target)], type: NodeType.jump);
  void jg(Label target) =>
      inst(X86InstId.kJnle, [LabelOp(target)], type: NodeType.jump);
  void jge(Label target) =>
      inst(X86InstId.kJnl, [LabelOp(target)], type: NodeType.jump);

  void jb(Label target) =>
      inst(X86InstId.kJb, [LabelOp(target)], type: NodeType.jump);
  void jbe(Label target) =>
      inst(X86InstId.kJbe, [LabelOp(target)], type: NodeType.jump);
  void ja(Label target) =>
      inst(X86InstId.kJnbe, [LabelOp(target)], type: NodeType.jump);
  void jae(Label target) =>
      inst(X86InstId.kJnb, [LabelOp(target)], type: NodeType.jump);

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
