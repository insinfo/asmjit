// Upstream x64 assembler goldens (asmjit-testing/tests/
// asmjit_test_assembler_x64.cpp), emitted through the generic
// `X86Assembler.emit(instId, operands)` path; see
// test/support/asm_goldens.dart for the data and the ratchet of unsupported
// cases.
//
// Prefix calls of the upstream emitter (`lock()`, `k(k1)`, `z()`, `rn_sae()`,
// `vex()`...) set `X86Assembler.instOptions` / `extraReg`, as upstream
// `BaseEmitter::inst_options()` / `extra_reg()`.
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
  for (var i = 0; i < 8; i++) ...{
    'k$i': X86KReg(i),
    'mm$i': X86Mm(i),
    'st$i': X86St(i),
    'tmm$i': X86Tmm(i),
    'dr$i': X86DReg(i),
  },
  for (var i = 0; i < 16; i++) 'cr$i': X86CReg(i),
  for (var i = 0; i < 4; i++) 'bnd$i': X86Bnd(i),
  for (final (i, n) in ['es', 'cs', 'ss', 'ds', 'fs', 'gs'].indexed)
    n: X86SReg(i + 1),
};

/// Prefix calls of the upstream emitter: instruction options.
const _prefixOptions = {
  'lock': X86EmitOptions.kX86_Lock,
  'rep': X86EmitOptions.kX86_Rep,
  'repe': X86EmitOptions.kX86_Rep,
  'repz': X86EmitOptions.kX86_Rep,
  'repne': X86EmitOptions.kX86_Repne,
  'repnz': X86EmitOptions.kX86_Repne,
  'xacquire': X86EmitOptions.kX86_XAcquire,
  'xrelease': X86EmitOptions.kX86_XRelease,
  'short_': X86EmitOptions.kShortForm,
  'long_': X86EmitOptions.kLongForm,
  'taken': X86EmitOptions.kTaken,
  'not_taken': X86EmitOptions.kNotTaken,
  'mod_mr': X86EmitOptions.kX86_ModMR,
  'mod_rm': X86EmitOptions.kX86_ModRM,
  'vex': X86EmitOptions.kX86_Vex,
  'vex3': X86EmitOptions.kX86_Vex3,
  'evex': X86EmitOptions.kX86_Evex,
  'rex': X86EmitOptions.kX86_Rex,
  'z': X86EmitOptions.kX86_ZMask,
  'sae': X86EmitOptions.kX86_SAE,
  'rn_sae': X86EmitOptions.kX86_ER | X86EmitOptions.kX86_RN_SAE,
  'rd_sae': X86EmitOptions.kX86_ER | X86EmitOptions.kX86_RD_SAE,
  'ru_sae': X86EmitOptions.kX86_ER | X86EmitOptions.kX86_RU_SAE,
  'rz_sae': X86EmitOptions.kX86_ER | X86EmitOptions.kX86_RZ_SAE,
};

/// `Mem::_1to2()` ... `_1to32()`.
const _broadcasts = {
  '_1to2': X86Broadcast.k1To2,
  '_1to4': X86Broadcast.k1To4,
  '_1to8': X86Broadcast.k1To8,
  '_1to16': X86Broadcast.k1To16,
  '_1to32': X86Broadcast.k1To32,
};

/// Condition-code aliases of the upstream emitter (`cmovpo` is `cmovnp`...).
const _ccAliases = {
  'a': 'nbe', 'ae': 'nb', 'c': 'b', 'e': 'z', 'g': 'nle', 'ge': 'nl', //
  'na': 'be', 'nae': 'b', 'nc': 'nb', 'ne': 'nz', 'ng': 'le', 'nge': 'l',
  'pe': 'p', 'po': 'np',
};

int? _instId(String name) {
  final id = _instIds[name];
  if (id != null) return id;
  if (name == 'sal') return _instIds['shl'];
  for (final p in ['cmov', 'set', 'j']) {
    if (name.startsWith(p)) {
      final cc = _ccAliases[name.substring(p.length)];
      if (cc != null) return _instIds['$p$cc'];
    }
  }
  return null;
}

const _memSizes = {
  'ptr': 0,
  'byte_ptr': 1,
  'word_ptr': 2,
  'dword_ptr': 4,
  'qword_ptr': 8,
  'fword_ptr': 6,
  'tword_ptr': 10,
  'tbyte_ptr': 10,
  'xmmword_ptr': 16,
  'ymmword_ptr': 32,
  'zmmword_ptr': 64,
};

Object _operand(CppExpr e) {
  switch (e) {
    case CppNum(:final value):
      return value;
    case CppIdent(name: 'rip'):
      return 'rip';
    case CppIdent(:final name):
      return _regs[name] ?? (throw GoldenUnsupported('operand $name'));
    case CppCall(receiver: null, :final name, :final args)
        when _memSizes.containsKey(name):
      return _mem(_memSizes[name]!, args.map(_operand).toList());
    case CppCall(:final receiver?, :final name, args: [])
        when _broadcasts.containsKey(name):
      final m = _operand(receiver);
      if (m is! X86Mem) throw GoldenUnsupported('broadcast of $m');
      return m.withBroadcast(_broadcasts[name]!);
    case CppCall():
      throw GoldenUnsupported('operand $e');
  }
}

BaseMem _mem(int size, List<Object> a) {
  if (a.length == 1 && a[0] is int) {
    return X86Mem.abs(a[0] as int, size: size);
  }
  if (a.isNotEmpty && a[0] == 'rip') {
    return X86RipMem(displacement: a.length > 1 ? a[1] as int : 0, size: size);
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
  final code = CodeHolder(env: Environment.x64SysV());
  final a = X86Assembler(code);

  // Prefix chain: `k(k1).z().vaddpd(...)`.
  var options = 0;
  BaseReg? extraReg;
  for (var r = e.receiver; r != null;) {
    if (r is! CppCall) throw GoldenUnsupported('prefix $r');
    if (r.name == 'k' && r.args.length == 1) {
      extraReg = _operand(r.args[0]) as BaseReg;
    } else {
      options |= _prefixOptions[r.name] ??
          (throw GoldenUnsupported('prefix ${r.name}'));
    }
    r = r.receiver;
  }

  final name =
      e.name.endsWith('_') ? e.name.substring(0, e.name.length - 1) : e.name;
  final id = _instId(name) ?? (throw GoldenUnsupported('instruction $name'));
  final ops = e.args.map(_operand).toList();
  a.instOptions = options;
  a.extraReg = extraReg;
  a.emit(id, ops);
  return code.text.buffer.bytes;
}

void main() => assemblerGoldens('x64', _assemble);
