/// AsmJit Instruction API (stub).
///
/// Provides minimal metadata helpers used by higher-level pipelines.

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
  /// Returns read/write metadata for [instId].
  ///
  /// TODO: Populate with real instruction metadata from the DB.
  static InstRWInfo queryRWInfo(int instId) {
    return const InstRWInfo();
  }
}
