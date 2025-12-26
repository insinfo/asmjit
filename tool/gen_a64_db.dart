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
    instOutputPath: 'lib/src/arm/a64_inst_db.g.dart',
    dispatcherOutputPath: 'lib/src/arm/a64_dispatcher.g.dart',
  );
}

/// Gera IDs e tabela de instruções AArch64 a partir do `isa_aarch64.json`.
Future<void> generateA64Db({
  String jsonPath = 'assets/db/isa_aarch64.json',
  String instOutputPath = 'lib/src/arm/a64_inst_db.g.dart',
  String dispatcherOutputPath = 'lib/src/arm/a64_dispatcher.g.dart',
}) async {
  print('=== AsmJit AArch64 Instruction DB Generator ===');
  print('Input: $jsonPath');
  print('Output: $instOutputPath');
  print('Dispatcher: $dispatcherOutputPath');
  print('');

  final generator = A64DbGenerator();
  await generator.loadFromFile(jsonPath);
  generator.analyze();
  generator.generateInstDb(instOutputPath);
  generator.generateDispatcher(dispatcherOutputPath);

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

    buffer.writeln('const kA64InstDb = <A64InstInfo>[');

    for (final inst in sorted) {
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

  void generateDispatcher(String outputPath) {
    // Subconjunto suportado pelo A64Assembler hoje.
    final supported = <String>{
      // Integer ALU
      'add',
      'adds',
      'sub',
      'subs',
      'and',
      'orr',
      'eor',
      'lsl',
      'lsr',
      'asr',
      'cmp',
      'cmn',
      // Moves / immediates
      'mov',
      'movz',
      'movn',
      'movk',
      // Branches
      'adr',
      'adrp',
      'b',
      'bl',
      'b.cond',
      // 'b.cond' // model cond via explicit mnemonics later
      'cbz',
      'cbnz',
      'br',
      'blr',
      'ret',
      // Loads/Stores
      'ldr',
      'str',
      'ldrb',
      'ldrh',
      'ldrsb',
      'ldrsh',
      'ldrsw',
      'strb',
      'strh',
      'ldp',
      'stp',
      // Multiply/Divide
      'mul',
      'madd',
      'msub',
      'sdiv',
      'udiv',
      // Misc
      'nop',
      'brk',
      'svc',
      // FP/NEON basic arith
      'fadd',
      'fsub',
      'fmul',
      'fdiv',
      // FP additional
      'fneg',
      'fabs',
      'fsqrt',
      'fcmp',
      'fcsel',
      // NEON integer additional
      'neg',
      'mvn',
      'abs',
      'cls',
      'clz',
      'cnt',
      'rev16',
      'rev32',
      'rev64',
      // NEON FP vector
      'faddp',
      'fmaxnm',
      'fminnm',
      'fmax',
      'fmin',
      // Vector moves
      'dup',
      'ins',
      'umov',
      'smov',
      // Bit manipulation
      'bic',
      'orn',
      'bif',
      'bit',
      'bsl',
    };

    final sorted = _instructions.values
        .where((i) => supported.contains(i.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final buf = StringBuffer();
    final usedHelpers = <String>{};
    buf.writeln('// GENERATED FILE - DO NOT EDIT');
    buf.writeln('// Generated by tool/gen_a64_db.dart');
    buf.writeln('');
    buf.writeln("import '../core/labels.dart';");
    buf.writeln("import 'a64.dart';");
    buf.writeln("import 'a64_assembler.dart';");
    buf.writeln("import 'a64_inst_db.g.dart';");
    buf.writeln('');
    buf.writeln(
        '/// Dispatches A64 instruction IDs to assembler methods for the supported set.');
    buf.writeln(
        'void a64Dispatch(A64Assembler asm, int instId, List<Object> ops) {');
    buf.writeln('  switch (instId) {');
    for (final inst in sorted) {
      final cname = _capitalize(_toConstName(inst.name));
      buf.writeln('    case A64InstId.k$cname:');
      buf.writeln('      ${_dispatchCall(inst.name, usedHelpers)}');
      buf.writeln('      break;');
    }
    buf.writeln('    default:');
    buf.writeln('      break;');
    buf.writeln('  }');
    buf.writeln('}');
    buf.writeln('');
    buf.writeln(_helpers(usedHelpers));

    final out = File(outputPath);
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(buf.toString());
    print('Generated dispatcher at $outputPath');
  }

  String _dispatchCall(String name, Set<String> used) {
    switch (name) {
      case 'add':
        return _useHelper(used, '_add', '_add(asm, ops);');
      case 'adds':
        return _useHelper(used, '_adds', '_adds(asm, ops);');
      case 'sub':
        return _useHelper(used, '_sub', '_sub(asm, ops);');
      case 'subs':
        return _useHelper(used, '_subs', '_subs(asm, ops);');
      case 'and':
        return _useHelper(used, '_and', '_and(asm, ops);');
      case 'orr':
        return _useHelper(used, '_orr', '_orr(asm, ops);');
      case 'eor':
        return _useHelper(used, '_eor', '_eor(asm, ops);');
      case 'lsl':
        return _useHelper(used, '_shift', '_shift(asm, ops, A64Shift.lsl);');
      case 'lsr':
        return _useHelper(used, '_shift', '_shift(asm, ops, A64Shift.lsr);');
      case 'asr':
        return _useHelper(used, '_shift', '_shift(asm, ops, A64Shift.asr);');
      case 'cmp':
        return _useHelper(used, '_cmp', '_cmp(asm, ops);');
      case 'cmn':
        return _useHelper(used, '_cmn', '_cmn(asm, ops);');
      case 'mov':
        return _useHelper(used, '_mov', '_mov(asm, ops);');
      case 'movz':
        return _useHelper(used, '_movz', '_movz(asm, ops);');
      case 'movn':
        return _useHelper(used, '_movn', '_movn(asm, ops);');
      case 'movk':
        return _useHelper(used, '_movk', '_movk(asm, ops);');
      case 'adr':
        return _useHelper(used, '_adr', '_adr(asm, ops);');
      case 'adrp':
        return _useHelper(used, '_adrp', '_adrp(asm, ops);');
      case 'b':
        return _useHelper(used, '_b', '_b(asm, ops);');
      case 'bl':
        return _useHelper(used, '_bl', '_bl(asm, ops);');
      case 'b.cond':
        return _useHelper(used, '_bCond', '_bCond(asm, ops);');
      case 'cbz':
        return _useHelper(used, '_cb', "_cb(asm, ops, zero: true);");
      case 'cbnz':
        return _useHelper(used, '_cb', "_cb(asm, ops, zero: false);");
      case 'br':
        return _useHelper(used, '_br', '_br(asm, ops);');
      case 'blr':
        return _useHelper(used, '_blr', '_blr(asm, ops);');
      case 'ret':
        return _useHelper(used, '_ret', '_ret(asm, ops);');
      case 'ldr':
        return _useHelper(used, '_ldr', '_ldr(asm, ops);');
      case 'str':
        return _useHelper(used, '_str', '_str(asm, ops);');
      case 'ldrb':
        return _useHelper(used, '_ldrb', '_ldrb(asm, ops);');
      case 'ldrh':
        return _useHelper(used, '_ldrh', '_ldrh(asm, ops);');
      case 'ldrsb':
        return _useHelper(used, '_ldrsb', '_ldrsb(asm, ops);');
      case 'ldrsh':
        return _useHelper(used, '_ldrsh', '_ldrsh(asm, ops);');
      case 'ldrsw':
        return _useHelper(used, '_ldrsw', '_ldrsw(asm, ops);');
      case 'strb':
        return _useHelper(used, '_strb', '_strb(asm, ops);');
      case 'strh':
        return _useHelper(used, '_strh', '_strh(asm, ops);');
      case 'ldur':
        return _useHelper(used, '_ldur', '_ldur(asm, ops);');
      case 'stur':
        return _useHelper(used, '_stur', '_stur(asm, ops);');
      case 'ldp':
        return _useHelper(used, '_ldp', '_ldp(asm, ops);');
      case 'stp':
        return _useHelper(used, '_stp', '_stp(asm, ops);');
      case 'mul':
        return _useHelper(used, '_mul', '_mul(asm, ops);');
      case 'madd':
        return _useHelper(used, '_madd', '_madd(asm, ops);');
      case 'msub':
        return _useHelper(used, '_msub', '_msub(asm, ops);');
      case 'sdiv':
        return _useHelper(used, '_ternaryReg',
            "_ternaryReg(asm, ops, (rd, rn, rm) => asm.sdiv(rd, rn, rm));");
      case 'udiv':
        return _useHelper(used, '_ternaryReg',
            "_ternaryReg(asm, ops, (rd, rn, rm) => asm.udiv(rd, rn, rm));");
      case 'nop':
        return 'if (ops.isEmpty) asm.nop();';
      case 'brk':
        return 'if (ops.length == 1 && ops[0] is int) asm.brk(ops[0] as int);';
      case 'svc':
        return 'if (ops.length == 1 && ops[0] is int) asm.svc(ops[0] as int);';
      case 'fadd':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fadd(rd, rn, rm));");
      case 'fsub':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fsub(rd, rn, rm));");
      case 'fmul':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fmul(rd, rn, rm));");
      case 'fdiv':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fdiv(rd, rn, rm));");
      // FP additional instructions
      case 'fneg':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.fneg(rd, rn));");
      case 'fabs':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.fabs(rd, rn));");
      case 'fsqrt':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.fsqrt(rd, rn));");
      case 'fcmp':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rn, rm) => asm.fcmp(rn, rm));");
      case 'fcsel':
        return _useHelper(used, '_fcsel', "_fcsel(asm, ops);");
      // NEON integer additional
      case 'neg':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.neg(rd, rn));");
      case 'mvn':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.mvn(rd, rn));");
      case 'abs':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.abs(rd, rn));");
      case 'cls':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.cls(rd, rn));");
      case 'clz':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.clz(rd, rn));");
      case 'cnt':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.cnt(rd, rn));");
      case 'rev16':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.rev16(rd, rn));");
      case 'rev32':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.rev32(rd, rn));");
      case 'rev64':
        return _useHelper(
            used, '_vec2', "_vec2(asm, ops, (rd, rn) => asm.rev64(rd, rn));");
      // NEON FP vector
      case 'faddp':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.faddp(rd, rn, rm));");
      case 'fmaxnm':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fmaxnmVec(rd, rn, rm));");
      case 'fminnm':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fminnmVec(rd, rn, rm));");
      case 'fmax':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fmaxVec(rd, rn, rm));");
      case 'fmin':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.fminVec(rd, rn, rm));");
      // Vector moves
      case 'dup':
        return _useHelper(used, '_dup', "_dup(asm, ops);");
      case 'ins':
        return _useHelper(used, '_ins', "_ins(asm, ops);");
      case 'umov':
        return _useHelper(used, '_umov', "_umov(asm, ops);");
      case 'smov':
        return _useHelper(used, '_smov', "_smov(asm, ops);");
      // Bit manipulation
      case 'bic':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.bic(rd, rn, rm));");
      case 'orn':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.orn(rd, rn, rm));");
      case 'bif':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.bif(rd, rn, rm));");
      case 'bit':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.bit(rd, rn, rm));");
      case 'bsl':
        return _useHelper(used, '_vec3',
            "_vec3(asm, ops, (rd, rn, rm) => asm.bsl(rd, rn, rm));");
      default:
        return '// unsupported';
    }
  }

  String _useHelper(Set<String> used, String helper, String code) {
    used.add(helper);
    return code;
  }

  String _helpers(Set<String> used) {
    final helpers = <String, String>{
      '_add': '''
void _add(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.add(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.addVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  } else if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.addImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_adds': '''
void _adds(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.addsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_sub': '''
void _sub(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.sub(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.subVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  } else if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.subImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_subs': '''
void _subs(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.subsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_and': '''
void _and(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.and(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.andVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}
''',
      '_orr': '''
void _orr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.orr(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.orrVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}
''',
      '_eor': '''
void _eor(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.eor(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.eorVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}
''',
      '_shift': '''
void _shift(A64Assembler asm, List<Object> ops, A64Shift shift) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    final dst = ops[0] as A64Gp;
    final src = ops[1] as A64Gp;
    final imm = ops[2] as int;
    final zr = dst.is64Bit ? xzr : wzr;
    if (shift == A64Shift.lsl) {
      asm.orr(dst, zr, src, shift: shift, amount: imm);
    } else {
      asm.eor(dst, zr, src, shift: shift, amount: imm);
    }
  }
}
''',
      '_cmp': '''
void _cmp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    asm.cmp(ops[0] as A64Gp, ops[1] as A64Gp);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.cmpImm(ops[0] as A64Gp, ops[1] as int);
  }
}
''',
      '_cmn': '''
void _cmn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.cmnImm(ops[0] as A64Gp, ops[1] as int);
  }
}
''',
      '_mov': '''
void _mov(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.movImm64(ops[0] as A64Gp, ops[1] as int);
  }
}
''',
      '_movz': '''
