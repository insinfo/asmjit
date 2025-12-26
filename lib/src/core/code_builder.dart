/// AsmJit Code Builder
///
/// High-level code builder that integrates virtual registers with
/// the X86Assembler and Register Allocator.

import 'package:asmjit/asmjit.dart';

/// A high-level code builder that uses virtual registers.
///
/// This builder allows you to write code using virtual registers,
/// which are automatically allocated to physical registers.
///
/// Example:
/// ```dart
/// final builder = X86CodeBuilder.create();
///
/// // Define virtual registers
/// final sum = builder.newGpReg();
/// final counter = builder.newGpReg();
///
/// // Get arg0
/// final arg0 = builder.getArgReg(0);
///
/// // Generate code
/// builder.mov(sum, 0);
/// builder.mov(counter, arg0);
///
/// final loop = builder.newLabel();
/// final done = builder.newLabel();
///
/// builder.bind(loop);
/// builder.test(counter, counter);
/// builder.jz(done);
/// builder.add(sum, counter);
/// builder.dec(counter);
/// builder.jmp(loop);
///
/// builder.bind(done);
/// builder.ret(sum);
///
/// // Finalize and get executable function
/// final fn = builder.build(runtime);
/// ```
class X86CodeBuilder {
  /// The underlying code holder.
  final CodeHolder code;

  /// The register allocator.
  final SimpleRegAlloc _ra;

  /// Instructions buffer (IR-like).
  final List<_Instruction> _instructions = [];

  /// Current instruction position.
  int _pos = 0;

  final List<Label> _labels = [];

  /// Pending label bindings (label -> instruction position).
  final Map<Label, int> _pendingBinds = {};

  /// Whether the builder is for 64-bit mode.
  final bool is64Bit;

  /// Calling convention.
  final CallingConvention callingConvention;

  /// Argument virtual registers.
  final List<VirtReg> _argRegs = [];

  // ignore: unused_field - reserved for future return value tracking
  VirtReg? _returnReg;

  X86CodeBuilder._({
    required this.code,
    required this.is64Bit,
    required this.callingConvention,
  }) : _ra = SimpleRegAlloc(
            isWin64: callingConvention == CallingConvention.win64);

  /// Creates a new code builder for the host environment.
  factory X86CodeBuilder.create({Environment? env}) {
    env ??= Environment.host();
    final code = CodeHolder(env: env);
    return X86CodeBuilder._(
      code: code,
      is64Bit: env.is64Bit,
      callingConvention: env.callingConvention,
    );
  }

  // ===========================================================================
  // Register management
  // ===========================================================================

  /// Creates a new virtual GP register.
  VirtReg newGpReg({int size = 8}) {
    return _ra.newVirtReg(size: size, regClass: RegClass.gp);
  }

  /// Creates a new virtual XMM register.
  VirtReg newXmmReg() {
    return _ra.newVirtReg(size: 16, regClass: RegClass.xmm);
  }

  /// Gets the virtual register for argument [index].
  VirtReg getArgReg(int index) {
    // Ensure we have enough arg registers
    while (_argRegs.length <= index) {
      final arg = _ra.newVirtReg();
      _argRegs.add(arg);
    }
    return _argRegs[index];
  }

  // ===========================================================================
  // Labels
  // ===========================================================================

  /// Creates a new label.
  Label newLabel() {
    final label = code.newLabel();
    _labels.add(label);
    return label;
  }

  /// Creates a new named label.
  Label newNamedLabel(String name) {
    final label = code.newNamedLabel(name);
    _labels.add(label);
    return label;
  }

  /// Binds a label at the current position.
  void bind(Label label) {
    _pendingBinds[label] = _pos;
  }

  // ===========================================================================
  // Instructions
  // ===========================================================================

