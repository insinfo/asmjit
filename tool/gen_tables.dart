/// Aggregates all codegen tools (ported from `tools/tablegen*.js`).
///
/// Generates x86 and AArch64 instruction databases and dispatch tables using
/// only local assets (no dependency on `referencias/`).
///
/// Usage:
///   dart run tool/gen_tables.dart
///   dart run tool/gen_tables.dart assets/db/custom_dir
///
/// Opcional: passar um header para enumgen como terceiro argumento
/// (ex.: dart run tool/gen_tables.dart assets/db include/myenum.h)

import 'dart:async';

import 'gen_a64_db.dart' as a64;
import 'gen_x86_db.dart' as x86;
import 'gen_enum.dart' as enumgen;

Future<void> main(List<String> args) async {
  final dbDir = args.isNotEmpty ? args[0] : 'assets/db';
  final x86Json = '$dbDir/isa_x86.json';
  final a64Json = '$dbDir/isa_aarch64.json';
  final enumHeader = args.length > 1 ? args[1] : null;

  print('=== Running all table generators (Dart port) ===');
  await x86.generateX86Db(jsonPath: x86Json);
  await a64.generateA64Db(jsonPath: a64Json);
  if (enumHeader != null) {
    final out = 'tool/generated_enum.g.dart';
    print('Enumgen: $enumHeader -> $out');
    // gen_enum main is sync; wrap in Future to keep signature async.
    await Future<void>.sync(() => enumgen.main([enumHeader, out]));
  }
  print('=== Done (tablegen Dart port) ===');
}