void _movz(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movz(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}
''',
      '_movn': '''
void _movn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movn(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}
''',
      '_movk': '''
void _movk(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movk(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}
''',
      '_adr': '''
void _adr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.adr(ops[0] as A64Gp, ops[1] as int);
  }
}
''',
      '_adrp': '''
void _adrp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.adrp(ops[0] as A64Gp, ops[1] as int);
  }
}
''',
      '_b': '''
void _b(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.b(ops[0] as Label);
  }
}
''',
      '_bl': '''
void _bl(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.bl(ops[0] as Label);
  }
}
''',
      '_bCond': '''
void _bCond(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Cond && ops[1] is Label) {
    asm.bCond(ops[0] as A64Cond, ops[1] as Label);
  }
}
''',
      '_cb': '''
void _cb(A64Assembler asm, List<Object> ops, {required bool zero}) {
  if (ops.length != 2) return;
  final rt = ops[0];
  final lbl = ops[1];
  if (rt is A64Gp && lbl is Label) {
    if (zero) {
      asm.cbz(rt, lbl);
    } else {
      asm.cbnz(rt, lbl);
    }
  }
}
''',
      '_br': '''
void _br(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is A64Gp) {
    asm.br(ops[0] as A64Gp);
  }
}
''',
      '_blr': '''
