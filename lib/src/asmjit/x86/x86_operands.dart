/// AsmJit x86/x64 Operands
///
/// Memory operands and additional operand types for x86/x64.
/// Ported from asmjit/x86/x86operand.h

import '../core/operand.dart';
import '../core/labels.dart';

/// x86/x64 memory operand.
///
/// Represents a memory reference in the form:
/// `[base + index*scale + displacement]`
class X86Mem extends BaseMem {
  /// The base register, or null if none.
  final BaseReg? base;

  /// The index register, or null if none.
  final BaseReg? index;

  /// The scale factor (1, 2, 4, or 8).
  final int scale;

  /// The displacement (signed offset).
  @override
  final int displacement;

  /// The size of the memory access in bytes (0 = unspecified).
  @override
  final int size;

  /// Segment override, or null for default.
  final X86Seg? segment;

  const X86Mem({
    this.base,
    this.index,
    this.scale = 1,
    this.displacement = 0,
    this.size = 0,
    this.segment,
  });

  /// Creates a memory operand from a pointer (base register + displacement).
  static X86Mem ptr(BaseReg base, [int disp = 0]) =>
      X86Mem.base(base, disp: disp);

  /// Creates a memory operand with just a base register.
  const X86Mem.base(BaseReg base, {int disp = 0, int size = 0})
      : this(base: base, displacement: disp, size: size);

  /// Creates a memory operand with base + displacement.
  const X86Mem.baseDisp(BaseReg base, int disp, {int size = 0})
      : this(base: base, displacement: disp, size: size);

  /// Creates a memory operand with base + index*scale + displacement.
  const X86Mem.baseIndexScale(
    BaseReg base,
    BaseReg index,
    int scale, {
    int disp = 0,
    int size = 0,
  }) : this(
          base: base,
          index: index,
          scale: scale,
          displacement: disp,
          size: size,
        );

  /// Creates an absolute memory operand (just displacement).
  const X86Mem.abs(int address, {int size = 0})
      : this(displacement: address, size: size);

  @override
  bool get hasBase => base != null;

  @override
  bool get hasIndex => index != null;

  /// Whether this memory reference has a displacement.
  bool get hasDisplacement => displacement != 0;

  /// Whether this memory reference has a segment override.
  bool get hasSegment => segment != null;

  /// Whether the scale is valid (1, 2, 4, or 8).
  bool get isScaleValid => scale == 1 || scale == 2 || scale == 4 || scale == 8;

  /// Whether this is a simple [base] reference.
  bool get isSimple =>
      base != null && index == null && displacement == 0 && segment == null;

  /// Whether the displacement fits in a signed 8-bit value.
  bool get dispFitsI8 => displacement >= -128 && displacement <= 127;

  /// Whether the displacement fits in a signed 32-bit value.
  bool get dispFitsI32 =>
      displacement >= -2147483648 && displacement <= 2147483647;

  /// Creates a copy with a different size.
  X86Mem withSize(int newSize) => X86Mem(
        base: base,
        index: index,
        scale: scale,
        displacement: displacement,
        size: newSize,
        segment: segment,
      );

  /// Creates a copy with a different displacement.
  X86Mem withDisplacement(int newDisp) => X86Mem(
        base: base,
        index: index,
        scale: scale,
        displacement: newDisp,
        size: size,
        segment: segment,
      );

  /// Adds an offset to the displacement.
  X86Mem operator +(int offset) => withDisplacement(displacement + offset);

  /// Subtracts an offset from the displacement.
  X86Mem operator -(int offset) => withDisplacement(displacement - offset);

  @override
  String toString() {
    final buffer = StringBuffer();

    // Size prefix
    if (size > 0) {
      switch (size) {
        case 1:
          buffer.write('byte ptr ');
        case 2:
          buffer.write('word ptr ');
        case 4:
          buffer.write('dword ptr ');
        case 8:
          buffer.write('qword ptr ');
        case 16:
          buffer.write('xmmword ptr ');
        case 32:
          buffer.write('ymmword ptr ');
        case 64:
          buffer.write('zmmword ptr ');
        default:
          buffer.write('[$size bytes] ');
      }
    }

    // Segment override
    if (segment != null) {
      buffer.write('${segment!.name}:');
    }

    buffer.write('[');

    var first = true;
    if (base != null) {
      buffer.write(base.toString());
      first = false;
    }

    if (index != null) {
      if (!first) buffer.write(' + ');
      buffer.write(index.toString());
      if (scale > 1) {
        buffer.write('*$scale');
      }
      first = false;
    }

    if (displacement != 0 || first) {
      if (displacement >= 0 && !first) {
        buffer.write(' + ');
      } else if (displacement < 0) {
        buffer.write(' - ');
      }
      buffer.write(displacement.abs().toRadixString(16).toUpperCase());
      buffer.write('h');
    }

    buffer.write(']');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is X86Mem &&
          other.base == base &&
          other.index == index &&
          other.scale == scale &&
          other.displacement == displacement &&
          other.size == size &&
          other.segment == segment;

  @override
  int get hashCode =>
      Object.hash(base, index, scale, displacement, size, segment);
}

/// x86 segment registers.
enum X86Seg {
  es,
  cs,
  ss,
  ds,
  fs,
  gs;

