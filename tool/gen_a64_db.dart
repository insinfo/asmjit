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
    };

    final sorted = _instructions.values
        .where((i) => supported.contains(i.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final buf = StringBuffer();
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
    buf.writeln('void a64Dispatch(A64Assembler asm, int instId, List<Object> ops) {');
    buf.writeln('  switch (instId) {');
    for (final inst in sorted) {
      final cname = _capitalize(_toConstName(inst.name));
      buf.writeln('    case A64InstId.k$cname:');
      buf.writeln('      ${_dispatchCall(inst.name)}');
      buf.writeln('      break;');
    }
    buf.writeln('    default:');
    buf.writeln('      break;');
    buf.writeln('  }');
    buf.writeln('}');
    buf.writeln('');
    buf.writeln(_helpers());

    final out = File(outputPath);
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(buf.toString());
    print('Generated dispatcher at $outputPath');
  }

  String _dispatchCall(String name) {
    switch (name) {
      case 'add':
        return '_add(asm, ops);';
      case 'adds':
        return '_adds(asm, ops);';
      case 'sub':
        return '_sub(asm, ops);';
      case 'subs':
        return '_subs(asm, ops);';
      case 'and':
        return "_binaryReg(asm, ops, (rd, rn, rm) => asm.and(rd, rn, rm));";
      case 'orr':
        return "_binaryReg(asm, ops, (rd, rn, rm) => asm.orr(rd, rn, rm));";
      case 'eor':
        return "_binaryReg(asm, ops, (rd, rn, rm) => asm.eor(rd, rn, rm));";
      case 'lsl':
        return '_shift(asm, ops, A64Shift.lsl);';
      case 'lsr':
        return '_shift(asm, ops, A64Shift.lsr);';
      case 'asr':
        return '_shift(asm, ops, A64Shift.asr);';
      case 'cmp':
        return '_cmp(asm, ops);';
      case 'cmn':
        return '_cmn(asm, ops);';
      case 'mov':
        return '_mov(asm, ops);';
      case 'movz':
        return '_movz(asm, ops);';
      case 'movn':
        return '_movn(asm, ops);';
      case 'movk':
        return '_movk(asm, ops);';
      case 'adr':
        return '_adr(asm, ops);';
      case 'adrp':
        return '_adrp(asm, ops);';
      case 'b':
        return '_b(asm, ops);';
      case 'bl':
        return '_bl(asm, ops);';
      case 'b.cond':
        return '_bCond(asm, ops);';
      case 'cbz':
        return "_cb(asm, ops, zero: true);";
      case 'cbnz':
        return "_cb(asm, ops, zero: false);";
      case 'br':
        return '_br(asm, ops);';
      case 'blr':
        return '_blr(asm, ops);';
      case 'ret':
        return '_ret(asm, ops);';
      case 'ldr':
        return '_ldr(asm, ops);';
      case 'str':
        return '_str(asm, ops);';
      case 'ldrb':
        return '_ldrb(asm, ops);';
      case 'ldrh':
        return '_ldrh(asm, ops);';
      case 'ldrsb':
        return '_ldrsb(asm, ops);';
      case 'ldrsh':
        return '_ldrsh(asm, ops);';
      case 'ldrsw':
        return '_ldrsw(asm, ops);';
      case 'strb':
        return '_strb(asm, ops);';
      case 'strh':
        return '_strh(asm, ops);';
      case 'ldp':
        return '_ldp(asm, ops);';
      case 'stp':
        return '_stp(asm, ops);';
      case 'mul':
        return "_ternaryReg(asm, ops, (rd, rn, rm) => asm.mul(rd, rn, rm));";
      case 'madd':
        return '_madd(asm, ops);';
      case 'msub':
        return '_msub(asm, ops);';
      case 'sdiv':
        return "_ternaryReg(asm, ops, (rd, rn, rm) => asm.sdiv(rd, rn, rm));";
      case 'udiv':
        return "_ternaryReg(asm, ops, (rd, rn, rm) => asm.udiv(rd, rn, rm));";
      case 'nop':
        return 'if (ops.isEmpty) asm.nop();';
      case 'brk':
        return 'if (ops.length == 1 && ops[0] is int) asm.brk(ops[0] as int);';
      case 'svc':
        return 'if (ops.length == 1 && ops[0] is int) asm.svc(ops[0] as int);';
      case 'fadd':
        return "_vec3(asm, ops, (rd, rn, rm) => asm.fadd(rd, rn, rm));";
      case 'fsub':
        return "_vec3(asm, ops, (rd, rn, rm) => asm.fsub(rd, rn, rm));";
      case 'fmul':
        return "_vec3(asm, ops, (rd, rn, rm) => asm.fmul(rd, rn, rm));";
      case 'fdiv':
        return "_vec3(asm, ops, (rd, rn, rm) => asm.fdiv(rd, rn, rm));";
      default:
        return '// unsupported';
    }
  }

  String _helpers() => '''
void _add(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.add(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.addImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _adds(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.addsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _sub(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    asm.sub(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.subImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _subs(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.subsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _binaryReg(A64Assembler asm, List<Object> ops,
    void Function(A64Gp, A64Gp, A64Gp) fn) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  }
}

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

void _cmp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    asm.cmp(ops[0] as A64Gp, ops[1] as A64Gp);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.cmpImm(ops[0] as A64Gp, ops[1] as int);
  }
}

void _cmn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.cmnImm(ops[0] as A64Gp, ops[1] as int);
  }
}

void _mov(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.movImm64(ops[0] as A64Gp, ops[1] as int);
  }
}

void _movz(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movz(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}

void _movn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movn(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}

void _movk(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movk(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}

void _adr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.adr(ops[0] as A64Gp, ops[1] as int);
  }
}

void _adrp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.adrp(ops[0] as A64Gp, ops[1] as int);
  }
}

void _b(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.b(ops[0] as Label);
  }
}

void _bl(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.bl(ops[0] as Label);
  }
}

void _bCond(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Cond && ops[1] is Label) {
    asm.bCond(ops[0] as A64Cond, ops[1] as Label);
  }
}

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

void _br(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is A64Gp) {
    asm.br(ops[0] as A64Gp);
  }
}

void _blr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is A64Gp) {
    asm.blr(ops[0] as A64Gp);
  }
}

void _ret(A64Assembler asm, List<Object> ops) {
  if (ops.isEmpty) {
    asm.ret();
  } else if (ops.length == 1 && ops[0] is A64Gp) {
    asm.ret(ops[0] as A64Gp);
  }
}

void _ldr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldr(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _str(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.str(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _ldrb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _ldrh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _ldrsb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _ldrsh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _ldrsw(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsw(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _strb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.strb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _strh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.strh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _ldp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is int) {
    asm.ldp(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as int);
  }
}

void _stp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is int) {
    asm.stp(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as int);
  }
}

void _ternaryReg(A64Assembler asm, List<Object> ops,
    void Function(A64Gp, A64Gp, A64Gp) fn) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is A64Gp) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  }
}

void _madd(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is A64Gp) {
    asm.madd(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as A64Gp);
  }
}

void _msub(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is A64Gp) {
    asm.msub(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as A64Gp);
  }
}

void _vec3(A64Assembler asm, List<Object> ops,
    void Function(A64Vec, A64Vec, A64Vec) fn) {
  if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}
''';
}
