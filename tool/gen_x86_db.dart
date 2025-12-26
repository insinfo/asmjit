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

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final jsonPath = args.isNotEmpty ? args[0] : 'assets/db/isa_x86.json';

  final outputPath = 'lib/src/x86/x86_inst_db.g.dart';

  print('=== AsmJit x86 Instruction DB Generator ===');
  print('Input: $jsonPath');
  print('Output: $outputPath');
  print('');

  final generator = X86DbGenerator();
  await generator.loadFromFile(jsonPath);
  generator.analyze();
  generator.generateInstDb(outputPath);

  print('');
  print('Done! Generated $outputPath');
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

class X86DbGenerator {
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
    buffer.writeln('// Source: assets/db/isa_x86.json');
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
    buffer.writeln('  const X86InstInfo({');
    buffer.writeln('    required this.id,');
    buffer.writeln('    required this.name,');
    buffer.writeln('    this.flags = 0,');
    buffer.writeln('    this.extensions = const [],');
    buffer.writeln('  });');
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
    buffer.writeln('const kX86InstDb = <X86InstInfo>[');

    for (final inst in sorted) {
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

      buffer.writeln("  X86InstInfo(id: ${inst.id}, name: '${inst.name}', "
          'flags: $flagsStr, extensions: $extsStr),');
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

    print('Generated ${sorted.length} instructions');
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
