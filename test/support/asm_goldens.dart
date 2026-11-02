// Runner of the upstream assembler goldens extracted to test/data/ by
// tool/convert_asmjit_assembler_tests.dart.
//
// Cases the port does not encode yet are listed in
// test/data/asmjit_assembler_<arch>.unsupported. The list is a ratchet: every
// other case must match upstream byte for byte, and a listed case that starts
// matching makes the test fail until it is removed from the list. Rewrite the
// list with `UPDATE_GOLDENS=1 dart test <test file>`; with
// `GOLDENS_REPORT=<file>` the update also writes why each case fails.
import 'dart:io';

import 'package:test/test.dart';

/// A case the test cannot express with the port's API (as opposed to a case
/// the port encodes differently).
class GoldenUnsupported implements Exception {
  final String why;
  GoldenUnsupported(this.why);
  @override
  String toString() => why;
}

String _hex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// Declares one test per upstream test function of [arch] ('x64', 'a64');
/// [assemble] returns the bytes the port emits for an upstream expression.
void assemblerGoldens(String arch, List<int> Function(String expr) assemble) {
  final dataFile = 'test/data/asmjit_assembler_$arch.txt';
  final unsupportedFile = 'test/data/asmjit_assembler_$arch.unsupported';
  final cases = [
    for (final line in File(dataFile).readAsLinesSync())
      if (!line.startsWith('#')) line.split('\t')
  ];
  final unsupported = File(unsupportedFile).existsSync()
      ? {
          for (final l in File(unsupportedFile).readAsLinesSync())
            if (!l.startsWith('#') && l.isNotEmpty) l
        }
      : <String>{};

  // Why a case does not match upstream, or null when it does.
  String? outcome(List<String> c) {
    try {
      final got = _hex(assemble(c[2]));
      return got == c[1] ? null : 'got $got';
    } on GoldenUnsupported catch (e) {
      return 'unsupported: $e';
    } catch (e) {
      return 'error: ${e.toString().split('\n').first}';
    }
  }

  String key(List<String> c) => '${c[0]}\t${c[1]}\t${c[2]}';

  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    test('update $unsupportedFile', () {
      final failing = <String>[];
      final report = StringBuffer();
      for (final c in cases) {
        final o = outcome(c);
        if (o == null) continue;
        failing.add(key(c));
        report.writeln('${key(c)}\t$o');
      }
      File(unsupportedFile).writeAsStringSync([
            '# Upstream $arch assembler cases the port does not encode yet',
            '# (see test/support/asm_goldens.dart).',
            ...failing,
          ].join('\n') +
          '\n');
      final reportPath = Platform.environment['GOLDENS_REPORT'];
      if (reportPath != null) File(reportPath).writeAsStringSync('$report');
      // ignore: avoid_print
      print('${cases.length - failing.length} of ${cases.length} match');
    });
    return;
  }

  final groups = <String, List<List<String>>>{};
  for (final c in cases) {
    (groups[c[0]] ??= []).add(c);
  }
  groups.forEach((name, list) {
    test(name, () {
      final errors = <String>[];
      for (final c in list) {
        final listed = unsupported.contains(key(c));
        final o = outcome(c);
        if (o != null && !listed) errors.add('${c[2]} (${c[1]}): $o');
        if (o == null && listed) {
          errors.add('${c[2]} now matches; remove it from $unsupportedFile');
        }
      }
      expect(errors, isEmpty,
          reason: '${errors.length} of ${list.length}:\n'
              '${errors.take(40).join('\n')}');
    });
  });
}
