/// Tiny Dart port of AsmJit's `enumgen.js`.
///
/// It parses simple C/C++-style enums (comma-separated, optional explicit
/// integer values) and emits a Dart `const Map<String, int>` file.
/// Suporta expressões simples com | e <<. Não gera tabelas compactadas de
/// strings ainda; para uso em código gerado basta o Map.

import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/gen_enum.dart <input.h> [output.dart]');
    exit(1);
  }

  final inputPath = args[0];
  final outputPath =
      args.length > 1 ? args[1] : 'tool/generated_enum.g.dart';

  final content = await File(inputPath).readAsString();
  final enumMap = _parseEnum(content);

  final buffer = StringBuffer()
    ..writeln('// GENERATED - simple enumgen port')
    ..writeln('// Source: $inputPath')
    ..writeln('const generatedEnum = <String, int>{');

  enumMap.forEach((k, v) => buffer.writeln("  '$k': $v,"));
  buffer.writeln('};');

  File(outputPath).writeAsStringSync(buffer.toString());
  print('Wrote $outputPath (${enumMap.length} entries)');
}

Map<String, int> _parseEnum(String content) {
  final map = <String, int>{};
  var current = -1;

  // Muito simples: split por vírgula e chaves; não trata macros complexas.
  final enumBody = RegExp(r'enum\s+[^{]*\{([\s\S]*?)\}')
      .firstMatch(content)
      ?.group(1);
  if (enumBody == null) {
    throw StateError('No enum found in $content');
  }

  for (final raw in enumBody.split(',')) {
    final entry = raw.trim();
    if (entry.isEmpty) continue;

    final parts = entry.split('=').map((s) => s.trim()).toList();
    final name = parts[0];
    if (parts.length == 2) {
      current = _evalExpression(parts[1]);
    } else {
      current++;
    }
    map[name] = current;
  }

  return map;
}

int _evalExpression(String expr) {
  // Support simple bitwise OR / shift expressions (e.g., 1<<2 | 0x10).
  int evalTerm(String term) {
    if (term.contains('<<')) {
      final pieces = term.split('<<').map((s) => s.trim()).toList();
      if (pieces.length == 2) {
        return evalTerm(pieces[0]) << evalTerm(pieces[1]);
      }
    }
    if (term.startsWith('0x') || term.startsWith('0X')) {
      return int.parse(term.substring(2), radix: 16);
    }
    return int.parse(term);
  }

  return expr
      .split('|')
      .map((t) => evalTerm(t.trim()))
      .reduce((a, b) => a | b);
}
