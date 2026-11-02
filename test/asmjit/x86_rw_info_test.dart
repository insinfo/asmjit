// x86QueryRWInfo() (port of x86::InstInternal::query_rw_info()) against
// upstream asmjit: the expected strings were printed by a program built
// against upstream asmjit (`InstAPI::query_rw_info(Arch::kX64, ...)`),
// printing per operand the OpRWFlags, physical id, read/write/extend byte
// masks and rm size, and the flags of the extra register.
import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/x86/x86_rw_info.dart';
import 'package:test/test.dart';

String _hex(int v) => BigInt.from(v).toUnsigned(64).toRadixString(16);

String _format(
    String name, int instId, List<Object> ops, int options, BaseReg? extraReg) {
  final rwi = InstRWInfo();
  final ok = x86QueryRWInfo(true, instId, ops, rwi,
      options: options, extraReg: extraReg);
  final sb = StringBuffer('$name err=${ok ? 0 : 1} inst=${rwi.instFlags}');
  if (ok) {
    for (var i = 0; i < ops.length; i++) {
      final o = rwi.operand(i);
      sb.write(' [${_hex(o.opFlags)} ${o.physId} ${_hex(o.readByteMask)} '
          '${_hex(o.writeByteMask)} ${_hex(o.extendByteMask)} rm${o.rmSize}]');
    }
    sb.write(' x[${_hex(rwi.extraReg.opFlags)}]');
  }
  return sb.toString();
}

const k2 = X86KReg(2);

