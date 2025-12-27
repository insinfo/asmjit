/// AsmJit Instruction API.
///
/// Provides minimal metadata helpers used by higher-level pipelines.

import '../x86/x86_inst_db.g.dart';

/// Read/write info for an instruction.
class InstRWInfo {
  final int readCount;
  final int writeCount;
  final int rwCount;

  const InstRWInfo({this.readCount = 0, this.writeCount = 0, this.rwCount = 0});

  bool get hasReads => readCount > 0 || rwCount > 0;
  bool get hasWrites => writeCount > 0 || rwCount > 0;
}

/// Instruction API entry point.
class InstAPI {
  static const Map<int, InstRWInfo> _x86RwInfo = {
    X86InstId.kMov: InstRWInfo(readCount: 1, writeCount: 1),
    X86InstId.kMovzx: InstRWInfo(readCount: 1, writeCount: 1),
    X86InstId.kMovsx: InstRWInfo(readCount: 1, writeCount: 1),
    X86InstId.kMovsxd: InstRWInfo(readCount: 1, writeCount: 1),
    X86InstId.kLea: InstRWInfo(readCount: 1, writeCount: 1),
    X86InstId.kAdd: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kSub: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kAnd: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kOr: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kXor: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kImul: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kShl: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kShr: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kSar: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kRol: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kRor: InstRWInfo(readCount: 1, rwCount: 1),
    X86InstId.kInc: InstRWInfo(rwCount: 1),
    X86InstId.kDec: InstRWInfo(rwCount: 1),
    X86InstId.kNeg: InstRWInfo(rwCount: 1),
    X86InstId.kNot: InstRWInfo(rwCount: 1),
    X86InstId.kCmp: InstRWInfo(readCount: 2),
    X86InstId.kTest: InstRWInfo(readCount: 2),
    X86InstId.kCall: InstRWInfo(),
    X86InstId.kRet: InstRWInfo(),
    X86InstId.kJmp: InstRWInfo(),
  };

  /// Returns read/write metadata for [instId].
  static InstRWInfo queryRWInfo(int instId) {
    final info = _x86RwInfo[instId];
    if (info != null) {
      return info;
    }
    return const InstRWInfo();
  }
}
