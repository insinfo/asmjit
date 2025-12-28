/// AsmJit Register Allocator
///
/// A simple linear-scan register allocator for x86-64.
/// Based on concepts from asmjit's RA (register allocator).

import 'package:asmjit/asmjit.dart';
import '../core/builder.dart' as ir;
import '../core/support.dart' as support;
import 'reg_type.dart';
import 'raconstraints.dart';

const int _kUnassignedPhysId = -1;
const int _kUnassignedWorkId = -1;

/// Flags used for RA work register metadata.
class RAWorkRegFlags {
  static const int kNone = 0;
  static const int kAllocated = 1 << 0;
  static const int kStackUsed = 1 << 1;
  static const int kStackPreferred = 1 << 2;
  static const int kTied = 1 << 3;
}

/// Stack slot reserved for spilled values.
class RAStackSlot {
  final RAWorkReg workReg;
  final int index;
  final int size;

  RAStackSlot(this.workReg, this.index, {this.size = 8});

  int get offset => index * size;
}

/// Work register data used by RA.
class RAWorkReg {
  final VirtReg vreg;
  final int workId;
  final RegGroup group;

  int _assignedPhysId = _kUnassignedPhysId;
  int _flags = RAWorkRegFlags.kNone;

  bool isSpilled = false;
  RAStackSlot? stackSlot;
  final List<RAWorkReg> tiedRegs = [];

  RAWorkReg(this.vreg, this.workId) : group = vreg.group;

  int? get assignedPhysId =>
      _assignedPhysId == _kUnassignedPhysId ? null : _assignedPhysId;

  bool get isAllocated => _flags & RAWorkRegFlags.kAllocated != 0;

  void markAllocated(int physId) {
    _assignedPhysId = physId;
    _flags |= RAWorkRegFlags.kAllocated;
    isSpilled = false;
    stackSlot = null;
    vreg.isSpilled = false;
    if (group == RegGroup.gp) {
      vreg.physId = physId;
    } else {
      vreg.physXmmId = physId;
    }
  }

  void markUnassigned() {
    _assignedPhysId = _kUnassignedPhysId;
    _flags &= ~RAWorkRegFlags.kAllocated;
    if (group == RegGroup.gp) {
      vreg.physId = null;
    } else {
      vreg.physXmmId = null;
    }
  }

  void markSpilled(RAStackSlot slot) {
    _assignedPhysId = _kUnassignedPhysId;
    _flags &= ~RAWorkRegFlags.kAllocated;
    isSpilled = true;
    stackSlot = slot;
    vreg.isSpilled = true;
    vreg.spillOffset = slot.offset;
  }

  void addTiedReg(RAWorkReg other) {
    if (!tiedRegs.contains(other)) {
      tiedRegs.add(other);
    }
  }
}

/// Tracks usage of physical registers by work IDs.
class RAAssignment {
  final List<int> physIds;
  final Map<int, int> _physIndex = {};
  final List<int> _physToWork;
  final List<int> _workToPhys = [];

  RAAssignment(List<int> physIds)
      : physIds = List.unmodifiable(physIds),
        _physToWork = List.filled(physIds.length, _kUnassignedWorkId) {
    for (int i = 0; i < physIds.length; i++) {
      _physIndex[physIds[i]] = i;
    }
  }

  void reset() {
    for (int i = 0; i < _physToWork.length; i++) {
      _physToWork[i] = _kUnassignedWorkId;
    }
    for (int i = 0; i < _workToPhys.length; i++) {
      _workToPhys[i] = _kUnassignedPhysId;
    }
  }

  int? firstAvailable() {
    for (int i = 0; i < _physToWork.length; i++) {
      if (_physToWork[i] == _kUnassignedWorkId) {
        return physIds[i];
      }
    }
    return null;
  }

  void assign(int workId, int physId) {
    final physIndex = _physIndex[physId];
    if (physIndex == null) return;
    _ensureWorkCapacity(workId);
    _physToWork[physIndex] = workId;
    _workToPhys[workId] = physId;
  }

  void unassignPhys(int physId) {
    final physIndex = _physIndex[physId];
    if (physIndex == null) return;
    final workId = _physToWork[physIndex];
    if (workId != _kUnassignedWorkId &&
        workId < _workToPhys.length &&
        _workToPhys[workId] == physId) {
      _workToPhys[workId] = _kUnassignedPhysId;
    }
    _physToWork[physIndex] = _kUnassignedWorkId;
  }

