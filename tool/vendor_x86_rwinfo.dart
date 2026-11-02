// Copies the read/write information tables of upstream
// asmjit/x86/x86instdb.cpp (`${InstRWInfoTable}`, the RW part of
// `${AdditionalInfoTable}` and the control-flow / same-register hints of
// `${InstCommonTable}`) into assets/db/x86_rwinfo.txt, which
// tool/gen_x86_rwinfo.dart turns into lib/src/asmjit/x86/x86_rw_info.g.dart
// (used by `x86QueryRWInfo()`, the port of `InstInternal::query_rw_info()`).
//
// Upstream generates these tables with `tools/tablegen-x86.js`; they are
// copied verbatim, one row per line:
//
//   I;Name;RwInfoIndexA;RwInfoIndexB;InstRWFlags;ControlFlow;SameRegHint
//   A;Category;RmInfo;Op0;Op1;Op2;Op3;Op4;Op5     (rw_info_a_table)
//   B;Category;RmInfo;Op0;Op1;Op2;Op3;Op4;Op5     (rw_info_b_table)
//   O;RByteMask;WByteMask;PhysId;ConsecutiveLeadCount;OpRWFlags
//   R;Category;RmOpsMask;FixedSize;Flags;RmFeature
//
// Usage: dart run tool/vendor_x86_rwinfo.dart [asmjit-master]
import 'dart:io';

void main(List<String> args) {
  final root = args.isNotEmpty ? args[0] : 'referencias/asmjit-master';
  final src = File('$root/asmjit/x86/x86instdb.cpp').readAsStringSync();

  String section(String name) {
    final b = src.indexOf('\${$name:Begin}');
    final e = src.indexOf('\${$name:End}');
    if (b < 0 || e < 0) throw StateError('section $name not found');
    return src.substring(b, e);
  }

  String table(String sec, String decl) {
    final b = sec.indexOf(decl);
    if (b < 0) throw StateError('table $decl not found');
    return sec.substring(b, sec.indexOf('};', b));
  }

  // INST(id, encoding, opcode0, opcode1, main_opcode_index,
  //      alt_opcode_index, common_info_index, additional_info_index).
  final inst = RegExp(r'^\s*INST\((\w+)\s*,\s*(\w+)\s*,\s*(.{26}[^,]*),\s*'
      r'(.{26}[^,]*),\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)');
  final names = <String>[];
  final commonIndex = <int>[];
  final additionalIndex = <int>[];
  for (final line in section('InstInfo').split('\n')) {
    final m = inst.firstMatch(line);
    if (m == null) continue;
    names.add(m[1]!);
    commonIndex.add(int.parse(m[7]!));
    additionalIndex.add(int.parse(m[8]!));
  }

  final commonRe =
      RegExp(r'CONTROL_FLOW\((\w+)\)\s*,\s*SAME_REG_HINT\((\w+)\)');
  final common = <(String, String)>[];
  for (final line in section('InstCommonTable').split('\n')) {
    final m = commonRe.firstMatch(line);
    if (m != null && line.trimLeft().startsWith('{')) {
      common.add((m[1]!, m[2]!));
    }
  }

  final additional = section('AdditionalInfoTable');
  // { inst_flags_index, rw_flags_index, { features } }
  final additionalRe = RegExp(r'^\s*\{\s*(\d+)\s*,\s*(\d+)\s*,');
  final instFlagsIndex = <int>[];
  for (final line
      in table(additional, 'InstDB::additional_info_table[]').split('\n')) {
    final m = additionalRe.firstMatch(line);
    if (m != null) instFlagsIndex.add(int.parse(m[1]!));
  }
  final instFlags = <String>[];
  for (final line
      in table(additional, 'InstDB::inst_flags_table[]').split('\n')) {
    final m = RegExp(r'InstRWFlags\(FLAG\((\w+)\)\)').firstMatch(line);
    if (m != null) instFlags.add(m[1]!);
  }

  final rw = section('InstRWInfoTable');
  List<int> indexTable(String decl) => RegExp(r'\d+')
      .allMatches(table(rw, decl).split('= {')[1])
      .map((m) => int.parse(m[0]!))
      .toList();
  final indexA = indexTable('InstDB::rw_info_index_a_table');
  final indexB = indexTable('InstDB::rw_info_index_b_table');
  if (indexA.length != names.length || indexB.length != names.length) {
    throw StateError('rw_info_index tables do not match the instructions');
  }

  final out = StringBuffer()
    ..writeln('# Copied from asmjit/x86/x86instdb.cpp by '
        'tool/vendor_x86_rwinfo.dart; do not edit.');
  for (var i = 0; i < names.length; i++) {
    final (cf, srh) = common[commonIndex[i]];
    out.writeln([
      'I',
      names[i],
      indexA[i],
      indexB[i],
      instFlags[instFlagsIndex[additionalIndex[i]]],
      cf,
      srh,
    ].join(';'));
  }

  final rwInfoRe = RegExp(r'kCategory(\w+)\s*,\s*(\d+)\s*,\s*\{([^}]*)\}');
  for (final (tag, decl) in [
    ('A', 'InstDB::rw_info_a_table[]'),
    ('B', 'InstDB::rw_info_b_table[]'),
  ]) {
    for (final line in table(rw, decl).split('\n')) {
      final m = rwInfoRe.firstMatch(line);
      if (m == null) continue;
      final ops = m[3]!.split(',').map((s) => s.trim()).toList();
      out.writeln([tag, m[1], m[2], ...ops].join(';'));
    }
  }

  final opRe = RegExp(r'\{\s*0x([0-9A-F]+)u\s*,\s*0x([0-9A-F]+)u\s*,\s*'
      r'0x([0-9A-F]+)\s*,\s*(\d+)\s*,\s*\{\s*0\s*\}\s*,\s*([^}]*?)\s*\}');
  for (final line in table(rw, 'InstDB::rw_info_op_table[]').split('\n')) {
    final m = opRe.firstMatch(line);
    if (m == null) continue;
    final flags = m[5]!
        .split('|')
        .map((f) => f.trim().replaceFirst('OpRWFlags::k', ''))
        .join('|');
    out.writeln(['O', m[1], m[2], m[3], m[4], flags].join(';'));
  }

  final rmRe = RegExp(r'kCategory(\w+)\s*,\s*0x([0-9A-F]+)\s*,\s*(\d+)\s*,\s*'
      r'([^,]+?)\s*,\s*([^}]+?)\s*\}');
  for (final line in table(rw, 'InstDB::rw_info_rm_table[]').split('\n')) {
    final m = rmRe.firstMatch(line);
    if (m == null) continue;
    final flags = m[4] == '0'
        ? '0'
        : m[4]!
            .split('|')
            .map((f) => f.trim().replaceFirst('InstDB::RWInfoRm::k', ''))
            .join('|');
    final feature = RegExp(r'X86::k(\w+)').firstMatch(m[5]!)?.group(1) ?? '0';
    out.writeln(['R', m[1], m[2], m[3], flags, feature].join(';'));
  }

  File('assets/db/x86_rwinfo.txt').writeAsStringSync(out.toString());
  stdout.writeln('assets/db/x86_rwinfo.txt: ${names.length} instructions');
}
