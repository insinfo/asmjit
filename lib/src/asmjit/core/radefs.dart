/// Register Allocator Definitions
///
/// This file contains all the core data structures used by the register allocator,
/// ported faithfully from the C++ AsmJit implementation.

import 'globals.dart';
import 'operand.dart';
import 'support.dart' as support;

/// Work register identifier (RA).
///
/// Work register is an actual virtual register that is used by the function
/// and subject to register allocation.
typedef RAWorkId = int;

/// Basic block identifier (RA).
typedef RABlockId = int;

/// Invalid work register ID.
const RAWorkId kBadWorkId = Globals.kInvalidId;

/// Invalid block ID.
const RABlockId kBadBlockId = Globals.kInvalidId;

/// Maximum number of consecutive registers aggregated from all backends.
const int kMaxConsecutiveRegs = 4;

/// Register allocation strategy type.
enum RAStrategyType {
  simple(0),
  complex(1);

  final int value;
  const RAStrategyType(this.value);
}

/// Register allocation strategy flags.
class RAStrategyFlags {
  static const int kNone = 0;
}

/// Register allocation strategy.
///
/// The idea is to select the best register allocation strategy for each
/// virtual register group based on the complexity of the code.
class RAStrategy {
  RAStrategyType _type = RAStrategyType.simple;
  int _flags = RAStrategyFlags.kNone;

  void reset() {
    _type = RAStrategyType.simple;
    _flags = RAStrategyFlags.kNone;
  }

  RAStrategyType get type => _type;
  set type(RAStrategyType value) => _type = value;

  bool get isSimple => _type == RAStrategyType.simple;
  bool get isComplex => _type.value >= RAStrategyType.complex.value;

  int get flags => _flags;
  bool hasFlag(int flag) => (_flags & flag) != 0;
  void addFlags(int flags) => _flags |= flags;
}

/// Count of virtual or physical registers per group.
///
/// Uses 8-bit integers to represent counters. Only used in places where this
/// is sufficient, for example total count of physical registers, count of
/// virtual registers per instruction, etc.
class RARegCount {
  int _counters = 0;

  void reset() => _counters = 0;

  bool operator ==(Object other) {
    if (other is RARegCount) {
      return _counters == other._counters;
    }
    return false;
  }

  @override
  int get hashCode => _counters.hashCode;

  /// Returns the count of registers by the given register `group`.
  int get(RegGroup group) {
    assert(group.index <= RegGroup.kMaxVirt);
    final shift = group.index * 8;
    return (_counters >> shift) & 0xFF;
  }

  /// Sets the register count by a register `group`.
  void set(RegGroup group, int n) {
    assert(group.index <= RegGroup.kMaxVirt);
    assert(n <= 0xFF);
    final shift = group.index * 8;
    _counters = (_counters & ~(0xFF << shift)) + (n << shift);
  }

  /// Adds n to the register count for the given register `group`.
  void add(RegGroup group, [int n = 1]) {
    assert(group.index <= RegGroup.kMaxVirt);
    assert(get(group) + n <= 0xFF);
    final shift = group.index * 8;
    _counters += n << shift;
  }
}

/// Provides mapping that can be used to fast index architecture register groups.
class RARegIndex extends RARegCount {
  /// Build register indexes based on the given `count` of registers.
  void buildIndexes(RARegCount count) {
    assert(
        count.get(RegGroup.values[0]) + count.get(RegGroup.values[1]) <= 0xFF);
    assert(count.get(RegGroup.values[0]) +
            count.get(RegGroup.values[1]) +
            count.get(RegGroup.values[2]) <=
        0xFF);

    final i = count._counters;
    _counters = (i + (i << 8) + (i << 16)) << 8;
  }
}

/// Register masks for all virtual register groups.
class RARegMask {
  final List<int> _masks = List.filled(Globals.numVirtGroups, 0);

  /// Initializes from other `RARegMask`.
  void init(RARegMask other) {
    for (int i = 0; i < _masks.length; i++) {
      _masks[i] = other._masks[i];
    }
  }

  /// Initializes from an array of masks.
  void initFromList(List<int> masks) {
    for (int i = 0; i < _masks.length && i < masks.length; i++) {
      _masks[i] = masks[i];
    }
  }

  /// Resets all register masks to zero.
  void reset() => _masks.fillRange(0, _masks.length, 0);

