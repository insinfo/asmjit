/// AsmJit Base Assembler
///
/// Ported from asmjit/core/assembler.h / assembler.cpp: the section being
/// written, label binding and data embedding shared by the architecture
/// assemblers.
library;

import 'code_buffer.dart';
import 'code_holder.dart';
import 'emitter.dart';
import 'error.dart';
import 'fixup.dart';
import 'globals.dart';
import 'labels.dart';

/// Base class of `X86Assembler` and `A64Assembler` (`BaseAssembler`).
abstract class BaseAssembler extends BaseEmitter {
  Section _section;

  BaseAssembler(CodeHolder code)
      : _section = code.text,
        super(code);

  /// The section the assembler writes to (`_section`).
  Section get currentSection => _section;

  /// The buffer of [currentSection].
  CodeBuffer get buffer => _section.buffer;

  /// The offset in [currentSection] (`offset()`).
  int get offset => _section.buffer.length;

  /// Called when [section] switches the section; the architecture
  /// assemblers point their encoder at it.
  void onSectionChanged(Section section) {}

  /// Switches to [section] (`section()`); it must belong to [code].
  void section(Section section) {
    if (!identical(code.getSection(section.id), section)) {
      throw AsmJitException(
          AsmJitError.invalidSection, 'Section ${section.name} is not in code');
    }
    log('.section ${section.name} {#${section.id}}');
    _section = section;
    onSectionChanged(section);
  }

  // ===========================================================================
  // Labels
  // ===========================================================================

  /// Creates a new label.
  Label newLabel() => code.newLabel();

  /// Creates a new named label.
  Label newNamedLabel(String name) => code.newNamedLabel(name);

  /// Binds [label] to the current offset of [currentSection] (`bind()`).
  void bind(Label label) => code.bindLabel(label, _section.id, offset);

  // ===========================================================================
  // Align
  // ===========================================================================

  /// Aligns the current offset to [alignment] (`align()`), padding as
  /// [alignMode] says for the architecture.
  void align(AlignMode alignMode, int alignment);

  /// Number of padding bytes [align] has to emit: validates [alignment]
  /// like upstream (a power of 2 up to `Globals::kMaxAlignment`).
  int alignPadding(int alignment) {
    if (alignment <= 1) return 0;
    if ((alignment & (alignment - 1)) != 0 ||
        alignment > Globals.kMaxAlignment) {
      throw AsmJitException(
          AsmJitError.invalidArgument, 'Invalid alignment: $alignment');
    }
    return (alignment - (offset & (alignment - 1))) & (alignment - 1);
  }

  // ===========================================================================
  // Embed
  // ===========================================================================

  /// Embeds raw [data] (`embed()`).
  void embed(List<int> data) {
    if (data.isEmpty) return;
    buffer.emitBytes(data);
  }

  /// Embeds [items] of [typeSize] bytes each (1, 2, 4 or 8), little endian,
  /// [repeatCount] times (`embed_data_array()`).
  void embedDataArray(int typeSize, List<int> items, [int repeatCount = 1]) {
    if (typeSize != 1 && typeSize != 2 && typeSize != 4 && typeSize != 8) {
      throw AsmJitException(
          AsmJitError.invalidArgument, 'Invalid data size: $typeSize');
    }
    for (var r = 0; r < repeatCount; r++) {
      for (final v in items) {
        switch (typeSize) {
          case 1:
            buffer.emit8(v);
          case 2:
            buffer.emit16(v);
          case 4:
            buffer.emit32(v);
          case 8:
            buffer.emit64(v);
        }
      }
    }
  }

  /// `embed_uint8()`.
  void embedUInt8(int value, [int repeatCount = 1]) =>
      embedDataArray(1, [value], repeatCount);

  /// `embed_uint16()`.
  void embedUInt16(int value, [int repeatCount = 1]) =>
      embedDataArray(2, [value], repeatCount);

