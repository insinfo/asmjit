/// Register Assignment
///
/// Holds the current register assignment used by the local register allocator.
/// Ported faithfully from the C++ AsmJit implementation.

import 'globals.dart';
import 'operand.dart' show RegGroup;
import 'radefs.dart';
import 'support.dart' as support;

/// Physical register to work register mapping.
class PhysToWorkMap {
  /// Assigned registers (each bit represents one physical reg).
  final RARegMask assigned = RARegMask();

  /// Dirty registers (spill slot out of sync or no spill slot).
  final RARegMask dirty = RARegMask();

  /// PhysReg to WorkReg mapping.
  final List<RAWorkId> workIds;

  PhysToWorkMap(int physTotal) : workIds = List.filled(physTotal, kBadWorkId);

  void reset() {
    assigned.reset();
    dirty.reset();
    workIds.fillRange(0, workIds.length, kBadWorkId);
  }

  void copyFrom(PhysToWorkMap other) {
    assigned.init(other.assigned);
    dirty.init(other.dirty);
    for (int i = 0; i < workIds.length && i < other.workIds.length; i++) {
      workIds[i] = other.workIds[i];
    }
  }

  void unassign(RegGroup group, int physId, int indexInWorkIds) {
    assigned.clear(group, support.bitMask(physId));
    dirty.clear(group, support.bitMask(physId));
    workIds[indexInWorkIds] = kBadWorkId;
  }
}

/// Work register to physical register mapping.
class WorkToPhysMap {
  /// WorkReg to PhysReg mapping.
  final List<int> physIds;

  WorkToPhysMap(int workCount)
      : physIds = List.filled(workCount, RAAssignment.kPhysNone);

  void reset() {
    physIds.fillRange(0, physIds.length, RAAssignment.kPhysNone);
  }

  void copyFrom(WorkToPhysMap other) {
    for (int i = 0; i < physIds.length && i < other.physIds.length; i++) {
      physIds[i] = other.physIds[i];
    }
  }
}

/// Layout information for register assignment.
class RAAssignmentLayout {
  /// Index of architecture registers per group.
  final RARegIndex physIndex = RARegIndex();

  /// Count of architecture registers per group.
  final RARegCount physCount = RARegCount();

  /// Count of physical registers of all groups.
  int physTotal = 0;

  /// Count of work registers.
  int workCount = 0;

  /// WorkRegs data (vector).
  List<RAWorkReg>? workRegs;

  void reset() {
    physIndex.reset();
    physCount.reset();
    physTotal = 0;
    workCount = 0;
    workRegs = null;
  }
}

/// Holds the current register assignment.
///
/// Has two purposes:
///   1. Holds register assignment of a local register allocator.
///   2. Holds register assignment of the entry of basic blocks.
class RAAssignmentState {
  /// Physical registers layout.
  final RAAssignmentLayout _layout = RAAssignmentLayout();

  /// WorkReg to PhysReg mapping.
  WorkToPhysMap? _workToPhysMap;

  /// PhysReg to WorkReg mapping and assigned/dirty bits.
  PhysToWorkMap? _physToWorkMap;

  /// Optimization to translate PhysRegs to WorkRegs faster.
  final List<List<RAWorkId>> _physToWorkIds =
      List.generate(Globals.numVirtGroups, (_) => []);

  RAAssignmentState() {
    _layout.reset();
    resetMaps();
  }

  void initLayout(RARegCount physCount, List<RAWorkReg> workRegs) {
    assert(_physToWorkMap == null);
    assert(_workToPhysMap == null);

    _layout.physIndex.buildIndexes(physCount);
    // Copy values from physCount to layout.physCount
    for (final group in enumerateRegGroupsMax()) {
      _layout.physCount.set(group, physCount.get(group));
    }
    _layout.physTotal =
        _layout.physIndex.get(RegGroup.values[RegGroup.kMaxVirt]) +
            _layout.physCount.get(RegGroup.values[RegGroup.kMaxVirt]);
    _layout.workCount = workRegs.length;
    _layout.workRegs = workRegs;
  }

  void initMaps(PhysToWorkMap physToWorkMap, WorkToPhysMap workToPhysMap) {
    _physToWorkMap = physToWorkMap;
    _workToPhysMap = workToPhysMap;

    for (final group in enumerateRegGroupsMax()) {
      final baseIndex = _layout.physIndex.get(group);
      final count = _layout.physCount.get(group);
      _physToWorkIds[group.index] = List.generate(
        count,
        (i) => physToWorkMap.workIds[baseIndex + i],
      );
    }
  }

  void resetMaps() {
    _physToWorkMap = null;
    _workToPhysMap = null;
    for (int i = 0; i < _physToWorkIds.length; i++) {
      _physToWorkIds[i] = [];
    }
  }

  PhysToWorkMap? get physToWorkMap => _physToWorkMap;
  WorkToPhysMap? get workToPhysMap => _workToPhysMap;

