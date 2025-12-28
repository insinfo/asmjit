/// AsmJit x86/x64 Architecture
///
/// Defines x86/x64 registers and constants.
/// Ported from asmjit/x86/x86.h and related files.

import '../core/operand.dart';
import '../core/reg_type.dart';

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

  /// Internal constructors with unique names to avoid collision with static fields.
  const X86Gp._(this.id, this.bits, this.isHighByte);

  /// Helper methods to create registers.
  static X86Gp r64(int id) => X86Gp._(id, 64, false);
  static X86Gp r32(int id) => X86Gp._(id, 32, false);
  static X86Gp r16(int id) => X86Gp._(id, 16, false);
  static X86Gp r8(int id) => X86Gp._(id, 8, false);
  static X86Gp r8h(int id) => X86Gp._(id, 8, true);

  @override
  RegType get type {
    if (isHighByte) return RegType.gp8Hi;
    switch (bits) {
      case 64:
        return RegType.gp64;
      case 32:
        return RegType.gp32;
      case 16:
        return RegType.gp16;
      case 8:
        return RegType.gp8Lo;
      default:
        return RegType.none;
    }
  }

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

  X86Gp get as8 => X86Gp.r8(id);
  X86Gp get as8h => X86Gp.r8h(id);
  X86Gp get as16 => X86Gp.r16(id);
  X86Gp get as32 => X86Gp.r32(id);
  X86Gp get as64 => X86Gp.r64(id);

  @override
  X86Gp toPhys(int physId) {
    if (isHighByte) return X86Gp.r8h(physId);
    switch (bits) {
      case 64:
        return X86Gp.r64(physId);
      case 32:
        return X86Gp.r32(physId);
      case 16:
        return X86Gp.r16(physId);
      case 8:
        return X86Gp.r8(physId);
      default:
        return X86Gp.r64(physId);
    }
  }

  @override
  String toString() {
    if (id < 0) return 'v$id';
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

    if (id >= 16) return 'gp$id';

    if (isHighByte) {
      return id < 4 ? names8h[id] : 'gp${id}h';
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
        return 'gp$id';
    }
  }

  static const rax = X86Gp._(0, 64, false);
  static const rcx = X86Gp._(1, 64, false);
  static const rdx = X86Gp._(2, 64, false);
  static const rbx = X86Gp._(3, 64, false);
  static const rsp = X86Gp._(4, 64, false);
  static const rbp = X86Gp._(5, 64, false);
  static const rsi = X86Gp._(6, 64, false);
  static const rdi = X86Gp._(7, 64, false);
  static const r8_ = X86Gp._(8, 64, false);
  static const r9 = X86Gp._(9, 64, false);
  static const r10 = X86Gp._(10, 64, false);
  static const r11 = X86Gp._(11, 64, false);
  static const r12 = X86Gp._(12, 64, false);
  static const r13 = X86Gp._(13, 64, false);
  static const r14 = X86Gp._(14, 64, false);
  static const r15 = X86Gp._(15, 64, false);

  static const eax = X86Gp._(0, 32, false);
  static const ecx = X86Gp._(1, 32, false);
  static const edx = X86Gp._(2, 32, false);
  static const ebx = X86Gp._(3, 32, false);
  static const esp = X86Gp._(4, 32, false);
  static const ebp = X86Gp._(5, 32, false);
  static const esi = X86Gp._(6, 32, false);
  static const edi = X86Gp._(7, 32, false);

  static const ax = X86Gp._(0, 16, false);
  static const cx = X86Gp._(1, 16, false);
  static const dx = X86Gp._(2, 16, false);
  static const bx = X86Gp._(3, 16, false);
  static const sp = X86Gp._(4, 16, false);
  static const bp = X86Gp._(5, 16, false);
  static const si = X86Gp._(6, 16, false);
  static const di = X86Gp._(7, 16, false);

  static const al = X86Gp._(0, 8, false);
  static const cl = X86Gp._(1, 8, false);
  static const dl = X86Gp._(2, 8, false);
  static const bl = X86Gp._(3, 8, false);

  static const ah = X86Gp._(0, 8, true);
  static const ch = X86Gp._(1, 8, true);
  static const dh = X86Gp._(2, 8, true);
  static const bh = X86Gp._(3, 8, true);
}

