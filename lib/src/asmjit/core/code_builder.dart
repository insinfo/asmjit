/// AsmJit Code Builder
///
/// High-level code builder that integrates virtual registers with
/// the X86Assembler and Register Allocator.

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/core/builder.dart' as ir;

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
  final List<VirtReg?> _argRegs = [];

  // ignore: unused_field - reserved for future return value tracking
  VirtReg? _returnReg;

  // Function frame (if any)
  FuncFrame? _funcFrame;

  // Function frame emitter
  FuncFrameEmitter? _frameEmitter;

  // ignore: unused_field - reserved for function tracking in compiler mode.
  FuncNode? _currentFunc;

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

  /// Current code offset.
  int get offset => code.text.buffer.length;

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
      _argRegs.add(null);
    }
    _argRegs[index] ??= _ra.newVirtReg();
    return _argRegs[index]!;
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

  /// MOVAPS (aligned move packed single)
  void movaps(Object dst, Object src) {
    inst(X86InstId.kMovaps, [_toOperand(dst), _toOperand(src)]);
  }

  /// MOVUPS (unaligned move packed single)
  void movups(Object dst, Object src) {
    inst(X86InstId.kMovups, [_toOperand(dst), _toOperand(src)]);
  }

  /// MOVSS (move scalar single)
  void movss(Object dst, Object src) {
    inst(X86InstId.kMovss, [_toOperand(dst), _toOperand(src)]);
  }

  /// MOVSD (move scalar double)
  void movsd(Object dst, Object src) {
    inst(X86InstId.kMovsd, [_toOperand(dst), _toOperand(src)]);
  }

  /// MOVD (move doubleword between XMM and GP/Mem)
  void movd(Object dst, Object src) {
    inst(X86InstId.kMovd, [_toOperand(dst), _toOperand(src)]);
  }

  /// MOVQ (move quadword between XMM and GP)
  void movq(Object dst, Object src) {
    inst(X86InstId.kMovq, [_toOperand(dst), _toOperand(src)]);
  }

  /// VMOVAPS (aligned AVX move packed single)
  void vmovaps(Object dst, Object src) {
    inst(X86InstId.kVmovaps, [_toOperand(dst), _toOperand(src)]);
  }

  /// VMOVUPS (unaligned AVX move packed single)
  void vmovups(Object dst, Object src) {
    inst(X86InstId.kVmovups, [_toOperand(dst), _toOperand(src)]);
  }

  /// VMOVAPD (aligned AVX move packed double)
  void vmovapd(Object dst, Object src) {
    inst(X86InstId.kVmovapd, [_toOperand(dst), _toOperand(src)]);
  }

  /// VMOVUPD (unaligned AVX move packed double)
  void vmovupd(Object dst, Object src) {
    inst(X86InstId.kVmovupd, [_toOperand(dst), _toOperand(src)]);
  }

  /// ADD vreg, vreg/imm
  void add(Object dst, Object src) {
    inst(X86InstId.kAdd, [_toOperand(dst), _toOperand(src)]);
  }

  /// ADDPS (packed single add)
  void addps(Object dst, Object src) {
    inst(X86InstId.kAddps, [_toOperand(dst), _toOperand(src)]);
  }

  /// ADDSS (scalar single add)
  void addss(Object dst, Object src) {
    inst(X86InstId.kAddss, [_toOperand(dst), _toOperand(src)]);
  }

  /// ADDPD (packed double add)
  void addpd(Object dst, Object src) {
    inst(X86InstId.kAddpd, [_toOperand(dst), _toOperand(src)]);
  }

  /// ADDSD (scalar double add)
  void addsd(Object dst, Object src) {
    inst(X86InstId.kAddsd, [_toOperand(dst), _toOperand(src)]);
  }

  /// SUBPS (packed single sub)
  void subps(Object dst, Object src) {
    inst(X86InstId.kSubps, [_toOperand(dst), _toOperand(src)]);
  }

  /// SUBSS (scalar single sub)
  void subss(Object dst, Object src) {
    inst(X86InstId.kSubss, [_toOperand(dst), _toOperand(src)]);
  }

  /// SUBPD (packed double sub)
  void subpd(Object dst, Object src) {
    inst(X86InstId.kSubpd, [_toOperand(dst), _toOperand(src)]);
  }

  /// SUBSD (scalar double sub)
  void subsd(Object dst, Object src) {
    inst(X86InstId.kSubsd, [_toOperand(dst), _toOperand(src)]);
  }

  /// MULPS (packed single mul)
  void mulps(Object dst, Object src) {
    inst(X86InstId.kMulps, [_toOperand(dst), _toOperand(src)]);
  }

  /// MULSS (scalar single mul)
  void mulss(Object dst, Object src) {
    inst(X86InstId.kMulss, [_toOperand(dst), _toOperand(src)]);
  }

  /// MULPD (packed double mul)
  void mulpd(Object dst, Object src) {
    inst(X86InstId.kMulpd, [_toOperand(dst), _toOperand(src)]);
  }

  /// MULSD (scalar double mul)
  void mulsd(Object dst, Object src) {
    inst(X86InstId.kMulsd, [_toOperand(dst), _toOperand(src)]);
  }

  /// DIVPS (packed single div)
  void divps(Object dst, Object src) {
    inst(X86InstId.kDivps, [_toOperand(dst), _toOperand(src)]);
  }

  /// DIVSS (scalar single div)
  void divss(Object dst, Object src) {
    inst(X86InstId.kDivss, [_toOperand(dst), _toOperand(src)]);
  }

  /// DIVPD (packed double div)
  void divpd(Object dst, Object src) {
    inst(X86InstId.kDivpd, [_toOperand(dst), _toOperand(src)]);
  }

  /// DIVSD (scalar double div)
  void divsd(Object dst, Object src) {
    inst(X86InstId.kDivsd, [_toOperand(dst), _toOperand(src)]);
  }

  /// SQRTSS (scalar single sqrt)
  void sqrtss(Object dst, Object src) {
    inst(X86InstId.kSqrtss, [_toOperand(dst), _toOperand(src)]);
  }

  /// SQRTSD (scalar double sqrt)
  void sqrtsd(Object dst, Object src) {
    inst(X86InstId.kSqrtsd, [_toOperand(dst), _toOperand(src)]);
  }

  /// XORPS (packed single xor)
  void xorps(Object dst, Object src) {
    inst(X86InstId.kXorps, [_toOperand(dst), _toOperand(src)]);
  }

  /// XORPD (packed double xor)
  void xorpd(Object dst, Object src) {
    inst(X86InstId.kXorpd, [_toOperand(dst), _toOperand(src)]);
  }

  /// PXOR (packed integer xor)
  void pxor(Object dst, Object src) {
    inst(X86InstId.kPxor, [_toOperand(dst), _toOperand(src)]);
  }

  /// MINPS (packed single min)
  void minps(Object dst, Object src) {
    inst(X86InstId.kMinps, [_toOperand(dst), _toOperand(src)]);
  }

  /// MAXPS (packed single max)
  void maxps(Object dst, Object src) {
    inst(X86InstId.kMaxps, [_toOperand(dst), _toOperand(src)]);
  }

  /// MINPD (packed double min)
  void minpd(Object dst, Object src) {
    inst(X86InstId.kMinpd, [_toOperand(dst), _toOperand(src)]);
  }

  /// MAXPD (packed double max)
  void maxpd(Object dst, Object src) {
    inst(X86InstId.kMaxpd, [_toOperand(dst), _toOperand(src)]);
  }

  /// COMISS (unordered compare single)
  void comiss(Object a, Object b) {
    inst(X86InstId.kComiss, [_toOperand(a), _toOperand(b)]);
  }

  /// UCOMISS (unordered compare single)
  void ucomiss(Object a, Object b) {
    inst(X86InstId.kUcomiss, [_toOperand(a), _toOperand(b)]);
  }

  /// COMISD (unordered compare double)
  void comisd(Object a, Object b) {
    inst(X86InstId.kComisd, [_toOperand(a), _toOperand(b)]);
  }

  /// UCOMISD (unordered compare double)
  void ucomisd(Object a, Object b) {
    inst(X86InstId.kUcomisd, [_toOperand(a), _toOperand(b)]);
  }

  /// CVTSI2SD (convert int to scalar double)
  void cvtsi2sd(Object dst, Object src) {
    inst(X86InstId.kCvtsi2sd, [_toOperand(dst), _toOperand(src)]);
  }

  /// CVTTSD2SI (convert scalar double to int)
  void cvttsd2si(Object dst, Object src) {
    inst(X86InstId.kCvttsd2si, [_toOperand(dst), _toOperand(src)]);
  }

  /// CVTSI2SS (convert int to scalar single)
  void cvtsi2ss(Object dst, Object src) {
    inst(X86InstId.kCvtsi2ss, [_toOperand(dst), _toOperand(src)]);
  }

  /// CVTTSS2SI (convert scalar single to int)
  void cvttss2si(Object dst, Object src) {
    inst(X86InstId.kCvttss2si, [_toOperand(dst), _toOperand(src)]);
  }

  /// CVTSD2SS (convert scalar double to scalar single)
  void cvtsd2ss(Object dst, Object src) {
    inst(X86InstId.kCvtsd2ss, [_toOperand(dst), _toOperand(src)]);
  }

  /// CVTSS2SD (convert scalar single to scalar double)
  void cvtss2sd(Object dst, Object src) {
    inst(X86InstId.kCvtss2sd, [_toOperand(dst), _toOperand(src)]);
  }

  /// VADDPS (packed single add)
  void vaddps(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      addps(dst, src1);
    } else {
      inst(X86InstId.kVaddps,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VADDPD (packed double add)
  void vaddpd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      addpd(dst, src1);
    } else {
      inst(X86InstId.kVaddpd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VSUBPS (packed single sub)
  void vsubps(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      subps(dst, src1);
    } else {
      inst(X86InstId.kVsubps,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VSUBPD (packed double sub)
  void vsubpd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      subpd(dst, src1);
    } else {
      inst(X86InstId.kVsubpd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VMULPS (packed single mul)
  void vmulps(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kMulps, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVmulps,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VMULPD (packed double mul)
  void vmulpd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kMulpd, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVmulpd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VDIVPS (packed single div)
  void vdivps(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kDivps, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVdivps,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VDIVPD (packed double div)
  void vdivpd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kDivpd, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVdivpd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VXORPS (packed single xor)
  void vxorps(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kXorps, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVxorps,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VXORPD (packed double xor)
  void vxorpd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kXorpd, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVxorpd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VPXOR (packed integer xor)
  void vpxor(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kPxor, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVpxor,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VADDSD (scalar double add)
  void vaddsd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      addsd(dst, src1);
    } else {
      inst(X86InstId.kVaddsd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VSUBSD (scalar double sub)
  void vsubsd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      subsd(dst, src1);
    } else {
      inst(X86InstId.kVsubsd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VMULSD (scalar double mul)
  void vmulsd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      mulsd(dst, src1);
    } else {
      inst(X86InstId.kVmulsd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VDIVSD (scalar double div)
  void vdivsd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      divsd(dst, src1);
    } else {
      inst(X86InstId.kVdivsd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VFMADD132SD (fused multiply add)
  void vfmadd132sd(Object dst, Object src1, Object src2) {
    inst(X86InstId.kVfmadd132sd,
        [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
  }

  /// VFMADD231SD (fused multiply add)
  void vfmadd231sd(Object dst, Object src1, Object src2) {
    inst(X86InstId.kVfmadd231sd,
        [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
  }

  /// VPADDD (packed integer add)
  void vpaddd(Object dst, Object src1, [Object? src2]) {
    if (src2 == null) {
      inst(X86InstId.kPaddd, [_toOperand(dst), _toOperand(src1)]);
    } else {
      inst(X86InstId.kVpaddd,
          [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
    }
  }

  /// VPADDQ (packed integer add)
  void vpaddq(Object dst, Object src1, Object src2) {
    inst(X86InstId.kVpaddq,
        [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
  }

  /// VPMULLD (packed integer mul)
  void vpmulld(Object dst, Object src1, Object src2) {
    inst(X86InstId.kVpmulld,
        [_toOperand(dst), _toOperand(src1), _toOperand(src2)]);
  }

  // ---------------------------------------------------------------------------

  void _rewriteRegisters() {
    for (final node in nodes.nodes) {
      if (node is ir.InstNode) {
        _rewriteOperandList(node, node.operands);

        // Check for mov [mem], imm (might require 64-bit size but encoder defaults to 32-bit?)
        // Safe option: Rewrite to mov r11, imm; mov [mem], r11
        if (node.instId == X86InstId.kMov &&
            node.operands.length == 2 &&
            node.operands[0] is ir.MemOperand &&
            node.operands[1] is ir.ImmOperand) {
          final immSrc = node.operands[1] as ir.ImmOperand;

          // Insert MOV r11, imm before
          final movNode =
              ir.InstNode(X86InstId.kMov, [ir.RegOperand(r11), immSrc]);
          nodes.insertBefore(movNode, node);

          // Replace current node with MOV [mem], r11
          // We modify source operand to be r11.
          node.operands[1] = ir.RegOperand(r11);
        }

        if (_rewriteUnsupportedMemOps(node)) {
          continue;
        }

        // Check for double memory operands (illegal in x86)
        // We assume binary instructions with 2 operands for now.
        if (node.operands.length == 2 &&
            node.operands[0] is ir.MemOperand &&
            node.operands[1] is ir.MemOperand) {
          // illegal: op [mem], [mem]
          // Fix: mov r11, [mem_src]
          //      op [mem_dst], r11
          final memSrc = node.operands[1] as ir.MemOperand;

          // Insert MOV r11, memSrc before this node
          final movNode =
              ir.InstNode(X86InstId.kMov, [ir.RegOperand(r11), memSrc]);
          nodes.insertBefore(movNode, node);

          // Replace source operand with r11
          node.operands[1] = ir.RegOperand(r11);
        }
      } else if (node is ir.InvokeNode) {
        _rewriteOperandList(node, node.args);
        final ret = node.ret;
        if (ret is VirtReg) {
          final phys = _physRegForVirt(ret);
          if (phys != null) {
            node.ret = phys;
          } else if (ret.isSpilled) {
            // TODO: Support spilled return values by storing to stack.
          }
        }
      }
    }
  }

  void _rewriteOperandList(ir.BaseNode anchor, List<ir.Operand> operands) {
    for (int i = 0; i < operands.length; i++) {
      final op = operands[i];
      if (op is ir.RegOperand && op.reg is VirtReg) {
        final vreg = op.reg as VirtReg;
        final phys = _physRegForVirt(vreg);
        if (phys != null) {
          operands[i] = ir.RegOperand(phys);
        } else if (vreg.isSpilled) {
          final slotIndex = vreg.spillOffset ~/ 8;
          int offset = 0;
          if (_funcFrame != null) {
            offset = _funcFrame!.getLocalOffset(slotIndex);
          } else {
            offset = -8 - vreg.spillOffset;
          }
          operands[i] = ir.MemOperand(X86Mem.baseDisp(rbp, offset));
        }
      } else if (op is ir.MemOperand && op.mem is X86Mem) {
        final mem = op.mem as X86Mem;
        final rewritten = _rewriteMemOperand(anchor, mem);
        if (rewritten != mem) {
          operands[i] = ir.MemOperand(rewritten);
        }
      }
    }
  }

  X86Mem _rewriteMemOperand(ir.BaseNode anchor, X86Mem mem) {
    final base = _rewriteMemReg(anchor, mem.base, r11);
    final index = _rewriteMemReg(anchor, mem.index, r10);

    if (base == mem.base && index == mem.index) return mem;
    return X86Mem(
      base: base,
      index: index,
      scale: mem.scale,
      displacement: mem.displacement,
      size: mem.size,
      segment: mem.segment,
    );
  }

  BaseReg? _rewriteMemReg(ir.BaseNode anchor, BaseReg? reg, X86Gp temp) {
    if (reg is VirtReg) {
      final phys = _physRegForVirt(reg);
      if (phys is X86Gp) return phys;
      if (reg.isSpilled) {
        final slotIndex = reg.spillOffset ~/ 8;
        int offset = 0;
        if (_funcFrame != null) {
          offset = _funcFrame!.getLocalOffset(slotIndex);
        } else {
          offset = -8 - reg.spillOffset;
        }
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kMov, [ir.RegOperand(temp), ir.MemOperand(X86Mem.baseDisp(rbp, offset))]),
            anchor);
        return temp;
      }
      // TODO: Support vector regs in memory addressing.
      return reg;
    }
    return reg;
  }

  BaseReg? _physRegForVirt(VirtReg vreg) {
    if (vreg.physReg != null) {
      return vreg.physReg;
    }
    if (vreg.physXmm != null) {
      BaseReg phys = vreg.physXmm!;
      if (vreg.regClass == RegClass.ymm) {
        phys = (phys as X86Xmm).ymm;
      } else if (vreg.regClass == RegClass.zmm) {
        phys = (phys as X86Xmm).zmm;
      }
      return phys;
    }
    return null;
  }

  void _setFuncArg(int index, BaseReg reg) {
    if (reg is VirtReg) {
      while (_argRegs.length <= index) {
        _argRegs.add(null);
      }
      _argRegs[index] = reg;
    } else {
      // TODO: Support binding physical registers as arguments.
    }
  }

  void _lowerInvokeNodes() {
    final nodesToLower = <ir.InvokeNode>[];
    for (final node in nodes.nodes) {
      if (node is ir.InvokeNode) {
        nodesToLower.add(node);
      }
    }

    for (final node in nodesToLower) {
      _lowerInvokeNode(node);
      nodes.remove(node);
    }
  }

  void _lowerInvokeNode(ir.InvokeNode node) {
    final signature = node.signature;
    if (signature is! FuncSignature) {
      // TODO: Support invocations without signature metadata.
      return;
    }

    final detail = FuncDetail(signature, cc: callingConvention);
    final stackSize = _alignStack(detail.stackArgsSize);

    if (stackSize > 0) {
      nodes.insertBefore(
          ir.InstNode(
              X86InstId.kSub, [ir.RegOperand(rsp), ir.ImmOperand(stackSize)]),
          node);
    }

    final moves = <_CallMove>[];

    for (int i = 0; i < detail.argValues.length; i++) {
      if (i >= node.args.length) break;
      final argInfo = detail.argValues[i];
      final arg = node.args[i];

      if (argInfo.isReg) {
        if (argInfo.regType == FuncRegType.gp) {
          final dst = argInfo.gpReg!;
          moves.add(_CallMove(dst, arg));
        } else if (argInfo.regType == FuncRegType.xmm ||
            argInfo.regType == FuncRegType.ymm ||
            argInfo.regType == FuncRegType.zmm) {
          _emitCallVecMove(node, argInfo, arg);
        }
      } else if (argInfo.isStack) {
        _emitCallStackArg(node, argInfo, arg);
      }
    }

    _emitCallMoves(node, moves);

    if (node.target is Label) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kCall, [ir.LabelOperand(node.target as Label)]),
          node);
    } else if (node.target is BaseReg) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kCall, [ir.RegOperand(node.target as BaseReg)]),
          node);
    } else if (node.target is int) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kCall, [ir.ImmOperand(node.target as int)]),
          node);
    }

    if (stackSize > 0) {
      nodes.insertBefore(
          ir.InstNode(
              X86InstId.kAdd, [ir.RegOperand(rsp), ir.ImmOperand(stackSize)]),
          node);
    }

    if (node.ret != null) {
      _emitCallReturnMove(node, node.ret!, detail.retValue);
    }
  }

  void _emitCallMoves(ir.BaseNode anchor, List<_CallMove> moves) {
    if (moves.isEmpty) return;

    final used = <X86Gp>{};
    for (final move in moves) {
      used.add(move.dst);
      if (move.src is ir.RegOperand &&
          (move.src as ir.RegOperand).reg is X86Gp) {
        used.add((move.src as ir.RegOperand).reg as X86Gp);
      }
    }

    while (moves.isNotEmpty) {
      final idx = _findIndependentCallMove(moves);
      if (idx != -1) {
        final move = moves.removeAt(idx);
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kMov, [ir.RegOperand(move.dst), move.src]),
            anchor);
        continue;
      }

      final temp = _findTempReg(used);
      final move = moves.removeAt(0);
      if (temp != null) {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kMov, [ir.RegOperand(temp), move.src]),
            anchor);
        moves.insert(0, _CallMove(move.dst, ir.RegOperand(temp)));
        used.add(temp);
      } else {
        // TODO: Spill to stack if no temp is available.
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kMov, [ir.RegOperand(move.dst), move.src]),
            anchor);
      }
    }
  }

  int _findIndependentCallMove(List<_CallMove> moves) {
    for (var i = 0; i < moves.length; i++) {
      final dst = moves[i].dst;
      var usedAsSrc = false;
      for (var j = 0; j < moves.length; j++) {
        if (i == j) continue;
        final src = moves[j].src;
        if (src is ir.RegOperand && src.reg == dst) {
          usedAsSrc = true;
          break;
        }
      }
      if (!usedAsSrc) return i;
    }
    return -1;
  }

  void _emitCallVecMove(
      ir.BaseNode anchor, FuncValue argInfo, ir.Operand arg) {
    final regType = argInfo.regType;
    if (regType == FuncRegType.zmm) {
      // TODO: Add AVX-512 dispatcher support for ZMM moves.
      return;
    }

    final BaseReg dst = regType == FuncRegType.ymm
        ? X86Ymm(argInfo.regId)
        : X86Xmm(argInfo.regId);
    final instId =
        regType == FuncRegType.ymm ? X86InstId.kVmovups : X86InstId.kMovups;

    if (arg is ir.RegOperand &&
        (arg.reg is X86Xmm || arg.reg is X86Ymm || arg.reg is X86Zmm)) {
      nodes.insertBefore(
          ir.InstNode(instId, [ir.RegOperand(dst), arg]), anchor);
    } else if (arg is ir.MemOperand) {
      nodes.insertBefore(
          ir.InstNode(instId, [ir.RegOperand(dst), arg]), anchor);
    } else if (arg is ir.ImmOperand) {
      // TODO: Support immediate to vector register moves.
    }
  }

  void _emitCallStackArg(
      ir.BaseNode anchor, FuncValue argInfo, ir.Operand arg) {
    final mem = X86Mem.baseDisp(rsp, argInfo.stackOffset + 8);
    if (arg is ir.RegOperand && arg.reg is X86Gp) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.MemOperand(mem), arg]), anchor);
    } else if (arg is ir.ImmOperand) {
      final immValue = arg.value;
      if (immValue >= -2147483648 && immValue <= 2147483647) {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kMov, [ir.MemOperand(mem), arg]), anchor);
      } else {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kMov, [ir.RegOperand(r11), arg]), anchor);
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kMov, [ir.MemOperand(mem), ir.RegOperand(r11)]),
            anchor);
      }
    } else if (arg is ir.RegOperand &&
        (arg.reg is X86Xmm || arg.reg is X86Ymm)) {
      final instId =
          arg.reg is X86Ymm ? X86InstId.kVmovups : X86InstId.kMovups;
      nodes.insertBefore(
          ir.InstNode(instId, [ir.MemOperand(mem), arg]), anchor);
    } else {
      // TODO: Support additional stack argument kinds.
    }
  }

  void _emitCallReturnMove(
      ir.BaseNode anchor, BaseReg ret, FuncValue retInfo) {
    if (!retInfo.isReg) return;
    if (retInfo.regType == FuncRegType.gp) {
      final src = retInfo.gpReg;
      if (src != null && ret is X86Gp && src != ret) {
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kMov, [ir.RegOperand(ret), ir.RegOperand(src)]),
            anchor);
      }
      return;
    }

    if (retInfo.regType == FuncRegType.zmm) {
      // TODO: Add AVX-512 dispatcher support for ZMM return moves.
      return;
    }

    final BaseReg src = retInfo.regType == FuncRegType.ymm
        ? X86Ymm(retInfo.regId)
        : X86Xmm(retInfo.regId);
    final instId =
        retInfo.regType == FuncRegType.ymm ? X86InstId.kVmovups : X86InstId.kMovups;

    if (ret.runtimeType == src.runtimeType && ret.id != src.id) {
      nodes.insertBefore(
          ir.InstNode(
              instId, [ir.RegOperand(ret), ir.RegOperand(src)]),
          anchor);
    }
  }

  int _alignStack(int size) {
    if (size == 0) return 0;
    return (size + 15) & ~15;
  }

  bool _rewriteUnsupportedMemOps(ir.InstNode node) {
    const binaryReadWrite = {
      X86InstId.kAdd,
      X86InstId.kSub,
      X86InstId.kAnd,
      X86InstId.kOr,
      X86InstId.kXor,
      X86InstId.kImul,
      X86InstId.kShl,
      X86InstId.kShr,
      X86InstId.kSar,
      X86InstId.kRol,
      X86InstId.kRor,
    };
    const binaryReadOnly = {
      X86InstId.kCmp,
      X86InstId.kTest,
    };
    const unaryReadWrite = {
      X86InstId.kInc,
      X86InstId.kDec,
      X86InstId.kNeg,
      X86InstId.kNot,
    };
    const unaryReadOnly = {
      X86InstId.kMul,
      X86InstId.kDiv,
      X86InstId.kIdiv,
    };

    final instId = node.instId;
    final ops = node.operands;

    final isBinary = ops.length == 2;
    final isUnary = ops.length == 1;
    final isBinaryRw = binaryReadWrite.contains(instId);
    final isBinaryRo = binaryReadOnly.contains(instId);
    final isUnaryRw = unaryReadWrite.contains(instId);
    final isUnaryRo = unaryReadOnly.contains(instId);

    if (!isBinary && !isUnary) return false;
    if (!(isBinaryRw || isBinaryRo || isUnaryRw || isUnaryRo)) return false;

    final writeBack = isBinaryRw || isUnaryRw;

    if (isUnary) {
      final op = ops[0];
      if (op is! ir.MemOperand) return false;

      final load = ir.InstNode(
        X86InstId.kMov,
        [ir.RegOperand(r11), op],
      );
      nodes.insertBefore(load, node);
      ops[0] = ir.RegOperand(r11);

      if (writeBack) {
        final store = ir.InstNode(
          X86InstId.kMov,
          [op, ir.RegOperand(r11)],
        );
        nodes.insertAfter(store, node);
      }
      return true;
    }

    if (!isBinary) return false;

    final dst = ops[0];
    final src = ops[1];
    final hasMem = dst is ir.MemOperand || src is ir.MemOperand;
    if (!hasMem) return false;

    ir.MemOperand? dstMem;
    BaseReg dstTemp = r11;
    if (dst is ir.MemOperand) {
      dstMem = dst;
      if (src is ir.RegOperand && src.reg == r11) {
        dstTemp = r10;
      }
      final load = ir.InstNode(
        X86InstId.kMov,
        [ir.RegOperand(dstTemp), dst],
      );
      nodes.insertBefore(load, node);
      ops[0] = ir.RegOperand(dstTemp);
    }

    if (src is ir.MemOperand) {
      final useTemp = dstTemp == r11 ? r10 : r11;
      final load = ir.InstNode(
        X86InstId.kMov,
        [ir.RegOperand(useTemp), src],
      );
      nodes.insertBefore(load, node);
      ops[1] = ir.RegOperand(useTemp);
    } else if (src is ir.RegOperand &&
        (src.reg == r11 || src.reg == r10) &&
        dstMem == null) {
      // Keep source intact if we aren't rewriting destination.
    }

    if (dstMem != null && writeBack) {
      final store = ir.InstNode(
        X86InstId.kMov,
        [dstMem, ir.RegOperand(dstTemp)],
      );
      nodes.insertAfter(store, node);
    }

    return true;
  }

  /// SUB vreg, vreg/imm
  void sub(Object dst, Object src) {
    inst(X86InstId.kSub, [_toOperand(dst), _toOperand(src)]);
  }

  /// IMUL vreg, vreg
  void imul(Object dst, Object src) {
    inst(X86InstId.kImul, [_toOperand(dst), _toOperand(src)]);
  }

  /// XOR vreg, vreg
  void xor(Object dst, Object src) {
    inst(X86InstId.kXor, [_toOperand(dst), _toOperand(src)]);
  }

  /// AND vreg, vreg
  void and(Object dst, Object src) {
    inst(X86InstId.kAnd, [_toOperand(dst), _toOperand(src)]);
  }

  /// OR vreg, vreg
  void or(Object dst, Object src) {
    inst(X86InstId.kOr, [_toOperand(dst), _toOperand(src)]);
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
  void cmp(Object a, Object b) {
    inst(X86InstId.kCmp, [_toOperand(a), _toOperand(b)]);
  }

  /// TEST vreg, vreg
  void test(Object a, Object b) {
    inst(X86InstId.kTest, [_toOperand(a), _toOperand(b)]);
  }

  /// SHL vreg, imm8
  void shl(Object dst, int imm8) {
    inst(X86InstId.kShl, [_toOperand(dst), ir.ImmOperand(imm8)]);
  }

  /// SHR vreg, imm8
  void shr(Object dst, int imm8) {
    inst(X86InstId.kShr, [_toOperand(dst), ir.ImmOperand(imm8)]);
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

  /// Adds a function with the given signature.
  ir.FuncNode addFunc(FuncSignature signature,
      {String name = 'func', FuncFrame? frame, FuncFrameAttr? attr}) {
    final node = ir.FuncNode(
      name,
      frame: frame,
      signature: signature,
      argSetter: _setFuncArg,
    );
    addNode(node);
    _currentFunc = node;
    if (frame != null) {
      _funcFrame = frame;
    } else if (attr != null) {
      _funcFrame = FuncFrame.host(attr: attr);
    }
    return node;
  }

  /// Ends the current function by emitting a return.
  void endFunc() {
    // TODO: Emit a default return value based on signature if needed.
    ret();
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
    final asm = X86Assembler(code);
    _emitToAssembler(asm, frameAttrHint: frameAttrHint);

    if (useCache) {
      return runtime.addCached(code, key: cacheKey);
    }
    return runtime.add(code);
  }

  /// Finalizes the code without allocating executable memory.
  FinalizedCode finalize({FuncFrameAttr? frameAttrHint}) {
    final asm = X86Assembler(code);
    _emitToAssembler(asm, frameAttrHint: frameAttrHint);
    return code.finalize();
  }

  /// Emits a raw instruction by ID with generic operands.
  void emitInst(int instId, List<Object> ops, {int options = 0}) {
    inst(instId, ops.map(_toOperand).toList(), options: options);
  }

  /// Emits an invocation node (call with signature).
  ir.InvokeNode invoke(Object target, FuncSignature signature,
      {List<Object> args = const [], BaseReg? ret}) {
    final node = ir.InvokeNode(
      target: target,
      args: args.map(_toOperand).toList(),
      ret: ret,
      signature: signature,
    );
    addNode(node);
    return node;
  }

  void _emitToAssembler(X86Assembler asm, {FuncFrameAttr? frameAttrHint}) {
    // 1. Run register allocation on IR
    _ra.allocate(nodes);

    // 2. Calculate Frame (Prologue)
    if (_funcFrame == null) {
      // Determine used callee-saved registers
      final usedRegs = <X86Gp>{};
      for (final vreg in _ra.virtualRegs) {
        if (vreg.physReg != null) usedRegs.add(vreg.physReg!);
      }

      final preserved = <X86Gp>[];
      final calleeSaved = FuncFrame.host().calleeSavedRegs;
      for (final reg in usedRegs) {
        if (calleeSaved.contains(reg)) {
          preserved.add(reg);
        }
      }

      final spillSize = _ra.spillAreaSize;
      final attr = frameAttrHint ??
          (spillSize > 0 || preserved.isNotEmpty
              ? FuncFrameAttr.nonLeaf(
                  localStackSize: spillSize, preservedRegs: preserved)
              : FuncFrameAttr.leaf());
      _funcFrame = FuncFrame.host(attr: attr);
    }

    // 3. Rewrite IR with physical registers (now that we have frame offsets)
    _rewriteRegisters();

    // 3.5 Lower invoke nodes into actual call sequences.
    _lowerInvokeNodes();

    if (_funcFrame != null) {
      _frameEmitter = FuncFrameEmitter(_funcFrame!, asm);
      _frameEmitter!.emitPrologue();
    }

    // 4. Move Arguments (Prologue)
    _emitArgMoves(asm);

    // 5. Serialize the body (Nodes)
    // Use custom serializer to handle RET -> Epilogue
    final serializer = _FuncSerializer(asm, _frameEmitter);
    serialize(serializer);
  }

  void _emitArgMoves(X86Assembler asm) {
    final physArgRegs = _getPhysicalArgRegs();
    final moves = <_ArgMove>[];

    // Spills must be stored before any register moves that could clobber sources.
    for (int i = 0; i < _argRegs.length && i < physArgRegs.length; i++) {
      final argVreg = _argRegs[i];
      if (argVreg == null) continue;
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

class _CallMove {
  final X86Gp dst;
  final ir.Operand src;

  _CallMove(this.dst, this.src);
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
