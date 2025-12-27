/// AsmJit Global Constants and Utilities
///
/// Ported from asmjit/core/globals.h

/// Global constants used throughout AsmJit.
abstract final class Globals {
  /// Host memory allocator overhead.
  static const int allocOverhead = 4 * 8; // sizeof(intptr_t) * 4

  /// Host memory allocator alignment.
  static const int allocAlignment = 8;

  /// Aggressive growing strategy threshold.
  static const int growThreshold = 1024 * 1024 * 16; // 16MB

  /// Maximum depth of RB-Tree.
  static const int maxTreeHeight = 128;

  /// Maximum function arguments.
  static const int maxFuncArgs = 32;

  /// Invalid identifier.
  static const int invalidId = 0xFFFFFFFF;

  /// Invalid base address.
  static const int noBaseAddress = -1; // ~0 in uint64

  /// Number of virtual register groups.
  static const int numVirtGroups = 4;

  /// Maximum label name size.
  static const int maxLabelNameSize = 2048;

  /// Maximum section name size.
  static const int maxSectionNameSize = 35;

  /// Maximum size of a comment.
  static const int maxCommentSize = 1024;
}

/// Reset behavior.
enum ResetPolicy {
  /// Soft reset, resets only the state, keeps allocated memory.
  soft,

  /// Hard reset, releases all allocated memory.
  hard,
}

/// Checks if an index is invalid (npos-like).
bool isNpos(int index) => index == -1 || index == Globals.invalidId;
