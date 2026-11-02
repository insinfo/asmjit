// Port of `x86::Assembler::_emit()` (asmjit/x86/x86assembler.cpp).
//
// The upstream function is a `switch` over the instruction encoding whose
// cases `goto` shared low-level emitters (EmitX86R, EmitX86M, EmitVexEvexM,
// ...). Dart has no `goto`, so every case and label of the upstream function
// is a state of [_S] and `goto X` is `s = _S.X; continue loop;`. The body was
// translated mechanically from upstream and then fixed by hand; keep it close
// to upstream so it can be diffed against it.
//
// Operands are adapted to upstream's model by [_Op] (operand type, register
// type and id, memory base/index types, ...).

// ignore_for_file: dead_code, non_constant_identifier_names, constant_identifier_names, unused_local_variable, unnecessary_parenthesis, curly_braces_in_flow_control_structures, unused_element, prefer_final_locals, no_leading_underscores_for_local_identifiers, unnecessary_null_comparison, unnecessary_non_null_assertion, unused_field
import 'dart:math' as math;

import '../core/arch.dart';
import '../core/code_buffer.dart';
import '../core/code_holder.dart';
import '../core/fixup.dart';
import '../core/emitter.dart' show EncodingOptions;
import '../core/labels.dart';
import '../core/operand.dart' show BaseReg, Imm, LabelOp;
import 'x86.dart';
import 'x86_inst_db.g.dart';
import 'x86_opcode.dart';
import 'x86_operands.dart';

/// `InstOptions` (asmjit/core/inst.h): the instruction options the x86
/// encoder understands.
abstract final class X86EmitOptions {
  static const int kNone = 0;
  static const int kReserved = 0x00000001;

  /// `InstOptions::kUnfollow`: the register allocator does not follow the
  /// jump (it has no successors in the control flow graph).
  static const int kUnfollow = 0x00000002;
  static const int kShortForm = 0x00000010;
  static const int kLongForm = 0x00000020;
  static const int kTaken = 0x00000040;
  static const int kNotTaken = 0x00000080;
  static const int kX86_ModMR = 0x00000100;
  static const int kX86_ModRM = 0x00000200;
  static const int kX86_Vex3 = 0x00000400;
  static const int kX86_Vex = 0x00000800;
  static const int kX86_Evex = 0x00001000;
  static const int kX86_Lock = 0x00002000;
  static const int kX86_Rep = 0x00004000;
  static const int kX86_Repne = 0x00008000;
  static const int kX86_XAcquire = 0x00010000;
  static const int kX86_XRelease = 0x00020000;
  static const int kX86_ER = 0x00040000;
  static const int kX86_SAE = 0x00080000;
  static const int kX86_RN_SAE = 0x00000000;
  static const int kX86_RD_SAE = 0x00200000;
  static const int kX86_RU_SAE = 0x00400000;
  static const int kX86_RZ_SAE = 0x00600000;
  static const int kX86_ZMask = 0x00800000;
  static const int kX86_ERMask = kX86_RZ_SAE;
  static const int kX86_AVX512Mask = 0x00FC0000;
  static const int kX86_OpCodeB = 0x01000000;
  static const int kX86_OpCodeX = 0x02000000;
  static const int kX86_OpCodeR = 0x04000000;
  static const int kX86_OpCodeW = 0x08000000;
  static const int kX86_Rex = 0x40000000;
  static const int kX86_InvalidRex = 0x80000000;
}

typedef _IO = X86EmitOptions;

/// `EncodingOptions::kPredictedJumps`.
const int _kPredictedJumps = 0x00000010;

/// Upstream `RegType` values (asmjit/core/operand.h).
abstract final class _RT {
  static const int kNone = 0;
  static const int kLabelTag = 1;
  static const int kGp8Lo = 2;
  static const int kGp8Hi = 3;
  static const int kGp16 = 4;
  static const int kGp32 = 5;
  static const int kGp64 = 6;
  static const int kVec8 = 7;
  static const int kVec16 = 8;
  static const int kVec32 = 9;
  static const int kVec64 = 10;
  static const int kVec128 = 11;
  static const int kVec256 = 12;
  static const int kVec512 = 13;
  static const int kVec1024 = 14;
  static const int kVecNLen = 15;
  static const int kMask = 16;
  static const int kTile = 17;
  static const int kSegment = 25;
  static const int kControl = 26;
  static const int kDebug = 27;
  static const int kX86_Mm = 28;
  static const int kX86_St = 29;
  static const int kX86_Bnd = 30;
  static const int kPC = 31;
}

/// `Mem::AddrType`.
abstract final class _Addr {
  static const int kDefault = 0;
  static const int kAbs = 1;
  static const int kRel = 2;
}

/// Upstream operand types.
const int _kOpNone = 0, _kOpReg = 1, _kOpMem = 2, _kOpImm = 4, _kOpLabel = 5;

/// Physical ids (`Gp::kIdAx`...) and segment ids (`SReg::kIdEs`...).
const int _kIdAx = 0, _kIdCx = 1, _kIdDx = 2, _kIdBx = 3;
const int _kIdSp = 4, _kIdBp = 5, _kIdSi = 6, _kIdDi = 7;
const int _kSegEs = 1, _kSegCs = 2, _kSegSs = 3, _kSegDs = 4;
const int _kSegFs = 5, _kSegGs = 6, _kSegCount = 7;

// X86MemInfo bits.
const int _kMemInfo0 = 0x00;
const int _kMemInfoBaseGp = 0x01;
const int _kMemInfoIndex = 0x02;
const int _kMemInfoBaseLabel = 0x10;
const int _kMemInfoBaseRip = 0x20;
const int _kMemInfo67H_X86 = 0x40;
const int _kMemInfo67H_X64 = 0x80;
const int _kMemInfo67H_Mask = 0xC0;

// X86Byte.
const int _kByteRex = 0x40;
const int _kByteRexW = 0x08;
const int _kByteInvalidRex = 0x80;
const int _kByteVex2 = 0xC5;
const int _kByteVex3 = 0xC4;
const int _kByteXop3 = 0x8F;
const int _kByteEvex = 0x62;

const int _kVexVVVVVShift = 7;
const int _kVexVVVVVMask = 0x1F << _kVexVVVVVShift;

/// Operand in upstream's terms.
final class _Op {
  final int opType;

  // Register.
  final int regType;
  final int _id;

  // Memory.
  final int baseType;
  final int baseId;
  final int indexType;
  final int indexId;
  final int shift;
  final int offset;
  final int memSize;
  final int segmentId;
  final int addrType;
  final int broadcast;

  // Immediate.
  final int imm;

  // Label (operand or memory base).
  final Label? label;

  const _Op._({
    this.opType = _kOpNone,
    this.regType = _RT.kNone,
    int id = 0,
    this.baseType = _RT.kNone,
    this.baseId = 0,
    this.indexType = _RT.kNone,
    this.indexId = 0,
    this.shift = 0,
    this.offset = 0,
    this.memSize = 0,
    this.segmentId = 0,
    this.addrType = _Addr.kDefault,
    this.broadcast = 0,
    this.imm = 0,
    this.label,
  }) : _id = id;

  static const none = _Op._();

  static int _gpType(X86Gp r) => switch (r.bits) {
        8 => r.isHighByte ? _RT.kGp8Hi : _RT.kGp8Lo,
        16 => _RT.kGp16,
        32 => _RT.kGp32,
        _ => _RT.kGp64,
      };

  /// Upstream `RegType` of [r] (the port's [RegType] uses the same values).
  static int? _regTypeOf(Object r) => r is X86Gp
      ? _gpType(r)
      : r is BaseReg
          ? r.type.value
          : null;

  factory _Op.of(Object? o) {
    switch (o) {
      case null:
        return none;
      case int():
        return _Op._(opType: _kOpImm, imm: o);
      case Imm():
        return _Op._(opType: _kOpImm, imm: o.value);
      case Label():
        return _Op._(opType: _kOpLabel, label: o, id: o.id);
      case LabelOp():
        return _Op._(opType: _kOpLabel, label: o.label, id: o.label.id);
      case X86Mem():
        final base = o.base, index = o.index;
        final label = o.label;
        return _Op._(
          opType: _kOpMem,
          baseType: label != null
              ? _RT.kLabelTag
              : base == null
                  ? _RT.kNone
                  : _regTypeOf(base) ??
                      (throw ArgumentError('x86: invalid base $base')),
          baseId: label?.id ?? base?.id ?? 0,
          indexType: index == null
              ? _RT.kNone
              : _regTypeOf(index) ??
                  (throw ArgumentError('x86: invalid index $index')),
          indexId: index?.id ?? 0,
          shift: switch (o.scale) {
            1 => 0,
            2 => 1,
            4 => 2,
            8 => 3,
            _ => throw ArgumentError('x86: invalid scale ${o.scale}'),
          },
          offset: o.displacement,
          memSize: o.size,
          segmentId: o.segment == null ? 0 : o.segment!.index + 1,
          addrType: o.addrType,
          broadcast: o.broadcast,
          label: label,
        );
      case X86RipMem():
        return _Op._(
          opType: _kOpMem,
          baseType: o.label != null ? _RT.kLabelTag : _RT.kPC,
          baseId: o.label?.id ?? 0,
          offset: o.displacement,
          memSize: o.size,
          broadcast: o.broadcast,
          label: o.label,
        );
      default:
        final t = _regTypeOf(o);
        if (t == null) throw ArgumentError('x86: unsupported operand $o');
        return _Op._(opType: _kOpReg, regType: t, id: (o as dynamic).id as int);
    }
  }

  int get id => opType == _kOpMem ? baseId : _id;
  int get immU8 => imm & 0xFF;
  int get immU16 => imm & 0xFFFF;
  int get immU32 => imm & 0xFFFFFFFF;
  int get labelId => label!.id;

  bool isNone() => opType == _kOpNone;
  bool isReg() => opType == _kOpReg;
  bool isMem() => opType == _kOpMem;
  bool isImm() => opType == _kOpImm;
  bool isLabel() => opType == _kOpLabel;

  bool _isReg(int t, [int? id]) =>
      opType == _kOpReg && regType == t && (id == null || _id == id);
  bool isGp([int? id]) =>
      opType == _kOpReg &&
      regType >= _RT.kGp8Lo &&
      regType <= _RT.kGp64 &&
      (id == null || _id == id);
  bool isGp8() => isReg() && (regType == _RT.kGp8Lo || regType == _RT.kGp8Hi);
  bool isGp8Hi() => _isReg(_RT.kGp8Hi);
  bool isGp16([int? id]) => _isReg(_RT.kGp16, id);
  bool isGp32([int? id]) => _isReg(_RT.kGp32, id);
  bool isGp64([int? id]) => _isReg(_RT.kGp64, id);
  bool isVec128([int? id]) => _isReg(_RT.kVec128, id);
  bool isMmReg() => _isReg(_RT.kX86_Mm);
  bool isMaskReg() => _isReg(_RT.kMask);
  bool isSegmentReg() => _isReg(_RT.kSegment);
  bool isControlReg() => _isReg(_RT.kControl);
  bool isDebugReg() => _isReg(_RT.kDebug);

  /// `x86_rm_size()`: the size of a register or memory operand.
  int get x86RmSize => opType == _kOpReg ? _regSize(regType) : memSize;
  int get size => memSize;

  static int _regSize(int t) => switch (t) {
        _RT.kGp8Lo || _RT.kGp8Hi => 1,
        _RT.kGp16 => 2,
        _RT.kGp32 => 4,
        _RT.kGp64 => 8,
        _RT.kVec128 => 16,
        _RT.kVec256 => 32,
        _RT.kVec512 => 64,
        _RT.kMask || _RT.kX86_Mm => 8,
        _RT.kSegment => 2,
        _ => 0,
      };

  // Memory.
  int get baseAndIndexTypes => baseType | (indexType << 5);
  int get offsetLo32 => _i32(offset);
  int get offsetHi32 => offset >> 32;
  bool hasOffset() => offset != 0;
  bool hasBaseReg() => baseType != _RT.kNone && baseType != _RT.kLabelTag;
  bool hasIndexReg() => indexType != _RT.kNone;
  bool hasIndex() => indexType != _RT.kNone;
  bool hasBaseOrIndex() => baseType != _RT.kNone || indexType != _RT.kNone;
  bool hasSegment() => segmentId != 0;
  bool hasBroadcast() => broadcast != 0;
  int get getBroadcast => broadcast;
  bool isAddrRel() => addrType == _Addr.kRel;
}

int _u8(int v) => v & 0xFF;
int _u16(int v) => v & 0xFFFF;
int _u32(Object v) => _b(v) & 0xFFFFFFFF;
int _i32(int v) => (v & 0xFFFFFFFF).toSigned(32);
int _signExtendInt32(int v) => _i32(v);
bool _isIntN(int n, int v) => v >= -(1 << (n - 1)) && v < (1 << (n - 1));
bool _isUintN(int n, int v) => v >= 0 && (n >= 64 || v < (1 << n));
bool _test(int a, int b) => (a & b) != 0;
bool _boolOr(bool a, bool b) => a || b;
int _max(int a, int b) => math.max(a, b);
int _ctz(int v) {
  var n = 0;
  while (v & 1 == 0 && n < 64) {
    v >>>= 1;
    n++;
  }
  return n;
}

// `Opcode` builders (x86opcode_p.h).
int _add(int op, Object x) => op + _b(x);
int _addW(int op) => op | X86Opcode.kW;
int _add66h(int op) => op | X86Opcode.kPP_66;
int _addWIf(int op, Object exp) => op | (_b(exp) << X86Opcode.kW_Shift);
int _add66hIf(int op, Object exp) => op | (_b(exp) << X86Opcode.kPP_Shift);
int _addWBySize(int op, int size) => _addWIf(op, size == 8);
int _add66hBySize(int op, int size) => _add66hIf(op, size == 2);
int _addPrefixBySize(int op, int size) => op | X86Opcode.prefixBySize(size);
int _addArithBySize(int op, int size) => op | X86Opcode.arithBySize(size);
int _forceEvex(int op) => op | X86Opcode.kMM_ForceEvex;
int _forceEvexIf(int op, Object exp) => op | (_b(exp) << 12);
int _b(Object exp) => exp is bool ? (exp ? 1 : 0) : exp as int;
bool _hasW(int op) => (op & X86Opcode.kW) != 0;

/// `extract_rex()`: REX.[B|X|R|W] of the opcode and the options (the byte
/// also holds kX86_Rex (0x40) and kX86_InvalidRex (0x80)).
int _extractRex(int op, int options) =>
    _u32(op | options) >> X86Opcode.kREX_Shift;

int _extractLLMmmmm(int op, int options) {
  final llMmmmm = op & (X86Opcode.kLL_Mask | X86Opcode.kMM_Mask);
  final vexEvex = options & _IO.kX86_Evex;
  return (llMmmmm | vexEvex) >> X86Opcode.kMM_Shift;
}

int encodeMod(int m, int o, int rm) => (m << 6) + (o << 3) + rm;
int encodeSib(int s, int i, int b) => (s << 6) + (i << 3) + b;
bool _isRexInvalid(int rex) => rex > _kByteInvalidRex;
int packRegAndVvvvv(int regId, int vvvvvId) =>
    regId + (vvvvvId << _kVexVVVVVShift);

bool isImplicitMem(_Op op, int base) =>
    op.isMem() && op.baseId == base && !op.hasOffset();

bool isMmxOrXmm(_Op reg) =>
    reg.regType == _RT.kX86_Mm || reg.regType == _RT.kVec128;

bool isJmpOrCall(int instId) =>
    instId == X86InstId.kJmp || instId == X86InstId.kCall;

const _opcodePpTable = [0x00, 0x66, 0xF3, 0xF2, 0x00, 0x00, 0x00, 0x9B];

/// `opcode_mm_table`: 2-byte/3-byte opcode prefix data (size, bytes).
const _opcodeMmTable = [
  (0, 0x00, 0x00), (1, 0x0F, 0x00), (2, 0x0F, 0x38), (2, 0x0F, 0x3A), //
  (2, 0x0F, 0x01), (0, 0x00, 0x00), (0, 0x00, 0x00), (0, 0x00, 0x00),
  (0, 0x00, 0x00), (0, 0x00, 0x00), (0, 0x00, 0x00), (0, 0x00, 0x00),
  (0, 0x00, 0x00), (0, 0x00, 0x00), (0, 0x00, 0x00), (0, 0x00, 0x00),
];

const _segmentPrefixTable = [0x00, 0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65, 0x00];

const _opcodePushSregTable = [
  0x00, 0x06, 0x0E, 0x16, 0x1E, //
  (0x01 << X86Opcode.kMM_Shift) | 0xA0, (0x01 << X86Opcode.kMM_Shift) | 0xA8,
  0x00,
];

const _opcodePopSregTable = [
  0x00, 0x07, 0x00, 0x17, 0x1F, //
  (0x01 << X86Opcode.kMM_Shift) | 0xA1, (0x01 << X86Opcode.kMM_Shift) | 0xA9,
  0x00,
];

/// `mem_info_table` (`X86MemInfo_T`), indexed by `base_and_index_types()`.
final List<int> memInfoTable = List.generate(1024, (x) {
  final b = x & 0x1F, i = (x >> 5) & 0x1F;
  final base = (b >= _RT.kGp16 && b <= _RT.kGp64)
      ? _kMemInfoBaseGp
      : b == _RT.kPC
          ? _kMemInfoBaseRip
          : b == _RT.kLabelTag
              ? _kMemInfoBaseLabel
              : 0;
  final index = (i >= _RT.kGp16 && i <= _RT.kGp64) ||
          (i >= _RT.kVec128 && i <= _RT.kVec512)
      ? _kMemInfoIndex
      : 0;
  int h67 = 0;
  final bGp16 = b == _RT.kGp16, bGp32 = b == _RT.kGp32;
  final bNone = b == _RT.kNone, bLabel = b == _RT.kLabelTag;
  final iVec = i == _RT.kVec128 || i == _RT.kVec256 || i == _RT.kVec512;
  if ((bGp16 && i == _RT.kNone) ||
      (bNone && i == _RT.kGp16) ||
      (bGp16 && i == _RT.kGp16) ||
      (bGp16 && iVec) ||
      (bLabel && i == _RT.kGp16)) {
    h67 = _kMemInfo67H_X86;
  } else if ((bGp32 && i == _RT.kNone) ||
      (bNone && i == _RT.kGp32) ||
      (bGp32 && i == _RT.kGp32) ||
      (bGp32 && iVec) ||
      (bLabel && i == _RT.kGp32)) {
    h67 = _kMemInfo67H_X64;
  }
  return base | index | h67 | 0x04 | 0x08;
});

/// `vex_prefix_table`: VEX3 or XOP xor bits indexed by `mmmmm`.
final List<int> vexPrefixTable = List.generate(
    16,
    (x) =>
        ((x & 0x08) != 0 ? _kByteXop3 : _kByteVex3) |
        (0xF << 19) |
        (0x7 << 13));

/// `ll_by_size_div_16_table`.
final List<int> _llBySizeDiv16Table = List.generate(
    16,
    (x) => (x & (64 >> 4)) != 0
        ? 2 << X86Opcode.kLL_Shift
        : (x & (32 >> 4)) != 0
            ? 1 << X86Opcode.kLL_Shift
            : 0);

/// `ll_by_reg_type_table`.
final List<int> llByRegTypeTable = List.generate(
    32,
    (x) => x == _RT.kVec512
        ? 2 << X86Opcode.kLL_Shift
        : x == _RT.kVec256
            ? 1 << X86Opcode.kLL_Shift
            : 0);

/// `cdisp8_shl_table` (`X86CDisp8SHL_T`), indexed by `CDTT[4:3]|W[2]|LL[1:0]`.
final List<int> cdisp8ShlTable = List.generate(32, (x) {
  final tt = (x >> 3) << X86Opcode.kCDTT_Shift;
  final ll = x & 0x3, w = (x >> 2) & 0x1;
  final v = tt == X86Opcode.kCDTT_None
      ? 0
      : tt == X86Opcode.kCDTT_ByLL
          ? (ll == 0 ? 0 : (ll == 1 ? 1 : 2))
          : tt == X86Opcode.kCDTT_T1W
              ? (ll == 0 ? w : (ll == 1 ? 1 + w : 2 + w))
              : tt == X86Opcode.kCDTT_DUP
                  ? (ll == 0 ? 0 : (ll == 1 ? 2 : 3))
                  : 0;
  return v << X86Opcode.kCDSHL_Shift;
});

/// `mod16_base_table` (32-bit mode only).
const mod16BaseTable = [0xFF, 0xFF, 0xFF, 0x07, 0xFF, 0x06, 0x04, 0x05];

