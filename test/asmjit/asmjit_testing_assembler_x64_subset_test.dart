import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

List<int> _hexToBytes(String hex) {
  final s = hex.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (s.length.isOdd) {
    throw ArgumentError('hex length must be even');
  }
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    out.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return out;
}

List<int> _assemble(Environment env, void Function(X86Assembler) fn) {
  final code = CodeHolder(env: env);
  final asm = X86Assembler(code);
  fn(asm);
  // Igual ao AssemblerTester do C++: compara bytes do .text sem resolver relocations.
  return code.text.buffer.bytes;
}

void _testInst(String expectedHex, void Function(X86Assembler) fn,
    {Environment? env}) {
  final actual = _assemble(env ?? Environment.x64Windows(), fn);
  expect(actual, equals(_hexToBytes(expectedHex)));
}

void main() {
  if (!Environment.host().isX86Family) return;

  group('asmjit-testing (subset) - assembler x64', () {
    test('mov rax, 42 (movRI64 otimiza para mov eax, imm32)', () {
      _testInst('b82a000000', (a) => a.movRI64(rax, 42));
    });

    test('mov rcx, -1 (movRI64 usa mov r64, imm32 sign-extend)', () {
      _testInst('48c7c1ffffffff', (a) => a.movRI64(rcx, -1));
    });

    test('mov rax, rcx', () {
      _testInst('4889c8', (a) => a.movRR(rax, rcx));
    });

    test('mov r8, r9 (regs estendidos - REX.WRB)', () {
      _testInst('4d89c8', (a) => a.movRR(r8, r9));
    });

    test('add r8, r9 (regs estendidos - REX.WRB)', () {
      _testInst('4d01c8', (a) => a.addRR(r8, r9));
    });

    test('add rax, rcx', () {
      _testInst('4801c8', (a) => a.addRR(rax, rcx));
    });

    test('xor rax, rax', () {
      _testInst('4831c0', (a) => a.xorRR(rax, rax));
    });

    test('cmp rax, rcx', () {
      _testInst('4839c8', (a) => a.cmpRR(rax, rcx));
    });

    test('cmp rax, 1', () {
      _testInst('483d01000000', (a) => a.cmpRI(rax, 1));
    });

    test('cmp rcx, 1', () {
      _testInst('4881f901000000', (a) => a.cmpRI(rcx, 1));
    });

    test('push rax; pop rax', () {
      _testInst('5058', (a) {
        a.push(rax);
        a.pop(rax);
      });
    });

    test('push r15; pop r15 (regs estendidos)', () {
      _testInst('4157415f', (a) {
        a.push(r15);
        a.pop(r15);
      });
    });

    test('push imm8 42', () {
      _testInst('6a2a', (a) => a.pushImm8(42));
    });

    test('push imm32 0x12345678', () {
      _testInst('6878563412', (a) => a.pushImm32(0x12345678));
    });

    test('adc rax, rcx', () {
      _testInst('4811c8', (a) => a.adcRR(rax, rcx));
    });

    test('adc rax, 1', () {
      _testInst('4883d001', (a) => a.adcRI(rax, 1));
    });

    test('adc rax, 0x12345678 (imm32 forma curta em rax)', () {
      _testInst('481578563412', (a) => a.adcRI(rax, 0x12345678));
    });

    test('adc rcx, 0x12345678 (imm32 /2)', () {
      _testInst('4881d178563412', (a) => a.adcRI(rcx, 0x12345678));
    });

    test('jmp label', () {
      _testInst('e900000000', (a) {
        final l = a.newLabel();
        a.jmp(l);
      });
    });

    test('call label', () {
      _testInst('e800000000', (a) {
        final l = a.newLabel();
        a.call(l);
      });
    });

    test('je label (jcc rel32 placeholder)', () {
      _testInst('0f8400000000', (a) {
        final l = a.newLabel();
        a.je(l);
      });
    });

    test('jne label (jcc rel32 placeholder)', () {
      _testInst('0f8500000000', (a) {
        final l = a.newLabel();
        a.jne(l);
      });
    });

    test('sub rax, 8', () {
      _testInst('4883e808', (a) => a.subRI(rax, 8));
    });

    test('sbb rax, 0x12345678 (imm32 forma curta em rax)', () {
      _testInst('481d78563412', (a) => a.sbbRI(rax, 0x12345678));
    });

    test('sbb rcx, 0x12345678 (imm32 /3)', () {
      _testInst('4881d978563412', (a) => a.sbbRI(rcx, 0x12345678));
    });

    test('and rax, 1', () {
      _testInst('4883e001', (a) => a.andRI(rax, 1));
    });

    test('or rax, 1', () {
      _testInst('4883c801', (a) => a.orRI(rax, 1));
    });

    test('xor rax, 1', () {
      _testInst('4883f001', (a) => a.xorRI(rax, 1));
    });

    test('test rax, 1', () {
      _testInst('48a901000000', (a) => a.testRI(rax, 1));
    });

    test('imul rax, rcx', () {
      _testInst('480fafc1', (a) => a.imulRR(rax, rcx));
    });

    test('imul rax, rcx, 127 (imm8)', () {
      _testInst('486bc17f', (a) => a.imulRRI(rax, rcx, 127));
    });

    test('imul rax, rcx, 0x12345678 (imm32)', () {
      _testInst('4869c178563412', (a) => a.imulRRI(rax, rcx, 0x12345678));
    });

    test('imul rax, 2 (imulRI imm8)', () {
      _testInst('486bc002', (a) => a.imulRI(rax, 2));
    });

    test('imul rax, 0x12345678 (imulRI imm32)', () {
      _testInst('4869c078563412', (a) => a.imulRI(rax, 0x12345678));
    });

    test('xchg rax, rcx', () {
      _testInst('4891', (a) => a.xchg(rax, rcx));
    });

    test('lea rax, [rcx + 16]', () {
      _testInst('488d4110', (a) => a.lea(rax, qwordPtr(rcx, 16)));
    });

    test('movsx rax, cl (movsxB)', () {
      _testInst('480fbec1', (a) => a.movsxB(rax, cl));
    });

    test('movsx rax, cx (movsxW)', () {
      _testInst('480fbfc1', (a) => a.movsxW(rax, cx));
    });

    test('movzx rax, cl (movzxB)', () {
      _testInst('480fb6c1', (a) => a.movzxB(rax, cl));
    });

    test('movzx rax, cx (movzxW)', () {
      _testInst('480fb7c1', (a) => a.movzxW(rax, cx));
    });

    test('movsxd rax, ecx', () {
      _testInst('4863c1', (a) => a.movsxd(rax, ecx));
    });

    test('shl rax, 1', () {
      _testInst('48d1e0', (a) => a.shlRI(rax, 1));
    });

    test('shl rax, 3', () {
      _testInst('48c1e003', (a) => a.shlRI(rax, 3));
    });

    test('shl rax, cl', () {
      _testInst('48d3e0', (a) => a.shlRCl(rax));
    });

    test('shr rax, 1', () {
      _testInst('48d1e8', (a) => a.shrRI(rax, 1));
    });

    test('shr rax, 3', () {
      _testInst('48c1e803', (a) => a.shrRI(rax, 3));
    });

    test('shr rax, cl', () {
      _testInst('48d3e8', (a) => a.shrRCl(rax));
    });

    test('sar rax, 1', () {
      _testInst('48d1f8', (a) => a.sarRI(rax, 1));
    });

    test('sar rax, 3', () {
      _testInst('48c1f803', (a) => a.sarRI(rax, 3));
    });

    test('sar rax, cl', () {
      _testInst('48d3f8', (a) => a.sarRCl(rax));
    });

    test('rol rax, 1', () {
      _testInst('48d1c0', (a) => a.rolRI(rax, 1));
    });

    test('rol rax, 3', () {
      _testInst('48c1c003', (a) => a.rolRI(rax, 3));
    });

    test('ror rax, 1', () {
      _testInst('48d1c8', (a) => a.rorRI(rax, 1));
    });

    test('ror rax, 3', () {
      _testInst('48c1c803', (a) => a.rorRI(rax, 3));
    });

    test('cmove rax, rcx', () {
      _testInst('480f44c1', (a) => a.cmove(rax, rcx));
    });

    test('cmovne rax, rcx', () {
      _testInst('480f45c1', (a) => a.cmovne(rax, rcx));
    });

    test('cmovb rax, rcx', () {
      _testInst('480f42c1', (a) => a.cmovb(rax, rcx));
    });

    test('cmova rax, rcx', () {
      _testInst('480f47c1', (a) => a.cmova(rax, rcx));
    });

    test('cmovge rax, rcx', () {
      _testInst('480f4dc1', (a) => a.cmovge(rax, rcx));
    });

    test('cmovle rax, rcx', () {
      _testInst('480f4ec1', (a) => a.cmovle(rax, rcx));
    });

    test('sete al', () {
      _testInst('0f94c0', (a) => a.sete(rax));
    });

    test('setne cl', () {
      _testInst('0f95c1', (a) => a.setne(rcx));
    });

    test('setl cl', () {
      _testInst('0f9cc1', (a) => a.setl(rcx));
    });

    test('setg cl', () {
      _testInst('0f9fc1', (a) => a.setg(rcx));
    });

    test('setb al', () {
      _testInst('0f92c0', (a) => a.setcc(X86Cond.b, rax));
    });

    test('seta al', () {
      _testInst('0f97c0', (a) => a.setcc(X86Cond.a, rax));
    });

    test('cdq', () {
      _testInst('99', (a) => a.cdq());
    });

    test('cqo', () {
      _testInst('4899', (a) => a.cqo());
    });

    test('mul rcx', () {
      _testInst('48f7e1', (a) => a.mul(rcx));
    });

    test('mulx rdx, rax, rcx (BMI2)', () {
      _testInst('c4a2fbf6d1', (a) => a.mulx(rdx, rax, rcx));
    });

    test('div rcx', () {
      _testInst('48f7f1', (a) => a.div(rcx));
    });

    test('idiv rcx', () {
      _testInst('48f7f9', (a) => a.idiv(rcx));
    });

    test('bsf rax, rcx', () {
      _testInst('480fbcc1', (a) => a.bsf(rax, rcx));
    });

    test('bsr rax, rcx', () {
      _testInst('480fbdc1', (a) => a.bsr(rax, rcx));
    });

    test('popcnt rax, rcx', () {
      _testInst('f3480fb8c1', (a) => a.popcnt(rax, rcx));
    });

    test('lzcnt rax, rcx', () {
      _testInst('f3480fbdc1', (a) => a.lzcnt(rax, rcx));
    });

    test('tzcnt rax, rcx', () {
      _testInst('f3480fbcc1', (a) => a.tzcnt(rax, rcx));
    });

    test('add rax, [rcx + 16]', () {
      _testInst('48034110', (a) {
        a.addRM(rax, qwordPtr(rcx, 16));
      });
    });

    test('and rax, [rcx + 16]', () {
      _testInst('48234110', (a) => a.andRM(rax, qwordPtr(rcx, 16)));
    });

    test('or rax, [rcx + 16]', () {
      _testInst('480b4110', (a) => a.orRM(rax, qwordPtr(rcx, 16)));
    });

    test('xor rax, [rcx + 16]', () {
      _testInst('48334110', (a) => a.xorRM(rax, qwordPtr(rcx, 16)));
    });

    test('cmp rax, [rcx + 16]', () {
      _testInst('483b4110', (a) => a.cmpRM(rax, qwordPtr(rcx, 16)));
    });

    test('test rax, [rcx + 16]', () {
      _testInst('48854110', (a) => a.testRM(rax, qwordPtr(rcx, 16)));
    });

    test('and rax, [rsp + 16] (SIB obrigatório por base=rsp)', () {
      _testInst('4823442410', (a) => a.andRM(rax, qwordPtr(rsp, 16)));
    });

    test('cmp rax, [rsp + 16] (SIB obrigatório por base=rsp)', () {
      _testInst('483b442410', (a) => a.cmpRM(rax, qwordPtr(rsp, 16)));
    });

    test('and rax, [rcx + rdx*2 + 16] (SIB scale=2 disp8)', () {
      _testInst('4823445110', (a) {
        final mem = X86Mem.baseIndexScale(rcx, rdx, 2, disp: 16, size: 8);
        a.andRM(rax, mem);
      });
    });

    test('or rax, [rcx + rdx*4 + 16] (SIB scale=4 disp8)', () {
      _testInst('480b449110', (a) {
        final mem = X86Mem.baseIndexScale(rcx, rdx, 4, disp: 16, size: 8);
        a.orRM(rax, mem);
      });
    });

    test('xor rax, [rcx + rdx*8 + 16] (SIB scale=8 disp8)', () {
      _testInst('483344d110', (a) {
        final mem = X86Mem.baseIndexScale(rcx, rdx, 8, disp: 16, size: 8);
        a.xorRM(rax, mem);
      });
    });

    test('sub rax, [rcx + rdx*2 + 128] (SIB scale=2 disp32)', () {
      _testInst('482b845180000000', (a) {
        final mem = X86Mem.baseIndexScale(rcx, rdx, 2, disp: 128, size: 8);
        a.subRM(rax, mem);
      });
    });

    test('cmp rax, [rcx + rdx*4 + 128] (SIB scale=4 disp32)', () {
      _testInst('483b849180000000', (a) {
        final mem = X86Mem.baseIndexScale(rcx, rdx, 4, disp: 128, size: 8);
        a.cmpRM(rax, mem);
      });
    });

    test('test rax, [rcx + rdx*8 + 128] (SIB scale=8 disp32)', () {
      _testInst('488584d180000000', (a) {
        final mem = X86Mem.baseIndexScale(rcx, rdx, 8, disp: 128, size: 8);
        a.testRM(rax, mem);
      });
    });

    test('mov [rcx + 16], rax', () {
      _testInst('48894110', (a) {
        a.movMR(qwordPtr(rcx, 16), rax);
      });
    });

    test('mov rax, [rcx + rdx + 128]', () {
      _testInst('488b841180000000', (a) {
        final mem = X86Mem.baseIndexScale(rcx, rdx, 1, disp: 128, size: 8);
        a.movRM(rax, mem);
      });
    });

    test('mov rax, [rbp] (base=rbp requer disp8=0)', () {
      _testInst('488b4500', (a) {
        a.movRM(rax, qwordPtr(rbp));
      });
    });

    test('mov rax, [rsp] (base=rsp requer SIB)', () {
      _testInst('488b0424', (a) {
        a.movRM(rax, qwordPtr(rsp));
      });
    });

    test('jmp curto (label bound, rel8)', () {
      _testInst('90909090909090909090ebf4', (a) {
        final l = a.newLabel();
        a.bind(l);
        // 10 bytes.
        for (var i = 0; i < 10; i++) {
          a.nop();
        }
        // disp8 = 0 - (10 + 2) = -12 = 0xF4
        a.jmp(l);
      });
    });

    test('jmp near (label bound, rel32)', () {
      _testInst('${'90' * 200}e933ffffff', (a) {
        final l = a.newLabel();
        a.bind(l);
        for (var i = 0; i < 200; i++) {
          a.nop();
        }
        // disp32 = 0 - (200 + 5) = -205 = 0xFFFFFF33
        a.jmp(l);
      });
    });

    test('je curto (label bound, rel8)', () {
      _testInst('9090909090909090909074f4', (a) {
        final l = a.newLabel();
        a.bind(l);
        for (var i = 0; i < 10; i++) {
          a.nop();
        }
        // disp8 = 0 - (10 + 2) = -12 = 0xF4
        a.je(l);
      });
    });

    test('je near (label bound, rel32)', () {
      _testInst('${'90' * 200}0f8432ffffff', (a) {
        final l = a.newLabel();
        a.bind(l);
        for (var i = 0; i < 200; i++) {
          a.nop();
        }
        // disp32 = 0 - (200 + 6) = -206 = 0xFFFFFF32
        a.je(l);
      });
    });
  });
}