void _blr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is A64Gp) {
    asm.blr(ops[0] as A64Gp);
  }
}
''',
      '_ret': '''
void _ret(A64Assembler asm, List<Object> ops) {
  if (ops.isEmpty) {
    asm.ret();
  } else if (ops.length == 1 && ops[0] is A64Gp) {
    asm.ret(ops[0] as A64Gp);
  }
}
''',
      '_ldr': '''
void _ldr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.ldr(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.ldrVec(ops[0] as A64Vec, base, off);
    }
  }
}
''',
      '_str': '''
void _str(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.str(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.strVec(ops[0] as A64Vec, base, off);
    }
  }
}
''',
      '_ldrb': '''
void _ldrb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_ldrh': '''
void _ldrh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_ldrsb': '''
void _ldrsb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_ldrsh': '''
void _ldrsh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_ldrsw': '''
void _ldrsw(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsw(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_strb': '''
void _strb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.strb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_strh': '''
void _strh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.strh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}
''',
      '_ldur': '''
void _ldur(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.ldur(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.ldrVecUnscaled(ops[0] as A64Vec, base, off);
    }
  }
}
''',
      '_stur': '''
void _stur(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.stur(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.strVecUnscaled(ops[0] as A64Vec, base, off);
    }
  }
}
''',
      '_ldp': '''
