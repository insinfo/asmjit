// Golden encodings of operand-size aware general purpose instructions used
// by the UniCompiler: the F6/F7 group (NEG/NOT/MUL/DIV/IDIV), shifts and
// rotates by CL/imm, CMOVcc, BSR/BSF/LZCNT/TZCNT/POPCNT, IMUL r, m, MOVBE,
// BSWAP, BT, SBB, PREFETCHT0 and the VEX forms ANDN/SHLX/SHRX/SARX/RORX.
// Expected bytes were produced by LLVM (clang -arch x86_64, Intel syntax).
import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

String hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Map<String, String> _encodeAll() {
  final out = <String, String>{};
  void emit(String text, void Function(X86Assembler a) f) {
    final code = CodeHolder(env: Environment.x64SysV());
    f(X86Assembler(code));
    out[text] = hex(code.text.buffer.bytes);
  }

  final regs = {
    32: [('ecx', X86Gp.r32(1)), ('r9d', X86Gp.r32(9))],
    64: [('rcx', X86Gp.r64(1)), ('r9', X86Gp.r64(9))],
  };
  X86Mem mem(int size) => X86Mem.baseIndexScale(X86Gp.r64(9), X86Gp.r64(0), 2,
      disp: 64, size: size);
  const memText = '[r9 + 2*rax + 64]';
  for (final bits in [32, 64]) {
    final ptr = bits == 32 ? 'dword' : 'qword';
    final r = regs[bits]!;
    for (final (n, f) in [
      ('neg', (X86Assembler a, X86Gp x) => a.neg(x)),
      ('not', (X86Assembler a, X86Gp x) => a.not(x))
    ]) {
      for (final (t, x) in r) {
        emit('$n $t', (a) => f(a, x));
      }
    }
    for (final (n, f) in [
      ('mul', (X86Assembler a, Object x) => a.mul(x)),
      ('div', (X86Assembler a, Object x) => a.div(x)),
      ('idiv', (X86Assembler a, Object x) => a.idiv(x))
    ]) {
      for (final (t, x) in r) {
        emit('$n $t', (a) => f(a, x));
      }
      emit('$n $ptr ptr $memText', (a) => f(a, mem(bits ~/ 8)));
    }
    for (final (t, x) in r) {
      emit('rol $t, cl', (a) => a.rolRCl(x));
      emit('ror $t, cl', (a) => a.rorRCl(x));
      emit('shl $t, cl', (a) => a.shlRCl(x));
      emit('shr $t, cl', (a) => a.shrRCl(x));
      emit('sar $t, cl', (a) => a.sarRCl(x));
      emit('rol $t, 5', (a) => a.rolRI(x, 5));
      emit('ror $t, 5', (a) => a.rorRI(x, 5));
      emit('sar $t, 7', (a) => a.sarRI(x, 7));
      emit('bswap $t', (a) => a.bswap(x));
    }
    final (d, dr) = r[1];
    final (s, sr) = r[0];
    for (final (cn, c) in [
      ('cmovb', X86Cond.b),
      ('cmovbe', X86Cond.be),
      ('cmovl', X86Cond.l),
      ('cmovg', X86Cond.g),
      ('cmove', X86Cond.e),
      ('cmovs', X86Cond.s)
    ]) {
      emit('$cn $d, $s', (a) => a.cmovcc(c, dr, sr));
      emit('$cn $s, $ptr ptr $memText', (a) => a.cmovcc(c, sr, mem(bits ~/ 8)));
    }
    for (final (n, f) in [
      ('bsr', (X86Assembler a, X86Gp x, Object y) => a.bsr(x, y)),
      ('bsf', (X86Assembler a, X86Gp x, Object y) => a.bsf(x, y)),
      ('lzcnt', (X86Assembler a, X86Gp x, Object y) => a.lzcnt(x, y)),
      ('tzcnt', (X86Assembler a, X86Gp x, Object y) => a.tzcnt(x, y)),
      ('popcnt', (X86Assembler a, X86Gp x, Object y) => a.popcnt(x, y)),
    ]) {
      emit('$n $d, $s', (a) => f(a, dr, sr));
      emit('$n $s, $ptr ptr $memText', (a) => f(a, sr, mem(bits ~/ 8)));
    }
    emit('imul $d, $ptr ptr $memText', (a) => a.imulRM(dr, mem(bits ~/ 8)));
    emit('movbe $d, $ptr ptr $memText', (a) => a.movbe(dr, mem(bits ~/ 8)));
    emit('bt $d, $s', (a) => a.bt(dr, sr));
    emit('bt $d, 13', (a) => a.btI(dr, 13));
    emit('sbb $d, $s', (a) => a.sbbRR(dr, sr));
    emit('andn $d, $s, $d', (a) => a.andn(dr, sr, dr));
    emit('andn $s, $d, $ptr ptr $memText',
        (a) => a.andn(sr, dr, mem(bits ~/ 8)));
    emit('shlx $d, $s, $d', (a) => a.shlx(dr, sr, dr));
    emit('shrx $s, $ptr ptr $memText, $d',
        (a) => a.shrx(sr, mem(bits ~/ 8), dr));
    emit('sarx $d, $s, $s', (a) => a.sarx(dr, sr, sr));
    emit('rorx $d, $s, 7', (a) => a.rorx(dr, sr, 7));
    emit('rorx $s, $ptr ptr $memText, 3', (a) => a.rorx(sr, mem(bits ~/ 8), 3));
  }
  emit('prefetcht0 byte ptr $memText', (a) => a.prefetcht0(mem(1)));
  return out;
}

