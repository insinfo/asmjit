/// AsmJit x86/x64 Architecture
///
/// Defines x86/x64 registers and constants.
/// Ported from asmjit/x86/x86.h and related files.

import '../core/operand.dart';

/// x86/x64 register IDs.
///
/// These correspond to the physical register encoding in x86.
enum X86RegId {
  rax, // 0
  rcx, // 1
  rdx, // 2
  rbx, // 3
  rsp, // 4
  rbp, // 5
  rsi, // 6
  rdi, // 7
  r8, // 8
  r9, // 9
  r10, // 10
  r11, // 11
  r12, // 12
  r13, // 13
  r14, // 14
  r15, // 15
}

/// x86/x64 general purpose register.
class X86Gp extends BaseReg {
  @override
  final int id;

  /// The register size in bits (8, 16, 32, 64).
  final int bits;

  /// Whether this is the high byte register (AH, BH, CH, DH).
  final bool isHighByte;

  const X86Gp._({
    required this.id,
    required this.bits,
    this.isHighByte = false,
  });

  /// Creates a 64-bit register.
  const X86Gp.r64(this.id)
      : bits = 64,
        isHighByte = false;

  /// Creates a 32-bit register.
  const X86Gp.r32(this.id)
      : bits = 32,
        isHighByte = false;

  /// Creates a 16-bit register.
  const X86Gp.r16(this.id)
      : bits = 16,
        isHighByte = false;

  /// Creates an 8-bit register (low byte).
  const X86Gp.r8(this.id)
      : bits = 8,
        isHighByte = false;

  /// Creates a high byte register (AH, BH, CH, DH).
  const X86Gp.r8h(this.id)
      : bits = 8,
        isHighByte = true;

  @override
  RegType get type => RegType.gp;

  @override
  int get size => bits ~/ 8;

  @override
  RegGroup get group => RegGroup.gp;

  /// Whether this register needs REX prefix (R8-R15 or 64-bit).
  bool get needsRex => id >= 8 || bits == 64;

  /// Whether this register uses the extended encoding (R8-R15).
  bool get isExtended => id >= 8;

  /// Gets the 3-bit encoding for ModR/M.
  int get encoding => id & 0x7;

  /// Returns the 64-bit version of this register.
  X86Gp get r64 => X86Gp.r64(id);

  /// Returns the 32-bit version of this register.
  X86Gp get r32 => X86Gp.r32(id);

  /// Returns the 16-bit version of this register.
  X86Gp get r16 => X86Gp.r16(id);

  /// Returns the 8-bit (low) version of this register.
  X86Gp get r8 => X86Gp.r8(id);

