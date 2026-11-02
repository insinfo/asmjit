/// AsmJit instruction API: read/write information of instructions.
///
/// Port of `OpRWFlags`, `OpRWInfo`, `InstRWFlags`, `InstRWInfo`,
/// `InstControlFlow` and `InstSameRegHint` (asmjit/core/inst.h). The x86
/// query is `x86QueryRWInfo()` (x86/x86_rw_info.dart).

/// `OpRWFlags`.
abstract final class OpRWFlags {
  static const int kNone = 0;
  static const int kRead = 0x00000001;
  static const int kWrite = 0x00000002;
  static const int kRW = 0x00000003;
  static const int kRegMem = 0x00000004;
  static const int kConsecutive = 0x00000008;
  static const int kZExt = 0x00000010;
  static const int kUnique = 0x00000080;
  static const int kRegPhysId = 0x00000100;
  static const int kMemPhysId = 0x00000200;
  static const int kMemFake = 0x00000400;
  static const int kMemBaseRead = 0x00001000;
  static const int kMemBaseWrite = 0x00002000;
  static const int kMemBaseRW = 0x00003000;
  static const int kMemIndexRead = 0x00004000;
  static const int kMemIndexWrite = 0x00008000;
  static const int kMemIndexRW = 0x0000C000;
  static const int kMemBasePreModify = 0x00010000;
  static const int kMemBasePostModify = 0x00020000;
}

/// `InstRWFlags`.
abstract final class InstRWFlags {
  static const int kNone = 0;
  static const int kMovOp = 0x00000001;
}

/// `InstControlFlow`.
abstract final class InstControlFlow {
  static const int kRegular = 0;
  static const int kJump = 1;
  static const int kBranch = 2;
  static const int kCall = 3;
  static const int kReturn = 4;
}

/// `InstSameRegHint`.
abstract final class InstSameRegHint {
  static const int kNone = 0;
  static const int kRO = 1;
  static const int kWO = 2;
}

/// Physical id meaning "none" (`Reg::kIdBad`).
const int _kIdBad = 0xFF;

int _lsbMask(int n) => n >= 64 ? -1 : (1 << n) - 1;

/// `OpRWInfo`: read/write information of one operand.
class OpRWInfo {
  int opFlags = 0;
  int physId = _kIdBad;
  int rmSize = 0;
  int consecutiveLeadCount = 0;
  int readByteMask = 0;
  int writeByteMask = 0;
  int extendByteMask = 0;

  /// `reset()`.
  void clear() {
    opFlags = 0;
    physId = 0;
    rmSize = 0;
    consecutiveLeadCount = 0;
    readByteMask = 0;
    writeByteMask = 0;
    extendByteMask = 0;
  }

  /// `reset(op_flags, register_size, phys_id)`.
  void reset(int flags, int registerSize, [int phys = _kIdBad]) {
    opFlags = flags;
    physId = phys;
    rmSize = (flags & OpRWFlags.kRegMem) != 0 ? registerSize : 0;
    consecutiveLeadCount = 0;
    final mask = _lsbMask(registerSize < 64 ? registerSize : 64);
    readByteMask = (flags & OpRWFlags.kRead) != 0 ? mask : 0;
    writeByteMask = (flags & OpRWFlags.kWrite) != 0 ? mask : 0;
    extendByteMask = 0;
  }

  bool hasOpFlag(int flag) => (opFlags & flag) != 0;
  void addOpFlags(int flags) => opFlags |= flags;
  void clearOpFlags(int flags) => opFlags &= ~flags;

  bool get isRead => hasOpFlag(OpRWFlags.kRead);
  bool get isWrite => hasOpFlag(OpRWFlags.kWrite);
  bool get isReadWrite => (opFlags & OpRWFlags.kRW) == OpRWFlags.kRW;
  bool get isReadOnly => (opFlags & OpRWFlags.kRW) == OpRWFlags.kRead;
  bool get isWriteOnly => (opFlags & OpRWFlags.kRW) == OpRWFlags.kWrite;
  bool get isUnique => hasOpFlag(OpRWFlags.kUnique);
  bool get hasPhysId => physId != _kIdBad;

  @override
  String toString() => 'OpRWInfo(flags: 0x${opFlags.toRadixString(16)}, '
      'phys: $physId, r: 0x${readByteMask.toRadixString(16)}, '
      'w: 0x${writeByteMask.toRadixString(16)}, '
      'ext: 0x${extendByteMask.toRadixString(16)})';
}

/// `InstRWInfo`: read/write information of an instruction.
class InstRWInfo {
  int instFlags = 0;
  int opCount = 0;
  String rmFeature = '';
  final OpRWInfo extraReg = OpRWInfo();
  final List<OpRWInfo> operands = List.generate(6, (_) => OpRWInfo());

  bool hasInstFlag(int flag) => (instFlags & flag) != 0;
  OpRWInfo operand(int i) => operands[i];
}
