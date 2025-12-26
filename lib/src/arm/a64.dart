/// AsmJit ARM64/AArch64 Backend
///
/// Provides registers, operands and instruction encoding for ARM64.
/// Ported from asmjit/arm/a64globals.h and a64operand.h

// ===========================================================================
// ARM64 Register Classes
// ===========================================================================

/// ARM64 General Purpose Register (32-bit or 64-bit).
class A64Gp {
  /// Register ID (0-31).
  final int id;

  /// Size in bits (32 or 64).
  final int sizeBits;

  const A64Gp(this.id, this.sizeBits);

  /// Is this a 64-bit register (X register).
  bool get is64Bit => sizeBits == 64;

  /// Is this a 32-bit register (W register).
  bool get is32Bit => sizeBits == 32;

  /// Size in bytes.
  int get size => sizeBits ~/ 8;

  /// Register encoding.
  int get encoding => id & 0x1F;

  /// Get the 64-bit version of this register.
  A64Gp get x => A64Gp(id, 64);

  /// Get the 32-bit version of this register.
  A64Gp get w => A64Gp(id, 32);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is A64Gp && other.id == id && other.sizeBits == sizeBits;

  @override
  int get hashCode => Object.hash(id, sizeBits);

  @override
  String toString() {
    if (id == 31) {
      return is64Bit ? 'sp' : 'wsp';
    }
    if (id == 30) {
      return is64Bit ? 'lr' : 'w30';
    }
    if (id == 29) {
      return is64Bit ? 'fp' : 'w29';
    }
    return is64Bit ? 'x$id' : 'w$id';
  }
}

/// ARM64 SIMD/FP Register (8, 16, 32, 64, or 128 bits).
class A64Vec {
  /// Register ID (0-31).
  final int id;

  /// Size in bits.
  final int sizeBits;

  const A64Vec(this.id, this.sizeBits);

  /// Size in bytes.
  int get size => sizeBits ~/ 8;

  /// Register encoding.
  int get encoding => id & 0x1F;

  /// Get as B (byte, 8-bit).
  A64Vec get b => A64Vec(id, 8);

  /// Get as H (half, 16-bit).
  A64Vec get h => A64Vec(id, 16);

  /// Get as S (single, 32-bit).
  A64Vec get s => A64Vec(id, 32);

  /// Get as D (double, 64-bit).
  A64Vec get d => A64Vec(id, 64);

  /// Get as Q (quad, 128-bit).
  A64Vec get q => A64Vec(id, 128);

  @override
  String toString() {
    final prefix = switch (sizeBits) {
      8 => 'b',
      16 => 'h',
      32 => 's',
      64 => 'd',
      128 => 'q',
      _ => 'v',
    };
    return '$prefix$id';
  }
}

// ===========================================================================
// ARM64 Pre-defined Registers
// ===========================================================================

// 64-bit General Purpose Registers (X0-X30)
const x0 = A64Gp(0, 64);
const x1 = A64Gp(1, 64);
const x2 = A64Gp(2, 64);
const x3 = A64Gp(3, 64);
const x4 = A64Gp(4, 64);
const x5 = A64Gp(5, 64);
const x6 = A64Gp(6, 64);
const x7 = A64Gp(7, 64);
const x8 = A64Gp(8, 64);
const x9 = A64Gp(9, 64);
const x10 = A64Gp(10, 64);
const x11 = A64Gp(11, 64);
const x12 = A64Gp(12, 64);
const x13 = A64Gp(13, 64);
const x14 = A64Gp(14, 64);
const x15 = A64Gp(15, 64);
const x16 = A64Gp(16, 64);
const x17 = A64Gp(17, 64);
const x18 = A64Gp(18, 64);
const x19 = A64Gp(19, 64);
const x20 = A64Gp(20, 64);
const x21 = A64Gp(21, 64);
const x22 = A64Gp(22, 64);
const x23 = A64Gp(23, 64);
const x24 = A64Gp(24, 64);
const x25 = A64Gp(25, 64);
const x26 = A64Gp(26, 64);
const x27 = A64Gp(27, 64);
const x28 = A64Gp(28, 64);
const x29 = A64Gp(29, 64); // Frame Pointer (FP)
const x30 = A64Gp(30, 64); // Link Register (LR)

/// Special aliases
const fp = x29; // Frame Pointer
const lr = x30; // Link Register
const sp = A64Gp(31, 64); // Stack Pointer
const xzr = A64Gp(31, 64); // Zero Register (64-bit)

