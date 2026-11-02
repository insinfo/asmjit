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
import '../core/builder.dart' as ir;
import 'x86_serializer.dart';
import 'x86_rapass.dart';
import '../core/raarch.dart';
import '../core/reg_utils.dart';
import '../core/func.dart';
import '../core/type.dart';
import 'x86_emit.dart' show X86EmitOptions;

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

  /// New virtual register of [typeId] whose operand signature is
  /// [regType] (`new_virt_reg()`), so its size is the declared one even when
  /// an instruction uses a narrower view of it.
  int _newTypedVirtId(TypeId typeId, RegType regType, String? name) =>
      newVirtReg(
              typeId,
              OperandSignature.fromRegTypeAndGroup(
                  regType, regGroupOf(regType)),
              name)
          .id;

  static RegGroup regGroupOf(RegType type) => switch (type) {
        RegType.vec128 || RegType.vec256 || RegType.vec512 => RegGroup.vec,
        RegType.mask => RegGroup.mask,
        _ => RegGroup.gp,
      };

  X86Gp newGp(RegType type, [String? name]) {
    switch (type) {
      case RegType.gp8Lo:
        return X86Gp.r8(_newTypedVirtId(TypeId.int8, type, name));
      case RegType.gp16:
        return X86Gp.r16(_newTypedVirtId(TypeId.int16, type, name));
      case RegType.gp64:
        return X86Gp.r64(_newTypedVirtId(TypeId.int64, type, name));
      default:
        return X86Gp.r32(_newTypedVirtId(TypeId.int32, RegType.gp32, name));
    }
  }

  X86Gp newGp8([String? name]) => newGp(RegType.gp8Lo, name);
  X86Gp newGp16([String? name]) => newGp(RegType.gp16, name);
  X86Gp newGp32([String? name]) => newGp(RegType.gp32, name);
  X86Gp newGp64([String? name]) => newGp(RegType.gp64, name);
  X86Gp newGpPtr([String? name]) =>
      newGp(arch.is64Bit ? RegType.gp64 : RegType.gp32, name);

  X86Xmm newXmm([String? name]) =>
      X86Xmm(_newTypedVirtId(TypeId.int32x4, RegType.vec128, name));
  X86Ymm newYmm([String? name]) =>
      X86Ymm(_newTypedVirtId(TypeId.int32x8, RegType.vec256, name));
  X86Zmm newZmm([String? name]) =>
      X86Zmm(_newTypedVirtId(TypeId.int32x16, RegType.vec512, name));
  X86KReg newKReg([String? name]) =>
      X86KReg(_newTypedVirtId(TypeId.mask64, RegType.mask, name));

  /// `new_xmm_ss()`: XMM register holding a scalar `float`.
  X86Xmm newXmmSs([String? name]) =>
      X86Xmm(_newTypedVirtId(TypeId.float32x1, RegType.vec128, name));

  /// `new_xmm_sd()`: XMM register holding a scalar `double`.
  X86Xmm newXmmSd([String? name]) =>
      X86Xmm(_newTypedVirtId(TypeId.float64x1, RegType.vec128, name));

  /// `new_kb()`, `new_kw()`, `new_kd()`, `new_kq()`: AVX-512 mask registers.
  X86KReg newKb([String? name]) =>
      X86KReg(_newTypedVirtId(TypeId.mask8, RegType.mask, name));
  X86KReg newKw([String? name]) =>
      X86KReg(_newTypedVirtId(TypeId.mask16, RegType.mask, name));
  X86KReg newKd([String? name]) =>
      X86KReg(_newTypedVirtId(TypeId.mask32, RegType.mask, name));
  X86KReg newKq([String? name]) =>
      X86KReg(_newTypedVirtId(TypeId.mask64, RegType.mask, name));

  /// Create new 128-bit vector register (XMM).
  X86Xmm newXmmF32x1([String? name]) => newXmmSs(name);
  X86Xmm newXmmF64x1([String? name]) => newXmmSd(name);
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

  // ===========================================================================
  // Instruction options (x86::EmitterExplicitT)
  // ===========================================================================

  /// `rep(zcx)`: REP prefix with the counter register [zcx] (allocated to
  /// ECX/RCX) for the next string instruction.
  X86Compiler rep(BaseReg zcx) {
    instOptions |= X86EmitOptions.kX86_Rep;
    extraReg = zcx;
    return this;
  }

  /// `repne(zcx)`.
  X86Compiler repne(BaseReg zcx) {
    instOptions |= X86EmitOptions.kX86_Repne;
    extraReg = zcx;
    return this;
  }

  /// `k(kreg)`: AVX-512 write mask selector of the next instruction.
  X86Compiler k(X86KReg kreg) {
    extraReg = kreg;
    return this;
  }

  /// `z()`: AVX-512 zeroing masking of the next instruction.
  X86Compiler z() {
    instOptions |= X86EmitOptions.kX86_ZMask;
    return this;
  }

  /// Create new stack allocation.
  X86Mem newStack(int size, [int alignment = 1, String? name]) {
    final vReg = createStackVirtReg(size, alignment, name);
    // Create memory operand pointing to the virtual register.
    // The RA will assign the stack offset.
    // We use r64 for base as the virtual ID holder (typical for 64-bit pointers).
    return X86Mem.base(X86Gp.r64(vReg.id), size: size);
  }

  /// Create new memory operand with index.
  X86Mem newMemWithIndex(X86Mem base, X86Gp index, [int shift = 0]) {
    return X86Mem.baseIndexScale(
        base.base ?? X86Gp.rsp, index, shift > 0 ? shift : 1,
        disp: base.displacement, size: base.size);
  }

  void finalize() {
    runPasses();
  }

  @override
  RAArch createRAArch() => X86RAArch(this);

  @override
  void serializeToAssembler(BaseEmitter assembler) {
    if (assembler is! X86Assembler) {
      throw ArgumentError('X86Compiler requires X86Assembler');
    }
    final serializer = X86Serializer(assembler);
    ir.serializeNodes(nodes, serializer);
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
  void movsxd(Operand dst, Operand src) => inst(X86InstId.kMovsxd, [dst, src]);
  void movzx(Operand dst, Operand src) => inst(X86InstId.kMovzx, [dst, src]);
  void lea(Operand dst, Operand src) => inst(X86InstId.kLea, [dst, src]);
  void xchg(Operand dst, Operand src) => inst(X86InstId.kXchg, [dst, src]);

  // ===========================================================================
  // Arithmetic
  // ===========================================================================

  void add(Operand dst, Operand src) => inst(X86InstId.kAdd, [dst, src]);
  void sub(Operand dst, Operand src) => inst(X86InstId.kSub, [dst, src]);

  /// `mul(src)` (implicit EDX:EAX) or the explicit form
  /// `mul(hi, lo, src)` that the register allocator ties to EDX:EAX.
  void mul(Operand o0, [Operand? o1, Operand? o2]) =>
      inst(X86InstId.kMul, [o0, if (o1 != null) o1, if (o2 != null) o2]);

  /// `imul(dst, src)`, `imul(dst, src, imm)` or the explicit widening form
  /// `imul(hi, lo, src)` (EDX:EAX).
  void imul(Operand o0, Operand o1, [Operand? o2]) =>
      inst(X86InstId.kImul, [o0, o1, if (o2 != null) o2]);

  /// `div(src)` (implicit EDX:EAX) or the explicit `div(hi, lo, src)`.
  void div(Operand o0, [Operand? o1, Operand? o2]) =>
      inst(X86InstId.kDiv, [o0, if (o1 != null) o1, if (o2 != null) o2]);

  /// `idiv(src)` (implicit EDX:EAX) or the explicit `idiv(hi, lo, src)`.
  void idiv(Operand o0, [Operand? o1, Operand? o2]) =>
      inst(X86InstId.kIdiv, [o0, if (o1 != null) o1, if (o2 != null) o2]);

  void adc(Operand dst, Operand src) => inst(X86InstId.kAdc, [dst, src]);
  void sbb(Operand dst, Operand src) => inst(X86InstId.kSbb, [dst, src]);

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
  void setz(Operand dst) => inst(X86InstId.kSetz, [dst]);
  void setnz(Operand dst) => inst(X86InstId.kSetnz, [dst]);
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

  /// Jump to a register or memory [target] (a jump table) whose possible
  /// targets are [annotation] (`jmp(target, annotation)`); without one the
  /// register allocator assumes it can reach any block.
  JumpNode jmpIndirect(Operand target, [JumpAnnotation? annotation]) =>
      emitAnnotatedJump(X86InstId.kJmp, target, annotation);
  void call(Label target) => inst(X86InstId.kCall, [LabelOp(target)]);

  /// Calls [target] (an [Imm] address, a [LabelOp] / function label, a
  /// register or a memory operand) with [signature] (`invoke()`); the
  /// arguments and return values are set on the returned [InvokeNode].
  InvokeNode invoke(Operand target, FuncSignature signature) =>
      addInvokeNode(X86InstId.kCall, target, signature);

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
  void jns(Label target) =>
      inst(X86InstId.kJns, [LabelOp(target)], type: NodeType.jump);

  // ===========================================================================
  // Shifts / Rotates
  // ===========================================================================

  void shl(Operand dst, Operand count) => inst(X86InstId.kShl, [dst, count]);
  void shr(Operand dst, Operand count) => inst(X86InstId.kShr, [dst, count]);
  void sar(Operand dst, Operand count) => inst(X86InstId.kSar, [dst, count]);
  void rol(Operand dst, Operand count) => inst(X86InstId.kRol, [dst, count]);
  void ror(Operand dst, Operand count) => inst(X86InstId.kRor, [dst, count]);
  // ===========================================================================
  // AVX Scalar Double
  // ===========================================================================

  void vmovsd(Operand dst, Operand src) => inst(X86InstId.kVmovsd, [dst, src]);

  void vaddsd(Operand dst, Operand src1, Operand src2) =>
      inst(X86InstId.kVaddsd, [dst, src1, src2]);
  void vsubsd(Operand dst, Operand src1, Operand src2) =>
      inst(X86InstId.kVsubsd, [dst, src1, src2]);
  void vmulsd(Operand dst, Operand src1, Operand src2) =>
      inst(X86InstId.kVmulsd, [dst, src1, src2]);
  void vdivsd(Operand dst, Operand src1, Operand src2) =>
      inst(X86InstId.kVdivsd, [dst, src1, src2]);
  void vminsd(Operand dst, Operand src1, Operand src2) =>
      inst(X86InstId.kVminsd, [dst, src1, src2]);
  void vmaxsd(Operand dst, Operand src1, Operand src2) =>
      inst(X86InstId.kVmaxsd, [dst, src1, src2]);

  // ===========================================================================
  // RA Emission Interface Implementation
  // ===========================================================================

  @override
  void emitMove(Operand dst, Operand src) {
    if (dst is BaseReg) {
      if (dst.isVec) {
        // Vector move
        // Using kMovaps as a generic vector move for now (typical for XMM/YMM)
        // Ideally should match type (Int/Float), but Movaps works for register copies on most SIMD units.
        inst(X86InstId.kMovaps, [dst, src]);
        return;
      }
    }

    if (dst is BaseReg && src is BaseReg) {
      if (dst.group == src.group) {
        // Simple register move
        inst(X86InstId.kMov, [dst, src]);
        return;
      }
      // Note: Cross-group moves (e.g. MOVD/MOVQ) are handled by specialized methods or explicit inst calls.
      // Automatic conversion is not yet implemented.
    }
    // Handle memory operands
    inst(X86InstId.kMov, [dst, src]);
  }

  @override
  void emitSwap(Operand a, Operand b) {
    inst(X86InstId.kXchg, [a, b]);
  }

  // ===========================================================================
  // SIMD (Manual additions)
  // ===========================================================================

  void movdqu(Operand dst, Operand src) => inst(X86InstId.kMovdqu, [dst, src]);
  void pxor(Operand dst, Operand src) => inst(X86InstId.kPxor, [dst, src]);

  // String instructions (explicit memory operands, `movs(dst, src)`).
  void movs(Operand dst, Operand src) => inst(X86InstId.kMovs, [dst, src]);
  void stos(Operand dst, Operand src) => inst(X86InstId.kStos, [dst, src]);

  // SSE.
  void movd(Operand dst, Operand src) => inst(X86InstId.kMovd, [dst, src]);
  void movq(Operand dst, Operand src) => inst(X86InstId.kMovq, [dst, src]);
  void movss(Operand dst, Operand src) => inst(X86InstId.kMovss, [dst, src]);
  void movsd(Operand dst, Operand src) => inst(X86InstId.kMovsd, [dst, src]);
  void movaps(Operand dst, Operand src) => inst(X86InstId.kMovaps, [dst, src]);
  void movups(Operand dst, Operand src) => inst(X86InstId.kMovups, [dst, src]);
  void movdqa(Operand dst, Operand src) => inst(X86InstId.kMovdqa, [dst, src]);
  void addss(Operand dst, Operand src) => inst(X86InstId.kAddss, [dst, src]);
  void addsd(Operand dst, Operand src) => inst(X86InstId.kAddsd, [dst, src]);
  void subss(Operand dst, Operand src) => inst(X86InstId.kSubss, [dst, src]);
  void subsd(Operand dst, Operand src) => inst(X86InstId.kSubsd, [dst, src]);
  void mulss(Operand dst, Operand src) => inst(X86InstId.kMulss, [dst, src]);
  void mulsd(Operand dst, Operand src) => inst(X86InstId.kMulsd, [dst, src]);
  void divss(Operand dst, Operand src) => inst(X86InstId.kDivss, [dst, src]);
  void divsd(Operand dst, Operand src) => inst(X86InstId.kDivsd, [dst, src]);
  void xorps(Operand dst, Operand src) => inst(X86InstId.kXorps, [dst, src]);
  void paddb(Operand dst, Operand src) => inst(X86InstId.kPaddb, [dst, src]);
  void paddw(Operand dst, Operand src) => inst(X86InstId.kPaddw, [dst, src]);
  void paddd(Operand dst, Operand src) => inst(X86InstId.kPaddd, [dst, src]);
  void pmullw(Operand dst, Operand src) => inst(X86InstId.kPmullw, [dst, src]);
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

    final id = node.instId;
    final ops = node.operands;
    final opCount = node.opCount;

    // Helper to add if reg
    void addUse(Operand op) {
      if (op is BaseReg) use.add(op);
      if (op is BaseMem) {
        if (op.base != null) use.add(op.base!);
        if (op.index != null) use.add(op.index!);
      }
    }

    void addDef(Operand op) {
      if (op is BaseReg) def.add(op);
    }

    // Handle specific instruction groups
    if (id == X86InstId.kMov ||
        id == X86InstId.kMovsx ||
        id == X86InstId.kMovzx ||
        id == X86InstId.kLea) {
      // MOV/LEA: Write op0, Read op1
      if (opCount > 0) addDef(ops[0]);
      if (opCount > 1) addUse(ops[1]);
      return;
    }

    if (id == X86InstId.kCmp || id == X86InstId.kTest) {
      // CMP/TEST: Read op0, Read op1
      if (opCount > 0) addUse(ops[0]);
      if (opCount > 1) addUse(ops[1]);
      return;
    }

    if (id == X86InstId.kPush) {
      // PUSH: Read op0
      if (opCount > 0) addUse(ops[0]);
      return;
    }

    if (id == X86InstId.kPop) {
      // POP: Write op0
      if (opCount > 0) addDef(ops[0]);
      return;
    }

    if (id == X86InstId.kDiv || id == X86InstId.kIdiv || id == X86InstId.kMul) {
      // Implicit Use/Def of AX/DX
      // DIV/MUL r/m: Reads AX (and DX for 64-bit/32-bit), Writes AX, DX
      def.add(X86Gp.rax);
      def.add(X86Gp.rdx);
      use.add(X86Gp.rax);
      use.add(X86Gp.rdx);
      if (opCount > 0) addUse(ops[0]);
      return;
    }

    // Default RMW (Read-Modify-Write) behavior for binary ops (ADD, SUB, XOR, etc)
    // op0 is R+W, op1 is R
    if (opCount > 0) {
      addUse(ops[0]);
      addDef(ops[0]);
    }
    for (var i = 1; i < opCount; i++) {
      addUse(ops[i]);
    }
  }
}