void _ldp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is int) {
    asm.ldp(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as int);
  }
}
''',
      '_stp': '''
void _stp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is int) {
    asm.stp(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as int);
  }
}
''',
      '_ternaryReg': '''
void _ternaryReg(A64Assembler asm, List<Object> ops,
    void Function(A64Gp, A64Gp, A64Gp) fn) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  }
}
''',
      '_mul': '''
void _mul(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.mul(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.mulVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}
''',
      '_madd': '''
void _madd(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is A64Gp) {
    asm.madd(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as A64Gp);
  }
}
''',
      '_msub': '''
void _msub(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is A64Gp) {
    asm.msub(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as A64Gp);
  }
}
''',
      '_vec3': '''
void _vec3(A64Assembler asm, List<Object> ops,
    void Function(A64Vec, A64Vec, A64Vec) fn) {
  if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}
''',
      '_vec2': '''
void _vec2(A64Assembler asm, List<Object> ops,
    void Function(A64Vec, A64Vec) fn) {
  if (ops.length == 2 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec);
  }
}
''',
      '_fcsel': '''
void _fcsel(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec &&
      ops[3] is A64Cond) {
    asm.fcsel(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec, ops[3] as A64Cond);
  }
}
''',
      '_dup': '''
void _dup(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is int) {
    asm.dup(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as int);
  }
}
''',
      '_ins': '''
void _ins(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&ops[0] is A64Vec && ops[1] is int && ops[2] is A64Vec && ops[3] is int) {
      asm.ins(ops[0] as A64Vec, ops[1] as int, ops[2] as A64Vec, ops[3] as int);
  }
}
''',
      '_umov': '''
void _umov(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Vec && ops[2] is int) {
      asm.umov(ops[0] as A64Gp, ops[1] as A64Vec, ops[2] as int);
  }
}
''',
      '_smov': '''
void _smov(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Vec && ops[2] is int) {
      asm.smov(ops[0] as A64Gp, ops[1] as A64Vec, ops[2] as int);
  }
}
''',
    };

    final ordered = [
      '_add',
      '_adds',
      '_sub',
      '_subs',
      '_and',
      '_orr',
      '_eor',
      '_shift',
      '_cmp',
      '_cmn',
      '_mov',
      '_movz',
      '_movn',
      '_movk',
      '_adr',
      '_adrp',
      '_b',
      '_bl',
      '_bCond',
      '_cb',
      '_br',
      '_blr',
      '_ret',
      '_ldr',
      '_str',
      '_ldrb',
      '_ldrh',
      '_ldrsb',
      '_ldrsh',
      '_ldrsw',
      '_strb',
      '_strh',
      '_ldur',
      '_stur',
      '_ldp',
      '_stp',
      '_ternaryReg',
      '_mul',
      '_madd',
      '_msub',
      '_vec3',
      '_vec2',
      '_fcsel',
      '_dup',
      '_ins',
      '_umov',
      '_smov',
    ];

    final buf = StringBuffer();
    for (final name in ordered) {
      if (used.contains(name)) {
        buf.writeln(helpers[name]);
      }
    }
    return buf.toString();
  }
}