  int? workToPhys(int workId) {
    if (workId >= _workToPhys.length) return null;
    final physId = _workToPhys[workId];
    return physId == _kUnassignedPhysId ? null : physId;
  }

  int? physToWork(int physId) {
    final physIndex = _physIndex[physId];
    if (physIndex == null) return null;
    final workId = _physToWork[physIndex];
    return workId == _kUnassignedWorkId ? null : workId;
  }

  void _ensureWorkCapacity(int workId) {
    while (workId >= _workToPhys.length) {
      _workToPhys.add(_kUnassignedPhysId);
    }
  }
}

/// Virtual register - represents a value that needs a physical register.
class VirtReg extends BaseReg {
  /// Unique ID.
  @override
  final int id;

  /// Size in bytes (1, 2, 4, or 8).
  @override
  final int size;

  /// Register class (GP, XMM, YMM, ZMM).
  final RegClass regClass;

  /// Assigned physical register ID (null if not yet assigned).
  int? physId;

  /// Assigned XMM/ZMM register ID.
  int? physXmmId;

  /// First/last use position.
  int firstUse = -1;
  int lastUse = -1;

  /// Live/spilled flags.
  bool isSpilled = false;
  int spillOffset = 0;

  VirtReg(this.id, {this.size = 8, this.regClass = RegClass.gp});

  /// The allocated general-purpose register (64-bit view).
  X86Gp? get physReg => physId == null ? null : X86Gp.r64(physId!);

  set physReg(X86Gp? reg) {
    physId = reg?.id;
  }

  /// The allocated vector register (XMM view).
  X86Xmm? get physXmm => physXmmId == null ? null : X86Xmm(physXmmId!);

  set physXmm(X86Xmm? reg) {
    physXmmId = reg?.id;
  }

  @override
  RegType get type {
    if (regClass == RegClass.gp) {
      switch (size) {
        case 1:
          return RegType.gp8Lo;
        case 2:
          return RegType.gp16;
        case 4:
          return RegType.gp32;
        default:
          return RegType.gp64;
      }
    }

    return switch (regClass) {
      RegClass.xmm => RegType.vec128,
      RegClass.ymm => RegType.vec256,
      RegClass.zmm => RegType.vec512,
      _ => RegType.none,
    };
  }

  @override
  RegGroup get group => regClass == RegClass.gp ? RegGroup.gp : RegGroup.vec;

  @override
  bool get isPhysical => false;

  @override
  String toString() => 'v$id';
}

/// Register class types.
enum RegClass {
  gp,
  xmm,
  ymm,
  zmm,
}

/// Live interval for a work register.
class LiveInterval {
  final RAWorkReg workReg;
  final int start;
  int end;

  LiveInterval(this.workReg, this.start, this.end);

  bool contains(int pos) => pos >= start && pos <= end;

  bool intersects(LiveInterval other) =>
      !(end < other.start || start > other.end);

  @override
  String toString() => 'v${workReg.vreg.id}@[$start..$end]';
}

class _RegMove {
  final RAWorkReg workReg;
  final int srcPhys;
  final int dstPhys;

  _RegMove(this.workReg, this.srcPhys, this.dstPhys);
}

class _RegSwap {
  final RAWorkReg workA;
  final RAWorkReg workB;
  final int physA;
  final int physB;

  _RegSwap(this.workA, this.workB, this.physA, this.physB);
}

/// Register allocator port from asmjit’s RALocal allocator.
/// TODO tem que ter a mesma logica exata do c++ se não tiver a logica identica ao c++ não vai funcionar
class RALocal {
  final Arch arch;
  final RAConstraints _constraints = RAConstraints();

  final List<VirtReg> _vregs = [];
  final List<LiveInterval> _intervals = [];
  final Map<VirtReg, RAWorkReg> _workMap = {};
  final List<RAWorkReg> _workRegs = [];

  final List<int> _gpPhysIds = [];
  final List<int> _vecPhysIds = [];
  late RAAssignment _gpAssignment;
  late RAAssignment _vecAssignment;

  int _nextWorkId = 0;
  final List<RAStackSlot> _stackSlots = [];
  final List<_RegMove> _plannedMoves = [];
  final List<_RegSwap> _plannedSwaps = [];

  static const int _stackAlignment = 16;

  RALocal(this.arch) {
    _constraints.init(arch);
    _initAssignments();
  }