  bool operator ==(Object other) {
    if (other is RARegMask) {
      for (int i = 0; i < _masks.length; i++) {
        if (_masks[i] != other._masks[i]) return false;
      }
      return true;
    }
    return false;
  }

  @override
  int get hashCode =>
      _masks.fold(0, (prev, element) => prev ^ element.hashCode);

  int operator [](RegGroup group) => _masks[group.index];
  void operator []=(RegGroup group, int value) => _masks[group.index] = value;

  /// Tests whether all register masks are zero (empty).
  bool get isEmpty {
    int agg = 0;
    for (final mask in _masks) {
      agg |= mask;
    }
    return agg == 0;
  }

  bool has(RegGroup group, [int mask = 0xFFFFFFFF]) {
    return (_masks[group.index] & mask) != 0;
  }

  void clear(RegGroup group, int mask) {
    _masks[group.index] &= ~mask;
  }

  void opOr(RARegMask other) {
    for (int i = 0; i < _masks.length; i++) {
      _masks[i] |= other._masks[i];
    }
  }

  void opAnd(RARegMask other) {
    for (int i = 0; i < _masks.length; i++) {
      _masks[i] &= other._masks[i];
    }
  }

  void opAndNot(RARegMask other) {
    for (int i = 0; i < _masks.length; i++) {
      _masks[i] &= ~other._masks[i];
    }
  }
}

/// Information associated with each instruction, propagated to blocks, loops,
/// and the whole function.
class RARegsStats {
  static const int kIndexUsed = 0;
  static const int kIndexFixed = 8;
  static const int kIndexClobbered = 16;

  static const int kMaskUsed = 0xFF << kIndexUsed;
  static const int kMaskFixed = 0xFF << kIndexFixed;
  static const int kMaskClobbered = 0xFF << kIndexClobbered;

  int _packed = 0;

  void reset() => _packed = 0;

  void combineWith(RARegsStats other) => _packed |= other._packed;

  bool get hasUsed => (_packed & kMaskUsed) != 0;
  bool hasUsedGroup(RegGroup group) =>
      support.bitTest(_packed, kIndexUsed + group.index);
  void makeUsed(RegGroup group) =>
      _packed |= support.bitMask(kIndexUsed + group.index);

  bool get hasFixed => (_packed & kMaskFixed) != 0;
  bool hasFixedGroup(RegGroup group) =>
      support.bitTest(_packed, kIndexFixed + group.index);
  void makeFixed(RegGroup group) =>
      _packed |= support.bitMask(kIndexFixed + group.index);

  bool get hasClobbered => (_packed & kMaskClobbered) != 0;
  bool hasClobberedGroup(RegGroup group) =>
      support.bitTest(_packed, kIndexClobbered + group.index);
  void makeClobbered(RegGroup group) =>
      _packed |= support.bitMask(kIndexClobbered + group.index);
}

/// Count of live registers, per group.
class RALiveCount {
  final List<int> n = List.filled(Globals.numVirtGroups, 0);

  RALiveCount();
  RALiveCount.from(RALiveCount other) {
    for (int i = 0; i < n.length; i++) {
      n[i] = other.n[i];
    }
  }

  void init(RALiveCount other) {
    for (int i = 0; i < n.length; i++) {
      n[i] = other.n[i];
    }
  }

  void reset() => n.fillRange(0, n.length, 0);

  int operator [](RegGroup group) => n[group.index];
  void operator []=(RegGroup group, int value) => n[group.index] = value;
}

/// Node position in the instruction stream.
typedef NodePosition = int;

/// Constants for NodePosition.
class NodePositionConst {
  static const NodePosition kNaN = 0;
  static const NodePosition kInf = 0xFFFFFFFF;
}

/// Span that contains start (a) and end (b).
class RALiveSpan {
  NodePosition a = 0;
  NodePosition b = 0;

  RALiveSpan([this.a = 0, this.b = 0]);

  RALiveSpan.from(RALiveSpan other)
      : a = other.a,
        b = other.b;

  void init(NodePosition first, NodePosition last) {
    a = first;
    b = last;
  }

  void initFrom(RALiveSpan other) => init(other.a, other.b);
  void reset() => init(0, 0);

  bool get isValid => a < b;
  int get width => b - a;
}

/// Vector of `RALiveSpan` with additional convenience API.
class RALiveSpans {
  final List<RALiveSpan> _data = [];

  void reset() => _data.clear();

  bool get isEmpty => _data.isEmpty;
  int get length => _data.length;