const _expected = <String, String>{
  'neg ecx': 'f7d9',
  'neg r9d': '41f7d9',
  'not ecx': 'f7d1',
  'not r9d': '41f7d1',
  'mul ecx': 'f7e1',
  'mul r9d': '41f7e1',
  'mul dword ptr [r9 + 2*rax + 64]': '41f7644140',
  'div ecx': 'f7f1',
  'div r9d': '41f7f1',
  'div dword ptr [r9 + 2*rax + 64]': '41f7744140',
  'idiv ecx': 'f7f9',
  'idiv r9d': '41f7f9',
  'idiv dword ptr [r9 + 2*rax + 64]': '41f77c4140',
  'rol ecx, cl': 'd3c1',
  'ror ecx, cl': 'd3c9',
  'shl ecx, cl': 'd3e1',
  'shr ecx, cl': 'd3e9',
  'sar ecx, cl': 'd3f9',
  'rol ecx, 5': 'c1c105',
  'ror ecx, 5': 'c1c905',
  'sar ecx, 7': 'c1f907',
  'bswap ecx': '0fc9',
  'rol r9d, cl': '41d3c1',
  'ror r9d, cl': '41d3c9',
  'shl r9d, cl': '41d3e1',
  'shr r9d, cl': '41d3e9',
  'sar r9d, cl': '41d3f9',
  'rol r9d, 5': '41c1c105',
  'ror r9d, 5': '41c1c905',
  'sar r9d, 7': '41c1f907',
  'bswap r9d': '410fc9',
  'cmovb r9d, ecx': '440f42c9',
  'cmovb ecx, dword ptr [r9 + 2*rax + 64]': '410f424c4140',
  'cmovbe r9d, ecx': '440f46c9',
  'cmovbe ecx, dword ptr [r9 + 2*rax + 64]': '410f464c4140',
  'cmovl r9d, ecx': '440f4cc9',
  'cmovl ecx, dword ptr [r9 + 2*rax + 64]': '410f4c4c4140',
  'cmovg r9d, ecx': '440f4fc9',
  'cmovg ecx, dword ptr [r9 + 2*rax + 64]': '410f4f4c4140',
  'cmove r9d, ecx': '440f44c9',
  'cmove ecx, dword ptr [r9 + 2*rax + 64]': '410f444c4140',
  'cmovs r9d, ecx': '440f48c9',
  'cmovs ecx, dword ptr [r9 + 2*rax + 64]': '410f484c4140',
  'bsr r9d, ecx': '440fbdc9',
  'bsr ecx, dword ptr [r9 + 2*rax + 64]': '410fbd4c4140',
  'bsf r9d, ecx': '440fbcc9',
  'bsf ecx, dword ptr [r9 + 2*rax + 64]': '410fbc4c4140',
  'lzcnt r9d, ecx': 'f3440fbdc9',
  'lzcnt ecx, dword ptr [r9 + 2*rax + 64]': 'f3410fbd4c4140',
  'tzcnt r9d, ecx': 'f3440fbcc9',
  'tzcnt ecx, dword ptr [r9 + 2*rax + 64]': 'f3410fbc4c4140',
  'popcnt r9d, ecx': 'f3440fb8c9',
  'popcnt ecx, dword ptr [r9 + 2*rax + 64]': 'f3410fb84c4140',
  'imul r9d, dword ptr [r9 + 2*rax + 64]': '450faf4c4140',
  'movbe r9d, dword ptr [r9 + 2*rax + 64]': '450f38f04c4140',
  'bt r9d, ecx': '410fa3c9',
  'bt r9d, 13': '410fbae10d',
  'sbb r9d, ecx': '4119c9',
  'andn r9d, ecx, r9d': 'c44270f2c9',
  'andn ecx, r9d, dword ptr [r9 + 2*rax + 64]': 'c4c230f24c4140',
  'shlx r9d, ecx, r9d': 'c46231f7c9',
  'shrx ecx, dword ptr [r9 + 2*rax + 64], r9d': 'c4c233f74c4140',
  'sarx r9d, ecx, ecx': 'c46272f7c9',
  'rorx r9d, ecx, 7': 'c4637bf0c907',
  'rorx ecx, dword ptr [r9 + 2*rax + 64], 3': 'c4c37bf04c414003',
  'neg rcx': '48f7d9',
  'neg r9': '49f7d9',
  'not rcx': '48f7d1',
  'not r9': '49f7d1',
  'mul rcx': '48f7e1',
  'mul r9': '49f7e1',
  'mul qword ptr [r9 + 2*rax + 64]': '49f7644140',
  'div rcx': '48f7f1',
  'div r9': '49f7f1',
  'div qword ptr [r9 + 2*rax + 64]': '49f7744140',
  'idiv rcx': '48f7f9',
  'idiv r9': '49f7f9',
  'idiv qword ptr [r9 + 2*rax + 64]': '49f77c4140',
  'rol rcx, cl': '48d3c1',
  'ror rcx, cl': '48d3c9',
  'shl rcx, cl': '48d3e1',
  'shr rcx, cl': '48d3e9',
  'sar rcx, cl': '48d3f9',
  'rol rcx, 5': '48c1c105',
  'ror rcx, 5': '48c1c905',
  'sar rcx, 7': '48c1f907',
  'bswap rcx': '480fc9',
  'rol r9, cl': '49d3c1',
  'ror r9, cl': '49d3c9',
  'shl r9, cl': '49d3e1',
  'shr r9, cl': '49d3e9',
  'sar r9, cl': '49d3f9',
  'rol r9, 5': '49c1c105',
  'ror r9, 5': '49c1c905',
  'sar r9, 7': '49c1f907',
  'bswap r9': '490fc9',
  'cmovb r9, rcx': '4c0f42c9',
  'cmovb rcx, qword ptr [r9 + 2*rax + 64]': '490f424c4140',
  'cmovbe r9, rcx': '4c0f46c9',
  'cmovbe rcx, qword ptr [r9 + 2*rax + 64]': '490f464c4140',
  'cmovl r9, rcx': '4c0f4cc9',
  'cmovl rcx, qword ptr [r9 + 2*rax + 64]': '490f4c4c4140',
  'cmovg r9, rcx': '4c0f4fc9',
  'cmovg rcx, qword ptr [r9 + 2*rax + 64]': '490f4f4c4140',
  'cmove r9, rcx': '4c0f44c9',
  'cmove rcx, qword ptr [r9 + 2*rax + 64]': '490f444c4140',
  'cmovs r9, rcx': '4c0f48c9',
  'cmovs rcx, qword ptr [r9 + 2*rax + 64]': '490f484c4140',
  'bsr r9, rcx': '4c0fbdc9',
  'bsr rcx, qword ptr [r9 + 2*rax + 64]': '490fbd4c4140',
  'bsf r9, rcx': '4c0fbcc9',
  'bsf rcx, qword ptr [r9 + 2*rax + 64]': '490fbc4c4140',
  'lzcnt r9, rcx': 'f34c0fbdc9',
  'lzcnt rcx, qword ptr [r9 + 2*rax + 64]': 'f3490fbd4c4140',
  'tzcnt r9, rcx': 'f34c0fbcc9',
  'tzcnt rcx, qword ptr [r9 + 2*rax + 64]': 'f3490fbc4c4140',
  'popcnt r9, rcx': 'f34c0fb8c9',
  'popcnt rcx, qword ptr [r9 + 2*rax + 64]': 'f3490fb84c4140',
  'imul r9, qword ptr [r9 + 2*rax + 64]': '4d0faf4c4140',
  'movbe r9, qword ptr [r9 + 2*rax + 64]': '4d0f38f04c4140',
  'bt r9, rcx': '490fa3c9',
  'bt r9, 13': '490fbae10d',
  'sbb r9, rcx': '4919c9',
  'andn r9, rcx, r9': 'c442f0f2c9',
  'andn rcx, r9, qword ptr [r9 + 2*rax + 64]': 'c4c2b0f24c4140',
  'shlx r9, rcx, r9': 'c462b1f7c9',
  'shrx rcx, qword ptr [r9 + 2*rax + 64], r9': 'c4c2b3f74c4140',
  'sarx r9, rcx, rcx': 'c462f2f7c9',
  'rorx r9, rcx, 7': 'c463fbf0c907',
  'rorx rcx, qword ptr [r9 + 2*rax + 64], 3': 'c4c3fbf04c414003',
  'prefetcht0 byte ptr [r9 + 2*rax + 64]': '410f184c4140',
};

void main() {
  test('every form matches LLVM', () {
    final actual = _encodeAll();
    expect(actual.length, _expected.length);
    final mismatches = [
      for (final e in _expected.entries)
        if (actual[e.key] != e.value) '${e.key}: ${actual[e.key]} != ${e.value}'
    ];
    expect(mismatches, isEmpty);
  });
}