  void _initAssignments() {
    _gpPhysIds.clear();
    _vecPhysIds.clear();

    int gpMask = _constraints.availableRegs(RegGroup.gp);
    while (gpMask != 0) {
      final id = support.ctz(gpMask);
      gpMask &= gpMask - 1;
      _gpPhysIds.add(id);
    }

    int vecMask = _constraints.availableRegs(RegGroup.vec);
    while (vecMask != 0) {
      final id = support.ctz(vecMask);
      vecMask &= vecMask - 1;
      _vecPhysIds.add(id);
    }

    _gpAssignment = RAAssignment(List.from(_gpPhysIds));
    _vecAssignment = RAAssignment(List.from(_vecPhysIds));
  }

  /// Create a new virtual register.
  VirtReg newVirtReg({int size = 8, RegClass regClass = RegClass.gp}) {
    final vreg = VirtReg(_vregs.length, size: size, regClass: regClass);
    _vregs.add(vreg);
    return vreg;
  }

  /// Record a use of a virtual register at an instruction position.
  void recordUse(VirtReg vreg, int pos) {
    if (vreg.firstUse < 0) {
      vreg.firstUse = pos;
    }
    vreg.lastUse = pos;
  }

  RAWorkReg _workFor(VirtReg vreg) {
    return _workMap.putIfAbsent(vreg, () {
      final work = RAWorkReg(vreg, _nextWorkId++);
      _workRegs.add(work);
      return work;
    });
  }

  /// Compute live intervals from recorded uses.
  void computeLiveIntervals() {
    _intervals.clear();
    _workMap.clear();
    _workRegs.clear();
    _nextWorkId = 0;

    for (final vreg in _vregs) {
      if (vreg.firstUse >= 0 && vreg.lastUse >= 0) {
        final workReg = _workFor(vreg);
        _intervals.add(LiveInterval(workReg, vreg.firstUse, vreg.lastUse));
      }
    }
    _intervals.sort((a, b) => a.start.compareTo(b.start));
  }

  /// Allocate registers following a kill/spill + move/swap model.
  void allocate([ir.NodeList? nodes]) {
    if (nodes != null) {
      _buildIntervals(nodes);
    }

    computeLiveIntervals();

    _plannedMoves.clear();
    _plannedSwaps.clear();

    _gpAssignment.reset();
    _vecAssignment.reset();
    _stackSlots.clear();

    final active = <LiveInterval>[];

    for (final interval in _intervals) {
      _expireOldIntervals(active, interval.start);

      final workReg = interval.workReg;
      final assignment =
          workReg.group == RegGroup.gp ? _gpAssignment : _vecAssignment;

      final physId = assignment.firstAvailable();
      if (physId != null) {
        _assignPhysical(workReg, physId, assignment);
        active.add(interval);
      } else {
        _spillInterval(interval, active, assignment);
      }
    }

    _optimizeMovePlan();
  }

  void _assignPhysical(RAWorkReg workReg, int physId, RAAssignment assignment) {
    final prevPhys = workReg.assignedPhysId;
    assignment.assign(workReg.workId, physId);
    workReg.markAllocated(physId);
    if (prevPhys != null && prevPhys != physId) {
      _recordMove(prevPhys, physId, workReg);
    }
  }

  void _spillInterval(LiveInterval interval, List<LiveInterval> active,
      RAAssignment assignment) {
    final workReg = interval.workReg;
    LiveInterval? spillCandidate;
    int maxEnd = interval.end;

    for (final activeInterval in active) {
      if (activeInterval.workReg.group == workReg.group) {
        if (activeInterval.end > maxEnd) {
          maxEnd = activeInterval.end;
          spillCandidate = activeInterval;
        }
      }
    }

    if (spillCandidate != null &&
        spillCandidate.workReg.assignedPhysId != null) {
      final physId = spillCandidate.workReg.assignedPhysId!;
      assignment.unassignPhys(physId);
      spillCandidate.workReg
          .markSpilled(_allocStackSlot(spillCandidate.workReg));
      active.remove(spillCandidate);

      _assignPhysical(workReg, physId, assignment);
      active.add(interval);
    } else {
      workReg.markSpilled(_allocStackSlot(workReg));
    }
  }

  void _expireOldIntervals(List<LiveInterval> active, int pos) {
    active.removeWhere((interval) {
      if (interval.end < pos) {
        final workReg = interval.workReg;
        final physId = workReg.assignedPhysId;
        if (physId != null) {
          final assignment =
              workReg.group == RegGroup.gp ? _gpAssignment : _vecAssignment;
          assignment.unassignPhys(physId);
        }
        return true;
      }
      return false;
    });
  }

  RAStackSlot _allocStackSlot(RAWorkReg workReg) {
    final slot = RAStackSlot(workReg, _stackSlots.length);
    _stackSlots.add(slot);
    return slot;
  }