  List<RALiveSpan> get data => _data;

  bool get isOpen {
    return _data.isNotEmpty && _data.last.b == NodePositionConst.kInf;
  }

  void swap(RALiveSpans other) {
    final temp = List<RALiveSpan>.from(_data);
    _data.clear();
    _data.addAll(other._data);
    other._data.clear();
    other._data.addAll(temp);
  }

  /// Open the current live span.
  void openAt(NodePosition start, NodePosition end) {
    if (_data.isNotEmpty) {
      final last = _data.last;
      if (last.b >= start) {
        last.b = end;
        return;
      }
    }
    _data.add(RALiveSpan(start, end));
  }

  void addFrom(RALiveSpans other) {
    for (final span in other._data) {
      openAt(span.a, span.b);
    }
  }

  void closeAt(NodePosition end) {
    assert(_data.isNotEmpty);
    _data.last.b = end;
  }

  /// Returns the sum of width of all spans.
  int get totalWidth {
    int width = 0;
    for (final span in _data) {
      width += span.width;
    }
    return width;
  }

  RALiveSpan operator [](int index) => _data[index];

  bool intersects(RALiveSpans other) {
    return _intersects(this, other);
  }

  static bool _intersects(RALiveSpans x, RALiveSpans y) {
    if (x.isEmpty || y.isEmpty) return false;

    int xi = 0;
    int yi = 0;

    NodePosition xa = x._data[xi].a;

    while (true) {
      while (y._data[yi].b <= xa) {
        if (++yi >= y.length) return false;
      }

      final ya = y._data[yi].a;
      while (x._data[xi].b <= ya) {
        if (++xi >= x.length) return false;
      }

      xa = x._data[xi].a;
      if (y._data[yi].b > xa) {
        return true;
      }
    }
  }
}

/// Live bundle (RA).
///
/// A live bundle is a group of live spans that should be assigned to the same
/// physical register.
class RALiveBundle {
  int physId = RAAssignment.kPhysNone;
  double priority = 0.0;
  int spillCost = 0;

  final List<RAWorkId> workIds = [];

  void reset() {
    physId = RAAssignment.kPhysNone;
    priority = 0.0;
    spillCost = 0;
    workIds.clear();
  }

  void addWorkId(RAWorkId id) {
    if (!workIds.contains(id)) {
      workIds.add(id);
    }
  }
}

/// Statistics about a register liveness.
class RALiveStats {
  int _width = 0;
  double _freq = 0.0;
  double _priority = 0.0;

  int get width => _width;
  set width(int v) => _width = v;

  double get freq => _freq;
  set freq(double v) => _freq = v;

  double get priority => _priority;
  set priority(double v) => _priority = v;
}

/// Flags used by RATiedReg.
class RATiedFlags {
  static const int kNone = 0;

  // Access Flags
  static const int kRead = 0x00000001;
  static const int kWrite = 0x00000002;
  static const int kRW = 0x00000003;

  // Use / Out Flags
  static const int kUse = 0x00000004;
  static const int kOut = 0x00000008;
  static const int kUseRM = 0x00000010;
  static const int kOutRM = 0x00000020;

  static const int kUseFixed = 0x00000040;
  static const int kOutFixed = 0x00000080;
  static const int kUseDone = 0x00000100;
  static const int kOutDone = 0x00000200;

  // Consecutive Flags / Data
  static const int kUseConsecutive = 0x00000400;
  static const int kOutConsecutive = 0x00000800;
  static const int kLeadConsecutive = 0x00001000;
  static const int kConsecutiveData = 0x00006000;

  // Other Constraints
  static const int kUnique = 0x00008000;

  // Liveness Flags
  static const int kDuplicate = 0x00010000;
  static const int kFirst = 0x00020000;
  static const int kLast = 0x00040000;
  static const int kKill = 0x00080000;

  // X86 Specific Flags
  static const int kX86Gpb = 0x01000000;

  // Instruction Flags (Never used by RATiedReg)
  static const int kInstRegToMemPatched = 0x40000000;
  static const int kInstIsTransformable = 0x80000000;
}

/// Tied register merges one or more register operand into a single entity.
///
/// It contains information about its access (Read|Write) and allocation slots
/// (Use|Out) that are used by the register allocator and liveness analysis.
class RATiedReg {
  RAWorkReg? _workReg;
  RAWorkReg? _consecutiveParent;

