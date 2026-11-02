// Extracts the `TEST_INSTRUCTION(OPCODE, expr)` cases of the upstream
// assembler tests (asmjit-testing/tests/asmjit_test_assembler_{x64,a64}.cpp)
// into data files used by test/asmjit/asmjit_assembler_goldens_test.dart.
//
// The upstream sources live in the untracked `referencias/` directory, so the
// extracted cases are committed under test/data/.
//
// Usage: dart run tool/convert_asmjit_assembler_tests.dart [asmjit-master]
import 'dart:io';

const _arches = ['x64', 'a64'];

void main(List<String> args) {
  final root = args.isNotEmpty ? args[0] : 'referencias/asmjit-master';
  for (final arch in _arches) {
    final src =
        File('$root/asmjit-testing/tests/asmjit_test_assembler_$arch.cpp');
    final out = File('test/data/asmjit_assembler_$arch.txt');
    out.parent.createSync(recursive: true);

    final testCase = RegExp(r'^\s*TEST_INSTRUCTION\("([0-9A-Fa-f]*)"\s*,\s*(.*)\);');
    final function = RegExp(r'^static void ASMJIT_NOINLINE (\w+)\(');
    final sb = StringBuffer()
      ..writeln('# Extracted from asmjit-testing/tests/'
          'asmjit_test_assembler_$arch.cpp by')
      ..writeln('# tool/convert_asmjit_assembler_tests.dart; do not edit.')
      ..writeln('# <function>\\t<expected hex>\\t<upstream expression>');
    var group = '';
    var count = 0;
    for (final line in src.readAsLinesSync()) {
      final f = function.firstMatch(line);
      if (f != null) group = f.group(1)!;
      final m = testCase.firstMatch(line);
      if (m == null) continue;
      // The greedy match ends at the last `);`, which also drops a trailing
      // comment and the extra parenthesis of `ldr(h1, ptr(x2, -1))); // LDUR`.
      final expr = m.group(2)!.trim();
      sb.writeln('$group\t${m.group(1)!.toUpperCase()}\t$expr');
      count++;
    }
    out.writeAsStringSync(sb.toString());
    stdout.writeln('${out.path}: $count cases');
  }
}