  /// MOV vreg, vreg
  void mov(VirtReg dst, Object src) {
    _recordUse(dst);
    if (src is VirtReg) {
      _recordUse(src);
      _emit(_OpKind.movRR, dst: dst, src1: src);
    } else if (src is int) {
      _emit(_OpKind.movRI, dst: dst, imm: src);
    } else {
      throw ArgumentError('Invalid source type: ${src.runtimeType}');
    }
  }

  /// ADD vreg, vreg/imm
  void add(VirtReg dst, Object src) {
    _recordUse(dst);
    if (src is VirtReg) {
      _recordUse(src);
      _emit(_OpKind.addRR, dst: dst, src1: src);
    } else if (src is int) {
      _emit(_OpKind.addRI, dst: dst, imm: src);
    } else {
      throw ArgumentError('Invalid source type');
    }
  }

  /// SUB vreg, vreg/imm
  void sub(VirtReg dst, Object src) {
    _recordUse(dst);
    if (src is VirtReg) {
      _recordUse(src);
      _emit(_OpKind.subRR, dst: dst, src1: src);
    } else if (src is int) {
      _emit(_OpKind.subRI, dst: dst, imm: src);
    } else {
      throw ArgumentError('Invalid source type');
    }
  }

  /// IMUL vreg, vreg
  void imul(VirtReg dst, VirtReg src) {
    _recordUse(dst);
    _recordUse(src);
    _emit(_OpKind.imulRR, dst: dst, src1: src);
  }

  /// XOR vreg, vreg (commonly used to zero a register)
  void xor(VirtReg dst, VirtReg src) {
    _recordUse(dst);
    _recordUse(src);
    _emit(_OpKind.xorRR, dst: dst, src1: src);
  }

  /// AND vreg, vreg
  void and(VirtReg dst, VirtReg src) {
    _recordUse(dst);
    _recordUse(src);
    _emit(_OpKind.andRR, dst: dst, src1: src);
  }

  /// OR vreg, vreg
  void or(VirtReg dst, VirtReg src) {
    _recordUse(dst);
    _recordUse(src);
    _emit(_OpKind.orRR, dst: dst, src1: src);
  }

  /// INC vreg
  void inc(VirtReg dst) {
    _recordUse(dst);
    _emit(_OpKind.inc, dst: dst);
  }

  /// DEC vreg
  void dec(VirtReg dst) {
    _recordUse(dst);
    _emit(_OpKind.dec, dst: dst);
  }

  /// NEG vreg
  void neg(VirtReg dst) {
    _recordUse(dst);
    _emit(_OpKind.neg, dst: dst);
  }

  /// NOT vreg
  void not(VirtReg dst) {
    _recordUse(dst);
    _emit(_OpKind.not, dst: dst);
  }

  /// CMP vreg, vreg
  void cmp(VirtReg a, VirtReg b) {
    _recordUse(a);
    _recordUse(b);
    _emit(_OpKind.cmpRR, dst: a, src1: b);
  }

  /// TEST vreg, vreg
  void test(VirtReg a, VirtReg b) {
    _recordUse(a);
    _recordUse(b);
    _emit(_OpKind.testRR, dst: a, src1: b);
  }

  /// SHL vreg, imm8
  void shl(VirtReg dst, int imm8) {
    _recordUse(dst);
    _emit(_OpKind.shlRI, dst: dst, imm: imm8);
  }

  /// SHR vreg, imm8
  void shr(VirtReg dst, int imm8) {
    _recordUse(dst);
    _emit(_OpKind.shrRI, dst: dst, imm: imm8);
  }

  // ===========================================================================
  // Control flow
  // ===========================================================================

  /// JMP label
  void jmp(Label target) {
    _emit(_OpKind.jmp, label: target);
  }

  /// JE/JZ label
  void je(Label target) => jcc(X86Cond.e, target);
  void jz(Label target) => jcc(X86Cond.e, target);

  /// JNE/JNZ label
  void jne(Label target) => jcc(X86Cond.ne, target);
  void jnz(Label target) => jcc(X86Cond.ne, target);