  /// `embed_uint32()`.
  void embedUInt32(int value, [int repeatCount = 1]) =>
      embedDataArray(4, [value], repeatCount);

  /// `embed_uint64()`.
  void embedUInt64(int value, [int repeatCount = 1]) =>
      embedDataArray(8, [value], repeatCount);

  static bool _isPowerOf2UpTo8(int n) => n == 1 || n == 2 || n == 4 || n == 8;

  /// Embeds the absolute address of [label], [dataSize] bytes (the register
  /// size by default), resolved by [CodeHolder.relocateToBase]
  /// (`embed_label()`).
  ///
  /// Deviation from upstream, whose check is inverted
  /// (`if (is_label_valid(label)) return kInvalidLabel`): executing upstream,
  /// `embed_label()` fails with `kInvalidLabel` for every valid label and
  /// crashes for an invalid one. The rest follows upstream.
  void embedLabel(Label label, [int dataSize = 0]) {
    if (!label.isValid || label.id >= code.labelCount) {
      throw AsmJitException(AsmJitError.invalidLabel, 'Invalid label $label');
    }
    final le = code.labelManager.getState(label);

    if (dataSize == 0) dataSize = code.env.registerSize;
    if (!_isPowerOf2UpTo8(dataSize)) {
      throw AsmJitException(
          AsmJitError.invalidOperandSize, 'Invalid data size: $dataSize');
    }

    log('.${_dataTypeName(dataSize)} L${label.id}');

    final re = code.newRelocEntry(RelocType.relToAbs);
    re.sourceSectionId = _section.id;
    re.sourceOffset = offset;
    re.format.resetToSimpleValue(OffsetType.kUnsignedOffset, dataSize);

    if (le.isBound) {
      re.targetSectionId = le.sectionId;
      re.payload = le.boundOffset!;
    } else {
      final of = OffsetFormat()
        ..resetToSimpleValue(OffsetType.kUnsignedOffset, dataSize);
      final fixup = code.newFixup(label, _section.id, offset, 0, of);
      fixup.labelOrRelocId = re.id;
    }

    // Emit dummy DWORD/QWORD depending on the data size.
    buffer.emitZeros(dataSize);
  }

  /// Embeds `label - base`, [dataSize] bytes (the register size by default)
  /// (`embed_label_delta()`).
  void embedLabelDelta(Label label, Label base, [int dataSize = 0]) {
    for (final l in [label, base]) {
      if (!l.isValid || l.id >= code.labelCount) {
        throw AsmJitException(AsmJitError.invalidLabel, 'Invalid label $l');
      }
    }
    final labelEntry = code.labelManager.getState(label);
    final baseEntry = code.labelManager.getState(base);

    if (dataSize == 0) dataSize = code.env.registerSize;
    if (!_isPowerOf2UpTo8(dataSize)) {
      throw AsmJitException(
          AsmJitError.invalidOperandSize, 'Invalid data size: $dataSize');
    }

    log('.${_dataTypeName(dataSize)} (L${label.id} - L${base.id})');

    // If both labels are bound within the same section it means the delta
    // can be calculated now.
    if (labelEntry.isBound &&
        baseEntry.isBound &&
        labelEntry.sectionId == baseEntry.sectionId) {
      final delta = labelEntry.boundOffset! - baseEntry.boundOffset!;
      for (var i = 0; i < dataSize; i++) {
        buffer.emit8(delta >> (i * 8));
      }
    } else {
      final re = code.newRelocEntry(RelocType.expression);
      re.expression = Expression(ExpressionOpType.sub, label, base);
      re.format.resetToSimpleValue(OffsetType.kSignedOffset, dataSize);
      re.sourceSectionId = _section.id;
      re.sourceOffset = offset;

      buffer.emitZeros(dataSize);
    }
  }

  static String _dataTypeName(int size) => switch (size) {
        1 => 'u8',
        2 => 'u16',
        4 => 'u32',
        _ => 'u64',
      };
}