// 32-bit General Purpose Registers (W0-W30)
const w0 = A64Gp(0, 32);
const w1 = A64Gp(1, 32);
const w2 = A64Gp(2, 32);
const w3 = A64Gp(3, 32);
const w4 = A64Gp(4, 32);
const w5 = A64Gp(5, 32);
const w6 = A64Gp(6, 32);
const w7 = A64Gp(7, 32);
const w8 = A64Gp(8, 32);
const w9 = A64Gp(9, 32);
const w10 = A64Gp(10, 32);
const w11 = A64Gp(11, 32);
const w12 = A64Gp(12, 32);
const w13 = A64Gp(13, 32);
const w14 = A64Gp(14, 32);
const w15 = A64Gp(15, 32);
const w16 = A64Gp(16, 32);
const w17 = A64Gp(17, 32);
const w18 = A64Gp(18, 32);
const w19 = A64Gp(19, 32);
const w20 = A64Gp(20, 32);
const w21 = A64Gp(21, 32);
const w22 = A64Gp(22, 32);
const w23 = A64Gp(23, 32);
const w24 = A64Gp(24, 32);
const w25 = A64Gp(25, 32);
const w26 = A64Gp(26, 32);
const w27 = A64Gp(27, 32);
const w28 = A64Gp(28, 32);
const w29 = A64Gp(29, 32);
const w30 = A64Gp(30, 32);
const wsp = A64Gp(31, 32); // Stack Pointer (32-bit)
const wzr = A64Gp(31, 32); // Zero Register (32-bit)

// 128-bit SIMD/FP Registers (V0-V31)
const v0 = A64Vec(0, 128);
const v1 = A64Vec(1, 128);
const v2 = A64Vec(2, 128);
const v3 = A64Vec(3, 128);
const v4 = A64Vec(4, 128);
const v5 = A64Vec(5, 128);
const v6 = A64Vec(6, 128);
const v7 = A64Vec(7, 128);
const v8 = A64Vec(8, 128);
const v9 = A64Vec(9, 128);
const v10 = A64Vec(10, 128);
const v11 = A64Vec(11, 128);
const v12 = A64Vec(12, 128);
const v13 = A64Vec(13, 128);
const v14 = A64Vec(14, 128);
const v15 = A64Vec(15, 128);
const v16 = A64Vec(16, 128);
const v17 = A64Vec(17, 128);
const v18 = A64Vec(18, 128);
const v19 = A64Vec(19, 128);
const v20 = A64Vec(20, 128);
const v21 = A64Vec(21, 128);
const v22 = A64Vec(22, 128);
const v23 = A64Vec(23, 128);
const v24 = A64Vec(24, 128);
const v25 = A64Vec(25, 128);
const v26 = A64Vec(26, 128);
const v27 = A64Vec(27, 128);
const v28 = A64Vec(28, 128);
const v29 = A64Vec(29, 128);
const v30 = A64Vec(30, 128);
const v31 = A64Vec(31, 128);

// 64-bit FP/SIMD Registers (D0-D31)
const d0 = A64Vec(0, 64);
const d1 = A64Vec(1, 64);
const d2 = A64Vec(2, 64);
const d3 = A64Vec(3, 64);
const d4 = A64Vec(4, 64);
const d5 = A64Vec(5, 64);
const d6 = A64Vec(6, 64);
const d7 = A64Vec(7, 64);

// 32-bit FP Registers (S0-S31)
const s0 = A64Vec(0, 32);
const s1 = A64Vec(1, 32);
const s2 = A64Vec(2, 32);
const s3 = A64Vec(3, 32);
const s4 = A64Vec(4, 32);
const s5 = A64Vec(5, 32);
const s6 = A64Vec(6, 32);
const s7 = A64Vec(7, 32);

// ===========================================================================
// ARM64 Condition Codes
// ===========================================================================

/// ARM64 Condition codes for conditional instructions.
enum A64Cond {
  /// Equal (Z == 1).
  eq(0),

  /// Not equal (Z == 0).
  ne(1),

  /// Carry set / unsigned higher or same (C == 1).
  cs(2),

  /// Carry clear / unsigned lower (C == 0).
  cc(3),

  /// Minus / negative (N == 1).
  mi(4),

  /// Plus / positive or zero (N == 0).
  pl(5),

  /// Overflow (V == 1).
  vs(6),

  /// No overflow (V == 0).
  vc(7),

  /// Unsigned higher (C == 1 && Z == 0).
  hi(8),

  /// Unsigned lower or same (C == 0 || Z == 1).
  ls(9),

  /// Signed greater than or equal (N == V).
  ge(10),

  /// Signed less than (N != V).
  lt(11),

  /// Signed greater than (Z == 0 && N == V).
  gt(12),

  /// Signed less than or equal (Z == 1 || N != V).
  le(13),

  /// Always (unconditional).
  al(14),

  /// Never (reserved).
  nv(15);

  final int encoding;
  const A64Cond(this.encoding);

