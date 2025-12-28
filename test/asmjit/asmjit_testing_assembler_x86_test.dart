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

List<int> _assembleX86(void Function(X86Assembler) fn) {
  final code = CodeHolder(env: Environment.x86());
  final asm = X86Assembler(code);
  fn(asm);
  // Igual ao AssemblerTester do C++: compara bytes do .text sem resolver relocations.
  return code.text.buffer.bytes;
}

void _testInstX86(String expectedHex, void Function(X86Assembler) fn,
    {String? why}) {
  final actual = _assembleX86(fn);
  expect(actual, equals(_hexToBytes(expectedHex)), reason: why);
}

void main() {
  if (!Environment.host().isX86Family) return;

  group('asmjit-testing - assembler x86 (port incremental)', () {
    // Portado de:
    // referencias/asmjit-master/asmjit-testing/tests/asmjit_test_assembler_x86.cpp

    test('adc cl, 1', () {
      _testInstX86('80D101', (a) => a.adcRI(cl, 1), why: 'adc(cl, 1)');
    });

    test('adc ch, 1', () {
      _testInstX86('80D501', (a) => a.adcRI(ch, 1), why: 'adc(ch, 1)');
    });

    test('adc byte_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '8094118000000001',
        (a) => a.adcMI(bytePtrSIB(ecx, edx, 1, 128), 1),
        why: 'adc(byte_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('adc cx, 1', () {
      _testInstX86('6683D101', (a) => a.adcRI(cx, 1), why: 'adc(cx, 1)');
    });

    test('adc word_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '668394118000000001',
        (a) => a.adcMI(wordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'adc(word_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('adc ecx, 1', () {
      _testInstX86('83D101', (a) => a.adcRI(ecx, 1), why: 'adc(ecx, 1)');
    });

    test('adc dword_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '8394118000000001',
        (a) => a.adcMI(dwordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'adc(dword_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('adc cl, dl', () {
      _testInstX86('10D1', (a) => a.adcRR(cl, dl), why: 'adc(cl, dl)');
    });

    test('adc cl, dh', () {
      _testInstX86('10F1', (a) => a.adcRR(cl, dh), why: 'adc(cl, dh)');
    });

    test('adc ch, dl', () {
      _testInstX86('10D5', (a) => a.adcRR(ch, dl), why: 'adc(ch, dl)');
    });

    test('adc ch, dh', () {
      _testInstX86('10F5', (a) => a.adcRR(ch, dh), why: 'adc(ch, dh)');
    });

    test('adc ptr(ecx, edx, 0, 128), bl', () {
      _testInstX86(
        '109C1180000000',
        (a) => a.adcMR(bytePtrSIB(ecx, edx, 1, 128), bl),
        why: 'adc(ptr(ecx, edx, 0, 128), bl)',
      );
    });

    test('adc ptr(ecx, edx, 0, 128), bh', () {
      _testInstX86(
        '10BC1180000000',
        (a) => a.adcMR(bytePtrSIB(ecx, edx, 1, 128), bh),
        why: 'adc(ptr(ecx, edx, 0, 128), bh)',
      );
    });

    test('adc byte_ptr(ecx, edx, 0, 128), bl', () {
      _testInstX86(
        '109C1180000000',
        (a) => a.adcMR(bytePtrSIB(ecx, edx, 1, 128), bl),
        why: 'adc(byte_ptr(ecx, edx, 0, 128), bl)',
      );
    });

    test('adc byte_ptr(ecx, edx, 0, 128), bh', () {
      _testInstX86(
        '10BC1180000000',
        (a) => a.adcMR(bytePtrSIB(ecx, edx, 1, 128), bh),
        why: 'adc(byte_ptr(ecx, edx, 0, 128), bh)',
      );
    });

    test('adc cx, dx', () {
      _testInstX86('6611D1', (a) => a.adcRR(cx, dx), why: 'adc(cx, dx)');
    });

    test('adc ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '66119C1180000000',
        (a) => a.adcMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'adc(ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('adc word_ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '66119C1180000000',
        (a) => a.adcMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'adc(word_ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('adc ecx, edx', () {
      _testInstX86('11D1', (a) => a.adcRR(ecx, edx), why: 'adc(ecx, edx)');
    });

    test('adc ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '119C1180000000',
        (a) => a.adcMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'adc(ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('adc dword_ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '119C1180000000',
        (a) => a.adcMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'adc(dword_ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('adc cl, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '128C1A80000000',
        (a) => a.adcRM(cl, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'adc(cl, ptr(edx, ebx, 0, 128))',
      );
    });

    test('adc cl, byte_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '128C1A80000000',
        (a) => a.adcRM(cl, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'adc(cl, byte_ptr(edx, ebx, 0, 128))',
      );
    });

    test('adc ch, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '12AC1A80000000',
        (a) => a.adcRM(ch, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'adc(ch, ptr(edx, ebx, 0, 128))',
      );
    });

    test('adc ch, byte_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '12AC1A80000000',
        (a) => a.adcRM(ch, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'adc(ch, byte_ptr(edx, ebx, 0, 128))',
      );
    });

    test('adc cx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66138C1A80000000',
        (a) => a.adcRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'adc(cx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('adc cx, word_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66138C1A80000000',
        (a) => a.adcRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'adc(cx, word_ptr(edx, ebx, 0, 128))',
      );
    });

    test('adc ecx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '138C1A80000000',
        (a) => a.adcRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'adc(ecx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('adc ecx, dword_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '138C1A80000000',
        (a) => a.adcRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'adc(ecx, dword_ptr(edx, ebx, 0, 128))',
      );
    });

    // -----------------------------------------------------------------------
    // add(...) - próximo bloco no arquivo C++.
    // -----------------------------------------------------------------------

    test('add cl, 1', () {
      _testInstX86('80C101', (a) => a.addRI(cl, 1), why: 'add(cl, 1)');
    });

    test('add ch, 1', () {
      _testInstX86('80C501', (a) => a.addRI(ch, 1), why: 'add(ch, 1)');
    });

    test('add byte_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '8084118000000001',
        (a) => a.addMI(bytePtrSIB(ecx, edx, 1, 128), 1),
        why: 'add(byte_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('add cx, 1', () {
      _testInstX86('6683C101', (a) => a.addRI(cx, 1), why: 'add(cx, 1)');
    });

    test('add word_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '668384118000000001',
        (a) => a.addMI(wordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'add(word_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('add ecx, 1', () {
      _testInstX86('83C101', (a) => a.addRI(ecx, 1), why: 'add(ecx, 1)');
    });

    test('add dword_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '8384118000000001',
        (a) => a.addMI(dwordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'add(dword_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('add cl, dl', () {
      _testInstX86('00D1', (a) => a.addRR(cl, dl), why: 'add(cl, dl)');
    });

    test('add cl, dh', () {
      _testInstX86('00F1', (a) => a.addRR(cl, dh), why: 'add(cl, dh)');
    });

    test('add ch, dl', () {
      _testInstX86('00D5', (a) => a.addRR(ch, dl), why: 'add(ch, dl)');
    });

    test('add ch, dh', () {
      _testInstX86('00F5', (a) => a.addRR(ch, dh), why: 'add(ch, dh)');
    });

    test('add ptr(ecx, edx, 0, 128), bl', () {
      _testInstX86(
        '009C1180000000',
        (a) => a.addMR(bytePtrSIB(ecx, edx, 1, 128), bl),
        why: 'add(ptr(ecx, edx, 0, 128), bl)',
      );
    });

    test('add ptr(ecx, edx, 0, 128), bh', () {
      _testInstX86(
        '00BC1180000000',
        (a) => a.addMR(bytePtrSIB(ecx, edx, 1, 128), bh),
        why: 'add(ptr(ecx, edx, 0, 128), bh)',
      );
    });

    test('add byte_ptr(ecx, edx, 0, 128), bl', () {
      _testInstX86(
        '009C1180000000',
        (a) => a.addMR(bytePtrSIB(ecx, edx, 1, 128), bl),
        why: 'add(byte_ptr(ecx, edx, 0, 128), bl)',
      );
    });

    test('add byte_ptr(ecx, edx, 0, 128), bh', () {
      _testInstX86(
        '00BC1180000000',
        (a) => a.addMR(bytePtrSIB(ecx, edx, 1, 128), bh),
        why: 'add(byte_ptr(ecx, edx, 0, 128), bh)',
      );
    });

    test('add cx, dx', () {
      _testInstX86('6601D1', (a) => a.addRR(cx, dx), why: 'add(cx, dx)');
    });

    test('add ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '66019C1180000000',
        (a) => a.addMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'add(ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('add word_ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '66019C1180000000',
        (a) => a.addMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'add(word_ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('add ecx, edx', () {
      _testInstX86('01D1', (a) => a.addRR(ecx, edx), why: 'add(ecx, edx)');
    });

    test('add ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '019C1180000000',
        (a) => a.addMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'add(ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('add dword_ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '019C1180000000',
        (a) => a.addMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'add(dword_ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('add cl, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '028C1A80000000',
        (a) => a.addRM(cl, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'add(cl, ptr(edx, ebx, 0, 128))',
      );
    });

    test('add cl, byte_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '028C1A80000000',
        (a) => a.addRM(cl, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'add(cl, byte_ptr(edx, ebx, 0, 128))',
      );
    });

    test('add ch, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '02AC1A80000000',
        (a) => a.addRM(ch, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'add(ch, ptr(edx, ebx, 0, 128))',
      );
    });

    test('add ch, byte_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '02AC1A80000000',
        (a) => a.addRM(ch, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'add(ch, byte_ptr(edx, ebx, 0, 128))',
      );
    });

    test('add cx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66038C1A80000000',
        (a) => a.addRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'add(cx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('add cx, word_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66038C1A80000000',
        (a) => a.addRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'add(cx, word_ptr(edx, ebx, 0, 128))',
      );
    });

    test('add ecx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '038C1A80000000',
        (a) => a.addRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'add(ecx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('add ecx, dword_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '038C1A80000000',
        (a) => a.addRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'add(ecx, dword_ptr(edx, ebx, 0, 128))',
      );
    });

    // -----------------------------------------------------------------------
    // and_(...) - próximo bloco no arquivo C++.
    // -----------------------------------------------------------------------

    test('and_ cl, 1', () {
      _testInstX86('80E101', (a) => a.andRI(cl, 1), why: 'and_(cl, 1)');
    });

    test('and_ ch, 1', () {
      _testInstX86('80E501', (a) => a.andRI(ch, 1), why: 'and_(ch, 1)');
    });

    test('and_ cx, 1', () {
      _testInstX86('6683E101', (a) => a.andRI(cx, 1), why: 'and_(cx, 1)');
    });

    test('and_ ecx, 1', () {
      _testInstX86('83E101', (a) => a.andRI(ecx, 1), why: 'and_(ecx, 1)');
    });

    test('and_ byte_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '80A4118000000001',
        (a) => a.andMI(bytePtrSIB(ecx, edx, 1, 128), 1),
        why: 'and_(byte_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('and_ word_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '6683A4118000000001',
        (a) => a.andMI(wordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'and_(word_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('and_ dword_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '83A4118000000001',
        (a) => a.andMI(dwordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'and_(dword_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('and_ cl, dl', () {
      _testInstX86('20D1', (a) => a.andRR(cl, dl), why: 'and_(cl, dl)');
    });

    test('and_ cl, dh', () {
      _testInstX86('20F1', (a) => a.andRR(cl, dh), why: 'and_(cl, dh)');
    });

    test('and_ ch, dl', () {
      _testInstX86('20D5', (a) => a.andRR(ch, dl), why: 'and_(ch, dl)');
    });

    test('and_ ch, dh', () {
      _testInstX86('20F5', (a) => a.andRR(ch, dh), why: 'and_(ch, dh)');
    });

    test('and_ ptr(ecx, edx, 0, 128), bl', () {
      _testInstX86(
        '209C1180000000',
        (a) => a.andMR(bytePtrSIB(ecx, edx, 1, 128), bl),
        why: 'and_(ptr(ecx, edx, 0, 128), bl)',
      );
    });

    test('and_ ptr(ecx, edx, 0, 128), bh', () {
      _testInstX86(
        '20BC1180000000',
        (a) => a.andMR(bytePtrSIB(ecx, edx, 1, 128), bh),
        why: 'and_(ptr(ecx, edx, 0, 128), bh)',
      );
    });

    test('and_ byte_ptr(ecx, edx, 0, 128), bl', () {
      _testInstX86(
        '209C1180000000',
        (a) => a.andMR(bytePtrSIB(ecx, edx, 1, 128), bl),
        why: 'and_(byte_ptr(ecx, edx, 0, 128), bl)',
      );
    });

    test('and_ byte_ptr(ecx, edx, 0, 128), bh', () {
      _testInstX86(
        '20BC1180000000',
        (a) => a.andMR(bytePtrSIB(ecx, edx, 1, 128), bh),
        why: 'and_(byte_ptr(ecx, edx, 0, 128), bh)',
      );
    });

    test('and_ cx, dx', () {
      _testInstX86('6621D1', (a) => a.andRR(cx, dx), why: 'and_(cx, dx)');
    });

    test('and_ ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '66219C1180000000',
        (a) => a.andMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'and_(ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('and_ word_ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '66219C1180000000',
        (a) => a.andMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'and_(word_ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('and_ ecx, edx', () {
      _testInstX86('21D1', (a) => a.andRR(ecx, edx), why: 'and_(ecx, edx)');
    });

    test('and_ ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '219C1180000000',
        (a) => a.andMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'and_(ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('and_ dword_ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '219C1180000000',
        (a) => a.andMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'and_(dword_ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('and_ cl, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '228C1A80000000',
        (a) => a.andRM(cl, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'and_(cl, ptr(edx, ebx, 0, 128))',
      );
    });

    test('and_ cl, byte_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '228C1A80000000',
        (a) => a.andRM(cl, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'and_(cl, byte_ptr(edx, ebx, 0, 128))',
      );
    });

    test('and_ ch, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '22AC1A80000000',
        (a) => a.andRM(ch, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'and_(ch, ptr(edx, ebx, 0, 128))',
      );
    });

    test('and_ ch, byte_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '22AC1A80000000',
        (a) => a.andRM(ch, bytePtrSIB(edx, ebx, 1, 128)),
        why: 'and_(ch, byte_ptr(edx, ebx, 0, 128))',
      );
    });

    test('and_ cx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66238C1A80000000',
        (a) => a.andRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'and_(cx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('and_ cx, word_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66238C1A80000000',
        (a) => a.andRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'and_(cx, word_ptr(edx, ebx, 0, 128))',
      );
    });

    test('and_ ecx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '238C1A80000000',
        (a) => a.andRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'and_(ecx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('and_ ecx, dword_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '238C1A80000000',
        (a) => a.andRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'and_(ecx, dword_ptr(edx, ebx, 0, 128))',
      );
    });

    // -----------------------------------------------------------------------
    // arpl / bound / bsf / bsr / bswap / bt / btc - sequência no arquivo C++.
    // -----------------------------------------------------------------------

    test('arpl cx, dx', () {
      _testInstX86('63D1', (a) => a.arplRR(cx, dx), why: 'arpl(cx, dx)');
    });

    test('arpl ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '639C1180000000',
        (a) => a.arplMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'arpl(ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('arpl word_ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '639C1180000000',
        (a) => a.arplMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'arpl(word_ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('bound cx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66628C1A80000000',
        (a) => a.bound(cx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bound(cx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('bound cx, dword_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '66628C1A80000000',
        (a) => a.bound(cx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bound(cx, dword_ptr(edx, ebx, 0, 128))',
      );
    });

    test('bound ecx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '628C1A80000000',
        (a) => a.bound(ecx, qwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bound(ecx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('bound ecx, qword_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '628C1A80000000',
        (a) => a.bound(ecx, qwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bound(ecx, qword_ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsf cx, dx', () {
      _testInstX86('660FBCCA', (a) => a.bsf(cx, dx), why: 'bsf(cx, dx)');
    });

    test('bsf cx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '660FBC8C1A80000000',
        (a) => a.bsfRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsf(cx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsf cx, word_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '660FBC8C1A80000000',
        (a) => a.bsfRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsf(cx, word_ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsf ecx, edx', () {
      _testInstX86('0FBCCA', (a) => a.bsf(ecx, edx), why: 'bsf(ecx, edx)');
    });

    test('bsf ecx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '0FBC8C1A80000000',
        (a) => a.bsfRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsf(ecx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsf ecx, dword_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '0FBC8C1A80000000',
        (a) => a.bsfRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsf(ecx, dword_ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsr cx, dx', () {
      _testInstX86('660FBDCA', (a) => a.bsr(cx, dx), why: 'bsr(cx, dx)');
    });

    test('bsr cx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '660FBD8C1A80000000',
        (a) => a.bsrRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsr(cx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsr cx, word_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '660FBD8C1A80000000',
        (a) => a.bsrRM(cx, wordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsr(cx, word_ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsr ecx, edx', () {
      _testInstX86('0FBDCA', (a) => a.bsr(ecx, edx), why: 'bsr(ecx, edx)');
    });

    test('bsr ecx, ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '0FBD8C1A80000000',
        (a) => a.bsrRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsr(ecx, ptr(edx, ebx, 0, 128))',
      );
    });

    test('bsr ecx, dword_ptr(edx, ebx, 0, 128)', () {
      _testInstX86(
        '0FBD8C1A80000000',
        (a) => a.bsrRM(ecx, dwordPtrSIB(edx, ebx, 1, 128)),
        why: 'bsr(ecx, dword_ptr(edx, ebx, 0, 128))',
      );
    });

    test('bswap cx', () {
      _testInstX86('660FC9', (a) => a.bswap(cx), why: 'bswap(cx)');
    });

    test('bswap ecx', () {
      _testInstX86('0FC9', (a) => a.bswap(ecx), why: 'bswap(ecx)');
    });

    test('bt cx, 1', () {
      _testInstX86('660FBAE101', (a) => a.btRI(cx, 1), why: 'bt(cx, 1)');
    });

    test('bt ecx, 1', () {
      _testInstX86('0FBAE101', (a) => a.btRI(ecx, 1), why: 'bt(ecx, 1)');
    });

    test('bt word_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '660FBAA4118000000001',
        (a) => a.btMI(wordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'bt(word_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('bt dword_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '0FBAA4118000000001',
        (a) => a.btMI(dwordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'bt(dword_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('bt cx, dx', () {
      _testInstX86('660FA3D1', (a) => a.btRR(cx, dx), why: 'bt(cx, dx)');
    });

    test('bt ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '660FA39C1180000000',
        (a) => a.btMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'bt(ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('bt word_ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '660FA39C1180000000',
        (a) => a.btMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'bt(word_ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('bt ecx, edx', () {
      _testInstX86('0FA3D1', (a) => a.btRR(ecx, edx), why: 'bt(ecx, edx)');
    });

    test('bt ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '0FA39C1180000000',
        (a) => a.btMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'bt(ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('bt dword_ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '0FA39C1180000000',
        (a) => a.btMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'bt(dword_ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('btc cx, 1', () {
      _testInstX86('660FBAF901', (a) => a.btcRI(cx, 1), why: 'btc(cx, 1)');
    });

    test('btc ecx, 1', () {
      _testInstX86('0FBAF901', (a) => a.btcRI(ecx, 1), why: 'btc(ecx, 1)');
    });

    test('btc word_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '660FBABC118000000001',
        (a) => a.btcMI(wordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'btc(word_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('btc dword_ptr(ecx, edx, 0, 128), 1', () {
      _testInstX86(
        '0FBABC118000000001',
        (a) => a.btcMI(dwordPtrSIB(ecx, edx, 1, 128), 1),
        why: 'btc(dword_ptr(ecx, edx, 0, 128), 1)',
      );
    });

    test('btc cx, dx', () {
      _testInstX86('660FBBD1', (a) => a.btcRR(cx, dx), why: 'btc(cx, dx)');
    });

    test('btc ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '660FBB9C1180000000',
        (a) => a.btcMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'btc(ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('btc word_ptr(ecx, edx, 0, 128), bx', () {
      _testInstX86(
        '660FBB9C1180000000',
        (a) => a.btcMR(wordPtrSIB(ecx, edx, 1, 128), bx),
        why: 'btc(word_ptr(ecx, edx, 0, 128), bx)',
      );
    });

    test('btc ecx, edx', () {
      _testInstX86('0FBBD1', (a) => a.btcRR(ecx, edx), why: 'btc(ecx, edx)');
    });

    test('btc ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '0FBB9C1180000000',
        (a) => a.btcMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'btc(ptr(ecx, edx, 0, 128), ebx)',
      );
    });

    test('btc dword_ptr(ecx, edx, 0, 128), ebx', () {
      _testInstX86(
        '0FBB9C1180000000',
        (a) => a.btcMR(dwordPtrSIB(ecx, edx, 1, 128), ebx),
        why: 'btc(dword_ptr(ecx, edx, 0, 128), ebx)',
      );
    });
  });
}
