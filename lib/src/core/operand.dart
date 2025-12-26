/// AsmJit Operand
///
/// Base classes for operands (registers, memory, immediates).
/// Ported from asmjit/core/operand.h

import 'labels.dart';

/// Base class for all operands.
abstract class Operand {
  const Operand();

  /// Whether this operand is none/invalid.
  bool get isNone => false;

  /// Whether this operand is a register.
  bool get isReg => false;

  /// Whether this operand is a memory operand.
  bool get isMem => false;

  /// Whether this operand is an immediate value.
  bool get isImm => false;

  /// Whether this operand is a label.
  bool get isLabel => false;
}

/// A "none" operand - represents absence of an operand.
class NoneOperand extends Operand {
  const NoneOperand();

  @override
  bool get isNone => true;

  static const instance = NoneOperand();
}

/// An immediate value operand.
class Imm extends Operand {
  /// The immediate value.
  final int value;

  /// Size hint in bits (8, 16, 32, 64), or null for automatic.
  final int? bits;

  const Imm(this.value, {this.bits});

  /// Creates an 8-bit immediate.
  const Imm.i8(this.value) : bits = 8;

  /// Creates a 16-bit immediate.
  const Imm.i16(this.value) : bits = 16;

  /// Creates a 32-bit immediate.
  const Imm.i32(this.value) : bits = 32;

  /// Creates a 64-bit immediate.
  const Imm.i64(this.value) : bits = 64;

  @override
  bool get isImm => true;

  /// Whether this immediate fits in 8 bits (signed).
  bool get fitsInI8 => value >= -128 && value <= 127;

  /// Whether this immediate fits in 8 bits (unsigned).
  bool get fitsInU8 => value >= 0 && value <= 255;

  /// Whether this immediate fits in 16 bits (signed).
  bool get fitsInI16 => value >= -32768 && value <= 32767;

  /// Whether this immediate fits in 16 bits (unsigned).
  bool get fitsInU16 => value >= 0 && value <= 65535;

  /// Whether this immediate fits in 32 bits (signed).
  bool get fitsInI32 => value >= -2147483648 && value <= 2147483647;

  /// Whether this immediate fits in 32 bits (unsigned).
  bool get fitsInU32 => value >= 0 && value <= 4294967295;

  @override
  String toString() => 'Imm($value${bits != null ? ', $bits bits' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Imm && other.value == value && other.bits == bits;

  @override
  int get hashCode => Object.hash(value, bits);
}

/// A label reference operand.
class LabelOp extends Operand {
  /// The label.
  final Label label;

  const LabelOp(this.label);

  @override
  bool get isLabel => true;

  @override
  String toString() => 'LabelOp(${label.id})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LabelOp && other.label == label;

  @override
  int get hashCode => label.hashCode;
}

/// Register type categories.
enum RegType {
  /// No register / unknown.
  none,

  /// General purpose register.
  gp,

  /// Vector register (SSE/AVX/NEON).
  vec,

  /// Mask register (AVX-512 k registers).
  mask,

  /// Segment register (x86).
  seg,

  /// Control register.
  cr,

  /// Debug register.
  dr,

  /// FPU register (x87).
  st,

  /// BND register (MPX).
  bnd,

  /// TMM register (AMX).
  tmm,

  /// RIP register (x86-64).
  rip,
}

/// Register group (for allocation purposes).
enum RegGroup {
  /// General purpose registers.
  gp,

  /// Vector registers.
  vec,

  /// Mask registers.
  mask,

  /// Other/extra registers.
  extra,
}

/// Base class for register operands.
abstract class BaseReg extends Operand {
  const BaseReg();

  /// The register type.
  RegType get type;

  /// The physical register ID.
  int get id;

  /// The register size in bytes.
  int get size;

  /// The register group.
  RegGroup get group;

  @override
  bool get isReg => true;

  /// Whether this is a general purpose register.
  bool get isGp => type == RegType.gp;

  /// Whether this is a vector register.
  bool get isVec => type == RegType.vec;

  /// Whether this is a physical register (not virtual).
  bool get isPhysical => id >= 0;
}

/// Base class for memory operands.
abstract class BaseMem extends Operand {
  const BaseMem();

  /// The size of the memory access in bytes.
  int get size;

  /// Whether this has a base register.
  bool get hasBase;

  /// Whether this has an index register.
  bool get hasIndex;

  /// Base register (if any).
  BaseReg? get base;

  /// Index register (if any).
  BaseReg? get index;

  /// The displacement/offset.
  int get displacement;

  @override
  bool get isMem => true;
}