final _cases = <(String, int, List<Object>, int, BaseReg?)>[
  (
    'imul3 err=0 inst=0 [112 2 0 f f0 rm0] [113 0 f f f0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kImul,
    <Object>[edx, eax, ecx],
    0,
    null
  ),
  (
    'imul2 err=0 inst=0 [13 255 f f f0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kImul,
    <Object>[eax, ecx],
    0,
    null
  ),
  (
    'imul3i err=0 inst=0 [12 255 0 f f0 rm0] [5 255 f 0 0 rm4] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kImul,
    <Object>[eax, ecx, Imm(3)],
    0,
    null
  ),
  (
    'idiv3 err=0 inst=0 [113 2 f f f0 rm0] [113 0 f f f0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kIdiv,
    <Object>[edx, eax, ecx],
    0,
    null
  ),
  (
    'mul3 err=0 inst=0 [112 2 0 f f0 rm0] [113 0 f f f0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kMul,
    <Object>[edx, eax, ecx],
    0,
    null
  ),
  (
    'movs err=0 inst=0 [23202 7 0 1 0 rm0] [23201 6 1 0 0 rm0] x[0]',
    X86InstId.kMovs,
    <Object>[X86Mem(base: rdi, size: 1), X86Mem(base: rsi, size: 1)],
    X86EmitOptions.kX86_Rep,
    rcx
  ),
  (
    'add err=0 inst=0 [17 255 f f f0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kAdd,
    <Object>[eax, ecx],
    0,
    null
  ),
  (
    'addmi err=0 inst=0 [1003 255 f f 0 rm0] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kAdd,
    <Object>[X86Mem(base: rax, size: 4), Imm(1)],
    0,
    null
  ),
  (
    'mov err=0 inst=1 [16 255 0 f f0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kMov,
    <Object>[eax, ecx],
    0,
    null
  ),
  (
    'mov8i err=0 inst=0 [6 255 0 1 0 rm1] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kMov,
    <Object>[al, Imm(0xFF)],
    0,
    null
  ),
  (
    'movmr err=0 inst=0 [5002 255 0 f 0 rm0] [1 255 f 0 0 rm0] x[0]',
    X86InstId.kMov,
    <Object>[X86Mem(base: rax, index: rcx, size: 4), ecx],
    0,
    null
  ),
  (
    'movrm err=0 inst=0 [12 255 0 f f0 rm0] [5001 255 f 0 0 rm0] x[0]',
    X86InstId.kMov,
    <Object>[ecx, X86Mem(base: rax, size: 4)],
    0,
    null
  ),
  (
    'movmi err=0 inst=0 [5002 255 0 f 0 rm0] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kMov,
    <Object>[X86Mem(base: rax, size: 4), Imm(0)],
    0,
    null
  ),
  (
    'movzx err=0 inst=0 [12 255 0 f f0 rm0] [5 255 1 0 0 rm1] x[0]',
    X86InstId.kMovzx,
    <Object>[eax, cl],
    0,
    null
  ),
  (
    'movsx err=0 inst=0 [12 255 0 f f0 rm0] [5 255 1 0 0 rm1] x[0]',
    X86InstId.kMovsx,
    <Object>[eax, cl],
    0,
    null
  ),
  (
    'shl err=0 inst=0 [17 255 f f f0 rm4] [101 1 1 0 0 rm0] x[0]',
    X86InstId.kShl,
    <Object>[eax, cl],
    0,
    null
  ),
  (
    'setz err=0 inst=0 [1002 255 0 1 0 rm0] x[0]',
    X86InstId.kSetz,
    <Object>[X86Mem(base: rax, size: 1)],
    0,
    null
  ),
  (
    'cmp err=0 inst=0 [5 255 f 0 0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kCmp,
    <Object>[eax, ecx],
    0,
    null
  ),
  (
    'xor err=0 inst=0 [17 255 f f f0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kXor,
    <Object>[eax, eax],
    0,
    null
  ),
  (
    'lea err=0 inst=0 [2 255 0 ff 0 rm0] [5001 255 0 0 0 rm0] x[0]',
    X86InstId.kLea,
    <Object>[rax, X86Mem(base: rcx, index: rdx)],
    0,
    null
  ),
  (
    'movd err=0 inst=0 [16 255 0 f fffffffffffffff0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kMovd,
    <Object>[xmm0, eax],
    0,
    null
  ),
  (
    'movdr err=0 inst=0 [16 255 0 f f0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kMovd,
    <Object>[eax, xmm0],
    0,
    null
  ),
  (
    'addss err=0 inst=0 [3 255 f f 0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kAddss,
    <Object>[xmm0, xmm1],
    0,
    null
  ),
  (
    'movss err=0 inst=1 [16 255 0 f 0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kMovss,
    <Object>[xmm0, xmm1],
    0,
    null
  ),
  (
    'movssm err=0 inst=0 [1002 255 0 f 0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kMovss,
    <Object>[X86Mem(base: rax), xmm1],
    0,
    null
  ),
  (
    'paddb err=0 inst=0 [13 255 ffff ffff ffffffffffff0000 rm0] [5 255 ffff 0 0 rm16] x[0]',
    X86InstId.kPaddb,
    <Object>[xmm0, xmm1],
    0,
    null
  ),
  (
    'vpternlogd err=0 inst=0 [2 255 0 ffffffffffffffff 0 rm0] [1 255 ffffffffffffffff 0 0 rm0] [5 255 ffffffffffffffff 0 0 rm64] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kVpternlogd,
    <Object>[zmm0, zmm0, zmm0, Imm(0xFF)],
    0,
    null
  ),
  (
    'kmovd err=0 inst=0 [16 255 0 f f0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kKmovd,
    <Object>[k1, eax],
    0,
    null
  ),
  (
    'vpcmpeqd err=0 inst=0 [12 255 0 0 ff rm0] [1 255 ffffffffffffffff 0 0 rm0] [5 255 ffffffffffffffff 0 0 rm64] x[1]',
    X86InstId.kVpcmpeqd,
    <Object>[k1, zmm0, zmm1],
    0,
    k2
  ),
  (
    'vpaddd err=0 inst=0 [12 255 0 ffffffff ffffffff00000000 rm0] [1 255 ffffffff 0 0 rm0] [5 255 ffffffff 0 0 rm32] x[0]',
    X86InstId.kVpaddd,
    <Object>[ymm0, ymm1, ymm2],
    0,
    null
  ),
  (
    'vmovdqu err=0 inst=0 [16 255 0 ffffffff ffffffff00000000 rm32] [1001 255 0 0 0 rm0] x[0]',
    X86InstId.kVmovdqu,
    <Object>[ymm0, X86Mem(base: rax)],
    0,
    null
  ),
  (
    'push err=0 inst=0 [5 255 ff 0 0 rm8] x[0]',
    X86InstId.kPush,
    <Object>[rax],
    0,
    null
  ),
  (
    'pop err=0 inst=0 [6 255 0 ff 0 rm8] x[0]',
    X86InstId.kPop,
    <Object>[rax],
    0,
    null
  ),
  (
    'inc err=0 inst=0 [17 255 f f f0 rm4] x[0]',
    X86InstId.kInc,
    <Object>[eax],
    0,
    null
  ),
  (
    'cmov err=0 inst=0 [13 255 f f f0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kCmovz,
    <Object>[eax, ecx],
    0,
    null
  ),
  (
    'xchg err=0 inst=0 [17 255 f f f0 rm4] [17 255 f f f0 rm4] x[0]',
    X86InstId.kXchg,
    <Object>[eax, ecx],
    0,
    null
  ),
  (
    'pshufd err=0 inst=0 [12 255 0 ffff ffffffffffff0000 rm0] [5 255 ffff 0 0 rm16] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kPshufd,
    <Object>[xmm0, xmm1, Imm(0)],
    0,
    null
  ),
  (
    'pblendvb err=0 inst=0 [13 255 ffff ffff ffffffffffff0000 rm0] [5 255 ffff 0 0 rm16] [101 0 ffff 0 0 rm0] x[0]',
    X86InstId.kPblendvb,
    <Object>[xmm0, xmm1, xmm0],
    0,
    null
  ),
  (
    'vpbroadcastd err=0 inst=0 [12 255 0 ffffffff ffffffff00000000 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kVpbroadcastd,
    <Object>[ymm0, xmm1],
    0,
    null
  ),
  (
    'call err=0 inst=0 [5 255 ff 0 0 rm8] x[0]',
    X86InstId.kCall,
    <Object>[rax],
    0,
    null
  ),
  (
    'jmp err=0 inst=0 [5 255 ff 0 0 rm8] x[0]',
    X86InstId.kJmp,
    <Object>[rax],
    0,
    null
  ),
  (
    'cdq err=0 inst=0 [112 2 0 f f0 rm0] [101 0 f 0 0 rm0] x[0]',
    X86InstId.kCdq,
    <Object>[edx, eax],
    0,
    null
  ),
  (
    'div1 err=0 inst=0 [113 2 f f f0 rm0] x[0]',
    X86InstId.kDiv,
    <Object>[ecx],
    0,
    null
  ),
  (
    'movups err=0 inst=1 [16 255 0 ffff ffffffffffff0000 rm16] [5 255 ffff 0 0 rm16] x[0]',
    X86InstId.kMovups,
    <Object>[xmm0, xmm1],
    0,
    null
  ),
  (
    'subsd err=0 inst=0 [3 255 ff ff 0 rm0] [5 255 ff 0 0 rm8] x[0]',
    X86InstId.kSubsd,
    <Object>[xmm0, xmm1],
    0,
    null
  ),
  (
    'cvtsi2sd err=0 inst=0 [2 255 0 ff 0 rm0] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kCvtsi2sd,
    <Object>[xmm0, eax],
    0,
    null
  ),
  (
    'rol err=0 inst=0 [17 255 f f f0 rm4] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kRol,
    <Object>[eax, Imm(3)],
    0,
    null
  ),
  (
    'bt err=0 inst=0 [5 255 f 0 0 rm4] [1 255 f 0 0 rm0] x[0]',
    X86InstId.kBt,
    <Object>[eax, ecx],
    0,
    null
  ),
  (
    'adc err=0 inst=0 [17 255 f f f0 rm4] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kAdc,
    <Object>[eax, Imm(0)],
    0,
    null
  ),
  (
    'test err=0 inst=0 [5 255 f 0 0 rm4] [1 255 f 0 0 rm0] x[0]',
    X86InstId.kTest,
    <Object>[eax, eax],
    0,
    null
  ),
  (
    'stos err=0 inst=0 [23202 7 0 f 0 rm0] [101 0 f 0 0 rm0] x[0]',
    X86InstId.kStos,
    <Object>[X86Mem(base: rdi, size: 4), eax],
    X86EmitOptions.kX86_Rep,
    rcx
  ),
  (
    'vmovdqu32k err=0 inst=1 [7 255 ffffffffffffffff ffffffffffffffff 0 rm64] [5 255 ffffffffffffffff 0 0 rm64] x[1]',
    X86InstId.kVmovdqu32,
    <Object>[zmm0, zmm1],
    0,
    k1
  ),
  (
    'vmovdqu8m err=0 inst=0 [1002 255 0 0 0 rm0] [5 255 ffffffffffffffff 0 0 rm64] x[0]',
    X86InstId.kVmovdqu8,
    <Object>[X86Mem(base: rax), zmm1],
    0,
    null
  ),
  (
    'pmullw err=0 inst=0 [13 255 ffff ffff ffffffffffff0000 rm0] [5 255 ffff 0 0 rm16] x[0]',
    X86InstId.kPmullw,
    <Object>[xmm0, xmm1],
    0,
    null
  ),
  (
    'xorps err=0 inst=0 [13 255 ffff ffff ffffffffffff0000 rm0] [5 255 ffff 0 0 rm16] x[0]',
    X86InstId.kXorps,
    <Object>[xmm0, xmm0],
    0,
    null
  ),
  (
    'movzxm err=0 inst=0 [12 255 0 f f0 rm0] [5001 255 1 0 0 rm0] x[0]',
    X86InstId.kMovzx,
    <Object>[eax, X86Mem(base: rax, index: rcx, size: 1)],
    0,
    null
  ),
  (
    'movsxd err=0 inst=0 [2 255 0 ff 0 rm0] [5001 255 f 0 0 rm0] x[0]',
    X86InstId.kMovsxd,
    <Object>[rax, X86Mem(base: rcx, index: rdx, scale: 4, size: 4)],
    0,
    null
  ),
  (
    'vmovd err=0 inst=0 [16 255 0 f fffffffffffffff0 rm4] [5 255 f 0 0 rm4] x[0]',
    X86InstId.kVmovd,
    <Object>[xmm0, eax],
    0,
    null
  ),
  (
    'movq err=0 inst=0 [6 255 0 ff 0 rm8] [5 255 ff 0 0 rm8] x[0]',
    X86InstId.kMovq,
    <Object>[rax, xmm0],
    0,
    null
  ),
  (
    'cvttsd2si err=0 inst=0 [12 255 0 f f0 rm0] [5 255 ff 0 0 rm8] x[0]',
    X86InstId.kCvttsd2si,
    <Object>[eax, xmm0],
    0,
    null
  ),
  (
    'sar err=0 inst=0 [7 255 ff ff 0 rm8] [0 0 0 0 0 rm0] x[0]',
    X86InstId.kSar,
    <Object>[rax, Imm(63)],
    0,
    null
  ),
  (
    'neg err=0 inst=0 [17 255 f f f0 rm4] x[0]',
    X86InstId.kNeg,
    <Object>[eax],
    0,
    null
  ),
  (
    'not err=0 inst=0 [17 255 f f f0 rm4] x[0]',
    X86InstId.kNot,
    <Object>[eax],
    0,
    null
  ),
  (
    'cqo err=0 inst=0 [102 2 0 ff 0 rm0] [101 0 ff 0 0 rm0] x[0]',
    X86InstId.kCqo,
    <Object>[rdx, rax],
    0,
    null
  ),
  (
    'movsd err=0 inst=0 [16 255 0 ff ffffffffffffff00 rm8] [1001 255 ff 0 0 rm0] x[0]',
    X86InstId.kMovsd,
    <Object>[xmm0, X86Mem(base: rax)],
    0,
    null
  ),
];

void main() {
  for (final (expected, id, ops, options, extraReg) in _cases) {
    final name = expected.split(' ').first;
    test(name, () {
      expect(_format(name, id, ops, options, extraReg), expected);
    });
  }
}
