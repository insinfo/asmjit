/// AsmJit x86 Instruction Database Generator
///
/// This tool parses the isa_x86.json from AsmJit's db/ directory
/// and generates Dart const tables for the instruction database.
///
/// Usage:
///   dart run tool/gen_x86_db.dart
///
/// Output:
///   lib/src/x86/x86_inst_db.g.dart
///   lib/src/x86/x86_opcode_db.g.dart

import 'package:asmjit/src/asmjit/x86/x86_opcode.dart';
import 'dart:convert';
import 'dart:io';

/// Entry point kept for CLI usage.
Future<void> main(List<String> args) async {
  final jsonPath = args.isNotEmpty ? args[0] : 'assets/db/isa_x86.json';
  await generateX86Db(
    jsonPath: jsonPath,
    instOutputPath: 'lib/src/asmjit/x86/x86_inst_db.g.dart',
  );
}

/// Gera a base de instruções x86 (IDs + tabela) a partir do `isa_x86.json` e
/// dos dados de encoding do upstream (`assets/db/x86_instdb.txt`, copiados
/// do `x86instdb.cpp` por `tool/vendor_x86_instdb.dart`), usados pelo port do
/// encoder (`lib/src/asmjit/x86/x86_emit.dart`).
Future<void> generateX86Db({
  String jsonPath = 'assets/db/isa_x86.json',
  String instdbPath = 'assets/db/x86_instdb.txt',
  String instOutputPath = 'lib/src/asmjit/x86/x86_inst_db.g.dart',
}) async {
  print('=== AsmJit x86 Instruction DB Generator ===');
  print('Input: $jsonPath');
  print('Inst Output: $instOutputPath');
  print('');

  final generator = X86DbGenerator();
  await generator.loadFromFile(jsonPath);
  generator.loadEncodings(instdbPath);
  generator.analyze();
  generator.generateInstDb(instOutputPath);

  print('');
  print('Done! Generated $instOutputPath');
}

/// Represents a parsed instruction from the JSON
class ParsedInst {
  final String mnemonic;
  final String operands;
  final String opcode;
  final String? ioFlags;
  final String arch; // 'any', 'x86', 'x64', 'apx'
  final String category;
  final String? extension;
  final bool isAlt; // alternate encoding
  final bool isVolatile;
  final bool hasLock;
  final bool hasRep;

  ParsedInst({
    required this.mnemonic,
    required this.operands,
    required this.opcode,
    this.ioFlags,
    required this.arch,
    required this.category,
    this.extension,
    this.isAlt = false,
    this.isVolatile = false,
    this.hasLock = false,
    this.hasRep = false,
  });

  @override
  String toString() => '$mnemonic ($arch): $operands | $opcode';
}

/// Unique instruction (by mnemonic)
class InstInfo {
  final int id;
  final String name;
  final Set<String> categories = {};
  final Set<String> extensions = {};
  final List<ParsedInst> forms = [];

  InstInfo(this.id, this.name);

  bool get hasX86Only => forms.any((f) => f.arch == 'x86');
  bool get hasX64Only => forms.any((f) => f.arch == 'x64');
  bool get hasAny => forms.any((f) => f.arch == 'any');
}

/// Encoder data of an instruction (a row of upstream `x86instdb.cpp`).
class EncodingInfo {
  final int encoding;
  final int opcode0;
  final int opcode1;
  final int flags;
  final int avx512Flags;
  EncodingInfo(
      this.encoding, this.opcode0, this.opcode1, this.flags, this.avx512Flags);
}

/// Value of an `O(...)`, `V(...)`, `E(...)` or `O_FPU(...)` opcode of
/// upstream `x86instdb.cpp` (the `O_ENCODE` macros).
int parseX86Opcode(String text) {
  text = text.replaceAll(' ', '');
  if (text == '0') return 0;
  final m = RegExp(r'^(O_FPU|O|V|E)\((.*)\)$').firstMatch(text);
  if (m == null) throw FormatException('opcode $text');
  final a = m[2]!.split(',');
  int field(String v, int shift) => v == '_' ? 0 : int.parse(v) << shift;
  int bit(String v, int shift) =>
      const {'_', 'x', 'I', '0'}.contains(v) ? 0 : int.parse(v) << shift;
  final op = int.parse(a[1], radix: 16);
  if (m[1] == 'O_FPU') {
    return X86Opcode.prefixes['FPU_${a[0]}']! |
        (op & 0xFF) |
        ((op >> 8) << X86Opcode.kFPU_2B_Shift) |
        field(a[2], X86Opcode.kModO_Shift);
  }
  var v = X86Opcode.prefixes[a[0]]! |
      op |
      field(a[2], X86Opcode.kModO_Shift) |
      bit(a[3], X86Opcode.kLL_Shift) |
      bit(a[4], X86Opcode.kW_Shift) |
      bit(a[5], X86Opcode.kEvex_W_Shift) |
      field(a[6], X86Opcode.kCDSHL_Shift);
  if (m[1] == 'O') {
    v |= field(a[7], X86Opcode.kModRM_Shift);
  } else {
    v |= X86Opcode.cdtt[a[7]]!;
  }
  if (m[1] == 'E') v |= X86Opcode.kMM_ForceEvex;
  return v;
}

