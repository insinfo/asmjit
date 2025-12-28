import 'radefs.dart';
import 'bitvector.dart';
import 'raassignment.dart';

/// Register allocator's data associated with each [InstNode].
class RAInst {
  /// Aggregated [RATiedFlags] from all operands & instruction specific flags.
  int flags = 0;

  /// Total count of [RATiedReg]s.
  int tiedTotal = 0;

  /// Count of [RATiedReg]s per register group.
  final RARegCount tiedCount = RARegCount();

  /// Number of live, and thus interfering [VirtReg]'s at this point.
  final RALiveCount liveCount = RALiveCount();

  /// Fixed physical registers used.
  final RARegMask usedRegs = RARegMask();

  /// Clobbered registers (by a function call).
  final RARegMask clobberedRegs = RARegMask();

  /// Tied registers.
  final List<RATiedReg> tiedRegs = [];

  RAInst();
}

/// Extended data for blocks during RA.
class RABlockData {
  final int id;

  /// GEN set: virtual registers defined in this block before being used.
  late BitVector gen;

  /// KILL set: virtual registers redefined in this block.
  late BitVector kill;

  /// LIVE-IN set: virtual registers live at the entry of this block.
  late BitVector liveIn;

  /// LIVE-OUT set: virtual registers live at the exit of this block.
  late BitVector liveOut;

  /// Register assignment on block entry.
  RAAssignmentState? entryAssignment;

  /// Register assignment on block exit.
  RAAssignmentState? exitAssignment;

  RABlockData(this.id, int numWorkRegs) {
    gen = BitVector(numWorkRegs);
    kill = BitVector(numWorkRegs);
    liveIn = BitVector(numWorkRegs);
    liveOut = BitVector(numWorkRegs);
  }
}
