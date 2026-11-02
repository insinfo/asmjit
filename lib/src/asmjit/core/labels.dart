/// AsmJit Labels
///
/// Provides label management for code generation.
/// Ported from asmjit/core/codeholder.h (label-related parts)

import 'error.dart';
import 'fixup.dart';
import 'globals.dart';

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

/// The internal state of a label (`LabelEntry`).
class LabelState {
  /// The offset where this label is bound, or null if not yet bound.
  int? boundOffset;

  /// Fixups referencing this label while it is not bound (`_get_fixups()`).
  final List<Fixup> fixups = [];

  /// Optional name for named labels.
  final String? name;

  /// The section ID where this label is bound.
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

/// A place in code or data that references a label which is not known yet
/// (`Fixup`): resolved when the label is bound in the same section, or by
/// `CodeHolder.resolveCrossSectionFixups()` once sections have offsets.
///
/// The written displacement is `target - offset + rel`.
final class Fixup {
  /// Section where the fixup is.
  final int sectionId;

  /// Label id of a cross-section fixup, or the id of the `RelocEntry` whose
  /// payload receives the label offset, or `Globals.kInvalidId`.
  int labelOrRelocId = Globals.kInvalidId;

  /// Offset of the patched region relative to the start of the section.
  final int offset;

  /// Displacement adjustment.
  final int rel;

  /// Format of the written displacement.
  final OffsetFormat format;

  Fixup(this.sectionId, this.offset, this.rel, this.format);
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
