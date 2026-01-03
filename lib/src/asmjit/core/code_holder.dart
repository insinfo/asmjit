/// AsmJit Code Holder
///
/// Container for generated code, managing sections, labels, and relocations.
/// Ported from asmjit/core/codeholder.h

import 'dart:typed_data';

import 'code_buffer.dart';
import 'environment.dart';
import 'error.dart';
import 'formatter.dart';
import 'labels.dart';

/// A section of code or data.
class Section {
  /// The section name.
  final String name;

  /// The section ID.
  final int id;

  /// The code/data buffer.
  final CodeBuffer buffer;
  
  /// return buffer.bytes
  Uint8List asUint8List() {
    return buffer.bytes;
  }

  /// Relocations in this section.
  final List<Reloc> relocs = [];

  /// Section flags.
  final SectionFlags flags;

  /// Section alignment.
  final int alignment;

  Section._({
    required this.name,
    required this.id,
    required this.flags,
    this.alignment = 1,
  }) : buffer = CodeBuffer();

  /// Creates a text (code) section.
  factory Section.text({int id = 0}) => Section._(
        name: '.text',
        id: id,
        flags: SectionFlags.executable,
        alignment: 16,
      );

  /// Creates a data section.
  factory Section.data({int id = 1}) => Section._(
        name: '.data',
        id: id,
        flags: SectionFlags.writable,
        alignment: 8,
      );

  /// Creates a read-only data section.
  factory Section.rodata({int id = 2}) => Section._(
        name: '.rodata',
        id: id,
        flags: SectionFlags.none,
        alignment: 8,
      );

  /// The current size of this section.
  int get size => buffer.length;

  /// Whether this section is empty.
  bool get isEmpty => buffer.isEmpty;

  /// Whether this section is executable.
  bool get isExecutable => flags.isExecutable;

  /// Whether this section is writable.
  bool get isWritable => flags.isWritable;
}

/// Section flags.
class SectionFlags {
  final int _value;

  const SectionFlags._(this._value);

  static const none = SectionFlags._(0);
  static const executable = SectionFlags._(1);
  static const writable = SectionFlags._(2);
  static const executableWritable = SectionFlags._(3);

  bool get isExecutable => (_value & 1) != 0;
  bool get isWritable => (_value & 2) != 0;

  SectionFlags operator |(SectionFlags other) =>
      SectionFlags._(_value | other._value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SectionFlags && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}

/// Finalized code ready for execution.
class FinalizedCode {
  /// The target environment.
  final Environment env;

  /// The text (code) section bytes.
  final Uint8List textBytes;

  /// The data section bytes (if any).
  final Uint8List? dataBytes;

  /// The total size of all sections.
  final int totalSize;

  FinalizedCode._({
    required this.env,
    required this.textBytes,
    this.dataBytes,
    required this.totalSize,
  });
}

/// Container for generated code.
///
/// Manages sections, labels, and relocations during code generation.
class CodeHolder {
  /// The target environment.
  final Environment env;

  /// The label manager.
  final LabelManager _labelManager = LabelManager();

  LabelManager get labelManager => _labelManager;

  /// The text (code) section.
  late final Section text;

  /// Optional logger attached to this code holder.
  BaseLogger? logger;

  /// All sections.
  final List<Section> _sections = [];

  /// Finalized code (cached after finalize()).
  FinalizedCode? _finalizedCode;

  /// Creates a new code holder.
  CodeHolder({Environment? env}) : env = env ?? Environment.host() {
    text = Section.text();
    _sections.add(text);
  }

  /// Whether the code has been finalized.
  bool get isFinalized => _finalizedCode != null;

  // ===========================================================================
  // Section management
  // ===========================================================================

  /// Gets all sections.
  List<Section> get sections => List.unmodifiable(_sections);

  /// Gets a section by ID.
  Section? getSection(int id) {
    if (id < 0 || id >= _sections.length) return null;
    return _sections[id];
  }

  /// Creates a new section.
  Section newSection(String name, SectionFlags flags, {int alignment = 1}) {
    final id = _sections.length;
    final section = Section._(
      name: name,
      id: id,
      flags: flags,
      alignment: alignment,
    );
    _sections.add(section);
    return section;
  }

  // ===========================================================================
  // Label management
  // ===========================================================================

  /// Creates a new label.
  Label newLabel() => _labelManager.newLabel();

  /// Creates a new named label.
  Label newNamedLabel(String name) => _labelManager.newNamedLabel(name);

  /// Gets a label by name.
  Label? getLabelByName(String name) => _labelManager.getLabelByName(name);

  /// Returns the total number of labels allocated.
  int get labelCount => _labelManager.labelCount;

