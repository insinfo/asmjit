// Upstream AArch64 assembler goldens (asmjit-testing/tests/
// asmjit_test_assembler_a64.cpp), emitted through the generic
// `A64Assembler.emit(instId, operands)` path; see
// test/support/asm_goldens.dart for the data and the ratchet of unsupported
// cases.
import 'package:asmjit/asmjit.dart';

import '../support/asm_goldens.dart';
import '../support/cpp_expr.dart';

/// Instruction ids by name: an alias of a combined entry (`umov|mov`)
/// never hides the instruction that has the name itself (`mov`).
final _instIds = {
  for (final i in kA64InstDb)
    for (final name in i.name.split('|').skip(1)) name: i.id,
  for (final i in kA64InstDb) i.name.split('|').first: i.id,
};

final _regs = <String, Object>{
  for (var i = 0; i < 31; i++) ...{'x$i': A64Gp(i, 64), 'w$i': A64Gp(i, 32)},
  'xzr': xzr,
  'wzr': wzr,
  'sp': A64Gp(A64Gp.kIdSp, 64),
  'wsp': A64Gp(A64Gp.kIdSp, 32),
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

final _shifts = {for (final s in A64Shift.values) s.name: s};

/// Element accessors (`v3.s(3)`, `v1.b4(0)`): upstream `VecElementType`.
const _elements = {'b': 1, 'h': 2, 's': 3, 'd': 4, 'b4': 5, 'h2': 6};

/// Label `L0` of the case being assembled (bound at offset 0).
Label? _label;

/// Condition aliases of the upstream API (`hs` = `cs`, `lo` = `cc`).
String _condAlias(String c) => switch (c) {
      'hs' => 'cs',
      'lo' => 'cc',
      _ => c,
    };

Object _operand(CppExpr e) {
  switch (e) {
    case CppNum(:final value):
      return value;
    case CppDouble(:final value):
      return value;
    case CppIdent(:final name) when name.startsWith('CondCode::k'):
      final c = _condAlias(name.substring('CondCode::k'.length).toLowerCase());
      // The serializer passes conditions to the dispatcher as A64Cond.
      return A64Cond.values.firstWhere((v) => v.name == c,
          orElse: () => throw GoldenUnsupported('condition $name'));
    case CppIdent(:final name) when name.startsWith('Predicate::'):
      return kA64Predicates[name.substring('Predicate::'.length)] ??
          (throw GoldenUnsupported('operand $name'));
    case CppIdent(name: 'L0'):
      // The upstream tester binds L0 at the instruction.
      return _label!;
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
    case CppCall(
          receiver: CppIdent(:final name),
          name: final element,
          :final args
        )
        when name.startsWith('v') &&
            args.length == 1 &&
            _elements.containsKey(element):
      final v = _regs[name] as A64Vec;
      return v.at(_elements[element]!, (args[0] as CppNum).value);
    case CppCall(receiver: CppIdent(:final name), name: final element, args: [])
        when name.startsWith('v') && element == 'h2':
      // `Vec::h2()`: a 32-bit vector of H elements (`.2h`).
      final v = _regs[name] as A64Vec;
      return A64Vec(v.id, 32, A64Layout.none, _elements['h']);
    case CppCall(receiver: null, :final name, :final args)
        when _shifts.containsKey(name) && args.length <= 1:
      return A64ShiftOp(
          _shifts[name]!, args.isEmpty ? 0 : (args[0] as CppNum).value);
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
      if (a.length == 2 && a[1] is A64Gp) {
        return A64Mem.postIndexReg(base, a[1] as A64Gp);
      }
      if (a.length != 2 || a[1] is! int) throw GoldenUnsupported('memory');
      return A64Mem.postIndex(base, offset);
  }
  if (a.length == 1) return A64Mem.base(base);
  if (a.length == 2 && a[1] is int) return A64Mem.baseOffset(base, offset);
  if (a[1] is A64Gp) {
    if (a.length == 2) return A64Mem.baseIndex(base, a[1] as A64Gp);
    final s = a[2];
    if (s is A64ShiftOp) {
      return A64Mem.baseIndex(base, a[1] as A64Gp,
          shift: s.amount,
          extend: s.shift == A64Shift.lsl ? null : s.shift.encoding);
    }
  }
  throw GoldenUnsupported('memory $a');
}

List<int> _assemble(String expr) {
  final e = parseCppExpr(expr);
  if (e is! CppCall || e.receiver != null) {
    throw GoldenUnsupported('not a plain call');
  }
  var name =
      e.name.endsWith('_') ? e.name.substring(0, e.name.length - 1) : e.name;
  // The upstream tester uses `code.init(env, 0)`.
  final code = CodeHolder(env: Environment.aarch64(), baseAddress: 0);
  _label = code.newLabel();
  code.bind(_label!);
  final ops = e.args.map(_operand).toList();
  // `b_eq(L0)`: B with an embedded condition (`b_al` is a plain B).
  if (name.startsWith('b_')) {
    final c = _condAlias(name.substring(2));
    if (c != 'al') {
      ops.add(A64Cond.values.firstWhere((v) => v.name == c,
          orElse: () => throw GoldenUnsupported('condition $c')));
      name = 'b.cond';
    } else {
      name = 'b';
    }
  }
  // `b(cond, label)`.
  if (name == 'b' && ops.isNotEmpty && ops.first is A64Cond) {
    final c = ops.removeAt(0) as A64Cond;
    if (c != A64Cond.al) {
      ops.add(c);
      name = 'b.cond';
    }
  }
  final id = name == 'b.cond'
      ? A64InstId.kB_cond
      : _instIds[name] ?? (throw GoldenUnsupported('instruction $name'));
  A64Assembler(code).emit(id, ops);
  return code.text.buffer.bytes;
}

void main() => assemblerGoldens('a64', _assemble);