  /// The encoding for the segment override prefix.
  int get prefix {
    switch (this) {
      case X86Seg.es:
        return 0x26;
      case X86Seg.cs:
        return 0x2E;
      case X86Seg.ss:
        return 0x36;
      case X86Seg.ds:
        return 0x3E;
      case X86Seg.fs:
        return 0x64;
      case X86Seg.gs:
        return 0x65;
    }
  }
}

/// Helper functions for creating memory operands.

/// Creates a memory operand: [base + disp]
X86Mem ptr(BaseReg base, [int disp = 0]) => X86Mem.base(base, disp: disp);

/// Creates a byte memory operand: byte ptr [base]
X86Mem bytePtr(BaseReg base, [int disp = 0]) =>
    X86Mem.baseDisp(base, disp, size: 1);

/// Creates a byte memory operand: byte ptr [base + index*scale + disp]
X86Mem bytePtrSIB(BaseReg base, BaseReg index, int scale, [int disp = 0]) =>
    X86Mem.baseIndexScale(base, index, scale, disp: disp, size: 1);

/// Creates a word memory operand: word ptr [base]
X86Mem wordPtr(BaseReg base, [int disp = 0]) =>
    X86Mem.baseDisp(base, disp, size: 2);

/// Creates a word memory operand: word ptr [base + index*scale + disp]
X86Mem wordPtrSIB(BaseReg base, BaseReg index, int scale, [int disp = 0]) =>
    X86Mem.baseIndexScale(base, index, scale, disp: disp, size: 2);

/// Creates a dword memory operand: dword ptr [base]
X86Mem dwordPtr(BaseReg base, [int disp = 0]) =>
    X86Mem.baseDisp(base, disp, size: 4);

/// Creates a dword memory operand: dword ptr [base + index*scale + disp]
X86Mem dwordPtrSIB(BaseReg base, BaseReg index, int scale, [int disp = 0]) =>
    X86Mem.baseIndexScale(base, index, scale, disp: disp, size: 4);

/// Creates a qword memory operand: qword ptr [base]
X86Mem qwordPtr(BaseReg base, [int disp = 0]) =>
    X86Mem.baseDisp(base, disp, size: 8);

/// Creates a qword memory operand: qword ptr [base + index*scale + disp]
X86Mem qwordPtrSIB(BaseReg base, BaseReg index, int scale, [int disp = 0]) =>
    X86Mem.baseIndexScale(base, index, scale, disp: disp, size: 8);

/// Creates an xmmword memory operand: xmmword ptr [base]
X86Mem xmmwordPtr(BaseReg base, [int disp = 0]) =>
    X86Mem.baseDisp(base, disp, size: 16);

/// Creates an xmmword memory operand: xmmword ptr [base + index*scale + disp]
X86Mem xmmwordPtrSIB(BaseReg base, BaseReg index, int scale, [int disp = 0]) =>
    X86Mem.baseIndexScale(base, index, scale, disp: disp, size: 16);

/// Creates a ymmword memory operand: ymmword ptr [base]
X86Mem ymmwordPtr(BaseReg base, [int disp = 0]) =>
    X86Mem.baseDisp(base, disp, size: 32);

/// Creates a ymmword memory operand: ymmword ptr [base + index*scale + disp]
X86Mem ymmwordPtrSIB(BaseReg base, BaseReg index, int scale, [int disp = 0]) =>
    X86Mem.baseIndexScale(base, index, scale, disp: disp, size: 32);

/// Creates a zmmword memory operand: zmmword ptr [base]
X86Mem zmmwordPtr(BaseReg base, [int disp = 0]) =>
    X86Mem.baseDisp(base, disp, size: 64);

/// Creates a zmmword memory operand: zmmword ptr [base + index*scale + disp]
X86Mem zmmwordPtrSIB(BaseReg base, BaseReg index, int scale, [int disp = 0]) =>
    X86Mem.baseIndexScale(base, index, scale, disp: disp, size: 64);

/// RIP-relative memory operand (for x86-64).
class X86RipMem extends BaseMem {
  /// The target label.
  final Label? label;

  /// The displacement (added to label address or used as absolute RIP offset).
  @override
  final int displacement;

  /// The size of the memory access in bytes.
  @override
  final int size;

  const X86RipMem({
    this.label,
    this.displacement = 0,
    this.size = 0,
  });

  /// Creates a RIP-relative reference to a label.
  const X86RipMem.label(Label label, {int size = 0})
      : this(label: label, size: size);

  @override
  bool get hasBase => false;

  @override
  bool get hasIndex => false;

  @override
  BaseReg? get base => null;

  @override
  BaseReg? get index => null;

  /// Whether this is a label reference.
  bool get hasLabel => label != null;

  @override
  String toString() {
    final buffer = StringBuffer();
    if (size > 0) {
      switch (size) {
        case 1:
          buffer.write('byte ptr ');
        case 2:
          buffer.write('word ptr ');
        case 4:
          buffer.write('dword ptr ');
        case 8:
          buffer.write('qword ptr ');
        default:
          buffer.write('[$size bytes] ');
      }
    }
    buffer.write('[rip');
    if (label != null) {
      buffer.write(' + L${label!.id}');
    }
    if (displacement != 0) {
      if (displacement > 0) {
        buffer.write(' + ${displacement.toRadixString(16)}h');
      } else {
        buffer.write(' - ${(-displacement).toRadixString(16)}h');
      }
    }
    buffer.write(']');
    return buffer.toString();
  }
}
