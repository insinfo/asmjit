// Golden encodings of the general-purpose ALU forms (ADD/OR/AND/SUB/XOR/CMP,
// TEST, IMUL, MOV mem/imm) for 8/16/32/64-bit registers (including the
// AL/AX/EAX/RAX short forms), immediates and memory operands. Expected bytes
// were produced by LLVM (clang -arch x86_64, Intel syntax); they also match
// the form selection of asmjit's x86 assembler (imm8 first, accumulator short
// form for AL or wider immediates).
import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

String hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Map<String, String> _encodeAll() {
  final out = <String, String>{};
  final regs = {
    8: [('al', X86Gp.r8(0)), ('cl', X86Gp.r8(1)), ('r9b', X86Gp.r8(9))],
    16: [('ax', X86Gp.r16(0)), ('dx', X86Gp.r16(2)), ('r10w', X86Gp.r16(10))],
    32: [('eax', X86Gp.r32(0)), ('ecx', X86Gp.r32(1)), ('r9d', X86Gp.r32(9))],
    64: [('rax', X86Gp.r64(0)), ('rdx', X86Gp.r64(2)), ('r10', X86Gp.r64(10))],
  };
  final mem = X86Mem.baseIndexScale(X86Gp.r64(9), X86Gp.r64(0), 2, disp: 64);
  void emit(String text, void Function(X86Assembler a) f) {
    final code = CodeHolder(env: Environment.x64SysV());
    f(X86Assembler(code));
    out[text] = hex(code.text.buffer.bytes);
  }

  final ops = {
    'sub': (X86Assembler a) => (a.subRR, a.subRI, a.subRM),
    'or': (X86Assembler a) => (a.orRR, a.orRI, a.orRM),
    'xor': (X86Assembler a) => (a.xorRR, a.xorRI, a.xorRM),
    'cmp': (X86Assembler a) => (a.cmpRR, a.cmpRI, a.cmpRM),
    'add': (X86Assembler a) => (a.addRR, a.addRI, a.addRM),
    'and': (X86Assembler a) => (a.andRR, a.andRI, a.andRM),
  };
  for (final e in ops.entries) {
    for (final bits in [8, 16, 32, 64]) {
      final r = regs[bits]!;
      final ptr = {8: 'byte', 16: 'word', 32: 'dword', 64: 'qword'}[bits];
      emit('${e.key} ${r[1].$1}, ${r[2].$1}',
          (a) => e.value(a).$1(r[1].$2, r[2].$2));
      emit('${e.key} ${r[2].$1}, ${r[1].$1}',
          (a) => e.value(a).$1(r[2].$2, r[1].$2));
      emit('${e.key} ${r[1].$1}, 5', (a) => e.value(a).$2(r[1].$2, 5));
      emit('${e.key} ${r[2].$1}, -3', (a) => e.value(a).$2(r[2].$2, -3));
      if (bits != 8)
        emit('${e.key} ${r[2].$1}, 1000', (a) => e.value(a).$2(r[2].$2, 1000));
      emit('${e.key} ${r[2].$1}, $ptr ptr [r9 + 2*rax + 64]',
          (a) => e.value(a).$3(r[2].$2, mem));
      emit('${e.key} ${r[0].$1}, 1', (a) => e.value(a).$2(r[0].$2, 1));
      emit('${e.key} ${r[0].$1}, ${bits == 8 ? 100 : 1000}',
          (a) => e.value(a).$2(r[0].$2, bits == 8 ? 100 : 1000));
    }
  }
  for (final bits in [8, 16, 32, 64]) {
    final r = regs[bits]!;
    final ptr = {8: 'byte', 16: 'word', 32: 'dword', 64: 'qword'}[bits];
    emit('test ${r[1].$1}, ${r[2].$1}', (a) => a.testRR(r[1].$2, r[2].$2));
    emit('test ${r[2].$1}, 100', (a) => a.testRI(r[2].$2, 100));
    emit('test ${r[0].$1}, 1', (a) => a.testRI(r[0].$2, 1));
    emit('test $ptr ptr [r9 + 2*rax + 64], ${r[2].$1}',
        (a) => a.testRM(r[2].$2, mem));
    if (bits != 8) {
      emit('imul ${r[1].$1}, ${r[2].$1}', (a) => a.imulRR(r[1].$2, r[2].$2));
      emit('imul ${r[2].$1}, ${r[1].$1}, 7',
          (a) => a.imulRRI(r[2].$2, r[1].$2, 7));
      emit('imul ${r[2].$1}, ${r[1].$1}, 1000',
          (a) => a.imulRRI(r[2].$2, r[1].$2, 1000));
    }
  }
  for (final (size, ptr) in [
    (1, 'byte'),
    (2, 'word'),
    (4, 'dword'),
    (8, 'qword')
  ]) {
    final m = X86Mem.baseIndexScale(X86Gp.r64(9), X86Gp.r64(0), 2,
        disp: 64, size: size);
    emit('mov $ptr ptr [r9 + 2*rax + 64], -7', (a) => a.movMI(m, -7));
  }
  return out;
}