  /// JL label
  void jl(Label target) => jcc(X86Cond.l, target);

  /// JLE label
  void jle(Label target) => jcc(X86Cond.le, target);

  /// JG label
  void jg(Label target) => jcc(X86Cond.g, target);

  /// JGE label
  void jge(Label target) => jcc(X86Cond.ge, target);

  /// JB label
  void jb(Label target) => jcc(X86Cond.b, target);

  /// JAE label
  void jae(Label target) => jcc(X86Cond.ae, target);

  /// Jcc label
  void jcc(X86Cond cond, Label target) {
    _emit(_OpKind.jcc, cond: cond, label: target);
  }

  /// RET (with optional return value)
  void ret([VirtReg? returnValue]) {
    if (returnValue != null) {
      _recordUse(returnValue);
      _returnReg = returnValue;
    }
    _emit(_OpKind.ret, src1: returnValue);
  }

  // ===========================================================================
  // Internal
  // ===========================================================================

  void _emit(
    _OpKind kind, {
    VirtReg? dst,
    VirtReg? src1,
    VirtReg? src2,
    int? imm,
    Label? label,
    X86Cond? cond,
  }) {
    _instructions.add(_Instruction(
      kind: kind,
      dst: dst,
      src1: src1,
      src2: src2,
      imm: imm,
      label: label,
      cond: cond,
    ));
    _pos++;
  }

