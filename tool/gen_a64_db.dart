/// AsmJit AArch64 Instruction Database Generator
///
/// This tool parses the isa_aarch64.json from AsmJit's db/ directory
/// and generates Dart const tables for the instruction database.
///
/// Usage:
///   dart run tool/gen_a64_db.dart
///
/// Output:
///   lib/src/arm/a64_inst_db.g.dart

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final jsonPath = args.isNotEmpty ? args[0] : 'assets/db/isa_aarch64.json';
  await generateA64Db(
    jsonPath: jsonPath,
    instOutputPath: 'lib/src/asmjit/arm/a64_inst_db.g.dart',
  );
}

/// Gera IDs e tabela de instruções AArch64 a partir do `isa_aarch64.json`.
Future<void> generateA64Db({
  String jsonPath = 'assets/db/isa_aarch64.json',
  String instdbPath = 'assets/db/a64_instdb.txt',
  String instOutputPath = 'lib/src/asmjit/arm/a64_inst_db.g.dart',
}) async {
  print('=== AsmJit AArch64 Instruction DB Generator ===');
  print('Input: $jsonPath');
  print('Output: $instOutputPath');
  print('');

  final generator = A64DbGenerator();
  await generator.loadFromFile(jsonPath);
  generator.analyze();
  generator.addUpstreamInstructions(instdbPath);
  generator.generateInstDb(instOutputPath);

  print('');
  print('Done! Generated $instOutputPath');
}

/// Represents a parsed instruction from the JSON
class ParsedInst {
  final String mnemonic;
  final String operands;
  final String opcode;
  final String arch; // 'a64' usually
  final bool isAlt;
  final List<String> extensions;
  final String? category;
  final Map<String, dynamic> raw;

  ParsedInst({
    required this.mnemonic,
    required this.operands,
    required this.opcode,
    required this.arch,
    this.isAlt = false,
    this.extensions = const [],
    this.category,
    this.raw = const {},
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
}

class A64DbGenerator {
  Map<String, dynamic> _json = {};
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

  /// Adds the instructions of the upstream table (assets/db/a64_instdb.txt,
  /// see tool/vendor_a64_instdb.dart) that isa_aarch64.json lacks, so every
  /// instruction the encoder supports has an id (`fcvtxn`...). The vector
  /// variants (`add_v`) share the id of their name.
  void addUpstreamInstructions(String path) {
    final known = {
      for (final name in _instructions.keys) ...name.split('|'),
    };
    for (final line in File(path).readAsLinesSync()) {
      if (line.startsWith('#') || line.isEmpty) continue;
      var name = line.split(';').first.toLowerCase();
      if (name == 'none') continue;
      if (name.endsWith('_v')) name = name.substring(0, name.length - 2);
      if (known.add(name)) {
        _instructions[name] = InstInfo(_nextId++, name);
      }
    }
  }

  void analyze() {
    final instructions = _json['instructions'] as List<dynamic>;
    print('Found ${instructions.length} instruction categories');

    for (final catObj in instructions) {
      final cat = catObj as Map<String, dynamic>;
      final category = cat['category'] as String? ?? '';
      // AArch64 DB uses 'data' instead of 'instructions'.
      final instList = cat['data'] as List<dynamic>?;
      if (instList == null) continue;

      for (final instObj in instList) {
        final inst = instObj as Map<String, dynamic>;
        _parseInstruction(inst, category: category);
      }
    }

    print('Parsed ${_instructions.length} unique instructions');
  }

  void _parseInstruction(Map<String, dynamic> inst, {String? category}) {
    // Expected keys: inst (syntax), op (encoding), io (flags), ext? (list)
    final syntax = inst['inst'] as String?;
    if (syntax == null || syntax.trim().isEmpty) {
      if (_instructions.isEmpty) {
        print('Sample instruction keys: ${inst.keys.toList()}');
      }
      return;
    }

    final opcode = inst['op'] as String? ?? '';
    final extField = inst['ext'];
    final List<String> extList;
    if (extField is List) {
      extList = extField.map((e) => e.toString()).toList();
    } else if (extField is String) {
      extList = [extField];
    } else {
      extList = const [];
    }

    final parsed = _parseSyntax(syntax);
    if (parsed == null) return;

    final mnemonic = parsed.mnemonic.toLowerCase();

    var info = _instructions[mnemonic];
    if (info == null) {
      info = InstInfo(_nextId++, mnemonic);
      _instructions[mnemonic] = info;
    }

    info.forms.add(ParsedInst(
      mnemonic: mnemonic,
      operands: parsed.operands,
      opcode: opcode,
      arch: 'a64',
      extensions: extList,
      category: category,
      raw: inst,
    ));
    if (category != null && category.isNotEmpty) info.categories.add(category);
    info.extensions.addAll(extList);
  }

  ({String mnemonic, String operands})? _parseSyntax(String syntax) {
    var s = syntax.trim();
    // Remove prefixes? Likely none for A64 like [lock].

    final parts = s.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;

    final mnemonic = parts[0];
    final operands = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    // Strip {..}
    final cleanMnemonic = mnemonic.replaceAll(RegExp(r'\{[^}]+\}'), '');

    return (mnemonic: cleanMnemonic, operands: operands);
  }

  void generateInstDb(String outputPath) {
    final buffer = StringBuffer();

    buffer.writeln('// GENERATED FILE - DO NOT EDIT');
    buffer.writeln('// Generated by tool/gen_a64_db.dart');
    buffer.writeln('// Source: assets/db/isa_aarch64.json');
    buffer.writeln('');
    buffer.writeln('/// AArch64 Instruction IDs');
    buffer.writeln('abstract class A64InstId {');

    final sorted = _instructions.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final inst in sorted) {
      final constName = _toConstName(inst.name);
      buffer.writeln(
          '  static const int k${_capitalize(constName)} = ${inst.id};');
    }

    buffer.writeln('');
    buffer.writeln('  static const int kCount = ${sorted.length};');
    buffer.writeln('}');
    buffer.writeln('');

    buffer.writeln('class A64InstInfo {');
    buffer.writeln('  final int id;');
    buffer.writeln('  final String name;');
    buffer.writeln('');
    buffer.writeln('  const A64InstInfo({');
    buffer.writeln('    required this.id,');
    buffer.writeln('    required this.name,');
    buffer.writeln('  });');
    buffer.writeln('}');
    buffer.writeln('');

    // Indexed by instruction id, so emit in id order (not alphabetical).
    buffer.writeln('const kA64InstDb = <A64InstInfo>[');

    for (final inst in [...sorted]..sort((a, b) => a.id.compareTo(b.id))) {
      buffer.writeln("  A64InstInfo(id: ${inst.id}, name: '${inst.name}'),");
    }

    buffer.writeln('];');
    buffer.writeln('');

    buffer.writeln('A64InstInfo? a64InstByName(String name) {');
    buffer.writeln('  final lower = name.toLowerCase();');
    buffer.writeln('  for (final inst in kA64InstDb) {');
    buffer.writeln('    if (inst.name == lower) return inst;');
    buffer.writeln('  }');
    buffer.writeln('  return null;');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('A64InstInfo? a64InstById(int id) {');
    buffer.writeln('  if (id < 0 || id >= kA64InstDb.length) return null;');
    buffer.writeln('  return kA64InstDb[id];');
    buffer.writeln('}');

    // Write
    final outFile = File(outputPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(buffer.toString());

    print('Generated ${sorted.length} instructions');
  }

  String _toConstName(String name) {
    // Remove . (e.g. b.cond -> b_cond)
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
