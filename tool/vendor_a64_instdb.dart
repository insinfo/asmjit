// Copies the instruction encoding data of upstream asmjit/arm/a64instdb.cpp
// into assets/db/, which tool/gen_a64_db.dart turns into the encoder tables
// of lib/src/asmjit/arm/a64_inst_db.g.dart and
// lib/src/asmjit/arm/a64_encoding_data.g.dart.
//
// Upstream maintains the `INST(...)` rows by hand in a64instdb.cpp and
// `tools/tablegen-a64.js` derives the `EncodingData` arrays from them. Both
// are copied verbatim:
//
//   assets/db/a64_instdb.txt         Name;Encoding;RWInfo;Flags;DataIndex
//   assets/db/a64_encoding_data.txt  the `EncodingData` section (C++ text)
//
// Usage: dart run tool/vendor_a64_instdb.dart [asmjit-master]
import 'dart:io';

void main(List<String> args) {
  final root = args.isNotEmpty ? args[0] : 'referencias/asmjit-master';
  final src = File('$root/asmjit/arm/a64instdb.cpp').readAsStringSync();

  String section(String name) {
    final b = src.indexOf('\${$name:Begin}');
    final e = src.indexOf('\${$name:End}');
    if (b < 0 || e < 0) throw StateError('section $name not found');
    return src.substring(src.indexOf('\n', b) + 1, src.lastIndexOf('\n', e));
  }

  final inst =
      RegExp(r'^\s*INST\((\w+)\s*,\s*(\w+)\s*,\s*\(.*\)\s*,\s*(\w+)\s*,'
          r'\s*([^,]+?)\s*,\s*(\d+)\s*\)');
  final out = StringBuffer()
    ..writeln('# Copied from asmjit/arm/a64instdb.cpp by '
        'tool/vendor_a64_instdb.dart; do not edit.')
    ..writeln('# Name;Encoding;RWInfo;Flags;DataIndex');
  var count = 0;
  for (final line in section('InstInfo').split('\n')) {
    final m = inst.firstMatch(line);
    if (m == null) continue;
    out.writeln([m[1], m[2], m[3], m[4]!.replaceAll(' ', ''), m[5]].join(';'));
    count++;
  }
  File('assets/db/a64_instdb.txt').writeAsStringSync(out.toString());

  final data = section('EncodingData');
  File('assets/db/a64_encoding_data.txt').writeAsStringSync(
      '// Copied from asmjit/arm/a64instdb.cpp (EncodingData) by '
      'tool/vendor_a64_instdb.dart; do not edit.\n$data\n');
  stdout.writeln('assets/db/a64_instdb.txt: $count instructions; '
      'assets/db/a64_encoding_data.txt: '
      '${RegExp(r'^const ', multiLine: true).allMatches(data).length} arrays');
}
