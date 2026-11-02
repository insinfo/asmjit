// Port of `a64::Assembler::_emit()` (asmjit/arm/a64assembler.cpp).
//
// As in x86_emit.dart, the `goto`-based switch of upstream is a state
// machine: every case and label is a state of [_S] and `goto X` is
// `s = _S.X; continue loop;`. The body was translated mechanically from
// upstream and then fixed by hand; keep it close to upstream so it can be
// diffed against it.
//
// The encoder works with upstream instruction ids (a64_encoding_data.g.dart);
// [A64Emitter.emit] maps the port's ids (and the vector `_v` variants that
// upstream selects by overloads) and adapts the operands with [_Op].

// ignore_for_file: dead_code, non_constant_identifier_names, constant_identifier_names, unused_local_variable, unnecessary_parenthesis, curly_braces_in_flow_control_structures, unused_element, prefer_final_locals, no_leading_underscores_for_local_identifiers, unnecessary_null_comparison, unnecessary_non_null_assertion, unused_field, dead_code_on_catch_subtype
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/code_buffer.dart';
import '../core/code_holder.dart';
import '../core/labels.dart';
import '../core/operand.dart' show Imm, LabelOp;
import 'a64.dart';
import 'a64_encoder.dart' show A64Encoder;
import 'a64_encoding_data.g.dart';
import 'a64_inst_db.g.dart';
import 'a64_instdb.dart';

/// Upstream `RegType` values used by the AArch64 encoder.
abstract final class _RT {
  static const int kNone = 0;
  static const int kLabelTag = 1;
  static const int kGp32 = 5;
  static const int kGp64 = 6;
  static const int kVec8 = 7;
  static const int kVec16 = 8;
  static const int kVec32 = 9;
  static const int kVec64 = 10;
  static const int kVec128 = 11;
}

/// `VecElementType`.
abstract final class _ET {
  static const int kNone = 0;
  static const int kB = 1;
  static const int kH = 2;
  static const int kS = 3;
  static const int kD = 4;
  static const int kB4 = 5;
  static const int kH2 = 6;
}

/// `ShiftOp` (asmjit/core/archcommons.h).
abstract final class _ShiftOp {
  static const int kLSL = 0x00;
  static const int kLSR = 0x01;
  static const int kASR = 0x02;
  static const int kROR = 0x03;
  static const int kRRX = 0x04;
  static const int kMSL = 0x05;
  static const int kUXTB = 0x06;
  static const int kUXTH = 0x07;
  static const int kUXTW = 0x08;
  static const int kUXTX = 0x09;
  static const int kSXTB = 0x0A;
  static const int kSXTH = 0x0B;
  static const int kSXTW = 0x0C;
  static const int kSXTX = 0x0D;
}

/// Upstream `CondCode` values (archcommons.h): `kAL` = 0, `kEQ` = 2...
abstract final class _CC {
  static const int kAL = 0x00;
  static const int kEQ = 0x02;
  static const int kNE = 0x03;
  static const int kCS = 0x04;
  static const int kLO = 0x05;
  static const int kMI = 0x06;
  static const int kPL = 0x07;
  static const int kVS = 0x08;
  static const int kVC = 0x09;
  static const int kHI = 0x0A;
  static const int kLS = 0x0B;
  static const int kGE = 0x0C;
  static const int kLT = 0x0D;
  static const int kGT = 0x0E;
  static const int kLE = 0x0F;
}

/// Upstream `CondCode` of an [A64Cond] (`kAL` = 0, `kNA` = 1, `kEQ` = 2...).
int _condCode(A64Cond c) => c == A64Cond.al
    ? _CC.kAL
    : c == A64Cond.nv
        ? 1
        : c.encoding + 2;

/// `arm::OffsetMode`.
const int _kOffsetFixed = 0, _kOffsetPreIndex = 1, _kOffsetPostIndex = 2;

/// Upstream operand types.
const int _kOpNone = 0, _kOpReg = 1, _kOpMem = 2, _kOpImm = 4, _kOpLabel = 5;

const int _kIdSp = 31;
const int _kIdZr = 63;

/// Operand in upstream's terms.
final class _Op {
  final int opType;

  // Register.
  final int regType;
  final int _id;
  final int elementType;
  final int elementIndex; // -1 = none

  // Immediate (`Imm`, shifts and conditions are immediates with a predicate).
  final int imm;
  final double? immDouble;
  final int predicate;

  // Memory.
  final int baseType;
  final int baseId;
  final int indexType;
  final int indexId;
  final int offset;
  final int offsetMode;
  final int shiftOp;
  final int shift;

  final Label? label;

  const _Op._({
    this.opType = _kOpNone,
    this.regType = _RT.kNone,
    int id = 0,
    this.elementType = _ET.kNone,
    this.elementIndex = -1,
    this.imm = 0,
    this.immDouble,
    this.predicate = 0,
    this.baseType = _RT.kNone,
    this.baseId = 0,
    this.indexType = _RT.kNone,
    this.indexId = 0,
    this.offset = 0,
    this.offsetMode = _kOffsetFixed,
    this.shiftOp = 0,
    this.shift = 0,
    this.label,
  }) : _id = id;

  static const none = _Op._();

  static int _vecType(int bits) => switch (bits) {
        8 => _RT.kVec8,
        16 => _RT.kVec16,
        32 => _RT.kVec32,
        64 => _RT.kVec64,
        _ => _RT.kVec128,
      };

  static int _layoutElement(A64Layout l) => switch (l) {
        A64Layout.b8 || A64Layout.b16 => _ET.kB,
        A64Layout.h4 || A64Layout.h8 => _ET.kH,
        A64Layout.s2 || A64Layout.s4 => _ET.kS,
        A64Layout.d1 || A64Layout.d2 => _ET.kD,
        _ => _ET.kNone,
      };

  static int _shiftOpOf(A64Shift s) => s.encoding;

  factory _Op.of(Object? o) {
    switch (o) {
      case null:
        return none;
      case int():
        return _Op._(opType: _kOpImm, imm: o);
      case double():
        return _Op._(opType: _kOpImm, imm: 0, immDouble: o);
      case Imm():
        return _Op._(opType: _kOpImm, imm: o.value);
      case A64ShiftOp():
        return _Op._(
            opType: _kOpImm, imm: o.amount, predicate: _shiftOpOf(o.shift));
      case A64Cond():
        return _Op._(opType: _kOpImm, imm: _condCode(o));
      case A64CondOp():
        return _Op._(opType: _kOpImm, imm: _condCode(o.cond));
      case Label():
        return _Op._(opType: _kOpLabel, label: o, id: o.id);
      case LabelOp():
        return _Op._(opType: _kOpLabel, label: o.label, id: o.label.id);
      case A64Gp():
        return _Op._(
            opType: _kOpReg,
            regType: o.is64Bit ? _RT.kGp64 : _RT.kGp32,
            id: o.id);
      case A64Vec():
        return _Op._(
            opType: _kOpReg,
            regType: _vecType(o.sizeBits),
            id: o.id,
            elementType: o.elementType ?? _layoutElement(o.layout),
            elementIndex: o.elementIndex);
      case A64Mem():
        final base = o.base, index = o.index;
        return _Op._(
          opType: _kOpMem,
          baseType: o.label != null
              ? _RT.kLabelTag
              : base == null
                  ? _RT.kNone
                  : (base.is64Bit ? _RT.kGp64 : _RT.kGp32),
          baseId: o.label?.id ?? base?.id ?? 0,
          indexType: index == null
              ? _RT.kNone
              : (index.is64Bit ? _RT.kGp64 : _RT.kGp32),
          indexId: index?.id ?? 0,
          offset: o.displacement,
          offsetMode: switch (o.addrMode) {
            A64AddrMode.preIndex => _kOffsetPreIndex,
            A64AddrMode.postIndex => _kOffsetPostIndex,
            _ => _kOffsetFixed,
          },
          shiftOp: o.extend ?? _ShiftOp.kLSL,
          shift: o.shift,
          label: o.label,
        );
      default:
        throw ArgumentError('a64: unsupported operand $o');
    }
  }

  int get id => opType == _kOpMem ? baseId : _id;

  bool isNone() => opType == _kOpNone;
  bool isReg() => opType == _kOpReg;
  bool isMem() => opType == _kOpMem;
  bool isImm() => opType == _kOpImm;
  bool isLabel() => opType == _kOpLabel;

  // Register.
  bool isGp() => isReg() && (regType == _RT.kGp32 || regType == _RT.kGp64);
  bool isGp32([int? id]) =>
      isReg() && regType == _RT.kGp32 && (id == null || _id == id);
  bool isGp64([int? id]) =>
      isReg() && regType == _RT.kGp64 && (id == null || _id == id);
  bool isSp() => isGp() && _id == _kIdSp;
  bool isZr() => isGp() && _id == _kIdZr;
  bool isVec() => isReg() && regType >= _RT.kVec8 && regType <= _RT.kVec128;
  bool isVec32() => isReg() && regType == _RT.kVec32;
  bool isVec64() => isReg() && regType == _RT.kVec64;
  bool isVec128() => isReg() && regType == _RT.kVec128;
  bool isVecS4() => isVec128() && elementType == _ET.kS;

  /// Upstream `is_vec_d1()`: a 64-bit vector without element type.
  bool isVecD1() => isVec64() && elementType == _ET.kNone;
  bool isVecD2() => isVec128() && elementType == _ET.kD;
  bool isVecB16() => isVec128() && elementType == _ET.kB;
  bool hasElementType() => elementType != _ET.kNone;
  bool hasElementIndex() => elementIndex >= 0;
  bool hasElementTypeOrIndex() => hasElementType() || hasElementIndex();

  /// Upstream `OperandSignature` bits of a register (op type, register type,
  /// group, size, element type, element index).
  int get signature {
    if (!isReg()) return opType;
    final group = isGp() ? 0 : 1;
    final size = switch (regType) {
      _RT.kGp32 => 4,
      _RT.kGp64 => 8,
      _RT.kVec8 => 1,
      _RT.kVec16 => 2,
      _RT.kVec32 => 4,
      _RT.kVec64 => 8,
      _RT.kVec128 => 16,
      _ => 0,
    };
    var sig = _kOpReg | (regType << 3) | (group << 8) | (size << 24);
    sig |= elementType << 12;
    if (hasElementIndex()) sig |= (1 << 15) | (elementIndex << 16);
    return sig;
  }

  // Immediate.
  int get immU32 => imm & 0xFFFFFFFF;
  int get immI32 => (imm & 0xFFFFFFFF).toSigned(32);
  bool isInt32() =>
      immDouble == null && imm >= -0x80000000 && imm <= 0x7FFFFFFF;
  bool isDouble() => immDouble != null;
  double get immAsDouble => immDouble ?? imm.toDouble();

  // Memory.
  bool hasBaseReg() => baseType != _RT.kNone && baseType != _RT.kLabelTag;
  bool hasIndex() => indexType != _RT.kNone;
  bool hasOffset() => offset != 0;
  bool isPreIndex() => offsetMode == _kOffsetPreIndex;
  bool isPostIndex() => offsetMode == _kOffsetPostIndex;
  bool isPreOrPost() => offsetMode != _kOffsetFixed;
  bool isFixedOffset() => offsetMode == _kOffsetFixed;

  /// `BaseMem::is_offset_64bit()`: no base register, the offset uses the
  /// base field too (absolute address).
  bool isOffset64bit() => baseType == _RT.kNone;
  int get offsetLo32 => (offset & 0xFFFFFFFF).toSigned(32);
}

/// `RegTraits<T>::kSignature`.
int _sigOf(int regType) => _Op._(opType: _kOpReg, regType: regType).signature;

int _u32(Object v) => (v is bool ? (v ? 1 : 0) : v as int) & 0xFFFFFFFF;
int _i32(int v) => (v & 0xFFFFFFFF).toSigned(32);
bool _isIntN(int n, int v) => v >= -(1 << (n - 1)) && v < (1 << (n - 1));
bool _isUintN(int n, int v) => v >= 0 && (n >= 64 || v < (1 << n));
bool _bitTest(int x, int n) => n >= 0 && n < 64 && ((x >> n) & 1) != 0;
int _lsbMask(int n) => n >= 64 ? -1 : (1 << n) - 1;
int _bitMask(int n) => 1 << n;
int _B(int index) => 1 << index;
int _diff(int a, int b) => (a - b) & 0xFFFFFFFF;
int _neg(int v) => (-v) & 0xFFFFFFFF;

/// `Support::shl()` on the 32-bit signed values the encoder uses.
int _shl(int v, int n) => _i32(v << n);
int _ctz(int v) {
  var n = 0;
  while (v & 1 == 0 && n < 64) {
    v >>>= 1;
    n++;
  }
  return n;
}

bool _isPowerOf2(int v) => v > 0 && (v & (v - 1)) == 0;

int condCodeToOpcodeField(int cond) => (cond - 2) & 0xF;

/// `shift_op_to_ld_st_opt_map`.
int shiftOpToLdStOptMap(int index) => switch (index) {
      _ShiftOp.kUXTW => 2,
      _ShiftOp.kLSL => 3,
      _ShiftOp.kSXTW => 6,
      _ShiftOp.kSXTX => 7,
      _ => 0xFF,
    };

/// `extend_option_to_reg_type()`.
int extendOptionToRegType(int option) =>
    (option & 0x3) == 0x3 ? _RT.kGp64 : _RT.kGp32;

/// `SizeOp`.
final class SizeOp {
  static const int k128BitShift = 0;
  static const int kScalarShift = 1;
  static const int kSizeShift = 2;
  static const int kQ = 1 << k128BitShift;
  static const int kS = 1 << kScalarShift;
  static const int k00 = 0 << kSizeShift;
  static const int k01 = 1 << kSizeShift;
  static const int k10 = 2 << kSizeShift;
  static const int k11 = 3 << kSizeShift;
  static const int k00Q = k00 | kQ;
  static const int k01Q = k01 | kQ;
  static const int k10Q = k10 | kQ;
  static const int k11Q = k11 | kQ;
  static const int k00S = k00 | kS;
  static const int k01S = k01 | kS;
  static const int k10S = k10 | kS;
  static const int k11S = k11 | kS;
  static const int kInvalid = 0xFF;
  static const int kSzQ = (0x3 << kSizeShift) | kQ;
  static const int kSzS = (0x3 << kSizeShift) | kS;
  static const int kSzQS = (0x3 << kSizeShift) | kQ | kS;

  int value;
  SizeOp(this.value);

  bool isValid() => value != kInvalid;
  void makeInvalid() => value = kInvalid;
  int q() => (value >> k128BitShift) & 0x1;
  int qs() => ((value >> k128BitShift) | (value >> kScalarShift)) & 0x1;
  int scalar() => (value >> kScalarShift) & 0x1;
  int size() => (value >> kSizeShift) & 0x3;
  void decrementSize() => value = (value - (1 << kSizeShift)) & 0xFF;
}

int _sizeOpIndex(int regType, int elementType) =>
    ((regType - _RT.kVec8) << 3) | elementType;

/// `size_op_table` (kTableBin, kTableAny): 40 entries each, laid out
/// back to back as in upstream (an index past the first table reads the
/// second one).
final List<int> _sizeOpTables = [
  for (var x = 0; x < 40; x++)
    x == _sizeOpIndex(_RT.kVec64, _ET.kNone)
        ? SizeOp.k00
        : x == _sizeOpIndex(_RT.kVec128, _ET.kNone)
            ? SizeOp.k00Q
            : x == _sizeOpIndex(_RT.kVec64, _ET.kB)
                ? SizeOp.k00
                : x == _sizeOpIndex(_RT.kVec128, _ET.kB)
                    ? SizeOp.k00Q
                    : SizeOp.kInvalid,
  for (var x = 0; x < 40; x++)
    {
          _sizeOpIndex(_RT.kVec8, _ET.kNone): SizeOp.k00S,
          _sizeOpIndex(_RT.kVec16, _ET.kNone): SizeOp.k01S,
          _sizeOpIndex(_RT.kVec32, _ET.kNone): SizeOp.k10S,
          _sizeOpIndex(_RT.kVec64, _ET.kNone): SizeOp.k11S,
          _sizeOpIndex(_RT.kVec64, _ET.kB): SizeOp.k00,
          _sizeOpIndex(_RT.kVec128, _ET.kB): SizeOp.k00Q,
          _sizeOpIndex(_RT.kVec64, _ET.kH): SizeOp.k01,
          _sizeOpIndex(_RT.kVec128, _ET.kH): SizeOp.k01Q,
          _sizeOpIndex(_RT.kVec64, _ET.kS): SizeOp.k10,
          _sizeOpIndex(_RT.kVec128, _ET.kS): SizeOp.k10Q,
          _sizeOpIndex(_RT.kVec64, _ET.kD): SizeOp.k11S,
          _sizeOpIndex(_RT.kVec128, _ET.kD): SizeOp.k11Q,
        }[x] ??
        SizeOp.kInvalid,
];

/// `size_op_map` (table id, size op mask, accept mask), indexed by `kVO_*`.
final List<(int, int, int)> _sizeOpMap = [
  (0, SizeOp.kQ, _B(SizeOp.k00) | _B(SizeOp.k00Q)), // kVO_V_B
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) | _B(SizeOp.k00Q) | _B(SizeOp.k01) | _B(SizeOp.k01Q)
  ), // kVO_V_BH
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) |
        _B(SizeOp.k00Q) |
        _B(SizeOp.k01) |
        _B(SizeOp.k01Q) |
        _B(SizeOp.k10Q)
  ), // kVO_V_BH_4S
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) |
        _B(SizeOp.k00Q) |
        _B(SizeOp.k01) |
        _B(SizeOp.k01Q) |
        _B(SizeOp.k10) |
        _B(SizeOp.k10Q)
  ), // kVO_V_BHS
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) |
        _B(SizeOp.k00Q) |
        _B(SizeOp.k01) |
        _B(SizeOp.k01Q) |
        _B(SizeOp.k10) |
        _B(SizeOp.k10Q) |
        _B(SizeOp.k11Q)
  ), // kVO_V_BHS_D2
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k01) | _B(SizeOp.k01Q) | _B(SizeOp.k10) | _B(SizeOp.k10Q)
  ), // kVO_V_HS
  (1, SizeOp.kQ, _B(SizeOp.k10) | _B(SizeOp.k10Q)), // kVO_V_S
  (1, SizeOp.kSzQS, _B(SizeOp.k00) | _B(SizeOp.k01)), // kVO_V_B8H4
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) | _B(SizeOp.k01) | _B(SizeOp.k10)
  ), // kVO_V_B8H4S2
  (1, SizeOp.kSzQ, _B(SizeOp.k00) | _B(SizeOp.k11S)), // kVO_V_B8D1
  (1, SizeOp.kSzQS, _B(SizeOp.k01) | _B(SizeOp.k10)), // kVO_V_H4S2
  (0, SizeOp.kQ, _B(SizeOp.k00Q)), // kVO_V_B16
  (1, SizeOp.kSzQS, _B(SizeOp.k00Q) | _B(SizeOp.k01Q)), // kVO_V_B16H8
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00Q) | _B(SizeOp.k01Q) | _B(SizeOp.k10Q)
  ), // kVO_V_B16H8S4
  (1, SizeOp.kSzQS, _B(SizeOp.k00Q) | _B(SizeOp.k11Q)), // kVO_V_B16D2
  (1, SizeOp.kSzQS, _B(SizeOp.k01Q) | _B(SizeOp.k10Q)), // kVO_V_H8S4
  (1, 0, _B(SizeOp.k10Q)), // kVO_V_S4
  (1, 0, _B(SizeOp.k11Q)), // kVO_V_D2
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) |
        _B(SizeOp.k00Q) |
        _B(SizeOp.k00S) |
        _B(SizeOp.k01) |
        _B(SizeOp.k01Q) |
        _B(SizeOp.k01S) |
        _B(SizeOp.k10) |
        _B(SizeOp.k10Q) |
        _B(SizeOp.k10S)
  ), // kVO_SV_BHS
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) |
        _B(SizeOp.k00S) |
        _B(SizeOp.k01) |
        _B(SizeOp.k01S) |
        _B(SizeOp.k10) |
        _B(SizeOp.k10S)
  ), // kVO_SV_B8H4S2
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k01) |
        _B(SizeOp.k01Q) |
        _B(SizeOp.k01S) |
        _B(SizeOp.k10) |
        _B(SizeOp.k10Q) |
        _B(SizeOp.k10S)
  ), // kVO_SV_HS
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) |
        _B(SizeOp.k00Q) |
        _B(SizeOp.k01) |
        _B(SizeOp.k01Q) |
        _B(SizeOp.k10) |
        _B(SizeOp.k10Q) |
        _B(SizeOp.k11S) |
        _B(SizeOp.k11Q)
  ), // kVO_V_Any
  (
    1,
    SizeOp.kSzQS,
    _B(SizeOp.k00) |
        _B(SizeOp.k00Q) |
        _B(SizeOp.k00S) |
        _B(SizeOp.k01) |
        _B(SizeOp.k01Q) |
        _B(SizeOp.k01S) |
        _B(SizeOp.k10) |
        _B(SizeOp.k10Q) |
        _B(SizeOp.k10S) |
        _B(SizeOp.k11) |
        _B(SizeOp.k11Q) |
        _B(SizeOp.k11S)
  ), // kVO_SV_Any
];

