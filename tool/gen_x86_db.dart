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

/// Entry point kept for CLI usage.
Future<void> main(List<String> args) async {
  final jsonPath = args.isNotEmpty ? args[0] : 'assets/db/isa_x86.json';
  await generateX86Db(
    jsonPath: jsonPath,
    instOutputPath: 'lib/src/asmjit/x86/x86_inst_db.g.dart',
    dispatcherOutputPath: 'lib/src/asmjit/x86/x86_dispatcher.g.dart',
  );
}

/// Port de geração da base x86: IDs + dispatcher estático (switch é ~3x mais
/// rápido que Map/List conforme serializer_benchmark).
/// Os corpos do dispatcher são gerados para o conjunto de instruções que o
/// assembler já expõe (mov/aritmética/shifts/jumps/cond/SIMD).
Future<void> generateX86Db({
  String jsonPath = 'assets/db/isa_x86.json',
  String instOutputPath = 'lib/src/asmjit/x86/x86_inst_db.g.dart',
  String dispatcherOutputPath = 'lib/src/asmjit/x86/x86_dispatcher.g.dart',
}) async {
  print('=== AsmJit x86 Instruction DB Generator ===');
  print('Input: $jsonPath');
  print('Inst Output: $instOutputPath');
  print('Dispatcher Output: $dispatcherOutputPath');
  print('');

  final generator = X86DbGenerator();
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

  void generateDispatcher(String outputPath) {
    final supported = <String>{
      'mov',
      'add',
      'sub',
      'and',
      'or',
      'xor',
      'cmp',
      'test',
      'lea',
      'imul',
      'inc',
      'dec',
      'neg',
      'not',
      'shl',
      'shr',
      'sar',
      'rol',
      'ror',
      'push',
      'pop',
      'jmp',
      'call',
      'ret',
      // jcc/setcc/cmovcc groups
      'jo',
      'jno',
      'jb',
      'jnb',
      'jz',
      'jnz',
      'jbe',
      'jnbe',
      'js',
      'jns',
      'jp',
      'jnp',
      'jl',
      'jnl',
      'jle',
      'jnle',
      'seto',
      'setno',
      'setb',
      'setnb',
      'setz',
      'setnz',
      'setbe',
      'setnbe',
      'sets',
      'setns',
      'setp',
      'setnp',
      'setl',
      'setnl',
      'setle',
      'setnle',
      'cmovo',
      'cmovno',
      'cmovb',
      'cmovnb',
      'cmovz',
      'cmovnz',
      'cmovbe',
      'cmovnbe',
      'cmovs',
      'cmovns',
      'cmovp',
      'cmovnp',
      'cmovl',
      'cmovnl',
      'cmovle',
      'cmovnle',
      // SIMD subset
      'movd',
      'movq',
      'movdqu',
      'paddd',
      'paddq',
      'paddb',
      'paddw',
      'pmullw',
      'psubd',
      'psubq',
      'psubb',
      'psubw',
      'pslld',
      'psrld',
      'pcmpeqd',
      'pshufd',
      'pand',
      'por',
      'pxor',
      'addss',
      'subss',
      'mulss',
      'divss',
      'sqrtss',
      'addsd',
      'subsd',
      'mulsd',
      'divsd',
      'sqrtsd',
      'minps',
      'maxps',
      'minpd',
      'maxpd',
      'sqrtps',
      'sqrtpd',
      'rsqrtps',
      'rcpps',
      'comiss',
      'ucomiss',
      'comisd',
      'ucomisd',
      'cvtsi2sd',
      'cvttsd2si',
      'cvtsi2ss',
      'cvttss2si',
      'cvtsd2ss',
      'cvtss2sd',
      'movss',
      'movsd',
      'movups',
      'movaps',
      'kmovw',
      'kmovd',
      'kmovq',
      'addps',
      'addpd',
      'subps',
      'subpd',
      'mulps',
      'mulpd',
      'divps',
      'divpd',
      'xorps',
      'xorpd',
      'vmovaps',
      'vmovups',
      'vaddps',
      'vaddpd',
      'vsubps',
      'vsubpd',
      'vmulps',
      'vmulpd',
      'vdivps',
      'vdivpd',
      'vxorps',
      'vxorpd',
      'vpxor',
      'vpord',
      'vporq',
      'vpxord',
      'vpxorq',
      'vpandd',
      'vpandq',
      'vaddsd',
      'vsubsd',
      'vmulsd',
      'vdivsd',
      'vfmadd132sd',
      'vfmadd231sd',
      'vminps',
      'vminpd',
      'vmaxps',
      'vmaxpd',
      'vsqrtps',
      'vsqrtpd',
      'vrsqrtps',
      'vrcpps',
      'vpbroadcastb',
      'vpbroadcastw',
      'vpbroadcastd',
      'vpbroadcastq',
      'cvtdq2ps',
      'cvtps2dq',
      'cvttps2dq',
      'cdq',
      'cqo',
      'idiv',
      'div',
      'mul',
    };

    final buffer = StringBuffer();
    buffer.writeln('// GENERATED FILE - DO NOT EDIT');
    buffer.writeln('// Generated by tool/gen_x86_db.dart');
    buffer.writeln('');
    buffer.writeln("import 'x86_assembler.dart';");
    buffer.writeln("import 'x86_inst_db.g.dart';");
    buffer.writeln("import 'x86.dart';");
    buffer.writeln("import 'x86_operands.dart';");
    buffer.writeln("import 'x86_encoder.dart' show X86Cond;");
    buffer.writeln("import 'x86_simd.dart';");
    buffer.writeln("import '../core/labels.dart';");
    buffer.writeln("import '../core/operand.dart' show Imm, LabelOp;");
    buffer.writeln('');
    buffer.writeln(
        '/// Dispatches instruction ID to Assembler method for implemented ops.');
    buffer.writeln(
        '/// Unsupported IDs are ignored (no-op), keeping behavior compatible with older stubs.');
    buffer.writeln(
        'void x86Dispatch(X86Assembler asm, int instId, List<Object> ops) {');
    buffer.writeln('  switch (instId) {');

    final sorted = _instructions.values
        .where((i) => supported.contains(i.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final inst in sorted) {
      final constName = _capitalize(_toConstName(inst.name));
      buffer.writeln('    case X86InstId.k$constName:');
      buffer.writeln('      ${_dispatchCall(inst.name)}');
      buffer.writeln('      break;');
    }

    buffer.writeln('    default:');
    buffer.writeln('      break;');
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln(_helpers());

    final outFile = File(outputPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(buffer.toString());
    print('Generated Dispatcher at $outputPath');
  }

  String _dispatchCall(String name) {
    switch (name) {
      case 'mov':
        return '_mov(asm, ops);';
      case 'add':
        return '_binary(asm, ops, (a, b) => asm.addRR(a, b), (a, imm) => asm.addRI(a, imm));';
      case 'sub':
        return '_binary(asm, ops, (a, b) => asm.subRR(a, b), (a, imm) => asm.subRI(a, imm));';
      case 'and':
        return '_binary(asm, ops, (a, b) => asm.andRR(a, b), (a, imm) => asm.andRI(a, imm));';
      case 'or':
        return '_binary(asm, ops, (a, b) => asm.orRR(a, b), (a, imm) => asm.orRI(a, imm));';
      case 'xor':
        return '_binary(asm, ops, (a, b) => asm.xorRR(a, b), (a, imm) => asm.xorRI(a, imm));';
      case 'cmp':
        return '_binary(asm, ops, (a, b) => asm.cmpRR(a, b), (a, imm) => asm.cmpRI(a, imm));';
      case 'test':
        return '_binary(asm, ops, (a, b) => asm.testRR(a, b), (a, imm) => asm.testRI(a, imm));';
      case 'lea':
        return "if (ops.length == 2 && ops[0] is X86Gp && ops[1] is X86Mem) asm.lea(ops[0] as X86Gp, ops[1] as X86Mem);";
      case 'imul':
        return '_imul(asm, ops);';
      case 'inc':
        return '_unary(asm, ops, (r) => asm.inc(r));';
      case 'dec':
        return '_unary(asm, ops, (r) => asm.dec(r));';
      case 'neg':
        return '_unary(asm, ops, (r) => asm.neg(r));';
      case 'not':
        return '_unary(asm, ops, (r) => asm.not(r));';
      case 'shl':
        return '_shift(asm, ops, (r, imm) => asm.shlRI(r, imm), (r) => asm.shlRCl(r));';
      case 'shr':
        return '_shift(asm, ops, (r, imm) => asm.shrRI(r, imm), (r) => asm.shrRCl(r));';
      case 'sar':
        return '_shift(asm, ops, (r, imm) => asm.sarRI(r, imm), (r) => asm.sarRCl(r));';
      case 'rol':
        return '_shift(asm, ops, (r, imm) => asm.rolRI(r, imm), null);';
      case 'ror':
        return '_shift(asm, ops, (r, imm) => asm.rorRI(r, imm), null);';
      case 'push':
        return '_push(asm, ops);';
      case 'pop':
        return '_pop(asm, ops);';
      case 'jmp':
        return '_jmp(asm, ops);';
      case 'call':
        return '_call(asm, ops);';
      case 'ret':
        return '_ret(asm, ops);';
      case 'jo':
      case 'jno':
      case 'jb':
      case 'jnb':
      case 'jz':
      case 'jnz':
      case 'jbe':
      case 'jnbe':
      case 'js':
      case 'jns':
      case 'jp':
      case 'jnp':
      case 'jl':
      case 'jnl':
      case 'jle':
      case 'jnle':
        return '_jcc(asm, instId, ops);';
      case 'seto':
      case 'setno':
      case 'setb':
      case 'setnb':
      case 'setz':
      case 'setnz':
      case 'setbe':
      case 'setnbe':
      case 'sets':
      case 'setns':
      case 'setp':
      case 'setnp':
      case 'setl':
      case 'setnl':
      case 'setle':
      case 'setnle':
        return '_setcc(asm, instId, ops);';
      case 'cmovo':
      case 'cmovno':
      case 'cmovb':
      case 'cmovnb':
      case 'cmovz':
      case 'cmovnz':
      case 'cmovbe':
      case 'cmovnbe':
      case 'cmovs':
      case 'cmovns':
      case 'cmovp':
      case 'cmovnp':
      case 'cmovl':
      case 'cmovnl':
      case 'cmovle':
      case 'cmovnle':
        return '_cmovcc(asm, instId, ops);';
      case 'movss':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.movssXM(d, s) : asm.movssXX(d, s as X86Xmm), memXmm: (m, s) => asm.movssMX(m, s));';
      case 'movsd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.movsdXM(d, s) : asm.movsdXX(d, s as X86Xmm), memXmm: (m, s) => asm.movsdMX(m, s));';
      case 'movd':
        return '_movd(asm, ops);';
      case 'movdqu':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.movdquXM(d, s) : asm.movdquXX(d, s as X86Xmm), memXmm: (m, s) => asm.movdquMX(m, s));';
      case 'movq':
        return '_movq(asm, ops);';
      case 'kmovw':
        return '_kmovw(asm, ops);';
      case 'kmovd':
        return '_kmovd(asm, ops);';
      case 'kmovq':
        return '_kmovq(asm, ops);';
      case 'movups':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.movupsXM(d, s) : asm.movupsXX(d, s as X86Xmm), memXmm: (m, s) => asm.movupsMX(m, s));';
      case 'movaps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.movapsXM(d, s) : asm.movapsXX(d, s as X86Xmm), memXmm: (m, s) => asm.movapsMX(m, s));';
      case 'addss':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.addssXX(d, s); });';
      case 'subss':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.subssXX(d, s); });';
      case 'mulss':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.mulssXX(d, s); });';
      case 'divss':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.divssXX(d, s); });';
      case 'sqrtss':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.sqrtssXX(d, s); });';
      case 'addsd':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.addsdXX(d, s); });';
      case 'subsd':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.subsdXX(d, s); });';
      case 'mulsd':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.mulsdXX(d, s); });';
      case 'divsd':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.divsdXX(d, s); });';
      case 'sqrtsd':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.sqrtsdXX(d, s); });';
      case 'comiss':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.comissXX(d, s); });';
      case 'ucomiss':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.ucomissXX(d, s); });';
      case 'comisd':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.comisdXX(d, s); });';
      case 'ucomisd':
        return '_simd2(asm, ops, xmm: (d, s) { if (s is X86Xmm) asm.ucomisdXX(d, s); });';
      case 'cvtsi2sd':
        return 'if (ops.length == 2 && ops[0] is X86Xmm && ops[1] is X86Gp) asm.cvtsi2sdXR(ops[0] as X86Xmm, ops[1] as X86Gp);';
      case 'cvttsd2si':
        return 'if (ops.length == 2 && ops[0] is X86Gp && ops[1] is X86Xmm) asm.cvttsd2siRX(ops[0] as X86Gp, ops[1] as X86Xmm);';
      case 'cvtsi2ss':
        return 'if (ops.length == 2 && ops[0] is X86Xmm && ops[1] is X86Gp) asm.cvtsi2ssXR(ops[0] as X86Xmm, ops[1] as X86Gp);';
      case 'cvttss2si':
        return 'if (ops.length == 2 && ops[0] is X86Gp && ops[1] is X86Xmm) asm.cvttss2siRX(ops[0] as X86Gp, ops[1] as X86Xmm);';
      case 'cvtsd2ss':
        return 'if (ops.length == 2 && ops[0] is X86Xmm && ops[1] is X86Xmm) asm.cvtsd2ssXX(ops[0] as X86Xmm, ops[1] as X86Xmm);';
      case 'cvtss2sd':
        return 'if (ops.length == 2 && ops[0] is X86Xmm && ops[1] is X86Xmm) asm.cvtss2sdXX(ops[0] as X86Xmm, ops[1] as X86Xmm);';
      case 'addps':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => asm.vaddpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => asm.vaddpsYYY(d, s1, s2 as X86Ymm), zmm: (d, s1, s2) => asm.vaddpsZmm(d, s1, s2 as X86Zmm));';
      case 'addpd':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => asm.vaddpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => asm.vaddpdYYY(d, s1, s2 as X86Ymm), zmm: (d, s1, s2) => asm.vaddpdZmm(d, s1, s2 as X86Zmm));';
      case 'subps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.subpsXM(d, s) : asm.subps(d, s as X86Xmm));';
      case 'subpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.subpdXM(d, s) : asm.subpd(d, s as X86Xmm));';
      case 'mulps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.mulpsXM(d, s) : asm.mulps(d, s as X86Xmm));';
      case 'mulpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.mulpdXM(d, s) : asm.mulpd(d, s as X86Xmm));';
      case 'divps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.divpsXM(d, s) : asm.divps(d, s as X86Xmm));';
      case 'divpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.divpdXM(d, s) : asm.divpd(d, s as X86Xmm));';
      case 'xorps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.xorpsXM(d, s) : asm.xorps(d, s as X86Xmm));';
      case 'xorpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.xorpdXM(d, s) : asm.xorpd(d, s as X86Xmm));';
      case 'pxor':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.pxorXM(d, s) : asm.pxor(d, s as X86Xmm));';
      case 'por':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.porXM(d, s) : asm.porXX(d, s as X86Xmm));';
      case 'pand':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.pandXM(d, s) : asm.pandXX(d, s as X86Xmm));';
      case 'paddb':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.paddbXM(d, s) : asm.paddbXX(d, s as X86Xmm));';
      case 'paddw':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.paddwXM(d, s) : asm.paddwXX(d, s as X86Xmm));';
      case 'paddd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.padddXM(d, s) : asm.padddXX(d, s as X86Xmm));';
      case 'pmullw':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.pmullwXM(d, s) : asm.pmullwXX(d, s as X86Xmm));';
      case 'paddq':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.paddqXM(d, s) : asm.paddqXX(d, s as X86Xmm));';
      case 'psubb':
      case 'psubw':
      case 'psubd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.psubdXM(d, s) : asm.psubdXX(d, s as X86Xmm));';
      case 'pslld':
        return '_simd2(asm, ops, xmm: (d, s) => (s is int || s is Imm) ? asm.pslldXI(d, s is Imm ? s.value : s as int) : asm.pslldXX(d, s as X86Xmm));';
      case 'psrld':
        return '_simd2(asm, ops, xmm: (d, s) => (s is int || s is Imm) ? asm.psrldXI(d, s is Imm ? s.value : s as int) : asm.psrldXX(d, s as X86Xmm));';
      case 'pcmpeqd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.pcmpeqdXM(d, s) : asm.pcmpeqdXX(d, s as X86Xmm));';
      case 'pshufd':
        return 'if (ops.length == 3 && ops[0] is X86Xmm && ops[1] is X86Xmm && (ops[2] is int || ops[2] is Imm)) asm.pshufdXXI(ops[0] as X86Xmm, ops[1] as X86Xmm, ops[2] is Imm ? (ops[2] as Imm).value : ops[2] as int);';
      case 'vmovups':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vmovupsXM(d, s) : asm.vmovups(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vmovupsYM(d, s) : asm.vmovupsY(d, s as X86Ymm), zmm: (d, s) => s is X86Mem ? asm.vmovupsZmmMem(d, s) : asm.vmovupsZmm(d, s as X86Zmm), memXmm: (m, s) => asm.vmovupsMX(m, s), memYmm: (m, s) => asm.vmovupsMY(m, s), memZmm: (m, s) => asm.vmovupsMemZmm(m, s));';
      case 'vmovaps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vmovapsXM(d, s) : asm.vmovaps(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vmovapsYM(d, s) : asm.vmovapsY(d, s as X86Ymm), memXmm: (m, s) => asm.vmovapsMX(m, s), memYmm: (m, s) => asm.vmovapsMY(m, s));';
      case 'vaddps':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vaddpsXXM(d, s1, s2) : asm.vaddpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vaddpsYYM(d, s1, s2) : asm.vaddpsYYY(d, s1, s2 as X86Ymm));';
      case 'vaddpd':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vaddpdXXM(d, s1, s2) : asm.vaddpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vaddpdYYM(d, s1, s2) : asm.vaddpdYYY(d, s1, s2 as X86Ymm));';
      case 'vpbroadcastb':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vpbroadcastbXM(d, s) : asm.vpbroadcastbXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vpbroadcastbYM(d, s) : asm.vpbroadcastbYX(d, s as X86Xmm));';
      case 'vpbroadcastw':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vpbroadcastwXM(d, s) : asm.vpbroadcastwXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vpbroadcastwYM(d, s) : asm.vpbroadcastwYX(d, s as X86Xmm));';
      case 'vpbroadcastd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vpbroadcastdXM(d, s) : asm.vpbroadcastdXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vpbroadcastdYM(d, s) : asm.vpbroadcastdYX(d, s as X86Xmm));';
      case 'vpbroadcastq':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vpbroadcastqXM(d, s) : asm.vpbroadcastqXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vpbroadcastqYM(d, s) : asm.vpbroadcastqYX(d, s as X86Xmm));';
      case 'vsubps':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vsubpsXXM(d, s1, s2) : asm.vsubpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vsubpsYYM(d, s1, s2) : asm.vsubpsYYY(d, s1, s2 as X86Ymm));';
      case 'vsubpd':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vsubpdXXM(d, s1, s2) : asm.vsubpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vsubpdYYM(d, s1, s2) : asm.vsubpdYYY(d, s1, s2 as X86Ymm));';
      case 'vmulps':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vmulpsXXM(d, s1, s2) : asm.vmulpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vmulpsYYM(d, s1, s2) : asm.vmulpsYYY(d, s1, s2 as X86Ymm));';
      case 'vmulpd':
        return '_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vmulpdXXM(d, s1, s2) : asm.vmulpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vmulpdYYM(d, s1, s2) : asm.vmulpdYYY(d, s1, s2 as X86Ymm));';
      case 'vxorps':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vxorpsXXM(d, s1, s2) : asm.vxorpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vxorpsYYM(d, s1, s2) : asm.vxorpsYYY(d, s1, s2 as X86Ymm));";
      case 'vxorpd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vxorpdXXM(d, s1, s2) : asm.vxorpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vxorpdYYM(d, s1, s2) : asm.vxorpdYYY(d, s1, s2 as X86Ymm));";
      case 'vpxor':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vpxorXXM(d, s1, s2) : asm.vpxorXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vpxorYYM(d, s1, s2) : asm.vpxorYYY(d, s1, s2 as X86Ymm));";
      case 'vdivps':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vdivpsXXM(d, s1, s2) : asm.vdivpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vdivpsYYM(d, s1, s2) : asm.vdivpsYYY(d, s1, s2 as X86Ymm));";
      case 'vdivpd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vdivpdXXM(d, s1, s2) : asm.vdivpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vdivpdYYM(d, s1, s2) : asm.vdivpdYYY(d, s1, s2 as X86Ymm));";
      // Additional SSE packed logical operations
      case 'andps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.andpsXM(d, s) : asm.andps(d, s as X86Xmm));';
      case 'andpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.andpdXM(d, s) : asm.andpd(d, s as X86Xmm));';
      case 'orps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.orpsXM(d, s) : asm.orps(d, s as X86Xmm));';
      case 'orpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.orpdXM(d, s) : asm.orpd(d, s as X86Xmm));';
      // SSE min/max operations
      case 'minps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.minpsXM(d, s) : asm.minps(d, s as X86Xmm));';
      case 'minpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.minpdXM(d, s) : asm.minpd(d, s as X86Xmm));';
      case 'maxps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.maxpsXM(d, s) : asm.maxps(d, s as X86Xmm));';
      case 'maxpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.maxpdXM(d, s) : asm.maxpd(d, s as X86Xmm));';
      // SSE sqrt/rcp/rsqrt
      case 'sqrtps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.sqrtpsXM(d, s) : asm.sqrtps(d, s as X86Xmm));';
      case 'sqrtpd':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.sqrtpdXM(d, s) : asm.sqrtpd(d, s as X86Xmm));';
      case 'rcpps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.rcppsXM(d, s) : asm.rcpps(d, s as X86Xmm));';
      case 'rsqrtps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.rsqrtpsXM(d, s) : asm.rsqrtps(d, s as X86Xmm));';
      // AVX versions of logical operations
      case 'vandps':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vandpsXXM(d, s1, s2) : asm.vandpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vandpsYYM(d, s1, s2) : asm.vandpsYYY(d, s1, s2 as X86Ymm));";
      case 'vandpd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vandpdXXM(d, s1, s2) : asm.vandpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vandpdYYM(d, s1, s2) : asm.vandpdYYY(d, s1, s2 as X86Ymm));";
      case 'vorps':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vorpsXXM(d, s1, s2) : asm.vorpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vorpsYYM(d, s1, s2) : asm.vorpsYYY(d, s1, s2 as X86Ymm));";
      case 'vorpd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vorpdXXM(d, s1, s2) : asm.vorpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vorpdYYM(d, s1, s2) : asm.vorpdYYY(d, s1, s2 as X86Ymm));";
      case 'vpor':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vporXXM(d, s1, s2) : asm.vporXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vporYYM(d, s1, s2) : asm.vporYYY(d, s1, s2 as X86Ymm));";
      case 'vpand':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vpandXXM(d, s1, s2) : asm.vpandXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vpandYYM(d, s1, s2) : asm.vpandYYY(d, s1, s2 as X86Ymm));";
      // AVX min/max/sqrt/rcp
      case 'vminps':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vminpsXXM(d, s1, s2) : asm.vminpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vminpsYYM(d, s1, s2) : asm.vminpsYYY(d, s1, s2 as X86Ymm));";
      case 'vminpd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vminpdXXM(d, s1, s2) : asm.vminpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vminpdYYM(d, s1, s2) : asm.vminpdYYY(d, s1, s2 as X86Ymm));";
      case 'vmaxps':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vmaxpsXXM(d, s1, s2) : asm.vmaxpsXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vmaxpsYYM(d, s1, s2) : asm.vmaxpsYYY(d, s1, s2 as X86Ymm));";
      case 'vmaxpd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vmaxpdXXM(d, s1, s2) : asm.vmaxpdXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vmaxpdYYM(d, s1, s2) : asm.vmaxpdYYY(d, s1, s2 as X86Ymm));";
      case 'vsqrtps':
        return "_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vsqrtpsXM(d, s) : asm.vsqrtpsXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vsqrtpsYM(d, s) : asm.vsqrtpsYY(d, s as X86Ymm));";
      case 'vsqrtpd':
        return "_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vsqrtpdXM(d, s) : asm.vsqrtpdXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vsqrtpdYM(d, s) : asm.vsqrtpdYY(d, s as X86Ymm));";
      case 'vrsqrtps':
        return "_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vrsqrtpsXM(d, s) : asm.vrsqrtpsXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vrsqrtpsYM(d, s) : asm.vrsqrtpsYY(d, s as X86Ymm));";
      case 'vrcpps':
        return "_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.vrcppsXM(d, s) : asm.vrcppsXX(d, s as X86Xmm), ymm: (d, s) => s is X86Mem ? asm.vrcppsYM(d, s) : asm.vrcppsYY(d, s as X86Ymm));";
      // Conversion
      case 'cvtdq2ps':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.cvtdq2psXM(d, s) : asm.cvtdq2psXX(d, s as X86Xmm));';
      case 'cvtps2dq':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.cvtps2dqXM(d, s) : asm.cvtps2dqXX(d, s as X86Xmm));';
      case 'cvttps2dq':
        return '_simd2(asm, ops, xmm: (d, s) => s is X86Mem ? asm.cvttps2dqXM(d, s) : asm.cvttps2dqXX(d, s as X86Xmm));';
      // AVX arithmetic extensions
      case 'vpaddd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vpadddXXM(d, s1, s2) : asm.vpadddXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vpadddYYM(d, s1, s2) : asm.vpadddYYY(d, s1, s2 as X86Ymm));";
      case 'vpaddq':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vpaddqXXM(d, s1, s2) : asm.vpaddqXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) => s2 is X86Mem ? asm.vpaddqYYM(d, s1, s2) : asm.vpaddqYYY(d, s1, s2 as X86Ymm));";
      case 'vpmulld':
        return "_simd3(asm, ops, xmm: (d, s1, s2) => s2 is X86Mem ? asm.vpmulldXXM(d, s1, s2) : asm.vpmulldXXX(d, s1, s2 as X86Xmm), ymm: (d, s1, s2) { if (s2 is X86Mem) asm.vpmulldYYM(d, s1, s2); });";
      case 'vaddsd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) { if (s2 is X86Xmm) asm.vaddsdXXX(d, s1, s2); });";
      case 'vsubsd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) { if (s2 is X86Xmm) asm.vsubsdXXX(d, s1, s2); });";
      case 'vmulsd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) { if (s2 is X86Xmm) asm.vmulsdXXX(d, s1, s2); });";
      case 'vdivsd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) { if (s2 is X86Xmm) asm.vdivsdXXX(d, s1, s2); });";
      case 'vfmadd132sd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) { if (s2 is X86Xmm) asm.vfmadd132sdXXX(d, s1, s2); });";
      case 'vfmadd231sd':
        return "_simd3(asm, ops, xmm: (d, s1, s2) { if (s2 is X86Xmm) asm.vfmadd231sdXXX(d, s1, s2); });";
      case 'vzeroupper':
        return 'asm.vzeroupper();';
      case 'vpord':
        return "_simd3(asm, ops, zmm: (d, s1, s2) => asm.vpordZmm(d, s1, s2 as X86Zmm));";
      case 'vporq':
        return "_simd3(asm, ops, zmm: (d, s1, s2) => asm.vporqZmm(d, s1, s2 as X86Zmm));";
      case 'vpxord':
        return "_simd3(asm, ops, zmm: (d, s1, s2) => asm.vpxordZmm(d, s1, s2 as X86Zmm));";
      case 'vpxorq':
        return "_simd3(asm, ops, zmm: (d, s1, s2) => asm.vpxorqZmm(d, s1, s2 as X86Zmm));";
      case 'vpandd':
        return "_simd3(asm, ops, zmm: (d, s1, s2) => asm.vpanddZmm(d, s1, s2 as X86Zmm));";
      case 'vpandq':
        return "_simd3(asm, ops, zmm: (d, s1, s2) => asm.vpandqZmm(d, s1, s2 as X86Zmm));";
      case 'cdq':
        return 'asm.cdq();';
      case 'cqo':
        return 'asm.cqo();';
      case 'idiv':
        return '_unary(asm, ops, (r) => asm.idiv(r));';
      case 'div':
        return '_unary(asm, ops, (r) => asm.div(r));';
      case 'mul':
        return '_unary(asm, ops, (r) => asm.mul(r));';
      default:
        return '// unsupported';
    }
  }

  String _helpers() => '''
// Helpers
void _mov(X86Assembler asm, List<Object> ops) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86Gp && src is X86Gp) {
    asm.movRR(dst, src);
  } else if (dst is X86Gp && src is int) {
    asm.movRI64(dst, src);
  } else if (dst is X86Gp && src is X86Mem) {
    asm.movRM(dst, src);
  } else if (dst is X86Mem && src is X86Gp) {
    asm.movMR(dst, src);
  } else if (dst is X86Mem && src is int) {
    asm.movMI(dst, src);
  } else if (dst is X86Xmm && src is X86Xmm) {
    asm.movapsXX(dst, src);
  } else if (dst is X86Xmm && src is X86Mem) {
    asm.movapsXM(dst, src);
  } else if (dst is X86Mem && src is X86Xmm) {
    asm.movapsMX(dst, src);
  }
}

void _movd(X86Assembler asm, List<Object> ops) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86Xmm && src is X86Gp) {
    asm.movdXR(dst, src);
  } else if (dst is X86Gp && src is X86Xmm) {
    asm.movdRX(dst, src);
  } else if (dst is X86Xmm && src is X86Mem) {
    asm.movdXM(dst, src);
  } else if (dst is X86Mem && src is X86Xmm) {
    asm.movdMX(dst, src);
  }
}

void _movq(X86Assembler asm, List<Object> ops) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86Xmm && src is X86Gp) {
    asm.movqXR(dst, src);
  } else if (dst is X86Gp && src is X86Xmm) {
    asm.movqRX(dst, src);
  }
}

void _kmovw(X86Assembler asm, List<Object> ops) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86KReg && src is X86Gp) {
    asm.kmovwKR(dst, src);
  } else if (dst is X86Gp && src is X86KReg) {
    asm.kmovwRK(dst, src);
  }
}

void _kmovd(X86Assembler asm, List<Object> ops) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86KReg && src is X86Gp) {
    asm.kmovdKR(dst, src);
  } else if (dst is X86Gp && src is X86KReg) {
    asm.kmovdRK(dst, src);
  }
}

void _kmovq(X86Assembler asm, List<Object> ops) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86KReg && src is X86Gp) {
    asm.kmovqKR(dst, src);
  } else if (dst is X86Gp && src is X86KReg) {
    asm.kmovqRK(dst, src);
  }
}

void _binary(X86Assembler asm, List<Object> ops,
    void Function(X86Gp, X86Gp) rr, void Function(X86Gp, int) ri) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86Gp && src is X86Gp) {
    rr(dst, src);
  } else if (dst is X86Gp && src is int) {
    ri(dst, src);
  } else if (dst is X86Gp && src is Imm) {
    ri(dst, src.value);
  }
}

void _unary(X86Assembler asm, List<Object> ops, void Function(X86Gp) r) {
  if (ops.length == 1 && ops[0] is X86Gp) r(ops[0] as X86Gp);
}

void _shift(X86Assembler asm, List<Object> ops,
    void Function(X86Gp, int) ri, void Function(X86Gp)? rCl) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];
  if (dst is X86Gp && src is int) {
    ri(dst, src);
  } else if (dst is X86Gp && src is X86Gp && src.id == 1 && rCl != null) {
    rCl(dst);
  }
}

void _imul(X86Assembler asm, List<Object> ops) {
  if (ops.length == 2) {
    final dst = ops[0];
    final src = ops[1];
    if (dst is X86Gp && src is X86Gp) {
      asm.imulRR(dst, src);
    } else if (dst is X86Gp && src is int) {
      asm.imulRI(dst, src);
    } else if (dst is X86Gp && src is Imm) {
      asm.imulRI(dst, src.value);
    }
  } else if (ops.length == 3) {
    final dst = ops[0];
    final src = ops[1];
    final imm = ops[2];
    if (dst is X86Gp && src is X86Gp && imm is int) {
      asm.imulRRI(dst, src, imm);
    } else if (dst is X86Gp && src is X86Gp && imm is Imm) {
      asm.imulRRI(dst, src, imm.value);
    }
  }
}

void _push(X86Assembler asm, List<Object> ops) {
  if (ops.length != 1) return;
  final op = ops[0];
  if (op is X86Gp) {
    asm.push(op);
  } else if (op is int) {
    asm.pushImm32(op);
  } else if (op is Imm) {
    asm.pushImm32(op.value);
  }
}

void _pop(X86Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is X86Gp) {
    asm.pop(ops[0] as X86Gp);
  }
}

void _jmp(X86Assembler asm, List<Object> ops) {
  if (ops.length != 1) return;
  final op = ops[0];
  if (op is Label) {
    asm.jmp(op);
  } else if (op is LabelOp) {
    asm.jmp(op.label);
  } else if (op is X86Gp) {
    asm.jmpR(op);
  } else if (op is int) {
    asm.jmpRel(op);
  } else if (op is Imm) {
    asm.jmpRel(op.value);
  }
}

void _call(X86Assembler asm, List<Object> ops) {
  if (ops.length != 1) return;
  final op = ops[0];
  if (op is Label) {
    asm.call(op);
  } else if (op is LabelOp) {
    asm.call(op.label);
  } else if (op is X86Gp) {
    asm.callR(op);
  } else if (op is int) {
    asm.callRel(op);
  } else if (op is Imm) {
    asm.callRel(op.value);
  }
}

void _ret(X86Assembler asm, List<Object> ops) {
  if (ops.isEmpty) {
    asm.ret();
  } else if (ops.length == 1 && ops[0] is int) {
    asm.retImm(ops[0] as int);
  }
}

void _jcc(X86Assembler asm, int instId, List<Object> ops) {
  if (ops.isEmpty) return;
  final cond = _condFromInst(instId);
  if (cond == null) return;
  final op = ops[0];
  if (op is Label) {
    asm.jcc(cond, op);
  } else if (op is LabelOp) {
    asm.jcc(cond, op.label);
  } else if (op is int) {
    asm.jccRel(cond, op);
  } else if (op is Imm) {
    asm.jccRel(cond, op.value);
  }
}

void _setcc(X86Assembler asm, int instId, List<Object> ops) {
  if (ops.length == 1 && ops[0] is X86Gp) {
    final cond = _condFromInst(instId);
    if (cond != null) asm.setcc(cond, ops[0] as X86Gp);
  }
}

void _cmovcc(X86Assembler asm, int instId, List<Object> ops) {
  if (ops.length == 2 && ops[0] is X86Gp && ops[1] is X86Gp) {
    final cond = _condFromInst(instId);
    if (cond != null) asm.cmovcc(cond, ops[0] as X86Gp, ops[1] as X86Gp);
  }
}

X86Cond? _condFromInst(int instId) {
  switch (instId) {
    case X86InstId.kJo:
    case X86InstId.kSeto:
    case X86InstId.kCmovo:
      return X86Cond.o;
    case X86InstId.kJno:
    case X86InstId.kSetno:
    case X86InstId.kCmovno:
      return X86Cond.no;
    case X86InstId.kJb:
    case X86InstId.kSetb:
    case X86InstId.kCmovb:
      return X86Cond.b;
    case X86InstId.kJnb:
    case X86InstId.kSetnb:
    case X86InstId.kCmovnb:
      return X86Cond.nb;
    case X86InstId.kJz:
    case X86InstId.kSetz:
    case X86InstId.kCmovz:
      return X86Cond.e;
    case X86InstId.kJnz:
    case X86InstId.kSetnz:
    case X86InstId.kCmovnz:
      return X86Cond.ne;
    case X86InstId.kJbe:
    case X86InstId.kSetbe:
    case X86InstId.kCmovbe:
      return X86Cond.be;
    case X86InstId.kJnbe:
    case X86InstId.kSetnbe:
    case X86InstId.kCmovnbe:
      return X86Cond.a;
    case X86InstId.kJs:
    case X86InstId.kSets:
    case X86InstId.kCmovs:
      return X86Cond.s;
    case X86InstId.kJns:
    case X86InstId.kSetns:
    case X86InstId.kCmovns:
      return X86Cond.ns;
    case X86InstId.kJp:
    case X86InstId.kSetp:
    case X86InstId.kCmovp:
      return X86Cond.p;
    case X86InstId.kJnp:
    case X86InstId.kSetnp:
    case X86InstId.kCmovnp:
      return X86Cond.np;
    case X86InstId.kJl:
    case X86InstId.kSetl:
    case X86InstId.kCmovl:
      return X86Cond.l;
    case X86InstId.kJnl:
    case X86InstId.kSetnl:
    case X86InstId.kCmovnl:
      return X86Cond.ge;
    case X86InstId.kJle:
    case X86InstId.kSetle:
    case X86InstId.kCmovle:
      return X86Cond.le;
    case X86InstId.kJnle:
    case X86InstId.kSetnle:
    case X86InstId.kCmovnle:
      return X86Cond.g;
    default:
      return null;
  }
}

void _simd2(
  X86Assembler asm,
  List<Object> ops, {
  void Function(X86Xmm, Object)? xmm,
  void Function(X86Ymm, Object)? ymm,
  void Function(X86Zmm, Object)? zmm,
  void Function(X86Mem, X86Xmm)? memXmm,
  void Function(X86Mem, X86Ymm)? memYmm,
  void Function(X86Mem, X86Zmm)? memZmm,
}) {
  if (ops.length != 2) return;
  final dst = ops[0];
  final src = ops[1];

  if (memZmm != null && dst is X86Mem && src is X86Zmm) {
    memZmm(dst, src);
    return;
  }
  if (memYmm != null && dst is X86Mem && src is X86Ymm) {
    memYmm(dst, src);
    return;
  }
  if (memXmm != null && dst is X86Mem && src is X86Xmm) {
    memXmm(dst, src);
    return;
  }
  if (zmm != null && dst is X86Zmm) {
    zmm(dst, src);
    return;
  }
  if (ymm != null && dst is X86Ymm) {
    ymm(dst, src);
    return;
  }
  if (xmm != null && dst is X86Xmm) {
    xmm(dst, src);
  }
}

void _simd3(
  X86Assembler asm,
  List<Object> ops, {
  void Function(X86Xmm, X86Xmm, Object)? xmm,
  void Function(X86Ymm, X86Ymm, Object)? ymm,
  void Function(X86Zmm, X86Zmm, Object)? zmm,
}) {
  if (ops.length != 3) return;
  final dst = ops[0];
  final s1 = ops[1];
  final s2 = ops[2];

  if (zmm != null && dst is X86Zmm && s1 is X86Zmm) {
    zmm(dst, s1, s2);
    return;
  }
  if (ymm != null && dst is X86Ymm && s1 is X86Ymm) {
    ymm(dst, s1, s2);
    return;
  }
  if (xmm != null && dst is X86Xmm && s1 is X86Xmm) {
    xmm(dst, s1, s2);
  }
}
''';

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