/// `mod16_base_index_table` (32-bit mode only).
final List<int> mod16BaseIndexTable = List.generate(64, (x) {
  final b = x >> 3, i = x & 0x7;
  if ((b == _kIdBx && i == _kIdSi) || (b == _kIdSi && i == _kIdBx)) return 0x00;
  if ((b == _kIdBx && i == _kIdDi) || (b == _kIdDi && i == _kIdBx)) return 0x01;
  if ((b == _kIdBp && i == _kIdSi) || (b == _kIdSi && i == _kIdBp)) return 0x02;
  if ((b == _kIdBp && i == _kIdDi) || (b == _kIdDi && i == _kIdBp)) return 0x03;
  return 0xFF;
});

int opcodeLByVmem(_Op op) => llByRegTypeTable[op.indexType];
int opcodeLBySize(int size) => _llBySizeDiv16Table[size ~/ 16];

int _forceEvex3MaskInLastBit(int options) =>
    (options & _IO.kX86_Vex3) != 0 ? 1 << 31 : 0;

/// `X86BufferWriter`.
final class _Writer {
  final CodeBuffer buf;
  _Writer(this.buf);

  int get cursor => buf.length;
  int offsetFrom(Object? _) => buf.length;

  void emit8(int v) => buf.emit8(v & 0xFF);
  void emit8If(int v, bool cond) {
    if (cond) buf.emit8(v & 0xFF);
  }

  void emit16uLe(int v) => buf.emit16(v & 0xFFFF);
  void emit32uLe(int v) => buf.emit32(v & 0xFFFFFFFF);
  void emitZeros(int n) => buf.emitZeros(n);

  void emitPp(int opcode) {
    final ppIndex = (opcode >> X86Opcode.kPP_Shift) &
        (X86Opcode.kPP_FPUMask >> X86Opcode.kPP_Shift);
    emit8If(_opcodePpTable[ppIndex], ppIndex != 0);
  }

  void emitMmAndOpcode(int opcode) {
    final mmIndex = (opcode & X86Opcode.kMM_Mask) >> X86Opcode.kMM_Shift;
    final (size, d0, d1) = _opcodeMmTable[mmIndex];
    emit8If(d0, size > 0);
    emit8If(d1, size > 1);
    emit8(opcode);
  }

  void emitSegmentOverride(int segmentId) {
    final prefix = _segmentPrefixTable[segmentId];
    emit8If(prefix, prefix != 0);
  }

  void emitAddressOverride(bool condition) => emit8If(0x67, condition);

  void emitImmByteOrDword(int immValue, int immSize) {
    if (immSize == 0) return;
    emit8(immValue);
    if (immSize == 1) return;
    emit8(immValue >> 8);
    emit8(immValue >> 16);
    emit8(immValue >> 24);
  }

  void emitImmediate(int immValue, int immSize) {
    var imm = immValue;
    if (immSize >= 4) {
      emit32uLe(imm);
      imm >>= 32;
      immSize -= 4;
    }
    for (; immSize > 0; immSize--) {
      emit8(imm);
      imm >>= 8;
    }
  }

  int at(int pos) => buf[pos];
  void setAt(int pos, int v) => buf[pos] = v;
  void insert8(int pos, int v) => buf.insertAt(pos, v);
  void remove8(int pos) => buf.removeAt(pos);
}

/// Encodes x86/x64 instructions as upstream `x86::Assembler::_emit()`.
final class X86Emitter {
  final CodeHolder code;

  /// The section being written (the assembler's `_section`).
  Section section;

  CodeBuffer get buffer => section.buffer;

  /// `inst_options()`: options of the next instruction (prefixes, forms).
  int instOptions = 0;

  /// `forced_inst_options()`.
  int forcedInstOptions = 0;

  /// `extra_reg()`: AVX-512 `{k}` mask register id or REP counter (0 = none).
  _Op _extraReg = _Op.none;

  /// `encoding_options()` (`EncodingOptions`).
  int encodingOptions = 0;

  X86Emitter(this.code, this.section);

  /// Sets the extra register (`{k}` selector) of the next instruction.
  set extraReg(Object? reg) => _extraReg = _Op.of(reg);

  bool _hasEncodingOption(int o) => (encodingOptions & o) != 0;

  /// `is_32bit()`, `is_64bit()` and `register_size()` of the target
  /// architecture.
  bool get _is32Bit => code.env.arch == Arch.x86;
  bool get _is64Bit => !_is32Bit;
  int get _registerSize => _is32Bit ? 4 : 8;

  /// `_address_override_mask()`: the [memInfoTable] bit that requires the
  /// address-size override prefix in the target mode.
  int get _addressOverrideMask =>
      _is32Bit ? _kMemInfo67H_X86 : _kMemInfo67H_X64;

  /// Emits [instId] with [operands]; throws [X86EmitError] if the
  /// instruction cannot be encoded.
  void emit(int instId, List<Object> operands) {
    final ops = [for (final o in operands) _Op.of(o)];
    while (ops.length < 6) {
      ops.add(_Op.none);
    }
    final start = buffer.length;
    try {
      _emit(instId, ops);
    } catch (_) {
      buffer.truncate(start);
      rethrow;
    } finally {
      instOptions = 0;
      _extraReg = _Op.none;
    }
  }

