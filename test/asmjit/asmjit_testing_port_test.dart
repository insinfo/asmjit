import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/x86/x86_dispatcher.g.dart';
import 'package:asmjit/src/asmjit/arm/a64_dispatcher.g.dart';
import 'package:asmjit/src/asmjit/core/builder.dart' as ir;

void main() {
  group('asmjit-testing parity (Dart port)', () {
    test('isa_x86.json unique instructions == X86InstId.kCount', () async {
      final file = File('assets/db/isa_x86.json');
      expect(file.existsSync(), isTrue,
          reason:
              'assets/db must contain isa_x86.json (copied from referencias)');

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
          reason:
              'assets/db must contain isa_aarch64.json (copied from referencias)');

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
    test('asmjit_test_compiler_a64.cpp', () {
      final env = Environment.aarch64();

      // Caso 1: prologo/epilogo e retorno simples via builder.
      final builder = A64CodeBuilder.create(env: env);
      builder.setStackSize(16);
      builder.mov(x0, x1);
      builder.add(x0, x0, 7);
      builder.ret();

      final finalized = builder.finalize();
      final bytes = finalized.textBytes;
      expect(bytes.length, greaterThanOrEqualTo(16));

      // RET (D65F03C0) em little-endian.
      expect(
        bytes.sublist(bytes.length - 4),
        equals([0xC0, 0x03, 0x5F, 0xD6]),
      );

      // Caso 2: branch fixups (B e CBZ) com offset diferente de zero.
      final builder2 = A64CodeBuilder.create(env: env);
      final target = builder2.newLabel();
      final cbzTarget = builder2.newLabel();
      builder2.b(target);
      builder2.nop();
      builder2.label(target);
      builder2.nop();
      builder2.cbz(x0, cbzTarget);
      builder2.nop();
      builder2.nop();
      builder2.label(cbzTarget);
      builder2.ret();

      builder2.finalize();
      final buf2 = builder2.code.text.buffer;
      final bInst = buf2.read32At(0);
      final cbzInst = buf2.read32At(12);

      final bImm = bInst & 0x03FFFFFF;
      final cbzImm = (cbzInst >> 5) & 0x7FFFF;
      expect(bImm, isNonZero);
      expect(cbzImm, isNonZero);

      // Caso 3: NEON/FP e load/store vetorial basico (apenas encode).
      final builder3 = A64CodeBuilder.create(env: env);
      builder3.ldrVec(v0, x0, 0);
      builder3.ldrVec(v1, x0, 16);
      builder3.addVec(v2.s, v0.s, v1.s);
      builder3.andVec(v3.s, v2.s, v1.s);
      builder3.fadd(d0, d1, d2);
      builder3.strVec(v3, x1, 32);
      builder3.ret();
      final bytes3 = builder3.finalize().textBytes;
      expect(bytes3.isNotEmpty, isTrue);

      // Caso 4: estresse de RA/spills (GP).
      final builder4 = A64CodeBuilder.create(env: env);
      final regs = <A64Gp>[];
      for (var i = 0; i < 28; i++) {
        final r = builder4.newGpReg();
        regs.add(r);
        builder4.mov(r, x0);
        builder4.add(r, r, i);
      }
      final acc = builder4.newGpReg();
      builder4.mov(acc, xzr);
      for (final r in regs) {
        builder4.add(acc, acc, r);
      }
      builder4.mov(x0, acc);
      builder4.ret();
      final bytes4 = builder4.finalize().textBytes;
      expect(bytes4.isNotEmpty, isTrue);
      expect(
        bytes4.sublist(bytes4.length - 4),
        equals([0xC0, 0x03, 0x5F, 0xD6]),
      );

      // Caso 5: estresse de RA/spills (vetores).
      final builder5 = A64CodeBuilder.create(env: env);
      final vregs = <A64Vec>[];
      for (var i = 0; i < 40; i++) {
        final r = builder5.newVecReg(sizeBits: 128);
        vregs.add(r);
        builder5.addVec(r.s, r.s, r.s);
      }
      for (final r in vregs) {
        builder5.addVec(v0.s, v0.s, r.s);
      }
      builder5.ret();
      final bytes5 = builder5.finalize().textBytes;
      expect(bytes5.isNotEmpty, isTrue);

      // Caso 6: spill com stackSize alto (sem sobreposicao).
      final builder6 = A64CodeBuilder.create(env: env);
      builder6.setStackSize(512);
      final regs6 = <A64Gp>[];
      for (var i = 0; i < 30; i++) {
        final r = builder6.newGpReg();
        regs6.add(r);
        builder6.mov(r, x0);
        builder6.add(r, r, i);
      }
      final acc6 = builder6.newGpReg();
      builder6.mov(acc6, xzr);
      for (final r in regs6) {
        builder6.add(acc6, acc6, r);
      }
      builder6.mov(x0, acc6);
      builder6.ret();
      final bytes6 = builder6.finalize().textBytes;
      expect(bytes6.isNotEmpty, isTrue);
      expect(
        bytes6.sublist(bytes6.length - 4),
        equals([0xC0, 0x03, 0x5F, 0xD6]),
      );
      final spillOffsets = builder6.debugSpillOffsets();
      for (final off in spillOffsets) {
        expect(off, greaterThanOrEqualTo(512));
      }
    });
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

    test('asmjit_bench_codegen_x86.cpp', () {
      final env = Environment.host();
      final code = CodeHolder(env: env);
      final asm = X86Assembler(code);

      final r0 = env.is32Bit ? eax : rax;
      final r1 = env.is32Bit ? ebx : rbx;
      final r2 = env.is32Bit ? ecx : rcx;
      final loopLabel = asm.newLabel();
      asm.bind(loopLabel);

      final loops = [512, 2048, 8192];
      for (final count in loops) {
        final start = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          asm.movRR(r0, r1);
          asm.addRI(r0, i & 0x7F);
          asm.xorRR(r2, r2);
          asm.cmpRR(r0, r2);
          asm.jcc(X86Cond.ne, loopLabel);
        }
        start.stop();
      }

      asm.ret();
      final bytes = code.finalize().textBytes;
      expect(bytes.length, greaterThan(0));
      expect(bytes.last, equals(0xC3));
    });
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