class X86DbGenerator {
  Map<String, dynamic> _json = {};

  /// Encoder data by (lowercase) instruction name.
  final Map<String, EncodingInfo> _encodings = {};

  void loadEncodings(String path) {
    for (final line in File(path).readAsLinesSync()) {
      if (line.startsWith('#') || line.isEmpty) continue;
      final f = line.split(';');
      if (f[0] == 'None') continue;
      int flagsOf(String s, Map<String, int> names) =>
          s.isEmpty ? 0 : s.split('|').fold(0, (v, n) => v | names[n]!);
      final enc = X86Encoding.names.indexOf(f[1]);
      if (enc < 0) throw FormatException('encoding ${f[1]}');
      _encodings[f[0].toLowerCase()] = EncodingInfo(
          enc,
          parseX86Opcode(f[2]),
          parseX86Opcode(f[3]),
          flagsOf(f[4], X86InstDbFlags.byName),
          flagsOf(f[5], X86Avx512Flags.byName));
    }
  }

  final Map<String, InstInfo> _instructions = {};
  int _nextId = 0;

  Future<void> loadFromFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception('File not found: $path');
    }

    final content = await file.readAsString();
    _json = json.decode(content) as Map<String, dynamic>;
    print('Loaded JSON: ${content.length} bytes');
  }

  void analyze() {
    final instructions = _json['instructions'] as List<dynamic>;
    print('Found ${instructions.length} instruction categories');

    for (final catObj in instructions) {
      final cat = catObj as Map<String, dynamic>;
      final category = cat['category'] as String? ?? 'unknown';
      final extension = cat['ext'] as String?;
      final isVolatile = cat['volatile'] as bool? ?? false;

      final instList = cat['instructions'] as List<dynamic>?;
      if (instList == null) continue;

      for (final instObj in instList) {
        final inst = instObj as Map<String, dynamic>;
        _parseInstruction(inst, category, extension, isVolatile);
      }
    }

    print('Parsed ${_instructions.length} unique instructions');
    print(
        'Total forms: ${_instructions.values.fold(0, (s, i) => s + i.forms.length)}');
  }

  void _parseInstruction(
    Map<String, dynamic> inst,
    String category,
    String? extension,
    bool isVolatile,
  ) {
    // Determine architecture
    String arch = 'any';
    String? syntax;

    if (inst.containsKey('any')) {
      arch = 'any';
      syntax = inst['any'] as String;
    } else if (inst.containsKey('x86')) {
      arch = 'x86';
      syntax = inst['x86'] as String;
    } else if (inst.containsKey('x64')) {
      arch = 'x64';
      syntax = inst['x64'] as String;
    } else if (inst.containsKey('apx')) {
      arch = 'apx';
      syntax = inst['apx'] as String;
    }

    if (syntax == null) return;

    final opcode = inst['op'] as String? ?? '';
    final ioFlags = inst['io'] as String?;
    final isAlt = inst['alt'] as bool? ?? false;

    // Parse mnemonic and operands from syntax
    // Format: "[prefix] mnemonic operands"
    final parsed = _parseSyntax(syntax);
    if (parsed == null) return;

    final mnemonic = parsed.mnemonic.toLowerCase();

    // Get or create InstInfo
    var info = _instructions[mnemonic];
    if (info == null) {
      info = InstInfo(_nextId++, mnemonic);
      _instructions[mnemonic] = info;
    }

    info.categories.add(category);
    if (extension != null) {
      info.extensions.add(extension);
    }

    info.forms.add(ParsedInst(
      mnemonic: mnemonic,
      operands: parsed.operands,
      opcode: opcode,
      ioFlags: ioFlags,
      arch: arch,
      category: category,
      extension: extension,
      isAlt: isAlt,
      isVolatile: isVolatile,
      hasLock: parsed.hasLock,
      hasRep: parsed.hasRep,
    ));
  }

  /// Access of the first operand per operand count, from the `R:`/`W:`/`X:`
  /// prefixes of the forms (no prefix means read). `w:` only overwrites the
  /// addressed part of the register, so like asmjit's RA (which turns such a
  /// write into read/write when the virtual register is wider) it is a
  /// read/write of vector registers, whose virtual registers are full width;
  /// general purpose `w:` writes stay writes. Forms with the same operand
  /// count that disagree are treated as read/write. APX forms are not used.
  int _op0Access(InstInfo inst) {
    final byCount = <int, int>{};
    for (final f in inst.forms) {
      if (f.arch == 'apx') continue;
      final ops = f.operands
          .split(',')
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toList();
      if (ops.isEmpty || ops.length > 15) continue;
      final m = RegExp(r'^([RWXrwx]):(.*)').firstMatch(ops[0]);
      final access = m == null
          ? 1
          : switch (m.group(1)!) {
              'W' => 2,
              'w' =>
                RegExp(r'^(xmm|ymm|zmm|xy|mm)').hasMatch(m.group(2)!) ? 3 : 2,
              'X' || 'x' => 3,
              _ => 1,
            };
      final prev = byCount[ops.length];
      byCount[ops.length] = prev == null || prev == access ? access : 3;
    }
    var value = 0;
    byCount.forEach((count, access) => value |= access << (2 * count));
    return value;
  }

  ({String mnemonic, String operands, bool hasLock, bool hasRep})? _parseSyntax(
      String syntax) {
    var s = syntax.trim();
    bool hasLock = false;
    bool hasRep = false;

    // Remove prefix brackets like [lock|xacqrel], [rep], etc.
    while (s.startsWith('[')) {
      final end = s.indexOf(']');
      if (end == -1) break;
      final prefix = s.substring(1, end).toLowerCase();
      if (prefix.contains('lock')) hasLock = true;
      if (prefix.contains('rep')) hasRep = true;
      s = s.substring(end + 1).trim();
    }

    // Split mnemonic and operands
    final parts = s.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;

    final mnemonic = parts[0];
    final operands = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    // Remove {nf} suffix from mnemonic if present
    final cleanMnemonic = mnemonic.replaceAll(RegExp(r'\{[^}]+\}'), '');

    return (
      mnemonic: cleanMnemonic,
      operands: operands,
      hasLock: hasLock,
      hasRep: hasRep
    );
  }

  void generateInstDb(String outputPath) {
    final buffer = StringBuffer();

    buffer.writeln('// GENERATED FILE - DO NOT EDIT');
    buffer.writeln('// Generated by tool/gen_x86_db.dart');
    buffer
        .writeln('// Source: assets/db/isa_x86.json, assets/db/x86_instdb.txt');
    buffer.writeln('');
    buffer.writeln('/// x86 Instruction IDs');
    buffer.writeln('abstract class X86InstId {');

    // Sort instructions alphabetically
    final sorted = _instructions.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // Generate enum-like constants
    for (final inst in sorted) {
      final constName = _toConstName(inst.name);
      buffer.writeln(
          '  static const int k${_capitalize(constName)} = ${inst.id};');
    }

    buffer.writeln('');
    buffer.writeln('  static const int kCount = ${sorted.length};');
    buffer.writeln('}');
    buffer.writeln('');

    // Generate instruction info class
    buffer.writeln('/// Basic info about an instruction.');
    buffer.writeln('class X86InstInfo {');
    buffer.writeln('  final int id;');
    buffer.writeln('  final String name;');
    buffer.writeln('  final int flags;');
    buffer.writeln('  final List<String> extensions;');
    buffer.writeln('');
    buffer.writeln(
        '  /// Access of the first operand per operand count (2 bits per');
    buffer.writeln(
        '  /// count, implicit operands like `<xmm0>` included): 0 = no form,');
    buffer.writeln('  /// 1 = read, 2 = write, 3 = read/write.');
    buffer.writeln('  final int op0Access;');
    buffer.writeln('');
    buffer.writeln(
        '  /// Encoder data from upstream `x86instdb.cpp`: encoding id');
    buffer.writeln(
        '  /// ([X86Encoding]), main and alternative opcode ([X86Opcode]),');
    buffer.writeln(
        '  /// [X86InstDbFlags] and [X86Avx512Flags] (all 0 when upstream');
    buffer.writeln('  /// has no such instruction).');
    buffer.writeln('  final int encoding;');
    buffer.writeln('  final int mainOpcode;');
    buffer.writeln('  final int altOpcode;');
    buffer.writeln('  final int dbFlags;');
    buffer.writeln('  final int avx512Flags;');
    buffer.writeln('');
    buffer.writeln('  const X86InstInfo({');
    buffer.writeln('    required this.id,');
    buffer.writeln('    required this.name,');
    buffer.writeln('    this.flags = 0,');
    buffer.writeln('    this.extensions = const [],');
    buffer.writeln('    this.op0Access = 0,');
    buffer.writeln('    this.encoding = 0,');
    buffer.writeln('    this.mainOpcode = 0,');
    buffer.writeln('    this.altOpcode = 0,');
    buffer.writeln('    this.dbFlags = 0,');
    buffer.writeln('    this.avx512Flags = 0,');
    buffer.writeln('  });');
    buffer.writeln('');
    buffer.writeln(
        '  /// Access of the first operand of the form with [opCount]');
    buffer.writeln('  /// operands (0 when the instruction has no such form).');
    buffer.writeln('  int op0AccessOf(int opCount) =>');
    buffer
        .writeln('      opCount < 16 ? (op0Access >> (2 * opCount)) & 3 : 0;');
    buffer.writeln('}');
    buffer.writeln('');

    // Generate flags
    buffer.writeln('/// Instruction flags.');
    buffer.writeln('abstract class X86InstFlags {');
    buffer.writeln('  static const int kNone = 0;');
    buffer.writeln('  static const int kLockable = 1 << 0;');
    buffer.writeln('  static const int kRepable = 1 << 1;');
    buffer.writeln('  static const int kVolatile = 1 << 2;');
    buffer.writeln('  static const int kX86Only = 1 << 3;');
    buffer.writeln('  static const int kX64Only = 1 << 4;');
    buffer.writeln('  static const int kHasAlt = 1 << 5;');
    buffer.writeln('}');
    buffer.writeln('');

    // Generate instruction table
    buffer.writeln('/// x86 instruction database.');
    // Indexed by instruction id (`kX86InstDb[X86InstId.kMov]`), so the list
    // must follow id order, not the alphabetical order of the constants.
    buffer.writeln('const kX86InstDb = <X86InstInfo>[');

    final byId = _instructions.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final inst in byId) {
      final flags = <String>[];
      if (inst.forms.any((f) => f.hasLock)) {
        flags.add('X86InstFlags.kLockable');
      }
      if (inst.forms.any((f) => f.hasRep)) {
        flags.add('X86InstFlags.kRepable');
      }
      if (inst.forms.any((f) => f.isVolatile)) {
        flags.add('X86InstFlags.kVolatile');
      }
      if (inst.hasX86Only && !inst.hasAny && !inst.hasX64Only) {
        flags.add('X86InstFlags.kX86Only');
      }
      if (inst.hasX64Only && !inst.hasAny && !inst.hasX86Only) {
        flags.add('X86InstFlags.kX64Only');
      }
      if (inst.forms.any((f) => f.isAlt)) {
        flags.add('X86InstFlags.kHasAlt');
      }

      final flagsStr = flags.isEmpty ? '0' : flags.join(' | ');
      final extsStr = inst.extensions.isEmpty
          ? 'const []'
          : "const [${inst.extensions.map((e) => "'$e'").join(', ')}]";

      final access = _op0Access(inst);
      final accessStr = access == 0
          ? ''
          : ', op0Access: 0x${access.toRadixString(16).toUpperCase()}';
      final e = _encodings[inst.name];
      String hex(int v) => '0x${v.toRadixString(16).toUpperCase()}';
      final encStr = e == null
          ? ''
          : ', encoding: ${e.encoding}, mainOpcode: ${hex(e.opcode0)}, '
              'altOpcode: ${hex(e.opcode1)}, dbFlags: ${hex(e.flags)}, '
              'avx512Flags: ${hex(e.avx512Flags)}';
      buffer.writeln("  X86InstInfo(id: ${inst.id}, name: '${inst.name}', "
          'flags: $flagsStr, extensions: $extsStr$accessStr$encStr),');
    }

    buffer.writeln('];');
    buffer.writeln('');

    // Generate lookup by name
    buffer.writeln('/// Lookup instruction by name.');
    buffer.writeln('X86InstInfo? x86InstByName(String name) {');
    buffer.writeln('  final lower = name.toLowerCase();');
    buffer.writeln('  for (final inst in kX86InstDb) {');
    buffer.writeln('    if (inst.name == lower) return inst;');
    buffer.writeln('  }');
    buffer.writeln('  return null;');
    buffer.writeln('}');
    buffer.writeln('');

    // Generate lookup by ID
    buffer.writeln('/// Lookup instruction by ID.');
    buffer.writeln('X86InstInfo? x86InstById(int id) {');
    buffer.writeln('  if (id < 0 || id >= kX86InstDb.length) return null;');
    buffer.writeln('  return kX86InstDb[id];');
    buffer.writeln('}');

    // Write file
    final outFile = File(outputPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(buffer.toString());

    final missing =
        _encodings.keys.where((n) => !_instructions.containsKey(n)).toList();
    if (missing.isNotEmpty) {
      throw StateError('x86_instdb.txt instructions missing from isa_x86.json: '
          '${missing.join(', ')}');
    }
    print('Generated ${sorted.length} instructions '
        '(${_encodings.length} with encoder data)');
  }

  String _toConstName(String name) {
    // Convert instruction name to valid Dart identifier
    return name
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