const _expected = <String, String>{
  'sub cl, r9b': '4428c9',
  'sub r9b, cl': '4128c9',
  'sub cl, 5': '80e905',
  'sub r9b, -3': '4180e9fd',
  'sub r9b, byte ptr [r9 + 2*rax + 64]': '452a4c4140',
  'sub al, 1': '2c01',
  'sub al, 100': '2c64',
  'sub dx, r10w': '664429d2',
  'sub r10w, dx': '664129d2',
  'sub dx, 5': '6683ea05',
  'sub r10w, -3': '664183eafd',
  'sub r10w, 1000': '664181eae803',
  'sub r10w, word ptr [r9 + 2*rax + 64]': '66452b544140',
  'sub ax, 1': '6683e801',
  'sub ax, 1000': '662de803',
  'sub ecx, r9d': '4429c9',
  'sub r9d, ecx': '4129c9',
  'sub ecx, 5': '83e905',
  'sub r9d, -3': '4183e9fd',
  'sub r9d, 1000': '4181e9e8030000',
  'sub r9d, dword ptr [r9 + 2*rax + 64]': '452b4c4140',
  'sub eax, 1': '83e801',
  'sub eax, 1000': '2de8030000',
  'sub rdx, r10': '4c29d2',
  'sub r10, rdx': '4929d2',
  'sub rdx, 5': '4883ea05',
  'sub r10, -3': '4983eafd',
  'sub r10, 1000': '4981eae8030000',
  'sub r10, qword ptr [r9 + 2*rax + 64]': '4d2b544140',
  'sub rax, 1': '4883e801',
  'sub rax, 1000': '482de8030000',
  'or cl, r9b': '4408c9',
  'or r9b, cl': '4108c9',
  'or cl, 5': '80c905',
  'or r9b, -3': '4180c9fd',
  'or r9b, byte ptr [r9 + 2*rax + 64]': '450a4c4140',
  'or al, 1': '0c01',
  'or al, 100': '0c64',
  'or dx, r10w': '664409d2',
  'or r10w, dx': '664109d2',
  'or dx, 5': '6683ca05',
  'or r10w, -3': '664183cafd',
  'or r10w, 1000': '664181cae803',
  'or r10w, word ptr [r9 + 2*rax + 64]': '66450b544140',
  'or ax, 1': '6683c801',
  'or ax, 1000': '660de803',
  'or ecx, r9d': '4409c9',
  'or r9d, ecx': '4109c9',
  'or ecx, 5': '83c905',
  'or r9d, -3': '4183c9fd',
  'or r9d, 1000': '4181c9e8030000',
  'or r9d, dword ptr [r9 + 2*rax + 64]': '450b4c4140',
  'or eax, 1': '83c801',
  'or eax, 1000': '0de8030000',
  'or rdx, r10': '4c09d2',
  'or r10, rdx': '4909d2',
  'or rdx, 5': '4883ca05',
  'or r10, -3': '4983cafd',
  'or r10, 1000': '4981cae8030000',
  'or r10, qword ptr [r9 + 2*rax + 64]': '4d0b544140',
  'or rax, 1': '4883c801',
  'or rax, 1000': '480de8030000',
  'xor cl, r9b': '4430c9',
  'xor r9b, cl': '4130c9',
  'xor cl, 5': '80f105',
  'xor r9b, -3': '4180f1fd',
  'xor r9b, byte ptr [r9 + 2*rax + 64]': '45324c4140',
  'xor al, 1': '3401',
  'xor al, 100': '3464',
  'xor dx, r10w': '664431d2',
  'xor r10w, dx': '664131d2',
  'xor dx, 5': '6683f205',
  'xor r10w, -3': '664183f2fd',
  'xor r10w, 1000': '664181f2e803',
  'xor r10w, word ptr [r9 + 2*rax + 64]': '664533544140',
  'xor ax, 1': '6683f001',
  'xor ax, 1000': '6635e803',
  'xor ecx, r9d': '4431c9',
  'xor r9d, ecx': '4131c9',
  'xor ecx, 5': '83f105',
  'xor r9d, -3': '4183f1fd',
  'xor r9d, 1000': '4181f1e8030000',
  'xor r9d, dword ptr [r9 + 2*rax + 64]': '45334c4140',
  'xor eax, 1': '83f001',
  'xor eax, 1000': '35e8030000',
  'xor rdx, r10': '4c31d2',
  'xor r10, rdx': '4931d2',
  'xor rdx, 5': '4883f205',
  'xor r10, -3': '4983f2fd',
  'xor r10, 1000': '4981f2e8030000',
  'xor r10, qword ptr [r9 + 2*rax + 64]': '4d33544140',
  'xor rax, 1': '4883f001',
  'xor rax, 1000': '4835e8030000',
  'cmp cl, r9b': '4438c9',
  'cmp r9b, cl': '4138c9',
  'cmp cl, 5': '80f905',
  'cmp r9b, -3': '4180f9fd',
  'cmp r9b, byte ptr [r9 + 2*rax + 64]': '453a4c4140',
  'cmp al, 1': '3c01',
  'cmp al, 100': '3c64',
  'cmp dx, r10w': '664439d2',
  'cmp r10w, dx': '664139d2',
  'cmp dx, 5': '6683fa05',
  'cmp r10w, -3': '664183fafd',
  'cmp r10w, 1000': '664181fae803',
  'cmp r10w, word ptr [r9 + 2*rax + 64]': '66453b544140',
  'cmp ax, 1': '6683f801',
  'cmp ax, 1000': '663de803',
  'cmp ecx, r9d': '4439c9',
  'cmp r9d, ecx': '4139c9',
  'cmp ecx, 5': '83f905',
  'cmp r9d, -3': '4183f9fd',
  'cmp r9d, 1000': '4181f9e8030000',
  'cmp r9d, dword ptr [r9 + 2*rax + 64]': '453b4c4140',
  'cmp eax, 1': '83f801',
  'cmp eax, 1000': '3de8030000',
  'cmp rdx, r10': '4c39d2',
  'cmp r10, rdx': '4939d2',
  'cmp rdx, 5': '4883fa05',
  'cmp r10, -3': '4983fafd',
  'cmp r10, 1000': '4981fae8030000',
  'cmp r10, qword ptr [r9 + 2*rax + 64]': '4d3b544140',
  'cmp rax, 1': '4883f801',
  'cmp rax, 1000': '483de8030000',
  'add cl, r9b': '4400c9',
  'add r9b, cl': '4100c9',
  'add cl, 5': '80c105',
  'add r9b, -3': '4180c1fd',
  'add r9b, byte ptr [r9 + 2*rax + 64]': '45024c4140',
  'add al, 1': '0401',
  'add al, 100': '0464',
  'add dx, r10w': '664401d2',
  'add r10w, dx': '664101d2',
  'add dx, 5': '6683c205',
  'add r10w, -3': '664183c2fd',
  'add r10w, 1000': '664181c2e803',
  'add r10w, word ptr [r9 + 2*rax + 64]': '664503544140',
  'add ax, 1': '6683c001',
  'add ax, 1000': '6605e803',
  'add ecx, r9d': '4401c9',
  'add r9d, ecx': '4101c9',
  'add ecx, 5': '83c105',
  'add r9d, -3': '4183c1fd',
  'add r9d, 1000': '4181c1e8030000',
  'add r9d, dword ptr [r9 + 2*rax + 64]': '45034c4140',
  'add eax, 1': '83c001',
  'add eax, 1000': '05e8030000',
  'add rdx, r10': '4c01d2',
  'add r10, rdx': '4901d2',
  'add rdx, 5': '4883c205',
  'add r10, -3': '4983c2fd',
  'add r10, 1000': '4981c2e8030000',
  'add r10, qword ptr [r9 + 2*rax + 64]': '4d03544140',
  'add rax, 1': '4883c001',
  'add rax, 1000': '4805e8030000',
  'and cl, r9b': '4420c9',
  'and r9b, cl': '4120c9',
  'and cl, 5': '80e105',
  'and r9b, -3': '4180e1fd',
  'and r9b, byte ptr [r9 + 2*rax + 64]': '45224c4140',
  'and al, 1': '2401',
  'and al, 100': '2464',
  'and dx, r10w': '664421d2',
  'and r10w, dx': '664121d2',
  'and dx, 5': '6683e205',
  'and r10w, -3': '664183e2fd',
  'and r10w, 1000': '664181e2e803',
  'and r10w, word ptr [r9 + 2*rax + 64]': '664523544140',
  'and ax, 1': '6683e001',
  'and ax, 1000': '6625e803',
  'and ecx, r9d': '4421c9',
  'and r9d, ecx': '4121c9',
  'and ecx, 5': '83e105',
  'and r9d, -3': '4183e1fd',
  'and r9d, 1000': '4181e1e8030000',
  'and r9d, dword ptr [r9 + 2*rax + 64]': '45234c4140',
  'and eax, 1': '83e001',
  'and eax, 1000': '25e8030000',
  'and rdx, r10': '4c21d2',
  'and r10, rdx': '4921d2',
  'and rdx, 5': '4883e205',
  'and r10, -3': '4983e2fd',
  'and r10, 1000': '4981e2e8030000',
  'and r10, qword ptr [r9 + 2*rax + 64]': '4d23544140',
  'and rax, 1': '4883e001',
  'and rax, 1000': '4825e8030000',
  'test cl, r9b': '4484c9',
  'test r9b, 100': '41f6c164',
  'test al, 1': 'a801',
  'test byte ptr [r9 + 2*rax + 64], r9b': '45844c4140',
  'test dx, r10w': '664485d2',
  'test r10w, 100': '6641f7c26400',
  'test ax, 1': '66a90100',
  'test word ptr [r9 + 2*rax + 64], r10w': '664585544140',
  'imul dx, r10w': '66410fafd2',
  'imul r10w, dx, 7': '66446bd207',
  'imul r10w, dx, 1000': '664469d2e803',
  'test ecx, r9d': '4485c9',
  'test r9d, 100': '41f7c164000000',
  'test eax, 1': 'a901000000',
  'test dword ptr [r9 + 2*rax + 64], r9d': '45854c4140',
  'imul ecx, r9d': '410fafc9',
  'imul r9d, ecx, 7': '446bc907',
  'imul r9d, ecx, 1000': '4469c9e8030000',
  'test rdx, r10': '4c85d2',
  'test r10, 100': '49f7c264000000',
  'test rax, 1': '48a901000000',
  'test qword ptr [r9 + 2*rax + 64], r10': '4d85544140',
  'imul rdx, r10': '490fafd2',
  'imul r10, rdx, 7': '4c6bd207',
  'imul r10, rdx, 1000': '4c69d2e8030000',
  'mov byte ptr [r9 + 2*rax + 64], -7': '41c6444140f9',
  'mov word ptr [r9 + 2*rax + 64], -7': '6641c7444140f9ff',
  'mov dword ptr [r9 + 2*rax + 64], -7': '41c7444140f9ffffff',
  'mov qword ptr [r9 + 2*rax + 64], -7': '49c7444140f9ffffff',
};

void main() {
  test('every ALU form matches LLVM', () {
    final actual = _encodeAll();
    expect(actual.length, _expected.length);
    final mismatches = [
      for (final e in _expected.entries)
        if (actual[e.key] != e.value) '${e.key}: ${actual[e.key]} != ${e.value}'
    ];
    expect(mismatches, isEmpty);
  });
}