  RARegMask get assigned => _physToWorkMap!.assigned;
  int assignedGroup(RegGroup group) => _physToWorkMap!.assigned[group];

  RARegMask get dirty => _physToWorkMap!.dirty;
  int dirtyGroup(RegGroup group) => _physToWorkMap!.dirty[group];

  int workToPhysId(RegGroup group, RAWorkId workId) {
    assert(workId != kBadWorkId);
    assert(workId < _layout.workCount);
    return _workToPhysMap!.physIds[workId];
  }

  RAWorkId physToWorkId(RegGroup group, int physId) {
    assert(physId < Globals.kMaxPhysRegs);
    // Fonte-da-verdade: o mapa linearizado `_physToWorkMap.workIds`.
    // O cache `_physToWorkIds` é apenas otimização e pode ficar desatualizado
    // após copy/swap - isso quebraria invariantes (ex.: unassign asserts).
    final baseIndex = _layout.physIndex.get(group);
    final count = _layout.physCount.get(group);
    if (physId >= count) {
      return kBadWorkId;
    }
    return _physToWorkMap!.workIds[baseIndex + physId];
  }

  bool isPhysAssigned(RegGroup group, int physId) {
    assert(physId < Globals.kMaxPhysRegs);
    return support.bitTest(_physToWorkMap!.assigned[group], physId);
  }

  bool isPhysDirty(RegGroup group, int physId) {
    assert(physId < Globals.kMaxPhysRegs);
    return support.bitTest(_physToWorkMap!.dirty[group], physId);
  }

  /// Assign [VirtReg/WorkReg] to a physical register.
  void assign(RegGroup group, RAWorkId workId, int physId, bool dirty) {
    assert(workToPhysId(group, workId) == RAAssignment.kPhysNone);
    assert(physToWorkId(group, physId) == kBadWorkId);
    assert(!isPhysAssigned(group, physId));
    assert(!isPhysDirty(group, physId));

    _workToPhysMap!.physIds[workId] = physId;

    // Update the phys to work mapping
    final baseIndex = _layout.physIndex.get(group);
    _physToWorkMap!.workIds[baseIndex + physId] = workId;
    if (physId < _physToWorkIds[group.index].length) {
      _physToWorkIds[group.index][physId] = workId;
    }

    final regMask = support.bitMask(physId);
    _physToWorkMap!.assigned[group] |= regMask;
    if (dirty) {
      _physToWorkMap!.dirty[group] |= regMask;
    }
  }

  /// Reassign [VirtReg/WorkReg] to `dstPhysId` from `srcPhysId`.
  void reassign(RegGroup group, RAWorkId workId, int dstPhysId, int srcPhysId) {
    assert(dstPhysId != srcPhysId);
    assert(workToPhysId(group, workId) == srcPhysId);
    assert(physToWorkId(group, srcPhysId) == workId);
    assert(isPhysAssigned(group, srcPhysId));
    assert(!isPhysAssigned(group, dstPhysId));

    _workToPhysMap!.physIds[workId] = dstPhysId;

    final baseIndex = _layout.physIndex.get(group);
    _physToWorkMap!.workIds[baseIndex + srcPhysId] = kBadWorkId;
    _physToWorkMap!.workIds[baseIndex + dstPhysId] = workId;

    if (srcPhysId < _physToWorkIds[group.index].length) {
      _physToWorkIds[group.index][srcPhysId] = kBadWorkId;
    }
    if (dstPhysId < _physToWorkIds[group.index].length) {
      _physToWorkIds[group.index][dstPhysId] = workId;
    }

    final srcMask = support.bitMask(srcPhysId);
    final dstMask = support.bitMask(dstPhysId);
    final wasDirty = (_physToWorkMap!.dirty[group] & srcMask) != 0;
    final regMask = dstMask | srcMask;

    _physToWorkMap!.assigned[group] ^= regMask;
    if (wasDirty) {
      _physToWorkMap!.dirty[group] ^= regMask;
    }
  }

  /// Swap two work registers between their physical registers.
  void swap(RegGroup group, RAWorkId aWorkId, int aPhysId, RAWorkId bWorkId,
      int bPhysId) {
    assert(aPhysId != bPhysId);
    assert(workToPhysId(group, aWorkId) == aPhysId);
    assert(workToPhysId(group, bWorkId) == bPhysId);
    assert(physToWorkId(group, aPhysId) == aWorkId);
    assert(physToWorkId(group, bPhysId) == bWorkId);
    assert(isPhysAssigned(group, aPhysId));
    assert(isPhysAssigned(group, bPhysId));

    _workToPhysMap!.physIds[aWorkId] = bPhysId;
    _workToPhysMap!.physIds[bWorkId] = aPhysId;

    final baseIndex = _layout.physIndex.get(group);
    _physToWorkMap!.workIds[baseIndex + aPhysId] = bWorkId;
    _physToWorkMap!.workIds[baseIndex + bPhysId] = aWorkId;

    if (aPhysId < _physToWorkIds[group.index].length) {
      _physToWorkIds[group.index][aPhysId] = bWorkId;
    }
    if (bPhysId < _physToWorkIds[group.index].length) {
      _physToWorkIds[group.index][bPhysId] = aWorkId;
    }

    final aMask = support.bitMask(aPhysId);
    final bMask = support.bitMask(bPhysId);
    final aDirty = (_physToWorkMap!.dirty[group] & aMask) != 0;
    final bDirty = (_physToWorkMap!.dirty[group] & bMask) != 0;

    if (aDirty != bDirty) {
      final regMask = aMask | bMask;
      _physToWorkMap!.dirty[group] ^= regMask;
    }
  }

