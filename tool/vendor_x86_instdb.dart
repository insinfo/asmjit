// Copies the instruction encoding data of upstream asmjit/x86/x86instdb.cpp
// into assets/db/x86_instdb.txt, which tool/gen_x86_db.dart turns into the
// encoder tables of lib/src/asmjit/x86/x86_inst_db.g.dart.
//
// Upstream maintains the `INST(...)` rows (instruction, encoding, opcode0,
// opcode1) by hand in x86instdb.cpp; `tools/tablegen-x86.js` derives the
// common-info table (instruction and AVX-512 flags) from them and
// isa_x86.json. Both are copied verbatim, one instruction per line:
//
//   Name|Encoding|Opcode0|Opcode1|InstFlags|Avx512Flags
//
// Usage: dart run tool/vendor_x86_instdb.dart [asmjit-master]
import 'dart:io';

void main(List<String> args) {
  final root = args.isNotEmpty ? args[0] : 'referencias/asmjit-master';
  final src = File('$root/asmjit/x86/x86instdb.cpp').readAsStringSync();

  final inst = RegExp(r'^\s*INST\((\w+)\s*,\s*(\w+)\s*,\s*(.{26}[^,]*),\s*'
      r'(.{26}[^,]*),\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)');
  final common = RegExp(r'^\s*\{\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*\d+\s*,\s*\d+'
      r'\s*,\s*CONTROL_FLOW\(\w+\)\s*,\s*SAME_REG_HINT\(\w+\)\s*\}');

  String section(String name) {
    final b = src.indexOf('\${$name:Begin}');
    final e = src.indexOf('\${$name:End}');
    if (b < 0 || e < 0) throw StateError('section $name not found');
    return src.substring(b, e);
  }

  String flags(String expr, String macro) => expr == '0'
      ? ''
      : expr
          .split('|')
          .map((f) =>
              RegExp('$macro\\((\\w+)\\)').firstMatch(f.trim())!.group(1))
          .join('|');

  final commonRows = <(String, String)>[];
  for (final line in section('InstCommonTable').split('\n')) {
    final m = common.firstMatch(line);
    if (m != null) commonRows.add((flags(m[1]!, 'F'), flags(m[2]!, 'X')));
  }

  final out = StringBuffer()
    ..writeln('# Copied from asmjit/x86/x86instdb.cpp by '
        'tool/vendor_x86_instdb.dart; do not edit.')
    ..writeln('# Name;Encoding;Opcode0;Opcode1;InstFlags;Avx512Flags');
  var count = 0;
  for (final line in section('InstInfo').split('\n')) {
    final m = inst.firstMatch(line);
    if (m == null) continue;
    final (f, x) = commonRows[int.parse(m[7]!)];
    out.writeln([m[1], m[2], m[3]!.trim(), m[4]!.trim(), f, x].join(';'));
    count++;
  }
  File('assets/db/x86_instdb.txt').writeAsStringSync(out.toString());
  stdout.writeln('assets/db/x86_instdb.txt: $count instructions, '
      '${commonRows.length} common rows');
}