  void _optimizeMovePlan() {
    final moves = List<_RegMove>.from(_plannedMoves);
    _plannedMoves.clear();
    final used = <int>{};
    for (var i = 0; i < moves.length; i++) {
      if (used.contains(i)) continue;
      var foundSwap = false;
      for (var j = i + 1; j < moves.length; j++) {
        if (used.contains(j)) continue;
        final a = moves[i];
        final b = moves[j];
        if (a.srcPhys == b.dstPhys &&
            a.dstPhys == b.srcPhys &&
            a.workReg.group == RegGroup.gp &&
            b.workReg.group == RegGroup.gp) {
          _plannedSwaps
              .add(_RegSwap(a.workReg, b.workReg, a.srcPhys, a.dstPhys));
          used.add(i);
          used.add(j);
          foundSwap = true;
          break;
        }
      }
      if (!foundSwap && !used.contains(i)) {
        _plannedMoves.add(moves[i]);
      }
    }
  }

  void emitRegMoves(X86Assembler asm) {
    for (final swap in _plannedSwaps) {
      _emitSwapInstruction(asm, swap);
    }
    for (final move in _plannedMoves) {
      _emitMoveInstruction(asm, move);
    }
    _plannedSwaps.clear();
    _plannedMoves.clear();
  }

  void _recordMove(int srcPhys, int dstPhys, RAWorkReg workReg) {
    _plannedMoves.add(_RegMove(workReg, srcPhys, dstPhys));
  }

  void _emitMoveInstruction(X86Assembler asm, _RegMove move) {
    if (move.workReg.group == RegGroup.gp) {
      asm.movRR(_toGp(move.dstPhys), _toGp(move.srcPhys));
    } else if (move.workReg.group == RegGroup.vec) {
      _emitVecMove(asm, move.workReg, move.srcPhys, move.dstPhys);
    }
  }

  void _emitSwapInstruction(X86Assembler asm, _RegSwap swap) {
    if (swap.workA.group == RegGroup.gp && swap.workB.group == RegGroup.gp) {
      asm.xchg(_toGp(swap.physA), _toGp(swap.physB));
    } else {
      _emitMoveInstruction(asm, _RegMove(swap.workA, swap.physA, swap.physB));
      _emitMoveInstruction(asm, _RegMove(swap.workB, swap.physB, swap.physA));
    }
  }

  void _emitVecMove(
      X86Assembler asm, RAWorkReg workReg, int srcPhys, int dstPhys) {
    switch (workReg.vreg.regClass) {
      case RegClass.xmm:
        asm.vmovupsXX(X86Xmm(dstPhys), X86Xmm(srcPhys));
        break;
      case RegClass.ymm:
        asm.vmovupsYY(X86Ymm(dstPhys), X86Ymm(srcPhys));
        break;
      case RegClass.zmm:
        asm.vmovupsZmm(X86Zmm(dstPhys), X86Zmm(srcPhys));
        break;
      default:
        asm.vmovupsXX(X86Xmm(dstPhys), X86Xmm(srcPhys));
        break;
    }
  }

  X86Gp _toGp(int id) => X86Gp.r64(id);

  /// Get the total spill area size (aligned).
  int get spillAreaSize {
    if (_stackSlots.isEmpty) return 0;
    final size = _stackSlots.length * 8;
    return (size + _stackAlignment - 1) & ~(_stackAlignment - 1);
  }

  /// Get all virtual registers.
  List<VirtReg> get virtualRegs => List.unmodifiable(_vregs);

  /// Get all live intervals.
  List<LiveInterval> get liveIntervals => List.unmodifiable(_intervals);

  /// Reset the allocator for reuse.
  void reset() {
    _vregs.clear();
    _intervals.clear();
    _workMap.clear();
    _workRegs.clear();
    _nextWorkId = 0;
    _stackSlots.clear();
    _plannedMoves.clear();
    _plannedSwaps.clear();
    _gpAssignment.reset();
    _vecAssignment.reset();
    _initAssignments();
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('RALocal-like LinearScanRegAlloc:');
    sb.writeln('  Virtual registers: ${_vregs.length}');
    sb.writeln('  Live intervals: ${_intervals.length}');
    sb.writeln('  Spill slots: ${_stackSlots.length}');
    sb.writeln('  Spillarea size: $spillAreaSize bytes');
    for (final workReg in _workRegs) {
      final reg = workReg.vreg.physReg ?? workReg.vreg.physXmm;
      final status = workReg.isSpilled
          ? 'spilled@${workReg.vreg.spillOffset}'
          : reg?.toString() ?? 'unassigned';
      sb.writeln('    v${workReg.vreg.id} -> $status');
    }
    return sb.toString();
  }

