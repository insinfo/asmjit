/// AsmJit Code Holder
///
/// Container for generated code, managing sections, labels, and relocations.
/// Ported from asmjit/core/codeholder.h

import 'dart:typed_data';

import 'code_buffer.dart';
import 'code_writer.dart';
import 'environment.dart';
import 'error.dart';
import 'fixup.dart';
import 'formatter.dart';
import 'globals.dart';
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

  /// Section flags.
  final SectionFlags flags;

  /// Section alignment.
  final int alignment;

  /// Order of the section in the flattened image (`Section::order()`).
  final int order;

  /// Offset of the section in the flattened image, assigned by
  /// [CodeHolder.flatten] (`Section::offset()`).
  int offset = 0;

  /// Virtual size of the section (`Section::virtual_size()`): space that is
  /// reserved but not backed by [buffer] (the address table).
  int virtualSize = 0;

  Section._({
    required this.name,
    required this.id,
    required this.flags,
    this.alignment = 1,
    this.order = 0,
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

  /// The greater of the buffer size and [virtualSize] (`real_size()`).
  int get realSize => buffer.length > virtualSize ? buffer.length : virtualSize;

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

/// Relocation type (`RelocType`).
enum RelocType {
  /// None/deleted (no relocation).
  none,

  /// Expression evaluation (not used by the port yet).
  expression,

  /// Relative relocation from one section to another.
  sectionRelative,

  /// Relocate absolute to absolute.
  absToAbs,

  /// Relocate relative to absolute.
  relToAbs,

  /// Relocate absolute to relative.
  absToRel,

  /// Relocate absolute to relative or use trampoline.
  x64AddressEntry,
}

/// Relocation entry (`RelocEntry`): a value that can only be written once
/// the base address of the code is known ([CodeHolder.relocateToBase]).
final class RelocEntry {
  /// Relocation id.
  final int id;

  /// Type of the relocation.
  RelocType relocType;

  /// Format of the relocated value.
  OffsetFormat format = OffsetFormat();

  /// Source section id.
  int sourceSectionId = Globals.kInvalidId;

  /// Target section id.
  int targetSectionId = Globals.kInvalidId;

  /// Source offset (relative to the start of the source section).
  int sourceOffset = 0;

  /// Payload (target offset, target address, expression, etc).
  int payload = 0;

  RelocEntry._(this.id, this.relocType);
}

/// Details of what happened during [CodeHolder.relocateToBase]
/// (`RelocationSummary`).
final class RelocationSummary {
  /// The number of bytes the final code has been reduced by: entries of
  /// the address table that were not needed.
  final int codeSizeReduction;

  const RelocationSummary(this.codeSizeReduction);
}

/// Finalized code ready for execution.
class FinalizedCode {
  /// The target environment.
  final Environment env;

  /// The text (code) section bytes; after [CodeHolder.relocateToBase] the
  /// whole flattened image (text first, then the address table).
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
  /// Base address of the code (`CodeHolder::init(env, base_address)`), or
  /// null when unknown (`Globals::kNoBaseAddress`). When known, encoders
  /// resolve absolute targets (x86 `[abs]`/`jmp imm`, AArch64 `adr`/`b imm`)
  /// relative to it at assembly time.
  final int? baseAddress;

  CodeHolder({Environment? env, this.baseAddress})
      : env = env ?? Environment.host() {
    text = Section.text();
    _sections.add(text);
  }

  /// Relocations (`CodeHolder::relocations()`).
  final List<RelocEntry> _relocations = [];

  /// Relocation entries recorded by the emitters.
  List<RelocEntry> get relocations => List.unmodifiable(_relocations);

  /// The `.addrtab` section, created on demand.
  Section? _addressTableSection;

  /// Address table entries: absolute address -> assigned slot (or null).
  final Map<int, int?> _addressTableEntries = {};

  /// Base address passed to the last [relocateToBase], or null.
  int? _relocatedBase;

  /// The address table section (`.addrtab`), if any.
  Section? get addressTableSection => _addressTableSection;

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
  Section newSection(String name, SectionFlags flags,
      {int alignment = 1, int order = 0}) {
    if (alignment < 0 || (alignment & (alignment - 1)) != 0) {
      throw AsmJitException(AsmJitError.invalidArgument,
          'Section alignment must be zero or a power of 2: $alignment');
    }
    final id = _sections.length;
    final section = Section._(
      name: name,
      id: id,
      flags: flags,
      alignment: alignment == 0 ? 1 : alignment,
      order: order,
    );
    _sections.add(section);
    return section;
  }

  /// Sections sorted by `(order, id)` (`sections_by_order()`).
  List<Section> get sectionsByOrder => [..._sections]..sort((a, b) =>
      a.order != b.order ? a.order.compareTo(b.order) : a.id.compareTo(b.id));

  /// Returns the `.addrtab` section, creating it (`ensure_address_table_section`).
  Section ensureAddressTableSection() =>
      _addressTableSection ??= newSection('.addrtab', SectionFlags.none,
          alignment: env.registerSize, order: 0x7FFFFFFF);

  /// Adds [address] to the address table (`add_address_to_address_table`),
  /// reserving a slot that [relocateToBase] uses for jmp/call trampolines.
  void addAddressToAddressTable(int address) {
    if (_addressTableEntries.containsKey(address)) return;
    final section = ensureAddressTableSection();
    _addressTableEntries[address] = null;
    section.virtualSize += env.registerSize;
  }

  /// Creates a new relocation entry (`new_reloc_entry`).
  RelocEntry newRelocEntry(RelocType relocType) {
    final re = RelocEntry._(_relocations.length, relocType);
    _relocations.add(re);
    return re;
  }

  /// Assigns offsets of all sections in the flattened image (`flatten`).
  void flatten() {
    Section? prev;
    var offset = 0;
    for (final section in sectionsByOrder) {
      final realSize = section.realSize;
      if (realSize != 0) offset = _alignUp(offset, section.alignment);
      section.offset = offset;

      // Make sure the previous section extends a bit to cover the alignment.
      if (prev != null) prev.virtualSize = offset - prev.offset;

      prev = section;
      offset += realSize;
    }
  }

  /// Size of the flattened image (`code_size()`).
  int get codeSize {
    var offset = 0;
    for (final section in sectionsByOrder) {
      final realSize = section.realSize;
      if (realSize != 0) {
        offset = _alignUp(offset, section.alignment) + realSize;
      }
    }
    return offset;
  }

  static int _alignUp(int x, int alignment) =>
      (x + alignment - 1) & ~(alignment - 1);

  /// Relocates the code to [baseAddress] (`relocate_to_base`): writes every
  /// [RelocEntry] and fills the address table. Call [flatten] first.
  RelocationSummary relocateToBase(int baseAddress) {
    final addressSize = env.registerSize;
    final addressTableSection = _addressTableSection;
    var addressTableEntrySize = 0;

    if (addressTableSection != null) {
      addressTableSection.buffer.clear();
      addressTableSection.buffer.emitZeros(addressTableSection.virtualSize);
    }

    AsmJitException invalidReloc(RelocEntry re) => AsmJitException(
        AsmJitError.invalidRelocEntry, 'Invalid relocation entry #${re.id}');

    // Relocate all recorded locations.
    for (final re in _relocations) {
      // Possibly deleted or optimized-out entry.
      if (re.relocType == RelocType.none) continue;

      final sourceSection = getSection(re.sourceSectionId)!;
      final targetSection = re.targetSectionId != Globals.kInvalidId
          ? getSection(re.targetSectionId)
          : null;

      var value = re.payload;
      final sectionOffset = sourceSection.offset;
      final sourceOffset = re.sourceOffset;

      // Make sure that the `RelocEntry` doesn't go out of bounds.
      final regionSize = re.format.regionSize();
      if (re.sourceOffset >= sourceSection.buffer.length ||
          sourceSection.buffer.length - re.sourceOffset < regionSize) {
        throw invalidReloc(re);
      }

      final buffer = sourceSection.buffer;

      switch (re.relocType) {
        case RelocType.absToAbs:
          break;

        case RelocType.relToAbs:
          // Value is currently a relative offset from the start of its
          // section. Convert it to an absolute offset (with base address).
          if (targetSection == null) throw invalidReloc(re);
          value += baseAddress + targetSection.offset;

        case RelocType.absToRel:
          value -= baseAddress + sectionOffset + sourceOffset + regionSize;

          // Sign extend as we are not interested in the high 32-bit word in
          // a 32-bit address space.
          if (addressSize <= 4) {
            value = value.toSigned(32);
          } else if (value != value.toSigned(32)) {
            throw AsmJitException(AsmJitError.relocOffsetOutOfRange,
                'Relocation #${re.id}: displacement out of range');
          }

        case RelocType.x64AddressEntry:
          final valueOffset = re.sourceOffset + re.format.valueOffset();
          if (re.format.valueSize() != 4 || valueOffset < 2) {
            throw invalidReloc(re);
          }

          // First try whether a relative 32-bit displacement would work.
          value -= baseAddress + sectionOffset + sourceOffset + regionSize;
          if (value != value.toSigned(32)) {
            // Relative 32-bit displacement is not possible, use '.addrtab'.
            if (!_addressTableEntries.containsKey(re.payload)) {
              throw invalidReloc(re);
            }
            final slot =
                _addressTableEntries[re.payload] ??= addressTableEntrySize++;

            final atEntryIndex = slot * addressSize;
            final addrSrc = sectionOffset + sourceOffset + regionSize;
            final addrDst = addressTableSection!.offset + atEntryIndex;

            value = addrDst - addrSrc;
            if (value != value.toSigned(32)) {
              throw AsmJitException(AsmJitError.relocOffsetOutOfRange,
                  'Relocation #${re.id}: address table out of range');
            }

            // Bytes that replace [REX, OPCODE] bytes.
            const byte0 = 0xFF;
            var byte1 = buffer[valueOffset - 1];

            if (byte1 == 0xE8) {
              // Patch CALL/MOD byte to FF /2 (-> 0x15).
              byte1 = _x86EncodeMod(0, 2, 5);
            } else if (byte1 == 0xE9) {
              // Patch JMP/MOD byte to FF /4 (-> 0x25).
              byte1 = _x86EncodeMod(0, 4, 5);
            } else {
              throw invalidReloc(re);
            }

            // Patch `jmp/call` instruction.
            buffer[valueOffset - 2] = byte0;
            buffer[valueOffset - 1] = byte1;

            addressTableSection.buffer.patch64(atEntryIndex, re.payload);
          }

        default:
          throw invalidReloc(re);
      }

      if (!CodeWriterUtils.writeOffset(
          buffer, re.sourceOffset, value, re.format)) {
        throw invalidReloc(re);
      }
    }

    var codeSizeReduction = 0;
    // Fixup the virtual size of the address table if it's the last section.
    if (addressTableSection != null &&
        identical(sectionsByOrder.last, addressTableSection)) {
      final reservedSize = addressTableSection.virtualSize;
      final addressTableSize = addressTableEntrySize * addressSize;

      addressTableSection.buffer.truncate(addressTableSize);
      addressTableSection.virtualSize = addressTableSize;

      assert(reservedSize >= addressTableSize);
      codeSizeReduction = reservedSize - addressTableSize;
    }

    _relocatedBase = baseAddress;
    return RelocationSummary(codeSizeReduction);
  }

  static int _x86EncodeMod(int m, int o, int rm) => (m << 6) | (o << 3) | rm;

  /// Copies the flattened image into [dst] (`copy_flattened_data`), padding
  /// the space between sections with zeros.
  void copyFlattenedData(Uint8List dst) {
    for (final section in sectionsByOrder) {
      if (section.offset > dst.length ||
          dst.length - section.offset < section.buffer.length) {
        throw AsmJitException(AsmJitError.invalidArgument,
            'copyFlattenedData: destination too small');
      }
      dst.setRange(section.offset, section.offset + section.buffer.length,
          section.buffer.bytes);
    }
  }

  /// Whether the code has relocation entries that [relocateToBase] has not
  /// applied yet.
  bool get needsRelocation =>
      _relocatedBase == null &&
      _relocations.any((re) => re.relocType != RelocType.none);

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
  void bind(Label label) => bindLabel(label, text.id, text.buffer.length);

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

  /// Binds a label to a specific offset of the text section.
  void bindAt(Label label, int offset) => bindLabel(label, text.id, offset);

  /// Whether a label is bound.
  bool isLabelBound(Label label) => _labelManager.isBound(label);

  /// Gets the bound offset of a label.
  int? getLabelOffset(Label label) => _labelManager.getBoundOffset(label);

  /// Whether [label] is bound to the section [sectionId] (`is_bound_to`).
  bool isLabelBoundTo(Label label, int sectionId) {
    final le = _labelManager.getState(label);
    return le.isBound && le.sectionId == sectionId;
  }

  // ===========================================================================
  // Fixups
  // ===========================================================================

  /// Cross-section fixups of bound labels, resolved by
  /// [resolveCrossSectionFixups] (`_fixups`).
  final List<Fixup> _fixups = [];

  int _unresolvedFixupCount = 0;

  /// Number of fixups not resolved yet (`unresolved_fixup_count()`).
  int get unresolvedFixupCount => _unresolvedFixupCount;

  /// Whether some fixups are not resolved yet (`has_unresolved_fixups()`).
  bool get hasUnresolvedFixups => _unresolvedFixupCount != 0;

  /// Creates a fixup of the region at [offset] of section [sectionId] that
  /// references the unbound [label] (`new_fixup`).
  Fixup newFixup(
      Label label, int sectionId, int offset, int rel, OffsetFormat format) {
    final le = _labelManager.getState(label);
    // Cannot be bound if we are creating a link.
    assert(!le.isBound);
    final fixup = Fixup(sectionId, offset, rel, format);
    le.fixups.add(fixup);
    _unresolvedFixupCount++;
    return fixup;
  }

  /// Binds [label] to [toOffset] of section [toSectionId] (`bind_label`) and
  /// resolves the fixups of the same section; cross-section fixups wait for
  /// [resolveCrossSectionFixups].
  void bindLabel(Label label, int toSectionId, int toOffset) {
    if (toSectionId < 0 || toSectionId >= _sections.length) {
      throw AsmJitException(
          AsmJitError.invalidSection, 'Invalid section id: $toSectionId');
    }
    final le = _labelManager.getState(label);

    // Label can be bound only once.
    _labelManager.bind(label, toOffset);
    le.sectionId = toSectionId;

    final buf = _sections[toSectionId].buffer;
    AsmJitException? err;
    var resolved = 0;

    for (final fixup in le.fixups) {
      final relocId = fixup.labelOrRelocId;

      if (relocId != Globals.kInvalidId) {
        // Adjust the relocation payload.
        final re = _relocations[relocId];
        re.payload += toOffset;
        re.targetSectionId = toSectionId;
      } else if (fixup.sectionId != toSectionId) {
        fixup.labelOrRelocId = label.id;
        _fixups.add(fixup);
        continue;
      } else {
        final displacement = toOffset - fixup.offset + fixup.rel;

        // Overwrite a real displacement in the CodeBuffer.
        if (!CodeWriterUtils.writeOffset(
            buf, fixup.offset, displacement, fixup.format)) {
          err ??= AsmJitException(AsmJitError.invalidDisplacement,
              'Label ${label.id}: displacement $displacement does not fit');
          fixup.labelOrRelocId = label.id;
          _fixups.add(fixup);
          continue;
        }
      }
      resolved++;
    }
    le.fixups.clear();
    _unresolvedFixupCount -= resolved;
    if (err != null) throw err;
  }

  /// Resolves the fixups between sections once they have offsets
  /// ([flatten]) (`resolve_cross_section_fixups`).
  void resolveCrossSectionFixups() {
    if (!hasUnresolvedFixups) return;

    AsmJitException? err;
    final unresolved = <Fixup>[];
    for (final fixup in _fixups) {
      final le = _labelManager.getState(Label(fixup.labelOrRelocId));
      final toOffset = _sections[le.sectionId].offset + le.boundOffset!;

      final fromSection = _sections[fixup.sectionId];
      // Calculate the offset relative to the start of the virtual base.
      final fromOffset = fromSection.offset + fixup.offset;
      final displacement = toOffset - fromOffset + fixup.rel;

      // Overwrite a real displacement in the CodeBuffer.
      if (CodeWriterUtils.writeOffset(
          fromSection.buffer, fixup.offset, displacement, fixup.format)) {
        _unresolvedFixupCount--;
      } else {
        err ??= AsmJitException(AsmJitError.invalidDisplacement,
            'Cross-section displacement $displacement does not fit');
        unresolved.add(fixup);
      }
    }
    _fixups
      ..clear()
      ..addAll(unresolved);
    if (err != null) throw err;
  }

  // ===========================================================================
  // Finalization
  // ===========================================================================

  /// Finalizes the code, resolving all relocations.
  ///
  /// Returns a [FinalizedCode] object containing the executable bytes.
  ///
  /// Code with [RelocEntry]s (absolute targets without a known
  /// [baseAddress]) can only run at the address it is relocated to: use
  /// `JitRuntime.add()`, or [flatten] + [relocateToBase] before this.
  FinalizedCode finalize() {
    resolveLabelFixups();

    if (needsRelocation) {
      throw AsmJitException(
          AsmJitError.invalidState,
          'The code has absolute targets that need relocation: use '
          'JitRuntime.add() or flatten() + relocateToBase()');
    }

    Uint8List bytes = text.buffer.bytes;
    if (_relocatedBase != null) {
      bytes = Uint8List(codeSize);
      copyFlattenedData(bytes);
    }

    _finalizedCode = FinalizedCode._(
      env: env,
      textBytes: bytes,
      dataBytes: null,
      totalSize: bytes.length,
    );
    return _finalizedCode!;
  }

  /// Assigns section offsets ([flatten]) and resolves the cross-section
  /// fixups; fails if a referenced label was never bound.
  void resolveLabelFixups() {
    for (final label in _labelManager.labels) {
      final le = _labelManager.getState(label);
      if (le.isUnbound && le.hasFixups) {
        throw AsmJitException(
          AsmJitError.expressionLabelNotBound,
          'Label ${label.id} is not bound (fixup at offset '
          '${le.fixups.first.offset})',
        );
      }
    }
    flatten();
    resolveCrossSectionFixups();
  }

  // ===========================================================================
  // Reset
  // ===========================================================================

  /// Resets the code holder, clearing all sections and labels.
  void reset() {
    for (final section in _sections) {
      section.buffer.clear();
      section.offset = 0;
      section.virtualSize = 0;
    }
    _labelManager.clear();
    _relocations.clear();
    _fixups.clear();
    _unresolvedFixupCount = 0;
    _addressTableEntries.clear();
    _relocatedBase = null;
  }

  /// Re-initializes the code holder (alias for reset).
  void reinit() => reset();
}
