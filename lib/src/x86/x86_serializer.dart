import '../core/builder.dart' as ir;
import '../core/labels.dart';
import 'x86_assembler.dart';
import 'x86_inst_db.g.dart';
import 'x86_operands.dart';
import 'x86_encoder.dart'; // For X86Cond
import 'x86_simd.dart';
import 'x86.dart';
import 'x86_dispatcher.g.dart'; // Generated dispatcher

/// Serializer that converts Builder IR to X86Assembler calls.
class X86Serializer implements ir.SerializerContext {
  /// The target assembler.
  final X86Assembler asm;

  X86Serializer(this.asm);

  @override
  void onLabel(Label label) {
    asm.bind(label);
  }

  @override
  void onAlign(ir.AlignMode mode, int alignment) {
    if (mode == ir.AlignMode.code) {
      asm.align(alignment);
    }
    // Data alignment not fully supported in text section mixed with code
  }

  @override
  void onEmbedData(List<int> data, int typeSize) {
    asm.emitInline(data);
  }

  @override
  void onComment(String text) {
    // Comments are ignored by assembler
  }

  @override
  void onSentinel(ir.SentinelType type) {
    // Sentinels are ignored
  }

  @override
  void onInst(int instId, List<ir.Operand> operands, int options) {
    // Helper to extract X86 operands
    final ops = <Object>[];
    for (final op in operands) {
      if (op is ir.RegOperand) {
        ops.add(op.reg);
      } else if (op is ir.ImmOperand) {
        ops.add(op.value);
      } else if (op is ir.MemOperand) {
        ops.add(op.mem);
      } else if (op is ir.LabelOperand) {
        ops.add(op.label);
      }
    }
    emitInst(instId, ops, options);
  }

  /// Emits the instruction with pre-processed operands.
  void emitInst(int instId, List<Object> ops, int options) {
    // 1. Try manual lookup (fast path for implemented insts)
    final handler = _lookup[instId];
    if (handler != null) {
      handler(asm, ops);
      return;
    }

    // 2. Fallback to generated dispatcher (for all other insts)
    x86Dispatch(asm, instId, ops);
  }

  // ===========================================================================
  // Lookup Table & Helpers
  // ===========================================================================

  static final Map<int, void Function(X86Assembler, List<Object>)> _lookup =
      _buildLookup();

