// Upstream x64 assembler goldens (asmjit-testing/tests/
// asmjit_test_assembler_x64.cpp), emitted through the generic
// `X86Assembler.emit(instId, operands)` path; see
// test/support/asm_goldens.dart for the data and the ratchet of unsupported
// cases.
import 'package:asmjit/asmjit.dart';

import '../support/asm_goldens.dart';
import '../support/cpp_expr.dart';

final _instIds = {for (final i in kX86InstDb) i.name: i.id};

final _regs = <String, Object>{
  for (final (i, n)
      in ['al', 'cl', 'dl', 'bl', 'spl', 'bpl', 'sil', 'dil'].indexed)
    n: X86Gp.r8(i),
  for (final (i, n) in ['ah', 'ch', 'dh', 'bh'].indexed) n: X86Gp.r8h(i),
  for (final (i, n) in ['ax', 'cx', 'dx', 'bx', 'sp', 'bp', 'si', 'di'].indexed)
    n: X86Gp.r16(i),
  for (final (i, n) in [
    'eax', 'ecx', 'edx', 'ebx', 'esp', 'ebp', 'esi', 'edi' //
  ].indexed)
    n: X86Gp.r32(i),
  for (final (i, n) in [
    'rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi' //
  ].indexed)
    n: X86Gp.r64(i),
  for (var i = 8; i < 16; i++) ...{
    'r${i}b': X86Gp.r8(i),
    'r${i}w': X86Gp.r16(i),
    'r${i}d': X86Gp.r32(i),
    'r$i': X86Gp.r64(i),
  },
  for (var i = 0; i < 32; i++) ...{
    'xmm$i': X86Xmm(i),
    'ymm$i': X86Ymm(i),
    'zmm$i': X86Zmm(i),
  },
  for (var i = 0; i < 8; i++) 'k$i': X86KReg(i),
};

const _memSizes = {
  'ptr': 0,
  'byte_ptr': 1,
  'word_ptr': 2,
  'dword_ptr': 4,
  'qword_ptr': 8,
  'tword_ptr': 10,
  'xmmword_ptr': 16,
  'ymmword_ptr': 32,
  'zmmword_ptr': 64,
};

Object _operand(CppExpr e) {
  switch (e) {
    case CppNum(:final value):
      return value;
    case CppIdent(:final name):
      return _regs[name] ?? (throw GoldenUnsupported('operand $name'));
    case CppCall(receiver: null, :final name, :final args)
        when _memSizes.containsKey(name):
      return _mem(_memSizes[name]!, args.map(_operand).toList());
    case CppCall():
      throw GoldenUnsupported('operand $e');
  }
}

X86Mem _mem(int size, List<Object> a) {
  if (a.length == 1 && a[0] is int) {
    return X86Mem.abs(a[0] as int, size: size);
  }
  if (a.isEmpty || a[0] is! X86Gp) throw GoldenUnsupported('memory $a');
  final base = a[0] as X86Gp;
  if (a.length == 2 && a[1] is int) {
    return X86Mem.baseDisp(base, a[1] as int, size: size);
  }
  if (a.length >= 2 && a[1] is BaseReg) {
    final shift = a.length > 2 ? a[2] as int : 0;
    final disp = a.length > 3 ? a[3] as int : 0;
    return X86Mem(
        base: base,
        index: a[1] as BaseReg,
        scale: 1 << shift,
        displacement: disp,
        size: size);
  }
  if (a.length == 1) return X86Mem.base(base, size: size);
  throw GoldenUnsupported('memory $a');
}

/// Bytes emitted for [expr], or throws.
List<int> _assemble(String expr) {
  final e = parseCppExpr(expr);
  if (e is! CppCall) throw GoldenUnsupported('not a call');
  if (e.receiver != null) throw GoldenUnsupported('prefix ${e.receiver}');
  final name =
      e.name.endsWith('_') ? e.name.substring(0, e.name.length - 1) : e.name;
  final id = _instIds[name] ?? (throw GoldenUnsupported('instruction $name'));
  final ops = e.args.map(_operand).toList();
  final code = CodeHolder(env: Environment.x64SysV());
  X86Assembler(code).emit(id, ops);
  return code.text.buffer.bytes;
}

void main() => assemblerGoldens('x64', _assemble);