  /// Unassign [VirtReg/WorkReg] from a physical register.
  void unassign(RegGroup group, RAWorkId workId, int physId) {
    assert(physId < Globals.kMaxPhysRegs);
    assert(workToPhysId(group, workId) == physId);
    assert(physToWorkId(group, physId) == workId);
    assert(isPhysAssigned(group, physId));

    _workToPhysMap!.physIds[workId] = RAAssignment.kPhysNone;

    final baseIndex = _layout.physIndex.get(group);
    _physToWorkMap!.workIds[baseIndex + physId] = kBadWorkId;

    if (physId < _physToWorkIds[group.index].length) {
      _physToWorkIds[group.index][physId] = kBadWorkId;
    }

    final regMask = support.bitMask(physId);
    _physToWorkMap!.assigned[group] &= ~regMask;
    _physToWorkMap!.dirty[group] &= ~regMask;
  }

  void makeClean(RegGroup group, RAWorkId workId, int physId) {
    final regMask = support.bitMask(physId);
    _physToWorkMap!.dirty[group] &= ~regMask;
  }

  void makeDirty(RegGroup group, RAWorkId workId, int physId) {
    final regMask = support.bitMask(physId);
    _physToWorkMap!.dirty[group] |= regMask;
  }

  void swapWith(RAAssignmentState other) {
    final tempWork = _workToPhysMap;
    final tempPhys = _physToWorkMap;
    _workToPhysMap = other._workToPhysMap;
    _physToWorkMap = other._physToWorkMap;
    other._workToPhysMap = tempWork;
    other._physToWorkMap = tempPhys;

    for (int i = 0; i < _physToWorkIds.length; i++) {
      final temp = _physToWorkIds[i];
      _physToWorkIds[i] = other._physToWorkIds[i];
      other._physToWorkIds[i] = temp;
    }
  }

  void assignWorkIdsFromPhysIds() {
    _workToPhysMap!.reset();

    for (final group in enumerateRegGroupsMax()) {
      final physBaseIndex = _layout.physIndex.get(group);
      int mask = _physToWorkMap!.assigned[group];

      while (mask != 0) {
        final physId = support.ctz(mask);
        mask &= mask - 1;

        final workId = _physToWorkMap!.workIds[physBaseIndex + physId];
        assert(workId != kBadWorkId);
        _workToPhysMap!.physIds[workId] = physId;
      }
    }
  }

  void copyFromPhysToWork(PhysToWorkMap physToWorkMap) {
    _physToWorkMap!.copyFrom(physToWorkMap);
    assignWorkIdsFromPhysIds();
  }

  void copyFrom(RAAssignmentState other) {
    _physToWorkMap!.copyFrom(other._physToWorkMap!);
    _workToPhysMap!.copyFrom(other._workToPhysMap!);
  }

  bool equals(RAAssignmentState other) {
    if (_layout.physTotal != other._layout.physTotal ||
        _layout.workCount != other._layout.workCount) {
      return false;
    }

    for (int i = 0; i < _layout.physTotal; i++) {
      if (_physToWorkMap!.workIds[i] != other._physToWorkMap!.workIds[i]) {
        return false;
      }
    }

    for (int i = 0; i < _layout.workCount; i++) {
      if (_workToPhysMap!.physIds[i] != other._workToPhysMap!.physIds[i]) {
        return false;
      }
    }

    if (_physToWorkMap!.assigned != other._physToWorkMap!.assigned ||
        _physToWorkMap!.dirty != other._physToWorkMap!.dirty) {
      return false;
    }

    return true;
  }
}

/// Intersection of multiple register assignments.
class RASharedAssignment {
  /// Bit-mask of registers that cannot be used upon a block entry.
  int _entryScratchGpRegs = 0;

  /// Union of all live-in registers (as bit set).
  List<int> _liveIn = [];

  /// Register assignment (PhysToWork).
  PhysToWorkMap? _physToWorkMap;

  bool get isEmpty => _physToWorkMap == null;

  int get entryScratchGpRegs => _entryScratchGpRegs;
  void addEntryScratchGpRegs(int mask) => _entryScratchGpRegs |= mask;

  List<int> get liveIn => _liveIn;
  set liveIn(List<int> value) => _liveIn = value;

  PhysToWorkMap? get physToWorkMap => _physToWorkMap;
  set physToWorkMap(PhysToWorkMap? value) => _physToWorkMap = value;
}
