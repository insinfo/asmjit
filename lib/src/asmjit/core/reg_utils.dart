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

/// Operand Signature.
///
/// Encodes operand type, register type, element type, and other metadata in a single integer.
class OperandSignature {
  final int value;

  const OperandSignature(this.value);

  // Constants
  static const int kSizeShift = 24;
  static const int kSizeMask =
      0xFF; // 8 bits for size? C++ uses 8 bits for size (1..255)

  // Helpers
  static OperandSignature fromOpType(int type) {
    return OperandSignature((type & kOpTypeMask) << kOpTypeShift);
  }

  static OperandSignature fromRegTypeAndGroup(RegType type, RegGroup group) {
    return OperandSignature(((type.index & kRegTypeMask) << kRegTypeShift) |
        ((group.index & kRegGroupMask) << kRegGroupShift));
  }

  static OperandSignature fromSize(int size) {
    return OperandSignature((size & kSizeMask) << kSizeShift);
  }

  OperandSignature operator |(OperandSignature other) {
    return OperandSignature(value | other.value);
  }

  /// Constants for bit layout.
  static const int kOpTypeShift = 0;
  static const int kOpTypeMask = 0x7;

  static const int kRegTypeShift = 3;
  static const int kRegTypeMask = 0x1F;

  static const int kRegGroupShift = 8;
  static const int kRegGroupMask = 0xF;

  static const int kMemBaseTypeShift = 3;
  static const int kMemBaseTypeMask = 0x1F;

  static const int kMemIndexTypeShift = 8;
  static const int kMemIndexTypeMask = 0x1F;

  static const int kMemRegHomeFlag = 0x20000000; // Example bit

  // Reg Groups (Consolidated here for const usage)
  static const int kGroupGp = 0;
  static const int kGroupVec = 1;
  static const int kGroupMask = 2;
  static const int kGroupMm = 3;
  static const int kGroupExtra = 4; // Or 15?
  // Enum RegGroup logic: gp=0, vec=1, mask=2, x86Mm=3, extra=4.

  // Op Types
  static const int kOpNone = 0;
  static const int kOpReg = 1;
  static const int kOpMem = 2;

  static const int kOpImm = 3;
  static const int kOpLabel = 4;

  // Size
  int get size => (value >> kSizeShift) & kSizeMask;

  bool get isValid => value != 0;

  int get opType => (value >> kOpTypeShift) & kOpTypeMask;
  int get regType => (value >> kRegTypeShift) & kRegTypeMask;
  int get regGroup => (value >> kRegGroupShift) & kRegGroupMask;

  OperandSignature withOpType(int type) {
    return OperandSignature((value & ~(kOpTypeMask << kOpTypeShift)) |
        ((type & kOpTypeMask) << kOpTypeShift));
  }

  OperandSignature withRegType(RegType type) {
    int typeId = type.index; // Assuming RegType is enum
    return OperandSignature((value & ~(kRegTypeMask << kRegTypeShift)) |
        ((typeId & kRegTypeMask) << kRegTypeShift));
  }

  OperandSignature withRegGroup(RegGroup group) {
    int groupId = group.index;
    return OperandSignature((value & ~(kRegGroupMask << kRegGroupShift)) |
        ((groupId & kRegGroupMask) << kRegGroupShift));
  }

  OperandSignature withMemBaseType(RegType type) {
    int typeId = type.index;
    return OperandSignature((value & ~(kMemBaseTypeMask << kMemBaseTypeShift)) |
        ((typeId & kMemBaseTypeMask) << kMemBaseTypeShift));
  }

  OperandSignature withVirtId(int id) {
    // Usually VirtID is stored in the ID field of the operand, not strictly in signature.
    // But if we encode it here for some reason:
    // For now just return this as typically ID is separate in BaseReg.
    // If C++ uses it in signature, we need more bits.
    // Assuming signature is 32-bits, we have limited space.
    // BaseReg has `_id`. Metadata `VirtReg` has `_id`.
    // We typically don't store ID in signature.
    return this;
  }

  OperandSignature withBits(int bits) {
    return OperandSignature(value | bits);
  }

  static const OperandSignature invalid = OperandSignature(0);
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
