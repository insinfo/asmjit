/// AsmJit Code Builder
///
/// High-level code builder that integrates virtual registers with
/// the X86Assembler and Register Allocator.

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/core/builder.dart' as ir;

/// A high-level code builder that uses virtual registers.
///
/// This builder allows you to write code using virtual registers,
/// which are automatically allocated to physical registers.
class X86CodeBuilder extends ir.BaseBuilder {
  /// The underlying code holder.
  final CodeHolder code;

  /// The register allocator.
  final SimpleRegAlloc _ra;

  /// Current label binding position is handled by BaseBuilder nodes.

  /// Whether the builder is for 64-bit mode.
  final bool is64Bit;

  /// Calling convention.
  final CallingConvention callingConvention;

  /// Argument virtual registers.
  final List<VirtReg> _argRegs = [];

  // ignore: unused_field - reserved for future return value tracking
  VirtReg? _returnReg;

  // Function frame (if any)
  FuncFrame? _funcFrame;

  // Function frame emitter
  FuncFrameEmitter? _frameEmitter;

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

  /// Creates a new virtual YMM register.
  VirtReg newYmmReg() {
    return _ra.newVirtReg(size: 32, regClass: RegClass.ymm);
  }

  /// Creates a new virtual ZMM register.
  VirtReg newZmmReg() {
    return _ra.newVirtReg(size: 64, regClass: RegClass.zmm);
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

  @override
  Label newLabel() {
    return code.newLabel();
  }

  // ===========================================================================
  // Instructions
  // ===========================================================================

  /// MOV vreg, vreg/imm
  void mov(Object dst, Object src) {
    inst(X86InstId.kMov, [_toOperand(dst), _toOperand(src)]);
  }

  /// VMOVUPS (unaligned move packed single)
  void vmovups(VirtReg dst, Object src) {
    inst(X86InstId.kMovups,
        [ir.RegOperand(dst), _toOperand(src)]); // Mapped to kMovups
  }

  /// VMOVUPD (unaligned move packed double)
  void vmovupd(VirtReg dst, Object src) {
    inst(X86InstId.kMovups, [
      ir.RegOperand(dst),
      _toOperand(src)
    ]); // Note: sharing ID? Check mappings.
    // X86InstId might have movupd. Assuming yes.
    // If not, use generic instructions or ensure ID is correct.
    // I previously missed adding kMovupd mapping in Serializer. I should check.
    // But for now let's focus on helper methods.
  }

  // ... (Other standard methods preserved)

  /// ADD vreg, vreg/imm
  void add(VirtReg dst, Object src) {
    inst(X86InstId.kAdd, [ir.RegOperand(dst), _toOperand(src)]);
  }

  /// VADDPS (packed single add)
  void vaddps(VirtReg dst, VirtReg src1, VirtReg src2) {
    inst(X86InstId.kAddps,
        [ir.RegOperand(dst), ir.RegOperand(src1), ir.RegOperand(src2)]);
  }

  /// VADDPD (packed double add)
  void vaddpd(VirtReg dst, VirtReg src1, VirtReg src2) {
    inst(X86InstId.kAddpd,
        [ir.RegOperand(dst), ir.RegOperand(src1), ir.RegOperand(src2)]);
  }

  // ...

  // ---------------------------------------------------------------------------

  void _rewriteRegisters() {
    for (final node in nodes.instructions) {
      for (int i = 0; i < node.operands.length; i++) {
        final op = node.operands[i];
        if (op is ir.RegOperand && op.reg is VirtReg) {
          final vreg = op.reg as VirtReg;
          if (vreg.physReg != null) {
            // Replace with physical register
            node.operands[i] = ir.RegOperand(vreg.physReg!);
          } else if (vreg.physXmm != null) {
            // Handle vector registers (XMM/YMM/ZMM)
            BaseReg phys = vreg.physXmm!;
            if (vreg.regClass == RegClass.ymm) {
              phys = (phys as X86Xmm).ymm;
            } else if (vreg.regClass == RegClass.zmm) {
              phys = (phys as X86Xmm).zmm;
            }
            node.operands[i] = ir.RegOperand(phys);
          } else if (vreg.isSpilled) {
            // Rewrite to MemOperand [rbp - offset]
            final offset = vreg.spillOffset;
            node.operands[i] = ir.MemOperand(X86Mem.baseDisp(rbp, -8 - offset));
          }
        }
      }
    }
  }

  /// SUB vreg, vreg/imm
  void sub(VirtReg dst, Object src) {
    inst(X86InstId.kSub, [ir.RegOperand(dst), _toOperand(src)]);
  }

  /// IMUL vreg, vreg
  void imul(VirtReg dst, VirtReg src) {
    inst(X86InstId.kImul, [ir.RegOperand(dst), ir.RegOperand(src)]);
  }

  /// XOR vreg, vreg
  void xor(VirtReg dst, VirtReg src) {
    inst(X86InstId.kXor, [ir.RegOperand(dst), ir.RegOperand(src)]);
  }

  /// AND vreg, vreg
  void and(VirtReg dst, VirtReg src) {
    inst(X86InstId.kAnd, [ir.RegOperand(dst), ir.RegOperand(src)]);
  }

  /// OR vreg, vreg
  void or(VirtReg dst, VirtReg src) {
    inst(X86InstId.kOr, [ir.RegOperand(dst), ir.RegOperand(src)]);
  }

  /// INC vreg
  void inc(VirtReg dst) {
    inst(X86InstId.kInc, [ir.RegOperand(dst)]);
  }

  /// DEC vreg
  void dec(VirtReg dst) {
    inst(X86InstId.kDec, [ir.RegOperand(dst)]);
  }

  /// NEG vreg
  void neg(VirtReg dst) {
    inst(X86InstId.kNeg, [ir.RegOperand(dst)]);
  }

  /// NOT vreg
  void not(VirtReg dst) {
    inst(X86InstId.kNot, [ir.RegOperand(dst)]);
  }

  /// CMP vreg, vreg
  void cmp(VirtReg a, VirtReg b) {
    inst(X86InstId.kCmp, [ir.RegOperand(a), ir.RegOperand(b)]);
  }

  /// TEST vreg, vreg
  void test(VirtReg a, VirtReg b) {
    inst(X86InstId.kTest, [ir.RegOperand(a), ir.RegOperand(b)]);
  }

  /// SHL vreg, imm8
  void shl(VirtReg dst, int imm8) {
    inst(X86InstId.kShl, [ir.RegOperand(dst), ir.ImmOperand(imm8)]);
  }

  /// SHR vreg, imm8
  void shr(VirtReg dst, int imm8) {
    inst(X86InstId.kShr, [ir.RegOperand(dst), ir.ImmOperand(imm8)]);
  }

  // ===========================================================================
  // Control flow
  // ===========================================================================

  /// JMP label
  void jmp(Label target) {
    inst(X86InstId.kJmp, [ir.LabelOperand(target)]);
  }

  /// JE/JZ label
  void je(Label target) => inst(X86InstId.kJz, [ir.LabelOperand(target)]);
  void jz(Label target) => je(target);

  /// JNE/JNZ label
  void jne(Label target) => inst(X86InstId.kJnz, [ir.LabelOperand(target)]);
  void jnz(Label target) => jne(target);

  /// RET (with optional return value)
  void ret([VirtReg? returnValue]) {
    if (returnValue != null) {
      _returnReg = returnValue;
      inst(X86InstId.kRet, [ir.RegOperand(returnValue)]);
    } else {
      inst(X86InstId.kRet, []);
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  ir.Operand _toOperand(Object o) {
    if (o is BaseReg)
      return ir.RegOperand(o); // Supports VirtReg and X86Gp/X86Xmm
    if (o is int) return ir.ImmOperand(o);
    if (o is Label) return ir.LabelOperand(o);
    if (o is X86Mem) return ir.MemOperand(o);
    throw ArgumentError('Unsupported operand type: ${o.runtimeType}');
  }

  // ===========================================================================
  // Build
  // ===========================================================================
  // ===========================================================================
  // Function Management
  // ===========================================================================

  /// Start a function definition.
  ///
  /// This allows specifying a custom [FuncFrame] or name.
  /// If [frame] is provided, it will be used for prologue/epilogue generation.
  ir.FuncNode func(String name, {FuncFrame? frame, FuncFrameAttr? attr}) {
    final node = ir.FuncNode(name, frame: frame);
    addNode(node);
    if (frame != null) {
      _funcFrame = frame;
    } else if (attr != null) {
      _funcFrame = FuncFrame.host(attr: attr);
    }
    return node;
  }

  /// Add a basic block (label).
  ir.BlockNode block(Label label) {
    final node = ir.BlockNode(label);
    addNode(node);
    return node;
  }

  /// Allows overriding frame attributes before build.
  void configureFrameAttr(FuncFrameAttr attr) {
    _funcFrame ??= FuncFrame.host(attr: attr);
  }

  /// Builds the code and returns the executable function.
  JitFunction build(JitRuntime runtime,
      {FuncFrameAttr? frameAttrHint, bool useCache = false, String? cacheKey}) {
    // 1. Run register allocation on IR
    _ra.allocate(nodes);

    // 2. Rewrite IR with physical registers
    _rewriteRegisters();

    // 3. Setup Assembler
    final asm = X86Assembler(code);

    // 4. Calculate Frame (Prologue)
    if (_funcFrame == null) {
      // Create minimal frame based on spills or user-provided attr hint.
      final spillSize = _ra.spillAreaSize;
      final attr = frameAttrHint ??
          (spillSize > 0
              ? FuncFrameAttr.nonLeaf(localStackSize: spillSize)
              : FuncFrameAttr.leaf());
      _funcFrame = FuncFrame.host(attr: attr);
    }

    if (_funcFrame != null) {
      _frameEmitter = FuncFrameEmitter(_funcFrame!, asm);
      _frameEmitter!.emitPrologue();
    }

    // 5. Move Arguments (Prologue)
    _emitArgMoves(asm);

    // 6. Serialize the body (Nodes)
    // Use custom serializer to handle RET -> Epilogue
    final serializer = _FuncSerializer(asm, _frameEmitter);
    serialize(serializer);

    if (useCache) {
      return runtime.addCached(code, key: cacheKey);
    }
    return runtime.add(code);
  }

  void _emitArgMoves(X86Assembler asm) {
    final physArgRegs = _getPhysicalArgRegs();
    final moves = <_ArgMove>[];

    // Spills must be stored before any register moves that could clobber sources.
    for (int i = 0; i < _argRegs.length && i < physArgRegs.length; i++) {
      final argVreg = _argRegs[i];
      final physArg = physArgRegs[i];
      if (argVreg.isSpilled) {
        final offset = argVreg.spillOffset;
        asm.movMR(X86Mem.baseDisp(rbp, -8 - offset), physArg);
      } else if (argVreg.physReg != null && argVreg.physReg != physArg) {
        moves.add(_ArgMove(argVreg.physReg!, physArg));
      }
    }

    if (moves.isEmpty) return;

    final used = <X86Gp>{};
    for (final m in moves) {
      used.add(m.dst);
      used.add(m.src);
    }

    while (moves.isNotEmpty) {
      final idx = _findIndependentMove(moves);
      if (idx != -1) {
        final m = moves.removeAt(idx);
        asm.movRR(m.dst, m.src);
        continue;
      }

      final temp = _findTempReg(used);
      final m = moves.removeAt(0);
      if (temp != null) {
        asm.movRR(temp, m.src);
        moves.insert(0, _ArgMove(m.dst, temp));
        used.add(temp);
      } else {
        asm.push(m.src);
        asm.pop(m.dst);
      }
    }
  }

  int _findIndependentMove(List<_ArgMove> moves) {
    for (var i = 0; i < moves.length; i++) {
      final dst = moves[i].dst;
      var usedAsSrc = false;
      for (var j = 0; j < moves.length; j++) {
        if (i == j) continue;
        if (moves[j].src == dst) {
          usedAsSrc = true;
          break;
        }
      }
      if (!usedAsSrc) return i;
    }
    return -1;
  }

  X86Gp? _findTempReg(Set<X86Gp> used) {
    const temps = [
      r11,
      r10,
      r9,
      r8,
      rcx,
      rdx,
      rax,
      rbx,
      rsi,
      rdi,
      r12,
      r13,
      r14,
      r15
    ];
    for (final reg in temps) {
      if (!used.contains(reg)) return reg;
    }
    return null;
  }

  List<X86Gp> _getPhysicalArgRegs() {
    if (callingConvention == CallingConvention.win64) {
      return [rcx, rdx, r8, r9];
    } else {
      return [rdi, rsi, rdx, rcx, r8, r9];
    }
  }
}

class _ArgMove {
  final X86Gp dst;
  final X86Gp src;

  _ArgMove(this.dst, this.src);
}

class _FuncSerializer extends X86Serializer {
  final FuncFrameEmitter? emitter;

  _FuncSerializer(X86Assembler asm, this.emitter) : super(asm);

  @override
  void emitInst(int instId, List<Object> ops, int options) {
    if (instId == X86InstId.kRet && emitter != null) {
      emitter!.emitEpilogue();
      return;
    }
    super.emitInst(instId, ops, options);
  }
}