_Op significantSimdOp(_Op o0, _Op o1, int instFlags) =>
    (instFlags & kInstFlagLong) == 0 ? o0 : o1;

/// `element_type_to_size_op()`.
SizeOp elementTypeToSizeOp(int vecOpType, int regType, int elementType) {
  final (tableId, sizeOpMask, acceptMask) = _sizeOpMap[vecOpType];
  final index =
      (math.min(_diff(regType, _RT.kVec8), _diff(_RT.kVec128, _RT.kVec8) + 1) <<
              3) |
          elementType;
  final i = tableId * 40 + index;
  final op = i < _sizeOpTables.length ? _sizeOpTables[i] : SizeOp.kInvalid;
  final modified = SizeOp(op & sizeOpMask);
  if (!_bitTest(acceptMask, op)) modified.makeInvalid();
  return modified;
}

/// `LMHImm` / `encode_lmh()`.
final class LMHImm {
  int lm = 0, h = 0, max_rm_id = 0;
}

bool encodeLmh(int sizeField, int elementIndex, LMHImm out) {
  if (sizeField != 1 && sizeField != 2) return false;
  final hShift = 3 - sizeField;
  final lmShift = sizeField - 1;
  final maxElementIndex = 15 >> sizeField;
  out.h = elementIndex >> hShift;
  out.lm = (elementIndex << lmShift) & 0x3;
  out.max_rm_id = (8 << sizeField) - 1;
  return elementIndex <= maxElementIndex;
}

/// `Opcode` (a64assembler.cpp).
final class Opcode {
  static const int kN = 1 << 22;
  static const int kQ = 1 << 30;
  static const int kX = 1 << 31;

  int v = 0;

  int get() => v;
  void reset(int value) => v = value & 0xFFFFFFFF;
  bool hasQ() => (v & kQ) != 0;
  bool hasX() => (v & kX) != 0;
  void addImm(Object value, int bitIndex) =>
      v = (v | (_u32(value) << bitIndex)) & 0xFFFFFFFF;
  void xorImm(Object value, int bitIndex) =>
      v = (v ^ (_u32(value) << bitIndex)) & 0xFFFFFFFF;
  void addIf(int value, bool condition) => v |= condition ? value : 0;
  void addLogicalImm(LogicalImm l) {
    addImm(l.n, 22);
    addImm(l.r, 16);
    addImm(l.s, 10);
  }

  void addReg(Object op, int bitIndex) {
    final id = op is _Op ? op.id : op as int;
    v = (v | ((id & 31) << bitIndex)) & 0xFFFFFFFF;
  }
}

/// `Utils::LogicalImm` (n:immr:imms).
final class LogicalImm {
  int n = 0, s = 0, r = 0;
}

/// `Utils::encode_logical_imm()`.
bool encodeLogicalImm(int imm, int width, LogicalImm out) {
  final enc = A64Encoder.encodeLogicalImm(imm, width);
  if (enc == null) return false;
  out.n = (enc >> 12) & 1;
  out.r = (enc >> 6) & 0x3F;
  out.s = enc & 0x3F;
  return true;
}

/// `match_signature(o0, o1[, o2[, o3]], inst_flags)`.
bool matchSignature(_Op o0, _Op o1, Object a, [Object? b, Object? c]) {
  final ops = [
    o0,
    o1,
    for (final x in [a, b, c])
      if (x is _Op) x
  ];
  final instFlags = [a, b, c].whereType<int>().first;
  final ok = (instFlags & (kInstFlagLong | kInstFlagNarrow)) == 0
      ? o0.signature == o1.signature
      : true;
  if (!ok) return false;
  for (var i = 2; i < ops.length; i++) {
    if (ops[i - 1].signature != ops[i].signature) return false;
  }
  return true;
}

bool checkMemBaseIndexRel(_Op mem) {
  final kBaseMask = _B(0) | _B(_RT.kLabelTag) | _B(_RT.kGp64);
  final kIndexMask = _B(0) | _B(_RT.kGp32) | _B(_RT.kGp64);
  final baseType = mem.baseType;
  final indexType = mem.indexType;
  if (!_bitTest(kBaseMask, baseType)) return false;
  if (baseType > _RT.kLabelTag) {
    if (!_bitTest(kIndexMask, indexType)) return false;
    if (indexType == _RT.kNone) return true;
    return !mem.hasOffset();
  }
  return indexType == _RT.kNone;
}

/// `pick_fp_opcode()`; [szOut] receives the size field.
bool pickFpOpcode(_Op reg, int sOp, int sHf, int vOp, int vHf, Opcode opcode,
    [List<int>? szOut]) {
  const kQBitIndex = 30;
  const szBitsTable = <(int, List<int>)>[
    ((1 << 2) | (1 << 1), [0, 0, 1 << 22]),
    ((1 << 2) | (1 << 1) | 1, [0, 0, 0]),
    ((1 << 2) | (1 << 1) | 1, [(1 << 23) | (1 << 22), 0, 1 << 22]),
    ((1 << 2) | (1 << 1) | 1, [(1 << 22) | (1 << 20) | (1 << 19), 0, 1 << 22]),
    (
      (1 << 2) | (1 << 1) | 1,
      [(1 << 22) | (1 << 21) | (1 << 15) | (1 << 14), 0, 1 << 22]
    ),
    ((1 << 2) | (1 << 1) | 1, [1 << 23, 0, 1 << 22]),
  ];
  if (!reg.hasElementType()) {
    final sz = _diff(reg.regType, _RT.kVec16);
    if (sz > 2 || !_bitTest(szBitsTable[sHf].$1, sz)) return false;
    opcode.reset(szBitsTable[sHf].$2[sz] ^ sOp);
    szOut?[0] = sz;
    return sOp != 0;
  } else {
    final q = _diff(reg.regType, _RT.kVec64);
    final sz = _diff(reg.elementType, _ET.kH);
    if (q > 1 || sz > 2 || !_bitTest(szBitsTable[vHf].$1, sz)) return false;
    opcode.reset(szBitsTable[vHf].$2[sz] ^ (vOp | (q << kQBitIndex)));
    szOut?[0] = sz;
    return vOp != 0;
  }
}

bool checkSignature(_Op o0, _Op o1, [_Op? o2, _Op? o3]) =>
    o0.signature == o1.signature &&
    (o2 == null || o1.signature == o2.signature) &&
    (o3 == null || o2!.signature == o3.signature);

/// `check_gp_type()`; [x] receives `reg_type - kGp32` masked by [allowed].
bool checkGpType(_Op op, int allowed, [List<int>? x]) {
  final type = op.regType;
  x?[0] = _diff(type, _RT.kGp32) & allowed;
  return _bitTest(allowed << _RT.kGp32, type);
}

bool checkGpType2(_Op o0, _Op o1, int allowed, List<int> x) =>
    checkGpType(o0, allowed, x) && checkSignature(o0, o1);

bool checkGpType3(_Op o0, _Op o1, _Op o2, int allowed, List<int> x) =>
    checkGpType(o0, allowed, x) && checkSignature(o0, o1, o2);

bool _gpIdOk(_Op o, int hiId) => o.id < 31 || o.id == hiId;

bool checkGpId(_Op o0, [Object? o1OrHiId, Object? o2OrHiId, int? hiId3]) {
  // check_gp_id(op, hi_id = kZR), (o0, o1, hi_id = kZR), (o0, o1, o2, hi_id).
  final ops = <_Op>[o0];
  var hiId = _kIdZr;
  for (final a in [o1OrHiId, o2OrHiId]) {
    if (a is _Op) ops.add(a);
    if (a is int) hiId = a;
  }
  if (hiId3 != null) hiId = hiId3;
  return ops.every((o) => _gpIdOk(o, hiId));
}

bool checkVecId(_Op o0, [_Op? o1]) =>
    ((o0.id | (o1?.id ?? 0)) & 0xFFFFFFFF) <= 31;

bool checkMemBase(_Op mem) => mem.baseType == _RT.kGp64 && mem.baseId <= 31;

bool checkEven(_Op o0, _Op o1) => ((o0.id | o1.id) & 1) == 0;

bool checkConsecutive(_Op o0, _Op o1, [_Op? o2, _Op? o3]) =>
    ((o0.id + 1) & 0x1F) == o1.id &&
    (o2 == null || ((o0.id + 2) & 0x1F) == o2.id) &&
    (o3 == null || ((o0.id + 3) & 0x1F) == o3.id);

int _commonHiRegIdOfType(int t) => switch (t) {
      _RT.kGp32 || _RT.kGp64 => _kIdZr,
      _RT.kVec8 || _RT.kVec16 || _RT.kVec32 || _RT.kVec64 || _RT.kVec128 => 31,
      _ => 0,
    };

bool checkValidRegs(_Op o0, [_Op? o1, _Op? o2, _Op? o3]) => [o0, o1, o2, o3]
    .whereType<_Op>()
    .every((o) => o.id < 31 || o.id == _commonHiRegIdOfType(o.regType));

/// `OffsetFormat` (asmjit/core/fixup.h) as used by the AArch64 encoder.
final class OffsetFormat {
  int _type = 0;
  int _valueSize = 0;
  int _immBitShift = 0;
  int _immBitCount = 0;
  int _imm_discard_lsb = 0;

  void resetToImmValue(int type, int valueSize, int immBitShift,
      int immBitCount, int immDiscardLsb) {
    _type = type;
    _valueSize = valueSize;
    _immBitShift = immBitShift;
    _immBitCount = immBitCount;
    _imm_discard_lsb = immDiscardLsb;
  }

  int type() => _type;
  int immBitShift() => _immBitShift;
  int immBitCount() => _immBitCount;
  int immDiscardLsb() => _imm_discard_lsb;
}

/// `EmitterUtils::is_encodable_offset_64()`.
bool isEncodableOffset64(int offset, int nBits) {
  final nRev = 64 - nBits;
  return ((offset << nRev) >> nRev) == offset;
}

/// `Utils::is_byte_mask_imm()`.
bool isByteMaskImm(int imm) {
  for (var i = 0; i < 8; i++) {
    final b = (imm >> (i * 8)) & 0xFF;
    if (b != 0 && b != 0xFF) return false;
  }
  return true;
}

/// `Utils::encode_imm64_byte_mask_to_imm8()`.
int encodeImm64ByteMaskToImm8(int imm) =>
    ((imm >>> 7) & 0x03) |
    ((imm >>> (23 - 2)) & 0x0C) |
    ((imm >>> (39 - 4)) & 0x30) |
    ((imm >>> (55 - 6)) & 0xC0);

/// `Utils::is_fp64_imm8()`: `aBbbbbbb_bbcdefgh_000...` (fmov immediate).
bool isFp64Imm8(int bits) {
  final b = (bits >>> 54) & 0xFF;
  return (bits & 0xFFFFFFFFFFFF) == 0 &&
      (b == 0x00 || b == 0xFF) &&
      false == false &&
      _isFp64Imm8(bits);
}

bool _isFp64Imm8(int bits) {
  // asmjit: is_fp_imm8_generic<uint64_t, 8, 6, 48>: lower 48 bits zero,
  // bits [61:54] all equal to the inverse of bit 62.
  if ((bits & ((1 << 48) - 1)) != 0) return false;
  final b6 = (bits >>> 54) & 0xFF; // bits 54..61
  final b62 = (bits >>> 62) & 1;
  return b6 == (b62 == 1 ? 0x00 : 0xFF);
}

/// `Utils::encode_fp64_to_imm8()`.
int encodeFp64ToImm8(int bits) =>
    (((bits >>> 56) & 0x80) | ((bits >>> 48) & 0x7F)) & 0xFF;

int doubleBits(double v) {
  final b = ByteData(8)..setFloat64(0, v, Endian.little);
  return b.getInt64(0, Endian.little);
}

/// The CodeBuffer writer.
final class _Writer {
  final CodeBuffer buf;
  _Writer(this.buf);
  int get cursor => buf.length;
  int offsetFrom(Object? _) => buf.length;
  void emit32uLe(int v) => buf.emit32(v & 0xFFFFFFFF);
}

/// Encodes AArch64 instructions as upstream `a64::Assembler::_emit()`.
final class A64Emitter {
  final CodeHolder code;
  final CodeBuffer buffer;

  /// `inst_options()` of the next instruction.
  int instOptions = 0;

  A64Emitter(this.code, this.buffer);

  static final Map<String, int> _upIds = {
    for (final (i, n) in kA64UpInstNames.indexed)
      if (n.isNotEmpty) n: i
  };

  /// Upstream id (and its vector `_v` variant, 0 if none) of each of the
  /// port's instruction ids.
  static final List<(int, int)> _toUpIds = [
    for (final info in kA64InstDb) _upIdsOf(info.name),
  ];

  static (int, int) _upIdsOf(String name) {
    for (final n in name.split('|')) {
      final base = _upIds[n] ?? 0;
      final vec = _upIds['${n}_v'] ?? 0;
      if (base != 0 || vec != 0) return (base, vec);
    }
    return (0, 0);
  }

  /// Emits [instId] (the port's id) with [operands]; throws
  /// [A64EmitError] if the instruction cannot be encoded.
  void emit(int instId, List<Object> operands) {
    var ops = operands;
    var instCc = _CC.kAL;
    // `b.cond label` is upstream `B` with an embedded condition code.
    if (instId == A64InstId.kB_cond) {
      final cond = ops.whereType<A64Cond>().firstOrNull ??
          ops.whereType<A64CondOp>().firstOrNull?.cond;
      if (cond == null) throw A64EmitError('InvalidInstruction', 'b.cond');
      instCc = _condCode(cond);
      ops = [
        for (final o in ops)
          if (o is! A64Cond && o is! A64CondOp) o
      ];
      instId = A64InstId.kB;
    }
    final (base, vec) =
        instId >= 0 && instId < _toUpIds.length ? _toUpIds[instId] : (0, 0);
    final useVec = vec != 0 &&
        (base == 0 ||
            ops.any((o) => o is A64Vec) ||
            (ops.isNotEmpty && ops.first is A64Vec));
    final upId = useVec ? vec : base;

    // Upstream `EmitterExplicitT::ret()` is `ret(x30)`.
    if (instId == A64InstId.kRet && ops.isEmpty) ops = const [x30];

    final opArray = [for (final o in ops) _Op.of(o)];
    while (opArray.length < 6) {
      opArray.add(_Op.none);
    }
    final start = buffer.length;
    try {
      _emit(upId, instCc, opArray);
    } catch (_) {
      buffer.truncate(start);
      rethrow;
    } finally {
      instOptions = 0;
    }
  }