  void _emit(int instId, List<_Op> opArray) {
    const kVSHR_W = X86Opcode.kW_Shift - 23;
    const kVSHR_PP = X86Opcode.kPP_Shift - 16;
    const kVSHR_PP_EW = X86Opcode.kPP_Shift - 16;

    const kRequiresSpecialHandling = _IO.kReserved |
        _IO.kX86_Rep |
        _IO.kX86_Repne |
        _IO.kX86_Lock |
        _IO.kX86_XAcquire |
        _IO.kX86_XRelease;

    final o0 = opArray[0], o1 = opArray[1], o2 = opArray[2];
    final opExt = opArray;

    int opcode;
    int options;
    int isign3;

    _Op? rmRel;
    int rmInfo = 0;
    int rbReg = 0;
    int rxReg = 0;
    int opReg;

    Label? label;
    // Relocation of a 32-bit [LABEL|RIP] operand, linked to the label fixup
    // created by EmitRel when the label is not bound yet.
    RelocEntry? re;
    int relOffset = 0;
    int relSize = 0;
    int memOpAoMark = -1;

    int immValue = 0;
    int immSize = 0;

    // Locals of EmitJmpCall shared with EmitJmpCallRel.
    int rel32 = 0, opcode8 = 0, inst8_size = 0, inst32_size = 0;

    final _w = _Writer(buffer);
    final instStart = buffer.length;

    // Upstream id 0 is `kIdNone`; in the port's DB an instruction without
    // encoder data (encoding `None`) plays that role.
    final instInfo = instId >= 0 && instId < kX86InstDb.length
        ? kX86InstDb[instId]
        : kX86InstDb[0];
    final isNone = instId < 0 ||
        instId >= kX86InstDb.length ||
        instInfo.encoding == X86Encoding.kEncodingNone;
    final ciFlags = instInfo.dbFlags;
    bool _ciHasFlag(int f) => (ciFlags & f) != 0;
    bool _ciIsTsibOp() => _ciHasFlag(X86InstDbFlags.kTsib);
    bool _ciPreferEvex() => _ciHasFlag(X86InstDbFlags.kPreferEvex);
    bool _ciHasAvx() =>
        _ciHasFlag(X86InstDbFlags.kVex) || _ciHasFlag(X86InstDbFlags.kEvex);
    int _ciBroadcastSize() {
      final f = instInfo.avx512Flags;
      return (f & X86Avx512Flags.kB64) != 0
          ? 8
          : (f & X86Avx512Flags.kB32) != 0
              ? 4
              : (f & X86Avx512Flags.kB16) != 0
                  ? 2
                  : 0;
    }

    int altOpcodeOf(Object _) => instInfo.altOpcode;
    final avx512 = instInfo.avx512Flags;
    bool _ciHasAvx512K() => (avx512 & X86Avx512Flags.kK) != 0;
    bool _ciHasAvx512Z() => (avx512 & X86Avx512Flags.kZ) != 0;
    bool _ciHasAvx512Er() => (avx512 & X86Avx512Flags.kER) != 0;
    bool _ciHasAvx512Sae() => (avx512 & X86Avx512Flags.kSAE) != 0;
    bool _ciHasAvx512Bcst() =>
        (avx512 &
            (X86Avx512Flags.kB16 |
                X86Avx512Flags.kB32 |
                X86Avx512Flags.kB64)) !=
        0;

    // `x86_get_movabs_inst_size_64bit()` + `x86_should_use_movabs()`.
    bool _shouldUseMovabs(int registerSize, int options, _Op rmRel) {
      if (_is32Bit) {
        // There is no relative addressing, just decide whether to use MOV
        // encoded with MOD R/M or absolute.
        return !_test(options, _IO.kX86_ModMR | _IO.kX86_ModRM);
      }
      if (rmRel.addrType == _Addr.kRel ||
          _test(options, _IO.kX86_ModMR | _IO.kX86_ModRM)) {
        return false;
      }
      final addrValue = rmRel.offset;
      final baseAddress = code.baseAddress;
      if (rmRel.addrType == _Addr.kDefault &&
          baseAddress != null &&
          !rmRel.hasSegment()) {
        final instructionSize = (rmRel.segmentId != 0 ? 1 : 0) +
            (registerSize == 2 ? 1 : 0) +
            (registerSize == 8 || _test(options, _IO.kX86_Rex) ? 1 : 0) +
            1 +
            8;
        final rip64 = baseAddress + buffer.length + instructionSize;
        if (_isIntN(32, addrValue - rip64)) return false;
      } else {
        if (_isIntN(32, addrValue)) return false;
      }
      return addrValue < 0 || addrValue > 0xFFFFFFFF;
    }

    // Signature of the first 3 operands.
    isign3 = o0.opType + (o1.opType << 3) + (o2.opType << 6);

    options = (isNone ? 1 : 0) | instOptions | forcedInstOptions;

    if (_test(options, kRequiresSpecialHandling)) {
      if (isNone) _fail('InvalidInstruction', instId, opArray);

      final instFlags = ciFlags;

      // LOCK, XACQUIRE, and XRELEASE prefixes.
      if (_test(options, _IO.kX86_Lock)) {
        final isXacqXrel =
            _test(options, _IO.kX86_XAcquire | _IO.kX86_XRelease);
        if (!_test(instFlags, X86InstDbFlags.kLock) && !isXacqXrel) {
          _fail('InvalidLockPrefix', instId, opArray);
        }
        if (isXacqXrel) {
          if (_test(options, _IO.kX86_XAcquire) &&
              !_test(instFlags, X86InstDbFlags.kXAcquire)) {
            _fail('InvalidXAcquirePrefix', instId, opArray);
          }
          if (_test(options, _IO.kX86_XRelease) &&
              !_test(instFlags, X86InstDbFlags.kXRelease)) {
            _fail('InvalidXReleasePrefix', instId, opArray);
          }
          _w.emit8(_test(options, _IO.kX86_XAcquire) ? 0xF2 : 0xF3);
        }
        _w.emit8(0xF0);
      }

      // REP and REPNE prefixes.
      if (_test(options, _IO.kX86_Rep | _IO.kX86_Repne)) {
        if (!_test(instFlags, X86InstDbFlags.kRep)) {
          _fail('InvalidRepPrefix', instId, opArray);
        }
        if (_extraReg.isReg() &&
            (!_extraReg.isGp() || _extraReg.id != _kIdCx)) {
          _fail('InvalidRepPrefix', instId, opArray);
        }
        _w.emit8(_test(options, _IO.kX86_Repne) ? 0xF2 : 0xF3);
      }
    }

    opcode = instInfo.mainOpcode & ~0xFF;
    opReg = X86Opcode.extractModO(opcode);
    opcode |= instInfo.mainOpcode & 0xFF;

    // FIXUP_GPB: BPL|SPL|SIL|DIL|R8B-15B force a REX prefix; AH|BH|CH|DH are
    // encoded as 4..7 and disallow REX.
    int fixupGpb(_Op regOp, int regId) {
      if (!regOp.isGp8Hi()) {
        if (regId >= 4) options |= _IO.kX86_Rex;
        return regId;
      }
      options |= _IO.kX86_InvalidRex;
      return regId + 4;
    }

    var s = isNone ? _S.InvalidInstruction : _encodingStates[instInfo.encoding];
    loop:
    while (true) {
      switch (s) {
        case _S.encNone:
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Base Instructions
        // -----------------

        case _S.encX86Op:
          {
            s = _S.EmitX86Op;
            continue loop;
          }

        case _S.encX86Op_Mod11RM:
          rbReg = X86Opcode.extractModRM(opcode);
          {
            s = _S.EmitX86R;
            continue loop;
          }

        case _S.encX86Op_Mod11RM_I8:
          // The first operand must be immediate, we don't care of other operands as they could be implicit.
          if (!o0.isImm()) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          rbReg = X86Opcode.extractModRM(opcode);
          immValue = o0.immU8;
          immSize = 1;
          {
            s = _S.EmitX86R;
            continue loop;
          }

        case _S.encX86Op_xAddr:
          if (!o0.isReg()) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          rmInfo = memInfoTable[(o0.regType)];
          _w.emitAddressOverride((rmInfo & _addressOverrideMask) != 0);
          {
            s = _S.EmitX86Op;
            continue loop;
          }

        case _S.encX86Op_xAX:
          if (isign3 == 0) {
            s = _S.EmitX86Op;
            continue loop;
          }

          if (isign3 == 1 /* ENC_OPS1(Reg) */ && o0.id == _kIdAx) {
            s = _S.EmitX86Op;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Op_xDX_xAX:
          if (isign3 == 0) {
            s = _S.EmitX86Op;
            continue loop;
          }

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */ &&
              o0.id == _kIdDx &&
              o1.id == _kIdAx) {
            s = _S.EmitX86Op;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Op_MemZAX:
          if (isign3 == 0) {
            s = _S.EmitX86Op;
            continue loop;
          }

          rmRel = o0;
          if (isign3 == 2 /* ENC_OPS1(Mem) */ && isImplicitMem(o0, _kIdAx)) {
            s = _S.EmitX86OpImplicitMem;
            continue loop;
          }

          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86I_xAX:
          // Implicit form.
          if (isign3 == 4 /* ENC_OPS1(Imm) */) {
            immValue = o0.immU8;
            immSize = 1;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }

          // Explicit form.
          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */ && o0.id == _kIdAx) {
            immValue = o1.immU8;
            immSize = 1;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86M_NoMemSize:
          if (o0.isReg()) opcode = _addPrefixBySize(opcode, o0.x86RmSize);
          {
            s = _S.CaseX86M_NoSize;
            continue loop;
          }

        case _S.encX86M:
          opcode = _addPrefixBySize(opcode, o0.x86RmSize);
          {
            s = _S.encX86M_NoSize;
            continue loop;
          }

        case _S.encX86M_NoSize:
        case _S.CaseX86M_NoSize:
          rbReg = o0.id;
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            s = _S.EmitX86R;
            continue loop;
          }

          rmRel = o0;
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            s = _S.EmitX86M;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86M_GPB_MulDiv:
        case _S.CaseX86M_GPB_MulDiv:
          // Explicit form?
          if (isign3 > 0x7) {
            // [AX] <- [AX] div|mul r8.
            if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (!o0.isGp16(_kIdAx) || !o1.isGp8()) {
                s = _S.InvalidInstruction;
                continue loop;
              }

              rbReg = o1.id;
              rbReg = fixupGpb(o1, rbReg);
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            // [AX] <- [AX] div|mul m8.
            if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
              if (!o0.isGp16(_kIdAx)) {
                s = _S.InvalidInstruction;
                continue loop;
              }

              rmRel = o1;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            // [?DX:?AX] <- [?DX:?AX] div|mul r16|r32|r64
            if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (o0.x86RmSize != o1.x86RmSize) {
                s = _S.InvalidInstruction;
                continue loop;
              }

              opcode = _addArithBySize(opcode, o0.x86RmSize);
              rbReg = o2.id;
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            // [?DX:?AX] <- [?DX:?AX] div|mul m16|m32|m64
            if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
              if (o0.x86RmSize != o1.x86RmSize) {
                s = _S.InvalidInstruction;
                continue loop;
              }

              opcode = _addArithBySize(opcode, o0.x86RmSize);
              rmRel = o2;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          {
            s = _S.encX86M_GPB;
            continue loop;
          }

        case _S.encX86M_GPB:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            opcode = _addArithBySize(opcode, o0.x86RmSize);
            rbReg = o0.id;

            if (o0.x86RmSize != 1) {
              s = _S.EmitX86R;
              continue loop;
            }

            rbReg = fixupGpb(o0, rbReg);
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            if (o0.x86RmSize == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            opcode = _addArithBySize(opcode, o0.x86RmSize);
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86M_Only_EDX_EAX:
          if (isign3 == 74 /* ENC_OPS3(Mem, Reg, Reg) */ &&
              o1.isGp32(_kIdDx) &&
              o2.isGp32(_kIdAx)) {
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.encX86M_Only;
            continue loop;
          }

        case _S.encX86M_Only:
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86M_Nop:
          if (isign3 == 0 /* ENC_OPS1(None) */) {
            s = _S.EmitX86Op;
            continue loop;
          }

          // Single operand NOP instruction "0F 1F /0".
          opcode = X86Opcode.k000F00 | 0x1F;
          opReg = 0;

          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // Two operand NOP instruction "0F 1F /r".
          opReg = o1.id;
          opcode = _addPrefixBySize(opcode, o1.x86RmSize);

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86R_FromM:
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            rmRel = o0;
            rbReg = o0.id;
            {
              s = _S.EmitX86RFromM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86R32_EDX_EAX:
          // Explicit form: R32, EDX, EAX.
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            if (!o1.isGp32(_kIdDx) || !o2.isGp32(_kIdAx)) {
              s = _S.InvalidInstruction;
              continue loop;
            }
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          // Implicit form: R32.
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            if (!o0.isGp32()) {
              s = _S.InvalidInstruction;
              continue loop;
            }
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86R_Native:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Rm:
          opcode = _addPrefixBySize(opcode, o0.x86RmSize);
          {
            s = _S.encX86Rm_NoSize;
            continue loop;
          }

        case _S.encX86Rm_NoSize:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Rm_Raw66H:
          // We normally emit either [66|F2|F3], this instruction requires 66+[F2|F3].
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;

            if (o0.x86RmSize == 2)
              _w.emit8(0x66);
            else
              opcode = _addWBySize(opcode, o0.x86RmSize);
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;

            if (o0.x86RmSize == 2)
              _w.emit8(0x66);
            else
              opcode = _addWBySize(opcode, o0.x86RmSize);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Mr:
          opcode = _addPrefixBySize(opcode, o1.x86RmSize);
          {
            s = _S.encX86Mr_NoSize;
            continue loop;
          }

        case _S.encX86Mr_NoSize:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            rbReg = o0.id;
            opReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            rmRel = o0;
            opReg = o1.id;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Arith:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opcode = _addArithBySize(opcode, o0.x86RmSize);

            if (o0.x86RmSize != o1.x86RmSize) {
              s = _S.OperandSizeMismatch;
              continue loop;
            }

            rbReg = o0.id;
            opReg = o1.id;

            if (o0.x86RmSize == 1) {
              rbReg = fixupGpb(o0, rbReg);
              opReg = fixupGpb(o1, opReg);
            }

            // MOD/MR: The default encoding used if not instructed otherwise..
            if (!_test(options, _IO.kX86_ModRM)) {
              s = _S.EmitX86R;
              continue loop;
            }

            // MOD/RM: Alternative encoding selected via instruction options.
            opcode += 2;
            {
              final t = opReg;
              opReg = rbReg;
              rbReg = t;
            }
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opcode += 2;
            opcode = _addArithBySize(opcode, o0.x86RmSize);

            opReg = o0.id;
            rmRel = o1;

            if (o0.x86RmSize != 1) {
              s = _S.EmitX86M;
              continue loop;
            }

            opReg = fixupGpb(o0, opReg);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = _addArithBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rmRel = o0;

            if (o1.x86RmSize != 1) {
              s = _S.EmitX86M;
              continue loop;
            }

            opReg = fixupGpb(o1, opReg);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The remaining instructions use 0x80 opcode.
          opcode = 0x80;

          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            var size = o0.x86RmSize;

            rbReg = o0.id;
            immValue = o1.imm;

            if (size == 1) {
              rbReg = fixupGpb(o0, rbReg);
              immSize = 1;
            } else {
              if (size == 2) {
                opcode |= X86Opcode.kPP_66;
              } else if (size == 4) {
                // Sign extend so is_int_n<8> returns the right result.
                immValue = _signExtendInt32(immValue);
              } else if (size == 8) {
                var can_transform_to_32bit =
                    instId == X86InstId.kAnd && _isUintN(32, immValue);

                if (!_isIntN(32, immValue)) {
                  // We would do this by default when `kOptionOptimizedForSize` is
                  // enabled, however, in this case we just force this as otherwise
                  // we would have to fail.
                  if (can_transform_to_32bit)
                    size = 4;
                  else {
                    s = _S.InvalidImmediate;
                    continue loop;
                  }
                } else if (can_transform_to_32bit &&
                    _hasEncodingOption(EncodingOptions.kOptimizeForSize)) {
                  size = 4;
                }

                opcode = _addWBySize(opcode, size);
              }

              immSize = (math.min(size, 4));
              if (_isIntN(8, immValue) && !_test(options, _IO.kLongForm))
                immSize = 1;
            }

            // Short form - AL, AX, EAX, RAX.
            if (rbReg == 0 &&
                (size == 1 || immSize != 1) &&
                !_test(options, _IO.kLongForm)) {
              opcode &= X86Opcode.kPP_66 | X86Opcode.kW;
              opcode |= ((opReg << 3) | (0x04 + _b(size != 1)));
              immSize = (math.min(size, 4));
              {
                s = _S.EmitX86Op;
                continue loop;
              }
            }

            opcode += size != 1 ? (immSize != 1 ? 1 : 3) : 0;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 34 /* ENC_OPS2(Mem, Imm) */) {
            var mem_size = o0.x86RmSize;

            if (mem_size == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            immValue = o1.imm;
            immSize = (math.min(mem_size, 4));

            // Sign extend so is_int_n<8> returns the right result.
            if (mem_size == 4) immValue = _signExtendInt32(immValue);

            if (_isIntN(8, immValue) && !_test(options, _IO.kLongForm))
              immSize = 1;

            opcode += mem_size != 1 ? (immSize != 1 ? 1 : 3) : 0;
            opcode = _addPrefixBySize(opcode, mem_size);

            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Bswap:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            if (o0.x86RmSize == 1) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opReg = o0.id;
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            {
              s = _S.EmitX86OpReg;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Bt:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opcode = _addPrefixBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = _addPrefixBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The remaining instructions use the secondary opcode/r.
          immValue = o1.imm;
          immSize = 1;

          opcode = altOpcodeOf(instInfo);
          opcode = _addPrefixBySize(opcode, o0.x86RmSize);
          opReg = X86Opcode.extractModO(opcode);

          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 34 /* ENC_OPS2(Mem, Imm) */) {
            if (o0.x86RmSize == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Call:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          rmRel = o0;
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            s = _S.EmitX86M;
            continue loop;
          }

          // Call with 32-bit displacement use 0xE8 opcode. Call with 8-bit displacement is not encodable so the
          // alternative opcode field in X86DB must be zero.
          opcode = 0xE8;
          opReg = 0;
          {
            s = _S.EmitJmpCall;
            continue loop;
          }

        case _S.encX86Cmpxchg:
          {
            // Convert explicit to implicit.
            if ((isign3 & (0x7 << 6)) != 0) {
              if (!o2.isGp() || o2.id != _kIdAx) {
                {
                  s = _S.InvalidInstruction;
                  continue loop;
                }
              }
              isign3 &= 0x3F;
            }

            if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (o0.x86RmSize != o1.x86RmSize) {
                s = _S.OperandSizeMismatch;
                continue loop;
              }

              opcode = _addArithBySize(opcode, o0.x86RmSize);
              rbReg = o0.id;
              opReg = o1.id;

              if (o0.x86RmSize != 1) {
                s = _S.EmitX86R;
                continue loop;
              }

              rbReg = fixupGpb(o0, rbReg);
              opReg = fixupGpb(o1, opReg);
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
              opcode = _addArithBySize(opcode, o1.x86RmSize);
              opReg = o1.id;
              rmRel = o0;

              if (o1.x86RmSize != 1) {
                s = _S.EmitX86M;
                continue loop;
              }

              opReg = fixupGpb(o1, opReg);
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encX86Cmpxchg8b_16b;
          continue loop; // (after block)
        case _S.encX86Cmpxchg8b_16b:
          {
            final o3 = opExt[3];
            final o4 = opExt[4];

            if (isign3 == 74 /* ENC_OPS3(Mem, Reg, Reg) */) {
              if (o3.isReg() && o4.isReg()) {
                rmRel = o0;
                {
                  s = _S.EmitX86M;
                  continue loop;
                }
              }
            }

            if (isign3 == 2 /* ENC_OPS1(Mem) */) {
              rmRel = o0;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encX86Crc;
          continue loop; // (after block)
        case _S.encX86Crc:
          opReg = o0.id;
          opcode = _addWBySize(opcode, o0.x86RmSize);

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            rbReg = o1.id;

            if (o1.x86RmSize == 1) {
              rbReg = fixupGpb(o1, rbReg);
              {
                s = _S.EmitX86R;
                continue loop;
              }
            } else {
              // This seems to be the only exception of encoding '66F2' prefix.
              if (o1.x86RmSize == 2) _w.emit8(0x66);

              opcode = _add(opcode, 1);
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            rmRel = o1;
            if (o1.x86RmSize == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            // This seems to be the only exception of encoding '66F2' prefix.
            if (o1.x86RmSize == 2) _w.emit8(0x66);

            opcode += _u32(o1.x86RmSize != 1);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Enter:
          if (isign3 == 36 /* ENC_OPS2(Imm, Imm) */) {
            var iw = o0.immU16;
            var ib = o1.immU8;

            immValue = iw | (ib << 16);
            immSize = 3;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Imul:
          // First process all forms distinct of `kEncodingX86M_OptB_MulDiv`.
          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opcode = 0x6B;
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);

            immValue = o2.imm;
            immSize = 1;

            if (!_isIntN(8, immValue) || _test(options, _IO.kLongForm)) {
              opcode -= 2;
              immSize = o0.x86RmSize == 2 ? 2 : 4;
            }

            opReg = o0.id;
            rbReg = o1.id;

            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opcode = 0x6B;
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);

            immValue = o2.imm;
            immSize = 1;

            // Sign extend so is_int_n<8> returns the right result.
            if (o0.x86RmSize == 4) immValue = _signExtendInt32(immValue);

            if (!_isIntN(8, immValue) || _test(options, _IO.kLongForm)) {
              opcode -= 2;
              immSize = o0.x86RmSize == 2 ? 2 : 4;
            }

            opReg = o0.id;
            rmRel = o1;

            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            // Must be explicit 'ax, r8' form.
            if (o1.x86RmSize == 1) {
              s = _S.CaseX86M_GPB_MulDiv;
              continue loop;
            }

            if (o0.x86RmSize != o1.x86RmSize) {
              s = _S.OperandSizeMismatch;
              continue loop;
            }

            opReg = o0.id;
            rbReg = o1.id;

            opcode = X86Opcode.k000F00 | 0xAF;
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            // Must be explicit 'ax, m8' form.
            if (o1.x86RmSize == 1) {
              s = _S.CaseX86M_GPB_MulDiv;
              continue loop;
            }

            opReg = o0.id;
            rmRel = o1;

            opcode = X86Opcode.k000F00 | 0xAF;
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // Shorthand to imul 'reg, reg, imm'.
          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            opcode = 0x6B;
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);

            immValue = o1.imm;
            immSize = 1;

            // Sign extend so is_int_n<8> returns the right result.
            if (o0.x86RmSize == 4) immValue = _signExtendInt32(immValue);

            if (!_isIntN(8, immValue) || _test(options, _IO.kLongForm)) {
              opcode -= 2;
              immSize = o0.x86RmSize == 2 ? 2 : 4;
            }

            opReg = rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          // Try implicit form.
          {
            s = _S.CaseX86M_GPB_MulDiv;
            continue loop;
          }

        case _S.encX86In:
          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            if (o0.id != _kIdAx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            immValue = o1.immU8;
            immSize = 1;

            opcode = altOpcodeOf(instInfo) + _b(o0.x86RmSize != 1);
            opcode = _add66hBySize(opcode, o0.x86RmSize);
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            if (o0.id != _kIdAx || o1.id != _kIdDx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode += _u32(o0.x86RmSize != 1);
            opcode = _add66hBySize(opcode, o0.x86RmSize);
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Ins:
          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            if (!isImplicitMem(o0, _kIdDi) || o1.id != _kIdDx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            var size = o0.x86RmSize;
            if (size == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            rmRel = o0;
            opcode += _u32(size != 1);

            opcode = _add66hBySize(opcode, size);
            {
              s = _S.EmitX86OpImplicitMem;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86IncDec:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            rbReg = o0.id;

            if (o0.x86RmSize == 1) {
              rbReg = fixupGpb(o0, rbReg);
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            if (_is32Bit) {
              // INC r16|r32 is only encodable in 32-bit mode (collides with REX).
              opcode = altOpcodeOf(instInfo) + (rbReg & 0x07);
              opcode = _add66hBySize(opcode, o0.x86RmSize);
              {
                s = _S.EmitX86Op;
                continue loop;
              }
            } else {
              opcode = _addArithBySize(opcode, o0.x86RmSize);
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            if (o0.x86RmSize == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }
            opcode = _addArithBySize(opcode, o0.x86RmSize);
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Int:
          if (isign3 == 4 /* ENC_OPS1(Imm) */) {
            immValue = o0.imm;
            immSize = 1;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Jcc:
          if (_test(options, _IO.kTaken | _IO.kNotTaken) &&
              _hasEncodingOption(_kPredictedJumps)) {
            var prefix = _test(options, _IO.kTaken) ? _u8(0x3E) : _u8(0x2E);
            _w.emit8(prefix);
          }

          rmRel = o0;
          opReg = 0;
          {
            s = _S.EmitJmpCall;
            continue loop;
          }

        case _S.encX86JecxzLoop:
          rmRel = o0;
          // Explicit jecxz|loop [r|e]cx, dst
          if (o0.isReg()) {
            if (!o0.isGp(_kIdCx)) {
              {
                s = _S.InvalidInstruction;
                continue loop;
              }
            }

            _w.emitAddressOverride((_is32Bit && o0.x86RmSize == 2) ||
                (_is64Bit && o0.x86RmSize == 4));
            rmRel = o1;
          }

          opReg = 0;
          {
            s = _S.EmitJmpCall;
            continue loop;
          }

        case _S.encX86Jmp:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          rmRel = o0;
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            s = _S.EmitX86M;
            continue loop;
          }

          // Jump encoded with 32-bit displacement use 0xE9 opcode. Jump encoded with 8-bit displacement's opcode is
          // stored as an alternative opcode.
          opcode = 0xE9;
          opReg = 0;
          {
            s = _S.EmitJmpCall;
            continue loop;
          }

        case _S.encX86JmpRel:
          rmRel = o0;
          {
            s = _S.EmitJmpCall;
            continue loop;
          }

        case _S.encX86LcallLjmp:
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            rmRel = o0;
            var mem_size = rmRel!.size;
            if (mem_size == 0) {
              mem_size = _registerSize;
            } else {
              mem_size -= 2;
              if (mem_size != 2 && mem_size != 4 && mem_size != _registerSize) {
                s = _S.InvalidAddress;
                continue loop;
              }
            }
            opcode = _addPrefixBySize(opcode, mem_size);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          if (isign3 == 36 /* ENC_OPS2(Imm, Imm) */) {
            if (!_is32Bit) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            final imm0 = o0;
            final imm1 = o1;

            if (imm0.imm > 0xFFFF || imm1.imm > 0xFFFFFFFF) {
              s = _S.InvalidImmediate;
              continue loop;
            }

            opcode = altOpcodeOf(instInfo);
            immValue = imm1.imm | (imm0.imm << 32);
            immSize = 6;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Lea:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Mov:
          // Reg <- Reg
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            // Asmjit uses segment registers indexed from 1 to 6, leaving zero as "no segment register used". We have to
            // fix this (decrement the index of the register) when emitting MOV instructions which move to/from a segment
            // register. The segment register is always `op_reg`, because the MOV instruction uses either RM or MR encoding.

            // GP <- ??
            if (o0.isGp()) {
              rbReg = o0.id;
              opReg = o1.id;

              // GP <- GP
              if (o1.isGp()) {
                var op_size = o0.x86RmSize;
                if (op_size != o1.x86RmSize) {
                  s = _S.InvalidInstruction;
                  continue loop;
                }

                if (op_size == 1) {
                  rbReg = fixupGpb(o0, rbReg);
                  opReg = fixupGpb(o1, opReg);
                  opcode = 0x88;

                  if (!_test(options, _IO.kX86_ModRM)) {
                    s = _S.EmitX86R;
                    continue loop;
                  }

                  opcode += 2;
                  {
                    final t = opReg;
                    opReg = rbReg;
                    rbReg = t;
                  }
                  {
                    s = _S.EmitX86R;
                    continue loop;
                  }
                } else {
                  opcode = 0x89;
                  opcode = _addPrefixBySize(opcode, op_size);

                  if (!_test(options, _IO.kX86_ModRM)) {
                    s = _S.EmitX86R;
                    continue loop;
                  }

                  opcode += 2;
                  {
                    final t = opReg;
                    opReg = rbReg;
                    rbReg = t;
                  }
                  {
                    s = _S.EmitX86R;
                    continue loop;
                  }
                }
              }

              // GP <- SReg
              if (o1.isSegmentReg()) {
                opcode = 0x8C;
                opcode = _addPrefixBySize(opcode, o0.x86RmSize);
                opReg--;
                {
                  s = _S.EmitX86R;
                  continue loop;
                }
              }

              // GP <- CReg
              if (o1.isControlReg()) {
                opcode = X86Opcode.k000F00 | 0x20;

                // Use `LOCK MOV` in 32-bit mode if CR8+ register is accessed (AMD extension).
                if ((opReg & 0x8) != 0 && _is32Bit) {
                  _w.emit8(0xF0);
                  opReg &= 0x7;
                }
                {
                  s = _S.EmitX86R;
                  continue loop;
                }
              }

              // GP <- DReg
              if (o1.isDebugReg()) {
                opcode = X86Opcode.k000F00 | 0x21;
                {
                  s = _S.EmitX86R;
                  continue loop;
                }
              }
            } else {
              opReg = o0.id;
              rbReg = o1.id;

              // ?? <- GP
              if (!o1.isGp()) {
                s = _S.InvalidInstruction;
                continue loop;
              }

              // SReg <- GP
              if (o0.isSegmentReg()) {
                opcode = 0x8E;
                opcode = _addPrefixBySize(opcode, o1.x86RmSize);
                opReg--;
                {
                  s = _S.EmitX86R;
                  continue loop;
                }
              }

              // CReg <- GP
              if (o0.isControlReg()) {
                opcode = X86Opcode.k000F00 | 0x22;

                // Use `LOCK MOV` in 32-bit mode if CR8+ register is accessed (AMD extension).
                if ((opReg & 0x8) != 0 && _is32Bit) {
                  _w.emit8(0xF0);
                  opReg &= 0x7;
                }
                {
                  s = _S.EmitX86R;
                  continue loop;
                }
              }

              // DReg <- GP
              if (o0.isDebugReg()) {
                opcode = X86Opcode.k000F00 | 0x23;
                {
                  s = _S.EmitX86R;
                  continue loop;
                }
              }
            }

            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;

            // SReg <- Mem
            if (o0.isSegmentReg()) {
              opcode = 0x8E;
              opcode = _addPrefixBySize(opcode, o1.x86RmSize);
              opReg--;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
            // Reg <- Mem
            else {
              opcode = 0;
              opcode = _addArithBySize(opcode, o0.x86RmSize);

              // Handle a special form of `mov al|ax|eax|rax, [ptr64]` that doesn't use MOD.
              if (opReg == _kIdAx && !rmRel!.hasBaseOrIndex()) {
                if (_shouldUseMovabs(o0.x86RmSize, options, rmRel!)) {
                  opcode += 0xA0;
                  immValue = rmRel!.offset;
                  {
                    s = _S.EmitX86OpMovAbs;
                    continue loop;
                  }
                }
              }

              if (o0.x86RmSize == 1) opReg = fixupGpb(o0, opReg);

              opcode += 0x8A;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;

            // Mem <- SReg
            if (o1.isSegmentReg()) {
              opcode = 0x8C;
              opcode = _addPrefixBySize(opcode, o0.x86RmSize);
              opReg--;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
            // Mem <- Reg
            else {
              opcode = 0;
              opcode = _addArithBySize(opcode, o1.x86RmSize);

              // Handle a special form of `mov [ptr64], al|ax|eax|rax` that doesn't use MOD.
              if (opReg == _kIdAx && !rmRel!.hasBaseOrIndex()) {
                if (_shouldUseMovabs(o1.x86RmSize, options, rmRel!)) {
                  opcode += 0xA2;
                  immValue = rmRel!.offset;
                  {
                    s = _S.EmitX86OpMovAbs;
                    continue loop;
                  }
                }
              }

              if (o1.x86RmSize == 1) opReg = fixupGpb(o1, opReg);

              opcode += 0x88;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }

          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            opReg = o0.id;
            immSize = (o0.x86RmSize);

            if (immSize == 1) {
              opReg = fixupGpb(o0, opReg);

              opcode = 0xB0;
              immValue = o1.immU8;
              {
                s = _S.EmitX86OpReg;
                continue loop;
              }
            } else {
              // 64-bit immediate in 64-bit mode is allowed.
              immValue = o1.imm;

              // Optimize the instruction size by using a 32-bit immediate if possible.
              if (immSize == 8 && !_test(options, _IO.kLongForm)) {
                if (_isUintN(32, immValue) &&
                    _hasEncodingOption(EncodingOptions.kOptimizeForSize)) {
                  // Zero-extend by using a 32-bit GPD destination instead of a 64-bit GPQ.
                  immSize = 4;
                } else if (_isIntN(32, immValue)) {
                  // Sign-extend, uses 'C7 /0' opcode.
                  rbReg = opReg;

                  opcode = X86Opcode.kW | 0xC7;
                  opReg = 0;

                  immSize = 4;
                  {
                    s = _S.EmitX86R;
                    continue loop;
                  }
                }
              }

              opcode = 0xB8;
              opcode = _addPrefixBySize(opcode, immSize);
              {
                s = _S.EmitX86OpReg;
                continue loop;
              }
            }
          }

          if (isign3 == 34 /* ENC_OPS2(Mem, Imm) */) {
            var mem_size = o0.x86RmSize;
            if (mem_size == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            opcode = 0xC6 + _b(mem_size != 1);
            opcode = _addPrefixBySize(opcode, mem_size);
            opReg = 0;
            rmRel = o0;

            immValue = o1.imm;
            immSize = (math.min(mem_size, 4));
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Movabs:
          // Reg <- Mem
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;

            opcode = 0xA0;
            opcode = _addArithBySize(opcode, o0.x86RmSize);

            if (!o0.isGp() || opReg != _kIdAx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            if (rmRel!.hasBaseOrIndex()) {
              s = _S.InvalidAddress;
              continue loop;
            }

            if (rmRel!.addrType == _Addr.kRel) {
              s = _S.InvalidAddress;
              continue loop;
            }

            immValue = rmRel!.offset;
            {
              s = _S.EmitX86OpMovAbs;
              continue loop;
            }
          }

          // Mem <- Reg
          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;

            opcode = 0xA2;
            opcode = _addArithBySize(opcode, o1.x86RmSize);

            if (!o1.isGp() || opReg != _kIdAx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            if (rmRel!.hasBaseOrIndex()) {
              s = _S.InvalidAddress;
              continue loop;
            }

            immValue = rmRel!.offset;
            {
              s = _S.EmitX86OpMovAbs;
              continue loop;
            }
          }

          // Reg <- Imm.
          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            if (!o0.isGp64()) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opReg = o0.id;
            opcode = 0xB8;

            immSize = 8;
            immValue = o1.imm;

            opcode = _addPrefixBySize(opcode, 8);
            {
              s = _S.EmitX86OpReg;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86MovsxMovzx:
          opcode = _add(opcode, o1.x86RmSize != 1);
          opcode = _addPrefixBySize(opcode, o0.x86RmSize);

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;

            if (o1.x86RmSize != 1) {
              s = _S.EmitX86R;
              continue loop;
            }

            rbReg = fixupGpb(o1, rbReg);
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86MovntiMovdiri:
          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = _addWIf(opcode, o1.isGp64());

            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86EnqcmdMovdir64b:
          if (isign3 == 18 /* ENC_OPS2(Mem, Mem) */) {
            final m0 = o0;
            // This is the only required validation, the rest is handled afterwards.
            if ((m0.baseType != o1.baseType ||
                m0.hasIndex() ||
                m0.hasOffset() ||
                (m0.hasSegment() && m0.segmentId != _kSegEs))) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            // The first memory operand is passed via register, the second memory operand is RM.
            opReg = o0.baseId;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Out:
          if (isign3 == 12 /* ENC_OPS2(Imm, Reg) */) {
            if (o1.id != _kIdAx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = altOpcodeOf(instInfo) + _b(o1.x86RmSize != 1);
            opcode = _add66hBySize(opcode, o1.x86RmSize);

            immValue = o0.immU8;
            immSize = 1;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            if (o0.id != _kIdDx || o1.id != _kIdAx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = _add(opcode, o1.x86RmSize != 1);
            opcode = _add66hBySize(opcode, o1.x86RmSize);
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Outs:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            if (o0.id != _kIdDx || !isImplicitMem(o1, _kIdSi)) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            var size = o1.x86RmSize;
            if (size == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            rmRel = o1;
            opcode = _add(opcode, size != 1);
            opcode = _add66hBySize(opcode, size);
            {
              s = _S.EmitX86OpImplicitMem;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Pushw:
          if (isign3 == 4 /* ENC_OPS1(Imm) */) {
            immValue = o0.imm;
            immSize = 2;
            opcode = 0x68 | X86Opcode.kPP_66;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Push:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            if (o0.isSegmentReg()) {
              var segment = o0.id;
              if (segment >= _kSegCount) {
                s = _S.InvalidSegment;
                continue loop;
              }

              opcode = _opcodePushSregTable[segment];
              {
                s = _S.EmitX86Op;
                continue loop;
              }
            } else {
              {
                s = _S.CaseX86PushPop_Gp;
                continue loop;
              }
            }
          }

          if (isign3 == 4 /* ENC_OPS1(Imm) */) {
            immValue = o0.imm;
            immSize = 4;

            if (_isIntN(8, immValue) && !_test(options, _IO.kLongForm))
              immSize = 1;

            opcode = immSize == 1 ? 0x6A : 0x68;
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }
          {
            s = _S.encX86Pop;
            continue loop;
          }

        case _S.encX86Pop:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            if (o0.isSegmentReg()) {
              var segment = o0.id;
              if (segment == _kSegCs || segment >= _kSegCount) {
                s = _S.InvalidSegment;
                continue loop;
              }

              opcode = _opcodePopSregTable[segment];
              {
                s = _S.EmitX86Op;
                continue loop;
              }
            } else {
              {
                s = _S.CaseX86PushPop_Gp;
                continue loop;
              }
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            if (o0.x86RmSize == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            if (o0.x86RmSize != 2 && o0.x86RmSize != _registerSize) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = _add66hBySize(opcode, o0.x86RmSize);
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Ret:
          if (isign3 == 0) {
            // 'ret' without immediate, change C2 to C3.
            opcode = _add(opcode, 1);
            {
              s = _S.EmitX86Op;
              continue loop;
            }
          }

          if (isign3 == 4 /* ENC_OPS1(Imm) */) {
            immValue = o0.imm;
            if (immValue == 0 && !_test(options, _IO.kLongForm)) {
              // 'ret' without immediate, change C2 to C3.
              opcode = _add(opcode, 1);
              {
                s = _S.EmitX86Op;
                continue loop;
              }
            } else {
              immSize = 2;
              {
                s = _S.EmitX86Op;
                continue loop;
              }
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Rot:
          if (o0.isReg()) {
            opcode = _addArithBySize(opcode, o0.x86RmSize);
            rbReg = o0.id;

            if (o0.x86RmSize == 1) rbReg = fixupGpb(o0, rbReg);

            if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (o1.id != _kIdCx) {
                s = _S.InvalidInstruction;
                continue loop;
              }

              opcode += 2;
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
              immValue = o1.imm & 0xFF;
              immSize = 0;

              if (immValue == 1 && !_test(options, _IO.kLongForm)) {
                s = _S.EmitX86R;
                continue loop;
              }

              opcode -= 0x10;
              immSize = 1;
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }
          } else {
            if (o0.x86RmSize == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }
            opcode = _addArithBySize(opcode, o0.x86RmSize);

            if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
              if (o1.id != _kIdCx) {
                s = _S.InvalidInstruction;
                continue loop;
              }

              opcode += 2;
              rmRel = o0;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            if (isign3 == 34 /* ENC_OPS2(Mem, Imm) */) {
              rmRel = o0;
              immValue = o1.imm & 0xFF;
              immSize = 0;

              if (immValue == 1 && !_test(options, _IO.kLongForm)) {
                s = _S.EmitX86M;
                continue loop;
              }

              opcode -= 0x10;
              immSize = 1;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Set:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            rbReg = o0.id;
            rbReg = fixupGpb(o0, rbReg);
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86ShldShrd:
          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            opReg = o1.id;
            rbReg = o0.id;

            immValue = o2.imm;
            immSize = 1;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 266 /* ENC_OPS3(Mem, Reg, Imm) */) {
            opcode = _addPrefixBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rmRel = o0;

            immValue = o2.imm;
            immSize = 1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The following instructions use opcode + 1.
          opcode = _add(opcode, 1);

          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            if (o2.id != _kIdCx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            opReg = o1.id;
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 74 /* ENC_OPS3(Mem, Reg, Reg) */) {
            if (o2.id != _kIdCx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = _addPrefixBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86StrRm:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            rmRel = o1;
            if (rmRel!.offsetLo32 != 0 || !o0.isGp(_kIdAx)) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            var size = o0.x86RmSize;
            if (o1.x86RmSize != 0 && o1.x86RmSize != size) {
              s = _S.OperandSizeMismatch;
              continue loop;
            }

            opcode = _addArithBySize(opcode, size);
            {
              s = _S.EmitX86OpImplicitMem;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86StrMr:
          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            rmRel = o0;
            if (rmRel!.offsetLo32 != 0 || !o1.isGp(_kIdAx)) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            var size = o1.x86RmSize;
            if (o0.x86RmSize != 0 && o0.x86RmSize != size) {
              s = _S.OperandSizeMismatch;
              continue loop;
            }

            opcode = _addArithBySize(opcode, size);
            {
              s = _S.EmitX86OpImplicitMem;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86StrMm:
          if (isign3 == 18 /* ENC_OPS2(Mem, Mem) */) {
            if ((o0.baseAndIndexTypes != o1.baseAndIndexTypes)) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            rmRel = o1;
            if (o0.hasOffset()) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            var size = o1.x86RmSize;
            if (size == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            if (o0.x86RmSize != size) {
              s = _S.OperandSizeMismatch;
              continue loop;
            }

            opcode = _addArithBySize(opcode, size);
            {
              s = _S.EmitX86OpImplicitMem;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Test:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            if (o0.x86RmSize != o1.x86RmSize) {
              s = _S.OperandSizeMismatch;
              continue loop;
            }

            opcode = _addArithBySize(opcode, o0.x86RmSize);
            rbReg = o0.id;
            opReg = o1.id;

            if (o0.x86RmSize != 1) {
              s = _S.EmitX86R;
              continue loop;
            }

            rbReg = fixupGpb(o0, rbReg);
            opReg = fixupGpb(o1, opReg);
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = _addArithBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rmRel = o0;

            if (o1.x86RmSize != 1) {
              s = _S.EmitX86M;
              continue loop;
            }

            opReg = fixupGpb(o1, opReg);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The following instructions use the secondary opcode.
          opcode = altOpcodeOf(instInfo);
          opReg = X86Opcode.extractModO(opcode);

          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            opcode = _addArithBySize(opcode, o0.x86RmSize);
            rbReg = o0.id;

            if (o0.x86RmSize == 1) {
              rbReg = fixupGpb(o0, rbReg);
              immValue = o1.immU8;
              immSize = 1;
            } else {
              immValue = o1.imm;
              immSize = (math.min(o0.x86RmSize, 4));
            }

            // Short form - AL, AX, EAX, RAX.
            if (rbReg == 0 && !_test(options, _IO.kLongForm)) {
              opcode &= X86Opcode.kPP_66 | X86Opcode.kW;
              opcode |= 0xA8 + _b(o0.x86RmSize != 1);
              {
                s = _S.EmitX86Op;
                continue loop;
              }
            }

            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 34 /* ENC_OPS2(Mem, Imm) */) {
            if (o0.x86RmSize == 0) {
              s = _S.AmbiguousOperandSize;
              continue loop;
            }

            opcode = _addArithBySize(opcode, o0.x86RmSize);
            rmRel = o0;

            immValue = o1.imm;
            immSize = (math.min(o0.x86RmSize, 4));
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Xchg:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opcode = _addArithBySize(opcode, o0.x86RmSize);
            opReg = o0.id;
            rmRel = o1;

            if (o0.x86RmSize != 1) {
              s = _S.EmitX86M;
              continue loop;
            }

            opReg = fixupGpb(o0, opReg);
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.encX86Xadd;
            continue loop;
          }

        case _S.encX86Xadd:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            rbReg = o0.id;
            opReg = o1.id;

            var op_size = o0.x86RmSize;
            if (op_size != o1.x86RmSize) {
              s = _S.OperandSizeMismatch;
              continue loop;
            }

            if (op_size == 1) {
              rbReg = fixupGpb(o0, rbReg);
              opReg = fixupGpb(o1, opReg);
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            // Special cases for 'xchg ?ax, reg'.
            if (instId == X86InstId.kXchg && (opReg == 0 || rbReg == 0)) {
              if (_is64Bit && opReg == rbReg && op_size >= 4) {
                if (op_size == 8) {
                  // Encode 'xchg rax, rax' as '90' (REX and other prefixes are optional).
                  opcode &= X86Opcode.kW;
                  opcode |= 0x90;
                  {
                    s = _S.EmitX86OpReg;
                    continue loop;
                  }
                } else {
                  // Encode 'xchg eax, eax' by using a generic path.
                }
              } else if (!_test(options, _IO.kLongForm)) {
                // The special encoding encodes only one register, which is non-zero.
                opReg += rbReg;

                opcode = _addArithBySize(opcode, op_size);
                opcode &= X86Opcode.kW | X86Opcode.kPP_66;
                opcode |= 0x90;
                {
                  s = _S.EmitX86OpReg;
                  continue loop;
                }
              }
            }

            opcode = _addArithBySize(opcode, op_size);
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = _addArithBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rmRel = o0;

            if (o1.x86RmSize == 1) {
              opReg = fixupGpb(o1, opReg);
            }

            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encX86Fence:
          rbReg = 0;
          {
            s = _S.EmitX86R;
            continue loop;
          }

        case _S.encX86Bndmov:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;

            // ModRM encoding:
            if (!_test(options, _IO.kX86_ModMR)) {
              s = _S.EmitX86R;
              continue loop;
            }

            // ModMR encoding:
            opcode = altOpcodeOf(instInfo);
            {
              final t = opReg;
              opReg = rbReg;
              rbReg = t;
            }
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = altOpcodeOf(instInfo);

            rmRel = o0;
            opReg = o1.id;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        // FPU Instructions
        // ----------------

        case _S.encFpuOp:
          {
            s = _S.EmitFpuOp;
            continue loop;
          }

        case _S.encFpuArith:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;

            // We switch to the alternative opcode if the first operand is zero.
            if (opReg == 0) {
              {
                s = _S.CaseFpuArith_Reg;
                continue loop;
              }
            } else if (rbReg == 0) {
              rbReg = opReg;
              opcode = ((0xDC << X86Opcode.kFPU_2B_Shift)) +
                  ((opcode) & 0xFF) +
                  rbReg;
              {
                s = _S.EmitFpuOp;
                continue loop;
              }
            } else {
              {
                s = _S.InvalidInstruction;
                continue loop;
              }
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            {
              s = _S.CaseFpuArith_Mem;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encFpuCom:
          if (isign3 == 0) {
            rbReg = 1;
            {
              s = _S.CaseFpuArith_Reg;
              continue loop;
            }
          }

          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            rbReg = o0.id;
            {
              s = _S.CaseFpuArith_Reg;
              continue loop;
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            {
              s = _S.CaseFpuArith_Mem;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encFpuFldFst:
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            rmRel = o0;

            if (o0.x86RmSize == 4 && _ciHasFlag(X86InstDbFlags.kFpuM32)) {
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            if (o0.x86RmSize == 8 && _ciHasFlag(X86InstDbFlags.kFpuM64)) {
              opcode += 4;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            if (o0.x86RmSize == 10 && _ciHasFlag(X86InstDbFlags.kFpuM80)) {
              opcode = altOpcodeOf(instInfo);
              opReg = X86Opcode.extractModO(opcode);
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }

          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            if (instId == X86InstId.kFld) {
              opcode = (0xD9 << X86Opcode.kFPU_2B_Shift) + 0xC0 + o0.id;
              {
                s = _S.EmitFpuOp;
                continue loop;
              }
            }
            if (instId == X86InstId.kFst) {
              opcode = (0xDD << X86Opcode.kFPU_2B_Shift) + 0xD0 + o0.id;
              {
                s = _S.EmitFpuOp;
                continue loop;
              }
            }
            if (instId == X86InstId.kFstp) {
              opcode = (0xDD << X86Opcode.kFPU_2B_Shift) + 0xD8 + o0.id;
              {
                s = _S.EmitFpuOp;
                continue loop;
              }
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encFpuM:
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            // Clear compressed displacement before going to EmitX86M.
            opcode &= ~_u32(X86Opcode.kCDSHL_Mask);

            rmRel = o0;
            if (o0.x86RmSize == 2 && _ciHasFlag(X86InstDbFlags.kFpuM16)) {
              opcode += 4;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            if (o0.x86RmSize == 4 && _ciHasFlag(X86InstDbFlags.kFpuM32)) {
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            if (o0.x86RmSize == 8 && _ciHasFlag(X86InstDbFlags.kFpuM64)) {
              opcode = altOpcodeOf(instInfo) & ~_u32(X86Opcode.kCDSHL_Mask);
              opReg = X86Opcode.extractModO(opcode);
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encFpuRDef:
          if (isign3 == 0) {
            opcode += 1;
            {
              s = _S.EmitFpuOp;
              continue loop;
            }
          }
          {
            s = _S.encFpuR;
            continue loop;
          }

        case _S.encFpuR:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            opcode += o0.id;
            {
              s = _S.EmitFpuOp;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encFpuStsw:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            if (o0.id != _kIdAx) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = altOpcodeOf(instInfo);
            {
              s = _S.EmitFpuOp;
              continue loop;
            }
          }

          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            // Clear compressed displacement before going to EmitX86M.
            opcode &= ~_u32(X86Opcode.kCDSHL_Mask);

            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        // Ext Instructions (Legacy Extensions)
        // ------------------------------------

        case _S.encExtPextrw:
          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opcode = _add66hIf(opcode, o1.isVec128());

            immValue = o2.imm;
            immSize = 1;

            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 266 /* ENC_OPS3(Mem, Reg, Imm) */) {
            // Secondary opcode of 'pextrw' instruction (SSE4.1).
            opcode = altOpcodeOf(instInfo);
            opcode = _add66hIf(opcode, o1.isVec128());

            immValue = o2.imm;
            immSize = 1;

            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtExtract:
          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opcode = _add66hIf(opcode, o1.isVec128());

            immValue = o2.imm;
            immSize = 1;

            opReg = o1.id;
            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 266 /* ENC_OPS3(Mem, Reg, Imm) */) {
            opcode = _add66hIf(opcode, o1.isVec128());

            immValue = o2.imm;
            immSize = 1;

            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtMov:
          // GP|MM|XMM <- GP|MM|XMM
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;

            if (!_test(options, _IO.kX86_ModMR) || instInfo.altOpcode == 0) {
              s = _S.EmitX86R;
              continue loop;
            }

            opcode = altOpcodeOf(instInfo);
            {
              final t = opReg;
              opReg = rbReg;
              rbReg = t;
            }
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          // GP|MM|XMM <- Mem
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The following instruction uses opcode[1].
          opcode = altOpcodeOf(instInfo);

          // Mem <- GP|MM|XMM
          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtMovbe:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            if (o0.x86RmSize == 1) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = _addPrefixBySize(opcode, o0.x86RmSize);
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The following instruction uses the secondary opcode.
          opcode = altOpcodeOf(instInfo);

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            if (o1.x86RmSize == 1) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            opcode = _addPrefixBySize(opcode, o1.x86RmSize);
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtMovd:
        case _S.CaseExtMovd:
          if (isMmxOrXmm(o0)) {
            opReg = o0.id;
            opcode = _add66hIf(opcode, o0.isVec128());

            // MM/XMM <- Gp
            if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */ && o1.isGp()) {
              rbReg = o1.id;
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            // MM/XMM <- Mem
            if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
              rmRel = o1;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }

          // The following instructions use the secondary opcode.
          if (isMmxOrXmm(o1)) {
            opcode &= X86Opcode.kW;
            opcode |= altOpcodeOf(instInfo);
            opReg = o1.id;
            opcode = _add66hIf(opcode, o1.isVec128());

            // GP <- MM/XMM
            if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */ && o0.isGp()) {
              rbReg = o0.id;
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            // Mem <- MM/XMM
            if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
              rmRel = o0;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtMovq:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;

            // MM <- MM
            if (o0.isMmReg() && o1.isMmReg()) {
              opcode = X86Opcode.k000F00 | 0x6F;

              if (!_test(options, _IO.kX86_ModMR)) {
                s = _S.EmitX86R;
                continue loop;
              }

              opcode += 0x10;
              {
                final t = opReg;
                opReg = rbReg;
                rbReg = t;
              }
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }

            // XMM <- XMM
            if (o0.isVec128() && o1.isVec128()) {
              opcode = X86Opcode.kF30F00 | 0x7E;

              if (!_test(options, _IO.kX86_ModMR)) {
                s = _S.EmitX86R;
                continue loop;
              }

              opcode = X86Opcode.k660F00 | 0xD6;
              {
                final t = opReg;
                opReg = rbReg;
                rbReg = t;
              }
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;

            // MM <- Mem
            if (o0.isMmReg()) {
              opcode = X86Opcode.k000F00 | 0x6F;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            // XMM <- Mem
            if (o0.isVec128()) {
              opcode = X86Opcode.kF30F00 | 0x7E;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;

            // Mem <- MM
            if (o1.isMmReg()) {
              opcode = X86Opcode.k000F00 | 0x7F;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }

            // Mem <- XMM
            if (o1.isVec128()) {
              opcode = X86Opcode.k660F00 | 0xD6;
              {
                s = _S.EmitX86M;
                continue loop;
              }
            }
          }

          // MOVQ in other case is simply a MOVD instruction promoted to 64-bit.
          opcode |= X86Opcode.kW;
          {
            s = _S.CaseExtMovd;
            continue loop;
          }

        case _S.encExtRm_XMM0:
          if (!o2.isNone() && !o2.isVec128(0)) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          isign3 &= 0x3F;
          {
            s = _S.CaseExtRm;
            continue loop;
          }

        case _S.encExtRm_ZDI:
          if (!o2.isNone() && !isImplicitMem(o2, _kIdDi)) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          isign3 &= 0x3F;
          {
            s = _S.CaseExtRm;
            continue loop;
          }

        case _S.encExtRm_Wx:
          opcode = _addWIf(opcode, o1.x86RmSize == 8);
          {
            s = _S.encExtRm_Wx_GpqOnly;
            continue loop;
          }

        case _S.encExtRm_Wx_GpqOnly:
          opcode = _addWIf(opcode, o0.isGp64());
          {
            s = _S.encExtRm;
            continue loop;
          }

        case _S.encExtRm:
        case _S.CaseExtRm:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtRm_P:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opcode = _add66hIf(opcode, _boolOr(o0.isVec128(), o1.isVec128()));

            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opcode = _add66hIf(opcode, o0.isVec128());

            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtRmRi:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The following instruction uses the secondary opcode.
          opcode = altOpcodeOf(instInfo);
          opReg = X86Opcode.extractModO(opcode);

          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            immValue = o1.imm;
            immSize = 1;

            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtRmRi_P:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opcode = _add66hIf(opcode, _boolOr(o0.isVec128(), o1.isVec128()));

            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opcode = _add66hIf(opcode, o0.isVec128());

            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }

          // The following instruction uses the secondary opcode.
          opcode = altOpcodeOf(instInfo);
          opReg = X86Opcode.extractModO(opcode);

          if (isign3 == 33 /* ENC_OPS2(Reg, Imm) */) {
            opcode = _add66hIf(opcode, o0.isVec128());

            immValue = o1.imm;
            immSize = 1;

            rbReg = o0.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtRmi:
          immValue = o2.imm;
          immSize = 1;

          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtRmi_P:
          immValue = o2.imm;
          immSize = 1;

          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opcode = _add66hIf(opcode, _boolOr(o0.isVec128(), o1.isVec128()));

            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opcode = _add66hIf(opcode, o0.isVec128());

            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        // Extrq & Insertq (SSE4A)
        // -----------------------

        case _S.encExtExtrq:
          opReg = o0.id;
          rbReg = o1.id;

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            s = _S.EmitX86R;
            continue loop;
          }

          if (isign3 == 289 /* ENC_OPS3(Reg, Imm, Imm) */) {
            // This variant of the instruction uses the secondary opcode.
            opcode = altOpcodeOf(instInfo);
            rbReg = opReg;
            opReg = X86Opcode.extractModO(opcode);

            immValue = (_u32(o1.immU8)) + (_u32(o2.immU8) << 8);
            immSize = 2;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encExtInsertq:
          {
            final o3 = opExt[3];
            final isign4 = isign3 + (_u32(o3.opType) << 9);

            opReg = o0.id;
            rbReg = o1.id;

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              s = _S.EmitX86R;
              continue loop;
            }

            if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
              // This variant of the instruction uses the secondary opcode.
              opcode = altOpcodeOf(instInfo);

              immValue = (_u32(o2.immU8)) + (_u32(o3.immU8) << 8);
              immSize = 2;
              {
                s = _S.EmitX86R;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          // 3DNOW Instructions
          // ------------------

          s = _S.encExt3dNow;
          continue loop; // (after block)
        case _S.encExt3dNow:
          // Every 3dNow instruction starts with 0x0F0F and the actual opcode is
          // stored as 8-bit immediate.
          immValue = opcode & 0xFF;
          immSize = 1;

          opcode = X86Opcode.k000F00 | 0x0F;
          opReg = o0.id;

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            rbReg = o1.id;
            {
              s = _S.EmitX86R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            rmRel = o1;
            {
              s = _S.EmitX86M;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        // VEX/EVEX Instructions
        // ---------------------

        case _S.encVexOp:
          {
            s = _S.EmitVexOp;
            continue loop;
          }

        case _S.encVexOpMod:
          rbReg = 0;
          {
            s = _S.EmitVexEvexR;
            continue loop;
          }

        case _S.encVexKmov:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;

            // Form 'k, reg'.
            if (o1.isGp()) {
              opcode = altOpcodeOf(instInfo);
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            // Form 'reg, k'.
            if (o0.isGp()) {
              opcode = altOpcodeOf(instInfo) + 1;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            // Form 'k, k'.
            if (!_test(options, _IO.kX86_ModMR)) {
              s = _S.EmitVexEvexR;
              continue loop;
            }

            opcode = _add(opcode, 1);
            {
              final t = opReg;
              opReg = rbReg;
              rbReg = t;
            }
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;

            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = _add(opcode, 1);
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexR_Wx:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            rbReg = o0.id;
            opcode = _addWIf(opcode, o0.isGp64());
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexM:
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexMr_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o1.id;
            rbReg = o0.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexMr_VM:
          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode |= _max(opcodeLByVmem(o0), opcodeLBySize(o1.x86RmSize));

            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexMri_Vpextrw:
          // Use 'vpextrw reg, xmm1, i8' when possible.
          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opcode = X86Opcode.k660F00 | 0xC5;

            opReg = o0.id;
            rbReg = o1.id;

            immValue = o2.imm;
            immSize = 1;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          {
            s = _S.CaseVexMri;
            continue loop;
          }

        case _S.encVexMvr_Wx:
          if (isign3 == 74 /* ENC_OPS3(Mem, Reg, Reg) */) {
            opcode = _addWIf(opcode, o1.isGp64());
            opReg = packRegAndVvvvv(o1.id, o2.id);
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexMri_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexMri;
            continue loop;
          }

        case _S.encVexMri:
        case _S.CaseVexMri:
          immValue = o2.imm;
          immSize = 1;

          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opReg = o1.id;
            rbReg = o0.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 266 /* ENC_OPS3(Mem, Reg, Imm) */) {
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRm_ZDI:
          if (!o2.isNone() && !isImplicitMem(o2, _kIdDi)) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          isign3 &= 0x3F;
          {
            s = _S.CaseVexRm;
            continue loop;
          }

        case _S.encVexRm_Wx:
          opcode = _addWIf(opcode, _boolOr(o0.isGp64(), o1.isGp64()));
          {
            s = _S.CaseVexRm;
            continue loop;
          }

        case _S.encVexRm_Lx_Narrow:
          if (o1.x86RmSize != 0)
            opcode |= opcodeLBySize(o1.x86RmSize);
          else if (o0.x86RmSize == 32) opcode |= X86Opcode.kLL_2;
          {
            s = _S.CaseVexRm;
            continue loop;
          }

        case _S.encVexRm_Lx_Bcst:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */ && o1.isGp()) {
            opcode = altOpcodeOf(instInfo) |
                opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }
          {
            s = _S.encVexRm_Lx;
            continue loop;
          }

        case _S.encVexRm_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRm;
            continue loop;
          }

        case _S.encVexRm:
        case _S.CaseVexRm:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRm_VM:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opcode |= _max(opcodeLByVmem(o1), opcodeLBySize(o0.x86RmSize));
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRmi_Wx:
          opcode = _addWIf(opcode, _boolOr(o0.isGp64(), o1.isGp64()));
          {
            s = _S.CaseVexRmi;
            continue loop;
          }

        case _S.encVexRmi_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRmi;
            continue loop;
          }

        case _S.encVexRmi:
        case _S.CaseVexRmi:
          immValue = o2.imm;
          immSize = 1;

          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvm:
        case _S.CaseVexRvm:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            {
              s = _S.CaseVexRvm_R;
              continue loop;
            }
          }

          if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rmRel = o2;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvm_ZDX_Wx:
          {
            final o3 = opExt[3];
            if (!o3.isNone() && !o3.isGp(_kIdDx)) {
              s = _S.InvalidInstruction;
              continue loop;
            }
            {
              s = _S.encVexRvm_Wx;
              continue loop;
            }
          }

          s = _S.encVexRvm_Wx;
          continue loop; // (after block)
        case _S.encVexRvm_Wx:
          {
            opcode = _addWIf(opcode, _boolOr(o0.isGp64(), o2.x86RmSize == 8));
            {
              s = _S.CaseVexRvm;
              continue loop;
            }
          }

          s = _S.encVexRvm_Lx_KEvex;
          continue loop; // (after block)
        case _S.encVexRvm_Lx_KEvex:
          {
            opcode = _forceEvexIf(opcode, o0.isMaskReg());
            {
              s = _S.encVexRvm_Lx;
              continue loop;
            }
          }

          s = _S.encVexRvm_Lx;
          continue loop; // (after block)
        case _S.encVexRvm_Lx:
          {
            opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
            {
              s = _S.CaseVexRvm;
              continue loop;
            }
          }

          s = _S.encVexRvm_Lx_2xK;
          continue loop; // (after block)
        case _S.encVexRvm_Lx_2xK:
          {
            if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              // Two registers are encoded as a single register.
              //   - First K register must be even.
              //   - Second K register must be first+1.
              if ((o0.id & 1) != 0 || o0.id + 1 != o1.id) {
                s = _S.InvalidPhysId;
                continue loop;
              }

              final o3 = opExt[3];

              opcode |= opcodeLBySize(o2.x86RmSize);
              opReg = packRegAndVvvvv(o0.id, o2.id);

              if (o3.isReg()) {
                rbReg = o3.id;
                {
                  s = _S.EmitVexEvexR;
                  continue loop;
                }
              }

              if (o3.isMem()) {
                rmRel = o3;
                {
                  s = _S.EmitVexEvexM;
                  continue loop;
                }
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encVexRvmr_Lx;
          continue loop; // (after block)
        case _S.encVexRvmr_Lx:
          {
            opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
            {
              s = _S.encVexRvmr;
              continue loop;
            }
          }

          s = _S.encVexRvmr;
          continue loop; // (after block)
        case _S.encVexRvmr:
          {
            final o3 = opExt[3];
            final isign4 = isign3 + (_u32(o3.opType) << 9);

            immValue = o3.id << 4;
            immSize = 1;

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rbReg = o2.id;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            if (isign4 == 649 /* ENC_OPS4(Reg, Reg, Mem, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o2;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encVexRvmi_KEvex;
          continue loop; // (after block)
        case _S.encVexRvmi_KEvex:
          opcode = _forceEvexIf(opcode, o0.isMaskReg());
          {
            s = _S.VexRvmi;
            continue loop;
          }

        case _S.encVexRvmi_Lx_KEvex:
          opcode = _forceEvexIf(opcode, o0.isMaskReg());
          {
            s = _S.encVexRvmi_Lx;
            continue loop;
          }

        case _S.encVexRvmi_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRvmi;
            continue loop;
          }

        case _S.encVexRvmi:
        case _S.VexRvmi:
          {
            final o3 = opExt[3];
            final isign4 = isign3 + (_u32(o3.opType) << 9);

            immValue = o3.imm;
            immSize = 1;

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rbReg = o2.id;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            if (isign4 == 2185 /* ENC_OPS4(Reg, Reg, Mem, Imm) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o2;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encVexRmv_Wx;
          continue loop; // (after block)
        case _S.encVexRmv_Wx:
          opcode = _addWIf(opcode, _boolOr(o0.isGp64(), o2.isGp64()));
          {
            s = _S.encVexRmv;
            continue loop;
          }

        case _S.encVexRmv:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o2.id);
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 81 /* ENC_OPS3(Reg, Mem, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o2.id);
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRmvRm_VM:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opcode = altOpcodeOf(instInfo);
            opcode |= _max(opcodeLByVmem(o1), opcodeLBySize(o0.x86RmSize));

            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.encVexRmv_VM;
            continue loop;
          }

        case _S.encVexRmv_VM:
          if (isign3 == 81 /* ENC_OPS3(Reg, Mem, Reg) */) {
            opcode |= _max(
                opcodeLByVmem(o1), opcodeLBySize(o0.x86RmSize | o2.x86RmSize));

            opReg = packRegAndVvvvv(o0.id, o2.id);
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRmvi:
          {
            final o3 = opExt[3];
            final isign4 = isign3 + (_u32(o3.opType) << 9);

            immValue = o3.imm;
            immSize = 1;

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              opReg = packRegAndVvvvv(o0.id, o2.id);
              rbReg = o1.id;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            if (isign4 == 2129 /* ENC_OPS4(Reg, Mem, Reg, Imm) */) {
              opReg = packRegAndVvvvv(o0.id, o2.id);
              rmRel = o1;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encVexMovdMovq;
          continue loop; // (after block)
        case _S.encVexMovdMovq:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            if (o0.isGp()) {
              opcode = altOpcodeOf(instInfo);
              opcode = _addWBySize(opcode, o0.x86RmSize);
              opReg = o1.id;
              rbReg = o0.id;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            if (o1.isGp()) {
              opcode = _addWBySize(opcode, o1.x86RmSize);
              opReg = o0.id;
              rbReg = o1.id;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            // If this is a 'W' version (movq) then allow also vmovq 'xmm|xmm' form.
            if ((opcode & X86Opcode.kEvex_W_1) != 0) {
              opcode &= ~(X86Opcode.kPP_VEXMask | X86Opcode.kMM_Mask | 0xFF);
              opcode |= (X86Opcode.kF30F00 | 0x7E);

              opReg = o0.id;
              rbReg = o1.id;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            if ((opcode & X86Opcode.kEvex_W_1) != 0) {
              opcode &= ~(X86Opcode.kPP_VEXMask | X86Opcode.kMM_Mask | 0xFF);
              opcode |= (X86Opcode.kF30F00 | 0x7E);
            }

            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          // The following instruction uses the secondary opcode.
          opcode = altOpcodeOf(instInfo);

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            if ((opcode & X86Opcode.kEvex_W_1) != 0) {
              opcode &= ~(X86Opcode.kPP_VEXMask | X86Opcode.kMM_Mask | 0xFF);
              opcode |= (X86Opcode.k660F00 | 0xD6);
            }

            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRmMr_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRmMr;
            continue loop;
          }

        case _S.encVexRmMr:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          // The following instruction uses the secondary opcode.
          opcode &= X86Opcode.kLL_Mask;
          opcode |= altOpcodeOf(instInfo);

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvmRmv:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o2.id);
            rbReg = o1.id;

            if (!_test(options, _IO.kX86_ModMR)) {
              s = _S.EmitVexEvexR;
              continue loop;
            }

            opcode = _addW(opcode);
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rbReg = o2.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 81 /* ENC_OPS3(Reg, Mem, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o2.id);
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
            opcode = _addW(opcode);
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rmRel = o2;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvmRmi_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRvmRmi;
            continue loop;
          }

        case _S.encVexRvmRmi:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rbReg = o2.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rmRel = o2;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          // The following instructions use the secondary opcode.
          opcode &= X86Opcode.kLL_Mask;
          opcode |= altOpcodeOf(instInfo);

          immValue = o2.imm;
          immSize = 1;

          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvmRmvRmi:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o2.id);
            rbReg = o1.id;

            if (!_test(options, _IO.kX86_ModMR)) {
              s = _S.EmitVexEvexR;
              continue loop;
            }

            opcode = _addW(opcode);
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rbReg = o2.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 81 /* ENC_OPS3(Reg, Mem, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o2.id);
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
            opcode = _addW(opcode);
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rmRel = o2;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          // The following instructions use the secondary opcode.
          opcode = altOpcodeOf(instInfo);

          immValue = o2.imm;
          immSize = 1;

          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opReg = o0.id;
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvmMr:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rbReg = o2.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rmRel = o2;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          // The following instructions use the secondary opcode.
          opcode = altOpcodeOf(instInfo);

          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = o1.id;
            rbReg = o0.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvmMvr_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRvmMvr;
            continue loop;
          }

        case _S.encVexRvmMvr:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rbReg = o2.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rmRel = o2;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          // The following instruction uses the secondary opcode.
          opcode &= X86Opcode.kLL_Mask;
          opcode |= altOpcodeOf(instInfo);

          if (isign3 == 74 /* ENC_OPS3(Mem, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o2.id, o1.id);
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexRvmVmi_Lx_MEvex:
          opcode = _forceEvexIf(opcode, o1.isMem());
          {
            s = _S.encVexRvmVmi_Lx;
            continue loop;
          }

        case _S.encVexRvmVmi_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRvmVmi;
            continue loop;
          }

        case _S.encVexRvmVmi:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rbReg = o2.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
            opReg = packRegAndVvvvv(o0.id, o1.id);
            rmRel = o2;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          // The following instruction uses the secondary opcode.
          opcode &= X86Opcode.kLL_Mask | X86Opcode.kMM_ForceEvex;
          opcode |= altOpcodeOf(instInfo);
          opReg = X86Opcode.extractModO(opcode);

          immValue = o2.imm;
          immSize = 1;

          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opReg = packRegAndVvvvv(opReg, o0.id);
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opReg = packRegAndVvvvv(opReg, o0.id);
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexVm_Wx:
          opcode = _addWIf(opcode, _boolOr(o0.isGp64(), o1.isGp64()));
          {
            s = _S.encVexVm;
            continue loop;
          }

        case _S.encVexVm:
          if (isign3 == 9 /* ENC_OPS2(Reg, Reg) */) {
            opReg = packRegAndVvvvv(opReg, o0.id);
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = packRegAndVvvvv(opReg, o0.id);
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexVmi_Lx_MEvex:
          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */)
            opcode = _forceEvex(opcode);
          {
            s = _S.encVexVmi_Lx;
            continue loop;
          }

        case _S.encVexVmi_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexVmi;
            continue loop;
          }

        case _S.encVexVmi:
          immValue = o2.imm;
          immSize = 1;

          s = _S.CaseVexVmi_AfterImm;
          continue loop;
        case _S.CaseVexVmi_AfterImm:
          if (isign3 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
            opReg = packRegAndVvvvv(opReg, o0.id);
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }

          if (isign3 == 273 /* ENC_OPS3(Reg, Mem, Imm) */) {
            opReg = packRegAndVvvvv(opReg, o0.id);
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encVexVmi4_Wx:
          opcode = _addWIf(opcode, _boolOr(o0.isGp64(), o1.x86RmSize == 8));
          immValue = o2.imm;
          immSize = 4;
          {
            s = _S.CaseVexVmi_AfterImm;
            continue loop;
          }

        case _S.encVexRvrmRvmr_Lx:
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encVexRvrmRvmr;
            continue loop;
          }

        case _S.encVexRvrmRvmr:
          {
            final o3 = opExt[3];
            final isign4 = isign3 + (_u32(o3.opType) << 9);

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rbReg = o2.id;

              immValue = o3.id << 4;
              immSize = 1;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            if (isign4 == 1097 /* ENC_OPS4(Reg, Reg, Reg, Mem) */) {
              opcode = _addW(opcode);
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o3;

              immValue = o2.id << 4;
              immSize = 1;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }

            if (isign4 == 649 /* ENC_OPS4(Reg, Reg, Mem, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o2;

              immValue = o3.id << 4;
              immSize = 1;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encVexRvrmiRvmri_Lx;
          continue loop; // (after block)
        case _S.encVexRvrmiRvmri_Lx:
          {
            final o3 = opExt[3];
            final o4 = opExt[4];

            if (!o4.isImm()) {
              s = _S.InvalidInstruction;
              continue loop;
            }

            final isign4 = isign3 + (_u32(o3.opType) << 9);
            opcode |= opcodeLBySize(
                o0.x86RmSize | o1.x86RmSize | o2.x86RmSize | o3.x86RmSize);

            immValue = o4.immU8 & 0x0F;
            immSize = 1;

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rbReg = o2.id;

              immValue |= o3.id << 4;
              {
                s = _S.EmitVexEvexR;
                continue loop;
              }
            }

            if (isign4 == 1097 /* ENC_OPS4(Reg, Reg, Reg, Mem) */) {
              opcode = _addW(opcode);
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o3;

              immValue |= o2.id << 4;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }

            if (isign4 == 649 /* ENC_OPS4(Reg, Reg, Mem, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o2;

              immValue |= o3.id << 4;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          s = _S.encVexMovssMovsd;
          continue loop; // (after block)
        case _S.encVexMovssMovsd:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            {
              s = _S.CaseVexRvm_R;
              continue loop;
            }
          }

          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }

          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opcode = altOpcodeOf(instInfo);
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        // FMA4 Instructions
        // -----------------

        case _S.encFma4_Lx:
          // It's fine to just check the first operand, second is just for sanity.
          opcode |= opcodeLBySize(o0.x86RmSize | o1.x86RmSize);
          {
            s = _S.encFma4;
            continue loop;
          }

        case _S.encFma4:
          {
            final o3 = opExt[3];
            final isign4 = isign3 + (_u32(o3.opType) << 9);

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);

              if (!_test(options, _IO.kX86_ModMR)) {
                // MOD/RM - Encoding preferred by LLVM.
                opcode = _addW(opcode);
                rbReg = o3.id;

                immValue = o2.id << 4;
                immSize = 1;
                {
                  s = _S.EmitVexEvexR;
                  continue loop;
                }
              } else {
                // MOD/MR - Alternative encoding.
                rbReg = o2.id;

                immValue = o3.id << 4;
                immSize = 1;
                {
                  s = _S.EmitVexEvexR;
                  continue loop;
                }
              }
            }

            if (isign4 == 1097 /* ENC_OPS4(Reg, Reg, Reg, Mem) */) {
              opcode = _addW(opcode);
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o3;

              immValue = o2.id << 4;
              immSize = 1;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }

            if (isign4 == 649 /* ENC_OPS4(Reg, Reg, Mem, Reg) */) {
              opReg = packRegAndVvvvv(o0.id, o1.id);
              rmRel = o2;

              immValue = o3.id << 4;
              immSize = 1;
              {
                s = _S.EmitVexEvexM;
                continue loop;
              }
            }
            {
              s = _S.InvalidInstruction;
              continue loop;
            }
          }

          // AMX Instructions
          // ----------------

          s = _S.encAmxCfg;
          continue loop; // (after block)
        case _S.encAmxCfg:
          if (isign3 == 2 /* ENC_OPS1(Mem) */) {
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encAmxR:
          if (isign3 == 1 /* ENC_OPS1(Reg) */) {
            opReg = o0.id;
            rbReg = 0;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encAmxRm:
          if (isign3 == 17 /* ENC_OPS2(Reg, Mem) */) {
            opReg = o0.id;
            rmRel = o1;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encAmxMr:
          if (isign3 == 10 /* ENC_OPS2(Mem, Reg) */) {
            opReg = o1.id;
            rmRel = o0;
            {
              s = _S.EmitVexEvexM;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        case _S.encAmxRmv:
          if (isign3 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
            opReg = packRegAndVvvvv(o0.id, o2.id);
            rbReg = o1.id;
            {
              s = _S.EmitVexEvexR;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        // Emit - X86 Opcode
        // -----------------

        case _S.EmitX86OpMovAbs:
          immSize = (_registerSize);
          _w.emitSegmentOverride(rmRel!.segmentId);

          s = _S.EmitX86Op;
          continue loop;
        case _S.EmitX86Op:
          // Emit mandatory instruction prefix.
          _w.emitPp(opcode);

          // Emit REX prefix (64-bit only).
          {
            var rex = _extractRex(opcode, options);
            if (_isRexInvalid(rex)) {
              s = _S.InvalidRexPrefix;
              continue loop;
            }
            rex &= ~_kByteInvalidRex & 0xFF;
            _w.emit8If(rex | _kByteRex, rex != 0);
          }

          // Emit instruction opcodes.
          _w.emitMmAndOpcode(opcode);
          _w.emitImmediate((immValue), immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Emit - X86 - Opcode + Reg
        // -------------------------

        case _S.EmitX86OpReg:
          // Emit mandatory instruction prefix.
          _w.emitPp(opcode);

          // Emit REX prefix (64-bit only).
          {
            var rex =
                _extractRex(opcode, options) | (opReg >> 3); // Rex.B (0x01).
            if (_isRexInvalid(rex)) {
              s = _S.InvalidRexPrefix;
              continue loop;
            }
            rex &= ~_kByteInvalidRex & 0xFF;
            _w.emit8If(rex | _kByteRex, rex != 0);

            opReg &= 0x7;
          }

          // Emit instruction opcodes.
          opcode += opReg;
          _w.emitMmAndOpcode(opcode);
          _w.emitImmediate((immValue), immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Emit - X86 - Opcode with Implicit <mem> Operand
        // -----------------------------------------------

        case _S.EmitX86OpImplicitMem:
          rmInfo = memInfoTable[rmRel!.baseAndIndexTypes];
          if (rmRel!.hasOffset() || (rmInfo & _kMemInfoIndex) != 0) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          // Emit mandatory instruction prefix.
          _w.emitPp(opcode);

          // Emit REX prefix (64-bit only).
          {
            var rex = _extractRex(opcode, options);
            if (_isRexInvalid(rex)) {
              s = _S.InvalidRexPrefix;
              continue loop;
            }
            rex &= ~_kByteInvalidRex & 0xFF;
            _w.emit8If(rex | _kByteRex, rex != 0);
          }

          // Emit override prefixes.
          _w.emitSegmentOverride(rmRel!.segmentId);
          _w.emitAddressOverride((rmInfo & _addressOverrideMask) != 0);

          // Emit instruction opcodes.
          _w.emitMmAndOpcode(opcode);

          // Emit immediate value.
          _w.emitImmediate((immValue), immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Emit - X86 - Opcode /r - Register
        // ---------------------------------

        case _S.EmitX86R:
          // Mandatory instruction prefix.
          _w.emitPp(opcode);

          // Emit REX prefix (64-bit only).
          {
            var rex = _extractRex(opcode, options) |
                ((opReg & 0x08) >> 1) | // REX.R (0x04).
                ((rbReg & 0x08) >> 3); // REX.B (0x01).

            if (_isRexInvalid(rex)) {
              s = _S.InvalidRexPrefix;
              continue loop;
            }
            rex &= ~_kByteInvalidRex & 0xFF;
            _w.emit8If(rex | _kByteRex, rex != 0);

            opReg &= 0x07;
            rbReg &= 0x07;
          }

          // Emit instruction opcodes.
          _w.emitMmAndOpcode(opcode);

          // Emit ModR.
          _w.emit8(encodeMod(3, opReg, rbReg));

          // Emit immediate value.
          _w.emitImmediate((immValue), immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Emit - X86 - Opcode /r - Memory Base
        // ------------------------------------

        case _S.EmitX86RFromM:
          rmInfo = memInfoTable[rmRel!.baseAndIndexTypes];
          if (rmRel!.hasOffset() || (rmInfo & _kMemInfoIndex) != 0) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          // Emit mandatory instruction prefix.
          _w.emitPp(opcode);

          // Emit REX prefix (64-bit only).
          {
            var rex = _extractRex(opcode, options) |
                ((opReg & 0x08) >> 1) | // REX.R (0x04).
                ((rbReg) >> 3); // REX.B (0x01).

            if (_isRexInvalid(rex)) {
              s = _S.InvalidRexPrefix;
              continue loop;
            }
            rex &= ~_kByteInvalidRex & 0xFF;
            _w.emit8If(rex | _kByteRex, rex != 0);

            opReg &= 0x07;
            rbReg &= 0x07;
          }

          // Emit override prefixes.
          _w.emitSegmentOverride(rmRel!.segmentId);
          _w.emitAddressOverride((rmInfo & _addressOverrideMask) != 0);

          // Emit instruction opcodes.
          _w.emitMmAndOpcode(opcode);

          // Emit ModR/M.
          _w.emit8(encodeMod(3, opReg, rbReg));

          // Emit immediate value.
          _w.emitImmediate((immValue), immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Emit - X86 - Opcode /r - memory Operand
        // ---------------------------------------

        case _S.EmitX86M:
          // `rm_rel` operand must be memory.
          // ASMJIT_ASSERT(rmRel != nullptr);
          // ASMJIT_ASSERT(rmRel!.opType == OperandType::kMem);
          // ASMJIT_ASSERT((opcode & X86Opcode.kCDSHL_Mask) == 0);

          // Emit override prefixes.
          rmInfo = memInfoTable[rmRel!.baseAndIndexTypes];
          _w.emitSegmentOverride(rmRel!.segmentId);

          memOpAoMark = _w.cursor;
          _w.emitAddressOverride((rmInfo & _addressOverrideMask) != 0);

          // Emit mandatory instruction prefix.
          _w.emitPp(opcode);

          // Emit REX prefix (64-bit only).
          rbReg = rmRel!.baseId;
          rxReg = rmRel!.indexId;
          {
            int rex;

            rex = (rbReg >> 3) & 0x01; // REX.B (0x01).
            rex |= (rxReg >> 2) & 0x02; // REX.X (0x02).
            rex |= (opReg >> 1) & 0x04; // REX.R (0x04).

            rex &= rmInfo;
            rex |= _extractRex(opcode, options);

            if (_isRexInvalid(rex)) {
              s = _S.InvalidRexPrefix;
              continue loop;
            }
            rex &= ~_kByteInvalidRex & 0xFF;
            _w.emit8If(rex | _kByteRex, rex != 0);

            opReg &= 0x07;
          }

          // Emit instruction opcodes.
          _w.emitMmAndOpcode(opcode);

          // ... Fall through ...

          // Emit - MOD/SIB
          // --------------

          s = _S.EmitModSib;
          continue loop;
        case _S.EmitModSib:
          if ((rmInfo & (_kMemInfoIndex | _kMemInfo67H_X86)) == 0) {
            // ==========|> [BASE + DISP8|DISP32].
            if ((rmInfo & _kMemInfoBaseGp) != 0) {
              rbReg &= 0x7;
              relOffset = rmRel!.offsetLo32;

              var mod = encodeMod(0, opReg, rbReg);
              var force_sib = _ciIsTsibOp();

              if (rbReg == _kIdSp || force_sib) {
                // TSIB or [XSP|R12].
                mod = (mod & 0xF8) | 0x04;
                if (rbReg != _kIdBp && relOffset == 0) {
                  _w.emit8(mod);
                  _w.emit8(encodeSib(0, 4, rbReg));
                }
                // TSIB or [XSP|R12 + DISP8|DISP32].
                else {
                  var cd_shift = (opcode & X86Opcode.kCDSHL_Mask) >>
                      X86Opcode.kCDSHL_Shift;
                  var cd_offset = relOffset >> cd_shift;

                  if (_isIntN(8, cd_offset) &&
                      relOffset == _i32(_u32(cd_offset) << cd_shift)) {
                    _w.emit8(mod + 0x40); // <- MOD(1, opReg, rbReg).
                    _w.emit8(encodeSib(0, 4, rbReg));
                    _w.emit8(cd_offset & 0xFF);
                  } else {
                    _w.emit8(mod + 0x80); // <- MOD(2, opReg, rbReg).
                    _w.emit8(encodeSib(0, 4, rbReg));
                    _w.emit32uLe(_u32(relOffset));
                  }
                }
              } else if (rbReg != _kIdBp && relOffset == 0) {
                // [BASE].
                _w.emit8(mod);
              } else {
                // [BASE + DISP8|DISP32].
                var cd_shift =
                    (opcode & X86Opcode.kCDSHL_Mask) >> X86Opcode.kCDSHL_Shift;
                var cd_offset = relOffset >> cd_shift;

                if (_isIntN(8, cd_offset) &&
                    relOffset == _i32(_u32(cd_offset) << cd_shift)) {
                  _w.emit8(mod + 0x40);
                  _w.emit8(cd_offset & 0xFF);
                } else {
                  _w.emit8(mod + 0x80);
                  _w.emit32uLe(_u32(relOffset));
                }
              }
            }
            // ==========|> [ABSOLUTE | DISP32].
            else if ((rmInfo & (_kMemInfoBaseLabel | _kMemInfoBaseRip)) == 0) {
              var addr_type = rmRel!.addrType;
              relOffset = rmRel!.offsetLo32;

              if (_is32Bit) {
                // Explicit relative addressing doesn't work in 32-bit mode.
                if (addr_type == _Addr.kRel) {
                  s = _S.InvalidAddress;
                  continue loop;
                }

                _w.emit8(encodeMod(0, opReg, 5));
                _w.emit32uLe(_u32(relOffset));
              } else {
                var is_offset_int32 = rmRel!.offsetHi32 == (relOffset >> 31);
                var is_offset_uint32 = rmRel!.offsetHi32 == 0;
                final baseAddress = code.baseAddress;

                // If relative addressing was not explicitly set then we can try to guess. By guessing we check some
                // properties of the memory operand and try to base the decision on the segment prefix and the address type.
                if (addr_type == _Addr.kDefault) {
                  if (baseAddress == null) {
                    // Prefer absolute addressing mode if the offset is 32-bit.
                    addr_type = is_offset_int32 || is_offset_uint32
                        ? _Addr.kAbs
                        : _Addr.kRel;
                  } else {
                    // Prefer absolute addressing mode if FS|GS segment override is present.
                    var has_fs_gs = rmRel!.segmentId >= _kSegFs;
                    // Prefer absolute addressing mode if this is LEA with 32-bit immediate.
                    var is_lea_32 = (instId == X86InstId.kLea) &&
                        (is_offset_int32 || is_offset_uint32);

                    addr_type =
                        has_fs_gs || is_lea_32 ? _Addr.kAbs : _Addr.kRel;
                  }
                }

                if (addr_type == _Addr.kRel) {
                  var kModRel32Size = 5;
                  var virtualOffset = _w.cursor + immSize + kModRel32Size;

                  if (baseAddress == null) {
                    // Create a new RelocEntry as we cannot calculate the offset right now.
                    final re = code.newRelocEntry(RelocType.absToRel);

                    _w.emit8(encodeMod(0, opReg, 5));

                    re.sourceSectionId = section.id;
                    re.sourceOffset = instStart;
                    re.format
                      ..resetToSimpleValue(OffsetType.kSignedOffset, 4)
                      ..setLeadingAndTrailingSize(
                          _w.cursor - instStart, immSize);
                    re.payload = rmRel!.offset;

                    _w.emit32uLe(0);
                    _w.emitImmediate(immValue, immSize);
                    {
                      s = _S.EmitDone;
                      continue loop;
                    }
                  } else {
                    var rip64 = baseAddress + virtualOffset;
                    var rel64 = rmRel!.offset - rip64;

                    if (_isIntN(32, rel64)) {
                      _w.emit8(encodeMod(0, opReg, 5));
                      _w.emit32uLe(_u32(rel64 & 0xFFFFFFFF));
                      _w.emitImmediate(immValue, immSize);
                      {
                        s = _S.EmitDone;
                        continue loop;
                      }
                    } else {
                      // We must check the original address type as we have modified
                      // `addr_type`. We failed if the original address type is 'rel'.
                      if (rmRel!.isAddrRel()) {
                        s = _S.InvalidAddress;
                        continue loop;
                      }
                    }
                  }
                }

                // Handle unsigned 32-bit address that doesn't work with sign extension. Consider the following instructions:
                //
                //   1. lea rax, [-1]         - Sign extended to 0xFFFFFFFFFFFFFFFF
                //   2. lea rax, [0xFFFFFFFF] - Zero extended to 0x00000000FFFFFFFF
                //   3. add rax, [-1]         - Sign extended to 0xFFFFFFFFFFFFFFFF
                //   4. add rax, [0xFFFFFFFF] - Zero extended to 0x00000000FFFFFFFF
                //
                // Sign extension is naturally performed by the CPU so we don't have to bother, however, zero extension
                // requires address-size override prefix, which we probably don't have at this moment. So to make the address
                // valid we need to insert it at `mem_op_ao_mark` if it's not already there.
                //
                // If this is 'lea' instruction then it's possible to remove REX.W part from REX prefix (if it's there), which
                // would be one-byte shorter than inserting address-size override.
                //
                // NOTE: If we don't do this then these instructions are unencodable.
                if (!is_offset_int32) {
                  // 64-bit absolute address is unencodable.
                  if (!is_offset_uint32) {
                    s = _S.InvalidAddress64Bit;
                    continue loop;
                  }

                  // We only patch the existing code if we don't have address-size override.
                  if (_w.at(memOpAoMark) != 0x67) {
                    if (instId == X86InstId.kLea) {
                      // LEA: Remove REX.W, if present. This is easy as we know that 'lea' doesn't use any PP prefix so if REX
                      // prefix was emitted it would be at `mem_op_ao_mark`.
                      var rex = _w.at(memOpAoMark);
                      if ((rex & _kByteRex) != 0) {
                        rex &= (~_kByteRexW) & 0xFF;
                        _w.setAt(memOpAoMark, _u8(rex));

                        // We can remove the REX prefix completely if it was not forced.
                        if (rex == _kByteRex && !_test(options, _IO.kX86_Rex))
                          _w.remove8(memOpAoMark);
                      }
                    } else {
                      // Any other instruction: Insert address-size override prefix.
                      _w.insert8(memOpAoMark, 0x67);
                    }
                  }
                }

                // Emit 32-bit absolute address.
                _w.emit8(encodeMod(0, opReg, 4));
                _w.emit8(encodeSib(0, 4, 5));
                _w.emit32uLe(_u32(relOffset));
              }
            }
            // ==========|> [LABEL|RIP + DISP32]
            else {
              _w.emit8(encodeMod(0, opReg, 5));

              if (_is32Bit) {
                {
                  s = _S.EmitModSib_LabelRip_X86;
                  continue loop;
                }
              } else {
                relOffset = rmRel!.offsetLo32;
                if ((rmInfo & _kMemInfoBaseLabel) != 0) {
                  // [RIP].
                  label = rmRel!.label;
                  relOffset -= (4 + immSize);

                  final bound = code.isLabelBoundTo(label!, section.id)
                      ? code.getLabelOffset(label!)
                      : null;
                  if (bound != null) {
                    // Label bound to the current section.
                    relOffset += _i32(bound - _w.cursor);
                    _w.emit32uLe(_u32(relOffset));
                  } else {
                    // Non-bound label or label bound to a different section.
                    relSize = 4;
                    {
                      s = _S.EmitRel;
                      continue loop;
                    }
                  }
                } else {
                  // [RIP].
                  _w.emit32uLe(_u32(relOffset));
                }
              }
            }
          } else if ((rmInfo & _kMemInfo67H_X86) == 0) {
            // ESP|RSP can't be used as INDEX in pure SIB mode, however, VSIB mode allows XMM4|YMM4|ZMM4 (that's why the
            // check is before the label).
            if (rxReg == _kIdSp) {
              s = _S.InvalidAddressIndex;
              continue loop;
            }

            {
              s = _S.EmitModVSib;
              continue loop;
            }
          } else {
            // 16-bit address mode (32-bit mode with 67 override prefix).
            relOffset = (_i32(rmRel!.offsetLo32) << 16) >> 16;

            // NOTE: 16-bit addresses don't use SIB byte and their encoding differs. We use a table-based approach to
            // calculate the proper MOD byte as it's easier. Also, not all BASE [+ INDEX] combinations are supported
            // in 16-bit mode, so this may fail.
            final kBaseGpIdx = (_kMemInfoBaseGp | _kMemInfoIndex);

            if ((rmInfo & kBaseGpIdx) != 0) {
              // ==========|> [BASE + INDEX + DISP16].
              int mod;

              rbReg &= 0x7;
              rxReg &= 0x7;

              if ((rmInfo & kBaseGpIdx) == kBaseGpIdx) {
                var shf = rmRel!.shift;
                if (shf != 0) {
                  s = _S.InvalidAddress;
                  continue loop;
                }
                mod = mod16BaseIndexTable[(rbReg << 3) + rxReg];
              } else {
                if ((rmInfo & _kMemInfoIndex) != 0) rbReg = rxReg;
                mod = mod16BaseTable[rbReg];
              }

              if (mod == 0xFF) {
                s = _S.InvalidAddress;
                continue loop;
              }

              mod += opReg << 3;
              if (relOffset == 0 && mod != 0x06) {
                _w.emit8(mod);
              } else if (_isIntN(8, relOffset)) {
                _w.emit8(mod + 0x40);
                _w.emit8(_u32(relOffset));
              } else {
                _w.emit8(mod + 0x80);
                _w.emit16uLe(_u32(relOffset));
              }
            } else {
              // Not supported in 16-bit addresses.
              if ((rmInfo & (_kMemInfoBaseRip | _kMemInfoBaseLabel)) != 0) {
                s = _S.InvalidAddress;
                continue loop;
              }

              // ==========|> [DISP16].
              _w.emit8(opReg | 0x06);
              _w.emit16uLe(_u32(relOffset));
            }
          }

          _w.emitImmediate((immValue), immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Emit - FPU
        // ----------

        case _S.EmitFpuOp:
          // Mandatory instruction prefix.
          _w.emitPp(opcode);

          // FPU instructions consist of two opcodes.
          _w.emit8(opcode >> X86Opcode.kFPU_2B_Shift);
          _w.emit8(opcode);
          {
            s = _S.EmitDone;
            continue loop;
          }

        // Emit - VEX Opcode
        // -----------------

        case _S.EmitVexOp:
          {
            // These don't use immediate.
            // ASMJIT_ASSERT(immSize == 0);

            // Only 'vzeroall' and 'vzeroupper' instructions use this encoding, they don't define 'W' to be '1' so we can
            // just check the 'mmmmm' field. Both functions can encode by using VEX2 prefix so VEX3 is basically only used
            // when specified as instruction option.
            // ASMJIT_ASSERT((opcode & X86Opcode.kW) == 0);

            var x =
                (_u32(opcode & X86Opcode.kMM_Mask) >> (X86Opcode.kMM_Shift)) |
                    (_u32(opcode & X86Opcode.kLL_Mask) >>
                        (X86Opcode.kLL_Shift - 10)) |
                    (_u32(opcode & X86Opcode.kPP_VEXMask) >>
                        (X86Opcode.kPP_Shift - 8));

            if (_test(options, _IO.kX86_Vex3)) {
              x = (x & 0xFFFF) << 8; // [00000000|00000Lpp|000mmmmm|00000000].
              x ^= (_kByteVex3) | // [........|00000Lpp|000mmmmm|__VEX3__].
                  (0x07 << 13) | // [........|00000Lpp|111mmmmm|__VEX3__].
                  (0x0F << 19) | // [........|01111Lpp|111mmmmm|__VEX3__].
                  (opcode << 24); // [_OPCODE_|01111Lpp|111mmmmm|__VEX3__].

              _w.emit32uLe(x);
              {
                s = _S.EmitDone;
                continue loop;
              }
            } else {
              x = ((x >> 8) ^ x) ^ 0xF9;
              _w.emit8(_kByteVex2);
              _w.emit8(x);
              _w.emit8(opcode);
              {
                s = _S.EmitDone;
                continue loop;
              }
            }
          }

          // Emit - VEX|EVEX - /r - Register
          // -------------------------------

          s = _S.EmitVexEvexR;
          continue loop; // (after block)
        case _S.EmitVexEvexR:
          {
            // Construct `x` - a complete EVEX|VEX prefix.
            var x = ((opReg << 4) &
                    0xF980) | // [........|........|Vvvvv..R|R.......].
                ((rbReg << 2) &
                    0x0060) | // [........|........|........|.BB.....].
                (_extractLLMmmmm(opcode,
                    options)) | // [........|.LL.....|Vvvvv..R|RBBmmmmm].
                (_extraReg.id << 16); // [........|.LL..aaa|Vvvvv..R|RBBmmmmm].
            opReg &= 0x7;

            // Handle AVX512 options by a single branch.
            const kAvx512Options = _IO.kX86_ZMask | _IO.kX86_ER | _IO.kX86_SAE;
            if (_test(options, kAvx512Options)) {
              const kBcstMask = 0x1 << 20;
              const kLLMask10 = 0x2 << 21;
              const kLLMask11 = 0x3 << 21;

              // Designed to be easily encodable so the position must be exact. The {rz-sae} is encoded as {11},
              // so it should match the mask.
              assert(_IO.kX86_RZ_SAE == kLLMask11);

              x |= _u32(options &
                  _IO.kX86_ZMask); // [........|zLLb.aaa|Vvvvv..R|RBBmmmmm].

              // Support embedded-rounding {er} and suppress-all-exceptions {sae}.
              if (_test(options, _IO.kX86_ER | _IO.kX86_SAE)) {
                // Embedded rounding is only encodable if the instruction is either scalar or it's a 512-bit
                // operation as the {er} rounding predicate collides with LL part of the instruction.
                if ((x & kLLMask11) != kLLMask10) {
                  // Ok, so LL is not 10, thus the instruction must be scalar. Scalar instructions don't
                  // support broadcast so if this instruction supports it {er} nor {sae} would be encodable.
                  if (_ciHasAvx512Bcst()) {
                    s = _S.InvalidEROrSAE;
                    continue loop;
                  }
                }

                if (_test(options, _IO.kX86_ER)) {
                  if (!_ciHasAvx512Er()) {
                    s = _S.InvalidEROrSAE;
                    continue loop;
                  }

                  x &= ~kLLMask11; // [........|.00..aaa|Vvvvv..R|RBBmmmmm].
                  x |= kBcstMask |
                      (_u32(options) &
                          kLLMask11); // [........|.LLb.aaa|Vvvvv..R|RBBmmmmm].
                } else {
                  if (!_ciHasAvx512Sae()) {
                    s = _S.InvalidEROrSAE;
                    continue loop;
                  }

                  x &= ~kLLMask11; // [........|.00..aaa|Vvvvv..R|RBBmmmmm].
                  x |= kBcstMask; // [........|.00b.aaa|Vvvvv..R|RBBmmmmm].
                }
              }
            }

            // These bits would force EVEX prefix.
            const kEvexForce =
                0x00000010; // [........|........|........|...x....].
            const kEvexBits =
                0x00D78150; // [........|xx.x.xxx|x......x|.x.x....].

            // Force EVEX prefix even in case the instruction has VEX encoding, because EVEX encoding is preferred. At the
            // moment this is only required by AVX_VNNI instructions, which were added after AVX512_VNNI instructions. If
            // such instruction doesn't specify prefix, EVEX (AVX512_VNNI) is selected by default.
            if (_ciPreferEvex()) {
              if ((x & kEvexBits) == 0 &&
                  !_test(options, _IO.kX86_Vex | _IO.kX86_Vex3)) {
                x |= kEvexForce;
              }
            }

            // Check if EVEX is required by checking bits in `x` :     [........|xx.x.xxx|x......x|.x.x....].
            if ((x & kEvexBits) != 0) {
              var y = ((x << 4) &
                      0x00080000) | // [........|...bV...|........|........].
                  ((x >> 4) &
                      0x00000010); // [........|...bV...|........|...R....].
              x = (x & 0x00FF78EF) |
                  y; // [........|zLLbVaaa|0vvvv000|RBBRmmmm].
              x = x << 8; // [zLLbVaaa|0vvvv000|RBBRmmmm|00000000].
              x |= (opcode >> kVSHR_W) &
                  0x00800000; // [zLLbVaaa|Wvvvv000|RBBRmmmm|00000000].
              x |= (opcode >> kVSHR_PP_EW) &
                  0x00830000; // [zLLbVaaa|Wvvvv0pp|RBBRmmmm|00000000] (added PP and EVEX.W).
              //      _     ____    ____
              x ^= 0x087CF000 |
                  _kByteEvex; // [zLLbVaaa|Wvvvv1pp|RBBRmmmm|01100010].

              _w.emit32uLe(x);
              _w.emit8(opcode);

              rbReg &= 0x7;
              _w.emit8(encodeMod(3, opReg, rbReg));
              _w.emitImmByteOrDword((immValue), immSize);
              {
                s = _S.EmitDone;
                continue loop;
              }
            }

            // Not EVEX, prepare `x` for VEX2 or VEX3:             x = [........|00L00000|0vvvv000|R0Bmmmmm].
            x |= ((opcode >> (kVSHR_W + 8)) &
                    0x8000) | // [00000000|00L00000|Wvvvv000|R0Bmmmmm].
                ((opcode >> (kVSHR_PP + 8)) &
                    0x0300) | // [00000000|00L00000|0vvvv0pp|R0Bmmmmm].
                ((x >> 11) & 0x0400); // [00000000|00L00000|WvvvvLpp|R0Bmmmmm].
            x |= _forceEvex3MaskInLastBit(
                options); // [x0000000|00L00000|WvvvvLpp|R0Bmmmmm].

            // Check if VEX3 is required / forced:                     [x.......|........|x.......|..xxxxx.].
            if ((x & 0x8000803E) != 0) {
              var xor_mask = vexPrefixTable[x & 0xF] | (opcode << 24);

              // Clear all high bits.
              x = (x & 0xFFFF) << 8; // [00000000|WvvvvLpp|R0Bmmmmm|00000000].
              //            ____    _ _
              x ^= xor_mask; // [_OPCODE_|WvvvvLpp|R1Bmmmmm|VEX3|XOP].
              _w.emit32uLe(x);

              rbReg &= 0x7;
              _w.emit8(encodeMod(3, opReg, rbReg));
              _w.emitImmByteOrDword((immValue), immSize);
              {
                s = _S.EmitDone;
                continue loop;
              }
            } else {
              // 'mmmmm' must be '00001'.
              // ASMJIT_ASSERT((x & 0x1F) == 0x01);

              x = ((x >> 8) ^ x) ^ 0xF9;
              _w.emit8(_kByteVex2);
              _w.emit8(x);
              _w.emit8(opcode);

              rbReg &= 0x7;
              _w.emit8(encodeMod(3, opReg, rbReg));
              _w.emitImmByteOrDword((immValue), immSize);
              {
                s = _S.EmitDone;
                continue loop;
              }
            }
          }

          // Emit - VEX|EVEX - /r - Memory
          // -----------------------------

          s = _S.EmitVexEvexM;
          continue loop; // (after block)
        case _S.EmitVexEvexM:
          // ASMJIT_ASSERT(rmRel != nullptr);
          // ASMJIT_ASSERT(rmRel!.opType == OperandType::kMem);

          rmInfo = memInfoTable[rmRel!.baseAndIndexTypes];
          _w.emitSegmentOverride(rmRel!.segmentId);

          memOpAoMark = _w.cursor;
          _w.emitAddressOverride((rmInfo & _addressOverrideMask) != 0);

          rbReg = rmRel!.hasBaseReg() ? rmRel!.baseId : _u32(0);
          rxReg = rmRel!.hasIndexReg() ? rmRel!.indexId : _u32(0);

          {
            var broadcast_bit = _u32(rmRel!.hasBroadcast());

            // Construct `x` - a complete EVEX|VEX prefix.
            var x = ((opReg << 4) &
                    0x0000F980) | // [........|........|Vvvvv..R|R.......].
                ((rxReg << 3) &
                    0x00000040) | // [........|........|........|.X......].
                ((rxReg << 15) &
                    0x00080000) | // [........|....X...|........|........].
                ((rbReg << 2) &
                    0x00000020) | // [........|........|........|..B.....].
                _extractLLMmmmm(
                    opcode, options) | // [........|.LL.X...|Vvvvv..R|RXBmmmmm].
                (_extraReg.id << 16) | // [........|.LL.Xaaa|Vvvvv..R|RXBmmmmm].
                (broadcast_bit << 20); // [........|.LLbXaaa|Vvvvv..R|RXBmmmmm].
            opReg &= 0x07;

            // Mark invalid VEX (force EVEX) case:                  // [@.......|.LLbXaaa|Vvvvv..R|RXBmmmmm].
            x |= _u32(~ciFlags & X86InstDbFlags.kVex) <<
                (31 - 22 /* ctz(kVex) */);

            // Handle AVX512 options by a single branch.
            const kAvx512Options = _IO.kX86_ZMask | _IO.kX86_ER | _IO.kX86_SAE;
            if (_test(options, kAvx512Options)) {
              // {er} and {sae} are both invalid if memory operand is used.
              if (_test(options, _IO.kX86_ER | _IO.kX86_SAE)) {
                s = _S.InvalidEROrSAE;
                continue loop;
              }

              x |= _u32(options &
                  _IO.kX86_ZMask); // [@.......|zLLbXaaa|Vvvvv..R|RXBmmmmm].
            }

            // If these bits are used then EVEX prefix is required.
            const kEvexForce =
                0x00000010; // [........|........|........|...x....].
            const kEvexBits =
                0x80DF8110; // [@.......|xx.xxxxx|x......x|...x....].

            // Force EVEX prefix even in case the instruction has VEX encoding, because EVEX encoding is preferred. At the
            // moment this is only required for AVX_VNNI instructions, which were added after AVX512_VNNI instructions. If
            // such instruction doesn't specify prefix, EVEX (AVX512_VNNI) would be used by default,
            if (_ciPreferEvex()) {
              if ((x & kEvexBits) == 0 &&
                  !_test(options, _IO.kX86_Vex | _IO.kX86_Vex3)) {
                x |= kEvexForce;
              }
            }

            // Check if EVEX is required by checking bits in `x` :     [@.......|xx.xxxxx|x......x|...x....].
            if ((x & kEvexBits) != 0) {
              var y = ((x << 4) &
                      0x00080000) | // [@.......|....V...|........|........].
                  ((x >> 4) &
                      0x00000010); // [@.......|....V...|........|...R....].
              x = (x & 0x00FF78EF) |
                  y; // [........|zLLbVaaa|0vvvv000|RXBRmmmm].
              x = x << 8; // [zLLbVaaa|0vvvv000|RBBRmmmm|00000000].
              x |= (opcode >> kVSHR_W) &
                  0x00800000; // [zLLbVaaa|Wvvvv000|RBBRmmmm|00000000].
              x |= (opcode >> kVSHR_PP_EW) &
                  0x00830000; // [zLLbVaaa|Wvvvv0pp|RBBRmmmm|00000000] (added PP and EVEX.W).
              //      _     ____    ____
              x ^= 0x087CF000 |
                  _kByteEvex; // [zLLbVaaa|Wvvvv1pp|RBBRmmmm|01100010].

              if ((x & 0x10000000) != 0) {
                // Broadcast support.
                //
                // 1. Verify our LL field is correct as broadcast changes the "size" of the source operand. For example if
                //    a broadcasted operand is qword_ptr[X] {1to8} the source size becomes 64 and not 8 as the memory operand
                //    would report.
                //
                // 2. Change the compressed displacement scale to either x2 (SHL1), x4 (SHL 2), or x8 (SHL 3) depending on
                //    the broadcast unit/element size.
                var broadcast_unit_size = _ciBroadcastSize();
                var broadcast_vector_size =
                    broadcast_unit_size << _u32(rmRel!.getBroadcast);

                if (broadcast_unit_size == 0) {
                  s = _S.InvalidBroadcast;
                  continue loop;
                }

                // LL was already shifted 8 bits right.
                const kLLShift = 21 + 8;

                var current_ll = x & (0x3 << kLLShift);
                var broadcast_ll =
                    (math.max(_ctz(broadcast_vector_size), 4) - 4) << kLLShift;

                if (broadcast_ll > (2 << kLLShift)) {
                  s = _S.InvalidBroadcast;
                  continue loop;
                }

                var new_ll = _max(current_ll, broadcast_ll);
                x = (x & ~(_u32(0x3) << kLLShift)) | new_ll;

                opcode &= ~_u32(X86Opcode.kCDSHL_Mask);
                opcode |= _ctz(broadcast_unit_size) << X86Opcode.kCDSHL_Shift;
              } else {
                // Add the compressed displacement 'SHF' to the opcode based on 'TTWLL'.
                // The index to `cdisp8_shl_table` is composed as `CDTT[4:3] | W[2] | LL[1:0]`.
                var TTWLL = ((opcode >> (X86Opcode.kCDTT_Shift - 3)) & 0x18) +
                    ((opcode >> (X86Opcode.kW_Shift - 2)) & 0x04) +
                    ((x >> 29) & 0x3);
                opcode += cdisp8ShlTable[TTWLL];
              }

              _w.emit32uLe(x);
              _w.emit8(opcode);
            } else {
              // Not EVEX, prepare `x` for VEX2 or VEX3:           x = [........|00L00000|0vvvv000|RXBmmmmm].
              x |= ((opcode >> (kVSHR_W + 8)) &
                      0x8000) | // [00000000|00L00000|Wvvvv000|RXBmmmmm].
                  ((opcode >> (kVSHR_PP + 8)) &
                      0x0300) | // [00000000|00L00000|Wvvvv0pp|RXBmmmmm].
                  ((x >> 11) &
                      0x0400); // [00000000|00L00000|WvvvvLpp|RXBmmmmm].
              x |= _forceEvex3MaskInLastBit(
                  options); // [x0000000|00L00000|WvvvvLpp|RXBmmmmm].

              // Clear a possible CDisp specified by EVEX.
              opcode &= ~X86Opcode.kCDSHL_Mask;

              // Check if VEX3 is required / forced:                   [x.......|........|x.......|.xxxxxx.].
              if ((x & 0x8000807E) != 0) {
                var xor_mask = vexPrefixTable[x & 0xF] | (opcode << 24);

                // Clear all high bits.
                x = (x & 0xFFFF) << 8; // [00000000|WvvvvLpp|RXBmmmmm|00000000].
                //            ____    ___
                x ^= xor_mask; // [_OPCODE_|WvvvvLpp|RXBmmmmm|VEX3_XOP].
                _w.emit32uLe(x);
              } else {
                // 'mmmmm' must be '00001'.
                // ASMJIT_ASSERT((x & 0x1F) == 0x01);

                x = ((x >> 8) ^ x) ^ 0xF9;
                _w.emit8(_kByteVex2);
                _w.emit8(x);
                _w.emit8(opcode);
              }
            }
          }

          // MOD|SIB address.
          if (!_ciHasFlag(X86InstDbFlags.kVsib)) {
            s = _S.EmitModSib;
            continue loop;
          }

          // MOD|VSIB address without INDEX is invalid.
          if ((rmInfo & _kMemInfoIndex) != 0) {
            s = _S.EmitModVSib;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }

        // Emit - Jmp/Jcc/Call
        // -------------------

        case _S.EmitJmpCall:
          {
            // Emit REX prefix if asked for (64-bit only).
            var rex = _extractRex(opcode, options);
            if (_isRexInvalid(rex)) {
              s = _S.InvalidRexPrefix;
              continue loop;
            }
            rex &= ~_kByteInvalidRex & 0xFF;
            _w.emit8If(rex | _kByteRex, rex != 0);

            var ip = _w.cursor;
            rel32 = 0;
            opcode8 = altOpcodeOf(instInfo);

            inst8_size = 1 + 1; //          OPCODE + REL8 .
            inst32_size = 1 + 4; // [PREFIX] OPCODE + REL32.

            // Jcc instructions with 32-bit displacement use 0x0F prefix,
            // other instructions don't. No other prefixes are used by X86.
            // ASMJIT_ASSERT((opcode8 & X86Opcode.kMM_Mask) == 0);
            // ASMJIT_ASSERT((opcode  & X86Opcode.kMM_Mask) == 0 ||
            //               (opcode  & X86Opcode.kMM_Mask) == X86Opcode.kMM_0F);

            // Only one of these should be used at the same time.
            inst32_size += _u32(opReg != 0);
            inst32_size +=
                _u32((opcode & X86Opcode.kMM_Mask) == X86Opcode.kMM_0F);

            if (rmRel!.isLabel()) {
              label = rmRel!.label;
              final bound = code.isLabelBoundTo(label!, section.id)
                  ? code.getLabelOffset(label!)
                  : null;
              if (bound != null) {
                // Label bound to the current section.
                rel32 = _u32((bound - ip - inst32_size) & 0xFFFFFFFF);
                {
                  s = _S.EmitJmpCallRel;
                  continue loop;
                }
              } else {
                // Non-bound label or label bound to a different section.
                if (opcode8 != 0 &&
                    (opcode == 0 || _test(options, _IO.kShortForm))) {
                  _w.emit8(opcode8);

                  // Record DISP8 (non-bound label).
                  relOffset = -1;
                  relSize = 1;
                  {
                    s = _S.EmitRel;
                    continue loop;
                  }
                } else {
                  // Refuse also 'short' prefix, if specified.
                  if (opcode == 0 || _test(options, _IO.kShortForm)) {
                    s = _S.InvalidDisplacement;
                    continue loop;
                  }

                  _w.emit8If(0x0F,
                      (opcode & X86Opcode.kMM_Mask) != 0); // Emit 0F prefix.
                  _w.emit8(opcode); // Emit opcode.
                  _w.emit8If(encodeMod(3, opReg, 0), opReg != 0); // Emit MOD.

                  // Record DISP32 (non-bound label).
                  relOffset = -4;
                  relSize = 4;
                  {
                    s = _S.EmitRel;
                    continue loop;
                  }
                }
              }
            }

            if (rmRel!.isImm()) {
              final baseAddress = code.baseAddress;
              var jump_address = rmRel!.imm;

              // If the base-address is known calculate a relative displacement and check if it fits in 32 bits (which is
              // always true in 32-bit mode). Emit relative displacement as it was a bound label if all checks are ok.
              if (baseAddress != null) {
                var rel64 = jump_address - (ip + baseAddress) - inst32_size;
                if (_isIntN(32, rel64)) {
                  rel32 = _u32(rel64 & 0xFFFFFFFF);
                  {
                    s = _S.EmitJmpCallRel;
                    continue loop;
                  }
                } else {
                  // Relative displacement exceeds 32-bits - relocator can only insert trampoline for jmp/call, but not
                  // for jcc/jecxz.
                  if (!isJmpOrCall(instId)) {
                    s = _S.InvalidDisplacement;
                    continue loop;
                  }
                }
              }

              final re = code.newRelocEntry(RelocType.absToRel);

              re.sourceOffset = instStart;
              re.sourceSectionId = section.id;
              re.payload = jump_address;

              if (opcode != 0) {
                // 64-bit: Emit REX prefix so the instruction can be patched later. REX prefix does nothing if not patched,
                // but allows to patch the instruction to use MOD/M and to point to a memory where the final 64-bit address
                // is stored.
                if (!_is32Bit && isJmpOrCall(instId)) {
                  if (rex == 0) _w.emit8(_kByteRex);

                  code.addAddressToAddressTable(jump_address);

                  re.relocType = RelocType.x64AddressEntry;
                }

                _w.emit8If(0x0F,
                    (opcode & X86Opcode.kMM_Mask) != 0); // Emit 0F prefix.
                _w.emit8(opcode); // Emit opcode.
                _w.emit8If(encodeMod(3, opReg, 0), opReg != 0); // Emit MOD.
                re.format
                  ..resetToSimpleValue(OffsetType.kSignedOffset, 4)
                  ..setLeadingAndTrailingSize(_w.cursor - instStart, immSize);
                _w.emit32uLe(0); // Emit DISP32.
              } else {
                _w.emit8(opcode8); // Emit opcode.
                re.format
                  ..resetToSimpleValue(OffsetType.kSignedOffset, 1)
                  ..setLeadingAndTrailingSize(_w.cursor - instStart, immSize);
                _w.emit8(0); // Emit DISP8 (zero).
              }
              {
                s = _S.EmitDone;
                continue loop;
              }
            }

            // Not Label|Imm -> Invalid.
            {
              s = _S.InvalidInstruction;
              continue loop;
            }

            // Emit jmp/call with relative displacement known at assembly-time. Decide between 8-bit and 32-bit displacement
            // encoding. Some instructions only allow either 8-bit or 32-bit encoding, others allow both encodings.
            {
              s = _S.EmitJmpCallRel;
              continue loop;
            }
          }

          // Emit - Relative
          // ---------------

          s = _S.EmitRel;
          continue loop; // (after block)
        case _S.EmitRel:
          {
            // ASMJIT_ASSERT(relSize == 1 || relSize == 4);

            // Chain with label.
            final offset = _w.cursor;
            final of = OffsetFormat()
              ..resetToSimpleValue(OffsetType.kSignedOffset, relSize);

            final fixup =
                code.newFixup(label!, section.id, offset, relOffset, of);
            if (re != null) fixup.labelOrRelocId = re.id;

            // Emit dummy zeros, must be patched later when the reference becomes known.
            _w.emitZeros(relSize);
          }
          _w.emitImmediate((immValue), immSize);

          // Emit - Done
          // -----------

          {
            s = _S.EmitDone;
            continue loop;
          }
        case _S.CaseX86PushPop_Gp:
          // We allow 2 byte, 4 byte, and 8 byte register sizes, although PUSH and POP only allow 2 bytes or
          // native size. On 64-bit we simply PUSH/POP 64-bit register even if 32-bit register was given.
          if (o0.x86RmSize < 2) {
            s = _S.InvalidInstruction;
            continue loop;
          }

          opcode = altOpcodeOf(instInfo);
          opcode = _add66hBySize(opcode, o0.x86RmSize);
          opReg = o0.id;
          {
            s = _S.EmitX86OpReg;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }
        case _S.CaseFpuArith_Reg:
          opcode = ((0xD8 << X86Opcode.kFPU_2B_Shift)) +
              ((opcode >> X86Opcode.kFPU_2B_Shift) & 0xFF) +
              rbReg;
          {
            s = _S.EmitFpuOp;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }
        case _S.CaseFpuArith_Mem:
          // 0xD8/0xDC, depends on the size of the memory operand; op_reg is valid.
          opcode = (o0.x86RmSize == 4) ? 0xD8 : 0xDC;
          // Clear compressed displacement before going to EmitX86M.
          opcode &= ~_u32(X86Opcode.kCDSHL_Mask);

          rmRel = o0;
          {
            s = _S.EmitX86M;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }
        case _S.CaseVexRvm_R:
          opReg = packRegAndVvvvv(o0.id, o1.id);
          rbReg = o2.id;
          {
            s = _S.EmitVexEvexR;
            continue loop;
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }
        case _S.EmitModSib_LabelRip_X86:
          relOffset = rmRel!.offsetLo32;
          if ((rmInfo & _kMemInfoBaseLabel) != 0) {
            // [LABEL->ABS].
            label = rmRel!.label;
            re = code.newRelocEntry(RelocType.relToAbs);

            re.sourceSectionId = section.id;
            re.sourceOffset = instStart;
            re.format
              ..resetToSimpleValue(OffsetType.kUnsignedOffset, 4)
              ..setLeadingAndTrailingSize(_w.cursor - instStart, immSize);
            re.payload = relOffset;

            final bound = code.getLabelOffset(label!);
            if (bound != null) {
              // Label bound to the current section.
              re.payload += bound;
              re.targetSectionId = code.labelManager.getState(label!).sectionId;
              _w.emit32uLe(0);
            } else {
              // Non-bound label or label bound to a different section.
              relOffset = -4 - immSize;
              relSize = 4;
              {
                s = _S.EmitRel;
                continue loop;
              }
            }
          } else {
            // [RIP->ABS].
            re = code.newRelocEntry(RelocType.relToAbs);

            re.sourceSectionId = section.id;
            re.targetSectionId = section.id;
            re.format
              ..resetToSimpleValue(OffsetType.kUnsignedOffset, 4)
              ..setLeadingAndTrailingSize(_w.cursor - instStart, immSize);
            re.sourceOffset = instStart;
            re.payload = re.sourceOffset + re.format.regionSize() + relOffset;

            _w.emit32uLe(0);
          }
          _w.emitImmediate(immValue, immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }
        case _S.EmitModVSib:
          rxReg &= 0x7;

          // ==========|> [BASE + INDEX + DISP8|DISP32].
          if ((rmInfo & _kMemInfoBaseGp) != 0) {
            rbReg &= 0x7;
            relOffset = rmRel!.offsetLo32;

            var mod = encodeMod(0, opReg, 4);
            var sib = encodeSib(rmRel!.shift, rxReg, rbReg);

            if (relOffset == 0 && rbReg != _kIdBp) {
              // [BASE + INDEX << SHIFT].
              _w.emit8(mod);
              _w.emit8(sib);
            } else {
              var cd_shift =
                  (opcode & X86Opcode.kCDSHL_Mask) >> X86Opcode.kCDSHL_Shift;
              var cd_offset = relOffset >> cd_shift;

              if (_isIntN(8, cd_offset) &&
                  relOffset == _i32(_u32(cd_offset) << cd_shift)) {
                // [BASE + INDEX << SHIFT + DISP8].
                _w.emit8(mod + 0x40); // <- MOD(1, opReg, 4).
                _w.emit8(sib);
                _w.emit8(_u32(cd_offset));
              } else {
                // [BASE + INDEX << SHIFT + DISP32].
                _w.emit8(mod + 0x80); // <- MOD(2, opReg, 4).
                _w.emit8(sib);
                _w.emit32uLe(_u32(relOffset));
              }
            }
          }
          // ==========|> [INDEX + DISP32].
          else if ((rmInfo & (_kMemInfoBaseLabel | _kMemInfoBaseRip)) == 0) {
            // [INDEX << SHIFT + DISP32].
            _w.emit8(encodeMod(0, opReg, 4));
            _w.emit8(encodeSib(rmRel!.shift, rxReg, 5));

            relOffset = rmRel!.offsetLo32;
            _w.emit32uLe(_u32(relOffset));
          }
          // ==========|> [LABEL|RIP + INDEX + DISP32].
          else {
            if (_is32Bit) {
              _w.emit8(encodeMod(0, opReg, 4));
              _w.emit8(encodeSib(rmRel!.shift, rxReg, 5));
              {
                s = _S.EmitModSib_LabelRip_X86;
                continue loop;
              }
            } else {
              // NOTE: This also handles VSIB+RIP, which is not allowed in 64-bit mode.
              {
                s = _S.InvalidAddress;
                continue loop;
              }
            }
          }
          _w.emitImmediate((immValue), immSize);
          {
            s = _S.EmitDone;
            continue loop;
          }
        case _S.EmitJmpCallRel:
          if (_isIntN(8, _i32(rel32 + inst32_size - inst8_size)) &&
              opcode8 != 0 &&
              !_test(options, _IO.kLongForm)) {
            options |= _IO.kShortForm;
            _w.emit8(opcode8); // Emit opcode
            _w.emit8(rel32 + inst32_size - inst8_size); // Emit DISP8.
            {
              s = _S.EmitDone;
              continue loop;
            }
          } else {
            if (opcode == 0 || _test(options, _IO.kShortForm)) {
              s = _S.InvalidDisplacement;
              continue loop;
            }

            options &= ~_IO.kShortForm;
            _w.emit8If(
                0x0F, (opcode & X86Opcode.kMM_Mask) != 0); // Emit 0x0F prefix.
            _w.emit8(opcode); // Emit Opcode.
            _w.emit8If(encodeMod(3, opReg, 0), opReg != 0); // Emit MOD.
            _w.emit32uLe(rel32); // Emit DISP32.
            {
              s = _S.EmitDone;
              continue loop;
            }
          }
          {
            s = _S.InvalidInstruction;
            continue loop;
          }
        case _S.EmitDone:
          return;

        case _S.InvalidInstruction:
          _fail('InvalidInstruction', instId, opArray);
        case _S.AmbiguousOperandSize:
          _fail('AmbiguousOperandSize', instId, opArray);
        case _S.InvalidAddress:
          _fail('InvalidAddress', instId, opArray);
        case _S.OperandSizeMismatch:
          _fail('OperandSizeMismatch', instId, opArray);
        case _S.Failed:
          _fail('Failed', instId, opArray);
        case _S.InvalidRexPrefix:
          _fail('InvalidRexPrefix', instId, opArray);
        case _S.InvalidEROrSAE:
          _fail('InvalidEROrSAE', instId, opArray);
        case _S.InvalidDisplacement:
          _fail('InvalidDisplacement', instId, opArray);
        case _S.OutOfMemory:
          _fail('OutOfMemory', instId, opArray);
        case _S.InvalidSegment:
          _fail('InvalidSegment', instId, opArray);
        case _S.InvalidRepPrefix:
          _fail('InvalidRepPrefix', instId, opArray);
        case _S.InvalidLabel:
          _fail('InvalidLabel', instId, opArray);
        case _S.InvalidImmediate:
          _fail('InvalidImmediate', instId, opArray);
        case _S.InvalidBroadcast:
          _fail('InvalidBroadcast', instId, opArray);
        case _S.InvalidXReleasePrefix:
          _fail('InvalidXReleasePrefix', instId, opArray);
        case _S.InvalidXAcquirePrefix:
          _fail('InvalidXAcquirePrefix', instId, opArray);
        case _S.InvalidPhysId:
          _fail('InvalidPhysId', instId, opArray);
        case _S.InvalidLockPrefix:
          _fail('InvalidLockPrefix', instId, opArray);
        case _S.InvalidAddressIndex:
          _fail('InvalidAddressIndex', instId, opArray);
        case _S.InvalidAddress64Bit:
          _fail('InvalidAddress64Bit', instId, opArray);
      }
    }
  }

  Never _fail(String error, int instId, List<_Op> ops) {
    final name = instId > 0 && instId < kX86InstDb.length
        ? kX86InstDb[instId].name
        : '#$instId';
    throw X86EmitError(error, name);
  }
}

/// An instruction the encoder cannot encode (upstream error name).
class X86EmitError extends ArgumentError {
  final String error;
  final String instruction;
  X86EmitError(this.error, this.instruction)
      : super('x86 $instruction: $error');
}

/// States of [X86Emitter._emit]: the cases and labels of upstream `_emit()`.
enum _S {
  encNone,
  encX86Op,
  encX86Op_Mod11RM,
  encX86Op_Mod11RM_I8,
  encX86Op_xAddr,
  encX86Op_xAX,
  encX86Op_xDX_xAX,
  encX86Op_MemZAX,
  encX86I_xAX,
  encX86M_NoMemSize,
  encX86M,
  encX86M_NoSize,
  CaseX86M_NoSize,
  encX86M_GPB_MulDiv,
  CaseX86M_GPB_MulDiv,
  encX86M_GPB,
  encX86M_Only_EDX_EAX,
  encX86M_Only,
  encX86M_Nop,
  encX86R_FromM,
  encX86R32_EDX_EAX,
  encX86R_Native,
  encX86Rm,
  encX86Rm_NoSize,
  encX86Rm_Raw66H,
  encX86Mr,
  encX86Mr_NoSize,
  encX86Arith,
  encX86Bswap,
  encX86Bt,
  encX86Call,
  encX86Cmpxchg,
  encX86Cmpxchg8b_16b,
  encX86Crc,
  encX86Enter,
  encX86Imul,
  encX86In,
  encX86Ins,
  encX86IncDec,
  encX86Int,
  encX86Jcc,
  encX86JecxzLoop,
  encX86Jmp,
  encX86JmpRel,
  encX86LcallLjmp,
  encX86Lea,
  encX86Mov,
  encX86Movabs,
  encX86MovsxMovzx,
  encX86MovntiMovdiri,
  encX86EnqcmdMovdir64b,
  encX86Out,
  encX86Outs,
  encX86Pushw,
  encX86Push,
  encX86Pop,
  encX86Ret,
  encX86Rot,
  encX86Set,
  encX86ShldShrd,
  encX86StrRm,
  encX86StrMr,
  encX86StrMm,
  encX86Test,
  encX86Xchg,
  encX86Xadd,
  encX86Fence,
  encX86Bndmov,
  encFpuOp,
  encFpuArith,
  encFpuCom,
  encFpuFldFst,
  encFpuM,
  encFpuRDef,
  encFpuR,
  encFpuStsw,
  encExtPextrw,
  encExtExtract,
  encExtMov,
  encExtMovbe,
  encExtMovd,
  CaseExtMovd,
  encExtMovq,
  encExtRm_XMM0,
  encExtRm_ZDI,
  encExtRm_Wx,
  encExtRm_Wx_GpqOnly,
  encExtRm,
  CaseExtRm,
  encExtRm_P,
  encExtRmRi,
  encExtRmRi_P,
  encExtRmi,
  encExtRmi_P,
  encExtExtrq,
  encExtInsertq,
  encExt3dNow,
  encVexOp,
  encVexOpMod,
  encVexKmov,
  encVexR_Wx,
  encVexM,
  encVexMr_Lx,
  encVexMr_VM,
  encVexMri_Vpextrw,
  encVexMvr_Wx,
  encVexMri_Lx,
  encVexMri,
  CaseVexMri,
  encVexRm_ZDI,
  encVexRm_Wx,
  encVexRm_Lx_Narrow,
  encVexRm_Lx_Bcst,
  encVexRm_Lx,
  encVexRm,
  CaseVexRm,
  encVexRm_VM,
  encVexRmi_Wx,
  encVexRmi_Lx,
  encVexRmi,
  CaseVexRmi,
  encVexRvm,
  CaseVexRvm,
  encVexRvm_ZDX_Wx,
  encVexRvm_Wx,
  encVexRvm_Lx_KEvex,
  encVexRvm_Lx,
  encVexRvm_Lx_2xK,
  encVexRvmr_Lx,
  encVexRvmr,
  encVexRvmi_KEvex,
  encVexRvmi_Lx_KEvex,
  encVexRvmi_Lx,
  encVexRvmi,
  VexRvmi,
  encVexRmv_Wx,
  encVexRmv,
  encVexRmvRm_VM,
  encVexRmv_VM,
  encVexRmvi,
  encVexMovdMovq,
  encVexRmMr_Lx,
  encVexRmMr,
  encVexRvmRmv,
  encVexRvmRmi_Lx,
  encVexRvmRmi,
  encVexRvmRmvRmi,
  encVexRvmMr,
  encVexRvmMvr_Lx,
  encVexRvmMvr,
  encVexRvmVmi_Lx_MEvex,
  encVexRvmVmi_Lx,
  encVexRvmVmi,
  encVexVm_Wx,
  encVexVm,
  encVexVmi_Lx_MEvex,
  encVexVmi_Lx,
  encVexVmi,
  CaseVexVmi_AfterImm,
  encVexVmi4_Wx,
  encVexRvrmRvmr_Lx,
  encVexRvrmRvmr,
  encVexRvrmiRvmri_Lx,
  encVexMovssMovsd,
  encFma4_Lx,
  encFma4,
  encAmxCfg,
  encAmxR,
  encAmxRm,
  encAmxMr,
  encAmxRmv,
  EmitX86OpMovAbs,
  EmitX86Op,
  EmitX86OpReg,
  EmitX86OpImplicitMem,
  EmitX86R,
  EmitX86RFromM,
  EmitX86M,
  EmitModSib,
  EmitFpuOp,
  EmitVexOp,
  EmitVexEvexR,
  EmitVexEvexM,
  EmitJmpCall,
  EmitRel,
  CaseX86PushPop_Gp,
  CaseFpuArith_Reg,
  CaseFpuArith_Mem,
  CaseVexRvm_R,
  EmitModSib_LabelRip_X86,
  EmitModVSib,
  EmitJmpCallRel,
  EmitDone,
  InvalidInstruction,
  AmbiguousOperandSize,
  InvalidAddress,
  OperandSizeMismatch,
  Failed,
  InvalidRexPrefix,
  InvalidEROrSAE,
  InvalidDisplacement,
  OutOfMemory,
  InvalidSegment,
  InvalidRepPrefix,
  InvalidLabel,
  InvalidImmediate,
  InvalidBroadcast,
  InvalidXReleasePrefix,
  InvalidXAcquirePrefix,
  InvalidPhysId,
  InvalidLockPrefix,
  InvalidAddressIndex,
  InvalidAddress64Bit,
}

/// Entry state of each [X86Encoding].
const _encodingStates = [
  _S.encNone,
  _S.encX86Op,
  _S.encX86Op_Mod11RM,
  _S.encX86Op_Mod11RM_I8,
  _S.encX86Op_xAddr,
  _S.encX86Op_xAX,
  _S.encX86Op_xDX_xAX,
  _S.encX86Op_MemZAX,
  _S.encX86I_xAX,
  _S.encX86M,
  _S.encX86M_NoMemSize,
  _S.encX86M_NoSize,
  _S.encX86M_GPB,
  _S.encX86M_GPB_MulDiv,
  _S.encX86M_Only,
  _S.encX86M_Only_EDX_EAX,
  _S.encX86M_Nop,
  _S.encX86R_Native,
  _S.encX86R_FromM,
  _S.encX86R32_EDX_EAX,
  _S.encX86Rm,
  _S.encX86Rm_Raw66H,
  _S.encX86Rm_NoSize,
  _S.encX86Mr,
  _S.encX86Mr_NoSize,
  _S.encX86Arith,
  _S.encX86Bswap,
  _S.encX86Bt,
  _S.encX86Call,
  _S.encX86Cmpxchg,
  _S.encX86Cmpxchg8b_16b,
  _S.encX86Crc,
  _S.encX86Enter,
  _S.encX86Imul,
  _S.encX86In,
  _S.encX86Ins,
  _S.encX86IncDec,
  _S.encX86Int,
  _S.encX86Jcc,
  _S.encX86JecxzLoop,
  _S.encX86Jmp,
  _S.encX86JmpRel,
  _S.encX86LcallLjmp,
  _S.encX86Lea,
  _S.encX86Mov,
  _S.encX86Movabs,
  _S.encX86MovsxMovzx,
  _S.encX86MovntiMovdiri,
  _S.encX86EnqcmdMovdir64b,
  _S.encX86Out,
  _S.encX86Outs,
  _S.encX86Push,
  _S.encX86Pushw,
  _S.encX86Pop,
  _S.encX86Ret,
  _S.encX86Rot,
  _S.encX86Set,
  _S.encX86ShldShrd,
  _S.encX86StrRm,
  _S.encX86StrMr,
  _S.encX86StrMm,
  _S.encX86Test,
  _S.encX86Xadd,
  _S.encX86Xchg,
  _S.encX86Fence,
  _S.encX86Bndmov,
  _S.encFpuOp,
  _S.encFpuArith,
  _S.encFpuCom,
  _S.encFpuFldFst,
  _S.encFpuM,
  _S.encFpuR,
  _S.encFpuRDef,
  _S.encFpuStsw,
  _S.encExtRm,
  _S.encExtRm_XMM0,
  _S.encExtRm_ZDI,
  _S.encExtRm_P,
  _S.encExtRm_Wx,
  _S.encExtRm_Wx_GpqOnly,
  _S.encExtRmRi,
  _S.encExtRmRi_P,
  _S.encExtRmi,
  _S.encExtRmi_P,
  _S.encExtPextrw,
  _S.encExtExtract,
  _S.encExtMov,
  _S.encExtMovbe,
  _S.encExtMovd,
  _S.encExtMovq,
  _S.encExtExtrq,
  _S.encExtInsertq,
  _S.encExt3dNow,
  _S.encVexOp,
  _S.encVexOpMod,
  _S.encVexKmov,
  _S.encVexR_Wx,
  _S.encVexM,
  _S.encVexMr_Lx,
  _S.encVexMr_VM,
  _S.encVexMri,
  _S.encVexMri_Lx,
  _S.encVexMri_Vpextrw,
  _S.encVexMvr_Wx,
  _S.encVexRm,
  _S.encVexRm_ZDI,
  _S.encVexRm_Wx,
  _S.encVexRm_Lx,
  _S.encVexRm_Lx_Narrow,
  _S.encVexRm_Lx_Bcst,
  _S.encVexRm_VM,
  _S.encVexRmi,
  _S.encVexRmi_Wx,
  _S.encVexRmi_Lx,
  _S.encVexRvm,
  _S.encVexRvm_Wx,
  _S.encVexRvm_ZDX_Wx,
  _S.encVexRvm_Lx,
  _S.encVexRvm_Lx_KEvex,
  _S.encVexRvm_Lx_2xK,
  _S.encVexRvmr,
  _S.encVexRvmr_Lx,
  _S.encVexRvmi,
  _S.encVexRvmi_KEvex,
  _S.encVexRvmi_Lx,
  _S.encVexRvmi_Lx_KEvex,
  _S.encVexRmv,
  _S.encVexRmv_Wx,
  _S.encVexRmv_VM,
  _S.encVexRmvRm_VM,
  _S.encVexRmvi,
  _S.encVexRmMr,
  _S.encVexRmMr_Lx,
  _S.encVexRvmRmv,
  _S.encVexRvmRmi,
  _S.encVexRvmRmi_Lx,
  _S.encVexRvmRmvRmi,
  _S.encVexRvmMr,
  _S.encVexRvmMvr,
  _S.encVexRvmMvr_Lx,
  _S.encVexRvmVmi,
  _S.encVexRvmVmi_Lx,
  _S.encVexRvmVmi_Lx_MEvex,
  _S.encVexVm,
  _S.encVexVm_Wx,
  _S.encVexVmi,
  _S.encVexVmi_Lx,
  _S.encVexVmi4_Wx,
  _S.encVexVmi_Lx_MEvex,
  _S.encVexRvrmRvmr,
  _S.encVexRvrmRvmr_Lx,
  _S.encVexRvrmiRvmri_Lx,
  _S.encVexMovdMovq,
  _S.encVexMovssMovsd,
  _S.encFma4,
  _S.encFma4_Lx,
  _S.encAmxCfg,
  _S.encAmxR,
  _S.encAmxRm,
  _S.encAmxMr,
  _S.encAmxRmv,
];