  int _flags = 0;
  int _refCount = 0;
  int _rmSize = 0;
  int _useId = RAAssignment.kPhysNone;
  int _outId = RAAssignment.kPhysNone;

  int _useRegMask = 0;
  int _outRegMask = 0;
  int _useRewriteMask = 0;
  int _outRewriteMask = 0;

  void init(
    RAWorkReg workReg,
    int flags,
    int useRegMask,
    int useId,
    int useRewriteMask,
    int outRegMask,
    int outId,
    int outRewriteMask, {
    int rmSize = 0,
    RAWorkReg? consecutiveParent,
  }) {
    _workReg = workReg;
    _consecutiveParent = consecutiveParent;
    _flags = flags;
    _refCount = 1;
    _rmSize = rmSize;
    _useId = useId;
    _outId = outId;
    _useRegMask = useRegMask;
    _outRegMask = outRegMask;
    _useRewriteMask = useRewriteMask;
    _outRewriteMask = outRewriteMask;
  }

  RAWorkReg get workReg => _workReg!;

  bool get hasConsecutiveParent => _consecutiveParent != null;
  RAWorkReg? get consecutiveParent => _consecutiveParent;

  int get consecutiveData {
    const kOffsetShift = 13; // ctz(kConsecutiveData)
    return (_flags & RATiedFlags.kConsecutiveData) >> kOffsetShift;
  }

  static int consecutiveDataToFlags(int offset) {
    assert(offset < 4);
    const kOffsetShift = 13;
    return offset << kOffsetShift;
  }

  int get flags => _flags;
  bool hasFlag(int flag) => (_flags & flag) != 0;
  void addFlags(int flags) => _flags |= flags;

  bool get isRead => hasFlag(RATiedFlags.kRead);
  bool get isWrite => hasFlag(RATiedFlags.kWrite);
  bool get isReadOnly => (_flags & RATiedFlags.kRW) == RATiedFlags.kRead;
  bool get isWriteOnly => (_flags & RATiedFlags.kRW) == RATiedFlags.kWrite;
  bool get isReadWrite => (_flags & RATiedFlags.kRW) == RATiedFlags.kRW;

  bool get isUse => hasFlag(RATiedFlags.kUse);
  bool get isOut => hasFlag(RATiedFlags.kOut);
  bool get isLeadConsecutive => hasFlag(RATiedFlags.kLeadConsecutive);
  bool get isUseConsecutive => hasFlag(RATiedFlags.kUseConsecutive);
  bool get isOutConsecutive => hasFlag(RATiedFlags.kOutConsecutive);
  bool get isUnique => hasFlag(RATiedFlags.kUnique);

  bool get hasAnyConsecutiveFlag => hasFlag(RATiedFlags.kLeadConsecutive |
      RATiedFlags.kUseConsecutive |
      RATiedFlags.kOutConsecutive);

  bool get hasUseRM => hasFlag(RATiedFlags.kUseRM);
  bool get hasOutRM => hasFlag(RATiedFlags.kOutRM);
  int get rmSize => _rmSize;

  void makeReadOnly() {
    _flags =
        (_flags & ~(RATiedFlags.kOut | RATiedFlags.kWrite)) | RATiedFlags.kUse;
    _useRewriteMask |= _outRewriteMask;
    _outRewriteMask = 0;
  }

  void makeWriteOnly() {
    _flags =
        (_flags & ~(RATiedFlags.kUse | RATiedFlags.kRead)) | RATiedFlags.kOut;
    _outRewriteMask |= _useRewriteMask;
    _useRewriteMask = 0;
  }

  bool get isDuplicate => hasFlag(RATiedFlags.kDuplicate);
  bool get isFirst => hasFlag(RATiedFlags.kFirst);
  bool get isLast => hasFlag(RATiedFlags.kLast);
  bool get isKill => hasFlag(RATiedFlags.kKill);
  bool get isOutOrKill => hasFlag(RATiedFlags.kOut | RATiedFlags.kKill);

  int get useRegMask => _useRegMask;
  int get outRegMask => _outRegMask;

  int get refCount => _refCount;
  void addRefCount([int n = 1]) => _refCount += n;

  bool get hasUseId => _useId != RAAssignment.kPhysNone;
  bool get hasOutId => _outId != RAAssignment.kPhysNone;

  int get useId => _useId;
  int get outId => _outId;

  int get useRewriteMask => _useRewriteMask;
  int get outRewriteMask => _outRewriteMask;

