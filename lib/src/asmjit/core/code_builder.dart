/// AsmJit Code Builder
///
/// High-level code builder that integrates virtual registers with
/// the X86Assembler and Register Allocator.

import 'code_holder.dart';
import 'regalloc.dart';
import 'environment.dart';
import 'operand.dart';
import 'labels.dart';
import 'error.dart';
import 'emitter.dart';
import 'func_frame_emitter.dart';
import '../x86/x86.dart';
import '../x86/x86_operands.dart';
import '../x86/x86_assembler.dart';
import '../x86/x86_serializer.dart';
import '../x86/x86_inst_db.g.dart';
import '../x86/x86_simd.dart';
import 'builder.dart' as ir;
import 'func.dart';
import 'type.dart';
import 'arch.dart';
import 'support.dart' as support;
import '../runtime/jit_runtime.dart';

extension FuncValueX86Extensions on FuncValue {
  X86Gp? get gpReg =>
      isReg && regType == FuncRegType.gp ? X86Gp.r64(regId) : null;
}

extension FuncDetailX86Extensions on FuncDetail {
  List<FuncValue> get argValues => List.generate(argCount, (i) => getArg(i));
}

/// A high-level code builder that uses virtual registers.
///
/// This builder allows you to write code using virtual registers,
/// which are automatically allocated to physical registers.
class X86CodeBuilder extends ir.BaseBuilder {
  /// The underlying code holder.
  final CodeHolder code;

  /// The register allocator.
  final RALocal _ra;

  RALocal get ra => _ra;

  /// Current label binding position is handled by BaseBuilder nodes.

  /// Whether the builder is for 64-bit mode.
  final bool is64Bit;

  /// Calling convention.
  final CallingConvention callingConvention;

  /// Encoding options forwarded to the assembler.
  int encodingOptions = EncodingOptions.kNone;

  /// Diagnostic options forwarded to the compiler pipeline.
  int diagnosticOptions = DiagnosticOptions.kNone;

  /// Argument virtual registers.
  final List<VirtReg?> _argRegs = [];
  final List<BaseReg?> _fixedArgRegs = [];

  // ignore: unused_field - reserved for future return value tracking
  VirtReg? _returnReg;

  // Function frame (if any)
  FuncFrame? _funcFrame;

  // Function frame emitter
  FuncFrameEmitter? _frameEmitter;

  // ignore: unused_field - reserved for function tracking in compiler mode.
  ir.FuncNode? _currentFunc;

  // Tracks whether the frame was provided explicitly (skip recomputation).
  bool _frameProvided = false;
  bool _argsMaterialized = false;

  /// Legacy constructor for compatibility with legacy tests.
  factory X86CodeBuilder({Environment? env}) => X86CodeBuilder.create(env: env);

  X86CodeBuilder._({
    required this.code,
    required this.is64Bit,
    required this.callingConvention,
  }) : _ra = RALocal(code.env.arch);

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

