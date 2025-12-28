/// AsmJit Global Constants and Utilities
///
/// Ported from asmjit/core/globals.h

/// Global constants used throughout AsmJit.
abstract final class Globals {
  /// Host memory allocator overhead.
  static const int kAllocOverhead = 4 * 8; // sizeof(intptr_t) * 4

  /// Host memory allocator alignment.
  static const int kAllocAlignment = 8;

  /// Aggressive growing strategy threshold.
  static const int kGrowThreshold = 1024 * 1024 * 16; // 16MB

  /// Maximum depth of RB-Tree.
  static const int kMaxTreeHeight = 128;

  /// Maximum function arguments.
  static const int kMaxFuncArgs = 32;

  /// Maximum value pack size.
  static const int kMaxValuePack = 4;

  /// Invalid identifier.
  static const int kInvalidId = 0xFFFFFFFF;

  /// Invalid base address.
  static const int kNoBaseAddress = -1; // ~0 in uint64

  /// Number of virtual register groups.
  static const int kNumVirtGroups = 4;

  /// Maximum label name size.
  static const int kMaxLabelNameSize = 2048;

  /// Maximum section name size.
  static const int kMaxSectionNameSize = 35;

  /// Maximum size of a comment.
  static const int kMaxCommentSize = 1024;

  // Compatibility aliases
  static const int numVirtGroups = kNumVirtGroups;
  static const int maxFuncArgs = kMaxFuncArgs;
  static const int maxValuePack = kMaxValuePack;
  static const int invalidId = kInvalidId;

  /// Maximum physical registers per group.
  static const int kMaxPhysRegs = 32;
}

/// Constant alias for max function arguments.
const int kMaxFuncArgs = Globals.kMaxFuncArgs;

/// Constant alias for max value pack size.
const int kMaxValuePack = Globals.kMaxValuePack;

/// Reset behavior.
enum ResetPolicy {
  /// Soft reset, resets only the state, keeps allocated memory.
  soft,

  /// Hard reset, releases all allocated memory.
  hard,
}

/// Checks if an index is invalid (npos-like).
bool isNpos(int index) => index == -1;