  set useId(int value) => _useId = value;
  set outId(int value) => _outId = value;

  bool get isUseDone => hasFlag(RATiedFlags.kUseDone);
  bool get isOutDone => hasFlag(RATiedFlags.kOutDone);

  void markUseDone() => addFlags(RATiedFlags.kUseDone);
  void markOutDone() => addFlags(RATiedFlags.kOutDone);
}

/// Forward declaration - implemented in raworkreg.dart
class RAWorkReg {
  final RAWorkId _workId;
  final RegGroup _group;
  final BaseReg virtReg;

  int _homeRegId = RAAssignment.kPhysNone;
  int _allocatedMask = 0;
  int _clobberSurvivalMask = 0;
  int _flags = 0;

  final RALiveSpans _liveSpans = RALiveSpans();
  final RALiveStats _liveStats = RALiveStats();

  RAWorkReg(this._workId, this._group, this.virtReg);

  RAWorkId get workId => _workId;
  RegGroup get group => _group;

  int get homeRegId => _homeRegId;
  set homeRegId(int v) => _homeRegId = v;
  bool get hasHomeRegId => _homeRegId != RAAssignment.kPhysNone;

  int get allocatedMask => _allocatedMask;
  set allocatedMask(int v) => _allocatedMask = v;

  int get clobberSurvivalMask => _clobberSurvivalMask;
  set clobberSurvivalMask(int v) => _clobberSurvivalMask = v;

  int get flags => _flags;
  void addFlags(int flags) => _flags |= flags;
  bool hasFlag(int flag) => (_flags & flag) != 0;

  RALiveSpans get liveSpans => _liveSpans;
  RALiveStats get liveStats => _liveStats;

  bool get isWithinSingleBasicBlock =>
      hasFlag(RAWorkRegFlags.kWithinSingleBlock);

  int stackOffset = 0;

  int _bundleId = Globals.kInvalidId;
  int get bundleId => _bundleId;
  set bundleId(int v) => _bundleId = v;
  bool get hasBundle => _bundleId != Globals.kInvalidId;

  int _preferredMask = 0xFFFFFFFF;
  int get preferredMask => _preferredMask;
  void restrictPreferredMask(int mask) => _preferredMask &= mask;

  int _consecutiveMask = 0xFFFFFFFF;
  int get consecutiveMask => _consecutiveMask;
  void restrictConsecutiveMask(int mask) => _consecutiveMask &= mask;

  RAWorkReg? _consecutiveParent;
  RAWorkReg? get consecutiveParent => _consecutiveParent;

  bool _isLeadConsecutive = false;
  bool get isLeadConsecutive => _isLeadConsecutive;
  void makeLeadConsecutive() => _isLeadConsecutive = true;

  bool _isProcessedConsecutive = false;
  bool get isProcessedConsecutive => _isProcessedConsecutive;
  void markProcessedConsecutive() => _isProcessedConsecutive = true;

  final Set<int> _immediateConsecutives = {};
  Set<int> get immediateConsecutives => _immediateConsecutives;
  bool get hasImmediateConsecutives => _immediateConsecutives.isNotEmpty;
  void addImmediateConsecutive(RAWorkId id) => _immediateConsecutives.add(id);

  bool get isAllocated => hasFlag(RAWorkRegFlags.kAllocated);
  void markAllocated() => addFlags(RAWorkRegFlags.kAllocated);
  void setHomeRegId(int id) {
    _homeRegId = id;
    markAllocated();
  }

  bool get isStackSlot => hasFlag(RAWorkRegFlags.kStackSlot);
  void markStackSlot() => addFlags(RAWorkRegFlags.kStackSlot);
}

/// Flags for RAWorkReg.
class RAWorkRegFlags {
  static const int kNone = 0;
  static const int kAllocated = 1 << 0;
  static const int kStackUsed = 1 << 1;
  static const int kStackPreferred = 1 << 2;
  static const int kWithinSingleBlock = 1 << 3;
  static const int kStackArgToStack = 1 << 4;
  static const int kStackSlot = 1 << 5;
}

/// Constants for RAAssignment.
class RAAssignment {
  static const int kPhysNone = 0xFF;
  static const int kClean = 0;
  static const int kDirty = 1;
}

/// Helper for iterating over RegGroups.
Iterable<RegGroup> enumerateRegGroupsMax() sync* {
  for (int i = 0; i <= RegGroup.kMaxVirt; i++) {
    yield RegGroup.values[i];
  }
}