  /// Creates a code builder that targets an existing [CodeHolder].
  factory X86CodeBuilder.forCodeHolder(CodeHolder code) {
    final env = code.env;
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

  /// MOVZX (zero-extend move).
  void movzx(Object dst, Object src) {
    inst(X86InstId.kMovzx, [_toOperand(dst), _toOperand(src)]);
  }

  /// MOVSXD (sign-extend move).
  void movsxd(Object dst, Object src) {
    inst(X86InstId.kMovsxd, [_toOperand(dst), _toOperand(src)]);
  }

  /// MOV immediate to register.
  void movRI(X86Gp dst, int imm) => mov(dst, imm);

  /// MOV register to register.
  void movRR(X86Gp dst, X86Gp src) => mov(dst, src);

  /// TEST reg/reg or reg/mem.
  void test(Object op1, Object op2) {
    inst(X86InstId.kTest, [_toOperand(op1), _toOperand(op2)]);
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
            final mem = _spillMemFor(ret);
            if (mem != null && ret.regClass == RegClass.gp) {
              final temp = _sizedGpTempFor(ret.size);
              node.ret = temp;
              nodes.insertAfter(
                  ir.InstNode(X86InstId.kMov,
                      [ir.MemOperand(mem), ir.RegOperand(temp)]),
                  node);
            } else {
              final sizedMem =
                  mem == null || ret.size == 0 ? mem : mem.withSize(ret.size);
              if (sizedMem != null && ret.regClass == RegClass.xmm) {
                node.ret = xmm0;
                nodes.insertAfter(
                    ir.InstNode(X86InstId.kMovups,
                        [ir.MemOperand(sizedMem), ir.RegOperand(xmm0)]),
                    node);
              } else if (sizedMem != null && ret.regClass == RegClass.ymm) {
                node.ret = ymm0;
                nodes.insertAfter(
                    ir.InstNode(X86InstId.kVmovups,
                        [ir.MemOperand(sizedMem), ir.RegOperand(ymm0)]),
                    node);
              } else if (sizedMem != null && ret.regClass == RegClass.zmm) {
                node.ret = zmm0;
                nodes.insertAfter(
                    ir.InstNode(X86InstId.kVmovups,
                        [ir.MemOperand(sizedMem), ir.RegOperand(zmm0)]),
                    node);
              }
            }
          }
        }
      }
    }
  }

  X86Mem? _spillMemFor(VirtReg vreg) {
    if (!vreg.isSpilled) return null;
    final slotIndex = vreg.spillOffset ~/ 8;
    int offset = 0;
    if (_funcFrame != null) {
      offset = _funcFrame!.getLocalOffset(slotIndex);
    } else {
      offset = -8 - vreg.spillOffset;
    }
    return X86Mem.baseDisp(rbp, offset);
  }

  X86Gp _sizedGpTempFor(int size) {
    if (size <= 1) return r11.r8;
    if (size == 2) return r11.r16;
    if (size == 4) return r11.r32;
    return r11;
  }

  void _rewriteOperandList(ir.BaseNode anchor, List<ir.Operand> operands) {
    print('[DEBUG] _rewriteOperandList: node=$anchor');
    for (int i = 0; i < operands.length; i++) {
      final op = operands[i];
      print('[DEBUG]   operand $i: $op (${op.runtimeType})');
      if (op is ir.RegOperand && op.reg is VirtReg) {
        final vreg = op.reg as VirtReg;
        final phys = _physRegForVirt(vreg);
        print('[DEBUG]     vreg.id=${vreg.id}, phys=$phys');
        if (phys != null) {
          operands[i] = ir.RegOperand(phys);
          print('[DEBUG]     -> replaced with $phys');
        } else if (vreg.isSpilled) {
          final slotIndex = vreg.spillOffset ~/ 8;
          int offset = 0;
          if (_funcFrame != null) {
            offset = _funcFrame!.getLocalOffset(slotIndex);
          } else {
            offset = -8 - vreg.spillOffset;
          }
          operands[i] =
              ir.MemOperand(X86Mem.baseDisp(rbp, offset, size: vreg.size));
          print('[DEBUG]     -> spilled to [rbp+$offset]');
        }
      } else if (op is ir.MemOperand && op.mem is X86Mem) {
        final mem = op.mem as X86Mem;
        final rewritten = _rewriteMemOperand(anchor, mem);
        if (rewritten != mem) {
          operands[i] = ir.MemOperand(rewritten);
          print('[DEBUG]     -> mem rewritten to $rewritten');
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
      // DEBUG
      print('[DEBUG] _rewriteMemReg: vreg.id=${reg.id}, vreg.size=${reg.size}, '
          'vreg.physReg=${reg.physReg}, phys=$phys, phys.runtimeType=${phys.runtimeType}');
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
            ir.InstNode(X86InstId.kMov, [
              ir.RegOperand(temp),
              ir.MemOperand(X86Mem.baseDisp(rbp, offset, size: reg.size))
            ]),
            anchor);
        return temp;
      }
      final physVec = reg.physXmm;
      if (physVec != null) {
        final dst = is64Bit ? temp : temp.r32;
        final instId = is64Bit ? X86InstId.kMovq : X86InstId.kMovd;
        // Use the low bits of the vector register as an address base/index.
        nodes.insertBefore(
            ir.InstNode(instId, [ir.RegOperand(dst), ir.RegOperand(physVec)]),
            anchor);
        return dst;
      }
      print(
          '[DEBUG] _rewriteMemReg: FAILED to find physical reg for vreg.id=${reg.id}!');
      return reg;
    }
    return reg;
  }

  BaseReg? _physRegForVirt(VirtReg vreg) {
    if (vreg.physReg != null) {
      final phys = vreg.physReg!;
      if (vreg.size == 4) return phys.r32;
      if (vreg.size == 2) return phys.r16;
      if (vreg.size == 1) return phys.r8;
      return phys;
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

    // Fallback for function arguments: if the vreg is an argument and has no
    // allocated physical register, use the calling convention's argument register.
    // This handles cases where the RA didn't allocate the arg to a different register.
    final argIndex = _argRegs.indexOf(vreg);
    if (argIndex >= 0 && argIndex < _getPhysicalArgRegs().length) {
      final physArgReg = _getPhysicalArgRegs()[argIndex];
      if (vreg.size == 4) return physArgReg.r32;
      if (vreg.size == 2) return physArgReg.r16;
      if (vreg.size == 1) return physArgReg.r8;
      return physArgReg;
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
      while (_fixedArgRegs.length <= index) {
        _fixedArgRegs.add(null);
      }
      _fixedArgRegs[index] = reg;
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
      _emitCallWithoutSignature(node);
      return;
    }

    final detail = FuncDetail();
    detail.init(signature, code.env);
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

  void _emitCallWithoutSignature(ir.InvokeNode node) {
    // No ABI metadata: assume caller already placed arguments.
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

    final ret = node.ret;
    if (ret == null) return;
    if (ret is X86Gp && ret != rax) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.RegOperand(ret), ir.RegOperand(rax)]),
          node);
      return;
    }
    if (ret is X86Xmm && ret.id != 0) {
      nodes.insertBefore(
          ir.InstNode(
              X86InstId.kMovups, [ir.RegOperand(ret), ir.RegOperand(xmm0)]),
          node);
      return;
    }
    if (ret is X86Ymm && ret.id != 0) {
      nodes.insertBefore(
          ir.InstNode(
              X86InstId.kVmovups, [ir.RegOperand(ret), ir.RegOperand(ymm0)]),
          node);
      return;
    }
    if (ret is X86Zmm && ret.id != 0) {
      nodes.insertBefore(
          ir.InstNode(
              X86InstId.kVmovups, [ir.RegOperand(ret), ir.RegOperand(zmm0)]),
          node);
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
            ir.InstNode(X86InstId.kMov, [ir.RegOperand(move.dst), move.src]),
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
        if (move.src is ir.RegOperand &&
            (move.src as ir.RegOperand).reg is X86Gp) {
          final srcReg = (move.src as ir.RegOperand).reg as X86Gp;
          nodes.insertBefore(
              ir.InstNode(X86InstId.kPush, [ir.RegOperand(srcReg)]), anchor);
          nodes.insertBefore(
              ir.InstNode(X86InstId.kPop, [ir.RegOperand(move.dst)]), anchor);
        } else {
          nodes.insertBefore(
              ir.InstNode(X86InstId.kMov, [ir.RegOperand(move.dst), move.src]),
              anchor);
        }
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

  void _emitCallVecMove(ir.BaseNode anchor, FuncValue argInfo, ir.Operand arg) {
    final regType = argInfo.regType;
    if (regType == FuncRegType.zmm) {
      final dst = X86Zmm(argInfo.regId);
      const instId = X86InstId.kVmovups;
      if (arg is ir.RegOperand &&
          (arg.reg is X86Xmm || arg.reg is X86Ymm || arg.reg is X86Zmm)) {
        nodes.insertBefore(
            ir.InstNode(instId, [ir.RegOperand(dst), arg]), anchor);
      } else if (arg is ir.MemOperand) {
        nodes.insertBefore(
            ir.InstNode(instId, [ir.RegOperand(dst), arg]), anchor);
      } else if (arg is ir.ImmOperand) {
        _emitVecImmMove(anchor, dst, arg.value);
      }
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
      if (arg.value == 0) {
        if (regType == FuncRegType.ymm) {
          nodes.insertBefore(
              ir.InstNode(X86InstId.kVpxor,
                  [ir.RegOperand(dst), ir.RegOperand(dst), ir.RegOperand(dst)]),
              anchor);
        } else {
          nodes.insertBefore(
              ir.InstNode(
                  X86InstId.kPxor, [ir.RegOperand(dst), ir.RegOperand(dst)]),
              anchor);
        }
      } else {
        _emitVecImmMove(anchor, dst, arg.value);
      }
    }
  }

  void _emitVecImmMove(ir.BaseNode anchor, BaseReg dst, int immValue) {
    final bytes = dst is X86Zmm
        ? 64
        : dst is X86Ymm
            ? 32
            : 16;
    nodes.insertBefore(
        ir.InstNode(X86InstId.kSub, [ir.RegOperand(rsp), ir.ImmOperand(bytes)]),
        anchor);
    nodes.insertBefore(
        ir.InstNode(
            X86InstId.kMov, [ir.RegOperand(r11), ir.ImmOperand(immValue)]),
        anchor);
    for (int offset = 0; offset < bytes; offset += 8) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [
            ir.MemOperand(X86Mem.baseDisp(rsp, offset)),
            ir.RegOperand(r11)
          ]),
          anchor);
    }
    final instId = dst is X86Xmm ? X86InstId.kMovups : X86InstId.kVmovups;
    nodes.insertBefore(
        ir.InstNode(instId,
            [ir.RegOperand(dst), ir.MemOperand(X86Mem.baseDisp(rsp, 0))]),
        anchor);
    nodes.insertBefore(
        ir.InstNode(X86InstId.kAdd, [ir.RegOperand(rsp), ir.ImmOperand(bytes)]),
        anchor);
  }

  void _emitCallStackArg(
      ir.BaseNode anchor, FuncValue argInfo, ir.Operand arg) {
    final mem = X86Mem.baseDisp(rsp, argInfo.stackOffset + 8);
    if (arg is ir.RegOperand && arg.reg is VirtReg) {
      final vreg = arg.reg as VirtReg;
      final phys = _physRegForVirt(vreg);
      if (phys != null) {
        arg = ir.RegOperand(phys);
      } else if (vreg.isSpilled) {
        final spill = _spillMemFor(vreg);
        if (spill != null) {
          arg = ir.MemOperand(spill.withSize(vreg.size));
        }
      }
    }
    if (arg is ir.RegOperand && arg.reg is X86Gp) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.MemOperand(mem), arg]), anchor);
    } else if (arg is ir.ImmOperand) {
      final immValue = arg.value;
      final sizeBytes = argInfo.typeId.sizeInBytes;
      if (sizeBytes > 8) {
        _emitStackImmFill(anchor, mem, sizeBytes, immValue);
      } else if (immValue >= -2147483648 && immValue <= 2147483647) {
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
        (arg.reg is X86Xmm || arg.reg is X86Ymm || arg.reg is X86Zmm)) {
      final instId = (arg.reg is X86Ymm || arg.reg is X86Zmm)
          ? X86InstId.kVmovups
          : X86InstId.kMovups;
      nodes.insertBefore(
          ir.InstNode(instId, [ir.MemOperand(mem), arg]), anchor);
    } else if (arg is ir.MemOperand && arg.mem is X86Mem) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.RegOperand(r11), arg]), anchor);
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.MemOperand(mem), ir.RegOperand(r11)]),
          anchor);
    } else if (arg is ir.LabelOperand) {
      final labelOffset = code.getLabelOffset(arg.label);
      if (labelOffset == null) {
        throw AsmJitException(AsmJitError.invalidLabel,
            'Unbound label used as stack argument: L${arg.label.id}');
      }
      nodes.insertBefore(
          ir.InstNode(
              X86InstId.kMov, [ir.RegOperand(r11), ir.ImmOperand(labelOffset)]),
          anchor);
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.MemOperand(mem), ir.RegOperand(r11)]),
          anchor);
    } else {
      throw AsmJitException.invalidArgument(
          'Unsupported stack argument kind: ${arg.runtimeType}');
    }
  }

  void _emitStackImmFill(
      ir.BaseNode anchor, X86Mem baseMem, int sizeBytes, int immValue) {
    nodes.insertBefore(
        ir.InstNode(
            X86InstId.kMov, [ir.RegOperand(r11), ir.ImmOperand(immValue)]),
        anchor);

    var offset = 0;
    var remaining = sizeBytes;
    while (remaining >= 8) {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [
            ir.MemOperand(baseMem
                .withDisplacement(baseMem.displacement + offset)
                .withSize(8)),
            ir.RegOperand(r11)
          ]),
          anchor);
      remaining -= 8;
      offset += 8;
    }

    if (remaining > 0) {
      final reg = _sizedGpTempFor(remaining);
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [
            ir.MemOperand(baseMem
                .withDisplacement(baseMem.displacement + offset)
                .withSize(remaining)),
            ir.RegOperand(reg)
          ]),
          anchor);
    }
  }

  void _emitCallReturnMove(ir.BaseNode anchor, BaseReg ret, FuncValue retInfo) {
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
      if (ret is X86Zmm) {
        final src = X86Zmm(retInfo.regId);
        if (ret.id != src.id) {
          nodes.insertBefore(
              ir.InstNode(
                  X86InstId.kVmovups, [ir.RegOperand(ret), ir.RegOperand(src)]),
              anchor);
        }
      }
      return;
    }

    final BaseReg src = retInfo.regType == FuncRegType.ymm
        ? X86Ymm(retInfo.regId)
        : X86Xmm(retInfo.regId);
    final instId = retInfo.regType == FuncRegType.ymm
        ? X86InstId.kVmovups
        : X86InstId.kMovups;

    if (ret.runtimeType == src.runtimeType && ret.id != src.id) {
      nodes.insertBefore(
          ir.InstNode(instId, [ir.RegOperand(ret), ir.RegOperand(src)]),
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
  void testInst(Object a, Object b) {
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
    _currentFunc ??= node;
    if (frame != null) {
      _funcFrame = frame;
      _frameProvided = true;
    } else if (attr != null) {
      _funcFrame = FuncFrame.host(attr: attr);
      _frameProvided = true;
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
      _frameProvided = true;
    } else {
      final finalAttr = attr ?? FuncFrameAttributes.nonLeaf();
      _funcFrame = FuncFrame.host(attr: finalAttr);
      _frameProvided = attr != null;
    }

    // Emit code to load arguments into virtual registers
    if (_funcFrame != null) {
      final detail = FuncDetail();
      detail.init(signature, code.env);

      for (int i = 0; i < signature.argCount; i++) {
        final arg = detail.getArg(i);
        final type = signature.arg(i);
        final size = type.sizeInBytes > 0 ? type.sizeInBytes : 8;

        // Ensure vreg exists with correct properties
        while (_argRegs.length <= i) _argRegs.add(null);
        if (_argRegs[i] == null) {
          var regClass = RegClass.gp;
          if (type.isVec || type.isFloat) {
            if (type.isVec512)
              regClass = RegClass.zmm;
            else if (type.isVec256)
              regClass = RegClass.ymm;
            else
              regClass = RegClass.xmm;
          }
          _argRegs[i] = _ra.newVirtReg(size: size, regClass: regClass);
        }
        final vreg = _argRegs[i]!;

        if (arg.isReg) {
          // Arguments passed in registers are handled by _emitArgMoves during build.
          // We do NOT emit explicit moves in the IR because implicit register
          // args (RCX, etc.) might be reused/clobbered by the time execution reaches here.
          // The register allocator/prologue ensures 'vreg' holds the correct value.
          // NOTE: Do NOT set _argsMaterialized = true here, as _emitArgMoves must still run.
        } else if (arg.isStack) {
          final offset = _funcFrame!.getStackArgOffset(i, null, true);
          final mem = X86Mem.baseDisp(rbp, offset);

          if (type.isFloat) {
            if (type == TypeId.float32)
              movss(vreg, mem);
            else
              movsd(vreg, mem);
          } else if (type.isVec) {
            if (type.sizeInBytes == 32)
              vmovups(vreg, mem);
            else if (type.sizeInBytes == 64)
              vmovups(vreg, mem);
            else
              movups(vreg, mem);
          } else {
            mov(vreg, mem);
          }
        }
      }

      // Only mark args as materialized if ALL args are stack-based.
      // If any arg is in a register, _emitArgMoves must run during build.
      final hasRegisterArg = Iterable.generate(signature.argCount)
          .any((i) => detail.getArg(i).isReg);
      _argsMaterialized = !hasRegisterArg;
    } else {
      // No funcFrame means no proper calling convention handling.
      _argsMaterialized = true;
    }
    return node;
  }

  /// Ends the current function by emitting a return.
  void endFunc() {
    final signature = _currentFunc?.signature;
    if (_returnReg == null && signature is FuncSignature && signature.hasRet) {
      final retType = signature.retType.deabstract(is64Bit ? 8 : 4);
      if (retType.isInt) {
        final size = retType.sizeInBytes;
        final reg = size <= 1
            ? al
            : size == 2
                ? ax
                : size == 4
                    ? eax
                    : rax;
        mov(reg, 0);
      } else if (retType.isFloat) {
        if (retType == TypeId.float64 || retType == TypeId.float80) {
          xorpd(xmm0, xmm0);
        } else {
          xorps(xmm0, xmm0);
        }
      } else if (retType.isVec) {
        final bytes = retType.sizeInBytes;
        if (bytes <= 16) {
          inst(X86InstId.kPxor, [ir.RegOperand(xmm0), ir.RegOperand(xmm0)]);
        } else if (bytes <= 32) {
          inst(X86InstId.kVpxor,
              [ir.RegOperand(ymm0), ir.RegOperand(ymm0), ir.RegOperand(ymm0)]);
        } else {
          inst(X86InstId.kVpxord,
              [ir.RegOperand(zmm0), ir.RegOperand(zmm0), ir.RegOperand(zmm0)]);
        }
      } else if (retType.isMask) {
        final bytes = retType.sizeInBytes;
        if (bytes <= 2) {
          mov(eax, 0);
          inst(X86InstId.kKmovw, [_toOperand(k0), _toOperand(eax)]);
        } else if (bytes <= 4) {
          mov(eax, 0);
          inst(X86InstId.kKmovd, [_toOperand(k0), _toOperand(eax)]);
        } else {
          mov(rax, 0);
          inst(X86InstId.kKmovq, [_toOperand(k0), _toOperand(rax)]);
        }
      } else if (retType.isMmx) {
        // MMX aliases XMM0 on x86-64; zero XMM0 to return a default value.
        inst(X86InstId.kPxor, [ir.RegOperand(xmm0), ir.RegOperand(xmm0)]);
      } else {
        mov(rax, 0);
      }
    }
    ret();
  }

  void _lowerFuncNodes() {
    final nodesToRemove = <ir.BaseNode>[];
    for (final node in nodes.nodes) {
      if (node is ir.FuncNode) {
        _currentFunc ??= node;
        if (node.frame is FuncFrame) {
          _funcFrame ??= node.frame as FuncFrame;
        }
        nodesToRemove.add(node);
      } else if (node is ir.FuncRetNode) {
        final signature = _currentFunc?.signature;
        if (_returnReg == null &&
            signature is FuncSignature &&
            signature.hasRet) {
          _emitDefaultReturnBefore(node, signature);
        }
        nodes.insertBefore(ir.InstNode(X86InstId.kRet, const []), node);
        nodesToRemove.add(node);
      }
    }

    for (final node in nodesToRemove) {
      nodes.remove(node);
    }
  }

  void _emitDefaultReturnBefore(ir.BaseNode anchor, FuncSignature signature) {
    final retType = signature.retType.deabstract(is64Bit ? 8 : 4);
    if (retType.isInt) {
      final size = retType.sizeInBytes;
      final reg = size <= 1
          ? al
          : size == 2
              ? ax
              : size == 4
                  ? eax
                  : rax;
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.RegOperand(reg), ir.ImmOperand(0)]),
          anchor);
    } else if (retType.isFloat) {
      if (retType == TypeId.float64 || retType == TypeId.float80) {
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kXorpd, [ir.RegOperand(xmm0), ir.RegOperand(xmm0)]),
            anchor);
      } else {
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kXorps, [ir.RegOperand(xmm0), ir.RegOperand(xmm0)]),
            anchor);
      }
    } else if (retType.isVec) {
      final bytes = retType.sizeInBytes;
      if (bytes <= 16) {
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kPxor, [ir.RegOperand(xmm0), ir.RegOperand(xmm0)]),
            anchor);
      } else if (bytes <= 32) {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kVpxor, [
              ir.RegOperand(ymm0),
              ir.RegOperand(ymm0),
              ir.RegOperand(ymm0)
            ]),
            anchor);
      } else {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kVpxord, [
              ir.RegOperand(zmm0),
              ir.RegOperand(zmm0),
              ir.RegOperand(zmm0)
            ]),
            anchor);
      }
    } else if (retType.isMask) {
      final bytes = retType.sizeInBytes;
      if (bytes <= 2) {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kMov, [ir.RegOperand(eax), ir.ImmOperand(0)]),
            anchor);
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kKmovw, [ir.RegOperand(k0), ir.RegOperand(eax)]),
            anchor);
      } else if (bytes <= 4) {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kMov, [ir.RegOperand(eax), ir.ImmOperand(0)]),
            anchor);
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kKmovd, [ir.RegOperand(k0), ir.RegOperand(eax)]),
            anchor);
      } else {
        nodes.insertBefore(
            ir.InstNode(X86InstId.kMov, [ir.RegOperand(rax), ir.ImmOperand(0)]),
            anchor);
        nodes.insertBefore(
            ir.InstNode(
                X86InstId.kKmovq, [ir.RegOperand(k0), ir.RegOperand(rax)]),
            anchor);
      }
    } else if (retType.isMmx) {
      nodes.insertBefore(
          ir.InstNode(
              X86InstId.kPxor, [ir.RegOperand(xmm0), ir.RegOperand(xmm0)]),
          anchor);
    } else {
      nodes.insertBefore(
          ir.InstNode(X86InstId.kMov, [ir.RegOperand(rax), ir.ImmOperand(0)]),
          anchor);
    }
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

  /// Imports nodes from [src] and resets builder state.
  void importNodes(ir.NodeList src) {
    final imported = src.nodes.toList();
    clear();
    _ra.reset();
    _argRegs.clear();
    _fixedArgRegs.clear();
    _returnReg = null;
    _funcFrame = null;
    _frameEmitter = null;
    _currentFunc = null;
    _frameProvided = false;
    _argsMaterialized = false;

    for (final node in imported) {
      addNode(node);
    }
  }

  /// Emits the current nodes to the given assembler.
  void emitToAssembler(X86Assembler asm, {FuncFrameAttr? frameAttrHint}) {
    _emitToAssembler(asm, frameAttrHint: frameAttrHint);
  }

  void _emitToAssembler(X86Assembler asm, {FuncFrameAttr? frameAttrHint}) {
    asm.encodingOptions = encodingOptions;
    asm.diagnosticOptions = diagnosticOptions;

    _lowerFuncNodes();

    // 1. Run register allocation on IR
    _ra.allocate(nodes);

    final signature = _currentFunc?.signature;
    final hasStackArgs = signature != null
        ? (() {
            final detail = FuncDetail();
            detail.init(signature as FuncSignature, code.env);
            return detail.stackArgCount > 0;
          })()
        : false;

    // 2. Calculate Frame (Prologue)
    if (_funcFrame == null || !_frameProvided) {
      // Determine used callee-saved registers.
      final usedRegs = <X86Gp>{};
      for (final vreg in _ra.virtualRegs) {
        if (vreg.physReg != null) usedRegs.add(vreg.physReg!);
      }

      final preserved = <X86Gp>[];
      final calleeSavedMask = FuncFrame.host().preservedRegs(RegGroup.gp);
      for (final reg in usedRegs) {
        if ((calleeSavedMask & support.bitMask(reg.id)) != 0) {
          preserved.add(reg);
        }
      }

      final spillSize = _ra.spillAreaSize;
      final needsNonLeaf =
          hasStackArgs || spillSize > 0 || preserved.isNotEmpty;
      if (_funcFrame == null) {
        final attr = frameAttrHint ??
            (needsNonLeaf
                ? FuncFrameAttributes.nonLeaf()
                : FuncFrameAttributes());
        _funcFrame = FuncFrame.host(
          attr: attr,
          localStackSize: spillSize,
          preservedRegs: preserved.toList(),
        );
      } else {
        if (needsNonLeaf) {
          _funcFrame!.addAttributes(FuncFrameAttributes.nonLeaf().attributes);
        }
        _funcFrame!.setLocalStackSize(_funcFrame!.localStackSize + spillSize);
        for (final reg in preserved) {
          _funcFrame!.addDirtyRegs(reg.group, 1 << reg.id);
          _funcFrame!.setPreservedRegs(
              reg.group, _funcFrame!.preservedRegs(reg.group) | (1 << reg.id));
        }
      }
    }

    // 3. Rewrite IR with physical registers (now that we have frame offsets)
    _rewriteRegisters();

    // 3.5 Lower invoke nodes into actual call sequences.
    _lowerInvokeNodes();

    if (_funcFrame != null) {
      _frameEmitter = FuncFrameEmitter(_funcFrame!, asm);
      _frameEmitter!.emitPrologue();
    }

    _ra.emitRegMoves(asm);

    // 4. Move Arguments (Prologue)
    if (!_argsMaterialized &&
        (_argRegs.isNotEmpty || _fixedArgRegs.isNotEmpty)) {
      _emitArgMoves(asm);
    }

    // 5. Serialize the body (Nodes)
    // Use custom serializer to handle RET -> Epilogue
    final serializer = _FuncSerializer(asm, _frameEmitter);
    serialize(serializer);
  }

  void _emitArgMoves(X86Assembler asm) {
    print('[DEBUG] _emitArgMoves called');
    final physArgRegs = _getPhysicalArgRegs();
    final physVecArgRegs = _getPhysicalVecArgRegs();
    final moves = <_ArgMove>[];

    print(
        '[DEBUG] _argRegs.length=${_argRegs.length}, physArgRegs=$physArgRegs');

    // Spills must be stored before any register moves that could clobber sources.
    for (int i = 0; i < _argRegs.length && i < physArgRegs.length; i++) {
      final argVreg = _argRegs[i];
      final fixed = i < _fixedArgRegs.length ? _fixedArgRegs[i] : null;
      if (argVreg == null) {
        print('[DEBUG]   arg $i: vreg=null, skipping');
        continue;
      }
      if (fixed != null) {
        print('[DEBUG]   arg $i: fixed=$fixed, skipping');
        continue;
      }
      final physArg = physArgRegs[i];
      print(
          '[DEBUG]   arg $i: vreg.id=${argVreg.id}, vreg.physReg=${argVreg.physReg}, '
          'physArg=$physArg, isSpilled=${argVreg.isSpilled}');
      if (argVreg.isSpilled) {
        final slotIndex = argVreg.spillOffset ~/ 8;
        final offset = _funcFrame != null
            ? _funcFrame!.getLocalOffset(slotIndex)
            : (-8 - argVreg.spillOffset);
        print('[DEBUG]     -> spilling to [rbp+$offset]');
        asm.movMR(X86Mem.baseDisp(rbp, offset), physArg);
      } else if (argVreg.physReg != null && argVreg.physReg != physArg) {
        print('[DEBUG]     -> adding move: ${argVreg.physReg} <- $physArg');
        moves.add(_ArgMove(argVreg.physReg!, physArg));
      } else {
        print('[DEBUG]     -> no move needed (physReg == physArg or null)');
      }
    }

    for (int i = 0; i < _fixedArgRegs.length && i < physArgRegs.length; i++) {
      final fixed = _fixedArgRegs[i];
      if (fixed == null) continue;
      final physArg = physArgRegs[i];
      if (fixed is X86Gp) {
        if (fixed != physArg) {
          moves.add(_ArgMove(fixed, physArg));
        }
      } else {
        // Handled in the vector-arg pass below.
      }
    }

    for (int i = 0;
        i < _fixedArgRegs.length && i < physVecArgRegs.length;
        i++) {
      final fixed = _fixedArgRegs[i];
      if (fixed == null) continue;
      if (fixed is X86Xmm || fixed is X86Ymm || fixed is X86Zmm) {
        final srcXmm = physVecArgRegs[i];
        if (fixed is X86Xmm) {
          if (fixed.id != srcXmm.id) {
            asm.movupsXX(fixed, srcXmm);
          }
        } else if (fixed is X86Ymm) {
          final src = X86Ymm(srcXmm.id);
          if (fixed.id != src.id) {
            asm.vmovupsYY(fixed, src);
          }
        } else if (fixed is X86Zmm) {
          final src = X86Zmm(srcXmm.id);
          if (fixed.id != src.id) {
            asm.vmovupsZmm(fixed, src);
          }
        }
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
        print('[DEBUG] _emitArgMoves: emitting MOV ${m.dst}, ${m.src}');
        asm.movRR(m.dst, m.src);
        continue;
      }

      // Cycle detected. Eliminate a dependency.
      // Pick the first move: dst <- src.
      // It is blocked because 'dst' is used as a source in another move.
      // To resolve:
      // 1. Move 'dst' to 'temp'.
      // 2. Update the other move to use 'temp' as source.
      // 3. Now 'dst' can be overwritten.
      final temp = _findTempReg(used);
      if (temp != null) {
        final m = moves[0]; // Don't remove yet
        // Find who uses m.dst as source
        var foundDependency = false;
        for (final other in moves) {
          if (other != m && other.src == m.dst) {
            // Found dependency: other.dst <- other.src (which is m.dst)
            // Save m.dst to temp
            if (!foundDependency) {
              asm.movRR(temp, m.dst);
              used.add(temp);
              foundDependency = true;
            }
            // Rewrite 'other' to use temp as source
            // We need to modify the list in-place or replace the object
            // Since _ArgMove is immutable, we replace it in the list
            final newOther = _ArgMove(other.dst, temp);
            final otherIdx = moves.indexOf(other);
            moves[otherIdx] = newOther;
          }
        }

        // Now m.dst is no longer needed as source (we moved it to temp).
        // So m is independent?
        // Let loop continue, _findIndependentMove will pick it up (or another one).
        if (!foundDependency) {
          // Should not happen if _findIndependentMove failed, unless self-cycle?
          // Or if all moves invoke src==dst? (nop) - handled by builder?
          // If we are here, there is a cycle.
          // Fallback: This logic should inevitably break a dependency.
          // If we didn't find dependency, maybe our graph logic is wrong?
          // Force execute 'm' via stack swap if no temp-based fix found?
          final m = moves.removeAt(0);
          asm.push(m.src);
          asm.pop(m.dst);
        }
      } else {
        // No temp available. Use stack swap.
        final m = moves.removeAt(0);
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
    // Only use volatile registers as temps to avoid clobbering callee-saved registers
    // which are not tracked by the frame calculator at this stage.
    // Common volatile set for Win64/SysV:
    const temps = [
      r11,
      r10,
      r9,
      r8,
      rcx,
      rdx,
      rax,
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

  List<X86Xmm> _getPhysicalVecArgRegs() {
    if (callingConvention == CallingConvention.win64) {
      return [xmm0, xmm1, xmm2, xmm3];
    } else {
      return [xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7];
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
