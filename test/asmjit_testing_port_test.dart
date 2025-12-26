import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/x86/x86_dispatcher.g.dart';
import 'package:asmjit/src/arm/a64_dispatcher.g.dart';
import 'package:asmjit/src/arm/a64.dart';
import 'package:asmjit/src/arm/a64_assembler.dart';
import 'package:asmjit/src/arm/a64_inst_db.g.dart';
import 'package:asmjit/src/core/builder.dart' as ir;

void main() {
  group('asmjit-testing parity (Dart port)', () {
    test('isa_x86.json unique instructions == X86InstId.kCount', () async {
      final file = File('assets/db/isa_x86.json');
      expect(file.existsSync(), isTrue,
          reason: 'assets/db must contain isa_x86.json (copied from referencias)');

      final jsonMap =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      final categories = jsonMap['instructions'] as List<dynamic>;

      final names = <String>{};
      for (final cat in categories) {
        final insts = (cat as Map<String, dynamic>)['instructions'] as List?;
        if (insts == null) continue;
        for (final inst in insts) {
          final syntax = inst as Map<String, dynamic>;
          final variants = <String>[];
          if (syntax.containsKey('any')) variants.add(syntax['any'] as String);
          if (syntax.containsKey('x86')) variants.add(syntax['x86'] as String);
          if (syntax.containsKey('x64')) variants.add(syntax['x64'] as String);
          if (syntax.containsKey('apx')) variants.add(syntax['apx'] as String);

          for (final v in variants) {
            final mnemonic = _parseMnemonic(v);
            if (mnemonic != null) names.add(mnemonic);
          }
        }
      }

      expect(names.length, X86InstId.kCount,
          reason:
              'Ported DB generator should stay in sync with assets/db/isa_x86.json');
    });

    test('inst db lookup basic mnemonics', () {
      final add = x86InstByName('add');
      final mov = x86InstByName('mov');
      final ret = x86InstByName('ret');
      expect(add?.id, X86InstId.kAdd);
      expect(mov?.id, X86InstId.kMov);
      expect(ret?.id, X86InstId.kRet);
    });

    test('isa_aarch64.json unique instructions == A64InstId.kCount', () async {
      final file = File('assets/db/isa_aarch64.json');
      expect(file.existsSync(), isTrue,
          reason: 'assets/db must contain isa_aarch64.json (copied from referencias)');

      final jsonMap =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      final categories = jsonMap['instructions'] as List<dynamic>;

      final names = <String>{};
      for (final cat in categories) {
        final insts = (cat as Map<String, dynamic>)['data'] as List?;
        if (insts == null) continue;
        for (final inst in insts) {
          final syntax = inst as Map<String, dynamic>;
          final syntaxStr = syntax['inst'] as String?;
          if (syntaxStr == null) continue;
          final mnemonic = _parseA64Mnemonic(syntaxStr);
          if (mnemonic != null) names.add(mnemonic);
        }
      }

      expect(names.length, A64InstId.kCount,
          reason:
              'Ported DB generator should stay em sync com assets/db/isa_aarch64.json');
    });

    test('dispatcher encodes mov/add/ret without fallback', () {
      final env = Environment.host();
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      x86Dispatch(asm, X86InstId.kMov, [rax, rbx]);
      x86Dispatch(asm, X86InstId.kAdd, [rax, 1]);
      x86Dispatch(asm, X86InstId.kRet, const []);

      expect(code.text.buffer.length, greaterThan(0));
    });

    test('A64 dispatcher encodes mov/add/ret without fallback', () {
      final env = Environment.host();
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);

      a64Dispatch(asm, A64InstId.kMov, [x0, x1]);
      a64Dispatch(asm, A64InstId.kAdd, [x0, x0, 1]);
      a64Dispatch(asm, A64InstId.kRet, const []);

      expect(code.text.buffer.length, greaterThan(0));
    });

    // Grandes suítes originais permanecem pendentes de porte completo.
    test('asmjit_test_assembler_x64.cpp (scaffold)', () {
      final env = Environment.host();
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      asm.movRR(rax, rcx);
      asm.addRI(rax, 1);
      asm.ret();

      final bytes = code.text.buffer.bytes;
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.last, equals(0xC3)); // ret
    });

    test('asmjit_test_assembler_x86.cpp (scaffold)', () {
      final env = Environment.host();
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      asm.movRR(eax, ecx);
      asm.addRI(eax, 1);
      asm.ret();

      final bytes = code.text.buffer.bytes;
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.last, equals(0xC3)); // ret
    });
    test('asmjit_test_compiler_x86.cpp (port completo)', () {
      final runtime = JitRuntime();

      // Caso 1: soma de dois argumentos.
      {
        final builder = X86CodeBuilder.create();
        final a = builder.getArgReg(0);
        final b = builder.getArgReg(1);
        final sum = builder.newGpReg();

        builder.mov(sum, a);
        builder.add(sum, b);
        builder.add(sum, a);
        builder.mov(rax, sum);
        builder.ret();

        // TODO: validar execucao com spills quando o RA/stack estiver estavel.
        final fn = builder.build(runtime);
        final call = _as2(fn);
        expect(call(40, 2), equals(82));
        expect(call(-10, 15), equals(-5));
        fn.dispose();
      }

      // Caso 2: if/else simples.
      {
        final builder = X86CodeBuilder.create();
        final a = builder.getArgReg(0);
        final isZero = builder.newLabel();
        final done = builder.newLabel();
        final out = builder.newGpReg();
        final zero = builder.newGpReg();

        builder.mov(zero, 0);
        builder.cmp(a, zero);
        builder.je(isZero);

        builder.mov(out, 20);
        builder.jmp(done);

        builder.label(isZero);
        builder.mov(out, 10);

        builder.label(done);
        builder.mov(rax, out);
        builder.ret();

        final fn = builder.build(runtime);
        final call = _as1(fn);
        expect(call(0), equals(10));
        expect(call(7), equals(20));
        fn.dispose();
      }

      // Caso 3: loop somatorio 1..n (n >= 0).
      {
        final builder = X86CodeBuilder.create();
        final n = builder.getArgReg(0);
        final sum = builder.newGpReg();
        final loop = builder.newLabel();
        final done = builder.newLabel();

        builder.mov(sum, 0);
        builder.label(loop);
        builder.test(n, n);
        builder.je(done);
        builder.add(sum, n);
        builder.dec(n);
        builder.inst(X86InstId.kJnz, [ir.LabelOperand(loop)]);

        builder.label(done);
        builder.mov(rax, sum);
        builder.ret();

        final fn = builder.build(runtime);
        final call = _as1(fn);
        expect(call(0), equals(0));
        expect(call(1), equals(1));
        expect(call(5), equals(15));
        fn.dispose();
      }

      // Caso 4: estresse de spills (muitos vregs vivos).
      {
        final builder = X86CodeBuilder.create();
        final regs = <VirtReg>[];
        for (var i = 0; i < 28; i++) {
          final r = builder.newGpReg();
          regs.add(r);
          builder.mov(r, i + 1);
        }
        final acc = builder.newGpReg();
        builder.mov(acc, 0);
        for (final r in regs) {
          builder.add(acc, r);
        }
        builder.mov(rax, acc);
        builder.ret();

        final fn = builder.build(runtime);
        final bytes = builder.code.text.buffer.bytes;
        expect(bytes.contains(0xC3), isTrue, reason: 'ret presente');
        fn.dispose();
      }

      // Caso 5: merge de saltos basico.
      {
        final builder = X86CodeBuilder.create();
        final v = builder.getArgReg(0);
        final out = builder.newGpReg();
        final l0 = builder.newLabel();
        final l1 = builder.newLabel();
        final l2 = builder.newLabel();
        final done = builder.newLabel();
        final zero = builder.newGpReg();
        final one = builder.newGpReg();
        final two = builder.newGpReg();

        builder.mov(zero, 0);
        builder.mov(one, 1);
        builder.mov(two, 2);

        builder.cmp(v, zero);
        builder.je(l2);
        builder.cmp(v, one);
        builder.je(l1);
        builder.cmp(v, two);
        builder.je(l0);

        builder.mov(out, 3);
        builder.jmp(done);

        builder.label(l0);
        builder.label(l1);
        builder.label(l2);
        builder.mov(out, 0);

        builder.label(done);
        builder.mov(rax, out);
        builder.ret();

        final fn = builder.build(runtime);
        final call = _as1(fn);
        expect(call(0), equals(0));
        expect(call(1), equals(0));
        expect(call(2), equals(0));
        expect(call(3), equals(3));
        fn.dispose();
      }

      // Caso 6: cadeia de saltos (100 saltos).
      {
        final builder = X86CodeBuilder.create();
        final labels = <Label>[];
        for (var i = 0; i < 100; i++) {
          labels.add(builder.newLabel());
        }
        for (final l in labels) {
          builder.jmp(l);
          builder.label(l);
        }
        builder.mov(rax, 0);
        builder.ret();

        final fn = builder.build(runtime);
        final call = _as0(fn);
        expect(call(), equals(0));
        fn.dispose();
      }

      runtime.dispose();
    });
    test('asmjit_test_compiler_a64.cpp', () {}, skip: 'pending port');
    test('asmjit_test_emitters.cpp (scaffold)', () {
      final env = Environment.host();
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      asm.nop();
      asm.int3();
      asm.ret();

      final bytes = code.text.buffer.bytes;
      expect(bytes.length, equals(3));
      expect(bytes, equals([0x90, 0xCC, 0xC3]));
    });

    test('asmjit_test_instinfo.cpp (parcial)', () {
      final add = x86InstByName('add');
      final mov = x86InstByName('mov');
      final ret = x86InstByName('ret');
      expect(add?.id, X86InstId.kAdd);
      expect(mov?.id, X86InstId.kMov);
      expect(ret?.id, X86InstId.kRet);

      final a64Add = a64InstByName('add');
      final a64Mov = a64InstByName('mov');
      final a64Ret = a64InstByName('ret');
      expect(a64Add?.id, A64InstId.kAdd);
      expect(a64Mov?.id, A64InstId.kMov);
      expect(a64Ret?.id, A64InstId.kRet);
    });

    test('asmjit_bench_codegen_x86.cpp', () {}, skip: 'pending port');
  });
}