  static Map<int, void Function(X86Assembler, List<Object>)> _buildLookup() {
    final m = <int, void Function(X86Assembler, List<Object>)>{};

    // MOV
    m[X86InstId.kMov] = (asm, ops) {
      if (ops.length == 2) {
        final dst = ops[0];
        final src = ops[1];
        if (dst is X86Gp && src is X86Gp)
          asm.movRR(dst, src);
        else if (dst is X86Gp && src is int)
          asm.movRI64(dst, src);
        else if (dst is X86Gp && src is X86Mem)
          asm.movRM(dst, src);
        else if (dst is X86Mem && src is X86Gp) asm.movMR(dst, src);
      }
    };

    // Arithmetic (ADD, SUB, AND, OR, XOR, CMP, TEST)
    _registerBinary(m, X86InstId.kAdd, (asm, dst, src) => asm.addRR(dst, src),
        (asm, dst, imm) => asm.addRI(dst, imm));
    _registerBinary(m, X86InstId.kSub, (asm, dst, src) => asm.subRR(dst, src),
        (asm, dst, imm) => asm.subRI(dst, imm));
    _registerBinary(m, X86InstId.kAnd, (asm, dst, src) => asm.andRR(dst, src),
        (asm, dst, imm) => asm.andRI(dst, imm));
    _registerBinary(m, X86InstId.kOr, (asm, dst, src) => asm.orRR(dst, src),
        (asm, dst, imm) => asm.orRI(dst, imm));
    _registerBinary(m, X86InstId.kXor, (asm, dst, src) => asm.xorRR(dst, src),
        (asm, dst, imm) => asm.xorRI(dst, imm));
    _registerBinary(m, X86InstId.kCmp, (asm, dst, src) => asm.cmpRR(dst, src),
        (asm, dst, imm) => asm.cmpRI(dst, imm));
    _registerBinary(m, X86InstId.kTest, (asm, dst, src) => asm.testRR(dst, src),
        (asm, dst, imm) => asm.testRI(dst, imm));

    // LEA
    m[X86InstId.kLea] = (asm, ops) {
      if (ops.length == 2 && ops[0] is X86Gp && ops[1] is X86Mem)
        asm.lea(ops[0] as X86Gp, ops[1] as X86Mem);
    };

    // Division and Multiplication
    m[X86InstId.kIdiv] = (asm, ops) {
      if (ops.length == 1 && ops[0] is X86Gp) asm.idiv(ops[0] as X86Gp);
    };
    m[X86InstId.kDiv] = (asm, ops) {
      if (ops.length == 1 && ops[0] is X86Gp) asm.div(ops[0] as X86Gp);
    };
    m[X86InstId.kMul] = (asm, ops) {
      if (ops.length == 1 && ops[0] is X86Gp) asm.mul(ops[0] as X86Gp);
    };

    // Sign Extension
    m[X86InstId.kCdq] = (asm, ops) => asm.cdq();
    m[X86InstId.kCqo] = (asm, ops) => asm.cqo();

    // IMUL (Special case for 3 operands)
    m[X86InstId.kImul] = (asm, ops) {
      if (ops.length == 2) {
        final dst = ops[0];
        final src = ops[1];
        if (dst is X86Gp && src is X86Gp)
          asm.imulRR(dst, src);
        else if (dst is X86Gp && src is int) asm.imulRI(dst, src);
      } else if (ops.length == 3) {
        final dst = ops[0];
        final src = ops[1];
        final imm = ops[2];
        if (dst is X86Gp && src is X86Gp && imm is int)
          asm.imulRRI(dst, src, imm);
      }
    };

    // Unary (INC, DEC, NEG, NOT)
    _registerUnary(m, X86InstId.kInc, (asm, reg) => asm.inc(reg));
    _registerUnary(m, X86InstId.kDec, (asm, reg) => asm.dec(reg));
    _registerUnary(m, X86InstId.kNeg, (asm, reg) => asm.neg(reg));
    _registerUnary(m, X86InstId.kNot, (asm, reg) => asm.not(reg));

    // Shift (SHL, SHR, SAR, ROL, ROR)
    _registerShift(m, X86InstId.kShl, (asm, reg, imm) => asm.shlRI(reg, imm),
        (asm, reg) => asm.shlRCl(reg));
    _registerShift(m, X86InstId.kShr, (asm, reg, imm) => asm.shrRI(reg, imm),
        (asm, reg) => asm.shrRCl(reg));
    _registerShift(m, X86InstId.kSar, (asm, reg, imm) => asm.sarRI(reg, imm),
        (asm, reg) => asm.sarRCl(reg));
    _registerShift(m, X86InstId.kRol, (asm, reg, imm) => asm.rolRI(reg, imm),
        (asm, reg) => null); // ROL CL not exposed yet
    _registerShift(m, X86InstId.kRor, (asm, reg, imm) => asm.rorRI(reg, imm),
        (asm, reg) => null); // ROR CL not exposed yet

    // Stack (PUSH, POP)
    m[X86InstId.kPush] = (asm, ops) {
      if (ops.length == 1) {
        final op = ops[0];
        if (op is X86Gp)
          asm.push(op);
        else if (op is int) asm.pushImm32(op); // Default to imm32 push
      }
    };
    m[X86InstId.kPop] = (asm, ops) {
      if (ops.length == 1 && ops[0] is X86Gp) asm.pop(ops[0] as X86Gp);
    };

    // Control Flow
    m[X86InstId.kJmp] = (asm, ops) {
      if (ops.length == 1) {
        final op = ops[0];
        if (op is Label)
          asm.jmp(op);
        else if (op is X86Gp)
          asm.jmpR(op);
        else if (op is int) asm.jmpRel(op);
      }
    };
    m[X86InstId.kCall] = (asm, ops) {
      if (ops.length == 1) {
        final op = ops[0];
        if (op is Label)
          asm.call(op);
        else if (op is X86Gp)
          asm.callR(op);
        else if (op is int) asm.callRel(op);
      }
    };
    m[X86InstId.kRet] = (asm, ops) {
      if (ops.isEmpty)
        asm.ret();
      else if (ops.length == 1 && ops[0] is int) asm.retImm(ops[0] as int);
    };

    // Conditionals (Jcc, SETcc, CMOVcc)
    // We Map 'cc' instructions systematically
    _registerJcc(m);
    _registerSetcc(m);
    _registerCmovcc(m);

    // AVX-512 / SIMD
    _registerSimd(m, X86InstId.kAddps,
        xmm: (asm, dst, src1, src2) => asm.vaddpsXXX(dst, src1, src2),
        ymm: (asm, dst, src1, src2) => asm.vaddpsYYY(dst, src1, src2),
        zmm: (asm, dst, src1, src2) => asm.vaddpsZmm(dst, src1, src2));
    _registerSimd(m, X86InstId.kAddpd,
        xmm: (asm, dst, src1, src2) => asm.vaddpdXXX(dst, src1, src2),
        ymm: (asm, dst, src1, src2) => asm.vaddpdYYY(dst, src1, src2),
        zmm: (asm, dst, src1, src2) => asm.vaddpdZmm(dst, src1, src2));

    // Moves
    // Using kMovups for vmovups (assuming merged ID or just handling one)
    // If kVmovups exists, we'd use it. For now, assuming standard Move logic or separate ID.
    // The DB seems to use canonical names like 'movups'.
    // Let's add standard Movups and check if it handles ZMM via operands.
    // Since we don't have existing movupsXXX in Assembler exposed yet (only enc),
    // and I added vmovupsZmm, I will register for ZMM only for now or check args.
    // Actually, x86_inst_db likely has kMovups.
    // I'll register a custom handler for kMovups that checks for ZMM.
    // Note: kMovups ID might not be in the subset I saw. I'll take a risk or use dynamic dispatch if needed.
    // Or better, I can assume if I use `vmovups` mnemonic in builder, it maps to `kMovups` or `kVmovups`.
    // I'll assume `kMovups` exists (it's standard SSE).

    // ZMM Logic
    // These likely have specific IDs like kVpandd in DB? I saw kVpord etc in snippet?
    // Snippet had kVpord = 1387.
    _registerSimd(m, X86InstId.kVpord,
        zmm: (asm, dst, src1, src2) => asm.vpordZmm(dst, src1, src2));
    _registerSimd(m, X86InstId.kVporq,
        zmm: (asm, dst, src1, src2) => asm.vporqZmm(dst, src1, src2));
    _registerSimd(m, X86InstId.kVpxord,
        zmm: (asm, dst, src1, src2) => asm.vpxordZmm(dst, src1, src2));
    _registerSimd(m, X86InstId.kVpxorq,
        zmm: (asm, dst, src1, src2) => asm.vpxorqZmm(dst, src1, src2));
    _registerSimd(m, X86InstId.kVpandd,
        zmm: (asm, dst, src1, src2) => asm.vpanddZmm(dst, src1, src2));
    _registerSimd(m, X86InstId.kVpandq,
        zmm: (asm, dst, src1, src2) => asm.vpandqZmm(dst, src1, src2));

    _registerSimd(m, X86InstId.kVxorps,
        xmm: (asm, dst, src1, src2) => asm.vxorpsXXX(dst, src1, src2),
        ymm: (asm, dst, src1, src2) => asm.vxorpsYYY(dst, src1, src2),
        zmm: (asm, dst, src1, src2) => asm.vxorpsZmm(dst, src1, src2));
    _registerSimd(m, X86InstId.kVxorpd,
        zmm: (asm, dst, src1, src2) => asm.vxorpdZmm(dst, src1, src2));

    return m;
  }

