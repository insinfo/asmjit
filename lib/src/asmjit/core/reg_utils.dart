import 'globals.dart';
import 'operand.dart' show OperandRegType, RegGroup;
import 'reg_type.dart';
import 'type.dart';

/// Mask of physical registers.
typedef RegMask = int;

/// Minimal Reg helper matching AsmJit's `Reg::kIdBad`.
class Reg {
  static const int kIdBad = 0xFF;

  final RegType regType;
  final int id;

  const Reg({this.regType = RegType.none, this.id = kIdBad});

  bool get isNone => id == kIdBad;

  Reg copyWith({RegType? regType, int? id}) =>
      Reg(regType: regType ?? this.regType, id: id ?? this.id);
}

/// Simplified operand signature that only tracks the register group.
class OperandSignature {
  final RegGroup _regGroup;
  final bool _isValid;

  const OperandSignature(this._regGroup, {bool isValid = true})
      : _isValid = isValid;

  /// Returns the register group described by this signature.
  RegGroup regGroup() => _regGroup;

  /// Whether this signature contains a valid group.
  bool get isValid => _isValid;

  /// Invalid signature (no register group).
  static const OperandSignature invalid =
      OperandSignature(RegGroup.extra, isValid: false);
}

/// Register utility helpers.
class RegUtils {
  static RegGroup groupOf(RegType type) {
    switch (type) {
      case RegType.gp8Lo:
      case RegType.gp8Hi:
      case RegType.gp16:
      case RegType.gp32:
      case RegType.gp64:
        return RegGroup.gp;
      case RegType.vec128:
      case RegType.vec256:
      case RegType.vec512:
        return RegGroup.vec;
      case RegType.mask:
        return RegGroup.mask;
      default:
        return RegGroup.extra;
    }
  }

  static TypeId typeIdOf(RegType type) {
    switch (type) {
      case RegType.gp8Lo:
      case RegType.gp8Hi:
        return TypeId.uint8;
      case RegType.gp16:
        return TypeId.uint16;
      case RegType.gp32:
        return TypeId.uint32;
      case RegType.gp64:
        return TypeId.uint64;
      case RegType.vec128:
      case RegType.vec256:
      case RegType.vec512:
        return TypeId.float64;
      case RegType.mask:
        return TypeId.mask64;
      case RegType.x86Mm:
        return TypeId.mmx64;
      case RegType.x86St:
        return TypeId.float80;
      default:
        return TypeId.void_;
    }
  }

  static OperandRegType operandRegTypeFromGroup(RegGroup group) {
    switch (group) {
      case RegGroup.gp:
        return OperandRegType.gp;
      case RegGroup.vec:
        return OperandRegType.vec;
      case RegGroup.mask:
        return OperandRegType.mask;
      default:
        return OperandRegType.none;
    }
  }
}

/// Enumerates register groups from zero up to [uptoIndex], inclusive.
Iterable<RegGroup> enumerateRegGroups(
    [int uptoIndex = Globals.numVirtGroups - 1]) sync* {
  for (final group in RegGroup.values) {
    if (group.index > uptoIndex) break;
    yield group;
  }
}