  /// Build intervals by iterating over the node list.
  void _buildIntervals(ir.NodeList nodes) {
    int pos = 0;
    final labelPos = <int, int>{};
    final loops = <_LoopRange>[];

    // Pass 1: map labels
    for (final node in nodes.nodes) {
      if (node is ir.LabelNode) {
        labelPos[node.label.id] = pos;
      } else if (node is ir.InstNode || node is ir.InvokeNode) {
        pos += 2;
      }
    }

    // Pass 2: record uses and find loops
    pos = 0;
    for (final node in nodes.nodes) {
      if (node is ir.InstNode) {
        _recordOperands(node.operands, pos);

        // Check for backward jump (loop)
        // Heuristic: if instruction has label operand pointing backward
        for (final op in node.operands) {
          if (op is ir.LabelOperand) {
            final target = labelPos[op.label.id];
            if (target != null && target < pos) {
              loops.add(_LoopRange(target, pos));
            }
          }
        }
        pos += 2;
      } else if (node is ir.InvokeNode) {
        _recordOperands(node.args, pos);
        if (node.ret is VirtReg) {
          recordUse(node.ret as VirtReg, pos);
        }
        pos += 2;
      }
    }

    // Pass 3: extend intervals for loops
    // If a register is used within a loop, it must be live throughout the loop
    for (final vreg in _vregs) {
      if (vreg.firstUse == -1) continue;

      for (final loop in loops) {
        // If reg is used inside the loop (or defined before/inside and used inside)
        // Check if [firstUse, lastUse] overlaps loop [start, end]
        // Actually, if it is USED inside the loop, we extend lastUse to loop end.
        // Determining "used inside" strictly:
        // We need to know if any use point is in [loop.start, loop.end].
        // SimpleRegAlloc doesn't store use list, only first/last.
        // Approximation: If intervals overlap, assume usage might be inside?
        // No, if defined at 10, used at 20. Loop 50..100.
        // Interval [10, 20]. No overlap.
        // If defined at 10, used at 60. Loop 50..100.
        // Overlap. Usage at 60 is inside. So extend lastUse to 100.
        // If defined at 60, used at 70. Loop 50..100.
        // Usage inside. Extend to 100.
        // So: If (lastUse >= loop.start && firstUse <= loop.end)
        // AND (lastUse < loop.end) -> Extend to loop.end.
        // But what if usage at 60 is the ONLY usage?
        // Then it needs to be live at 50 (start of loop)?
        // Yes, if it is live-in.
        // But if defined at 60. It is NOT live-in.
        // If defined at 10. Used at 60. It IS live-in.
        // So:
        // 1. If defined (firstUse) < loop.start AND used (lastUse) >= loop.start.
        //    Then it is live-in. It must be live until loop.end.
        //    newLastUse = max(lastUse, loop.end).
        // 2. If defined inside loop (firstUse >= loop.start).
        //    It is local.
        //    It only needs to be live until loop.end if it is live-out?
        //    "Simple" alloc handles local properly (linear scan).
        //    Wait, if defined at 60, used at 70. Loop back to 50.
        //    Is it live at 50? No.
        //    Is it live at 100 (jump)? No, unless used in next iter.
        //    If used in next iter, it would be live-in (via phi) or defined before?
        //    If defined INSIDE, it is new instance each iter.
        //    So only Case 1 matters: Live-In variables.

        if (vreg.firstUse < loop.start && vreg.lastUse >= loop.start) {
          if (vreg.lastUse < loop.end) {
            vreg.lastUse = loop.end;
          }
        }
      }
    }
  }

  void _scanMemOperand(ir.MemOperand op, int pos) {
    final mem = op.mem;
    if (mem is X86Mem) {
      if (mem.base is VirtReg) {
        recordUse(mem.base as VirtReg, pos);
      }
      if (mem.index is VirtReg) {
        recordUse(mem.index as VirtReg, pos);
      }
    }
  }

  void _recordOperands(List<ir.Operand> operands, int pos) {
    for (final op in operands) {
      if (op is ir.RegOperand) {
        final reg = op.reg;
        if (reg is VirtReg) {
          recordUse(reg, pos);
        }
      } else if (op is ir.MemOperand) {
        _scanMemOperand(op, pos);
      }
    }
  }
}

class _LoopRange {
  final int start;
  final int end;
  _LoopRange(this.start, this.end);
}
