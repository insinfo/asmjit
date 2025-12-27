/// AsmJit Labels
///
/// Provides label management for code generation.
/// Ported from asmjit/core/codeholder.h (label-related parts)

import 'error.dart';

/// A label identifier.
///
/// Labels are used to mark positions in code for jumps, calls, and
/// other references. They are identified by an integer ID.
class Label {
  /// The label ID.
  final int id;

  /// Creates a label with the given ID.
  const Label(this.id);

  /// An invalid/uninitialized label.
  static const Label invalid = Label(-1);

  /// Whether this label is valid.
  bool get isValid => id >= 0;

  /// Whether this label is invalid.
  bool get isInvalid => id < 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Label && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Label($id)';
}

/// The internal state of a label.
class LabelState {
  /// The offset where this label is bound, or null if not yet bound.
  int? boundOffset;

  /// Offsets that need to be fixed up when this label is bound.
  final List<_LabelFixup> fixups = [];

  /// Optional name for named labels.
  final String? name;

  /// The section ID where this label is defined.
  int sectionId;

  /// Creates a new label state.
  LabelState({
    this.name,
    this.sectionId = 0,
  });

  /// Whether this label has been bound.
  bool get isBound => boundOffset != null;

  /// Whether this label has not been bound yet.
  bool get isUnbound => boundOffset == null;

  /// Whether this label has any pending fixups.
  bool get hasFixups => fixups.isNotEmpty;
}

/// A fixup for a label reference.
class _LabelFixup {
  /// The offset in the code buffer where the fixup needs to be applied.
  final int atOffset;

  /// The kind of relocation.
  final RelocKind kind;

  /// Additional addend to apply.
  final int addend;

  const _LabelFixup({
    required this.atOffset,
    required this.kind,
    this.addend = 0,
  });
}

/// The kind of relocation.
enum RelocKind {
  /// PC-relative 8-bit displacement (short jump).
  rel8,

  /// PC-relative 32-bit displacement (near jump/call).
  rel32,

  /// Absolute 32-bit address.
  abs32,

  /// Absolute 64-bit address.
  abs64,

  /// RIP-relative 32-bit displacement (x86-64).
  ripRel32,

  /// ARM64 26-bit branch (B, BL).
  arm64Branch26,

  /// ARM64 19-bit conditional branch (B.cond, CBZ, CBNZ).
  arm64Branch19,

  /// ARM64 ADR/ADRP 21-bit PC-relative.
  arm64Adr21,
}

/// A relocation entry.
class Reloc {
  /// The kind of relocation.
  final RelocKind kind;

  /// The offset in the code buffer where this relocation applies.
  final int atOffset;

  /// The target label.
  final Label target;

  /// Additional addend.
  final int addend;

  /// The size of the relocation (in bytes).
  final int size;

  Reloc({
    required this.kind,
    required this.atOffset,
    required this.target,
    this.addend = 0,
    int? size,
  }) : size = size ?? _defaultSize(kind);

  static int _defaultSize(RelocKind kind) {
    switch (kind) {
      case RelocKind.rel8:
        return 1;
      case RelocKind.rel32:
      case RelocKind.abs32:
      case RelocKind.ripRel32:
      case RelocKind.arm64Branch26:
      case RelocKind.arm64Branch19:
      case RelocKind.arm64Adr21:
        return 4;
      case RelocKind.abs64:
        return 8;
    }
  }
}

/// Manages labels for a code holder.
class LabelManager {
  /// All label states, indexed by label ID.
  final List<LabelState> _labels = [];

  /// Map of named labels.
  final Map<String, Label> _namedLabels = {};

  /// Creates a new label.
  Label newLabel() {
    final id = _labels.length;
    _labels.add(LabelState());
    return Label(id);
  }

  /// Creates a new named label.
  Label newNamedLabel(String name) {
    if (_namedLabels.containsKey(name)) {
      throw AsmJitException(
        AsmJitError.labelAlreadyDefined,
        'Label "$name" is already defined',
      );
    }

    final id = _labels.length;
    _labels.add(LabelState(name: name));
    final label = Label(id);
    _namedLabels[name] = label;
    return label;
  }

  /// Gets a label by name.
  Label? getLabelByName(String name) => _namedLabels[name];

  /// Gets the state of a label.
  LabelState getState(Label label) {
    if (label.id < 0 || label.id >= _labels.length) {
      throw AsmJitException(
        AsmJitError.invalidLabel,
        'Invalid label ID: ${label.id}',
      );
    }
    return _labels[label.id];
  }

  /// Whether a label is bound.
  bool isBound(Label label) => getState(label).isBound;

  /// Gets the bound offset of a label.
  ///
  /// Returns null if the label is not bound.
  int? getBoundOffset(Label label) => getState(label).boundOffset;

  /// Binds a label to an offset.
  void bind(Label label, int offset) {
    final state = getState(label);
    if (state.isBound) {
      throw AsmJitException(
        AsmJitError.labelAlreadyBound,
        'Label ${label.id} is already bound at offset ${state.boundOffset}',
      );
    }
    state.boundOffset = offset;
  }

  /// Adds a fixup for a label.
  void addFixup(Label label, int atOffset, RelocKind kind, [int addend = 0]) {
    final state = getState(label);
    state.fixups.add(_LabelFixup(
      atOffset: atOffset,
      kind: kind,
      addend: addend,
    ));
  }

  /// Gets all labels.
  Iterable<Label> get labels sync* {
    for (int i = 0; i < _labels.length; i++) {
      yield Label(i);
    }
  }

  /// Gets the number of labels.
  int get labelCount => _labels.length;

  /// Clears all labels.
  void clear() {
    _labels.clear();
    _namedLabels.clear();
  }
}