  /// Get the inverse condition.
  A64Cond get inverse => A64Cond.values.firstWhere(
        (c) => c.encoding == (encoding ^ 1),
        orElse: () => this,
      );
}

/// Aliases for condition codes.
const hs = A64Cond.cs; // Unsigned higher or same
const lo = A64Cond.cc; // Unsigned lower

// ===========================================================================
// ARM64 Memory Operand
// ===========================================================================

/// ARM64 Memory operand.
class A64Mem {
  /// Base register.
  final A64Gp? base;

  /// Offset (immediate).
  final int offset;

  /// Index register (for indexed addressing).
  final A64Gp? index;

  /// Shift amount for index.
  final int shift;

  /// Addressing mode.
  final A64AddrMode addrMode;

  const A64Mem._({
    this.base,
    this.offset = 0,
    this.index,
    this.shift = 0,
    this.addrMode = A64AddrMode.offset,
  });

  /// [base] - Simple base register addressing.
  factory A64Mem.base(A64Gp base) {
    return A64Mem._(base: base);
  }

  /// [base, #offset] - Base + immediate offset.
  factory A64Mem.baseOffset(A64Gp base, int offset) {
    return A64Mem._(base: base, offset: offset);
  }

  /// [base], #offset - Post-index.
  factory A64Mem.postIndex(A64Gp base, int offset) {
    return A64Mem._(
        base: base, offset: offset, addrMode: A64AddrMode.postIndex);
  }

  /// [base, #offset]! - Pre-index.
  factory A64Mem.preIndex(A64Gp base, int offset) {
    return A64Mem._(base: base, offset: offset, addrMode: A64AddrMode.preIndex);
  }

  /// [base, index] - Base + index register.
  factory A64Mem.baseIndex(A64Gp base, A64Gp index, {int shift = 0}) {
    return A64Mem._(base: base, index: index, shift: shift);
  }

  /// Has base register.
  bool get hasBase => base != null;

  /// Has index register.
  bool get hasIndex => index != null;

  /// Is post-index mode.
  bool get isPostIndex => addrMode == A64AddrMode.postIndex;

  /// Is pre-index mode.
  bool get isPreIndex => addrMode == A64AddrMode.preIndex;

  @override
  String toString() {
    final buf = StringBuffer('[');

    if (base != null) {
      buf.write(base);
    }

    if (index != null) {
      buf.write(', ');
      buf.write(index);
      if (shift != 0) {
        buf.write(', lsl #$shift');
      }
    } else if (offset != 0) {
      buf.write(', #$offset');
    }

    buf.write(']');

    if (isPostIndex && offset != 0) {
      return '[${base}], #$offset';
    }
    if (isPreIndex) {
      buf.write('!');
    }

    return buf.toString();
  }
}

/// ARM64 Addressing modes.
enum A64AddrMode {
  /// [base, #offset]
  offset,

  /// [base], #offset
  postIndex,

  /// [base, #offset]!
  preIndex,
}

// ===========================================================================
// ARM64 Shift Operations
// ===========================================================================

/// ARM64 Shift types.
enum A64Shift {
  /// Logical shift left.
  lsl(0),

  /// Logical shift right.
  lsr(1),

  /// Arithmetic shift right.
  asr(2),

  /// Rotate right.
  ror(3);

  final int encoding;
  const A64Shift(this.encoding);
}

/// An immediate value with optional shift.
class A64Imm {
  final int value;
  final A64Shift shift;
  final int shiftAmount;

  const A64Imm(this.value, {this.shift = A64Shift.lsl, this.shiftAmount = 0});

  /// Create a simple immediate.
  factory A64Imm.imm(int value) => A64Imm(value);

  /// Create an immediate with LSL shift.
  factory A64Imm.lsl(int value, int amount) =>
      A64Imm(value, shift: A64Shift.lsl, shiftAmount: amount);

  @override
  String toString() {
    if (shiftAmount == 0) return '#$value';
    return '#$value, ${shift.name} #$shiftAmount';
  }
}

// ===========================================================================
// ARM64 Calling Convention
// ===========================================================================

/// AAPCS64 argument registers.
const List<A64Gp> aapcs64ArgRegs = [x0, x1, x2, x3, x4, x5, x6, x7];

/// AAPCS64 FP/SIMD argument registers.
const List<A64Vec> aapcs64VecArgRegs = [v0, v1, v2, v3, v4, v5, v6, v7];

/// AAPCS64 callee-saved registers.
const List<A64Gp> aapcs64CalleeSaved = [
  x19,
  x20,
  x21,
  x22,
  x23,
  x24,
  x25,
  x26,
  x27,
  x28,
  x29,
  x30
];

/// AAPCS64 return register.
const A64Gp aapcs64RetReg = x0;
