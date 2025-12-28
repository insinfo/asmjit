/// Register Allocator Block
///
/// Holds information about a basic block during register allocation.
/// Ported faithfully from the C++ AsmJit implementation.

import 'radefs.dart';
import 'raassignment.dart';
import 'compiler.dart' show BlockNode, BaseNode;

/// Flags used by [RABlock].
class RABlockFlags {
  static const int kNone = 0;
  static const int kIsReachable = 0x00000001;
  static const int kIsAllocated = 0x00000002;
  static const int kIsEnqueued = 0x00000004;
  static const int kHasTerminator = 0x00000008;
}

/// Basic block used by [RAPass].
class RABlock {
  final BlockNode blockNode;
  final int blockId;

  int _flags = 0;

  // CFG
  final List<RABlock> predecessors = [];
  final List<RABlock> successors = [];

  // Liveness analysis
  // BitWord arrays (represented as List<int> or specialized BitVector)
  List<int> gen = [];
  List<int> kill = [];
  List<int> liveIn = [];
  List<int> liveOut = [];

  // Statistics
  final RALiveCount maxLiveCount = RALiveCount();

  // Positions in the instruction stream
  int firstPosition = 0;
  int endPosition = 0;

  // Assignment at the entry of the block
  final RAAssignmentState entryAssignment = RAAssignmentState();

  RABlock(this.blockNode, this.blockId);

  void addFlags(int flags) => _flags |= flags;
  void clearFlags(int flags) => _flags &= ~flags;
  bool hasFlag(int flag) => (_flags & flag) != 0;

  bool get isReachable => hasFlag(RABlockFlags.kIsReachable);
  bool get isAllocated => hasFlag(RABlockFlags.kIsAllocated);
  bool get isEnqueued => hasFlag(RABlockFlags.kIsEnqueued);
  bool get hasTerminator => hasFlag(RABlockFlags.kHasTerminator);

  void makeReachable() => addFlags(RABlockFlags.kIsReachable);
  void makeAllocated() => addFlags(RABlockFlags.kIsAllocated);

  BaseNode? get first => blockNode;
}