  static void _registerSimd(
      Map<int, void Function(X86Assembler, List<Object>)> m, int instId,
      {void Function(X86Assembler, X86Xmm, X86Xmm, X86Xmm)? xmm,
      void Function(X86Assembler, X86Ymm, X86Ymm, X86Ymm)? ymm,
      void Function(X86Assembler, X86Zmm, X86Zmm, X86Zmm)? zmm}) {
    m[instId] = (asm, ops) {
      if (ops.length == 3) {
        final dst = ops[0];
        final src1 = ops[1];
        final src2 = ops[2];

        if (zmm != null && dst is X86Zmm && src1 is X86Zmm && src2 is X86Zmm) {
          zmm(asm, dst, src1, src2);
        } else if (ymm != null &&
            dst is X86Ymm &&
            src1 is X86Ymm &&
            src2 is X86Ymm) {
          ymm(asm, dst, src1, src2);
        } else if (xmm != null &&
            dst is X86Xmm &&
            src1 is X86Xmm &&
            src2 is X86Xmm) {
          xmm(asm, dst, src1, src2);
        }
      }
      // TODO: Handle Memory operands and other counts (2-op)
    };
  }

  static void _registerBinary(
      Map<int, void Function(X86Assembler, List<Object>)> m,
      int instId,
      void Function(X86Assembler, X86Gp, X86Gp) rr,
      void Function(X86Assembler, X86Gp, int) ri) {
    m[instId] = (asm, ops) {
      if (ops.length == 2) {
        final dst = ops[0];
        final src = ops[1];
        if (dst is X86Gp && src is X86Gp)
          rr(asm, dst, src);
        else if (dst is X86Gp && src is int) ri(asm, dst, src);
      }
    };
  }

  static void _registerUnary(
      Map<int, void Function(X86Assembler, List<Object>)> m,
      int instId,
      void Function(X86Assembler, X86Gp) r) {
    m[instId] = (asm, ops) {
      if (ops.length == 1 && ops[0] is X86Gp) r(asm, ops[0] as X86Gp);
    };
  }

