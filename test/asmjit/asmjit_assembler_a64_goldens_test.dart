// Upstream AArch64 assembler goldens (asmjit-testing/tests/
// asmjit_test_assembler_a64.cpp), emitted through the generic
// `A64Assembler.emit(instId, operands)` path; see
// test/support/asm_goldens.dart for the data and the ratchet of unsupported
// cases.
import 'package:asmjit/asmjit.dart';

import '../support/asm_goldens.dart';
import '../support/cpp_expr.dart';

final _instIds = {
  for (final i in kA64InstDb)
    for (final name in i.name.split('|')) name: i.id
};

final _regs = <String, Object>{
  for (var i = 0; i < 31; i++) ...{'x$i': A64Gp(i, 64), 'w$i': A64Gp(i, 32)},
  'xzr': A64Gp(31, 64),
  'wzr': A64Gp(31, 32),
  'sp': A64Gp(31, 64),
  'wsp': A64Gp(31, 32),
  for (var i = 0; i < 32; i++) ...{
    'b$i': A64Vec(i, 8),
    'h$i': A64Vec(i, 16),
    's$i': A64Vec(i, 32),
    'd$i': A64Vec(i, 64),
    'q$i': A64Vec(i, 128),
    'v$i': A64Vec(i, 128),
  },
};

const _layouts = {
  'b8': A64Layout.b8,
  'b16': A64Layout.b16,
  'h4': A64Layout.h4,
  'h8': A64Layout.h8,
  's2': A64Layout.s2,
  's4': A64Layout.s4,
  'd1': A64Layout.d1,
  'd2': A64Layout.d2,
};

const _shifts = {
  'lsl': A64Shift.lsl,
  'lsr': A64Shift.lsr,
  'asr': A64Shift.asr,
  'ror': A64Shift.ror,
};

Object _operand(CppExpr e) {
  switch (e) {
    case CppNum(:final value):
      return value;
    case CppIdent(:final name) when name.startsWith('CondCode::k'):
      final c = name.substring('CondCode::k'.length).toLowerCase();
      // The serializer passes conditions to the dispatcher as A64Cond.
      return A64Cond.values.firstWhere((v) => v.name == c,
          orElse: () => throw GoldenUnsupported('condition $name'));
    case CppIdent(:final name):
      return _regs[name] ?? (throw GoldenUnsupported('operand $name'));
    case CppCall(
          receiver: CppIdent(:final name),
          name: final layout,
          :final args
        )
        when name.startsWith('v') &&
            args.isEmpty &&
            _layouts.containsKey(layout):
      final v = _regs[name] as A64Vec;
      const half = {'b8', 'h4', 's2', 'd1'};
      return A64Vec(v.id, half.contains(layout) ? 64 : 128, _layouts[layout]!);
    case CppCall(receiver: null, :final name, :final args)
        when _shifts.containsKey(name) && args.length == 1:
      return A64ShiftOp(_shifts[name]!, (args[0] as CppNum).value);
    case CppCall(receiver: null, :final name, :final args)
        when name == 'ptr' || name == 'ptr_pre' || name == 'ptr_post':
      return _mem(name, args.map(_operand).toList());
    case CppCall():
      throw GoldenUnsupported('operand $e');
  }
}

A64Mem _mem(String kind, List<Object> a) {
  if (a.isEmpty || a[0] is! A64Gp) throw GoldenUnsupported('memory $a');
  final base = a[0] as A64Gp;
  final offset = a.length > 1 && a[1] is int ? a[1] as int : 0;
  switch (kind) {
    case 'ptr_pre':
      if (a.length != 2 || a[1] is! int) throw GoldenUnsupported('memory');
      return A64Mem.preIndex(base, offset);
    case 'ptr_post':
      if (a.length != 2 || a[1] is! int) throw GoldenUnsupported('memory');
      return A64Mem.postIndex(base, offset);
  }
  if (a.length == 1) return A64Mem.base(base);
  if (a.length == 2 && a[1] is int) return A64Mem.baseOffset(base, offset);
  if (a[1] is A64Gp) {
    if (a.length == 2) return A64Mem.baseIndex(base, a[1] as A64Gp);
    final s = a[2];
    if (s is A64ShiftOp && s.shift == A64Shift.lsl) {
      return A64Mem.baseIndex(base, a[1] as A64Gp, shift: s.amount);
    }
  }
  throw GoldenUnsupported('memory $a');
}

List<int> _assemble(String expr) {
  final e = parseCppExpr(expr);
  if (e is! CppCall || e.receiver != null) {
    throw GoldenUnsupported('not a plain call');
  }
  final name =
      e.name.endsWith('_') ? e.name.substring(0, e.name.length - 1) : e.name;
  final id = _instIds[name] ?? (throw GoldenUnsupported('instruction $name'));
  final ops = e.args.map(_operand).toList();
  final code = CodeHolder(env: Environment.aarch64());
  A64Assembler(code).emit(id, ops);
  return code.text.buffer.bytes;
}

void main() => assemblerGoldens('a64', _assemble);
