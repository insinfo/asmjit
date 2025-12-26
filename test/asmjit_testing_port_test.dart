import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/x86/x86_dispatcher.g.dart';
import 'package:asmjit/src/arm/a64_dispatcher.g.dart';
import 'package:asmjit/src/arm/a64.dart';
import 'package:asmjit/src/arm/a64_assembler.dart';
import 'package:asmjit/src/arm/a64_inst_db.g.dart';

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

    test('A64 dispatcher encodes add/ret without fallback', () {
      final env = Environment.host();
      final code = CodeHolder(env: env);
      final asm = A64Assembler(code);

      a64Dispatch(asm, A64InstId.kMov, [x0, x1]);
      a64Dispatch(asm, A64InstId.kAdd, [x0, x0, 1]);
      a64Dispatch(asm, A64InstId.kRet, const []);

      expect(code.text.buffer.length, greaterThan(0));
    });

    // Grandes suítes originais permanecem pendentes de porte completo.
    test('asmjit_test_assembler_x64.cpp', () {}, skip: 'pending port');
    test('asmjit_test_assembler_x86.cpp', () {}, skip: 'pending port');
    test('asmjit_test_compiler_x86.cpp', () {}, skip: 'pending port');
    test('asmjit_test_compiler_a64.cpp', () {}, skip: 'pending port');
    test('asmjit_test_emitters.cpp', () {}, skip: 'pending port');
    test('asmjit_test_instinfo.cpp', () {}, skip: 'pending port');
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