  /// Ensures the label manager has at least [count] labels.
  void ensureLabelCount(int count) {
    while (_labelManager.labelCount < count) {
      _labelManager.newLabel();
    }
  }

  /// Binds a label to the current position in the text section.
  void bind(Label label) {
    _labelManager.bind(label, text.buffer.length);
  }

  /// Attaches a logger to the code holder.
  void attach(BaseLogger logger) {
    this.logger = logger;
  }

  /// Sets a logger (alias for attach).
  void setLogger(BaseLogger logger) {
    attach(logger);
  }

  /// Detaches the current logger.
  void detach() {
    logger = null;
  }

  /// Resets the logger (alias for detach).
  void resetLogger() {
    detach();
  }

  /// Binds a label to a specific offset.
  void bindAt(Label label, int offset) {
    _labelManager.bind(label, offset);
  }

  /// Whether a label is bound.
  bool isLabelBound(Label label) => _labelManager.isBound(label);

  /// Gets the bound offset of a label.
  int? getLabelOffset(Label label) => _labelManager.getBoundOffset(label);

  // ===========================================================================
  // Relocation management
  // ===========================================================================

  /// Adds a relocation to the text section.
  void addReloc(Reloc reloc) {
    text.relocs.add(reloc);
    _labelManager.addFixup(
        reloc.target, reloc.atOffset, reloc.kind, reloc.addend);
  }

  /// Adds a rel32 relocation (for calls/jumps).
  void addRel32(Label target, int atOffset, [int addend = 0]) {
    addReloc(Reloc(
      kind: RelocKind.rel32,
      atOffset: atOffset,
      target: target,
      addend: addend,
    ));
  }

  /// Adds a rel8 relocation (for short jumps).
  void addRel8(Label target, int atOffset, [int addend = 0]) {
    addReloc(Reloc(
      kind: RelocKind.rel8,
      atOffset: atOffset,
      target: target,
      addend: addend,
    ));
  }

  // ===========================================================================
  // Finalization
  // ===========================================================================

  /// Finalizes the code, resolving all relocations.
  ///
  /// Returns a [FinalizedCode] object containing the executable bytes.
  FinalizedCode finalize() {
    // Resolve all relocations
    for (final reloc in text.relocs) {
      _resolveReloc(reloc, text.buffer);
    }

    _finalizedCode = FinalizedCode._(
      env: env,
      textBytes: text.buffer.bytes,
      dataBytes: null,
      totalSize: text.buffer.length,
    );
    return _finalizedCode!;
  }

  void _resolveReloc(Reloc reloc, CodeBuffer buffer) {
    final labelState = _labelManager.getState(reloc.target);

    if (!labelState.isBound) {
      throw AsmJitException(
        AsmJitError.expressionLabelNotBound,
        'Label ${reloc.target.id} is not bound (reloc at offset ${reloc.atOffset})',
      );
    }

    final targetOffset = labelState.boundOffset! + reloc.addend;
    final atOffset = reloc.atOffset;

    switch (reloc.kind) {
      case RelocKind.rel8:
        // rel8 = target - next_ip
        final nextIp = atOffset + 1;
        final disp = targetOffset - nextIp;
        if (disp < -128 || disp > 127) {
          throw AsmJitException(
            AsmJitError.relocOffsetOutOfRange,
            'rel8 displacement out of range: $disp',
          );
        }
        buffer.patch8(atOffset, disp);

      case RelocKind.rel32:
        // rel32 = target - next_ip
        final nextIp = atOffset + 4;
        final disp = targetOffset - nextIp;
        buffer.patch32(atOffset, disp);

      case RelocKind.ripRel32:
        // rip-rel32: same as rel32
        final nextIp = atOffset + 4;
        final disp = targetOffset - nextIp;
        buffer.patch32(atOffset, disp);

      case RelocKind.abs32:
        buffer.patch32(atOffset, targetOffset);

      case RelocKind.abs64:
        buffer.patch64(atOffset, targetOffset);

      case RelocKind.arm64Branch26:
      case RelocKind.arm64Branch19:
      case RelocKind.arm64Adr21:
        // ARM64-specific relocations are handled by A64Assembler.finalize()
        // They should not appear in standard CodeHolder relocations.
        throw AsmJitException(
          AsmJitError.invalidArgument,
          'ARM64 relocations must be handled by A64Assembler',
        );
    }
  }

  // ===========================================================================
  // Reset
  // ===========================================================================

  /// Resets the code holder, clearing all sections and labels.
  void reset() {
    for (final section in _sections) {
      section.buffer.clear();
      section.relocs.clear();
    }
    _labelManager.clear();
  }

  /// Re-initializes the code holder (alias for reset).
  void reinit() => reset();
}