  @override
  String toString() {
    final names64 = [
      'rax',
      'rcx',
      'rdx',
      'rbx',
      'rsp',
      'rbp',
      'rsi',
      'rdi',
      'r8',
      'r9',
      'r10',
      'r11',
      'r12',
      'r13',
      'r14',
      'r15'
    ];
    final names32 = [
      'eax',
      'ecx',
      'edx',
      'ebx',
      'esp',
      'ebp',
      'esi',
      'edi',
      'r8d',
      'r9d',
      'r10d',
      'r11d',
      'r12d',
      'r13d',
      'r14d',
      'r15d'
    ];
    final names16 = [
      'ax',
      'cx',
      'dx',
      'bx',
      'sp',
      'bp',
      'si',
      'di',
      'r8w',
      'r9w',
      'r10w',
      'r11w',
      'r12w',
      'r13w',
      'r14w',
      'r15w'
    ];
    final names8 = [
      'al',
      'cl',
      'dl',
      'bl',
      'spl',
      'bpl',
      'sil',
      'dil',
      'r8b',
      'r9b',
      'r10b',
      'r11b',
      'r12b',
      'r13b',
      'r14b',
      'r15b'
    ];
    final names8h = ['ah', 'ch', 'dh', 'bh'];

    if (isHighByte && id < 4) {
      return names8h[id];
    }

    switch (bits) {
      case 64:
        return names64[id];
      case 32:
        return names32[id];
      case 16:
        return names16[id];
      case 8:
        return names8[id];
      default:
        return 'gp$id($bits)';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is X86Gp &&
          other.id == id &&
          other.bits == bits &&
          other.isHighByte == isHighByte;

  @override
  int get hashCode => Object.hash(id, bits, isHighByte);
}

// =============================================================================
// Predefined 64-bit registers
// =============================================================================

const rax = X86Gp.r64(0);
const rcx = X86Gp.r64(1);
const rdx = X86Gp.r64(2);
const rbx = X86Gp.r64(3);
const rsp = X86Gp.r64(4);
const rbp = X86Gp.r64(5);
const rsi = X86Gp.r64(6);
const rdi = X86Gp.r64(7);
const r8 = X86Gp.r64(8);
const r9 = X86Gp.r64(9);
const r10 = X86Gp.r64(10);
const r11 = X86Gp.r64(11);
const r12 = X86Gp.r64(12);
const r13 = X86Gp.r64(13);
const r14 = X86Gp.r64(14);
const r15 = X86Gp.r64(15);

// =============================================================================
// Predefined 32-bit registers
// =============================================================================

const eax = X86Gp.r32(0);
const ecx = X86Gp.r32(1);
const edx = X86Gp.r32(2);
const ebx = X86Gp.r32(3);
const esp = X86Gp.r32(4);
const ebp = X86Gp.r32(5);
const esi = X86Gp.r32(6);
const edi = X86Gp.r32(7);
const r8d = X86Gp.r32(8);
const r9d = X86Gp.r32(9);
const r10d = X86Gp.r32(10);
const r11d = X86Gp.r32(11);
const r12d = X86Gp.r32(12);
const r13d = X86Gp.r32(13);
const r14d = X86Gp.r32(14);
const r15d = X86Gp.r32(15);

// =============================================================================
// Predefined 16-bit registers
// =============================================================================

const ax = X86Gp.r16(0);
const cx = X86Gp.r16(1);
const dx = X86Gp.r16(2);
const bx = X86Gp.r16(3);
const sp = X86Gp.r16(4);
const bp = X86Gp.r16(5);
const si = X86Gp.r16(6);
const di = X86Gp.r16(7);

// =============================================================================
// Predefined 8-bit registers
// =============================================================================

const al = X86Gp.r8(0);
const cl = X86Gp.r8(1);
const dl = X86Gp.r8(2);
const bl = X86Gp.r8(3);
const spl = X86Gp.r8(4);
const bpl = X86Gp.r8(5);
const sil = X86Gp.r8(6);
const dil = X86Gp.r8(7);
const r8b = X86Gp.r8(8);
const r9b = X86Gp.r8(9);
const r10b = X86Gp.r8(10);
const r11b = X86Gp.r8(11);
const r12b = X86Gp.r8(12);
const r13b = X86Gp.r8(13);
const r14b = X86Gp.r8(14);
const r15b = X86Gp.r8(15);

// High byte registers
const ah = X86Gp.r8h(0);
const ch = X86Gp.r8h(1);
const dh = X86Gp.r8h(2);
const bh = X86Gp.r8h(3);

// =============================================================================
// Argument registers by calling convention
// =============================================================================

/// System V AMD64 ABI argument registers.
class SysVArgs {
  static const arg0 = rdi;
  static const arg1 = rsi;
  static const arg2 = rdx;
  static const arg3 = rcx;
  static const arg4 = r8;
  static const arg5 = r9;

  static const all = [arg0, arg1, arg2, arg3, arg4, arg5];

  /// Return value register.
  static const ret = rax;

  /// Secondary return value register (for 128-bit returns).
  static const ret2 = rdx;
}

/// Windows x64 ABI argument registers.
class Win64Args {
  static const arg0 = rcx;
  static const arg1 = rdx;
  static const arg2 = r8;
  static const arg3 = r9;

  static const all = [arg0, arg1, arg2, arg3];

  /// Return value register.
  static const ret = rax;
}

// =============================================================================
// Callee-saved registers
// =============================================================================

/// Callee-saved (non-volatile) registers for System V AMD64.
const sysVCalleeSaved = [rbx, rbp, r12, r13, r14, r15];

/// Callee-saved (non-volatile) registers for Windows x64.
const win64CalleeSaved = [rbx, rbp, rdi, rsi, r12, r13, r14, r15];

/// Volatile (caller-saved) registers for System V AMD64.
const sysVVolatile = [rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11];

/// Volatile (caller-saved) registers for Windows x64.
const win64Volatile = [rax, rcx, rdx, r8, r9, r10, r11];