// Global aliases to match AsmJit/C++ usage more closely
const rax = X86Gp.rax;
const rcx = X86Gp.rcx;
const rdx = X86Gp.rdx;
const rbx = X86Gp.rbx;
const rsp = X86Gp.rsp;
const rbp = X86Gp.rbp;
const rsi = X86Gp.rsi;
const rdi = X86Gp.rdi;
const r8 = X86Gp.r8_;
const r9 = X86Gp.r9;
const r10 = X86Gp.r10;
const r11 = X86Gp.r11;
const r12 = X86Gp.r12;
const r13 = X86Gp.r13;
const r14 = X86Gp.r14;
const r15 = X86Gp.r15;

const eax = X86Gp.eax;
const ecx = X86Gp.ecx;
const edx = X86Gp.edx;
const ebx = X86Gp.ebx;
const esp = X86Gp.esp;
const ebp = X86Gp.ebp;
const esi = X86Gp.esi;
const edi = X86Gp.edi;

const ax = X86Gp.ax;
const cx = X86Gp.cx;
const dx = X86Gp.dx;
const bx = X86Gp.bx;
const sp = X86Gp.sp;
const bp = X86Gp.bp;
const si = X86Gp.si;
const di = X86Gp.di;

const al = X86Gp.al;
const cl = X86Gp.cl;
const dl = X86Gp.dl;
const bl = X86Gp.bl;

const ah = X86Gp.ah;
const ch = X86Gp.ch;
const dh = X86Gp.dh;
const bh = X86Gp.bh;

const r8d = X86Gp._(8, 32, false);
const r9d = X86Gp._(9, 32, false);
const r10d = X86Gp._(10, 32, false);
const r11d = X86Gp._(11, 32, false);
const r12d = X86Gp._(12, 32, false);
const r13d = X86Gp._(13, 32, false);
const r14d = X86Gp._(14, 32, false);
const r15d = X86Gp._(15, 32, false);

const r8w = X86Gp._(8, 16, false);
const r9w = X86Gp._(9, 16, false);
const r10w = X86Gp._(10, 16, false);
const r11w = X86Gp._(11, 16, false);
const r12w = X86Gp._(12, 16, false);
const r13w = X86Gp._(13, 16, false);
const r14w = X86Gp._(14, 16, false);
const r15w = X86Gp._(15, 16, false);

const r8b = X86Gp._(8, 8, false);
const r9b = X86Gp._(9, 8, false);
const r10b = X86Gp._(10, 8, false);
const r11b = X86Gp._(11, 8, false);
const r12b = X86Gp._(12, 8, false);
const r13b = X86Gp._(13, 8, false);
const r14b = X86Gp._(14, 8, false);
const r15b = X86Gp._(15, 8, false);

const spl = X86Gp._(4, 8, false);
const bpl = X86Gp._(5, 8, false);
const sil = X86Gp._(6, 8, false);
const dil = X86Gp._(7, 8, false);

// ABI definitions
final x64SystemVArgsGp = [rdi, rsi, rdx, rcx, r8, r9];
final x64WindowsArgsGp = [rcx, rdx, r8, r9];

final x64SystemVPreservedGp = [rbx, rsp, rbp, r12, r13, r14, r15];
final x64WindowsPreservedGp = [rbx, rsp, rbp, rsi, rdi, r12, r13, r14, r15];

final x64SystemVVolatileGp = [rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11];
final x64WindowsVolatileGp = [rax, rcx, rdx, r8, r9, r10, r11];

final win64CalleeSaved = x64WindowsPreservedGp;
final sysVCalleeSaved = x64SystemVPreservedGp;
