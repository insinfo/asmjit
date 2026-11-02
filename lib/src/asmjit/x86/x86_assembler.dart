/// AsmJit x86/x64 Assembler
///
/// High-level x86/x64 instruction emission API.
/// Ported from asmjit/x86/x86assembler.h

import '../core/code_holder.dart';
import '../core/code_buffer.dart';
import '../core/emitter.dart';
import '../core/error.dart';
import '../core/func.dart';
import '../core/labels.dart';
import '../core/environment.dart';
import '../core/arch.dart';
import '../core/reg_utils.dart';
import '../core/operand.dart';
import 'x86.dart';
import 'x86_operands.dart';
import 'x86_cond.dart';
import 'x86_simd.dart';
import 'x86_inst_db.g.dart';
import 'x86_emit.dart';
import 'x86_emit_helper.dart';

/// x86/x64 Assembler.
///
/// Provides a high-level API for emitting x86/x64 instructions.
/// Handles label binding, relocations, and instruction encoding.
class X86Assembler extends BaseEmitter {
  /// The internal code buffer.
  late final CodeBuffer _buf;

  /// Encoding options (used by higher-level pipelines).
  int encodingOptions = EncodingOptions.kNone;

  /// Diagnostic options (used by higher-level pipelines).
  int diagnosticOptions = DiagnosticOptions.kNone;

  /// Creates an x86 assembler for the given code holder.
  X86Assembler(CodeHolder code) : super(code) {
    _buf = code.text.buffer;
  }

  /// Port of upstream `x86::Assembler::_emit()` (x86_emit.dart).
  late final X86Emitter _emitter = X86Emitter(code, _buf);

  /// Options of the next instruction ([X86EmitOptions]: prefixes such as
  /// LOCK/REP, `{sae}`/`{er}`, `{z}`, forced VEX3/EVEX, short/long forms);
  /// reset after every instruction, as upstream `inst_options()`.
  int get instOptions => _emitter.instOptions;
  set instOptions(int options) => _emitter.instOptions = options;

  /// Extra register of the next instruction (AVX-512 `{k}` selector or the
  /// REP counter), as upstream `extra_reg()`; reset after every instruction.
  set extraReg(BaseReg? reg) => _emitter.extraReg = reg;

  /// Emits a raw instruction by ID with generic operands (registers,
  /// [X86Mem], integers or [Imm] immediates and [Label]s), encoded as
  /// upstream `x86::Assembler::_emit()`.
  void emit(int instId, List<Object> ops) {
    instructionCount++;
    _emitter.encodingOptions = encodingOptions;
    _emitter.emit(instId, ops);
  }

  /// Emits moves required to assign arguments if any remapping is needed.
  AsmJitError emitArgsAssignment(FuncFrame frame, FuncArgsAssignment args) {
    final helper = X86EmitHelper(this);
    return helper.emitArgsAssignment(frame, args);
  }

  /// Creates an x86 assembler with a new code holder.
  factory X86Assembler.create({Environment? env}) {
    final code = CodeHolder(env: env);
    return X86Assembler(code);
  }

  // ===========================================================================
  // Properties
  // ===========================================================================

  /// The current offset in the code buffer.
  int get offset => _buf.length;

  /// The environment.
  Environment get environment => code.env;

  /// Whether this is a 64-bit assembler.
  bool get is64Bit => environment.arch == Arch.x64;

  /// The calling convention for this environment.
  CallingConvention get callingConvention => environment.callingConvention;

  // ===========================================================================
  // Label management
  // ===========================================================================

  /// Creates a new label.
  Label newLabel() => code.newLabel();

  /// Creates a new named label.
  Label newNamedLabel(String name) => code.newNamedLabel(name);

  /// Binds a label to the current position.
  void bind(Label label) => code.bind(label);

  // ===========================================================================
  // Raw byte emission
  // ===========================================================================

  /// Emits raw bytes.
  void emitBytes(List<int> bytes) => _buf.emitBytes(bytes);

  /// Emits a single byte.
  void emit8(int value) => _buf.emit8(value);

  /// Emits a 16-bit value.
  void emit16(int value) => _buf.emit16(value);

  /// Emits a 32-bit value.
  void emit32(int value) => _buf.emit32(value);

  /// Emits a 64-bit value.
  void emit64(int value) => _buf.emit64(value);

  /// Aligns to [alignment] bytes with NOPs.
  void align(int alignment) => _buf.alignWithNops(alignment);

  // ===========================================================================
  // Basic instructions
  // ===========================================================================

  /// RET - Return from procedure.
  void ret() => emit(X86InstId.kRet, []);

  /// RET imm16 - Return and pop bytes from stack.
  void retImm(int imm16) => emit(X86InstId.kRet, [imm16]);

  /// NOP - No operation.
  void nop() => emit(X86InstId.kNop, []);

  /// Multi-byte NOP: [bytes] bytes of the NOP sequences upstream
  /// `x86::Assembler::align()` uses with `EncodingOptions::kOptimizedAlign`.
  void nopN(int bytes) {
    while (bytes > 0) {
      final n = bytes < _nopTable.length ? bytes : _nopTable.length;
      _buf.emitBytes(_nopTable[n - 1]);
      bytes -= n;
    }
  }

  /// Upstream `nop_table` (x86assembler.cpp, `Assembler::align()`).
  static const List<List<int>> _nopTable = [
    [0x90],
    [0x66, 0x90],
    [0x0F, 0x1F, 0x00],
    [0x0F, 0x1F, 0x40, 0x00],
    [0x0F, 0x1F, 0x44, 0x00, 0x00],
    [0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00],
    [0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00],
    [0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
    [0x66, 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
  ];

  /// INT3 - Breakpoint.
  void int3() => emit(X86InstId.kInt3, []);

  /// INT n - Software interrupt.
  void intN(int n) => emit(X86InstId.kInt, [n]);

  // ===========================================================================
  // MOV instructions
  // ===========================================================================

  /// MOV dst, src (register to register).
  void movRR(X86Gp dst, X86Gp src) => emit(X86InstId.kMov, [dst, src]);

  /// MOV reg, imm64: as upstream, a 64-bit destination uses `mov r32, imm32`
  /// when the value is a zero-extended 32-bit one, `mov r64, simm32` when it
  /// is a sign-extended one and `movabs r64, imm64` otherwise.
  void movRI64(X86Gp dst, int imm) => emit(X86InstId.kMov, [dst, imm]);

  /// MOV r32, imm32.
  void movRI32(X86Gp dst, int imm) => emit(X86InstId.kMov, [dst.as32, imm]);

  /// MOV reg, imm (the immediate size follows the register size).
  void movRI(X86Gp dst, int imm) => emit(X86InstId.kMov, [dst, imm]);

  /// MOV (generic).
  void mov(Operand dst, Object src) => emit(X86InstId.kMov, [dst, src]);

  /// MOV reg, [mem] — operand size follows the register size.
  void movRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kMov, [dst, mem]);

  /// MOV [mem], reg — operand size follows the register size.
  void movMR(X86Mem mem, X86Gp src) => emit(X86InstId.kMov, [mem, src]);

  /// MOV [mem], imm (the memory operand must have a size).
  void movMI(X86Mem mem, int imm) => emit(X86InstId.kMov, [mem, imm]);

  // ===========================================================================
  // Arithmetic instructions
  // ===========================================================================

  /// ADD dst, src (register to register).
  void addRR(X86Gp dst, X86Gp src) => emit(X86InstId.kAdd, [dst, src]);

  /// ADD reg, imm.
  void addRI(X86Gp dst, int imm) => emit(X86InstId.kAdd, [dst, imm]);

  /// ADD reg, [mem].
  void addRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kAdd, [dst, mem]);

  /// ADD [mem], reg.
  void addMR(X86Mem mem, X86Gp src) => emit(X86InstId.kAdd, [mem, src]);

  /// ADD [mem], imm.
  void addMI(X86Mem mem, int imm) => emit(X86InstId.kAdd, [mem, imm]);

  /// SUB dst, src.
  void subRR(X86Gp dst, X86Gp src) => emit(X86InstId.kSub, [dst, src]);

  /// SUB reg, imm.
  void subRI(X86Gp dst, int imm) => emit(X86InstId.kSub, [dst, imm]);