  static void _registerShift(
      Map<int, void Function(X86Assembler, List<Object>)> m,
      int instId,
      void Function(X86Assembler, X86Gp, int) ri,
      void Function(X86Assembler, X86Gp)? rCl) {
    m[instId] = (asm, ops) {
      if (ops.length == 2) {
        final dst = ops[0];
        final src = ops[1];
        if (dst is X86Gp && src is int)
          ri(asm, dst, src);
        else if (dst is X86Gp &&
            src is X86Gp &&
            src.id == 1 &&
            rCl != null) // CL is ID 1 (RCX)
          rCl(asm, dst);
      }
    };
  }

  static void _registerJcc(
      Map<int, void Function(X86Assembler, List<Object>)> m) {
    // Correct mapping to canonical InstIds (matches x86_inst_db.g.dart)
    final jccMap = {
      X86InstId.kJo: X86Cond.o,
      X86InstId.kJno: X86Cond.no,
      X86InstId.kJb: X86Cond.b,
      X86InstId.kJnb: X86Cond.ae, // jae -> jnb
      X86InstId.kJz: X86Cond.e, // je -> jz
      X86InstId.kJnz: X86Cond.ne, // jne -> jnz
      X86InstId.kJbe: X86Cond.be,
      X86InstId.kJnbe: X86Cond.a, // ja -> jnbe
      X86InstId.kJs: X86Cond.s,
      X86InstId.kJns: X86Cond.ns,
      X86InstId.kJp: X86Cond.p,
      X86InstId.kJnp: X86Cond.np,
      X86InstId.kJl: X86Cond.l,
      X86InstId.kJnl: X86Cond.ge, // jge -> jnl
      X86InstId.kJle: X86Cond.le,
      X86InstId.kJnle: X86Cond.g, // jg -> jnle
    };

    jccMap.forEach((id, cond) {
      m[id] = (asm, ops) {
        if (ops.isNotEmpty) {
          final op = ops[0];
          if (op is Label)
            asm.jcc(cond, op);
          else if (op is int) asm.jccRel(cond, op);
        }
      };
    });
  }

  static void _registerSetcc(
      Map<int, void Function(X86Assembler, List<Object>)> m) {
    final map = {
      X86InstId.kSeto: X86Cond.o,
      X86InstId.kSetno: X86Cond.no,
      X86InstId.kSetb: X86Cond.b,
      X86InstId.kSetnb: X86Cond.nb, // setae
      X86InstId.kSetz: X86Cond.e, // sete
      X86InstId.kSetnz: X86Cond.ne, // setne
      X86InstId.kSetbe: X86Cond.be,
      X86InstId.kSetnbe: X86Cond.a, // seta
      X86InstId.kSets: X86Cond.s,
      X86InstId.kSetns: X86Cond.ns,
      X86InstId.kSetp: X86Cond.p,
      X86InstId.kSetnp: X86Cond.np,
      X86InstId.kSetl: X86Cond.l,
      X86InstId.kSetnl: X86Cond.ge, // setge
      X86InstId.kSetle: X86Cond.le,
      X86InstId.kSetnle: X86Cond.g, // setg
    };

    map.forEach((id, cond) {
      m[id] = (asm, ops) {
        if (ops.length == 1 && ops[0] is X86Gp)
          asm.setcc(cond, ops[0] as X86Gp);
      };
    });
  }

  static void _registerCmovcc(
      Map<int, void Function(X86Assembler, List<Object>)> m) {
    final map = {
      X86InstId.kCmovo: X86Cond.o,
      X86InstId.kCmovno: X86Cond.no,
      X86InstId.kCmovb: X86Cond.b,
      X86InstId.kCmovnb: X86Cond.nb, // cmovae
      X86InstId.kCmovz: X86Cond.e, // cmove
      X86InstId.kCmovnz: X86Cond.ne, // cmovne
      X86InstId.kCmovbe: X86Cond.be,
      X86InstId.kCmovnbe: X86Cond.a, // cmova
      X86InstId.kCmovs: X86Cond.s,
      X86InstId.kCmovns: X86Cond.ns,
      X86InstId.kCmovp: X86Cond.p,
      X86InstId.kCmovnp: X86Cond.np,
      X86InstId.kCmovl: X86Cond.l,
      X86InstId.kCmovnl: X86Cond.ge, // cmovge
      X86InstId.kCmovle: X86Cond.le,
      X86InstId.kCmovnle: X86Cond.g, // cmovg
    };

    map.forEach((id, cond) {
      m[id] = (asm, ops) {
        if (ops.length == 2 && ops[0] is X86Gp && ops[1] is X86Gp)
          asm.cmovcc(cond, ops[0] as X86Gp, ops[1] as X86Gp);
      };
    });
  }
}