  void _emit(int instId, int instCc, List<_Op> opArray) {
    final o0 = opArray[0], o1 = opArray[1], o2 = opArray[2];
    final opExt = opArray;
    final o3 = opArray[3];

    final _w = _Writer(buffer);
    var options = (instId == 0 ? 1 : 0) | instOptions;

    if (instId < 0 || instId >= kA64UpInstInfo.length) instId = 0;
    var instInfo = kA64UpInstInfo[instId];
    var encodingIndex = instInfo.encodingDataIndex;

    final opcode = Opcode();
    int isign4;
    int instFlags;
    _Op? rmRel;

    // `uint32_t x` of the cases that call `check_gp_type(..., &x)`.
    var x = 0;
    bool checkGpTypeX(_Op o0, Object a1, [Object? a2, Object? a3]) {
      final ops = [
        o0,
        for (final a in [a1, a2, a3])
          if (a is _Op) a
      ];
      final allowed = [a1, a2, a3].whereType<int>().first;
      final r = [0];
      final ok = checkGpType(o0, allowed, r);
      x = r[0];
      if (!ok) return false;
      return ops.length == 1 ||
          checkSignature(ops[0], ops[1], ops.length > 2 ? ops[2] : null);
    }

    final multipleOpData = <int>[];
    var multipleOpCount = 0;

    final offsetFormat = OffsetFormat();
    var offsetValue = 0;

    if (instId == 0) _fail('InvalidInstruction', instId);
    if (instCc != _CC.kAL && instId != _upIds['b']) {
      _fail('InvalidInstruction', instId);
    }

    isign4 = o0.opType + (o1.opType << 3) + (o2.opType << 6) + (o3.opType << 9);
    instFlags = instInfo.flags;

    var state = _encodingStates[instInfo.encoding];
    loop:
    while (true) {
      switch (state) {
        // ------------------------------------------------------------------------
        // [Base - Universal]
        // ------------------------------------------------------------------------

        case _S.encBaseOp:
          {
            final op_data = baseOp[encodingIndex];

            if (isign4 == 0) {
              opcode.reset(op_data.opcode);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseOpX16;
          continue loop; // (after block)
        case _S.encBaseOpX16:
          {
            final op_data = baseOpX16[encodingIndex];

            if (isign4 == 1 /* ENC_OPS1(Reg) */ && o0.isGp64(16)) {
              opcode.reset(op_data.opcode);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseOpImm;
          continue loop; // (after block)
        case _S.encBaseOpImm:
          {
            final op_data = baseOpImm[encodingIndex];

            if (isign4 == 4 /* ENC_OPS1(Imm) */) {
              var imm = o0.imm;
              var immMax = _u32(1 << op_data.imm_bits);

              if (imm >= immMax) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(imm, op_data.imm_offset);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseR;
          continue loop; // (after block)
        case _S.encBaseR:
          {
            final op_data = baseR[encodingIndex];

            if (isign4 == 1 /* ENC_OPS1(Reg) */) {
              if (!checkGpType(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.reg_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addReg(o0, op_data.r_shift);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRR;
          continue loop; // (after block)
        case _S.encBaseRR:
          {
            final op_data = baseRR[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.a_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpType(o1, op_data.b_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (op_data.uniform != 0 && !checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.a_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkGpId(o1, op_data.b_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addReg(o1, op_data.b_shift);
              opcode.addReg(o0, op_data.a_shift);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRRR;
          continue loop; // (after block)
        case _S.encBaseRRR:
          {
            final op_data = baseRRR[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.a_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpType(o1, op_data.b_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpType(o2, op_data.c_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (op_data.uniform != 0 && !checkSignature(o0, o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.a_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkGpId(o1, op_data.b_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkGpId(o2, op_data.c_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addReg(o2, 16);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRRRR;
          continue loop; // (after block)
        case _S.encBaseRRRR:
          {
            final op_data = baseRRRR[encodingIndex];

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.a_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpType(o1, op_data.b_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpType(o2, op_data.c_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpType(o3, op_data.d_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (op_data.uniform != 0 && !checkSignature(o0, o1, o2, o3)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.a_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkGpId(o1, op_data.b_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkGpId(o2, op_data.c_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkGpId(o3, op_data.d_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addReg(o2, 16);
              opcode.addReg(o3, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRRII;
          continue loop; // (after block)
        case _S.encBaseRRII:
          {
            final op_data = baseRRII[encodingIndex];

            if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
              if (!checkGpType(o0, op_data.a_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpType(o1, op_data.b_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.a_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkGpId(o1, op_data.b_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (o2.imm >=
                      _bitMask(
                          op_data.a_imm_size + op_data.a_imm_discard_lsb) ||
                  o3.imm >=
                      _bitMask(
                          op_data.b_imm_size + op_data.b_imm_discard_lsb)) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var a_imm = _u32(o2.immU32 >> op_data.a_imm_discard_lsb);
              var b_imm = _u32(o3.immU32 >> op_data.b_imm_discard_lsb);

              if ((a_imm << op_data.a_imm_discard_lsb) != o2.immU32 ||
                  (b_imm << op_data.b_imm_discard_lsb) != o3.immU32) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(a_imm, op_data.a_imm_offset);
              opcode.addImm(b_imm, op_data.b_imm_offset);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Mov]
          // ------------------------------------------------------------------------

          state = _S.encBaseMov;
          continue loop; // (after block)
        case _S.encBaseMov:
          {
            // MOV is a pseudo instruction that uses various instructions depending on its signature.
            var x = _u32(_diff(o0.regType, _RT.kGp32));
            if (x > 1) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (!o0.isGp()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var has_sp = o0.isSp() || o1.isSp();
              if (has_sp) {
                // Cannot be combined with ZR.
                if (!checkGpId(o0, o1, kSP)) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                // MOV Rd, Rm -> ADD Rd, Rn, #0.
                opcode.reset(0x11000000);
                opcode.addImm(x, 31);
                opcode.addReg(o1, 5);
                opcode.addReg(o0, 0);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              } else {
                if (!checkGpId(o0, o1, kZR)) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                // MOV Rd, Rm -> ORR Rd, <ZR>, Rm.
                opcode.reset(0x2a0003e0);
                opcode.addImm(x, 31);
                opcode.addReg(o1, 16);
                opcode.addReg(o0, 0);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              }
            }

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              if (!o0.isGp()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var imm_value = o1.imm;
              if (x == 0) imm_value &= 0xFFFFFFFF;

              // Prefer a single MOVN/MOVZ instruction over a logical instruction.
              {
                final seq =
                    A64Encoder.encodeMovSequence64(imm_value, o0.id & 31, x);
                multipleOpData
                  ..clear()
                  ..addAll(seq);
                multipleOpCount = seq.length;
              }
              if (multipleOpCount == 1 && !o0.isSp()) {
                opcode.reset(multipleOpData[0]);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              }

              // Logical instructions use 13-bit immediate pattern encoded as N:ImmR:ImmS.
              final logical_imm = LogicalImm();
              if (!o0.isZr()) {
                if (encodeLogicalImm(
                    imm_value, x != 0 ? 64 : 32, logical_imm)) {
                  if (!checkGpId(o0, kSP)) {
                    state = _S.InvalidPhysId;
                    continue loop;
                  }

                  opcode.reset(0x320003e0);
                  opcode.addImm(x, 31);
                  opcode.addLogicalImm(logical_imm);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp;
                    continue loop;
                  }
                }
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              {
                state = _S.EmitOp_Multiple;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseMovKNZ;
          continue loop; // (after block)
        case _S.encBaseMovKNZ:
          {
            final op_data = baseMovKNZ[encodingIndex];

            var x = _u32(_diff(o0.regType, _RT.kGp32));
            if (x > 1) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (!checkGpId(o0, kZR)) {
              state = _S.InvalidPhysId;
              continue loop;
            }

            opcode.reset(op_data.opcode);
            opcode.addImm(x, 31);

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              var imm16 = o1.imm;
              if (imm16 > 0xFFFF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.addImm(imm16, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 289 /* ENC_OPS3(Reg, Imm, Imm) */) {
              var imm16 = o1.imm;
              var shift_type = _u32(o2.predicate);
              var shiftValue = o2.imm;

              if (imm16 > 0xFFFF ||
                  shiftValue > 48 ||
                  shift_type != _u32(_ShiftOp.kLSL)) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              // Convert shift value to 'hw' field.
              var hw = _u32(_u32(shiftValue) >> 4);
              if ((hw << 4) != _u32(shiftValue)) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.addImm(hw, 21);
              opcode.addImm(imm16, 5);
              opcode.addReg(o0, 0);

              if (x == 0 && hw > 1) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Adr]
          // ------------------------------------------------------------------------

          state = _S.encBaseAdr;
          continue loop; // (after block)
        case _S.encBaseAdr:
          {
            final op_data = baseAdr[encodingIndex];

            if (isign4 == 41 /* ENC_OPS2(Reg, Label) */ ||
                isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              if (!o0.isGp64()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addReg(o0, 0);
              offsetFormat.resetToImmValue(op_data.offset_type, 4, 5, 21, 0);

              if (instId == _upIds['adrp']!) offsetFormat._imm_discard_lsb = 12;

              rmRel = o1;
              {
                state = _S.EmitOp_Rel;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Arithmetic and Logical]
          // ------------------------------------------------------------------------

          state = _S.encBaseAddSub;
          continue loop; // (after block)
        case _S.encBaseAddSub:
          {
            final op_data = baseAddSub[encodingIndex];

            // uint32_t x; (function-level)
            if (!checkGpTypeX(o0, o1, kWX)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */ ||
                isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
              opcode.reset(_u32(op_data.immediate_op) << 24);

              // ADD | SUB (immediate) - ZR is not allowed.
              // ADDS|SUBS (immediate) - ZR allowed in Rd, SP allowed in Rn.
              var a_hi_id = (opcode.get() & _B(29)) != 0 ? kZR : kSP;
              var b_hi_id = _u32(kSP);

              if (!checkGpId(o0, a_hi_id) || !checkGpId(o1, b_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              // ADD|SUB (immediate) use 12-bit immediate optionally shifted by 'LSL #12'.
              var imm = o2.imm;
              var shift = _u32(0);

              if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
                if (o3.predicate != _u32(_ShiftOp.kLSL)) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                if (o3.imm != 0 && o3.imm != 12) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                shift = _u32(o3.imm != 0);
              }

              // Accept immediate value of '0x00XXX000' by setting 'shift' to 12.
              if (imm > 0xFFF) {
                if (shift != 0 || (imm & ~(0xFFF << 12)) != 0) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
                shift = 1;
                imm >>= 12;
              }

              opcode.addImm(x, 31);
              opcode.addImm(shift, 22);
              opcode.addImm(imm, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */ ||
                isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              var op_size = _u32(x != 0 ? 64 : 32);
              var shift = 0;
              var shift_type = _u32(_u32(_ShiftOp.kLSL));

              if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
                shift_type = o3.predicate;
                shift = o3.imm;
              }

              if (!checkGpId(o2, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              // Shift operation - LSL, LSR, ASR.
              if (shift_type <= _u32(_ShiftOp.kASR)) {
                var has_sp = o0.isSp() || o1.isSp();
                if (!has_sp) {
                  if (!checkSignature(o1, o2)) {
                    {
                      state = _S.InvalidInstruction;
                      continue loop;
                    }
                  }

                  if (!checkGpId(o0, o1, kZR)) {
                    {
                      state = _S.InvalidPhysId;
                      continue loop;
                    }
                  }

                  if (shift >= op_size) {
                    {
                      state = _S.InvalidImmediate;
                      continue loop;
                    }
                  }

                  opcode.reset(_u32(op_data.shifted_op) << 21);
                  opcode.addImm(x, 31);
                  opcode.addImm(shift_type, 22);
                  opcode.addReg(o2, 16);
                  opcode.addImm(shift, 10);
                  opcode.addReg(o1, 5);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp;
                    continue loop;
                  }
                }

                // SP register can only be used with LSL or Extend.
                if (shift_type != _u32(_ShiftOp.kLSL)) {
                  {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }
                }

                shift_type =
                    x != 0 ? _u32(_ShiftOp.kUXTX) : _u32(_ShiftOp.kUXTW);
              }

              // Extend operation - UXTB, UXTH, UXTW, UXTX, SXTB, SXTH, SXTW, SXTX.
              opcode.reset(_u32(op_data.extended_op) << 21);
              shift_type -= _u32(_ShiftOp.kUXTB);

              if (shift_type > 7 || shift > 4) {
                {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
              }

              if ((opcode.get() & _B(29)) == 0) {
                // ADD|SUB (extend) - ZR is not allowed.
                if (!checkGpId(o0, o1, kSP)) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }
              } else {
                // ADDS|SUBS (extend) - ZR allowed in Rd, SP allowed in Rn.
                if (!checkGpId(o0, kZR) || !checkGpId(o1, kSP)) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }
              }

              // Validate whether the register operands match extend option.
              if (o2.regType != extendOptionToRegType(shift_type) ||
                  o1.regType < o2.regType) {
                {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
              }

              opcode.addImm(x, 31);
              opcode.addReg(o2, 16);
              opcode.addImm(shift_type, 13);
              opcode.addImm(shift, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseLogical;
          continue loop; // (after block)
        case _S.encBaseLogical:
          {
            final op_data = baseLogical[encodingIndex];

            // uint32_t x; (function-level)
            if (!checkGpTypeX(o0, o1, kWX)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (!checkSignature(o0, o1)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            var op_size = _u32(x != 0 ? 64 : 32);

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */ &&
                op_data.immediate_op != 0) {
              opcode.reset(_u32(op_data.immediate_op) << 23);

              // AND|ANDS|BIC|BICS|ORR|EOR (immediate) uses a LogicalImm format described by N:R:S values.
              var imm_mask = _lsbMask(op_size);
              var imm_value = o2.imm;

              if (op_data.negate_imm != 0) imm_value ^= imm_mask;

              // Logical instructions use 13-bit immediate pattern encoded as N:ImmS:ImmR.
              final logical_imm = LogicalImm();
              if (!encodeLogicalImm(
                  imm_value & imm_mask, op_size, logical_imm)) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              // AND|BIC|ORR|EOR (immediate) can have SP on destination, but ANDS|BICS (immediate) cannot.
              var kOpANDS = _u32(0x3 << 29);
              var isANDS = (opcode.get() & kOpANDS) == kOpANDS;

              if (!checkGpId(o0, isANDS ? kZR : kSP) || !checkGpId(o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.addImm(x, 31);
              opcode.addLogicalImm(logical_imm);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (!checkSignature(o1, o2)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (!checkGpId(o0, o1, o2, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(_u32(op_data.shifted_op) << 21);
              opcode.addImm(x, 31);
              opcode.addReg(o2, 16);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              if (!checkGpId(o0, o1, o2, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var shift_type = _u32(o3.predicate);
              var op_shift = o3.imm;

              if (shift_type > 0x3 || op_shift >= op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(_u32(op_data.shifted_op) << 21);
              opcode.addImm(x, 31);
              opcode.addImm(shift_type, 22);
              opcode.addReg(o2, 16);
              opcode.addImm(op_shift, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseCmpCmn;
          continue loop; // (after block)
        case _S.encBaseCmpCmn:
          {
            final op_data = baseCmpCmn[encodingIndex];

            // uint32_t x; (function-level)
            if (!checkGpTypeX(o0, kWX)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              // CMN|CMP (immediate) - ZR is not allowed.
              if (!checkGpId(o0, kSP)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              // CMN|CMP (immediate) use 12-bit immediate optionally shifted by 'LSL #12'.
              final imm12 = o1;
              var imm_shift = _u32(0);
              var imm_value = imm12.imm;

              if (imm_value > 0xFFF) {
                if ((imm_value & ~(0xFFF << 12)) != 0) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
                imm_shift = 1;
                imm_value >>= 12;
              }

              opcode.reset(_u32(op_data.immediate_op) << 24);
              opcode.addImm(x, 31);
              opcode.addImm(imm_shift, 22);
              opcode.addImm(imm_value, 10);
              opcode.addReg(o0, 5);
              opcode.addReg(_kIdZr, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */ ||
                isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
              var op_size = _u32(x != 0 ? 64 : 32);
              var shift_type = _u32(0);
              var shift_value = 0;

              if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
                shift_type = o2.predicate;
                shift_value = o2.imm;
              }

              var has_sp = o0.isSp() || o1.isSp();

              // Shift operation - LSL, LSR, ASR.
              if (shift_type <= _u32(_ShiftOp.kASR)) {
                if (!has_sp) {
                  if (!checkSignature(o0, o1)) {
                    {
                      state = _S.InvalidInstruction;
                      continue loop;
                    }
                  }

                  if (shift_value >= op_size) {
                    {
                      state = _S.InvalidImmediate;
                      continue loop;
                    }
                  }

                  opcode.reset(_u32(op_data.shifted_op) << 21);
                  opcode.addImm(x, 31);
                  opcode.addImm(shift_type, 22);
                  opcode.addReg(o1, 16);
                  opcode.addImm(shift_value, 10);
                  opcode.addReg(o0, 5);
                  opcode.addReg(_kIdZr, 0);
                  {
                    state = _S.EmitOp;
                    continue loop;
                  }
                }

                // SP register can only be used with LSL or Extend.
                if (shift_type != _u32(_ShiftOp.kLSL)) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                shift_type =
                    x != 0 ? _u32(_ShiftOp.kUXTX) : _u32(_ShiftOp.kUXTW);
              }

              // Extend operation - UXTB, UXTH, UXTW, UXTX, SXTB, SXTH, SXTW, SXTX.
              shift_type -= _u32(_ShiftOp.kUXTB);
              if (shift_type > 7 || shift_value > 4) {
                {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
              }

              // Validate whether the register operands match extend option.
              if (o1.regType != extendOptionToRegType(shift_type) ||
                  o0.regType < o1.regType) {
                {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
              }

              opcode.reset(_u32(op_data.extended_op) << 21);
              opcode.addImm(x, 31);
              opcode.addReg(o1, 16);
              opcode.addImm(shift_type, 13);
              opcode.addImm(shift_value, 10);
              opcode.addReg(o0, 5);
              opcode.addReg(_kIdZr, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseMvnNeg;
          continue loop; // (after block)
        case _S.encBaseMvnNeg:
          {
            final op_data = baseMvnNeg[encodingIndex];

            // uint32_t x; (function-level)
            if (!checkGpTypeX(o0, o1, kWX)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            opcode.reset(op_data.opcode);
            opcode.addImm(x, 31);
            opcode.addReg(o1, 16);
            opcode.addReg(o0, 0);

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var op_size = _u32(x != 0 ? 64 : 32);
              var shift_type = _u32(o2.predicate);
              var shift_value = o2.imm;

              if (shift_type > _u32(_ShiftOp.kROR) || shift_value >= op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.addImm(shift_type, 22);
              opcode.addImm(shift_value, 10);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseTst;
          continue loop; // (after block)
        case _S.encBaseTst:
          {
            final op_data = baseTst[encodingIndex];

            // uint32_t x; (function-level)
            if (!checkGpTypeX(o0, kWX)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            var op_size = _u32(x != 0 ? 64 : 32);

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */ &&
                op_data.immediate_op != 0) {
              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              // TST (immediate) uses a LogicalImm format described by N:R:S values.
              var imm_mask = _lsbMask(op_size);
              var imm_value = o1.imm;

              // Logical instructions use 13-bit immediate pattern encoded as N:ImmS:ImmR.
              final logical_imm = LogicalImm();
              if (!encodeLogicalImm(
                  imm_value & imm_mask, op_size, logical_imm)) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(_u32(op_data.immediate_op) << 22);
              opcode.addLogicalImm(logical_imm);
              opcode.addImm(x, 31);
              opcode.addReg(o0, 5);
              opcode.addReg(_kIdZr, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            opcode.reset(_u32(op_data.shifted_op) << 21);
            opcode.addImm(x, 31);
            opcode.addReg(o1, 16);
            opcode.addReg(o0, 5);
            opcode.addReg(_kIdZr, 0);

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var shift_type = _u32(o2.predicate);
              var op_shift = o2.imm;

              if (shift_type > 0x3 || op_shift >= op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.addImm(shift_type, 22);
              opcode.addImm(op_shift, 10);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Bit Manipulation]
          // ------------------------------------------------------------------------

          state = _S.encBaseBfc;
          continue loop; // (after block)
        case _S.encBaseBfc:
          {
            final op_data = baseBfc[encodingIndex];

            if (isign4 == 289 /* ENC_OPS3(Reg, Imm, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var lsb = o1.imm;
              var width = o2.imm;
              var op_size = _u32(x != 0 ? 64 : 32);

              if (lsb >= op_size || width == 0 || width > op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var lsb32 = _u32(_neg(_u32(lsb)) & (op_size - 1));
              var width32 = _u32(_u32(width) - 1);

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(x, 22);
              opcode.addImm(lsb32, 16);
              opcode.addImm(width32, 10);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseBfi;
          continue loop; // (after block)
        case _S.encBaseBfi:
          {
            final op_data = baseBfi[encodingIndex];

            if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var lsb = o2.imm;
              var width = o3.imm;
              var op_size = _u32(x != 0 ? 64 : 32);

              if (lsb >= op_size || width == 0 || width > op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var imm_l = _u32(_neg(_u32(lsb)) & (op_size - 1));
              var imm_w = _u32(_u32(width) - 1);

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(x, 22);
              opcode.addImm(imm_l, 16);
              opcode.addImm(imm_w, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseBfm;
          continue loop; // (after block)
        case _S.encBaseBfm:
          {
            final op_data = baseBfm[encodingIndex];

            if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var imm_r = o2.imm;
              var imm_s = o3.imm;
              var op_size = _u32(x != 0 ? 64 : 32);

              if ((imm_r | imm_s) >= op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(x, 22);
              opcode.addImm(imm_r, 16);
              opcode.addImm(imm_s, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseBfx;
          continue loop; // (after block)
        case _S.encBaseBfx:
          {
            final op_data = baseBfx[encodingIndex];

            if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var lsb = o2.imm;
              var width = o3.imm;
              var op_size = _u32(x != 0 ? 64 : 32);

              if (lsb >= op_size || width == 0 || width > op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var lsb32 = _u32(_u32(lsb));
              var width32 = _u32(lsb32 + _u32(width) - 1);

              if (width32 >= op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(x, 22);
              opcode.addImm(lsb32, 16);
              opcode.addImm(width32, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseExtend;
          continue loop; // (after block)
        case _S.encBaseExtend:
          {
            final op_data = baseExtend[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!o1.isGp32()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(x, 22);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseExtract;
          continue loop; // (after block)
        case _S.encBaseExtract:
          {
            final op_data = baseExtract[encodingIndex];

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, o2)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var lsb = o3.imm;
              var op_size = _u32(x != 0 ? 64 : 32);

              if (lsb >= op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(x, 22);
              opcode.addReg(o2, 16);
              opcode.addImm(lsb, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRev;
          continue loop; // (after block)
        case _S.encBaseRev:
          {
            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(0x5ac00800);
              opcode.addImm(x, 31);
              opcode.addImm(x, 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseShift;
          continue loop; // (after block)
        case _S.encBaseShift:
          {
            final op_data = baseShift[encodingIndex];

            // uint32_t x; (function-level)
            if (!checkGpTypeX(o0, kWX)) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (!checkSignature(o0, o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, o2, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.register_op);
              opcode.addImm(x, 31);
              opcode.addReg(o2, 16);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */ &&
                op_data.immediate_op != 0) {
              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var imm_r = o2.imm;
              var op_size = _u32(x != 0 ? 64 : 32);

              if (imm_r >= op_size) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.immediate_op);
              opcode.addImm(x, 31);
              opcode.addImm(x, 22);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);

              if ((opcode.get() & _B(10)) != 0) {
                // ASR and LSR (immediate) has the same logic.
                opcode.addImm(x, 15);
                opcode.addImm(imm_r, 16);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              }

              if (op_data.ror == 0) {
                // LSL (immediate) is an alias to UBFM
                var ubfm_imm_r = _u32(_neg(_u32(imm_r)) & (op_size - 1));
                var ubfm_imm_s = _u32(op_size - 1 - _u32(imm_r));

                opcode.addImm(ubfm_imm_r, 16);
                opcode.addImm(ubfm_imm_s, 10);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              } else {
                // ROR (immediate) is an alias to EXTR.
                opcode.addImm(imm_r, 10);
                opcode.addReg(o1, 16);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Conditionals]
          // ------------------------------------------------------------------------

          state = _S.encBaseCCmp;
          continue loop; // (after block)
        case _S.encBaseCCmp:
          {
            final op_data = baseCCmp[encodingIndex];

            if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */ ||
                isign4 == 2337 /* ENC_OPS4(Reg, Imm, Imm, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var nzcv = o2.imm;
              var cond = o3.imm;

              if ((nzcv | cond) > 0xF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(condCodeToOpcodeField(_u32(cond)), 12);
              opcode.addImm(nzcv, 0);

              if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
                // CCMN|CCMP (register) form.
                if (!checkSignature(o0, o1)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (!checkGpId(o1, kZR)) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                opcode.addReg(o1, 16);
                opcode.addReg(o0, 5);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              } else {
                // CCMN|CCMP (immediate) form.
                var imm5 = o1.imm;
                if (imm5 > 0x1F) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                opcode.addImm(1, 11);
                opcode.addImm(imm5, 16);
                opcode.addReg(o0, 5);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseCInc;
          continue loop; // (after block)
        case _S.encBaseCInc:
          {
            final op_data = baseCInc[encodingIndex];

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, o1, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var cond = o2.imm;
              if (cond - 2 > 0xE) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addReg(o1, 16);
              opcode.addImm(condCodeToOpcodeField(_u32(cond)) ^ 1, 12);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseCSel;
          continue loop; // (after block)
        case _S.encBaseCSel:
          {
            final op_data = baseCSel[encodingIndex];

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, o1, o2, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, o2, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var cond = o3.imm;
              if (cond > 0xF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addReg(o2, 16);
              opcode.addImm(condCodeToOpcodeField(_u32(cond)), 12);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseCSet;
          continue loop; // (after block)
        case _S.encBaseCSet:
          {
            final op_data = baseCSet[encodingIndex];

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var cond = o1.imm;
              if (cond - 2 >= 0xE) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addImm(condCodeToOpcodeField(_u32(cond)) ^ 1, 12);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Min/Max]
          // ------------------------------------------------------------------------

          state = _S.encBaseMinMax;
          continue loop; // (after block)
        case _S.encBaseMinMax:
          {
            final op_data = baseMinMax[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.register_op);
              opcode.addImm(x, 31);
              opcode.addReg(o2, 16);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var imm = o2.imm;

              if ((op_data.immediate_op & (1 << 18)) != 0) {
                // Zero extend imm.
                if (!_isUintN(8, imm)) {
                  {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }
                }
              } else {
                // Sign extend imm.
                if (!_isIntN(8, (imm))) {
                  {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }
                }
              }

              opcode.reset(op_data.immediate_op);
              opcode.addImm(x, 31);
              opcode.addImm(_u32(imm & 0xFF), 10);
              opcode.addReg(o1, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Special]
          // ------------------------------------------------------------------------

          state = _S.encBaseAtDcIcTlbi;
          continue loop; // (after block)
        case _S.encBaseAtDcIcTlbi:
          {
            final op_data = baseAtDcIcTlbi[encodingIndex];

            if (isign4 == 4 /* ENC_OPS1(Imm) */ ||
                isign4 == 12 /* ENC_OPS2(Imm, Reg) */) {
              if (op_data.mandatory_reg != 0 &&
                  isign4 != 12 /* ENC_OPS2(Imm, Reg) */) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o0.imm > 0x7FFF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var imm = _u32(o0.immU32);
              if ((imm & op_data.imm_verify_mask) != op_data.imm_verify_data) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var rt = _u32(31);
              if (o1.isReg()) {
                if (!o1.isGp64()) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (!checkGpId(o1, kZR)) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                rt = o1.id & 31;
              }

              opcode.reset(0xd5080000);
              opcode.addImm(imm, 5);
              opcode.addReg(rt, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }
            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseMrs;
          continue loop; // (after block)
        case _S.encBaseMrs:
          {
            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              if (!o0.isGp64()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (o1.imm > 0xFFFF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var imm = _u32(o1.immU32);
              if ((imm & _B(15)) == 0) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(0xd5300000);
              opcode.addImm(imm, 5);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseMsr;
          continue loop; // (after block)
        case _S.encBaseMsr:
          {
            if (isign4 == 12 /* ENC_OPS2(Imm, Reg) */) {
              if (!o1.isGp64()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o0.imm > 0xFFFF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var imm = _u32(o0.immU32);
              if ((imm & _B(15)) == 0) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              if (!checkGpId(o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(0xd5100000);
              opcode.addImm(imm, 5);
              opcode.addReg(o1, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            if (isign4 == 36 /* ENC_OPS2(Imm, Imm) */) {
              if (o0.imm > 0x1F) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              if (o1.imm > 0xF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var op = _u32(o0.immU32);
              var crm = _u32(o1.immU32);

              var op1 = _u32(_u32(op) >> 3);
              var op2 = _u32(_u32(op) & 0x7);

              opcode.reset(0xd500401f);
              opcode.addImm(op1, 16);
              opcode.addImm(crm, 8);
              opcode.addImm(op2, 5);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseSys;
          continue loop; // (after block)
        case _S.encBaseSys:
          {
            if (isign4 == 2340 /* ENC_OPS4(Imm, Imm, Imm, Imm) */) {
              if (o0.imm > 0x7 ||
                  o1.imm > 0xF ||
                  o2.imm > 0xF ||
                  o3.imm > 0x7) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var op1 = _u32(o0.immU32);
              var crn = _u32(o1.immU32);
              var crm = _u32(o2.immU32);
              var op2 = _u32(o3.immU32);
              var rt = _u32(31);

              final o4 = opExt[4];
              if (o4.isReg()) {
                if (!o4.isGp64()) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (!checkGpId(o4, kZR)) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                rt = o4.id & 31;
              } else if (!o4.isNone()) {
                {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
              }

              opcode.reset(0xd5080000);
              opcode.addImm(op1, 16);
              opcode.addImm(crn, 12);
              opcode.addImm(crm, 8);
              opcode.addImm(op2, 5);
              opcode.addImm(rt, 0);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Branch]
          // ------------------------------------------------------------------------

          state = _S.encBaseBranchReg;
          continue loop; // (after block)
        case _S.encBaseBranchReg:
          {
            final op_data = baseBranchReg[encodingIndex];

            if (isign4 == 1 /* ENC_OPS1(Reg) */) {
              if (!o0.isGp64()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addReg(o0, 5);
              {
                state = _S.EmitOp;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseBranchRel;
          continue loop; // (after block)
        case _S.encBaseBranchRel:
          {
            final op_data = baseBranchRel[encodingIndex];

            if (isign4 == 5 /* ENC_OPS1(Label) */ ||
                isign4 == 4 /* ENC_OPS1(Imm) */) {
              opcode.reset(op_data.opcode);
              rmRel = o0;

              // A variation that uses Cond code (or where Cond code is forced like BC.<cond>).
              if (instCc != _CC.kAL || _bitTest(opcode.v, 30)) {
                if (opcode.hasX()) {
                  // Condition code cannot be applied when the instruction has X bit set (this would be BL instruction).
                  {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }
                }

                opcode.v |= _B(30);
                opcode.addImm(condCodeToOpcodeField(_u32(instCc)), 0);
                offsetFormat.resetToImmValue(
                    A64OffsetType.kSignedOffset, 4, 5, 19, 2);
                {
                  state = _S.EmitOp_Rel;
                  continue loop;
                }
              }

              offsetFormat.resetToImmValue(
                  A64OffsetType.kSignedOffset, 4, 0, 26, 2);
              {
                state = _S.EmitOp_Rel;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseBranchCmp;
          continue loop; // (after block)
        case _S.encBaseBranchCmp:
          {
            final op_data = baseBranchCmp[encodingIndex];

            if (isign4 == 41 /* ENC_OPS2(Reg, Label) */ ||
                isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, 31);
              opcode.addReg(o0, 0);
              offsetFormat.resetToImmValue(
                  A64OffsetType.kSignedOffset, 4, 5, 19, 2);

              rmRel = o1;
              {
                state = _S.EmitOp_Rel;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseBranchTst;
          continue loop; // (after block)
        case _S.encBaseBranchTst:
          {
            final op_data = baseBranchTst[encodingIndex];

            if (isign4 == 353 /* ENC_OPS3(Reg, Imm, Label) */ ||
                isign4 == 289 /* ENC_OPS3(Reg, Imm, Imm) */) {
              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, kWX)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              var imm = o1.imm;

              opcode.reset(op_data.opcode);
              if (imm >= 32) {
                if (x == 0) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
                opcode.addImm(x, 31);
                imm &= 0x1F;
              }

              opcode.addReg(o0, 0);
              opcode.addImm(imm, 19);
              offsetFormat.resetToImmValue(
                  A64OffsetType.kSignedOffset, 4, 5, 14, 2);

              rmRel = o2;
              {
                state = _S.EmitOp_Rel;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Prefetch]
          // ------------------------------------------------------------------------

          state = _S.encBasePrfm;
          continue loop; // (after block)
        case _S.encBasePrfm:
          {
            final op_data = basePrfm[encodingIndex];

            if (isign4 == 20 /* ENC_OPS2(Imm, Mem) */) {
              final m = o1;
              rmRel = m;

              var imm_shift = _u32(3);

              if (o0.imm > 0x1F) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              if (!checkMemBaseIndexRel(m)) {
                state = _S.InvalidAddress;
                continue loop;
              }

              var offset = m.offset;
              var prfop = _u32(o0.immU32);

              if (m.hasBaseReg()) {
                // [Base {Offset | Index}]
                if (m.hasIndex()) {
                  var opt = _u32(shiftOpToLdStOptMap((m.shiftOp)));
                  if (opt == 0xFF) {
                    state = _S.InvalidAddress;
                    continue loop;
                  }

                  var shift = _u32(m.shift);
                  var s = _u32(shift != 0);

                  if (s != 0 && shift != imm_shift) {
                    state = _S.InvalidAddressScale;
                    continue loop;
                  }

                  opcode.reset(_u32(op_data.register_op) << 21);
                  opcode.addImm(opt, 13);
                  opcode.addImm(s, 12);
                  opcode.v |= _B(11);
                  opcode.addImm(prfop, 0);
                  {
                    state = _S.EmitOp_MemBaseIndex_Rn5_Rm16;
                    continue loop;
                  }
                }

                if (!_isIntN(32, offset)) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                var offset32 = _i32(_i32(offset));

                if (m.isPreOrPost()) {
                  state = _S.InvalidAddress;
                  continue loop;
                }

                var imm12 = _u32(_u32(offset32) >> imm_shift);

                if (_isUintN(12, imm12) &&
                    (imm12 << imm_shift) == _u32(offset32)) {
                  opcode.reset(_u32(op_data.s_offset_op) << 22);
                  opcode.addImm(imm12, 10);
                  opcode.addImm(prfop, 0);
                  {
                    state = _S.EmitOp_MemBase_Rn5;
                    continue loop;
                  }
                }

                if (_isIntN(9, offset32)) {
                  opcode.reset(_u32(op_data.u_offset_op) << 21);
                  opcode.addImm(_u32(offset32) & 0x1FF, 12);
                  opcode.addImm(prfop, 0);
                  {
                    state = _S.EmitOp_MemBase_Rn5;
                    continue loop;
                  }
                }

                {
                  state = _S.InvalidAddress;
                  continue loop;
                }
              } else {
                opcode.reset(_u32(op_data.literal_op) << 24);
                opcode.addImm(prfop, 0);
                offsetFormat.resetToImmValue(
                    A64OffsetType.kSignedOffset, 4, 5, 19, 2);
                {
                  state = _S.EmitOp_Rel;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Base - Load / Store]
          // ------------------------------------------------------------------------

          state = _S.encBaseLdSt;
          continue loop; // (after block)
        case _S.encBaseLdSt:
          {
            final op_data = baseLdSt[encodingIndex];

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              final m = o1;
              rmRel = m;

              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              // Instructions that work with either word or dword have the unsigned
              // offset shift set to 2 (word), so we set it to 3 (dword) if this is
              // X version of the instruction.
              var x_shift_mask = _u32(_u32(op_data.u_offset_shift == 2));
              var imm_shift =
                  _u32(_u32(op_data.u_offset_shift) + (x & x_shift_mask));

              if (!checkMemBaseIndexRel(m)) {
                state = _S.InvalidAddress;
                continue loop;
              }

              var offset = m.offset;
              if (m.hasBaseReg()) {
                // [Base {Offset | Index}]
                if (m.hasIndex()) {
                  var opt = _u32(shiftOpToLdStOptMap((m.shiftOp)));
                  if (opt == 0xFF) {
                    state = _S.InvalidAddress;
                    continue loop;
                  }

                  var shift = _u32(m.shift);
                  var s = _u32(shift != 0);

                  if (s != 0 && shift != imm_shift) {
                    state = _S.InvalidAddressScale;
                    continue loop;
                  }

                  opcode.reset(_u32(op_data.register_op) << 21);
                  opcode.xorImm(x, op_data.x_offset);
                  opcode.addImm(opt, 13);
                  opcode.addImm(s, 12);
                  opcode.v |= _B(11);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp_MemBaseIndex_Rn5_Rm16;
                    continue loop;
                  }
                }

                // Makes it easier to work with the offset especially on 32-bit arch.
                if (!_isIntN(32, offset)) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }
                var offset32 = _i32(_i32(offset));

                if (m.isPreOrPost()) {
                  if (!_isIntN(9, offset32)) {
                    state = _S.InvalidDisplacement;
                    continue loop;
                  }

                  opcode.reset(_u32(op_data.pre_post_op) << 21);
                  opcode.xorImm(x, op_data.x_offset);
                  opcode.addImm(offset32 & 0x1FF, 12);
                  opcode.addImm(m.isPreIndex(), 11);
                  opcode.v |= _B(10);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp_MemBase_Rn5;
                    continue loop;
                  }
                } else {
                  var imm12 = _u32(_u32(offset32) >> imm_shift);

                  // Alternative form of LDUR/STUR and related instructions as described by AArch64 reference manual:
                  //
                  // If this instruction is not encodable with scaled unsigned offset, try unscaled signed offset.
                  if (!_isUintN(12, imm12) ||
                      (imm12 << imm_shift) != _u32(offset32)) {
                    instId = op_data.u_alt_inst_id;
                    instInfo = kA64UpInstInfo[instId];
                    encodingIndex = instInfo.encodingDataIndex;
                    {
                      state = _S.Case_BaseLdurStur;
                      continue loop;
                    }
                  }

                  opcode.reset(_u32(op_data.u_offset_op) << 22);
                  opcode.xorImm(x, op_data.x_offset);
                  opcode.addImm(imm12, 10);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp_MemBase_Rn5;
                    continue loop;
                  }
                }
              } else {
                if ((op_data.literal_op == 0)) {
                  state = _S.InvalidAddress;
                  continue loop;
                }

                opcode.reset(_u32(op_data.literal_op) << 24);
                opcode.xorImm(x, op_data.x_offset);
                opcode.addReg(o0, 0);
                offsetFormat.resetToImmValue(
                    A64OffsetType.kSignedOffset, 4, 5, 19, 2);
                {
                  state = _S.EmitOp_Rel;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseLdpStp;
          continue loop; // (after block)
        case _S.encBaseLdpStp:
          {
            final op_data = baseLdpStp[encodingIndex];

            if (isign4 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
              final m = o2;
              rmRel = m;

              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, o1, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (m.baseType != _RT.kGp64 || m.hasIndex()) {
                state = _S.InvalidAddress;
                continue loop;
              }

              if (m.isOffset64bit()) {
                state = _S.InvalidDisplacement;
                continue loop;
              }

              var offset_shift = _u32(op_data.offset_shift + x);
              var offset32 = _i32(m.offsetLo32 >> offset_shift);

              // Make sure we didn't lose bits by applying the mandatory offset shift.
              if (_u32(_u32(offset32) << offset_shift) != _u32(m.offsetLo32)) {
                state = _S.InvalidDisplacement;
                continue loop;
              }

              // Offset is encoded as 7-bit immediate.
              if (!_isIntN(7, offset32)) {
                state = _S.InvalidDisplacement;
                continue loop;
              }

              if (m.isPreOrPost() && offset32 != 0) {
                if ((op_data.pre_post_op == 0)) {
                  state = _S.InvalidAddress;
                  continue loop;
                }

                opcode.reset(_u32(op_data.pre_post_op) << 22);
                opcode.addImm(m.isPreIndex(), 24);
              } else {
                opcode.reset(_u32(op_data.offset_op) << 22);
              }

              opcode.addImm(x, op_data.x_offset);
              opcode.addImm(offset32 & 0x7F, 15);
              opcode.addReg(o1, 10);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp_MemBase_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseStx;
          continue loop; // (after block)
        case _S.encBaseStx:
          {
            final op_data = baseStx[encodingIndex];

            if (isign4 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
              final m = o2;
              // uint32_t x; (function-level)

              if (!o0.isGp32() || !checkGpTypeX(o1, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, op_data.x_offset);
              opcode.addReg(o0, 16);
              opcode.addReg(o1, 0);

              rmRel = m;
              {
                state = _S.EmitOp_MemBaseNoImm_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseLdxp;
          continue loop; // (after block)
        case _S.encBaseLdxp:
          {
            final op_data = baseLdxp[encodingIndex];

            if (isign4 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
              final m = o2;
              // uint32_t x; (function-level)

              if (!checkGpTypeX(o0, op_data.reg_type) ||
                  !checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, op_data.x_offset);
              opcode.addReg(o1, 10);
              opcode.addReg(o0, 0);

              rmRel = m;
              {
                state = _S.EmitOp_MemBaseNoImm_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseStxp;
          continue loop; // (after block)
        case _S.encBaseStxp:
          {
            final op_data = baseStxp[encodingIndex];

            if (isign4 == 1097 /* ENC_OPS4(Reg, Reg, Reg, Mem) */) {
              final m = o3;
              // uint32_t x; (function-level)

              if (!o0.isGp32() ||
                  !checkGpTypeX(o1, op_data.reg_type) ||
                  !checkSignature(o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, o2, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, op_data.x_offset);
              opcode.addReg(o0, 16);
              opcode.addReg(o2, 10);
              opcode.addReg(o1, 0);

              rmRel = m;
              {
                state = _S.EmitOp_MemBaseNoImm_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRM_NoImm;
          continue loop; // (after block)
        case _S.encBaseRM_NoImm:
          {
            final op_data = baseRM_NoImm[encodingIndex];

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              final m = o1;
              rmRel = m;

              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.reg_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, op_data.x_offset);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp_MemBaseNoImm_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRM_SImm9;
          continue loop; // (after block)
        case _S.encBaseRM_SImm9:
        case _S.Case_BaseLdurStur:
          {
            final op_data = baseRM_SImm9[encodingIndex];

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              final m = o1;
              rmRel = m;

              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.reg_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (m.hasBaseReg() && !m.hasIndex()) {
                if (m.isOffset64bit()) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                var offset32 = _i32(m.offsetLo32 >> op_data.imm_shift);
                if (_shl(offset32, op_data.imm_shift) != m.offsetLo32) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                if (!_isIntN(9, offset32)) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                if (m.isFixedOffset()) {
                  opcode.reset(op_data.offset_op);
                } else {
                  if ((op_data.pre_post_op == 0)) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  opcode.reset(op_data.pre_post_op);
                  opcode.xorImm(m.isPreIndex(), 11);
                }

                opcode.xorImm(x, op_data.x_offset);
                opcode.addImm(offset32 & 0x1FF, 12);
                opcode.addReg(o0, 0);
                {
                  state = _S.EmitOp_MemBase_Rn5;
                  continue loop;
                }
              }

              {
                state = _S.InvalidAddress;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseRM_SImm10;
          continue loop; // (after block)
        case _S.encBaseRM_SImm10:
          {
            final op_data = baseRM_SImm10[encodingIndex];

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              final m = o1;
              rmRel = m;

              // uint32_t x; (function-level)
              if (!checkGpTypeX(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, op_data.reg_hi_id)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (m.hasBaseReg() && !m.hasIndex()) {
                if (m.isOffset64bit()) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                var offset32 = _i32(m.offsetLo32 >> op_data.imm_shift);
                if (_shl(offset32, op_data.imm_shift) != m.offsetLo32) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                if (!_isIntN(10, offset32)) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                if (m.isPostIndex()) {
                  state = _S.InvalidAddress;
                  continue loop;
                }

                // Offset has 10 bits, sign is stored in the 10th bit.
                offset32 &= 0x3FF;

                opcode.reset(op_data.opcode);
                opcode.xorImm(m.isPreIndex(), 11);
                opcode.xorImm(x, op_data.x_offset);
                opcode.addImm(offset32 >> 9, 22);
                opcode.addImm(offset32, 12);
                opcode.addReg(o0, 0);
                {
                  state = _S.EmitOp_MemBase_Rn5;
                  continue loop;
                }
              }

              {
                state = _S.InvalidAddress;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseAtomicOp;
          continue loop; // (after block)
        case _S.encBaseAtomicOp:
          {
            final op_data = baseAtomicOp[encodingIndex];

            if (isign4 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
              final m = o2;
              // uint32_t x; (function-level)

              if (!checkGpTypeX(o0, op_data.reg_type) ||
                  !checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, o1, kZR)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, op_data.x_offset);
              opcode.addReg(o0, 16);
              opcode.addReg(o1, 0);

              rmRel = m;
              {
                state = _S.EmitOp_MemBaseNoImm_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseAtomicSt;
          continue loop; // (after block)
        case _S.encBaseAtomicSt:
          {
            final op_data = baseAtomicSt[encodingIndex];

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              final m = o1;
              // uint32_t x; (function-level)

              if (!checkGpTypeX(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkGpId(o0, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, op_data.x_offset);
              opcode.addReg(o0, 16);
              opcode.addReg(_kIdZr, 0);

              rmRel = m;
              {
                state = _S.EmitOp_MemBaseNoImm_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encBaseAtomicCasp;
          continue loop; // (after block)
        case _S.encBaseAtomicCasp:
          {
            final op_data = baseAtomicCasp[encodingIndex];
            final o4 = opExt[4];

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */ &&
                o4.isMem()) {
              final m = o4;
              // uint32_t x; (function-level)

              if (!checkGpTypeX(o0, op_data.reg_type)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1, o2, o3)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkEven(o0, o2) || !checkGpId(o0, o2, kZR)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkConsecutive(o0, o1) || !checkConsecutive(o2, o3)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(x, op_data.x_offset);
              opcode.addReg(o0, 16);
              opcode.addReg(o2, 0);

              rmRel = m;
              {
                state = _S.EmitOp_MemBaseNoImm_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [FSimd - Instructions]
          // ------------------------------------------------------------------------

          state = _S.encFSimdSV;
          continue loop; // (after block)
        case _S.encFSimdSV:
          {
            final op_data = fSimdSV[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              var q = _u32(_diff(o1.regType, _RT.kVec64));
              if (q > 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o0.hasElementType()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // This operation is only defined for:
              //   hD, vS.{4|8}h (16-bit)
              //   sD, vS.4s     (32-bit)
              var sz = _u32(_diff(o0.regType, _RT.kVec16));
              var element_sz = _u32(_diff(o1.elementType, _ET.kH));

              // Size greater than 1 means 64-bit elements, not supported.
              if ((sz | element_sz) > 1 || sz != element_sz) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // Size 1 (32-bit float) requires at least 4 elements.
              if (sz != 0 && q == 0) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // Bit flipping according to sz.
              final sz_bits_table = [_B(29), 0];

              opcode.reset(op_data.opcode << 10);
              opcode.v ^= sz_bits_table[sz];
              opcode.addImm(q, 30);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encFSimdVV;
          continue loop; // (after block)
        case _S.encFSimdVV:
          {
            final op_data = fSimdVV[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (!matchSignature(o0, o1, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!pickFpOpcode(o0, op_data.scalar_op, op_data.scalar_hf,
                  op_data.vector_op, op_data.vector_hf, opcode)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encFSimdVVV;
          continue loop; // (after block)
        case _S.encFSimdVVV:
          {
            final op_data = fSimdVVV[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!pickFpOpcode(o0, op_data.scalar_op, op_data.scalar_hf,
                  op_data.vector_op, op_data.vector_hf, opcode)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encFSimdVVVe;
          continue loop; // (after block)
        case _S.encFSimdVVVe:
          {
            final op_data = fSimdVVVe[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (!o2.hasElementIndex()) {
                if (!matchSignature(o0, o1, o2, instFlags)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (!pickFpOpcode(o0, op_data.scalar_op, op_data.scalar_hf,
                    op_data.vector_op, op_data.vector_hf, opcode)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              } else {
                if (!matchSignature(o0, o1, instFlags)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var q = _u32(o1.isVec128());
                final szOut = [0];

                if (!pickFpOpcode(o0, op_data.element_scalar_op, kHF_D,
                    op_data.element_vector_op, kHF_D, opcode, szOut)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
                final sz = szOut[0];

                if (sz == 0 && o2.id > 15) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                var element_index = _u32(o2.elementIndex);
                if (element_index > (7 >> sz)) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                var hlm = _u32(element_index << sz);
                opcode.addImm(q, 30);
                opcode.addImm(hlm & 3, 20);
                opcode.addImm(hlm >> 2, 11);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encFSimdVVVV;
          continue loop; // (after block)
        case _S.encFSimdVVVV:
          {
            final op_data = fSimdVVVV[encodingIndex];

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              if (!matchSignature(o0, o1, o2, o3, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!pickFpOpcode(o0, op_data.scalar_op, op_data.scalar_hf,
                  op_data.vector_op, op_data.vector_hf, opcode)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              {
                state = _S.EmitOp_Rd0_Rn5_Rm16_Ra10;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcadd;
          continue loop; // (after block)
        case _S.encSimdFcadd:
          {
            final op_data = simdFcadd[encodingIndex];

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              if (!checkSignature(o0, o1, o2) || o0.hasElementIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var q = _u32(_diff(o0.regType, _RT.kVec64));
              if (q > 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var sz = _u32(_diff(o0.elementType, _ET.kB));
              if (sz == 0 || sz > 3) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // 0 <- 90deg.
              // 1 <- 270deg.
              var rot = _u32(0);
              if (o3.imm == 270)
                rot = 1;
              else if (o3.imm != 90) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(q, 30);
              opcode.addImm(sz, 22);
              opcode.addImm(rot, 12);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFccmpFccmpe;
          continue loop; // (after block)
        case _S.encSimdFccmpFccmpe:
          {
            final op_data = simdFccmpFccmpe[encodingIndex];

            if (isign4 == 2313 /* ENC_OPS4(Reg, Reg, Imm, Imm) */) {
              var sz = _u32(_diff(o0.regType, _RT.kVec16));
              if (sz > 2) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1) || o0.hasElementType()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var nzcv = o2.imm;
              var cond = o3.imm;

              if ((nzcv | cond) > 0xF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var type = _u32((sz - 1) & 0x3);

              opcode.reset(op_data.opcode);
              opcode.addImm(type, 22);
              opcode.addImm(condCodeToOpcodeField(_u32(cond)), 12);
              opcode.addImm(nzcv, 0);

              {
                state = _S.EmitOp_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcm;
          continue loop; // (after block)
        case _S.encSimdFcm:
          {
            final op_data = simdFcm[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */ &&
                op_data.has_register_op != 0) {
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!pickFpOpcode(
                  o0,
                  op_data.register_scalar_op,
                  op_data.register_scalar_hf,
                  op_data.register_vector_op,
                  op_data.register_vector_hf,
                  opcode)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */ &&
                op_data.has_zero_op != 0) {
              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o2.imm != 0 || o2.predicate != 0) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              if (!pickFpOpcode(o0, op_data.zero_scalar_op, kHF_B,
                  op_data.zero_vector_op, kHF_B, opcode)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcmla;
          continue loop; // (after block)
        case _S.encSimdFcmla:
          {
            final op_data = simdFcmla[encodingIndex];

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var q = _u32(_diff(o0.regType, _RT.kVec64));
              if (q > 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var sz = _u32(_diff(o0.elementType, _ET.kB));
              if (sz == 0 || sz > 3) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var rot = _u32(0);
              switch (o3.imm) {
                case 0:
                  rot = 0;
                  break;
                case 90:
                  rot = 1;
                  break;
                case 180:
                  rot = 2;
                  break;
                case 270:
                  rot = 3;
                  break;
                default:
                  {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }
              }

              if (!o2.hasElementIndex()) {
                if (!checkSignature(o1, o2)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                opcode.reset(op_data.regular_op);
                opcode.addImm(q, 30);
                opcode.addImm(sz, 22);
                opcode.addImm(rot, 11);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              } else {
                if (o0.elementType != o2.elementType) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                // Only allowed vectors are: 4H, 8H, and 4S.
                if (!(sz == 1 || (q == 1 && sz == 2))) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                // Element index ranges:
                //   4H - ElementIndex[0..1] (index 2..3 is UNDEFINED).
                //   8H - ElementIndex[0..3].
                //   4S - ElementIndex[0..1].
                var element_index = _u32(o2.elementIndex);
                var hl_field_shift = _u32(sz == 1 ? 0 : 1);
                var max_element_index = _u32(q == 1 && sz == 1 ? 3 : 1);

                if (element_index > max_element_index) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                var hl = _u32(element_index << hl_field_shift);

                opcode.reset(op_data.element_op);
                opcode.addImm(q, 30);
                opcode.addImm(sz, 22);
                opcode.addImm(hl & 1, 21); // L field.
                opcode.addImm(hl >> 1, 11); // H field.
                opcode.addImm(rot, 13);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcmpFcmpe;
          continue loop; // (after block)
        case _S.encSimdFcmpFcmpe:
          {
            final op_data = simdFcmpFcmpe[encodingIndex];

            var sz = _u32(_diff(o0.regType, _RT.kVec16));
            var type = _u32((sz - 1) & 0x3);

            if (sz > 2) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (o0.hasElementType()) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            opcode.reset(op_data.opcode);
            opcode.addImm(type, 22);

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              {
                state = _S.EmitOp_Rn5_Rm16;
                continue loop;
              }
            }

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              if (o1.imm != 0 || o1.predicate != 0) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.v |= _B(3);
              {
                state = _S.EmitOp_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcsel;
          continue loop; // (after block)
        case _S.encSimdFcsel:
          {
            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              if (!checkSignature(o0, o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var sz = _u32(_diff(o0.regType, _RT.kVec16));
              var type = _u32((sz - 1) & 0x3);

              if (sz > 2 || o0.hasElementType()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var cond = o3.imm;
              if (cond > 0xF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(0x1e200c00);
              opcode.addImm(type, 22);
              opcode.addImm(condCodeToOpcodeField(_u32(cond)), 12);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcvt;
          continue loop; // (after block)
        case _S.encSimdFcvt:
          {
            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              var dst_sz = _u32(_diff(o0.regType, _RT.kVec16));
              var src_sz = _u32(_diff(o1.regType, _RT.kVec16));

              if ((dst_sz | src_sz) > 3) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o0.hasElementType() || o1.hasElementType()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // Table that provides 'type' and 'opc' according to the dst/src combination.
              final table = [
                0xFF, // H <- H (Invalid).
                0x03, // H <- S (type=00 opc=11).
                0x13, // H <- D (type=01 opc=11).
                0xFF, // H <- Q (Invalid).
                0x30, // S <- H (type=11 opc=00).
                0xFF, // S <- S (Invalid).
                0x10, // S <- D (type=01 opc=00).
                0xFF, // S <- Q (Invalid).
                0x31, // D <- H (type=11 opc=01).
                0x01, // D <- S (type=00 opc=01).
                0xFF, // D <- D (Invalid).
                0xFF, // D <- Q (Invalid).
                0xFF, // Q <- H (Invalid).
                0xFF, // Q <- S (Invalid).
                0xFF, // Q <- D (Invalid).
                0xFF // Q <- Q (Invalid).
              ];

              var type_opc = _u32(table[(dst_sz << 2) | src_sz]);
              opcode.reset(0x78890 << 10);
              opcode.addImm(type_opc >> 4, 22);
              opcode.addImm(type_opc & 15, 15);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcvtLN;
          continue loop; // (after block)
        case _S.encSimdFcvtLN:
          {
            final op_data = simdFcvtLN[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // Scalar form - only FCVTXN.
              if (o0.isVec32() && o1.isVec64()) {
                if ((op_data.has_scalar == 0)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (o0.hasElementType() || o1.hasElementType()) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                opcode.reset(op_data.scalar_op);
                opcode.v |= _B(
                    22); // sz bit must be 1, the only supported combination of FCVTXN.
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              opcode.reset(op_data.vector_op);

              final rl = (instFlags & kInstFlagLong) != 0 ? o0 : o1;
              final rn = (instFlags & kInstFlagLong) != 0 ? o1 : o0;

              var q = _u32(_diff(rn.regType, _RT.kVec64));
              if (_u32(opcode.hasQ()) != q) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (rl.isVecS4() &&
                  rn.elementType == _ET.kH &&
                  (op_data.is_cvtxn == 0)) {
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              if (rl.isVecD2() && rn.elementType == _ET.kS) {
                opcode.v |= _B(22);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFcvtSV;
          continue loop; // (after block)
        case _S.encSimdFcvtSV:
          {
            final op_data = simdFcvtSV[encodingIndex];

            // So we can support both IntToFloat and FloatToInt conversions.
            final op_gp = op_data.is_float_to_int != 0 ? o0 : o1;
            final op_vec = op_data.is_float_to_int != 0 ? o1 : o0;

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (op_gp.isGp() && op_vec.isVec()) {
                var x = _u32(op_gp.isGp64());
                var type = _u32(_diff(op_vec.regType, _RT.kVec16));

                if (type > 2) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                type = (type - 1) & 0x3;
                opcode.reset(op_data.general_op);
                opcode.addImm(type, 22);
                opcode.addImm(x, 31);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              if (o0.isVec() && o1.isVec()) {
                if (!checkSignature(o0, o1)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (!pickFpOpcode(o0, op_data.scalar_int_op, kHF_B,
                    op_data.vector_int_op, kHF_B, opcode)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */ &&
                op_data.is_fixed_point != 0) {
              if (o2.imm >= 64) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var scale = _u32(o2.immU32);
              if (scale == 0) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (op_gp.isGp() && op_vec.isVec()) {
                var x = _u32(op_gp.isGp64());
                var type = _u32(_diff(op_vec.regType, _RT.kVec16));

                var scale_limit = _u32(32 << x);
                if (scale > scale_limit) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                type = (type - 1) & 0x3;
                opcode.reset(op_data.general_op ^ _B(21));
                opcode.addImm(type, 22);
                opcode.addImm(x, 31);
                opcode.addImm(64 - scale, 10);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              if (o0.isVec() && o1.isVec()) {
                if (!checkSignature(o0, o1)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                final szOut = [0];
                if (!pickFpOpcode(o0, op_data.scalar_fp_op, kHF_0,
                    op_data.vector_fp_op, kHF_0, opcode, szOut)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
                final sz = szOut[0];

                var scale_limit = _u32(16 << sz);
                if (scale > scale_limit) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var imm = _u32(_neg(scale) & _lsbMask(sz + 4 + 1));
                opcode.addImm(imm, 16);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFmlal;
          continue loop; // (after block)
        case _S.encSimdFmlal:
          {
            final op_data = simdFmlal[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              var q = _u32(_diff(o0.regType, _RT.kVec64));
              var q_is_optional = _u32(op_data.optional_q);

              if (q_is_optional != 0) {
                // This instruction works with either 64-bit or 128-bit registers,
                // encoded by Q bit.
                if (q > 1) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
              } else {
                // This instruction requires 128-bit vector registers.
                if (q != 1) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                // The instruction is ehtier B (bottom) or T (top), which is part of
                // the opcode, which uses Q bit, so we have to clear it explicitly.
                q = 0;
              }

              if (_u32(o0.regType) != _u32(o1.regType) + q_is_optional ||
                  _u32(o0.elementType) != op_data.ta ||
                  _u32(o1.elementType) != op_data.tb) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!o2.hasElementIndex()) {
                if (!checkSignature(o1, o2)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                opcode.reset(op_data.vector_op);
                opcode.addImm(q, 30);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              } else {
                if (_u32(o2.elementType) != op_data.tElement) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (o2.id > 15) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                var element_index = _u32(o2.elementIndex);
                if (element_index > 7) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                opcode.reset(op_data.element_op);
                opcode.addImm(q, 30);
                opcode.addImm(element_index & 3, 20);
                opcode.addImm(element_index >> 2, 11);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdFmov;
          continue loop; // (after block)
        case _S.encSimdFmov:
          {
            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // FMOV Gp <-> Vec opcode:
              opcode.reset(0x1e260000);

              if (o0.isGp() && o1.isVec()) {
                // FMOV Wd, Hn      (sf=0 type=11 rmode=00 op=110)
                // FMOV Xd, Hn      (sf=1 type=11 rmode=00 op=110)
                // FMOV Wd, Sn      (sf=0 type=00 rmode=00 op=110)
                // FMOV Xd, Dn      (sf=1 type=11 rmode=00 op=110)
                // FMOV Xd, Vn.d[1] (sf=1 type=10 rmode=01 op=110)
                var x = _u32(o0.isGp64());
                var sz = _u32(_diff(o1.regType, _RT.kVec16));

                var type = _u32((sz - 1) & 0x3);
                var r_mode_op = _u32(0x6);

                if (o1.hasElementIndex()) {
                  // Special case.
                  if (x == 0 || !o1.isVecD2() || o1.elementIndex != 1) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }
                  type = 0x2;
                  r_mode_op = 0xe;
                } else {
                  // Must be scalar.
                  if (sz > 2) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o1.hasElementType()) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o1.isVec32() && x != 0) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o1.isVec64() && x == 0) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }
                }

                opcode.addImm(x, 31);
                opcode.addImm(type, 22);
                opcode.addImm(r_mode_op, 16);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              if (o0.isVec() && o1.isGp()) {
                // FMOV Hd, Wn      (sf=0 type=11 rmode=00 op=111)
                // FMOV Hd, Xn      (sf=1 type=11 rmode=00 op=111)
                // FMOV Sd, Wn      (sf=0 type=00 rmode=00 op=111)
                // FMOV Dd, Xn      (sf=1 type=11 rmode=00 op=111)
                // FMOV Vd.d[1], Xn (sf=1 type=10 rmode=01 op=111)
                var x = _u32(o1.isGp64());
                var sz = _u32(_diff(o0.regType, _RT.kVec16));

                var type = _u32((sz - 1) & 0x3);
                var r_mode_op = _u32(0x7);

                if (o0.hasElementIndex()) {
                  // Special case.
                  if (x == 0 || !o0.isVecD2() || o0.elementIndex != 1) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }
                  type = 0x2;
                  r_mode_op = 0xf;
                } else {
                  // Must be scalar.
                  if (sz > 2) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o0.hasElementType()) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o0.isVec32() && x != 0) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o0.isVec64() && x == 0) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }
                }

                opcode.addImm(x, 31);
                opcode.addImm(type, 22);
                opcode.addImm(r_mode_op, 16);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              if (checkSignature(o0, o1)) {
                var sz = _u32(_diff(o0.regType, _RT.kVec16));
                if (sz > 2) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (o0.hasElementType()) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var type = _u32((sz - 1) & 0x3);
                opcode.reset(0x1e204000);
                opcode.addImm(type, 22);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }
            }

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */) {
              if (o0.isVec()) {
                double fp_value;
                if (o1.isDouble())
                  fp_value = o1.immAsDouble;
                else if (o1.isInt32())
                  fp_value = o1.immI32.toDouble();
                else {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                if (!isFp64Imm8(doubleBits(fp_value))) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                var imm8 = _u32(encodeFp64ToImm8(doubleBits(fp_value)));
                if (!o0.hasElementType()) {
                  // FMOV (scalar, immediate).
                  var sz = _u32(_diff(o0.regType, _RT.kVec16));
                  var type = _u32((sz - 1) & 0x3);

                  if (sz > 2) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  opcode.reset(0x1e201000);
                  opcode.addImm(type, 22);
                  opcode.addImm(imm8, 13);
                  {
                    state = _S.EmitOp_Rd0;
                    continue loop;
                  }
                } else {
                  var q = _u32(_diff(o0.regType, _RT.kVec64));
                  var sz = _u32(_diff(o0.elementType, _ET.kH));

                  if (q > 1 || sz > 2) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  final sz_bits_table = [_B(11), 0, _B(29)];
                  opcode.reset(0xf00f400);
                  opcode.v ^= sz_bits_table[sz];
                  opcode.addImm(q, 30);
                  opcode.addImm(imm8 >> 5, 16);
                  opcode.addImm(imm8 & 31, 5);
                  {
                    state = _S.EmitOp_Rd0;
                    continue loop;
                  }
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encFSimdPair;
          continue loop; // (after block)
        case _S.encFSimdPair:
          {
            final op_data = fSimdPair[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // This operation is only defined for:
              //   hD, vS.2h (16-bit)
              //   sD, vS.2s (32-bit)
              //   dD, vS.2d (64-bit)
              var sz = _u32(_diff(o0.regType, _RT.kVec16));
              if (sz > 2) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              final szSignatures = [
                _sigOf(_RT.kVec32) | ((_ET.kH << 12)),
                _sigOf(_RT.kVec64) | ((_ET.kS << 12)),
                _sigOf(_RT.kVec128) | ((_ET.kD << 12))
              ];

              if (o1.signature != szSignatures[sz]) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              final sz_bits_table = [_B(29), 0, _B(22)];
              opcode.reset(op_data.scalar_op);
              opcode.v ^= sz_bits_table[sz];
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (!checkSignature(o0, o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var q = _u32(_diff(o0.regType, _RT.kVec64));
              if (q > 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var sz = _u32(_diff(o0.elementType, _ET.kH));
              if (sz > 2) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              final sz_bits_table = [
                _B(22) | _B(21) | _B(15) | _B(14),
                0,
                _B(22)
              ];
              opcode.reset(op_data.vector_op);
              opcode.v ^= sz_bits_table[sz];
              opcode.addImm(q, 30);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [ISimd - Instructions]
          // ------------------------------------------------------------------------

          state = _S.encISimdSV;
          continue loop; // (after block)
        case _S.encISimdSV:
          {
            final op_data = iSimdSV[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // The first destination operand is scalar, which matches element-type of source vectors.
              var L = _u32((instFlags & kInstFlagLong) != 0);
              if (_diff(o0.regType, _RT.kVec8) !=
                  _diff(o1.elementType, _ET.kB) + L) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, o1.regType, o1.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(size_op.q(), 30);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVV;
          continue loop; // (after block)
        case _S.encISimdVV:
          {
            final op_data = iSimdVV[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              final sop = significantSimdOp(o0, o1, instFlags);
              if (!matchSignature(o0, o1, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, sop.regType, sop.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVVx;
          continue loop; // (after block)
        case _S.encISimdVVx:
          {
            final op_data = iSimdVVx[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (o0.signature != op_data.op0_signature ||
                  o1.signature != op_data.op1_signature) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVVV;
          continue loop; // (after block)
        case _S.encISimdVVV:
          {
            final op_data = iSimdVVV[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              final sop = significantSimdOp(o0, o1, instFlags);
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, sop.regType, sop.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVVVx;
          continue loop; // (after block)
        case _S.encISimdVVVx:
          {
            final op_data = iSimdVVVx[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (o0.signature != op_data.op0_signature ||
                  o1.signature != op_data.op1_signature ||
                  o2.signature != op_data.op2_signature) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdWWV;
          continue loop; // (after block)
        case _S.encISimdWWV:
          {
            // Special case for wide add/sub [s|b][add|sub][w]{2}.
            final op_data = iSimdWWV[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, o2.regType, o2.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1) ||
                  !o0.isVec128() ||
                  _u32(o0.elementType) != _u32(o2.elementType) + 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVVVe;
          continue loop; // (after block)
        case _S.encISimdVVVe:
          {
            final op_data = iSimdVVVe[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              final sop = significantSimdOp(o0, o1, instFlags);
              if (!matchSignature(o0, o1, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!o2.hasElementIndex()) {
                var size_op = elementTypeToSizeOp(
                    op_data.regular_vec_type, sop.regType, sop.elementType);
                if (!size_op.isValid()) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (!checkSignature(o1, o2)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                opcode.reset(_u32(op_data.regular_op) << 10);
                opcode.addImm(size_op.qs(), 30);
                opcode.addImm(size_op.scalar(), 28);
                opcode.addImm(size_op.size(), 22);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              } else {
                var size_op = elementTypeToSizeOp(
                    op_data.element_vec_type, sop.regType, sop.elementType);
                if (!size_op.isValid()) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var element_index = _u32(o2.elementIndex);
                final lmh = LMHImm();

                if (!encodeLmh(size_op.size(), element_index, lmh)) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                if (o2.id > lmh.max_rm_id) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                opcode.reset(_u32(op_data.element_op) << 10);
                opcode.addImm(size_op.q(), 30);
                opcode.addImm(size_op.size(), 22);
                opcode.addImm(lmh.lm, 20);
                opcode.addImm(lmh.h, 11);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVVVI;
          continue loop; // (after block)
        case _S.encISimdVVVI:
          {
            final op_data = iSimdVVVI[encodingIndex];

            if (isign4 == 2121 /* ENC_OPS4(Reg, Reg, Reg, Imm) */) {
              final sop = significantSimdOp(o0, o1, instFlags);
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, sop.regType, sop.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var imm_value = o3.imm;
              var imm_size = _u32(op_data.imm_size);

              if (op_data.imm64_has_one_bit_less != 0 && size_op.q() == 0)
                imm_size--;

              var immMax = _u32(1 << imm_size);
              if (imm_value >= immMax) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(op_data.opcode);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              opcode.addImm(imm_value, op_data.imm_shift);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVVVV;
          continue loop; // (after block)
        case _S.encISimdVVVV:
          {
            final op_data = iSimdVVVV[encodingIndex];

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              final sop = significantSimdOp(o0, o1, instFlags);
              if (!matchSignature(o0, o1, o2, o3, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, sop.regType, sop.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.opcode) << 10);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16_Ra10;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdVVVVx;
          continue loop; // (after block)
        case _S.encISimdVVVVx:
          {
            final op_data = iSimdVVVVx[encodingIndex];

            if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              if (o0.signature != op_data.op0_signature ||
                  o1.signature != op_data.op1_signature ||
                  o2.signature != op_data.op2_signature ||
                  o3.signature != op_data.op3_signature) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.opcode) << 10);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16_Ra10;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encISimdPair;
          continue loop; // (after block)
        case _S.encISimdPair:
          {
            final op_data = iSimdPair[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */ && op_data.opcode2 != 0) {
              if (o0.isVecD1() && o1.isVecD2()) {
                opcode.reset(_u32(op_data.opcode2) << 10);
                opcode.addImm(0x3, 22); // size.
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }
            }

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.op_type3, o0.regType, o0.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.opcode3) << 10);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdBicOrr;
          continue loop; // (after block)
        case _S.encSimdBicOrr:
          {
            final op_data = simdBicOrr[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op =
                  elementTypeToSizeOp(kVO_V_B, o0.regType, o0.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.register_op) << 10);
              opcode.addImm(size_op.q(), 30);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */ ||
                isign4 == 289 /* ENC_OPS3(Reg, Imm, Imm) */) {
              var size_op =
                  elementTypeToSizeOp(kVO_V_HS, o0.regType, o0.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o1.imm > 0xFFFFFFFF) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var imm = _u32(o1.immU32);
              var shift = _u32(0);
              var max_shift = _u32((8 << size_op.size()) - 8);

              if (o2.isImm()) {
                if (o2.predicate != _u32(_ShiftOp.kLSL)) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                if (imm > 0xFF || o2.imm > max_shift) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                shift = o2.immU32;
                if ((shift & 0x7) != 0) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
              } else if (imm != 0) {
                shift = _ctz(imm) & ~0x7;
                imm >>= shift;

                if (imm > 0xFF || shift > max_shift) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
              }

              var cmode = _u32(0x1 | ((shift ~/ 8) << 1));
              if (size_op.size() == 1) cmode |= _B(3);

              // The immediate value is split into ABC and DEFGH parts.
              var abc = _u32((imm >> 5) & 0x7);
              var defgh = _u32(imm & 0x1F);

              opcode.reset(_u32(op_data.immediate_op) << 10);
              opcode.addImm(size_op.q(), 30);
              opcode.addImm(abc, 16);
              opcode.addImm(cmode, 12);
              opcode.addImm(defgh, 5);
              {
                state = _S.EmitOp_Rd0;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdCmp;
          continue loop; // (after block)
        case _S.encSimdCmp:
          {
            final op_data = simdCmp[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */ &&
                op_data.register_op != 0) {
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, o0.regType, o0.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.register_op) << 10);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */ &&
                op_data.zero_op != 0) {
              if (!matchSignature(o0, o1, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o2.imm != 0) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, o0.regType, o0.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.zero_op) << 10);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdDot;
          continue loop; // (after block)
        case _S.encSimdDot:
          {
            final op_data = simdDot[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              var q = _u32(_diff(o0.regType, _RT.kVec64));
              var size = _u32(2);

              if (q > 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!o2.hasElementIndex()) {
                if ((op_data.vector_op == 0)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (o0.regType != o1.regType || o1.regType != o2.regType) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (_u32(o0.elementType) != op_data.ta ||
                    _u32(o1.elementType) != op_data.tb ||
                    _u32(o2.elementType) != op_data.tb) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                opcode.reset(_u32(op_data.vector_op) << 10);
                opcode.addImm(q, 30);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              } else {
                if ((op_data.element_op == 0)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (o0.regType != o1.regType || !o2.isVec128()) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                if (_u32(o0.elementType) != op_data.ta ||
                    _u32(o1.elementType) != op_data.tb ||
                    _u32(o2.elementType) != op_data.tElement) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var element_index = _u32(o2.elementIndex);
                final lmh = LMHImm();

                if (!encodeLmh(size, element_index, lmh)) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                if (o2.id > lmh.max_rm_id) {
                  state = _S.InvalidPhysId;
                  continue loop;
                }

                opcode.reset(_u32(op_data.element_op) << 10);
                opcode.addImm(q, 30);
                opcode.addImm(lmh.lm, 20);
                opcode.addImm(lmh.h, 11);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdDup;
          continue loop; // (after block)
        case _S.encSimdDup:
        case _S.SimdDup:
          {
            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              // Truth table of valid encodings of `Q:1|ElementType:3`
              var kValidEncodings = _B(_u32(_ET.kB) + 0) |
                  _B(_u32(_ET.kH) + 0) |
                  _B(_u32(_ET.kS) + 0) |
                  _B(_u32(_ET.kB) + 8) |
                  _B(_u32(_ET.kH) + 8) |
                  _B(_u32(_ET.kS) + 8) |
                  _B(_u32(_ET.kD) + 8);

              var q = _u32(_diff(o0.regType, _RT.kVec64));

              if (o1.isGp()) {
                // DUP - Vec (scalar|vector) <- GP register.
                //
                // NOTE: This is only scalar for `dup d, x` case, otherwise the value
                // would be duplicated across all vector elements (1, 2, 4, 8, or 16).
                var element_type = _u32(_u32(o0.elementType));
                if (q > 1 ||
                    !_bitTest(kValidEncodings, (q << 3) | element_type)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var lsb_index = _u32(element_type - 1);
                var imm5 = _u32(1 << lsb_index);

                opcode.reset(0x38003 << 10);
                opcode.addImm(q, 30);
                opcode.addImm(imm5, 16);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              if (!o1.isVec() || !o1.hasElementIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var dst_index = _u32(o1.elementIndex);
              if (!o0.hasElementType()) {
                // DUP - Vec (scalar) <- Vec[N].
                var lsb_index = _u32(_diff(o0.regType, _RT.kVec8));

                if (lsb_index != _diff(o1.elementType, _ET.kB) ||
                    lsb_index > 3) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var imm5 = _u32(((dst_index << 1) | 1) << lsb_index);
                if (imm5 > 31) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                opcode.reset(0x178001 << 10);
                opcode.addImm(imm5, 16);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              } else {
                // DUP - Vec (all) <- Vec[N].
                var element_type = _u32(_u32(o0.elementType));
                if (q > 1 ||
                    !_bitTest(kValidEncodings, (q << 3) | element_type)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var lsb_index = _u32(element_type - 1);
                var imm5 = _u32(((dst_index << 1) | 1) << lsb_index);

                if (imm5 > 31) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                opcode.reset(0x38001 << 10);
                opcode.addImm(q, 30);
                opcode.addImm(imm5, 16);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdIns;
          continue loop; // (after block)
        case _S.encSimdIns:
        case _S.SimdIns:
          {
            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */ && o0.isVec128()) {
              if (!o0.hasElementIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var element_type = _u32(_u32(o0.elementType));
              var dst_index = _u32(o0.elementIndex);
              var lsb_index = _u32(element_type - 1);

              var imm5 = _u32(((dst_index << 1) | 1) << lsb_index);
              if (imm5 > 31) {
                state = _S.InvalidElementIndex;
                continue loop;
              }

              if (o1.isGp()) {
                // INS - Vec[N] <- GP register.
                opcode.reset(0x138007 << 10);
                opcode.addImm(imm5, 16);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              } else if (o1.isVec128() && o1.hasElementIndex()) {
                // INS - Vec[N] <- Vec[M].
                if (o0.elementType != o1.elementType) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var src_index = _u32(o1.elementIndex);
                if (o0.regType != o1.regType) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                var imm4 = _u32(src_index << lsb_index);
                if (imm4 > 15) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                opcode.reset(0x1b8001 << 10);
                opcode.addImm(imm5, 16);
                opcode.addImm(imm4, 11);
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdMov;
          continue loop; // (after block)
        case _S.encSimdMov:
          {
            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              if (o0.isVec() && o1.isVec()) {
                // INS v.x[index], v.x[index].
                if (o0.hasElementIndex() && o1.hasElementIndex()) {
                  state = _S.SimdIns;
                  continue loop;
                }

                // DUP {b|h|s|d}, v.{b|h|s|d}[index].
                if (o1.hasElementIndex()) {
                  state = _S.SimdDup;
                  continue loop;
                }

                if (!checkSignature(o0, o1)) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                // ORR Vd, Vn, Vm
                var q = _u32(_diff(o0.regType, _RT.kVec64));
                if (q > 1) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }

                opcode.reset(0x3a807 << 10);
                opcode.addImm(q, 30);
                opcode.addReg(o1, 16); // Vn == Vm.
                {
                  state = _S.EmitOp_Rd0_Rn5;
                  continue loop;
                }
              }

              if (o0.isVec() && o1.isGp()) {
                // INS v.x[index], Rn.
                if (o0.hasElementIndex()) {
                  state = _S.SimdIns;
                  continue loop;
                }

                {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
              }

              if (o0.isGp() && o1.isVec()) {
                // UMOV Rd, V.{s|d}[index].
                encodingIndex = 1;
                {
                  state = _S.SimdUmov;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdMoviMvni;
          continue loop; // (after block)
        case _S.encSimdMoviMvni:
          {
            final op_data = simdMoviMvni[encodingIndex];

            if (isign4 == 33 /* ENC_OPS2(Reg, Imm) */ ||
                isign4 == 289 /* ENC_OPS3(Reg, Imm, Imm) */) {
              var size_op =
                  elementTypeToSizeOp(kVO_V_Any, o0.regType, o0.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var imm64 = o1.imm;
              var imm8 = _u32(0);
              var cmode = _u32(0);
              var inverted = _u32(op_data.inverted);
              var op = _u32(0);
              var shift = _u32(0);
              var shift_op = _u32(_u32(_ShiftOp.kLSL));

              if (size_op.size() == 3) {
                // The second immediate should not be present, however, we accept
                // an immediate value of zero as some user code may still pass it.
                if (o2.isImm() && o0.imm != 0) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }

                if (isByteMaskImm(imm64)) {
                  imm8 = encodeImm64ByteMaskToImm8(imm64);
                } else {
                  // Change from D to S and from 64-bit imm to 32-bit imm if this
                  // is not a byte-mask pattern.
                  if ((imm64 >>> 32) == (imm64 & 0xFFFFFFFF)) {
                    imm64 &= 0xFFFFFFFF;
                    size_op.decrementSize();
                  } else {
                    {
                      state = _S.InvalidImmediate;
                      continue loop;
                    }
                  }
                }
              }

              if (size_op.size() < 3) {
                if (imm64 < 0 || imm64 > 0xFFFFFFFF) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
                imm8 = _u32(imm64);

                if (size_op.size() == 2) {
                  if ((imm8 >> 16) == (imm8 & 0xFFFF)) {
                    imm8 >>= 16;
                    size_op.decrementSize();
                  }
                }

                if (size_op.size() == 1) {
                  if (imm8 > 0xFFFF) {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }

                  if ((imm8 >> 8) == (imm8 & 0xFF)) {
                    imm8 >>= 8;
                    size_op.decrementSize();
                  }
                }

                var max_shift = _u32((8 << size_op.size()) - 8);
                if (o2.isImm()) {
                  if (imm8 > 0xFF || o2.imm > max_shift) {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }

                  shift = o2.immU32;
                  shift_op = o2.predicate;
                } else if (imm8 != 0) {
                  shift = _ctz(imm8) & ~0x7;
                  imm8 >>= shift;

                  if (imm8 > 0xFF || shift > max_shift) {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }
                }

                if ((shift & 0x7) != 0) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
              }

              shift ~/= 8;

              switch (size_op.size()) {
                case 0:
                  if (shift_op != _u32(_ShiftOp.kLSL)) {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }

                  if (inverted != 0) {
                    imm8 = ~imm8 & 0xFF;
                  }

                  cmode = _B(3) | _B(2) | _B(1);
                  break;

                case 1:
                  if (shift_op != _u32(_ShiftOp.kLSL)) {
                    state = _S.InvalidImmediate;
                    continue loop;
                  }

                  cmode = _B(3) | (shift << 1);
                  op = inverted;
                  break;

                case 2:
                  if (shift_op == _u32(_ShiftOp.kLSL)) {
                    cmode = shift << 1;
                  } else if (shift_op == _u32(_ShiftOp.kMSL)) {
                    if (shift == 0 || shift > 2) {
                      state = _S.InvalidImmediate;
                      continue loop;
                    }
                    cmode = _B(3) | _B(2) | (shift - 1);
                  } else {
                    {
                      state = _S.InvalidImmediate;
                      continue loop;
                    }
                  }

                  op = inverted;
                  break;

                case 3:
                  if (inverted != 0) {
                    imm8 = ~imm8 & 0xFF;
                  }

                  op = 1;
                  cmode = _B(3) | _B(2) | _B(1);
                  break;
              }

              // The immediate value is split into ABC and DEFGH parts.
              var abc = _u32((imm8 >> 5) & 0x7);
              var defgh = _u32(imm8 & 0x1F);

              opcode.reset(_u32(op_data.opcode) << 10);
              opcode.addImm(size_op.q(), 30);
              opcode.addImm(op, 29);
              opcode.addImm(abc, 16);
              opcode.addImm(cmode, 12);
              opcode.addImm(defgh, 5);
              {
                state = _S.EmitOp_Rd0;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdShift;
          continue loop; // (after block)
        case _S.encSimdShift:
          {
            final op_data = simdShift[encodingIndex];

            final sop = significantSimdOp(o0, o1, instFlags);
            var size_op = elementTypeToSizeOp(
                op_data.vec_op_type, sop.regType, sop.elementType);

            if (!size_op.isValid()) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */ &&
                op_data.immediate_op != 0) {
              if (!matchSignature(o0, o1, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (o2.imm > 63) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              var lsb_shift = _u32(size_op.size() + 3);
              var lsb_mask = _u32((1 << lsb_shift) - 1);
              var imm = _u32(o2.immU32);

              // Some instructions use IMM and some X - IMM, so negate if required.
              if (op_data.inverted_imm != 0) {
                if (imm == 0 || imm > (1 << lsb_shift)) {
                  state = _S.InvalidImmediate;
                  continue loop;
                }
                imm = _neg(imm) & lsb_mask;
              }

              if (imm > lsb_mask) {
                state = _S.InvalidImmediate;
                continue loop;
              }
              imm |= (1 << lsb_shift);

              opcode.reset(_u32(op_data.immediate_op) << 10);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(imm, 16);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */ &&
                op_data.register_op != 0) {
              if (!matchSignature(o0, o1, o2, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.register_op) << 10);
              opcode.addImm(size_op.qs(), 30);
              opcode.addImm(size_op.scalar(), 28);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5_Rm16;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdShiftES;
          continue loop; // (after block)
        case _S.encSimdShiftES:
          {
            final op_data = simdShiftES[encodingIndex];

            if (isign4 == 265 /* ENC_OPS3(Reg, Reg, Imm) */) {
              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, o1.regType, o1.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!matchSignature(o0, o1, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // The immediate value must match the element size.
              var shift = o2.imm;
              var shift_op = _u32(o2.predicate);

              if (shift != (8 << size_op.size()) ||
                  shift_op != _u32(_ShiftOp.kLSL)) {
                state = _S.InvalidImmediate;
                continue loop;
              }

              opcode.reset(_u32(op_data.opcode) << 10);
              opcode.addImm(size_op.q(), 30);
              opcode.addImm(size_op.size(), 22);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdSm3tt;
          continue loop; // (after block)
        case _S.encSimdSm3tt:
          {
            final op_data = simdSm3tt[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */) {
              if (o0.isVecS4() &&
                  o1.isVecS4() &&
                  o2.isVecS4() &&
                  o2.hasElementIndex()) {
                var imm2 = _u32(o2.elementIndex);
                if (imm2 > 3) {
                  state = _S.InvalidElementIndex;
                  continue loop;
                }

                opcode.reset(_u32(op_data.opcode) << 10);
                opcode.addImm(imm2, 12);
                {
                  state = _S.EmitOp_Rd0_Rn5_Rm16;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdSmovUmov;
          continue loop; // (after block)
        case _S.encSimdSmovUmov:
        case _S.SimdUmov:
          {
            final op_data = simdSmovUmov[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */ &&
                o0.isGp() &&
                o1.isVec()) {
              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, o1.regType, o1.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!o1.hasElementIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var x = _u32(o0.isGp64());
              var gp_must_be_x =
                  _u32(_u32(size_op.size() >= 3 - op_data.is_signed));

              if (op_data.is_signed != 0) {
                if (gp_must_be_x != 0 && x == 0) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
              } else {
                if (x != gp_must_be_x) {
                  state = _S.InvalidInstruction;
                  continue loop;
                }
              }

              var element_index = _u32(o1.elementIndex);
              var max_element_index = _u32(15 >> size_op.size());

              if (element_index > max_element_index) {
                state = _S.InvalidElementIndex;
                continue loop;
              }

              var imm5 = _u32((1 | (element_index << 1)) << size_op.size());

              opcode.reset(_u32(op_data.opcode) << 10);
              opcode.addImm(x, 30);
              opcode.addImm(imm5, 16);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdSxtlUxtl;
          continue loop; // (after block)
        case _S.encSimdSxtlUxtl:
          {
            final op_data = simdSxtlUxtl[encodingIndex];

            if (isign4 == 9 /* ENC_OPS2(Reg, Reg) */) {
              var size_op = elementTypeToSizeOp(
                  op_data.vec_op_type, o1.regType, o1.elementType);
              if (!size_op.isValid()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!matchSignature(o0, o1, instFlags)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.opcode) << 10);
              opcode.addImm(size_op.q(), 30);
              opcode.addImm(1, size_op.size() + 19);
              {
                state = _S.EmitOp_Rd0_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdTblTbx;
          continue loop; // (after block)
        case _S.encSimdTblTbx:
          {
            final op_data = simdTblTbx[encodingIndex];

            if (isign4 == 73 /* ENC_OPS3(Reg, Reg, Reg) */ ||
                isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */) {
              // TBL/TBX <Vd>.<Ta>, { <Vn>.16B }, <Vm>.<Ta>
              // TBL/TBX <Vd>.<Ta>, { <Vn>.16B, <Vn+1>.16B }, <Vm>.<Ta>
              // TBL/TBX <Vd>.<Ta>, { <Vn>.16B, <Vn+1>.16B, <Vn+2>.16B }, <Vm>.<Ta>
              // TBL/TBX <Vd>.<Ta>, { <Vn>.16B, <Vn+1>.16B, <Vn+2>.16B, <Vn+3>.16B }, <Vm>.<Ta>
              opcode.reset(_u32(op_data.opcode) << 10);

              final o4 = opExt[4];
              final o5 = opExt[5];

              var q = _u32(_diff(o0.regType, _RT.kVec64));
              if (q > 1 || o0.hasElementIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!o1.isVecB16() || o1.hasElementIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              var len = _u32(
                  _u32(!o3.isNone()) + _u32(!o4.isNone()) + _u32(!o5.isNone()));
              opcode.addImm(q, 30);
              opcode.addImm(len, 13);

              switch (len) {
                case 0:
                  if (!checkSignature(o0, o2)) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o2.id > 31) {
                    state = _S.InvalidPhysId;
                    continue loop;
                  }

                  opcode.addReg(o2, 16);
                  {
                    state = _S.EmitOp_Rd0_Rn5;
                    continue loop;
                  }

                case 1:
                  if (!checkSignature(o0, o3)) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o3.id > 31) {
                    state = _S.InvalidPhysId;
                    continue loop;
                  }

                  opcode.addReg(o3, 16);
                  {
                    state = _S.EmitOp_Rd0_Rn5;
                    continue loop;
                  }

                case 2:
                  if (!checkSignature(o0, o4)) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o4.id > 31) {
                    state = _S.InvalidPhysId;
                    continue loop;
                  }

                  opcode.addReg(o4, 16);
                  {
                    state = _S.EmitOp_Rd0_Rn5;
                    continue loop;
                  }

                case 3:
                  if (!checkSignature(o0, o5)) {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }

                  if (o5.id > 31) {
                    state = _S.InvalidPhysId;
                    continue loop;
                  }

                  opcode.addReg(o5, 16);
                  {
                    state = _S.EmitOp_Rd0_Rn5;
                    continue loop;
                  }

                default:
                  // Should never happen.
                  {
                    state = _S.InvalidInstruction;
                    continue loop;
                  }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          // ------------------------------------------------------------------------
          // [Simd - Load / Store]
          // ------------------------------------------------------------------------

          state = _S.encSimdLdSt;
          continue loop; // (after block)
        case _S.encSimdLdSt:
          {
            final op_data = simdLdSt[encodingIndex];

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              final m = o1;
              rmRel = m;

              // Width  |       SZ |        XY | XSZ
              // -------+----------+-----------+-----
              // 8-bit  | size==00 | opc == 01 | 000
              // 16-bit | size==01 | opc == 01 | 001
              // 32-bit | size==10 | opc == 01 | 010
              // 64-bit | size==11 | opc == 01 | 011
              // 128-bit| size==00 | opc == 11 | 100
              var xsz = _u32(_diff(o0.regType, _RT.kVec8));
              if (xsz > 4 || o0.hasElementIndex()) {
                state = _S.InvalidRegType;
                continue loop;
              }

              if (!checkVecId(o0)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkMemBaseIndexRel(m)) {
                state = _S.InvalidAddress;
                continue loop;
              }

              var offset = m.offset;
              if (m.hasBaseReg()) {
                // [Base {Offset | Index}]
                if (m.hasIndex()) {
                  var opt = _u32(shiftOpToLdStOptMap((m.shiftOp)));
                  if (opt == 0xFF) {
                    state = _S.InvalidAddress;
                    continue loop;
                  }

                  var shift = _u32(m.shift);
                  var s = _u32((shift != 0));

                  if (s != 0 && shift != xsz) {
                    state = _S.InvalidAddressScale;
                    continue loop;
                  }

                  opcode.reset(_u32(op_data.register_op) << 21);
                  opcode.addImm(xsz & 3, 30);
                  opcode.addImm(xsz >> 2, 23);
                  opcode.addImm(opt, 13);
                  opcode.addImm(s, 12);
                  opcode.v |= _B(11);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp_MemBaseIndex_Rn5_Rm16;
                    continue loop;
                  }
                }

                // Makes it easier to work with the offset especially on 32-bit arch.
                if (!_isIntN(32, offset)) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }
                var offset32 = _i32(_i32(offset));

                if (m.isPreOrPost()) {
                  if (!_isIntN(9, offset32)) {
                    state = _S.InvalidDisplacement;
                    continue loop;
                  }

                  opcode.reset(_u32(op_data.pre_post_op) << 21);
                  opcode.addImm(xsz & 3, 30);
                  opcode.addImm(xsz >> 2, 23);
                  opcode.addImm(offset32 & 0x1FF, 12);
                  opcode.addImm(m.isPreIndex(), 11);
                  opcode.v |= _B(10);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp_MemBase_Rn5;
                    continue loop;
                  }
                } else {
                  var imm12 = _u32(_u32(offset32) >> xsz);

                  // If this instruction is not encodable with scaled unsigned offset, try unscaled signed offset.
                  if (!_isUintN(12, imm12) ||
                      (imm12 << xsz) != _u32(offset32)) {
                    instId = op_data.u_alt_inst_id;
                    instInfo = kA64UpInstInfo[instId];
                    encodingIndex = instInfo.encodingDataIndex;
                    {
                      state = _S.Case_SimdLdurStur;
                      continue loop;
                    }
                  }

                  opcode.reset(_u32(op_data.u_offset_op) << 22);
                  opcode.addImm(xsz & 3, 30);
                  opcode.addImm(xsz >> 2, 23);
                  opcode.addImm(imm12, 10);
                  opcode.addReg(o0, 0);
                  {
                    state = _S.EmitOp_MemBase_Rn5;
                    continue loop;
                  }
                }
              } else {
                if ((op_data.literal_op == 0)) {
                  state = _S.InvalidAddress;
                  continue loop;
                }

                if (xsz < 2) {
                  state = _S.InvalidRegType;
                  continue loop;
                }

                var opc = _u32(xsz - 2);
                opcode.reset(_u32(op_data.literal_op) << 24);
                opcode.addImm(opc, 30);
                opcode.addReg(o0, 0);
                offsetFormat.resetToImmValue(
                    A64OffsetType.kSignedOffset, 4, 5, 19, 2);
                {
                  state = _S.EmitOp_Rel;
                  continue loop;
                }
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdLdpStp;
          continue loop; // (after block)
        case _S.encSimdLdpStp:
          {
            final op_data = simdLdpStp[encodingIndex];

            if (isign4 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
              final m = o2;
              rmRel = m;

              var opc = _u32(_diff(o0.regType, _RT.kVec32));
              if (opc > 2 || o0.hasElementTypeOrIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkVecId(o0, o1)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (m.baseType != _RT.kGp64 || m.hasIndex()) {
                state = _S.InvalidAddress;
                continue loop;
              }

              if (m.isOffset64bit()) {
                state = _S.InvalidDisplacement;
                continue loop;
              }

              var offset_shift = _u32(2 + opc);
              var offset32 = _i32(m.offsetLo32 >> offset_shift);

              // Make sure we didn't lose bits by applying the mandatory offset shift.
              if (_shl(offset32, offset_shift) != m.offsetLo32) {
                state = _S.InvalidDisplacement;
                continue loop;
              }

              // Offset is encoded as a 7-bit immediate.
              if (!_isIntN(7, offset32)) {
                state = _S.InvalidDisplacement;
                continue loop;
              }

              if (m.isPreOrPost() && offset32 != 0) {
                if ((op_data.pre_post_op == 0)) {
                  state = _S.InvalidAddress;
                  continue loop;
                }

                opcode.reset(_u32(op_data.pre_post_op) << 22);
                opcode.addImm(m.isPreIndex(), 24);
              } else {
                opcode.reset(_u32(op_data.offset_op) << 22);
              }

              opcode.addImm(opc, 30);
              opcode.addImm(offset32 & 0x7F, 15);
              opcode.addReg(o1, 10);
              opcode.addReg(o0, 0);
              {
                state = _S.EmitOp_MemBase_Rn5;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdLdurStur;
          continue loop; // (after block)
        case _S.encSimdLdurStur:
        case _S.Case_SimdLdurStur:
          {
            final op_data = simdLdurStur[encodingIndex];

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              final m = o1;
              rmRel = m;

              var sz = _u32(_diff(o0.regType, _RT.kVec8));
              if (sz > 4 || o0.hasElementTypeOrIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkVecId(o0)) {
                state = _S.InvalidPhysId;
                continue loop;
              }

              if (!checkMemBaseIndexRel(m)) {
                state = _S.InvalidAddress;
                continue loop;
              }

              if (m.hasBaseReg() && !m.hasIndex() && !m.isPreOrPost()) {
                if (m.isOffset64bit()) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                var offset32 = _i32(m.offsetLo32);
                if (!_isIntN(9, offset32)) {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }

                opcode.reset(_u32(op_data.opcode) << 10);
                opcode.addImm(sz & 3, 30);
                opcode.addImm(sz >> 2, 23);
                opcode.addImm(offset32 & 0x1FF, 12);
                opcode.addReg(o0, 0);
                {
                  state = _S.EmitOp_MemBase_Rn5;
                  continue loop;
                }
              }

              {
                state = _S.InvalidAddress;
                continue loop;
              }
            }

            {
              state = _S.InvalidInstruction;
              continue loop;
            }
          }

          state = _S.encSimdLdNStN;
          continue loop; // (after block)
        case _S.encSimdLdNStN:
          {
            final op_data = simdLdNStN[encodingIndex];
            final o4 = opExt[4];

            var n = _u32(1);

            if (isign4 == 17 /* ENC_OPS2(Reg, Mem) */) {
              if (op_data.n != 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              rmRel = o1;
            } else if (isign4 == 137 /* ENC_OPS3(Reg, Reg, Mem) */) {
              if (op_data.n != 1 && op_data.n != 2) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1) || !checkConsecutive(o0, o1)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              n = 2;
              rmRel = o2;
            } else if (isign4 == 1097 /* ENC_OPS4(Reg, Reg, Reg, Mem) */ &&
                o4.isNone()) {
              if (op_data.n != 1 && op_data.n != 3) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1, o2) ||
                  !checkConsecutive(o0, o1, o2)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              n = 3;
              rmRel = o3;
            } else if (isign4 == 585 /* ENC_OPS4(Reg, Reg, Reg, Reg) */ &&
                o4.isMem()) {
              if (op_data.n != 1 && op_data.n != 4) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (!checkSignature(o0, o1, o2, o3) ||
                  !checkConsecutive(o0, o1, o2, o3)) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              n = 4;
              rmRel = o4;
            } else {
              {
                state = _S.InvalidInstruction;
                continue loop;
              }
            }

            // We will use `v` and `m` from now as those are relevant for encoding.
            final v = o0;
            final m = rmRel!;

            var q = _u32(0);
            var rm = _u32(0);
            var rn = _u32(m.baseId);
            var sz = _u32(_diff(v.elementType, _ET.kB));
            var opc_s_size = _u32(sz);
            var offset_possibility = _u32(0);

            if (sz > 3) {
              state = _S.InvalidInstruction;
              continue loop;
            }

            if (m.baseType != _RT.kGp64) {
              state = _S.InvalidAddress;
              continue loop;
            }

            // Rn cannot be ZR, but can be SP.
            if (rn > 30 && rn != _kIdSp) {
              state = _S.InvalidAddress;
              continue loop;
            }

            rn &= 31;

            if (op_data.replicate != 0) {
              if (n != op_data.n) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // Replicates to the whole register, element index cannot be used.
              if (v.hasElementIndex()) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              q = _diff(v.regType, _RT.kVec64);
              if (q > 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              opcode.reset(_u32(op_data.single_op) << 10);
              offset_possibility = (1 << sz) * n;
            } else if (v.hasElementIndex()) {
              if (n != op_data.n) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              // LDx/STx (single structure).
              final opc_s_size_by_sz_table = [
                0x0 << 3,
                0x2 << 3,
                0x4 << 3,
                (0x4 << 3) | 1
              ];

              opcode.reset(_u32(op_data.single_op) << 10);
              opc_s_size = opc_s_size_by_sz_table[sz];
              offset_possibility = (1 << sz) * op_data.n;

              var element_index = _u32(v.elementIndex);
              var max_element_index = _u32(15 >> sz);

              if (element_index > max_element_index) {
                state = _S.InvalidElementIndex;
                continue loop;
              }

              element_index <<= sz;
              q = element_index >> 3;
              opc_s_size |= element_index & 0x7;
            } else {
              // LDx/STx (multiple structures).
              final opc_s_size_by_n_table = [
                0,
                0x7 << 2,
                0xA << 2,
                0x6 << 2,
                0x2 << 2
              ];

              q = _diff(v.regType, _RT.kVec64);
              if (q > 1) {
                state = _S.InvalidInstruction;
                continue loop;
              }

              if (op_data.n == 1) opc_s_size |= opc_s_size_by_n_table[n];

              opcode.reset(_u32(op_data.multiple_op) << 10);
              offset_possibility = (8 << q) * n;
            }

            if (m.hasIndex()) {
              if (m.hasOffset() || !m.isPostIndex()) {
                state = _S.InvalidAddress;
                continue loop;
              }

              rm = m.indexId;
              if (rm > 30) {
                state = _S.InvalidAddress;
                continue loop;
              }

              // Bit 23 - PostIndex.
              opcode.v |= _B(23);
            } else {
              if (m.hasOffset()) {
                if (m.offset != _i32(offset_possibility) || !m.isPostIndex()) {
                  state = _S.InvalidAddress;
                  continue loop;
                }
                rm = 31;

                // Bit 23 - PostIndex.
                opcode.v |= _B(23);
              }
            }

            opcode.addImm(q, 30);
            opcode.addImm(rm, 16);
            opcode.addImm(opc_s_size, 10);
            opcode.addImm(rn, 5);
            {
              state = _S.EmitOp_Rd0;
              continue loop;
            }
          }

          // (upstream main switch default)
          {
            state = _S.InvalidInstruction;
            continue loop;
          }

          {
            state = _S.InvalidInstruction;
            continue loop;
          }

        // --------------------------------------------------------------------------
        // [EmitGp - Single]
        // --------------------------------------------------------------------------

        case _S.EmitOp_Rd0:
          if (!checkValidRegs(o0)) {
            state = _S.InvalidPhysId;
            continue loop;
          }

          opcode.addReg(o0, 0);
          {
            state = _S.EmitOp;
            continue loop;
          }

        case _S.EmitOp_Rn5:
          if (!checkValidRegs(o0)) {
            state = _S.InvalidPhysId;
            continue loop;
          }

          opcode.addReg(o0, 5);
          {
            state = _S.EmitOp;
            continue loop;
          }

        case _S.EmitOp_Rn5_Rm16:
          if (!checkValidRegs(o0, o1)) {
            state = _S.InvalidPhysId;
            continue loop;
          }

          opcode.addReg(o0, 5);
          opcode.addReg(o1, 16);
          {
            state = _S.EmitOp;
            continue loop;
          }

        case _S.EmitOp_Rd0_Rn5:
          if (!checkValidRegs(o0, o1)) {
            state = _S.InvalidPhysId;
            continue loop;
          }

          opcode.addReg(o0, 0);
          opcode.addReg(o1, 5);
          {
            state = _S.EmitOp;
            continue loop;
          }

        case _S.EmitOp_Rd0_Rn5_Rm16_Ra10:
          if (!checkValidRegs(o0, o1, o2, o3)) {
            state = _S.InvalidPhysId;
            continue loop;
          }

          opcode.addReg(o0, 0);
          opcode.addReg(o1, 5);
          opcode.addReg(o2, 16);
          opcode.addReg(o3, 10);
          {
            state = _S.EmitOp;
            continue loop;
          }

        case _S.EmitOp_Rd0_Rn5_Rm16:
          if (!checkValidRegs(o0, o1, o3)) {
            state = _S.InvalidPhysId;
            continue loop;
          }

          opcode.addReg(o0, 0);
          opcode.addReg(o1, 5);
          opcode.addReg(o2, 16);
          {
            state = _S.EmitOp;
            continue loop;
          }

        // --------------------------------------------------------------------------
        // [EmitGp - Multiple]
        // --------------------------------------------------------------------------

        case _S.EmitOp_Multiple:
          {
            // ASMJIT_ASSERT(multipleOpCount > 0);

            for (var i = 0; i < multipleOpCount; i++) {
              _w.emit32uLe(multipleOpData[i]);
            }

            {
              state = _S.EmitDone;
              continue loop;
            }
          }

          // --------------------------------------------------------------------------
          // [EmitGp - Memory]
          // --------------------------------------------------------------------------

          state = _S.EmitOp_MemBase_Rn5;
          continue loop; // (after block)
        case _S.EmitOp_MemBase_Rn5:
          if (!checkMemBase(rmRel!)) {
            {
              state = _S.InvalidAddress;
              continue loop;
            }
          }

          opcode.addReg(rmRel!.baseId, 5);
          {
            state = _S.EmitOp;
            continue loop;
          }

        case _S.EmitOp_MemBaseNoImm_Rn5:
          if (!checkMemBase(rmRel!) || rmRel!.hasIndex()) {
            {
              state = _S.InvalidAddress;
              continue loop;
            }
          }

          if (rmRel!.hasOffset()) {
            {
              state = _S.InvalidDisplacement;
              continue loop;
            }
          }

          opcode.addReg(rmRel!.baseId, 5);
          {
            state = _S.EmitOp;
            continue loop;
          }

        case _S.EmitOp_MemBaseIndex_Rn5_Rm16:
          if (!rmRel!.hasBaseReg()) {
            {
              state = _S.InvalidAddress;
              continue loop;
            }
          }

          if (rmRel!.indexId > 30 && rmRel!.indexId != _kIdZr) {
            {
              state = _S.InvalidPhysId;
              continue loop;
            }
          }

          opcode.addReg(rmRel!.indexId, 16);
          opcode.addReg(rmRel!.baseId, 5);
          {
            state = _S.EmitOp;
            continue loop;
          }

        // --------------------------------------------------------------------------
        // [EmitOp - PC Relative]
        // --------------------------------------------------------------------------

        case _S.EmitOp_Rel:
          {
            if (rmRel!.isLabel() || rmRel!.isMem()) {
              final label = rmRel!.label!;
              final labelOffset = rmRel!.isLabel() ? 0 : rmRel!.offset;

              final bound = code.getLabelOffset(label);
              if (bound != null) {
                // Label bound to the current section.
                offsetValue = bound - _w.cursor + labelOffset;
                {
                  state = _S.EmitOp_DispImm;
                  continue loop;
                }
              } else {
                // Create a fixup referencing an non-bound label.
                _addFixup(label, _w.cursor, labelOffset, offsetFormat, instId);
                {
                  state = _S.EmitOp;
                  continue loop;
                }
              }
            }
          }

          if (rmRel!.isImm()) {
            // Upstream records an AbsToRel relocation (the port's CodeHolder has no
            // base address); not supported yet.
            {
              state = _S.InvalidDisplacement;
              continue loop;
            }
          }

          {
            state = _S.InvalidInstruction;
            continue loop;
          }

        case _S.EmitOp_DispImm:
          {
            if ((offsetValue & _lsbMask(offsetFormat.immDiscardLsb())) != 0) {
              {
                state = _S.InvalidDisplacement;
                continue loop;
              }
            }

            var disp_imm64 = (offsetValue) >> offsetFormat.immDiscardLsb();
            if (!isEncodableOffset64(disp_imm64, offsetFormat.immBitCount())) {
              {
                state = _S.InvalidDisplacement;
                continue loop;
              }
            }

            var disp_imm32 =
                _u32(_u32(disp_imm64 & _lsbMask(offsetFormat.immBitCount())));
            switch (offsetFormat.type()) {
              case A64OffsetType.kSignedOffset:
                {
                  opcode.addImm(disp_imm32, offsetFormat.immBitShift());
                  {
                    state = _S.EmitOp;
                    continue loop;
                  }
                }

              case A64OffsetType.kAArch64_ADR:
              case A64OffsetType.kAArch64_ADRP:
                {
                  var imm_lo = _u32(disp_imm32 & 0x3);
                  var imm_hi = _u32(disp_imm32 >> 2);
                  opcode.addImm(imm_lo, 29);
                  opcode.addImm(imm_hi, 5);
                  {
                    state = _S.EmitOp;
                    continue loop;
                  }
                }

              default:
                {
                  state = _S.InvalidDisplacement;
                  continue loop;
                }
            }
          }

          // --------------------------------------------------------------------------
          // [EmitOp - Opcode]
          // --------------------------------------------------------------------------

          state = _S.EmitOp;
          continue loop; // (after block)
        case _S.EmitOp:
          _w.emit32uLe(opcode.get());
          {
            state = _S.EmitDone;
            continue loop;
          }

          // --------------------------------------------------------------------------
          // [Done]
          // --------------------------------------------------------------------------

          {
            state = _S.EmitDone;
            continue loop;
          }
        case _S.EmitDone:
          return;

        case _S.OutOfMemory:
          _fail('OutOfMemory', instId);
        case _S.InvalidAddress:
          _fail('InvalidAddress', instId);
        case _S.InvalidAddressScale:
          _fail('InvalidAddressScale', instId);
        case _S.InvalidDisplacement:
          _fail('InvalidDisplacement', instId);
        case _S.InvalidElementIndex:
          _fail('InvalidElementIndex', instId);
        case _S.InvalidLabel:
          _fail('InvalidLabel', instId);
        case _S.InvalidImmediate:
          _fail('InvalidImmediate', instId);
        case _S.InvalidInstruction:
          _fail('InvalidInstruction', instId);
        case _S.InvalidPhysId:
          _fail('InvalidPhysId', instId);
        case _S.InvalidRegType:
          _fail('InvalidRegType', instId);
        case _S.Failed:
          _fail('Failed', instId);
      }
    }
  }

  /// `CodeHolder::new_fixup()`: the port's relocation kinds for the AArch64
  /// offset formats (the fixup is applied when [label] is bound).
  void _addFixup(Label label, int at, int addend, OffsetFormat f, int instId) {
    final kind = switch ((f.type(), f.immBitShift(), f.immBitCount())) {
      (A64OffsetType.kSignedOffset, 0, 26) => RelocKind.arm64Branch26,
      (A64OffsetType.kSignedOffset, 5, 19) => RelocKind.arm64Branch19,
      (A64OffsetType.kSignedOffset, 5, 14) => RelocKind.arm64Branch14,
      (A64OffsetType.kAArch64_ADR, _, _) => RelocKind.arm64Adr21,
      _ => null,
    };
    if (kind == null) _fail('InvalidDisplacement', instId);
    code.addReloc(
        Reloc(kind: kind, atOffset: at, target: label, addend: addend));
  }

  Never _fail(String error, int instId) {
    final name = instId > 0 && instId < kA64UpInstNames.length
        ? kA64UpInstNames[instId]
        : '#$instId';
    throw A64EmitError(error, name);
  }
}

/// An instruction the encoder cannot encode (upstream error name).
class A64EmitError extends ArgumentError {
  final String error;
  final String instruction;
  A64EmitError(this.error, this.instruction)
      : super('a64 $instruction: $error');
}

/// States of [A64Emitter._emit]: the cases and labels of upstream `_emit()`.
enum _S {
  encBaseOp,
  encBaseOpX16,
  encBaseOpImm,
  encBaseR,
  encBaseRR,
  encBaseRRR,
  encBaseRRRR,
  encBaseRRII,
  encBaseMov,
  encBaseMovKNZ,
  encBaseAdr,
  encBaseAddSub,
  encBaseLogical,
  encBaseCmpCmn,
  encBaseMvnNeg,
  encBaseTst,
  encBaseBfc,
  encBaseBfi,
  encBaseBfm,
  encBaseBfx,
  encBaseExtend,
  encBaseExtract,
  encBaseRev,
  encBaseShift,
  encBaseCCmp,
  encBaseCInc,
  encBaseCSel,
  encBaseCSet,
  encBaseMinMax,
  encBaseAtDcIcTlbi,
  encBaseMrs,
  encBaseMsr,
  encBaseSys,
  encBaseBranchReg,
  encBaseBranchRel,
  encBaseBranchCmp,
  encBaseBranchTst,
  encBasePrfm,
  encBaseLdSt,
  encBaseLdpStp,
  encBaseStx,
  encBaseLdxp,
  encBaseStxp,
  encBaseRM_NoImm,
  encBaseRM_SImm9,
  Case_BaseLdurStur,
  encBaseRM_SImm10,
  encBaseAtomicOp,
  encBaseAtomicSt,
  encBaseAtomicCasp,
  encFSimdSV,
  encFSimdVV,
  encFSimdVVV,
  encFSimdVVVe,
  encFSimdVVVV,
  encSimdFcadd,
  encSimdFccmpFccmpe,
  encSimdFcm,
  encSimdFcmla,
  encSimdFcmpFcmpe,
  encSimdFcsel,
  encSimdFcvt,
  encSimdFcvtLN,
  encSimdFcvtSV,
  encSimdFmlal,
  encSimdFmov,
  encFSimdPair,
  encISimdSV,
  encISimdVV,
  encISimdVVx,
  encISimdVVV,
  encISimdVVVx,
  encISimdWWV,
  encISimdVVVe,
  encISimdVVVI,
  encISimdVVVV,
  encISimdVVVVx,
  encISimdPair,
  encSimdBicOrr,
  encSimdCmp,
  encSimdDot,
  encSimdDup,
  SimdDup,
  encSimdIns,
  SimdIns,
  encSimdMov,
  encSimdMoviMvni,
  encSimdShift,
  encSimdShiftES,
  encSimdSm3tt,
  encSimdSmovUmov,
  SimdUmov,
  encSimdSxtlUxtl,
  encSimdTblTbx,
  encSimdLdSt,
  encSimdLdpStp,
  encSimdLdurStur,
  Case_SimdLdurStur,
  encSimdLdNStN,
  EmitOp_Rd0,
  EmitOp_Rn5,
  EmitOp_Rn5_Rm16,
  EmitOp_Rd0_Rn5,
  EmitOp_Rd0_Rn5_Rm16_Ra10,
  EmitOp_Rd0_Rn5_Rm16,
  EmitOp_Multiple,
  EmitOp_MemBase_Rn5,
  EmitOp_MemBaseNoImm_Rn5,
  EmitOp_MemBaseIndex_Rn5_Rm16,
  EmitOp_Rel,
  EmitOp_DispImm,
  EmitOp,
  EmitDone,
  OutOfMemory,
  InvalidAddress,
  InvalidAddressScale,
  InvalidDisplacement,
  InvalidElementIndex,
  InvalidLabel,
  InvalidImmediate,
  InvalidInstruction,
  InvalidPhysId,
  InvalidRegType,
  Failed,
}

/// Entry state of each [A64Encoding].
const _encodingStates = [
  _S.InvalidInstruction /* None */,
  _S.encBaseAddSub,
  _S.encBaseAdr,
  _S.encBaseAtDcIcTlbi,
  _S.encBaseAtomicCasp,
  _S.encBaseAtomicOp,
  _S.encBaseAtomicSt,
  _S.encBaseBfc,
  _S.encBaseBfi,
  _S.encBaseBfm,
  _S.encBaseBfx,
  _S.encBaseBranchCmp,
  _S.encBaseBranchReg,
  _S.encBaseBranchRel,
  _S.encBaseBranchTst,
  _S.encBaseCCmp,
  _S.encBaseCInc,
  _S.encBaseCSel,
  _S.encBaseCSet,
  _S.encBaseCmpCmn,
  _S.encBaseExtend,
  _S.encBaseExtract,
  _S.encBaseLdSt,
  _S.encBaseLdpStp,
  _S.encBaseLdxp,
  _S.encBaseLogical,
  _S.encBaseMinMax,
  _S.encBaseMov,
  _S.encBaseMovKNZ,
  _S.encBaseMrs,
  _S.encBaseMsr,
  _S.encBaseMvnNeg,
  _S.encBaseOp,
  _S.encBaseOpImm,
  _S.encBaseOpX16,
  _S.encBasePrfm,
  _S.encBaseR,
  _S.encBaseRM_NoImm,
  _S.encBaseRM_SImm10,
  _S.encBaseRM_SImm9,
  _S.encBaseRR,
  _S.encBaseRRII,
  _S.encBaseRRR,
  _S.encBaseRRRR,
  _S.encBaseRev,
  _S.encBaseShift,
  _S.encBaseStx,
  _S.encBaseStxp,
  _S.encBaseSys,
  _S.encBaseTst,
  _S.encFSimdPair,
  _S.encFSimdSV,
  _S.encFSimdVV,
  _S.encFSimdVVV,
  _S.encFSimdVVVV,
  _S.encFSimdVVVe,
  _S.encISimdPair,
  _S.encISimdSV,
  _S.encISimdVV,
  _S.encISimdVVV,
  _S.encISimdVVVI,
  _S.encISimdVVVV,
  _S.encISimdVVVVx,
  _S.encISimdVVVe,
  _S.encISimdVVVx,
  _S.encISimdVVx,
  _S.encISimdWWV,
  _S.encSimdBicOrr,
  _S.encSimdCmp,
  _S.encSimdDot,
  _S.encSimdDup,
  _S.encSimdFcadd,
  _S.encSimdFccmpFccmpe,
  _S.encSimdFcm,
  _S.encSimdFcmla,
  _S.encSimdFcmpFcmpe,
  _S.encSimdFcsel,
  _S.encSimdFcvt,
  _S.encSimdFcvtLN,
  _S.encSimdFcvtSV,
  _S.encSimdFmlal,
  _S.encSimdFmov,
  _S.encSimdIns,
  _S.encSimdLdNStN,
  _S.encSimdLdSt,
  _S.encSimdLdpStp,
  _S.encSimdLdurStur,
  _S.encSimdMov,
  _S.encSimdMoviMvni,
  _S.encSimdShift,
  _S.encSimdShiftES,
  _S.encSimdSm3tt,
  _S.encSimdSmovUmov,
  _S.encSimdSxtlUxtl,
  _S.encSimdTblTbx,
];