  /// SUB reg, [mem].
  void subRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kSub, [dst, mem]);

  /// AND r64, [mem].
  void andRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kAnd, [dst, mem]);

  /// AND [mem], reg.
  void andMR(X86Mem mem, X86Gp src) => emit(X86InstId.kAnd, [mem, src]);

  /// AND [mem], imm.
  void andMI(X86Mem mem, int imm) => emit(X86InstId.kAnd, [mem, imm]);

  /// OR reg, [mem].
  void orRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kOr, [dst, mem]);

  /// XOR reg, [mem].
  void xorRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kXor, [dst, mem]);

  /// CMP reg, [mem].
  void cmpRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kCmp, [dst, mem]);

  /// TEST [mem], reg.
  void testRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kTest, [mem, dst]);

  /// IMUL dst, src.
  void imulRR(X86Gp dst, X86Gp src) => emit(X86InstId.kImul, [dst, src]);

  /// IMUL dst, src, imm (three-operand form).
  void imulRRI(X86Gp dst, X86Gp src, int imm) =>
      emit(X86InstId.kImul, [dst, src, imm]);

  /// IMUL dst, imm (dst = dst * imm).
  void imulRI(X86Gp dst, int imm) => emit(X86InstId.kImul, [dst, imm]);

  /// XOR dst, src.
  void xorRR(X86Gp dst, X86Gp src) => emit(X86InstId.kXor, [dst, src]);

  /// AND dst, src.
  void andRR(X86Gp dst, X86Gp src) => emit(X86InstId.kAnd, [dst, src]);

  /// OR dst, src.
  void orRR(X86Gp dst, X86Gp src) => emit(X86InstId.kOr, [dst, src]);

  /// CMP dst, src.
  void cmpRR(X86Gp dst, X86Gp src) => emit(X86InstId.kCmp, [dst, src]);

  /// CMP reg, imm.
  void cmpRI(X86Gp dst, int imm) => emit(X86InstId.kCmp, [dst, imm]);

  /// TEST dst, src.
  void testRR(X86Gp dst, X86Gp src) => emit(X86InstId.kTest, [dst, src]);

  /// TEST reg, imm.
  void testRI(X86Gp dst, int imm) => emit(X86InstId.kTest, [dst, imm]);

  /// AND r64, imm.
  void andRI(X86Gp dst, int imm) => emit(X86InstId.kAnd, [dst, imm]);

  /// OR reg, imm.
  void orRI(X86Gp dst, int imm) => emit(X86InstId.kOr, [dst, imm]);

  /// XOR reg, imm.
  void xorRI(X86Gp dst, int imm) => emit(X86InstId.kXor, [dst, imm]);

  /// MOVSX dst, r8 (sign-extend the low byte of [src]).
  void movsxB(X86Gp dst, X86Gp src) =>
      emit(X86InstId.kMovsx, [dst, src.bits == 8 ? src : src.as8]);

  /// MOVSX dst, r16 (sign-extend the low word of [src]).
  void movsxW(X86Gp dst, X86Gp src) => emit(X86InstId.kMovsx, [dst, src.as16]);

  /// MOVZX reg, reg — source register size selects the byte/word form.
  void movzxRR(X86Gp dst, X86Gp src) => emit(X86InstId.kMovzx, [dst, src]);

  /// MOVSX reg, reg — source register size selects the byte/word form.
  void movsxRR(X86Gp dst, X86Gp src) => emit(X86InstId.kMovsx, [dst, src]);

  /// MOVZX reg, [mem] — memory operand size selects the byte/word form.
  void movzxRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kMovzx, [dst, mem]);

  /// MOVSX reg, [mem] — memory operand size selects the byte/word form.
  void movsxRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kMovsx, [dst, mem]);

  /// MOVSXD r64, dword ptr [mem].
  /// MOVSXD r64, dword ptr [mem].
  void movsxdRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kMovsxd, [dst, mem]);

  // ===========================================================================
  // Stack instructions
  // ===========================================================================

  /// PUSH r64.
  void push(X86Gp reg) => emit(X86InstId.kPush, [reg]);

  /// POP r64.
  void pop(X86Gp reg) => emit(X86InstId.kPop, [reg]);

  /// PUSH imm8.
  void pushImm8(int imm) => emit(X86InstId.kPush, [imm]);

  /// PUSH imm32 (always the 4-byte immediate form).
  void pushImm32(int imm) {
    instOptions |= X86EmitOptions.kLongForm;
    emit(X86InstId.kPush, [imm]);
  }

  // ===========================================================================
  // Control flow instructions
  // ===========================================================================

  /// JMP to label.
  ///
  /// As upstream: a jump to a bound label uses the short form (rel8) when the
  /// displacement fits; a jump to an unbound label uses rel32 unless
  /// [forceShort] (`kShortForm`) is given.
  void jmp(Label target, {bool forceShort = false}) {
    if (forceShort) instOptions |= X86EmitOptions.kShortForm;
    emit(X86InstId.kJmp, [target]);
  }

  /// JMP r64.
  void jmpR(X86Gp reg) => emit(X86InstId.kJmp, [reg]);

  /// CALL to label.
  void call(Label target) => emit(X86InstId.kCall, [target]);

  /// CALL r64.
  void callR(X86Gp reg) => emit(X86InstId.kCall, [reg]);

  // ===========================================================================
  // Conditional jumps
  // ===========================================================================

  /// Instruction ids of Jcc, CMOVcc and SETcc indexed by [X86Cond.code].
  static const List<int> _jccIds = [
    X86InstId.kJo, X86InstId.kJno, X86InstId.kJb, X86InstId.kJnb, //
    X86InstId.kJz, X86InstId.kJnz, X86InstId.kJbe, X86InstId.kJnbe,
    X86InstId.kJs, X86InstId.kJns, X86InstId.kJp, X86InstId.kJnp,
    X86InstId.kJl, X86InstId.kJnl, X86InstId.kJle, X86InstId.kJnle,
  ];
  static const List<int> _cmovIds = [
    X86InstId.kCmovo, X86InstId.kCmovno, X86InstId.kCmovb, //
    X86InstId.kCmovnb, X86InstId.kCmovz, X86InstId.kCmovnz,
    X86InstId.kCmovbe, X86InstId.kCmovnbe, X86InstId.kCmovs,
    X86InstId.kCmovns, X86InstId.kCmovp, X86InstId.kCmovnp,
    X86InstId.kCmovl, X86InstId.kCmovnl, X86InstId.kCmovle,
    X86InstId.kCmovnle,
  ];
  static const List<int> _setIds = [
    X86InstId.kSeto, X86InstId.kSetno, X86InstId.kSetb, X86InstId.kSetnb, //
    X86InstId.kSetz, X86InstId.kSetnz, X86InstId.kSetbe, X86InstId.kSetnbe,
    X86InstId.kSets, X86InstId.kSetns, X86InstId.kSetp, X86InstId.kSetnp,
    X86InstId.kSetl, X86InstId.kSetnl, X86InstId.kSetle, X86InstId.kSetnle,
  ];

  /// Jcc to label (short/near form chosen as in [jmp]).
  void jcc(X86Cond cond, Label target, {bool forceShort = false}) {
    if (forceShort) instOptions |= X86EmitOptions.kShortForm;
    emit(_jccIds[cond.code], [target]);
  }

  /// JE/JZ - Jump if equal/zero.
  void je(Label target) => jcc(X86Cond.e, target);
  void jz(Label target) => jcc(X86Cond.e, target);

  /// JNE/JNZ - Jump if not equal/not zero.
  void jne(Label target) => jcc(X86Cond.ne, target);
  void jnz(Label target) => jcc(X86Cond.ne, target);

  /// JL - Jump if less (signed).
  void jl(Label target) => jcc(X86Cond.l, target);

  /// JLE - Jump if less or equal (signed).
  void jle(Label target) => jcc(X86Cond.le, target);

  /// JG - Jump if greater (signed).
  void jg(Label target) => jcc(X86Cond.g, target);

  /// JGE - Jump if greater or equal (signed).
  void jge(Label target) => jcc(X86Cond.ge, target);

  /// JB - Jump if below (unsigned).
  void jb(Label target) => jcc(X86Cond.b, target);

  /// JBE - Jump if below or equal (unsigned).
  void jbe(Label target) => jcc(X86Cond.be, target);

  /// JA - Jump if above (unsigned).
  void ja(Label target) => jcc(X86Cond.a, target);

  /// JAE - Jump if above or equal (unsigned).
  void jae(Label target) => jcc(X86Cond.ae, target);

  // ===========================================================================
  // LEA instruction
  // ===========================================================================

  /// LEA r64, [mem].
  void lea(X86Gp dst, X86Mem mem) => emit(X86InstId.kLea, [dst, mem]);

  // ===========================================================================
  // Prologue/Epilogue helpers
  // ===========================================================================

  /// Emits a standard function prologue.
  ///
  /// ```asm
  /// push rbp
  /// mov rbp, rsp
  /// sub rsp, stackSize  ; if stackSize > 0
  /// ```
  void emitPrologue({int stackSize = 0}) {
    push(rbp);
    movRR(rbp, rsp);
    if (stackSize > 0) {
      // Align stack size to 16 bytes
      stackSize = (stackSize + 15) & ~15;
      subRI(rsp, stackSize);
    }
  }

  /// Emits a standard function epilogue.
  ///
  /// ```asm
  /// mov rsp, rbp  ; or leave
  /// pop rbp
  /// ret
  /// ```
  void emitEpilogue() {
    movRR(rsp, rbp);
    pop(rbp);
    ret();
  }

  /// Emits LEAVE instruction (equivalent to mov rsp, rbp; pop rbp).
  void leave() => emit(X86InstId.kLeave, []);

  // ===========================================================================
  // ABI helpers
  // ===========================================================================

  /// Gets the argument register for the given argument index.
  X86Gp getArgReg(int index) {
    if (callingConvention == CallingConvention.win64) {
      const regs = [rcx, rdx, r8, r9];
      if (index >= regs.length) {
        throw ArgumentError('Win64 only has ${regs.length} register arguments');
      }
      return regs[index];
    } else {
      // System V AMD64
      const regs = [rdi, rsi, rdx, rcx, r8, r9];
      if (index >= regs.length) {
        throw ArgumentError('SysV only has ${regs.length} register arguments');
      }
      return regs[index];
    }
  }

  /// Gets the return value register.
  X86Gp get retReg => rax;

  /// Gets callee-saved registers for the current ABI.
  List<X86Gp> get calleeSavedRegs {
    if (callingConvention == CallingConvention.win64) {
      return win64CalleeSaved;
    } else {
      return sysVCalleeSaved;
    }
  }

  // ===========================================================================
  // Inline bytes API
  // ===========================================================================

  /// Emits inline bytes (for raw shellcode).
  void emitInline(List<int> bytes) {
    _buf.emitBytes(bytes);
  }

  // ===========================================================================
  // Unary instructions
  // ===========================================================================

  /// INC reg.
  void inc(X86Gp reg) => emit(X86InstId.kInc, [reg]);

  /// DEC reg.
  void dec(X86Gp reg) => emit(X86InstId.kDec, [reg]);

  /// NEG reg (two's complement negation).
  void neg(X86Gp reg) => emit(X86InstId.kNeg, [reg]);

  /// NOT reg (one's complement).
  void not(X86Gp reg) => emit(X86InstId.kNot, [reg]);

  // ===========================================================================
  // Shift instructions
  // ===========================================================================

  /// SHL reg, imm (left shift).
  void shlRI(X86Gp reg, int imm) => emit(X86InstId.kShl, [reg, imm]);

  /// SHL reg, CL (left shift by CL).
  void shlRCl(X86Gp reg) => emit(X86InstId.kShl, [reg, cl]);

  /// SHR reg, imm (logical right shift).
  void shrRI(X86Gp reg, int imm) => emit(X86InstId.kShr, [reg, imm]);

  /// SHR reg, CL (logical right shift by CL).
  void shrRCl(X86Gp reg) => emit(X86InstId.kShr, [reg, cl]);

  /// SAR reg, imm (arithmetic right shift).
  void sarRI(X86Gp reg, int imm) => emit(X86InstId.kSar, [reg, imm]);

  /// SAR reg, CL (arithmetic right shift by CL).
  void sarRCl(X86Gp reg) => emit(X86InstId.kSar, [reg, cl]);

  /// ROL reg, imm (rotate left).
  void rolRI(X86Gp reg, int imm) => emit(X86InstId.kRol, [reg, imm]);

  /// ROR reg, imm (rotate right).
  void rorRI(X86Gp reg, int imm) => emit(X86InstId.kRor, [reg, imm]);

  // ===========================================================================
  // Exchange instruction
  // ===========================================================================

  /// XCHG a, b (exchange values).
  void xchg(X86Gp a, X86Gp b) => emit(X86InstId.kXchg, [a, b]);

  // ===========================================================================
  // Conditional move (CMOVcc)
  // ===========================================================================

  /// CMOVcc dst, src (conditional move).
  void cmovcc(X86Cond cond, X86Gp dst, Object src) =>
      emit(_cmovIds[cond.code], [dst, src]);

  /// CMOVE dst, src (move if equal).
  void cmove(X86Gp dst, X86Gp src) => cmovcc(X86Cond.e, dst, src);
  void cmovz(X86Gp dst, X86Gp src) => cmovcc(X86Cond.e, dst, src);

  /// CMOVNE dst, src (move if not equal).
  void cmovne(X86Gp dst, X86Gp src) => cmovcc(X86Cond.ne, dst, src);
  void cmovnz(X86Gp dst, X86Gp src) => cmovcc(X86Cond.ne, dst, src);

  /// CMOVL dst, src (move if less, signed).
  void cmovl(X86Gp dst, X86Gp src) => cmovcc(X86Cond.l, dst, src);

  /// CMOVG dst, src (move if greater, signed).
  void cmovg(X86Gp dst, X86Gp src) => cmovcc(X86Cond.g, dst, src);

  /// CMOVLE dst, src (move if less or equal, signed).
  void cmovle(X86Gp dst, X86Gp src) => cmovcc(X86Cond.le, dst, src);

  /// CMOVGE dst, src (move if greater or equal, signed).
  void cmovge(X86Gp dst, X86Gp src) => cmovcc(X86Cond.ge, dst, src);

  /// CMOVB dst, src (move if below, unsigned).
  void cmovb(X86Gp dst, X86Gp src) => cmovcc(X86Cond.b, dst, src);

  /// CMOVA dst, src (move if above, unsigned).
  void cmova(X86Gp dst, X86Gp src) => cmovcc(X86Cond.a, dst, src);

  // ===========================================================================
  // Set byte on condition (SETcc)
  // ===========================================================================

  /// SETcc reg (set byte based on condition).
  void setcc(X86Cond cond, X86Gp reg) =>
      emit(_setIds[cond.code], [reg.bits == 8 ? reg : reg.as8]);

  /// SETE reg (set if equal).
  void sete(X86Gp reg) => setcc(X86Cond.e, reg);

  /// SETNE reg (set if not equal).
  void setne(X86Gp reg) => setcc(X86Cond.ne, reg);

  /// SETL reg (set if less, signed).
  void setl(X86Gp reg) => setcc(X86Cond.l, reg);

  /// SETG reg (set if greater, signed).
  void setg(X86Gp reg) => setcc(X86Cond.g, reg);

  // ===========================================================================
  // Move with extension
  // ===========================================================================

  /// MOVZX dst, src (zero-extend byte to qword).
  void movzxB(X86Gp dst, X86Gp src) =>
      emit(X86InstId.kMovzx, [dst, src.bits == 8 ? src : src.as8]);

  /// MOVZX dst, src (zero-extend word to qword).
  void movzxW(X86Gp dst, X86Gp src) => emit(X86InstId.kMovzx, [dst, src.as16]);

  /// MOVSXD dst, src (sign-extend dword to qword).
  void movsxd(X86Gp dst, X86Gp src) => emit(X86InstId.kMovsxd, [dst, src]);

  // ===========================================================================
  // Bit manipulation
  // ===========================================================================

  /// ARPL r/m16, r16.
  void arplRR(X86Gp dst, X86Gp src) => emit(X86InstId.kArpl, [dst, src]);

  /// ARPL [mem16], r16.
  void arplMR(X86Mem dst, X86Gp src) => emit(X86InstId.kArpl, [dst, src]);

  /// BOUND r16/r32, [mem].
  void bound(X86Gp dst, X86Mem mem) => emit(X86InstId.kBound, [dst, mem]);

  /// BSF dst, [mem].
  void bsfRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kBsf, [dst, mem]);

  /// BSR dst, [mem].
  void bsrRM(X86Gp dst, X86Mem mem) => emit(X86InstId.kBsr, [dst, mem]);

  /// BT reg, imm.
  void btRI(X86Gp dst, int imm) => emit(X86InstId.kBt, [dst, imm]);

  /// BT [mem], imm.
  void btMI(X86Mem mem, int imm) => emit(X86InstId.kBt, [mem, imm]);

  /// BT reg, reg.
  void btRR(X86Gp dst, X86Gp src) => emit(X86InstId.kBt, [dst, src]);

  /// BT [mem], reg.
  void btMR(X86Mem mem, X86Gp src) => emit(X86InstId.kBt, [mem, src]);

  /// BTC reg, imm.
  void btcRI(X86Gp dst, int imm) => emit(X86InstId.kBtc, [dst, imm]);

  /// BTC [mem], imm.
  void btcMI(X86Mem mem, int imm) => emit(X86InstId.kBtc, [mem, imm]);

  /// BTC reg, reg.
  void btcRR(X86Gp dst, X86Gp src) => emit(X86InstId.kBtc, [dst, src]);

  /// BTC [mem], reg.
  void btcMR(X86Mem mem, X86Gp src) => emit(X86InstId.kBtc, [mem, src]);

  /// BTR reg, imm.
  void btrRI(X86Gp dst, int imm) => emit(X86InstId.kBtr, [dst, imm]);

  /// BTR reg, reg.
  void btrRR(X86Gp dst, X86Gp src) => emit(X86InstId.kBtr, [dst, src]);

  /// BTS reg, imm.
  void btsRI(X86Gp dst, int imm) => emit(X86InstId.kBts, [dst, imm]);

  /// BTS reg, reg.
  void btsRR(X86Gp dst, X86Gp src) => emit(X86InstId.kBts, [dst, src]);

  // ===========================================================================
  // Division
  // ===========================================================================

  /// CDQ - Sign-extend EAX into EDX:EAX
  void cdq() => emit(X86InstId.kCdq, []);

  /// CQO - Sign-extend RAX into RDX:RAX
  void cqo() => emit(X86InstId.kCqo, []);

  /// CBW - Convert byte to word (AL -> AX)
  void cbw() => emit(X86InstId.kCbw, []);

  /// CWDE - Convert word to doubleword (AX -> EAX)
  void cwde() => emit(X86InstId.kCwde, []);

  /// CDQE - Convert doubleword to quadword (EAX -> RAX)
  void cdqe() => emit(X86InstId.kCdqe, []);

  /// CWD - Convert word to doubleword (AX -> DX:AX)
  void cwd() => emit(X86InstId.kCwd, []);

  /// IDIV reg - Signed divide RDX:RAX by reg
  /// Result: quotient in RAX, remainder in RDX
  void idiv(Object src) => emit(X86InstId.kIdiv, [src]);

  /// DIV reg - Unsigned divide RDX:RAX by reg
  /// Result: quotient in RAX, remainder in RDX
  void div(Object src) => emit(X86InstId.kDiv, [src]);

  // ===========================================================================
  // High-precision arithmetic (for cryptography)
  // ===========================================================================

  /// ADC dst, src - Add with carry
  void adcRR(X86Gp dst, X86Gp src) => emit(X86InstId.kAdc, [dst, src]);

  /// ADC dst, imm - Add with carry
  void adcRI(X86Gp dst, int imm) => emit(X86InstId.kAdc, [dst, imm]);

  /// ADC dst, [mem] - Add with carry (register <- register + memory)
  void adcRM(X86Gp dst, X86Mem src) => emit(X86InstId.kAdc, [dst, src]);

  /// ADC [mem], src - Add with carry (memory <- memory + register)
  void adcMR(X86Mem dst, X86Gp src) => emit(X86InstId.kAdc, [dst, src]);

  /// ADC [mem], imm - Add with carry (memory <- memory + immediate)
  void adcMI(X86Mem dst, int imm) => emit(X86InstId.kAdc, [dst, imm]);

  /// SBB dst, imm - Subtract with borrow
  void sbbRI(X86Gp dst, int imm) => emit(X86InstId.kSbb, [dst, imm]);

  /// SBB dst, [mem] - Subtract with borrow (register <- register - memory)
  void sbbRM(X86Gp dst, X86Mem src) => emit(X86InstId.kSbb, [dst, src]);

  /// MUL src - Unsigned multiply RDX:RAX = RAX * src
  void mul(Object src) => emit(X86InstId.kMul, [src]);

  /// ROL/ROR/SHL/SHR/SAR by CL.
  void rolRCl(X86Gp reg) => emit(X86InstId.kRol, [reg, cl]);
  void rorRCl(X86Gp reg) => emit(X86InstId.kRor, [reg, cl]);

  /// BSR/BSF/LZCNT/TZCNT/POPCNT reg, r/m.
  void bsr(X86Gp dst, Object src) => emit(X86InstId.kBsr, [dst, src]);
  void bsf(X86Gp dst, Object src) => emit(X86InstId.kBsf, [dst, src]);
  void lzcnt(X86Gp dst, Object src) => emit(X86InstId.kLzcnt, [dst, src]);
  void tzcnt(X86Gp dst, Object src) => emit(X86InstId.kTzcnt, [dst, src]);
  void popcnt(X86Gp dst, Object src) => emit(X86InstId.kPopcnt, [dst, src]);

  /// IMUL reg, [mem], imm.
  void imulRMI(X86Gp dst, X86Mem src, int imm) =>
      emit(X86InstId.kImul, [dst, src, imm]);

  /// IMUL reg, [mem].
  void imulRM(X86Gp dst, X86Mem src) => emit(X86InstId.kImul, [dst, src]);

  /// MOVBE reg, [mem].
  void movbe(X86Gp dst, X86Mem src) => emit(X86InstId.kMovbe, [dst, src]);

  /// BSWAP reg.
  void bswap(X86Gp reg) => emit(X86InstId.kBswap, [reg]);

  /// BT r/m, reg and BT r/m, imm8.
  void bt(Object dst, X86Gp bit) => emit(X86InstId.kBt, [dst, bit]);
  void btI(X86Gp dst, int bit) => emit(X86InstId.kBt, [dst, bit]);

  /// SBB reg, reg.
  void sbbRR(X86Gp dst, X86Gp src) => emit(X86InstId.kSbb, [dst, src]);

  /// PREFETCHT0 [mem].
  void prefetcht0(X86Mem mem) => emit(X86InstId.kPrefetcht0, [mem]);

  /// BMI: ANDN dst, src1, src2 (dst = ~src1 & src2).
  void andn(X86Gp dst, X86Gp src1, Object src2) =>
      emit(X86InstId.kAndn, [dst, src1, src2]);

  /// BMI2: SHLX/SHRX/SARX dst, src, count.
  void shlx(X86Gp dst, Object src, X86Gp count) =>
      emit(X86InstId.kShlx, [dst, src, count]);
  void shrx(X86Gp dst, Object src, X86Gp count) =>
      emit(X86InstId.kShrx, [dst, src, count]);
  void sarx(X86Gp dst, Object src, X86Gp count) =>
      emit(X86InstId.kSarx, [dst, src, count]);

  /// MULX hi, lo, src (BMI2) - Unsigned multiply without flags
  void mulx(X86Gp hi, X86Gp lo, X86Gp src) =>
      emit(X86InstId.kMulx, [hi, lo, src]);

  // ==========================================================================
  // BMI2
  // ==========================================================================

  /// BZHI dst, src, idx (BMI2) - Zero high bits starting from idx.
  void bzhi(X86Gp dst, X86Gp src, X86Gp idx) =>
      emit(X86InstId.kBzhi, [dst, src, idx]);

  /// PDEP dst, src, mask (BMI2) - Parallel bit deposit.
  void pdep(X86Gp dst, X86Gp src, X86Gp mask) =>
      emit(X86InstId.kPdep, [dst, src, mask]);

  /// PEXT dst, src, mask (BMI2) - Parallel bit extract.
  void pext(X86Gp dst, X86Gp src, X86Gp mask) =>
      emit(X86InstId.kPext, [dst, src, mask]);

  /// RORX dst, src, imm8 (BMI2) - Rotate right without affecting flags.
  void rorx(X86Gp dst, Object src, int imm8) =>
      emit(X86InstId.kRorx, [dst, src, imm8]);

  /// ADCX dst, src (ADX) - Add with carry (uses CF only)
  void adcx(X86Gp dst, X86Gp src) => emit(X86InstId.kAdcx, [dst, src]);

  /// ADOX dst, src (ADX) - Add with overflow (uses OF only)
  void adox(X86Gp dst, X86Gp src) => emit(X86InstId.kAdox, [dst, src]);

  // ===========================================================================
  // Flag manipulation
  // ===========================================================================

  /// CLC - Clear carry flag
  void clc() => emit(X86InstId.kClc, []);

  /// STC - Set carry flag
  void stc() => emit(X86InstId.kStc, []);

  /// CMC - Complement carry flag
  void cmc() => emit(X86InstId.kCmc, []);

  /// CLD - Clear direction flag
  void cld() => emit(X86InstId.kCld, []);

  /// STD - Set direction flag (use with caution)
  void std() => emit(X86InstId.kStd, []);

  // ===========================================================================
  // String operations
  // ===========================================================================

  /// REP MOVSB - Copy RCX bytes from [RSI] to [RDI]
  void repMovsb() => _repString(X86InstId.kMovs, 1);

  /// REP MOVSQ - Copy RCX qwords from [RSI] to [RDI]
  void repMovsq() => _repString(X86InstId.kMovs, 8);

  /// REP STOSB - Store AL to RCX bytes at [RDI]
  void repStosb() => _repString(X86InstId.kStos, 1);

  /// REP STOSQ - Store RAX to RCX qwords at [RDI]
  void repStosq() => _repString(X86InstId.kStos, 8);

  /// `rep(zcx).movs(ptr_zdi, ptr_zsi)` / `rep(zcx).stos(ptr_zdi, zax)` of
  /// [size] bytes, as upstream's `movsb()`... aliases (x86emitter.h).
  void _repString(int instId, int size) {
    final zdi = is64Bit ? rdi : edi;
    final zsi = is64Bit ? rsi : esi;
    final dst = X86Mem.base(zdi, size: size);
    instOptions |= X86EmitOptions.kX86_Rep;
    extraReg = is64Bit ? rcx : ecx;
    emit(
        instId,
        instId == X86InstId.kMovs
            ? [dst, X86Mem.base(zsi, size: size)]
            : [dst, size == 8 ? rax : al]);
  }

  // ===========================================================================
  // Memory fences
  // ===========================================================================

  /// MFENCE - Full memory fence
  void mfence() => emit(X86InstId.kMfence, []);

  /// SFENCE - Store fence
  void sfence() => emit(X86InstId.kSfence, []);

  /// LFENCE - Load fence
  void lfence() => emit(X86InstId.kLfence, []);

  /// PAUSE - Spin loop hint
  void pause() => emit(X86InstId.kPause, []);

  // ===========================================================================
  // SSE/SSE2 - Move instructions
  // ===========================================================================

  /// MOVAPS xmm, xmm (move aligned packed single-precision)
  void movapsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMovaps, [dst, src]);

  /// MOVUPS xmm, xmm (move unaligned packed single-precision)
  void movupsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMovups, [dst, src]);

  /// MOVUPS xmm, [mem]
  void movupsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kMovups, [dst, mem]);

  /// MOVUPS [mem], xmm
  void movupsMX(X86Mem mem, X86Xmm src) => emit(X86InstId.kMovups, [mem, src]);

  /// MOVAPS xmm, [mem]
  void movapsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kMovaps, [dst, mem]);

  /// MOVAPS [mem], xmm
  void movapsMX(X86Mem mem, X86Xmm src) => emit(X86InstId.kMovaps, [mem, src]);

  /// MOVD xmm, [mem]
  void movdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kMovd, [dst, mem]);

  /// MOVD [mem], xmm
  void movdMX(X86Mem mem, X86Xmm src) => emit(X86InstId.kMovd, [mem, src]);

  /// MOVSD xmm, xmm (move scalar double-precision)
  void movsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMovsd, [dst, src]);

  /// MOVSD xmm, [mem]
  void movsdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kMovsd, [dst, mem]);

  /// MOVSD [mem], xmm
  void movsdMX(X86Mem mem, X86Xmm src) => emit(X86InstId.kMovsd, [mem, src]);

  /// MOVSS xmm, xmm (move scalar single-precision)
  void movssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMovss, [dst, src]);

  /// MOVSS xmm, [mem]
  void movssXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kMovss, [dst, mem]);

  /// MOVSS [mem], xmm
  void movssMX(X86Mem mem, X86Xmm src) => emit(X86InstId.kMovss, [mem, src]);

  // ===========================================================================
  // SSE/SSE2 - Arithmetic (scalar double)
  // ===========================================================================

  /// ADDSD xmm, xmm (add scalar double)
  void addsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kAddsd, [dst, src]);

  /// SUBSD xmm, xmm (subtract scalar double)
  void subsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSubsd, [dst, src]);

  /// MULSD xmm, xmm (multiply scalar double)
  void mulsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMulsd, [dst, src]);

  /// DIVSD xmm, xmm (divide scalar double)
  void divsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kDivsd, [dst, src]);

  /// SQRTSD xmm, xmm (square root scalar double)
  void sqrtsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSqrtsd, [dst, src]);

  /// ADDSD xmm, [mem]
  void addsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kAddsd, [dst, src]);

  /// SUBSD xmm, [mem]
  void subsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kSubsd, [dst, src]);

  /// MULSD xmm, [mem]
  void mulsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMulsd, [dst, src]);

  /// DIVSD xmm, [mem]
  void divsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kDivsd, [dst, src]);

  /// SQRTSD xmm, [mem]
  void sqrtsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kSqrtsd, [dst, src]);

  // ===========================================================================
  // SSE/SSE2 - Arithmetic (scalar single)
  // ===========================================================================

  /// ADDSS xmm, xmm (add scalar single)
  void addssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kAddss, [dst, src]);

  /// SUBSS xmm, xmm (subtract scalar single)
  void subssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSubss, [dst, src]);

  /// MULSS xmm, xmm (multiply scalar single)
  void mulssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMulss, [dst, src]);

  /// DIVSS xmm, xmm (divide scalar single)
  void divssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kDivss, [dst, src]);

  /// SQRTSS xmm, xmm (square root scalar single)
  void sqrtssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSqrtss, [dst, src]);

  /// ADDSS xmm, [mem]
  void addssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kAddss, [dst, src]);

  /// SUBSS xmm, [mem]
  void subssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kSubss, [dst, src]);

  /// MULSS xmm, [mem]
  void mulssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMulss, [dst, src]);

  /// DIVSS xmm, [mem]
  void divssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kDivss, [dst, src]);

  /// SQRTSS xmm, [mem]
  void sqrtssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kSqrtss, [dst, src]);

  // SSE/SSE2 - Scalar Min/Max and Reciprocal
  /// MINSD xmm, xmm
  void minsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMinsd, [dst, src]);
  void minsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMinsd, [dst, src]);

  /// MINSS xmm, xmm
  void minssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMinss, [dst, src]);
  void minssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMinss, [dst, src]);

  /// MAXSD xmm, xmm
  void maxsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMaxsd, [dst, src]);
  void maxsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMaxsd, [dst, src]);

  /// MAXSS xmm, xmm
  void maxssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMaxss, [dst, src]);
  void maxssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMaxss, [dst, src]);

  /// RCPSS xmm, xmm
  void rcpssXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kRcpss, [dst, src]);
  void rcpssXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kRcpss, [dst, src]);

  /// RSQRTSS xmm, xmm
  void rsqrtssXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kRsqrtss, [dst, src]);
  void rsqrtssXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kRsqrtss, [dst, src]);

  // ===========================================================================
  // SSE/SSE2 - Packed single-precision arithmetic
  // ===========================================================================

  /// ADDPS xmm, xmm (add packed single)
  void addps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kAddps, [dst, src]);

  /// ADDPS xmm, [mem]
  void addpsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kAddps, [dst, mem]);

  /// SUBPS xmm, xmm (subtract packed single)
  void subps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSubps, [dst, src]);

  /// SUBPS xmm, [mem]
  void subpsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kSubps, [dst, mem]);

  /// MULPS xmm, xmm (multiply packed single)
  void mulps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMulps, [dst, src]);

  /// MULPS xmm, [mem]
  void mulpsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kMulps, [dst, mem]);

  /// DIVPS xmm, xmm (divide packed single)
  void divps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kDivps, [dst, src]);

  /// DIVPS xmm, [mem]
  void divpsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kDivps, [dst, mem]);

  /// ADDPD xmm, xmm (add packed double)
  void addpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kAddpd, [dst, src]);
  void addpdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kAddpd, [dst, mem]);

  /// SUBPD xmm, xmm (subtract packed double)
  void subpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSubpd, [dst, src]);
  void subpdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kSubpd, [dst, mem]);

  /// MULPD xmm, xmm (multiply packed double)
  void mulpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMulpd, [dst, src]);
  void mulpdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kMulpd, [dst, mem]);

  /// DIVPD xmm, xmm (divide packed double)
  void divpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kDivpd, [dst, src]);
  void divpdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kDivpd, [dst, mem]);

  /// MINPS xmm, xmm (minimum packed single)
  void minps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMinps, [dst, src]);

  /// MAXPS xmm, xmm (maximum packed single)
  void maxps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMaxps, [dst, src]);

  /// RCPPS xmm, xmm
  void rcppsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kRcpps, [dst, src]);

  /// RCPPS xmm, [mem]
  void rcppsXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kRcpps, [dst, src]);

  /// RSQRTPS xmm, xmm
  void rsqrtpsXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kRsqrtps, [dst, src]);

  /// RSQRTPS xmm, [mem]
  void rsqrtpsXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kRsqrtps, [dst, src]);

  /// SQRTPS xmm, xmm
  void sqrtpsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSqrtps, [dst, src]);

  /// SQRTPS xmm, [mem]
  void sqrtpsXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kSqrtps, [dst, src]);

  /// SQRTPD xmm, xmm
  void sqrtpdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSqrtpd, [dst, src]);

  /// SQRTPD xmm, [mem]
  void sqrtpdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kSqrtpd, [dst, src]);

  /// SQRTPS xmm, xmm (alias)
  void sqrtps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSqrtps, [dst, src]);

  /// SQRTPD xmm, xmm (alias)
  void sqrtpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kSqrtpd, [dst, src]);

  /// RCPPS xmm, xmm (alias)
  void rcpps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kRcpps, [dst, src]);

  /// RSQRTPS xmm, xmm (alias)
  void rsqrtps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kRsqrtps, [dst, src]);

  /// MINPS xmm, xmm
  void minpsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMinps, [dst, src]);

  /// MINPS xmm, [mem]
  void minpsXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMinps, [dst, src]);

  /// MINPD xmm, xmm
  void minpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMinpd, [dst, src]);
  void minpdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMinpd, [dst, src]);

  /// MINPD xmm, [mem]
  void minpdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMinpd, [dst, src]);

  /// MAXPS xmm, xmm
  void maxpsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMaxps, [dst, src]);

  /// MAXPS xmm, [mem]
  void maxpsXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMaxps, [dst, src]);

  /// MAXPD xmm, xmm
  void maxpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMaxpd, [dst, src]);
  void maxpdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMaxpd, [dst, src]);

  /// MAXPD xmm, [mem]
  void maxpdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMaxpd, [dst, src]);

  // ===========================================================================
  // SSE/SSE2 - Logical (convenience aliases)
  // ===========================================================================

  /// XORPS xmm, xmm (XOR packed single) - also used to zero registers
  void xorps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kXorps, [dst, src]);

  // ===========================================================================
  // SSE/SSE2 - Logical
  // ===========================================================================

  /// PXOR xmm, xmm (packed XOR, zero register: pxor xmm, xmm)
  void pxor(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPxor, [dst, src]);
  void pxorXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPxor, [dst, src]);

  /// PXOR xmm, [mem]
  void pxorXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kPxor, [dst, mem]);

  /// XORPS xmm, xmm (XOR packed single)
  void xorpsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kXorps, [dst, src]);

  /// XORPS xmm, [mem]
  void xorpsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kXorps, [dst, mem]);

  /// XORPD xmm, xmm (XOR packed double)
  void xorpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kXorpd, [dst, src]);
  void xorpdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kXorpd, [dst, src]);

  /// XORPD xmm, [mem]
  void xorpdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kXorpd, [dst, mem]);

  // ===========================================================================
  // SSE/SSE2 - Conversion
  // ===========================================================================

  /// CVTSI2SD xmm, r64 (convert int64 to double)
  void cvtsi2sdXR(X86Xmm dst, X86Gp src) =>
      emit(X86InstId.kCvtsi2sd, [dst, src]);

  /// CVTSI2SS xmm, r64 (convert int64 to float)
  void cvtsi2ssXR(X86Xmm dst, X86Gp src) =>
      emit(X86InstId.kCvtsi2ss, [dst, src]);

  /// CVTTSD2SI r64, xmm (convert double to int64 with truncation)
  void cvttsd2siRX(X86Gp dst, X86Xmm src) =>
      emit(X86InstId.kCvttsd2si, [dst, src]);

  /// CVTTSS2SI r64, xmm (convert float to int64 with truncation)
  void cvttss2siRX(X86Gp dst, X86Xmm src) =>
      emit(X86InstId.kCvttss2si, [dst, src]);

  /// CVTSD2SS xmm, xmm (convert double to float)
  void cvtsd2ssXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kCvtsd2ss, [dst, src]);

  /// CVTSS2SD xmm, xmm (convert float to double)
  void cvtss2sdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kCvtss2sd, [dst, src]);

  /// CVTSD2SS xmm, [mem] (convert double to float)
  void cvtsd2ssXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kCvtsd2ss, [dst, src]);

  /// CVTSS2SD xmm, [mem] (convert float to double)
  void cvtss2sdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kCvtss2sd, [dst, src]);

  /// CVTDQ2PS xmm, xmm
  void cvtdq2psXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kCvtdq2ps, [dst, src]);

  /// CVTDQ2PS xmm, [mem]
  void cvtdq2psXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kCvtdq2ps, [dst, src]);

  /// CVTPS2DQ xmm, xmm
  void cvtps2dqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kCvtps2dq, [dst, src]);

  /// CVTPS2DQ xmm, [mem]
  void cvtps2dqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kCvtps2dq, [dst, src]);

  /// CVTTPS2DQ xmm, xmm
  void cvttps2dqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kCvttps2dq, [dst, src]);

  /// CVTTPS2DQ xmm, [mem]
  void cvttps2dqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kCvttps2dq, [dst, src]);

  /// CVTSI2SD xmm, [mem] (convert int32/64 to double)
  void cvtsi2sdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kCvtsi2sd, [dst, src]);

  /// CVTSI2SS xmm, [mem] (convert int32/64 to float)
  void cvtsi2ssXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kCvtsi2ss, [dst, src]);

  // ===========================================================================
  // SSE/SSE2 - Comparison
  // ===========================================================================

  /// COMISD xmm, xmm (ordered compare double, set EFLAGS)
  void comisdXX(X86Xmm a, X86Xmm b) => emit(X86InstId.kComisd, [a, b]);

  /// COMISS xmm, xmm (ordered compare single, set EFLAGS)
  void comissXX(X86Xmm a, X86Xmm b) => emit(X86InstId.kComiss, [a, b]);

  /// UCOMISD xmm, xmm (unordered compare double, set EFLAGS)
  void ucomisdXX(X86Xmm a, X86Xmm b) => emit(X86InstId.kUcomisd, [a, b]);

  /// UCOMISS xmm, xmm (unordered compare single, set EFLAGS)
  void ucomissXX(X86Xmm a, X86Xmm b) => emit(X86InstId.kUcomiss, [a, b]);

  /// CMPPS xmm, xmm, imm8
  void cmppsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kCmpps, [dst, src, imm8]);

  /// CMPPS xmm, [mem], imm8
  void cmppsXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kCmpps, [dst, src, imm8]);

  /// CMPPD xmm, xmm, imm8
  void cmppdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kCmppd, [dst, src, imm8]);

  /// CMPPD xmm, [mem], imm8
  void cmppdXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kCmppd, [dst, src, imm8]);

  /// CMPSS xmm, xmm, imm8
  void cmpssXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kCmpss, [dst, src, imm8]);

  /// CMPSS xmm, [mem], imm8
  void cmpssXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kCmpss, [dst, src, imm8]);

  /// CMPSD xmm, xmm, imm8
  void cmpsdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kCmpsd, [dst, src, imm8]);

  /// CMPSD xmm, [mem], imm8
  void cmpsdXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kCmpsd, [dst, src, imm8]);

  // ===========================================================================
  // SSE/SSE2 - GP <-> XMM Transfer
  // ===========================================================================

  /// MOVQ xmm, r64 (move quadword from GP to XMM)
  void movqXR(X86Xmm dst, X86Gp src) => emit(X86InstId.kMovq, [dst, src]);

  /// MOVQ r64, xmm (move quadword from XMM to GP)
  void movqRX(X86Gp dst, X86Xmm src) => emit(X86InstId.kMovq, [dst, src]);

  /// MOVQ xmm, m64
  void movqXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMovq, [dst, src]);

  /// MOVQ m64, xmm
  void movqMX(X86Mem dst, X86Xmm src) => emit(X86InstId.kMovq, [dst, src]);

  /// MOVD xmm, r32 (move doubleword from GP to XMM)
  void movdXR(X86Xmm dst, X86Gp src) => emit(X86InstId.kMovd, [dst, src]);

  /// MOVD r32, xmm (move doubleword from XMM to GP)
  void movdRX(X86Gp dst, X86Xmm src) => emit(X86InstId.kMovd, [dst, src]);

  /// KMOVW k, r32 (move 16-bit from GP to mask)
  void kmovwKR(X86KReg dst, X86Gp src) => emit(X86InstId.kKmovw, [dst, src]);

  /// KMOVW r32, k (move 16-bit from mask to GP)
  void kmovwRK(X86Gp dst, X86KReg src) => emit(X86InstId.kKmovw, [dst, src]);

  /// KMOVD k, r32 (move 32-bit from GP to mask)
  void kmovdKR(X86KReg dst, X86Gp src) => emit(X86InstId.kKmovd, [dst, src]);

  /// KMOVD r32, k (move 32-bit from mask to GP)
  void kmovdRK(X86Gp dst, X86KReg src) => emit(X86InstId.kKmovd, [dst, src]);

  /// KMOVQ k, r64 (move 64-bit from GP to mask)
  void kmovqKR(X86KReg dst, X86Gp src) => emit(X86InstId.kKmovq, [dst, src]);

  /// KMOVQ r64, k (move 64-bit from mask to GP)
  void kmovqRK(X86Gp dst, X86KReg src) => emit(X86InstId.kKmovq, [dst, src]);

  // ===========================================================================
  // AVX - Move instructions (VEX-encoded)
  // ===========================================================================

  /// VMOVAPS xmm, xmm (VEX move aligned packed single 128-bit)
  void vmovapsXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVmovaps, [dst, src]);

  /// VMOVAPS ymm, ymm (VEX move aligned packed single 256-bit)
  void vmovapsYY(X86Ymm dst, X86Ymm src) =>
      emit(X86InstId.kVmovaps, [dst, src]);

  /// VMOVUPS xmm, xmm (VEX move unaligned packed single 128-bit)
  void vmovupsXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVmovups, [dst, src]);

  /// VMOVUPS ymm, ymm (VEX move unaligned packed single 256-bit)
  void vmovupsYY(X86Ymm dst, X86Ymm src) =>
      emit(X86InstId.kVmovups, [dst, src]);

  /// VMOVD xmm, r32
  void vmovdXR(X86Xmm dst, X86Gp src) => emit(X86InstId.kVmovd, [dst, src]);

  /// VMOVD r32, xmm
  void vmovdRX(X86Gp dst, X86Xmm src) => emit(X86InstId.kVmovd, [dst, src]);

  /// VMOVD xmm, [mem]
  void vmovdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kVmovd, [dst, src]);

  /// VMOVD [mem], xmm
  void vmovdMX(X86Mem dst, X86Xmm src) => emit(X86InstId.kVmovd, [dst, src]);

  /// VMOVQ xmm, r64
  void vmovqXR(X86Xmm dst, X86Gp src) => emit(X86InstId.kVmovq, [dst, src]);

  /// VMOVQ r64, xmm
  void vmovqRX(X86Gp dst, X86Xmm src) => emit(X86InstId.kVmovq, [dst, src]);

  /// VMOVQ xmm, [mem]
  void vmovqXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kVmovq, [dst, src]);

  /// VMOVQ [mem], xmm
  void vmovqMX(X86Mem dst, X86Xmm src) => emit(X86InstId.kVmovq, [dst, src]);

  /// VBROADCASTSS xmm, mem32
  void vbroadcastssXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVbroadcastss, [dst, mem]);

  /// VBROADCASTSS ymm, mem32
  void vbroadcastssYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVbroadcastss, [dst, mem]);

  /// VBROADCASTSD ymm, mem64
  void vbroadcastsdYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVbroadcastsd, [dst, mem]);

  /// VPBROADCASTB xmm, xmm
  void vpbroadcastbXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastb, [dst, src]);
  void vpbroadcastbXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastb, [dst, mem]);

  /// VPBROADCASTW xmm, xmm
  void vpbroadcastwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastw, [dst, src]);
  void vpbroadcastwXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastw, [dst, mem]);

  /// VPBROADCASTD xmm, xmm
  void vpbroadcastdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastd, [dst, src]);
  void vpbroadcastdXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastd, [dst, mem]);

  /// VPBROADCASTQ xmm, xmm
  void vpbroadcastqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastq, [dst, src]);
  void vpbroadcastqXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastq, [dst, mem]);

  /// VPBROADCASTB ymm, xmm
  void vpbroadcastbYX(X86Ymm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastb, [dst, src]);
  void vpbroadcastbYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastb, [dst, mem]);

  /// VPBROADCASTW ymm, xmm
  void vpbroadcastwYX(X86Ymm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastw, [dst, src]);
  void vpbroadcastwYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastw, [dst, mem]);

  /// VPBROADCASTD ymm, xmm
  void vpbroadcastdYX(X86Ymm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastd, [dst, src]);
  void vpbroadcastdYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastd, [dst, mem]);

  /// VPBROADCASTQ ymm, xmm
  void vpbroadcastqYX(X86Ymm dst, X86Xmm src) =>
      emit(X86InstId.kVpbroadcastq, [dst, src]);
  void vpbroadcastqYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVpbroadcastq, [dst, mem]);

  // ===========================================================================
  // AVX - Scalar arithmetic (VEX-encoded)
  // ===========================================================================

  /// VADDSD xmm, xmm, xmm (VEX add scalar double)
  void vaddsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVaddsd, [dst, src1, src2]);

  /// VSUBSD xmm, xmm, xmm (VEX subtract scalar double)
  void vsubsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVsubsd, [dst, src1, src2]);

  /// VMULSD xmm, xmm, xmm (VEX multiply scalar double)
  void vmulsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmulsd, [dst, src1, src2]);

  /// VDIVSD xmm, xmm, xmm (VEX divide scalar double)
  void vdivsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVdivsd, [dst, src1, src2]);

  /// VADDSD xmm, xmm, [mem]
  void vaddsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVaddsd, [dst, src1, mem]);

  /// VSUBSD xmm, xmm, [mem]
  void vsubsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVsubsd, [dst, src1, mem]);

  /// VMULSD xmm, xmm, [mem]
  void vmulsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmulsd, [dst, src1, mem]);

  /// VDIVSD xmm, xmm, [mem]
  void vdivsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVdivsd, [dst, src1, mem]);

  // ===========================================================================
  // AVX - Scalar arithmetic (Single Precision)
  // ===========================================================================

  /// VADDSS xmm, xmm, xmm
  void vaddssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVaddss, [dst, src1, src2]);
  void vaddssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVaddss, [dst, src1, mem]);

  /// VSUBSS xmm, xmm, xmm
  void vsubssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVsubss, [dst, src1, src2]);
  void vsubssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVsubss, [dst, src1, mem]);

  /// VMULSS xmm, xmm, xmm
  void vmulssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmulss, [dst, src1, src2]);
  void vmulssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmulss, [dst, src1, mem]);

  /// VDIVSS xmm, xmm, xmm
  void vdivssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVdivss, [dst, src1, src2]);
  void vdivssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVdivss, [dst, src1, mem]);

  // ===========================================================================
  // AVX - Math (SQRT, MIN, MAX)
  // ===========================================================================

  /// VSQRTPS xmm, xmm
  void vsqrtpsXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVsqrtps, [dst, src]);
  void vsqrtpsXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVsqrtps, [dst, mem]);

  /// VSQRTPD xmm, xmm
  void vsqrtpdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVsqrtpd, [dst, src]);
  void vsqrtpdXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVsqrtpd, [dst, mem]);

  /// VSQRTPS ymm, ymm
  void vsqrtpsYY(X86Ymm dst, X86Ymm src) =>
      emit(X86InstId.kVsqrtps, [dst, src]);
  void vsqrtpsYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVsqrtps, [dst, mem]);

  /// VSQRTPD ymm, ymm
  void vsqrtpdYY(X86Ymm dst, X86Ymm src) =>
      emit(X86InstId.kVsqrtpd, [dst, src]);
  void vsqrtpdYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVsqrtpd, [dst, mem]);

  /// VRSQRTPS xmm, xmm
  void vrsqrtpsXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVrsqrtps, [dst, src]);
  void vrsqrtpsXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVrsqrtps, [dst, mem]);

  /// VRSQRTPS ymm, ymm
  void vrsqrtpsYY(X86Ymm dst, X86Ymm src) =>
      emit(X86InstId.kVrsqrtps, [dst, src]);
  void vrsqrtpsYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVrsqrtps, [dst, mem]);

  /// VRCPPS xmm, xmm
  void vrcppsXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kVrcpps, [dst, src]);
  void vrcppsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kVrcpps, [dst, mem]);

  /// VRCPPS ymm, ymm
  void vrcppsYY(X86Ymm dst, X86Ymm src) => emit(X86InstId.kVrcpps, [dst, src]);
  void vrcppsYM(X86Ymm dst, X86Mem mem) => emit(X86InstId.kVrcpps, [dst, mem]);

  /// VSQRTSS xmm, xmm, xmm
  void vsqrtssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVsqrtss, [dst, src1, src2]);
  void vsqrtssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVsqrtss, [dst, src1, mem]);

  /// VSQRTSD xmm, xmm, xmm
  void vsqrtsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVsqrtsd, [dst, src1, src2]);
  void vsqrtsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVsqrtsd, [dst, src1, mem]);

  /// VMINPS xmm, xmm, xmm
  void vminpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVminps, [dst, src1, src2]);
  void vminpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVminps, [dst, src1, mem]);

  /// VMINPD xmm, xmm, xmm
  void vminpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVminpd, [dst, src1, src2]);
  void vminpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVminpd, [dst, src1, mem]);

  /// VMINPS ymm, ymm, ymm
  void vminpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVminps, [dst, src1, src2]);
  void vminpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVminps, [dst, src1, mem]);

  /// VMINPD ymm, ymm, ymm
  void vminpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVminpd, [dst, src1, src2]);
  void vminpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVminpd, [dst, src1, mem]);

  /// VMINSS xmm, xmm, xmm
  void vminssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVminss, [dst, src1, src2]);
  void vminssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVminss, [dst, src1, mem]);

  /// VMINSD xmm, xmm, xmm
  void vminsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVminsd, [dst, src1, src2]);
  void vminsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVminsd, [dst, src1, mem]);

  /// VMAXPS xmm, xmm, xmm
  void vmaxpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmaxps, [dst, src1, src2]);
  void vmaxpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmaxps, [dst, src1, mem]);

  /// VMAXPD xmm, xmm, xmm
  void vmaxpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmaxpd, [dst, src1, src2]);
  void vmaxpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmaxpd, [dst, src1, mem]);

  /// VMAXPS ymm, ymm, ymm
  void vmaxpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVmaxps, [dst, src1, src2]);
  void vmaxpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVmaxps, [dst, src1, mem]);

  /// VMAXPD ymm, ymm, ymm
  void vmaxpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVmaxpd, [dst, src1, src2]);
  void vmaxpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVmaxpd, [dst, src1, mem]);

  /// VMAXSS xmm, xmm, xmm
  void vmaxssXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmaxss, [dst, src1, src2]);
  void vmaxssXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmaxss, [dst, src1, mem]);

  /// VMAXSD xmm, xmm, xmm
  void vmaxsdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmaxsd, [dst, src1, src2]);
  void vmaxsdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmaxsd, [dst, src1, mem]);

  // ===========================================================================
  // AVX - Shuffle / Permute
  // ===========================================================================

  /// VSHUFPS xmm, xmm, xmm, imm8
  void vshufpsXXXI(X86Xmm dst, X86Xmm src1, X86Xmm src2, int imm8) =>
      emit(X86InstId.kVshufps, [dst, src1, src2, imm8]);

  /// VSHUFPD xmm, xmm, xmm, imm8
  void vshufpdXXXI(X86Xmm dst, X86Xmm src1, X86Xmm src2, int imm8) =>
      emit(X86InstId.kVshufpd, [dst, src1, src2, imm8]);

  /// VPERMILPS xmm, xmm, imm8
  void vpermilpsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kVpermilps, [dst, src, imm8]);

  /// VPERMILPD xmm, xmm, imm8
  void vpermilpdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kVpermilpd, [dst, src, imm8]);

  /// VPERMD ymm, ymm, ymm (AVX2)
  void vpermdYYY(X86Ymm dst, X86Ymm idx, X86Ymm src) =>
      emit(X86InstId.kVpermd, [dst, idx, src]);

  /// VPERMQ ymm, ymm, imm8 (AVX2)
  void vpermqYYI(X86Ymm dst, X86Ymm src, int imm8) =>
      emit(X86InstId.kVpermq, [dst, src, imm8]);

  /// VPERM2F128 ymm, ymm, ymm, imm8
  void vperm2f128YYYI(X86Ymm dst, X86Ymm src1, X86Ymm src2, int imm8) =>
      emit(X86InstId.kVperm2f128, [dst, src1, src2, imm8]);

  /// VPERM2I128 ymm, ymm, ymm, imm8 (AVX2)
  void vperm2i128YYYI(X86Ymm dst, X86Ymm src1, X86Ymm src2, int imm8) =>
      emit(X86InstId.kVperm2i128, [dst, src1, src2, imm8]);

  // ===========================================================================
  // AVX - Insert/Extract
  // ===========================================================================

  /// VINSERTF128 ymm, ymm, xmm, imm8
  void vinsertf128YYXI(X86Ymm dst, X86Ymm src1, X86Xmm src2, int imm8) =>
      emit(X86InstId.kVinsertf128, [dst, src1, src2, imm8]);

  /// VEXTRACTF128 xmm, ymm, imm8
  void vextractf128XYI(X86Xmm dst, X86Ymm src, int imm8) =>
      emit(X86InstId.kVextractf128, [dst, src, imm8]);

  /// VINSERTI128 ymm, ymm, xmm, imm8 (AVX2)
  void vinserti128YYXI(X86Ymm dst, X86Ymm src1, X86Xmm src2, int imm8) =>
      emit(X86InstId.kVinserti128, [dst, src1, src2, imm8]);

  /// VEXTRACTI128 xmm, ymm, imm8
  void vextracti128XYI(X86Xmm dst, X86Ymm src, int imm8) =>
      emit(X86InstId.kVextracti128, [dst, src, imm8]);

  // ===========================================================================
  // AVX - Masked Move
  // ===========================================================================

  /// VPMASKMOVD xmm, xmm, mem (Load)
  void vpmaskmovdLoadXXM(X86Xmm dst, X86Xmm mask, X86Mem mem) =>
      emit(X86InstId.kVpmaskmovd, [dst, mask, mem]);

  /// VPMASKMOVD mem, xmm, xmm (Store)
  // Note: Arguments are mem, mask, src (to match encoder logic)
  void vpmaskmovdStoreMXX(X86Mem mem, X86Xmm mask, X86Xmm src) =>
      emit(X86InstId.kVpmaskmovd, [mem, mask, src]);

  // ===========================================================================
  // AVX2 - Gather Instructions
  // ===========================================================================

  /// VGATHERDPS xmm, [mem], xmm
  void vgatherdpsXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      emit(X86InstId.kVgatherdps, [dst, mem, mask]);

  /// VGATHERDPS ymm, [mem], ymm
  void vgatherdpsYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      emit(X86InstId.kVgatherdps, [dst, mem, mask]);

  /// VGATHERDPD xmm, [mem], xmm
  void vgatherdpdXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      emit(X86InstId.kVgatherdpd, [dst, mem, mask]);

  /// VGATHERDPD ymm, [mem], ymm
  void vgatherdpdYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      emit(X86InstId.kVgatherdpd, [dst, mem, mask]);

  /// VGATHERQPS xmm, [mem], xmm
  void vgatherqpsXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      emit(X86InstId.kVgatherqps, [dst, mem, mask]);

  /// VGATHERQPS ymm, [mem], ymm
  void vgatherqpsYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      emit(X86InstId.kVgatherqps, [dst, mem, mask]);

  /// VGATHERQPD xmm, [mem], xmm
  void vgatherqpdXMX(X86Xmm dst, X86Mem mem, X86Xmm mask) =>
      emit(X86InstId.kVgatherqpd, [dst, mem, mask]);

  /// VGATHERQPD ymm, [mem], ymm
  void vgatherqpdYMY(X86Ymm dst, X86Mem mem, X86Ymm mask) =>
      emit(X86InstId.kVgatherqpd, [dst, mem, mask]);

  // ===========================================================================
  // AVX-512 - Mask Instructions
  // ===========================================================================

  /// KMOVW k, k
  void kmovwKK(X86KReg dst, X86KReg src) => emit(X86InstId.kKmovw, [dst, src]);

  // ===========================================================================
  // AVX-512 - Packed arithmetic
  // ===========================================================================

  /// VPADDD zmm, zmm, zmm
  void vpadddZmmZmmZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVpaddd, [dst, src1, src2]);

  /// VPADDD zmm, zmm, zmm {k}
  void vpadddZmmZmmZmmK(X86Zmm dst, X86Zmm src1, X86Zmm src2, X86KReg k) {
    extraReg = k;
    emit(X86InstId.kVpaddd, [dst, src1, src2]);
  }

  /// VPADDD zmm, zmm, zmm {k}{z}
  void vpadddZmmZmmZmmKz(X86Zmm dst, X86Zmm src1, X86Zmm src2, X86KReg k) {
    instOptions |= X86EmitOptions.kX86_ZMask;
    extraReg = k;
    emit(X86InstId.kVpaddd, [dst, src1, src2]);
  }

  /// VPTERNLOGD zmm, zmm, zmm, imm8
  void vpternlogdZmmZmmZmmI(X86Zmm dst, X86Zmm src1, X86Zmm src2, int imm8) =>
      emit(X86InstId.kVpternlogd, [dst, src1, src2, imm8]);

  // ===========================================================================
  // AVX - Packed arithmetic 128-bit (VEX-encoded)
  // ===========================================================================

  /// VADDPS xmm, xmm, xmm (VEX add packed single 128-bit)
  void vaddpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVaddps, [dst, src1, src2]);

  /// VADDPS xmm, xmm, [mem]
  void vaddpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVaddps, [dst, src1, mem]);

  void vaddpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVaddpd, [dst, src1, src2]);

  /// VADDPD xmm, xmm, [mem]
  void vaddpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVaddpd, [dst, src1, mem]);

  /// VSUBPS xmm, xmm, xmm (VEX subtract packed single 128-bit)
  void vsubpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVsubps, [dst, src1, src2]);

  /// VMULPS xmm, xmm, xmm (VEX multiply packed single 128-bit)
  void vmulpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmulps, [dst, src1, src2]);

  /// VMULPS xmm, xmm, [mem]
  void vmulpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmulps, [dst, src1, mem]);

  /// VMULPD xmm, xmm, xmm (VEX multiply packed double 128-bit)
  void vmulpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVmulpd, [dst, src1, src2]);

  /// VSUBPS xmm, xmm, [mem]
  void vsubpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVsubps, [dst, src1, mem]);

  /// VSUBPD xmm, xmm, xmm (VEX subtract packed double 128-bit)
  void vsubpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVsubpd, [dst, src1, src2]);

  /// VSUBPD xmm, xmm, [mem]
  void vsubpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVsubpd, [dst, src1, mem]);

  // ===========================================================================
  // AVX - Packed arithmetic 256-bit (VEX-encoded)
  // ===========================================================================

  /// VADDPS ymm, ymm, ymm (VEX add packed single 256-bit)
  void vaddpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVaddps, [dst, src1, src2]);

  /// VADDPS ymm, ymm, [mem]
  void vaddpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVaddps, [dst, src1, mem]);

  /// VMULPS ymm, ymm, ymm (VEX multiply packed single 256-bit)
  void vmulpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVmulps, [dst, src1, src2]);

  /// VMULPS ymm, ymm, [mem]
  void vmulpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVmulps, [dst, src1, mem]);

  /// VADDPD ymm, ymm, ymm (VEX add packed double 256-bit)
  void vaddpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVaddpd, [dst, src1, src2]);

  /// VADDPD ymm, ymm, [mem]
  void vaddpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVaddpd, [dst, src1, mem]);

  /// VMULPD xmm, xmm, [mem]
  void vmulpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVmulpd, [dst, src1, mem]);

  /// VSUBPS ymm, ymm, ymm (VEX subtract packed single 256-bit)
  void vsubpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVsubps, [dst, src1, src2]);

  /// VSUBPS ymm, ymm, [mem]
  void vsubpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVsubps, [dst, src1, mem]);

  /// VSUBPD ymm, ymm, ymm (VEX subtract packed double 256-bit)
  void vsubpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVsubpd, [dst, src1, src2]);

  /// VSUBPD ymm, ymm, [mem]
  void vsubpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVsubpd, [dst, src1, mem]);

  /// VMULPD ymm, ymm, ymm (VEX multiply packed double 256-bit)
  void vmulpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVmulpd, [dst, src1, src2]);

  /// VMULPD ymm, ymm, [mem]
  void vmulpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVmulpd, [dst, src1, mem]);

  // ===========================================================================
  // AVX - Logical (VEX-encoded)
  // ===========================================================================

  /// VXORPS xmm, xmm, xmm (VEX XOR packed single) - use for zeroing
  void vxorpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVxorps, [dst, src1, src2]);

  /// VXORPS xmm, xmm, [mem]
  void vxorpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVxorps, [dst, src1, mem]);

  /// VXORPS ymm, ymm, ymm (VEX XOR packed single 256-bit) - use for zeroing
  void vxorpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVxorps, [dst, src1, src2]);

  /// VXORPS ymm, ymm, [mem]
  void vxorpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVxorps, [dst, src1, mem]);

  /// VXORPD xmm, xmm, xmm (VEX XOR packed double)
  void vxorpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVxorpd, [dst, src1, src2]);

  /// VXORPD ymm, ymm, ymm (VEX XOR packed double 256-bit)
  void vxorpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVxorpd, [dst, src1, src2]);

  /// VXORPD xmm, xmm, [mem]
  void vxorpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVxorpd, [dst, src1, mem]);

  /// VXORPD ymm, ymm, [mem]
  void vxorpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVxorpd, [dst, src1, mem]);

  /// VPXOR xmm, xmm, xmm (VEX XOR packed integer)
  void vpxorXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVpxor, [dst, src1, src2]);

  /// VPXOR xmm, xmm, [mem]
  void vpxorXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVpxor, [dst, src1, mem]);

  /// VPXOR ymm, ymm, ymm (VEX XOR packed integer 256-bit)
  void vpxorYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVpxor, [dst, src1, src2]);

  /// VPXOR ymm, ymm, [mem]
  void vpxorYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVpxor, [dst, src1, mem]);

  // ===========================================================================
  // AVX2 - Integer arithmetic (VEX-encoded)
  // ===========================================================================

  /// VPADDD xmm, xmm, xmm (VEX add packed dwords)
  void vpadddXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVpaddd, [dst, src1, src2]);

  /// VPADDD ymm, ymm, ymm (VEX add packed dwords 256-bit)
  void vpadddYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVpaddd, [dst, src1, src2]);

  /// VPADDQ xmm, xmm, xmm (VEX add packed qwords)
  void vpaddqXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVpaddq, [dst, src1, src2]);

  /// VPMULLD xmm, xmm, xmm (VEX multiply packed dwords low)
  void vpmulldXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVpmulld, [dst, src1, src2]);

  // ===========================================================================
  // FMA - Fused Multiply-Add (VEX-encoded)
  // ===========================================================================

  /// VFMADD132SD xmm, xmm, xmm: dst = dst * src2 + src1
  void vfmadd132sdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVfmadd132sd, [dst, src1, src2]);

  /// VFMADD231SD xmm, xmm, xmm: dst = src1 * src2 + dst
  void vfmadd231sdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVfmadd231sd, [dst, src1, src2]);

  // ===========================================================================
  // AVX - Special
  // ===========================================================================

  /// VZEROUPPER - Zero upper 128 bits of all YMM registers.
  ///
  /// CRITICAL: Call this before transitioning from AVX to SSE code!
  /// Avoids expensive AVX-SSE transition penalty.
  void vzeroupper() => emit(X86InstId.kVzeroupper, []);

  /// VZEROALL - Zero all YMM registers completely.
  void vzeroall() => emit(X86InstId.kVzeroall, []);

  // ===========================================================================
  // AVX-512 Instructions (EVEX-encoded)
  // ===========================================================================

  /// VADDPS zmm, zmm, zmm (AVX-512 add packed single 512-bit)
  void vaddpsZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVaddps, [dst, src1, src2]);

  /// VADDPD zmm, zmm, zmm (AVX-512 add packed double 512-bit)
  void vaddpdZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVaddpd, [dst, src1, src2]);

  // --- Move Instructions ---

  /// VMOVUPS zmm, zmm (AVX-512)
  void vmovupsZmm(X86Zmm dst, X86Zmm src) =>
      emit(X86InstId.kVmovups, [dst, src]);

  /// VMOVUPS zmm, [mem] (AVX-512)
  void vmovupsZmmMem(X86Zmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovups, [dst, mem]);

  /// VMOVUPS [mem], zmm (AVX-512)
  void vmovupsMemZmm(X86Mem mem, X86Zmm src) =>
      emit(X86InstId.kVmovups, [mem, src]);

  /// VMOVUPD zmm, zmm (AVX-512)
  void vmovupdZmm(X86Zmm dst, X86Zmm src) =>
      emit(X86InstId.kVmovupd, [dst, src]);

  /// VMOVUPD zmm, [mem] (AVX-512)
  void vmovupdZmmMem(X86Zmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovupd, [dst, mem]);

  /// VMOVUPD [mem], zmm (AVX-512)
  void vmovupdMemZmm(X86Mem mem, X86Zmm src) =>
      emit(X86InstId.kVmovupd, [mem, src]);

  /// VMOVDQU32 zmm, zmm (AVX-512)
  void vmovdqu32Zmm(X86Zmm dst, X86Zmm src) =>
      emit(X86InstId.kVmovdqu32, [dst, src]);

  /// VMOVDQU32 zmm, [mem] (AVX-512)
  void vmovdqu32ZmmMem(X86Zmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovdqu32, [dst, mem]);

  /// VMOVDQU32 [mem], zmm (AVX-512)
  void vmovdqu32MemZmm(X86Mem mem, X86Zmm src) =>
      emit(X86InstId.kVmovdqu32, [mem, src]);

  /// VMOVDQU64 zmm, zmm (AVX-512)
  void vmovdqu64Zmm(X86Zmm dst, X86Zmm src) =>
      emit(X86InstId.kVmovdqu64, [dst, src]);

  /// VMOVDQU64 zmm, [mem] (AVX-512)
  void vmovdqu64ZmmMem(X86Zmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovdqu64, [dst, mem]);

  /// VMOVDQU64 [mem], zmm (AVX-512)
  void vmovdqu64MemZmm(X86Mem mem, X86Zmm src) =>
      emit(X86InstId.kVmovdqu64, [mem, src]);

  // --- Logic Instructions ---

  /// VPANDD zmm, zmm, zmm (AVX-512)
  void vpanddZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVpandd, [dst, src1, src2]);

  /// VPANDQ zmm, zmm, zmm (AVX-512)
  void vpandqZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVpandq, [dst, src1, src2]);

  /// VPORD zmm, zmm, zmm (AVX-512)
  void vpordZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVpord, [dst, src1, src2]);

  /// VPORQ zmm, zmm, zmm (AVX-512)
  void vporqZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVporq, [dst, src1, src2]);

  /// VPXORD zmm, zmm, zmm (AVX-512)
  void vpxordZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVpxord, [dst, src1, src2]);

  /// VPXORQ zmm, zmm, zmm (AVX-512)
  void vpxorqZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVpxorq, [dst, src1, src2]);

  /// VXORPS zmm, zmm, zmm (AVX-512)
  void vxorpsZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVxorps, [dst, src1, src2]);

  /// VXORPD zmm, zmm, zmm (AVX-512)
  void vxorpdZmm(X86Zmm dst, X86Zmm src1, X86Zmm src2) =>
      emit(X86InstId.kVxorpd, [dst, src1, src2]);

  // --- Conversion Instructions ---

  /// VCVTTPS2DQ zmm, zmm (AVX-512) - Convert with truncation
  void vcvttps2dqZmm(X86Zmm dst, X86Zmm src) =>
      emit(X86InstId.kVcvttps2dq, [dst, src]);

  /// VCVTDQ2PS zmm, zmm (AVX-512)
  void vcvtdq2psZmm(X86Zmm dst, X86Zmm src) =>
      emit(X86InstId.kVcvtdq2ps, [dst, src]);

  /// VCVTPS2PD zmm, ymm (AVX-512)
  void vcvtps2pdZmm(X86Zmm dst, X86Ymm src) =>
      emit(X86InstId.kVcvtps2pd, [dst, src]);

  /// VCVTPD2PS ymm, zmm (AVX-512)
  void vcvtpd2psYmm(X86Ymm dst, X86Zmm src) =>
      emit(X86InstId.kVcvtpd2ps, [dst, src]);

  /// MOVDQU xmm, xmm (SSE2)
  void movdquXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMovdqu, [dst, src]);

  /// MOVDQU xmm, [mem] (SSE2)
  void movdquXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMovdqu, [dst, src]);

  /// MOVDQU [mem], xmm (SSE2)
  void movdquMX(X86Mem dst, X86Xmm src) => emit(X86InstId.kMovdqu, [dst, src]);

  /// MOVDQA xmm, xmm (SSE2)
  void movdqaXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kMovdqa, [dst, src]);

  /// MOVDQA xmm, [mem] (SSE2)
  void movdqaXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kMovdqa, [dst, src]);

  /// MOVDQA [mem], xmm (SSE2)
  void movdqaMX(X86Mem dst, X86Xmm src) => emit(X86InstId.kMovdqa, [dst, src]);

  /// VMOVDQU xmm, [mem] (AVX)
  void vmovdquXmmMem(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovdqu, [dst, mem]);

  /// VMOVDQU xmm, xmm (AVX)
  void vmovdquXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVmovdqu, [dst, src]);

  /// VMOVDQU [mem], xmm (AVX)
  void vmovdquMemXmm(X86Mem mem, X86Xmm src) =>
      emit(X86InstId.kVmovdqu, [mem, src]);

  /// VMOVDQU ymm, [mem] (AVX)
  void vmovdquYmmMem(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVmovdqu, [dst, mem]);

  /// VMOVDQU ymm, ymm (AVX)
  void vmovdquYY(X86Ymm dst, X86Ymm src) =>
      emit(X86InstId.kVmovdqu, [dst, src]);

  /// VMOVDQU [mem], ymm (AVX)
  void vmovdquMemYmm(X86Mem mem, X86Ymm src) =>
      emit(X86InstId.kVmovdqu, [mem, src]);

  /// VMOVDQA xmm, [mem] (AVX)
  void vmovdqaXmmMem(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovdqa, [dst, mem]);

  /// VMOVDQA [mem], xmm (AVX)
  void vmovdqaMemXmm(X86Mem mem, X86Xmm src) =>
      emit(X86InstId.kVmovdqa, [mem, src]);

  /// VMOVDQA xmm, xmm (AVX)
  void vmovdqaXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kVmovdqa, [dst, src]);

  /// VMOVDQA ymm, [mem] (AVX)
  void vmovdqaYmmMem(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVmovdqa, [dst, mem]);

  /// VMOVDQA [mem], ymm (AVX)
  void vmovdqaMemYmm(X86Mem mem, X86Ymm src) =>
      emit(X86InstId.kVmovdqa, [mem, src]);

  /// VMOVDQA ymm, ymm (AVX)
  void vmovdqaYY(X86Ymm dst, X86Ymm src) =>
      emit(X86InstId.kVmovdqa, [dst, src]);

  /// VPSHUFD xmm, xmm/m128, imm8
  void vpshufdXXX(X86Xmm dst, X86Xmm src, int imm) =>
      emit(X86InstId.kVpshufd, [dst, src, imm]);
  void vpshufdXXM(X86Xmm dst, X86Mem src, int imm) =>
      emit(X86InstId.kVpshufd, [dst, src, imm]);

  /// VPSHUFD ymm, ymm/m256, imm8
  void vpshufdYYY(X86Ymm dst, X86Ymm src, int imm) =>
      emit(X86InstId.kVpshufd, [dst, src, imm]);
  void vpshufdYYM(X86Ymm dst, X86Mem src, int imm) =>
      emit(X86InstId.kVpshufd, [dst, src, imm]);

  // ===========================================================================
  // SSE2 - Packed Integer Arithmetic
  // ===========================================================================

  /// PADDD xmm, xmm
  void padddXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPaddd, [dst, src]);

  /// PADDD xmm, [mem]
  void padddXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPaddd, [dst, src]);

  /// PADDB xmm, xmm
  void paddbXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPaddb, [dst, src]);

  /// PADDB xmm, [mem]
  void paddbXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPaddb, [dst, src]);

  /// PADDW xmm, xmm
  void paddwXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPaddw, [dst, src]);

  /// PADDW xmm, [mem]
  void paddwXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPaddw, [dst, src]);

  /// PADDQ xmm, xmm
  void paddqXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPaddq, [dst, src]);

  /// PADDQ xmm, [mem]
  void paddqXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPaddq, [dst, src]);

  /// PSUBB xmm, xmm
  void psubbXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsubb, [dst, src]);

  /// PSUBB xmm, [mem]
  void psubbXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPsubb, [dst, src]);

  /// PSUBW xmm, xmm
  void psubwXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsubw, [dst, src]);

  /// PSUBW xmm, [mem]
  void psubwXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPsubw, [dst, src]);

  /// PSUBD xmm, xmm
  void psubdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsubd, [dst, src]);

  /// PSUBD xmm, [mem]
  void psubdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPsubd, [dst, src]);

  /// PSUBQ xmm, xmm
  void psubqXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsubq, [dst, src]);

  /// PSUBQ xmm, [mem]
  void psubqXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPsubq, [dst, src]);

  /// PMULLW xmm, xmm
  void pmullwXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPmullw, [dst, src]);

  /// PMULLW xmm, [mem]
  void pmullwXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPmullw, [dst, src]);

  /// PMULLD xmm, xmm (SSE4.1)
  void pmulldXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPmulld, [dst, src]);

  /// PMULLD xmm, [mem] (SSE4.1)
  void pmulldXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPmulld, [dst, src]);

  /// PMULHW xmm, xmm
  void pmulhwXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPmulhw, [dst, src]);

  /// PMULHW xmm, [mem]
  void pmulhwXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPmulhw, [dst, src]);

  /// PMULHUW xmm, xmm
  void pmulhuwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmulhuw, [dst, src]);

  /// PMULHUW xmm, [mem]
  void pmulhuwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmulhuw, [dst, src]);

  /// PMADDWD xmm, xmm
  void pmaddwdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmaddwd, [dst, src]);

  /// PMADDWD xmm, [mem]
  void pmaddwdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmaddwd, [dst, src]);

  /// PMADDUBSW xmm, xmm (SSSE3)
  void pmaddubswXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmaddubsw, [dst, src]);

  /// PMADDUBSW xmm, [mem] (SSSE3)
  void pmaddubswXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmaddubsw, [dst, src]);

  /// PABSB xmm, xmm (SSSE3)
  void pabsbXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPabsb, [dst, src]);

  /// PABSB xmm, [mem] (SSSE3)
  void pabsbXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPabsb, [dst, src]);

  /// PABSW xmm, xmm (SSSE3)
  void pabswXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPabsw, [dst, src]);

  /// PABSW xmm, [mem] (SSSE3)
  void pabswXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPabsw, [dst, src]);

  /// PABSD xmm, xmm (SSSE3)
  void pabsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPabsd, [dst, src]);

  /// PABSD xmm, [mem] (SSSE3)
  void pabsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPabsd, [dst, src]);

  /// PSADBW xmm, xmm
  void psadbwXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsadbw, [dst, src]);

  /// PSADBW xmm, [mem]
  void psadbwXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPsadbw, [dst, src]);

  // ===========================================================================
  // SSE2/SSE4.1 - Packed Integer Compare
  // ===========================================================================

  /// PCMPEQB xmm, xmm
  void pcmpeqbXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpeqb, [dst, src]);

  /// PCMPEQB xmm, [mem]
  void pcmpeqbXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpeqb, [dst, src]);

  /// PCMPEQW xmm, xmm
  void pcmpeqwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpeqw, [dst, src]);

  /// PCMPEQW xmm, [mem]
  void pcmpeqwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpeqw, [dst, src]);

  /// PCMPEQD xmm, xmm
  void pcmpeqdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpeqd, [dst, src]);

  /// PCMPEQD xmm, [mem]
  void pcmpeqdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpeqd, [dst, src]);

  /// PCMPEQQ xmm, xmm (SSE4.1)
  void pcmpeqqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpeqq, [dst, src]);

  /// PCMPEQQ xmm, [mem] (SSE4.1)
  void pcmpeqqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpeqq, [dst, src]);

  /// PCMPGTB xmm, xmm
  void pcmpgtbXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpgtb, [dst, src]);

  /// PCMPGTB xmm, [mem]
  void pcmpgtbXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpgtb, [dst, src]);

  /// PCMPGTW xmm, xmm
  void pcmpgtwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpgtw, [dst, src]);

  /// PCMPGTW xmm, [mem]
  void pcmpgtwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpgtw, [dst, src]);

  /// PCMPGTD xmm, xmm
  void pcmpgtdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpgtd, [dst, src]);

  /// PCMPGTD xmm, [mem]
  void pcmpgtdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpgtd, [dst, src]);

  /// PCMPGTQ xmm, xmm (SSE4.2)
  void pcmpgtqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPcmpgtq, [dst, src]);

  /// PCMPGTQ xmm, [mem] (SSE4.2)
  void pcmpgtqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPcmpgtq, [dst, src]);

  // ===========================================================================
  // SSE2/SSE4.1 - Packed Integer Min/Max
  // ===========================================================================

  /// PMINUB xmm, xmm
  void pminubXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPminub, [dst, src]);

  /// PMINUB xmm, [mem]
  void pminubXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPminub, [dst, src]);

  /// PMAXUB xmm, xmm
  void pmaxubXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPmaxub, [dst, src]);

  /// PMAXUB xmm, [mem]
  void pmaxubXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPmaxub, [dst, src]);

  /// PMINSW xmm, xmm
  void pminswXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPminsw, [dst, src]);

  /// PMINSW xmm, [mem]
  void pminswXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPminsw, [dst, src]);

  /// PMAXSW xmm, xmm
  void pmaxswXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPmaxsw, [dst, src]);

  /// PMAXSW xmm, [mem]
  void pmaxswXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPmaxsw, [dst, src]);

  /// PMINUD xmm, xmm (SSE4.1)
  void pminudXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPminud, [dst, src]);

  /// PMINUD xmm, [mem] (SSE4.1)
  void pminudXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPminud, [dst, src]);

  /// PMAXUD xmm, xmm (SSE4.1)
  void pmaxudXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPmaxud, [dst, src]);

  /// PMAXUD xmm, [mem] (SSE4.1)
  void pmaxudXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPmaxud, [dst, src]);

  /// PMINSD xmm, xmm (SSE4.1)
  void pminsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPminsd, [dst, src]);

  /// PMINSD xmm, [mem] (SSE4.1)
  void pminsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPminsd, [dst, src]);

  /// PMAXSD xmm, xmm (SSE4.1)
  void pmaxsdXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPmaxsd, [dst, src]);

  /// PMAXSD xmm, [mem] (SSE4.1)
  void pmaxsdXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPmaxsd, [dst, src]);

  // ===========================================================================
  // SSE2 - Packed Integer Shift
  // ===========================================================================

  /// PSLLW xmm, xmm
  void psllwXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsllw, [dst, src]);

  /// PSLLW xmm, imm8
  void psllwXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsllw, [dst, imm8]);

  /// PSLLD xmm, xmm
  void pslldXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPslld, [dst, src]);

  /// PSLLD xmm, imm8
  void pslldXI(X86Xmm dst, int imm8) => emit(X86InstId.kPslld, [dst, imm8]);

  /// PSLLQ xmm, xmm
  void psllqXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsllq, [dst, src]);

  /// PSLLQ xmm, imm8
  void psllqXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsllq, [dst, imm8]);

  /// PSRLW xmm, xmm
  void psrlwXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsrlw, [dst, src]);

  /// PSRLW xmm, imm8
  void psrlwXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsrlw, [dst, imm8]);

  /// PSRLD xmm, xmm
  void psrldXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsrld, [dst, src]);

  /// PSRLD xmm, imm8
  void psrldXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsrld, [dst, imm8]);

  /// VPSLLD xmm, xmm, imm8 (AVX)
  void vpslld(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kVpslld, [dst, src, imm8]);

  /// VPSRLD xmm, xmm, imm8 (AVX)
  void vpsrld(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kVpsrld, [dst, src, imm8]);

  /// VPSHUFD xmm, xmm, imm8 (AVX)
  void vpshufd(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kVpshufd, [dst, src, imm8]);

  /// PSRLQ xmm, xmm
  void psrlqXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsrlq, [dst, src]);

  /// PSRLQ xmm, imm8
  void psrlqXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsrlq, [dst, imm8]);

  /// PSRAW xmm, xmm
  void psrawXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsraw, [dst, src]);

  /// PSRAW xmm, imm8
  void psrawXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsraw, [dst, imm8]);

  /// PSRAD xmm, xmm
  void psradXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPsrad, [dst, src]);

  /// PSRAD xmm, imm8
  void psradXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsrad, [dst, imm8]);

  /// PSLLDQ xmm, imm8 (byte shift left)
  void pslldqXI(X86Xmm dst, int imm8) => emit(X86InstId.kPslldq, [dst, imm8]);

  /// PSRLDQ xmm, imm8 (byte shift right)
  void psrldqXI(X86Xmm dst, int imm8) => emit(X86InstId.kPsrldq, [dst, imm8]);

  // ===========================================================================
  // SSE2/SSE4.1 - Packed Integer Logic
  // ===========================================================================

  /// PAND xmm, xmm
  void pandXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPand, [dst, src]);

  /// PAND xmm, [mem]
  void pandXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPand, [dst, src]);

  /// PANDN xmm, xmm
  void pandnXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPandn, [dst, src]);

  /// PANDN xmm, [mem]
  void pandnXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPandn, [dst, src]);

  // POR and PXOR are already implemented as porXX/porXM and pxorXX/pxorXM

  // ===========================================================================
  // SSE2/SSE4.1 - Pack/Unpack
  // ===========================================================================

  /// PACKSSWB xmm, xmm
  void packsswbXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPacksswb, [dst, src]);

  /// PACKSSWB xmm, [mem]
  void packsswbXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPacksswb, [dst, src]);

  /// PACKSSDW xmm, xmm
  void packssdwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPackssdw, [dst, src]);

  /// PACKSSDW xmm, [mem]
  void packssdwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPackssdw, [dst, src]);

  /// PACKUSWB xmm, xmm
  void packuswbXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPackuswb, [dst, src]);

  /// PACKUSWB xmm, [mem]
  void packuswbXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPackuswb, [dst, src]);

  /// PACKUSDW xmm, xmm (SSE4.1)
  void packusdwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPackusdw, [dst, src]);

  /// PACKUSDW xmm, [mem] (SSE4.1)
  void packusdwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPackusdw, [dst, src]);

  /// PUNPCKLBW xmm, xmm
  void punpcklbwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpcklbw, [dst, src]);

  /// PUNPCKLBW xmm, [mem]
  void punpcklbwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpcklbw, [dst, src]);

  /// PUNPCKLWD xmm, xmm
  void punpcklwdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpcklwd, [dst, src]);

  /// PUNPCKLWD xmm, [mem]
  void punpcklwdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpcklwd, [dst, src]);

  /// PUNPCKLDQ xmm, xmm
  void punpckldqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpckldq, [dst, src]);

  /// PUNPCKLDQ xmm, [mem]
  void punpckldqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpckldq, [dst, src]);

  /// PUNPCKLQDQ xmm, xmm
  void punpcklqdqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpcklqdq, [dst, src]);

  /// PUNPCKLQDQ xmm, [mem]
  void punpcklqdqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpcklqdq, [dst, src]);

  /// PUNPCKHBW xmm, xmm
  void punpckhbwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpckhbw, [dst, src]);

  /// PUNPCKHBW xmm, [mem]
  void punpckhbwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpckhbw, [dst, src]);

  /// PUNPCKHWD xmm, xmm
  void punpckhwdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpckhwd, [dst, src]);

  /// PUNPCKHWD xmm, [mem]
  void punpckhwdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpckhwd, [dst, src]);

  /// PUNPCKHDQ xmm, xmm
  void punpckhdqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpckhdq, [dst, src]);

  /// PUNPCKHDQ xmm, [mem]
  void punpckhdqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpckhdq, [dst, src]);

  /// PUNPCKHQDQ xmm, xmm
  void punpckhqdqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPunpckhqdq, [dst, src]);

  /// PUNPCKHQDQ xmm, [mem]
  void punpckhqdqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPunpckhqdq, [dst, src]);

  // ===========================================================================
  // SSE2/SSSE3 - Shuffle and Align
  // ===========================================================================

  /// PSHUFD xmm, xmm, imm8
  void pshufdXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPshufd, [dst, src, imm8]);

  /// PSHUFD xmm, [mem], imm8
  void pshufdXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPshufd, [dst, src, imm8]);

  /// PSHUFB xmm, xmm (SSSE3)
  void pshufbXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPshufb, [dst, src]);

  /// PSHUFB xmm, [mem] (SSSE3)
  void pshufbXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPshufb, [dst, src]);

  /// PSHUFLW xmm, xmm, imm8
  void pshuflwXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPshuflw, [dst, src, imm8]);

  /// PSHUFLW xmm, [mem], imm8
  void pshuflwXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPshuflw, [dst, src, imm8]);

  /// PSHUFHW xmm, xmm, imm8
  void pshufhwXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPshufhw, [dst, src, imm8]);

  /// PSHUFHW xmm, [mem], imm8
  void pshufhwXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPshufhw, [dst, src, imm8]);

  /// PALIGNR xmm, xmm, imm8 (SSSE3)
  void palignrXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPalignr, [dst, src, imm8]);

  /// PALIGNR xmm, [mem], imm8 (SSSE3)
  void palignrXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPalignr, [dst, src, imm8]);

  // ===========================================================================
  // SSE4.1 - Packed Integer Extend
  // ===========================================================================

  void pmovzxbwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovzxbw, [dst, src]);
  void pmovzxbwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovzxbw, [dst, src]);

  void pmovzxbdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovzxbd, [dst, src]);
  void pmovzxbdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovzxbd, [dst, src]);

  void pmovzxbqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovzxbq, [dst, src]);
  void pmovzxbqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovzxbq, [dst, src]);

  void pmovzxwdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovzxwd, [dst, src]);
  void pmovzxwdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovzxwd, [dst, src]);

  void pmovzxwqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovzxwq, [dst, src]);
  void pmovzxwqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovzxwq, [dst, src]);

  void pmovzxdqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovzxdq, [dst, src]);
  void pmovzxdqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovzxdq, [dst, src]);

  void pmovsxbwXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovsxbw, [dst, src]);
  void pmovsxbwXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovsxbw, [dst, src]);

  void pmovsxbdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovsxbd, [dst, src]);
  void pmovsxbdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovsxbd, [dst, src]);

  void pmovsxbqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovsxbq, [dst, src]);
  void pmovsxbqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovsxbq, [dst, src]);

  void pmovsxwdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovsxwd, [dst, src]);
  void pmovsxwdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovsxwd, [dst, src]);

  void pmovsxwqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovsxwq, [dst, src]);
  void pmovsxwqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovsxwq, [dst, src]);

  void pmovsxdqXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPmovsxdq, [dst, src]);
  void pmovsxdqXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPmovsxdq, [dst, src]);

  // ===========================================================================
  // SSE4.1 - Insert/Extract
  // ===========================================================================

  void pinsrbR(X86Xmm dst, X86Gp src, int imm8) =>
      emit(X86InstId.kPinsrb, [dst, src, imm8]);
  void pinsrbM(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPinsrb, [dst, src, imm8]);

  void pinsrdR(X86Xmm dst, X86Gp src, int imm8) =>
      emit(X86InstId.kPinsrd, [dst, src, imm8]);
  void pinsrdM(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPinsrd, [dst, src, imm8]);

  void pinsrqR(X86Xmm dst, X86Gp src, int imm8) =>
      emit(X86InstId.kPinsrq, [dst, src, imm8]);
  void pinsrqM(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPinsrq, [dst, src, imm8]);

  void pextrbR(X86Gp dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrb, [dst, src, imm8]);
  void pextrbM(X86Mem dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrb, [dst, src, imm8]);

  void pextrdR(X86Gp dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrd, [dst, src, imm8]);
  void pextrdM(X86Mem dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrd, [dst, src, imm8]);

  void pextrqR(X86Gp dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrq, [dst, src, imm8]);
  void pextrqM(X86Mem dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrq, [dst, src, imm8]);

  // ===========================================================================
  // SSE4.1 - Blend
  // ===========================================================================

  void pblendwXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPblendw, [dst, src, imm8]);
  void pblendwXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPblendw, [dst, src, imm8]);

  void pblendvbXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kPblendvb, [dst, src]);
  void pblendvbXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kPblendvb, [dst, src]);

  void blendpsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kBlendps, [dst, src, imm8]);
  void blendpsXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kBlendps, [dst, src, imm8]);

  /// POR xmm, xmm
  void porXX(X86Xmm dst, X86Xmm src) => emit(X86InstId.kPor, [dst, src]);

  /// POR xmm, [mem]
  void porXM(X86Xmm dst, X86Mem src) => emit(X86InstId.kPor, [dst, src]);

  void vmovups(X86Xmm dst, X86Xmm src) => emit(X86InstId.kVmovups, [dst, src]);
  void vmovupsXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovups, [dst, mem]);
  void vmovupsMX(X86Mem mem, X86Xmm src) =>
      emit(X86InstId.kVmovups, [mem, src]);

  void vmovaps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kVmovaps, [dst, src]);
  void vmovapsXM(X86Xmm dst, X86Mem mem) =>
      emit(X86InstId.kVmovaps, [dst, mem]);
  void vmovapsMX(X86Mem mem, X86Xmm src) =>
      emit(X86InstId.kVmovaps, [mem, src]);

  void vmovupsY(X86Ymm dst, X86Ymm src) => emit(X86InstId.kVmovups, [dst, src]);
  void vmovupsYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVmovups, [dst, mem]);
  void vmovupsMY(X86Mem mem, X86Ymm src) =>
      emit(X86InstId.kVmovups, [mem, src]);

  void vmovapsY(X86Ymm dst, X86Ymm src) => emit(X86InstId.kVmovaps, [dst, src]);
  void vmovapsYM(X86Ymm dst, X86Mem mem) =>
      emit(X86InstId.kVmovaps, [dst, mem]);
  void vmovapsMY(X86Mem mem, X86Ymm src) =>
      emit(X86InstId.kVmovaps, [mem, src]);

  // VDIVPS/VDIVPD forms
  void vdivpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVdivps, [dst, src1, src2]);
  void vdivpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVdivps, [dst, src1, mem]);
  void vdivpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVdivps, [dst, src1, src2]);
  void vdivpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVdivps, [dst, src1, mem]);

  void vdivpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVdivpd, [dst, src1, src2]);
  void vdivpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVdivpd, [dst, src1, mem]);
  void vdivpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVdivpd, [dst, src1, src2]);
  void vdivpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVdivpd, [dst, src1, mem]);

  // SSE Logical operations
  void andps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kAndps, [dst, src]);
  void andpsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kAndps, [dst, mem]);
  void andpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kAndpd, [dst, src]);
  void andpdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kAndpd, [dst, mem]);

  void orps(X86Xmm dst, X86Xmm src) => emit(X86InstId.kOrps, [dst, src]);
  void orpsXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kOrps, [dst, mem]);
  void orpd(X86Xmm dst, X86Xmm src) => emit(X86InstId.kOrpd, [dst, src]);
  void orpdXM(X86Xmm dst, X86Mem mem) => emit(X86InstId.kOrpd, [dst, mem]);

  // SSE Compare operations (min/max)

  // AVX Logical operations
  void vandpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVandps, [dst, src1, src2]);
  void vandpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVandps, [dst, src1, mem]);
  void vandpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVandps, [dst, src1, src2]);
  void vandpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVandps, [dst, src1, mem]);

  void vandpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVandpd, [dst, src1, src2]);
  void vandpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVandpd, [dst, src1, mem]);
  void vandpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVandpd, [dst, src1, src2]);
  void vandpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVandpd, [dst, src1, mem]);

  void vorpsXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVorps, [dst, src1, src2]);
  void vorpsXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVorps, [dst, src1, mem]);
  void vorpsYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVorps, [dst, src1, src2]);
  void vorpsYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVorps, [dst, src1, mem]);

  void vorpdXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVorpd, [dst, src1, src2]);
  void vorpdXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVorpd, [dst, src1, mem]);
  void vorpdYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVorpd, [dst, src1, src2]);
  void vorpdYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVorpd, [dst, src1, mem]);

  void vporXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVpor, [dst, src1, src2]);
  void vporXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVpor, [dst, src1, mem]);
  void vporYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVpor, [dst, src1, src2]);
  void vporYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVpor, [dst, src1, mem]);

  void vpandXXX(X86Xmm dst, X86Xmm src1, X86Xmm src2) =>
      emit(X86InstId.kVpand, [dst, src1, src2]);
  void vpandXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVpand, [dst, src1, mem]);
  void vpandYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVpand, [dst, src1, src2]);
  void vpandYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVpand, [dst, src1, mem]);

  void vpaddqXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVpaddq, [dst, src1, mem]);

  void vpaddqYYY(X86Ymm dst, X86Ymm src1, X86Ymm src2) =>
      emit(X86InstId.kVpaddq, [dst, src1, src2]);

  void vpaddqYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVpaddq, [dst, src1, mem]);

  void vpadddXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVpaddd, [dst, src1, mem]);
  void vpadddYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVpaddd, [dst, src1, mem]);

  void vpmulldXXM(X86Xmm dst, X86Xmm src1, X86Mem mem) =>
      emit(X86InstId.kVpmulld, [dst, src1, mem]);
  void vpmulldYYM(X86Ymm dst, X86Ymm src1, X86Mem mem) =>
      emit(X86InstId.kVpmulld, [dst, src1, mem]);

  // ===========================================================================
  // SSE4.1 - Blend (Variable)
  // ===========================================================================

  void blendvpsXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kBlendvps, [dst, src]);
  void blendvpsXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kBlendvps, [dst, src]);

  void blendvpdXX(X86Xmm dst, X86Xmm src) =>
      emit(X86InstId.kBlendvpd, [dst, src]);
  void blendvpdXM(X86Xmm dst, X86Mem src) =>
      emit(X86InstId.kBlendvpd, [dst, src]);

  // ===========================================================================
  // SSE4.1 - Insert/Extract (Remaining)
  // ===========================================================================

  void pextrwRX(X86Gp dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrw, [dst, src, imm8]);
  void pextrwMX(X86Mem dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kPextrw, [dst, src, imm8]);

  void pinsrwXR(X86Xmm dst, X86Gp src, int imm8) =>
      emit(X86InstId.kPinsrw, [dst, src, imm8]);
  void pinsrwXM(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kPinsrw, [dst, src, imm8]);

  void insertpsXXI(X86Xmm dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kInsertps, [dst, src, imm8]);
  void insertpsXMI(X86Xmm dst, X86Mem src, int imm8) =>
      emit(X86InstId.kInsertps, [dst, src, imm8]);

  void extractpsRX(X86Gp dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kExtractps, [dst, src, imm8]);
  void extractpsMX(X86Mem dst, X86Xmm src, int imm8) =>
      emit(X86InstId.kExtractps, [dst, src, imm8]);

  // ===========================================================================
  // AVX-512 Mask Operations (k*)
  // ===========================================================================

  void kandb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandb, [k1, k2, k3]);
  void kandw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandw, [k1, k2, k3]);
  void kandd(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandd, [k1, k2, k3]);
  void kandq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandq, [k1, k2, k3]);

  void kandnb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnb, [k1, k2, k3]);
  void kandnw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnw, [k1, k2, k3]);
  void kandnd(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnd, [k1, k2, k3]);
  void kandnq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKandnq, [k1, k2, k3]);

  void korb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKorb, [k1, k2, k3]);
  void korw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKorw, [k1, k2, k3]);
  void kord(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKord, [k1, k2, k3]);
  void korq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKorq, [k1, k2, k3]);

  void kxnorb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnorb, [k1, k2, k3]);
  void kxnorw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnorw, [k1, k2, k3]);
  void kxnord(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnord, [k1, k2, k3]);
  void kxnorq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxnorq, [k1, k2, k3]);

  void kxorb(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxorb, [k1, k2, k3]);
  void kxorw(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxorw, [k1, k2, k3]);
  void kxord(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxord, [k1, k2, k3]);
  void kxorq(X86KReg k1, X86KReg k2, X86KReg k3) =>
      emit(X86InstId.kKxorq, [k1, k2, k3]);

  void kmovb(Object dst, Object src) => emit(X86InstId.kKmovb, [dst, src]);
  void kmovw(Object dst, Object src) => emit(X86InstId.kKmovw, [dst, src]);
  void kmovd(Object dst, Object src) => emit(X86InstId.kKmovd, [dst, src]);
  void kmovq(Object dst, Object src) => emit(X86InstId.kKmovq, [dst, src]);

  void knotb(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotb, [dst, src]);
  void knotw(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotw, [dst, src]);
  void knotd(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotd, [dst, src]);
  void knotq(X86KReg dst, X86KReg src) => emit(X86InstId.kKnotq, [dst, src]);

  // ===========================================================================
  // AVX-512 Zero/Sign Extension
  // ===========================================================================

  void vpmovzxbd(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxbd, [dst, src]);
  void vpmovzxbq(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxbq, [dst, src]);
  void vpmovzxbw(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxbw, [dst, src]);
  void vpmovzxdq(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxdq, [dst, src]);
  void vpmovzxwd(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxwd, [dst, src]);
  void vpmovzxwq(Object dst, Object src) =>
      emit(X86InstId.kVpmovzxwq, [dst, src]);

  void vpmovsxbd(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxbd, [dst, src]);
  void vpmovsxbq(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxbq, [dst, src]);
  void vpmovsxbw(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxbw, [dst, src]);
  void vpmovsxdq(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxdq, [dst, src]);
  void vpmovsxwd(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxwd, [dst, src]);
  void vpmovsxwq(Object dst, Object src) =>
      emit(X86InstId.kVpmovsxwq, [dst, src]);

  // ===========================================================================
  // SSE4.1 Rounding Instructions
  // ===========================================================================

  /// ROUNDPS xmm, xmm/m128, imm8 - Round packed single-precision values.
  /// imm8: 0=round to nearest, 1=floor, 2=ceil, 3=truncate
  void roundps(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundps, [dst, src, Imm(imm8)]);

  /// ROUNDPD xmm, xmm/m128, imm8 - Round packed double-precision values.
  void roundpd(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundpd, [dst, src, Imm(imm8)]);

  /// ROUNDSS xmm, xmm/m32, imm8 - Round scalar single-precision value.
  void roundss(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundss, [dst, src, Imm(imm8)]);

  /// ROUNDSD xmm, xmm/m64, imm8 - Round scalar double-precision value.
  void roundsd(Object dst, Object src, int imm8) =>
      emit(X86InstId.kRoundsd, [dst, src, Imm(imm8)]);

  /// VROUNDPS - AVX version of ROUNDPS.
  void vroundps(Object dst, Object src, int imm8) =>
      emit(X86InstId.kVroundps, [dst, src, Imm(imm8)]);

  /// VROUNDPD - AVX version of ROUNDPD.
  void vroundpd(Object dst, Object src, int imm8) =>
      emit(X86InstId.kVroundpd, [dst, src, Imm(imm8)]);

  /// VROUNDSS - AVX version of ROUNDSS.
  void vroundss(Object dst, Object src1, Object src2, int imm8) =>
      emit(X86InstId.kVroundss, [dst, src1, src2, Imm(imm8)]);

  /// VROUNDSD - AVX version of ROUNDSD.
  void vroundsd(Object dst, Object src1, Object src2, int imm8) =>
      emit(X86InstId.kVroundsd, [dst, src1, src2, Imm(imm8)]);
}

extension FuncFrameX86Extensions on FuncFrame {
  /// Returns the GP register used for function arguments.
  X86Gp getArgReg(int index, [CallingConvention? cc]) {
    final regId = getArgRegId(index, cc);
    if (regId == Reg.kIdBad) {
      throw RangeError.index(index, null, 'index');
    }
    return X86Gp.r64(regId);
  }
}
