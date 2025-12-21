/// AsmJit Inline Bytes API
///
/// Provides a way to emit pre-compiled machine code with optional patches.
/// This is useful for embedding shellcode or pre-optimized instruction sequences.

import 'dart:typed_data';

import '../core/labels.dart';

/// Represents a pre-compiled block of machine code bytes.
///
/// Can include patches for dynamic values like addresses, offsets, or immediates.
///
/// Example:
/// ```dart
/// // Pre-compiled: mov eax, <imm32>; ret
/// final code = InlineBytes(
///   Uint8List.fromList([0xB8, 0x00, 0x00, 0x00, 0x00, 0xC3]),
///   patches: [
///     InlinePatch(kind: InlinePatchKind.imm32, atOffset: 1, value: 42),
///   ],
/// );
/// ```
class InlineBytes {
  /// The raw bytes of the machine code.
  final Uint8List bytes;

  /// List of patches to apply to the bytes.
  final List<InlinePatch> patches;

  const InlineBytes(this.bytes, {this.patches = const []});

  /// Creates an InlineBytes from a list of integers.
  factory InlineBytes.fromList(List<int> bytes, {List<InlinePatch>? patches}) {
    return InlineBytes(
      Uint8List.fromList(bytes),
      patches: patches ?? const [],
    );
  }

  /// The length of the code in bytes.
  int get length => bytes.length;

  /// Whether this code block has patches.
  bool get hasPatches => patches.isNotEmpty;

  /// Creates a copy of the bytes with all patches applied.
  ///
  /// For label patches, the label must be bound before calling this.
  Uint8List applyPatches({
    LabelManager? labelManager,
    int baseOffset = 0,
  }) {
    final result = Uint8List.fromList(bytes);

    for (final patch in patches) {
      patch.apply(result, labelManager: labelManager, baseOffset: baseOffset);
    }

    return result;
  }

  /// Returns a new InlineBytes with additional bytes appended.
  InlineBytes append(InlineBytes other) {
    final newBytes = Uint8List(length + other.length);
    newBytes.setRange(0, length, bytes);
    newBytes.setRange(length, newBytes.length, other.bytes);

    // Adjust patch offsets for the appended code
    final adjustedPatches = other.patches.map((p) => InlinePatch(
          kind: p.kind,
          atOffset: p.atOffset + length,
          value: p.value,
          label: p.label,
        ));

    return InlineBytes(
      newBytes,
      patches: [...patches, ...adjustedPatches],
    );
  }

  @override
  String toString() {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return 'InlineBytes($length bytes: $hex${hasPatches ? ", ${patches.length} patches" : ""})';
  }
}

/// Kind of patch to apply to inline bytes.
enum InlinePatchKind {
  /// 8-bit signed immediate.
  imm8,

  /// 16-bit signed immediate (little-endian).
  imm16,

  /// 32-bit signed immediate (little-endian).
  imm32,

  /// 64-bit signed immediate (little-endian).
  imm64,

  /// 8-bit PC-relative offset.
  rel8,

  /// 32-bit PC-relative offset.
  rel32,

  /// 32-bit RIP-relative offset (x86-64).
  ripRel32,

  /// 64-bit absolute address (little-endian).
  abs64,

  /// 32-bit absolute address (little-endian).
  abs32,
}

/// A patch to apply to inline bytes.
///
/// Patches can be for immediate values (known at build time) or for
/// labels (resolved at link time).
class InlinePatch {
  /// The kind of patch.
  final InlinePatchKind kind;

  /// Offset within the bytes where the patch should be applied.
  final int atOffset;

  /// The value for immediate patches.
  /// For label patches, this is an addend.
  final int value;

  /// The target label for label-based patches (rel8, rel32, ripRel32).
  final Label? label;

  const InlinePatch({
    required this.kind,
    required this.atOffset,
    this.value = 0,
    this.label,
  });

  /// The size of this patch in bytes.
  int get size {
    switch (kind) {
      case InlinePatchKind.imm8:
      case InlinePatchKind.rel8:
        return 1;
      case InlinePatchKind.imm16:
        return 2;
      case InlinePatchKind.imm32:
      case InlinePatchKind.rel32:
      case InlinePatchKind.ripRel32:
      case InlinePatchKind.abs32:
        return 4;
      case InlinePatchKind.imm64:
      case InlinePatchKind.abs64:
        return 8;
    }
  }

  /// Applies this patch to the given bytes.
  void apply(
    Uint8List bytes, {
    LabelManager? labelManager,
    int baseOffset = 0,
  }) {
    int patchValue;

    switch (kind) {
      case InlinePatchKind.imm8:
      case InlinePatchKind.imm16:
      case InlinePatchKind.imm32:
      case InlinePatchKind.imm64:
      case InlinePatchKind.abs32:
      case InlinePatchKind.abs64:
        patchValue = value;

      case InlinePatchKind.rel8:
      case InlinePatchKind.rel32:
      case InlinePatchKind.ripRel32:
        if (label != null && labelManager != null) {
          final targetOffset = labelManager.getBoundOffset(label!);
          if (targetOffset == null) {
            throw StateError('Patch references unbound label: ${label!.id}');
          }
          // rel = target - (patch_location + patch_size)
          final patchLocation = baseOffset + atOffset;
          patchValue = targetOffset - (patchLocation + size) + value;
        } else {
          patchValue = value;
        }
    }

    // Write the value to the bytes
    _writeValue(bytes, atOffset, patchValue, size);
  }

  static void _writeValue(Uint8List bytes, int offset, int value, int size) {
    for (int i = 0; i < size; i++) {
      bytes[offset + i] = (value >> (i * 8)) & 0xFF;
    }
  }

  @override
  String toString() =>
      'InlinePatch(kind: $kind, at: $atOffset, value: $value${label != null ? ", label: ${label!.id}" : ""})';
}

/// A template for code that can be instantiated multiple times with different parameters.
///
/// Useful for creating optimized code snippets that can be reused.
class InlineTemplate {
  /// The template bytes.
  final Uint8List bytes;

  /// Patch specifications (template placeholders).
  final List<InlineTemplatePatch> patchSpec;

  const InlineTemplate._({
    required this.bytes,
    required this.patchSpec,
  });

  /// Creates a template from a list of bytes.
  factory InlineTemplate.fromList(
    List<int> bytes,
    List<InlineTemplatePatch> patchSpec,
  ) {
    return InlineTemplate._(
      bytes: Uint8List.fromList(bytes),
      patchSpec: patchSpec,
    );
  }

  /// Instantiates the template with the given values.
  InlineBytes instantiate(Map<String, int> values) {
    final patches = <InlinePatch>[];

    for (final spec in patchSpec) {
      final value = values[spec.name];
      if (value == null && spec.required) {
        throw ArgumentError('Missing required parameter: ${spec.name}');
      }
      patches.add(InlinePatch(
        kind: spec.kind,
        atOffset: spec.atOffset,
        value: value ?? spec.defaultValue,
      ));
    }

    return InlineBytes(Uint8List.fromList(bytes), patches: patches);
  }

  /// The length of the template in bytes.
  int get length => bytes.length;
}

/// A placeholder in an inline template.
class InlineTemplatePatch {
  /// The name of the parameter.
  final String name;

  /// The patch kind.
  final InlinePatchKind kind;

  /// Offset within the template bytes.
  final int atOffset;

  /// Default value if not provided.
  final int defaultValue;

  /// Whether this parameter is required.
  final bool required;

  const InlineTemplatePatch({
    required this.name,
    required this.kind,
    required this.atOffset,
    this.defaultValue = 0,
    this.required = true,
  });
}