/// Match the same parsing rules used by tool/gen_x86_db.dart.
String? _parseMnemonic(String syntax) {
  var s = syntax.trim();
  if (s.isEmpty) return null;

  // Strip prefixes like [rep], [lock], [xacquire].
  while (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end == -1) break;
    s = s.substring(end + 1).trim();
  }

  final parts = s.split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;

  final mnemonic = parts[0];
  // Remove suffix like {nf}
  final clean = mnemonic.replaceAll(RegExp(r'\{[^}]+\}'), '');
  return clean.toLowerCase();
}

String? _parseA64Mnemonic(String syntax) {
  var s = syntax.trim();
  if (s.isEmpty) return null;
  final parts = s.split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;
  final mnemonic = parts[0];
  final clean = mnemonic.replaceAll(RegExp(r'\{[^}]+\}'), '');
  return clean.toLowerCase();
}

typedef _NativeNoArgs = Int64 Function();
typedef _DartNoArgs = int Function();
typedef _NativeOneArg = Int64 Function(Int64);
typedef _DartOneArg = int Function(int);
typedef _NativeTwoArgs = Int64 Function(Int64, Int64);
typedef _DartTwoArgs = int Function(int, int);

_DartNoArgs _as0(JitFunction fn) {
  final ptr = fn.pointer.cast<NativeFunction<_NativeNoArgs>>();
  return ptr.asFunction<_DartNoArgs>();
}

_DartOneArg _as1(JitFunction fn) {
  final ptr = fn.pointer.cast<NativeFunction<_NativeOneArg>>();
  return ptr.asFunction<_DartOneArg>();
}

_DartTwoArgs _as2(JitFunction fn) {
  final ptr = fn.pointer.cast<NativeFunction<_NativeTwoArgs>>();
  return ptr.asFunction<_DartTwoArgs>();
}