  void _recordUse(VirtReg vreg) {
    _ra.recordUse(vreg, _pos);
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  /// Builds the code and returns the executable function.
  JitFunction build(JitRuntime runtime) {
    // Run register allocation
    _ra.allocate();

    // Create assembler
    final asm = X86Assembler(code);

    // Get physical argument registers
    final physArgRegs = _getPhysicalArgRegs();

    // Emit prologue if we have spills
    if (_ra.spillAreaSize > 0) {
      asm.emitPrologue(stackSize: _ra.spillAreaSize);
    }

    // Move arguments to their allocated registers
    for (int i = 0; i < _argRegs.length && i < physArgRegs.length; i++) {
      final argVreg = _argRegs[i];
      final physArg = physArgRegs[i];

      if (argVreg.physReg != null && argVreg.physReg != physArg) {
        asm.movRR(argVreg.physReg!, physArg);
      } else if (argVreg.isSpilled) {
        // Store to spill slot
        _emitSpillStore(asm, argVreg, physArg);
      }
    }

    // Emit instructions
    for (int i = 0; i < _instructions.length; i++) {
      // Bind labels at this position
      for (final entry in _pendingBinds.entries) {
        if (entry.value == i) {
          code.bind(entry.key);
        }
      }

      _emitInstruction(asm, _instructions[i]);
    }

    // Bind remaining labels
    for (final entry in _pendingBinds.entries) {
      if (entry.value >= _instructions.length) {
        code.bind(entry.key);
      }
    }

    // Finalize and add to runtime
    return runtime.add(code);
  }

  void _emitInstruction(X86Assembler asm, _Instruction inst) {
    switch (inst.kind) {
      case _OpKind.movRR:
        final dst = _getPhysReg(inst.dst!);
        final src = _getPhysReg(inst.src1!);
        asm.movRR(dst, src);

      case _OpKind.movRI:
        final dst = _getPhysReg(inst.dst!);
        asm.movRI64(dst, inst.imm!);

      case _OpKind.addRR:
        final dst = _getPhysReg(inst.dst!);
        final src = _getPhysReg(inst.src1!);
        asm.addRR(dst, src);

      case _OpKind.addRI:
        final dst = _getPhysReg(inst.dst!);
        asm.addRI(dst, inst.imm!);

      case _OpKind.subRR:
        final dst = _getPhysReg(inst.dst!);
        final src = _getPhysReg(inst.src1!);
        asm.subRR(dst, src);

      case _OpKind.subRI:
        final dst = _getPhysReg(inst.dst!);
        asm.subRI(dst, inst.imm!);

      case _OpKind.imulRR:
        final dst = _getPhysReg(inst.dst!);
        final src = _getPhysReg(inst.src1!);
        asm.imulRR(dst, src);

      case _OpKind.xorRR:
        final dst = _getPhysReg(inst.dst!);
        final src = _getPhysReg(inst.src1!);
        asm.xorRR(dst, src);

      case _OpKind.andRR:
        final dst = _getPhysReg(inst.dst!);
        final src = _getPhysReg(inst.src1!);
        asm.andRR(dst, src);

      case _OpKind.orRR:
        final dst = _getPhysReg(inst.dst!);
        final src = _getPhysReg(inst.src1!);
        asm.orRR(dst, src);

      case _OpKind.inc:
        final dst = _getPhysReg(inst.dst!);
        asm.inc(dst);

      case _OpKind.dec:
        final dst = _getPhysReg(inst.dst!);
        asm.dec(dst);

      case _OpKind.neg:
        final dst = _getPhysReg(inst.dst!);
        asm.neg(dst);

      case _OpKind.not:
        final dst = _getPhysReg(inst.dst!);
        asm.not(dst);

      case _OpKind.cmpRR:
        final a = _getPhysReg(inst.dst!);
        final b = _getPhysReg(inst.src1!);
        asm.cmpRR(a, b);

      case _OpKind.testRR:
        final a = _getPhysReg(inst.dst!);
        final b = _getPhysReg(inst.src1!);
        asm.testRR(a, b);

      case _OpKind.shlRI:
        final dst = _getPhysReg(inst.dst!);
        asm.shlRI(dst, inst.imm!);

      case _OpKind.shrRI:
        final dst = _getPhysReg(inst.dst!);
        asm.shrRI(dst, inst.imm!);

      case _OpKind.jmp:
        asm.jmp(inst.label!);

      case _OpKind.jcc:
        asm.jcc(inst.cond!, inst.label!);

      case _OpKind.ret:
        // Move return value to RAX if needed
        if (inst.src1 != null) {
          final retReg = _getPhysReg(inst.src1!);
          if (retReg != rax) {
            asm.movRR(rax, retReg);
          }
        }

        if (_ra.spillAreaSize > 0) {
          asm.emitEpilogue();
        } else {
          asm.ret();
        }
    }
  }

  X86Gp _getPhysReg(VirtReg vreg) {
    if (vreg.physReg != null) {
      return vreg.physReg!;
    }
    // If spilled, we need spill/reload logic (simplified: use a temp)
    throw StateError(
        'Virtual register ${vreg.id} was spilled - reload not implemented');
  }

  List<X86Gp> _getPhysicalArgRegs() {
    if (callingConvention == CallingConvention.win64) {
      return [rcx, rdx, r8, r9];
    } else {
      return [rdi, rsi, rdx, rcx, r8, r9];
    }
  }

  void _emitSpillStore(X86Assembler asm, VirtReg vreg, X86Gp src) {
    // MOV [rbp - offset], src
    final offset = vreg.spillOffset;
    asm.movMR(X86Mem.baseDisp(rbp, -8 - offset), src);
  }
}

/// Instruction kinds.
enum _OpKind {
  movRR,
  movRI,
  addRR,
  addRI,
  subRR,
  subRI,
  imulRR,
  xorRR,
  andRR,
  orRR,
  inc,
  dec,
  neg,
  not,
  cmpRR,
  testRR,
  shlRI,
  shrRI,
  jmp,
  jcc,
  ret,
}

/// Internal instruction representation (mini IR).
class _Instruction {
  final _OpKind kind;
  final VirtReg? dst;
  final VirtReg? src1;
  final VirtReg? src2;
  final int? imm;
  final Label? label;
  final X86Cond? cond;

  _Instruction({
    required this.kind,
    this.dst,
    this.src1,
    this.src2,
    this.imm,
    this.label,
    this.cond,
  });
}
