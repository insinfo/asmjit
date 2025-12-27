/// AsmJit Register Allocator
///
/// A simple linear-scan register allocator for x86-64.
/// Based on concepts from asmjit's RA (register allocator).

import 'package:asmjit/asmjit.dart';

/// Virtual register - represents a value that needs a physical register.
class VirtReg extends BaseReg {
  /// Unique ID.
  @override
  final int id;

  /// Size in bytes (1, 2, 4, or 8).
  @override
  final int size;

  /// Register class (GP, XMM, YMM).
  final RegClass regClass;

  /// Assigned physical register (null if not yet assigned).
  X86Gp? physReg;

  /// Assigned XMM register (null if GP).
  X86Xmm? physXmm;

  /// First use position (instruction index).
  int firstUse = -1;

  /// Last use position (instruction index).
  int lastUse = -1;

  /// Whether this register is currently live.
  bool isLive = false;

  /// Whether this register has been spilled to memory.
  bool isSpilled = false;

  /// Stack offset if spilled.
  int spillOffset = 0;

  VirtReg(this.id, {this.size = 8, this.regClass = RegClass.gp});

  @override
  RegType get type => regClass == RegClass.gp ? RegType.gp : RegType.vec;

  @override
  RegGroup get group => regClass == RegClass.gp ? RegGroup.gp : RegGroup.vec;

  @override
  bool get isPhysical => false; // Virtual registers are not physical by default

  @override
  String toString() => 'v$id';
}

/// Register class types.
enum RegClass {
  /// General purpose registers (RAX, RBX, etc.)
  gp,

  /// SSE/AVX XMM registers
  xmm,

  /// AVX YMM registers
  ymm,

  /// AVX-512 ZMM registers
  zmm,
}

/// Live interval for a virtual register.
class LiveInterval {
  final VirtReg vreg;
  final int start;
  int end;

  LiveInterval(this.vreg, this.start, this.end);

  bool contains(int pos) => pos >= start && pos <= end;

  bool intersects(LiveInterval other) =>
      !(end < other.start || start > other.end);

  @override
  String toString() => '${vreg}@[$start..$end]';
}

/// Simple linear-scan register allocator.
///
/// This allocator uses a simplified linear-scan algorithm:
/// 1. Compute live intervals for all virtual registers
/// 2. Sort intervals by start position
/// 3. Allocate registers in order, spilling when necessary
class SimpleRegAlloc {
  /// Available GP registers for allocation.
  /// Does NOT include RSP, RBP (stack management), or platform-specific reserved regs.
  final List<X86Gp> _availableGpRegs;

  /// Available XMM registers.
  final List<X86Xmm> _availableXmmRegs;

  /// Current GP register assignments.
  final Map<X86Gp, VirtReg?> _gpAssignments = {};

  /// Current XMM register assignments.
  final Map<X86Xmm, VirtReg?> _xmmAssignments = {};

  /// All virtual registers.
  final List<VirtReg> _vregs = [];

  /// Live intervals.
  final List<LiveInterval> _intervals = [];

  /// Spill slots used.
  int _spillSlots = 0;

  /// Stack alignment (16 bytes for x86-64).
  static const int _stackAlignment = 16;

  /// Create a register allocator for the given calling convention.
  SimpleRegAlloc({bool isWin64 = false})
      : _availableGpRegs = _getAvailableGpRegs(isWin64),
        _availableXmmRegs = _getAvailableXmmRegs() {
    // Initialize assignments
    for (final reg in _availableGpRegs) {
      _gpAssignments[reg] = null;
    }
    for (final reg in _availableXmmRegs) {
      _xmmAssignments[reg] = null;
    }
  }

  /// Get available GP registers (caller-saved are preferred first).
  static List<X86Gp> _getAvailableGpRegs(bool isWin64) {
    if (isWin64) {
      // Win64: volatile = RAX, RCX, RDX, R8-R11
      // Non-volatile = RBX, RDI, RSI, R12-R15, RBP, RSP
      return [
        rax,
        rcx,
        rdx,
        r8,
        r9,
        // r11,
        rbx,
        rdi,
        rsi,
        r12,
        r13,
        r14,
        r15
      ];
    } else {
      // SysV: volatile = RAX, RCX, RDX, RSI, RDI, R8-R11
      // Non-volatile = RBX, R12-R15, RBP, RSP
      return [
        rax,
        rcx,
        rdx,
        rsi,
        rdi,
        r8,
        r9,
        // r11, // Reserved for scratch (spill resolution)
        rbx,
        r12,
        r13,
        r14,
        r15
      ];
    }
  }

  /// Get available XMM registers.
  static List<X86Xmm> _getAvailableXmmRegs() {
    return [
      xmm0,
      xmm1,
      xmm2,
      xmm3,
      xmm4,
      xmm5,
      xmm6,
      xmm7,
      xmm8,
      xmm9,
      xmm10,
      xmm11,
      xmm12,
      xmm13,
      xmm14,
      xmm15
    ];
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

  /// Compute live intervals from recorded uses.
  void computeLiveIntervals() {
    _intervals.clear();
    for (final vreg in _vregs) {
      if (vreg.firstUse >= 0 && vreg.lastUse >= 0) {
        _intervals.add(LiveInterval(vreg, vreg.firstUse, vreg.lastUse));
      }
    }
    // Sort by start position
    _intervals.sort((a, b) => a.start.compareTo(b.start));
  }

  /// Allocate registers using linear scan.
  ///
  /// If [nodes] is provided, it scans the instruction list to build live intervals.
  /// Otherwise, it assumes uses have been recorded via [recordUse].
  void allocate([NodeList? nodes]) {
    if (nodes != null) {
      _buildIntervals(nodes);
    }

    computeLiveIntervals();

    final active = <LiveInterval>[];

    for (final interval in _intervals) {
      // Expire old intervals
      _expireOldIntervals(active, interval.start);

      // Try to allocate a register
      if (interval.vreg.regClass == RegClass.gp) {
        final reg = _allocateGpReg(interval.vreg);
        if (reg != null) {
          interval.vreg.physReg = reg;
          _gpAssignments[reg] = interval.vreg;
          active.add(interval);
        } else {
          // Spill - find the longest-living active interval
          _spillRegister(interval, active);
        }
      } else if (interval.vreg.regClass == RegClass.xmm ||
          interval.vreg.regClass == RegClass.ymm ||
          interval.vreg.regClass == RegClass.zmm) {
        final reg = _allocateXmmReg(interval.vreg);
        if (reg != null) {
          interval.vreg.physXmm = reg;
          _xmmAssignments[reg] = interval.vreg;
          active.add(interval);
        } else {
          _spillXmmRegister(interval, active);
        }
      }
    }
  }

  /// Expire intervals that end before [pos].
  void _expireOldIntervals(List<LiveInterval> active, int pos) {
    active.removeWhere((interval) {
      if (interval.end < pos) {
        // Free the register
        if (interval.vreg.regClass == RegClass.gp &&
            interval.vreg.physReg != null) {
          _gpAssignments[interval.vreg.physReg!] = null;
        } else if (interval.vreg.physXmm != null) {
          _xmmAssignments[interval.vreg.physXmm!] = null;
        }
        return true;
      }
      return false;
    });
  }

  /// Try to allocate a GP register.
  X86Gp? _allocateGpReg(VirtReg vreg) {
    for (final reg in _availableGpRegs) {
      if (_gpAssignments[reg] == null) {
        return reg;
      }
    }
    return null;
  }

  /// Try to allocate an XMM register.
  X86Xmm? _allocateXmmReg(VirtReg vreg) {
    for (final reg in _availableXmmRegs) {
      if (_xmmAssignments[reg] == null) {
        return reg;
      }
    }
    return null;
  }

  /// Spill a GP register when all are in use.
  void _spillRegister(LiveInterval newInterval, List<LiveInterval> active) {
    // Find the interval with the longest remaining lifetime
    LiveInterval? longest;
    for (final interval in active) {
      if (interval.vreg.regClass == RegClass.gp) {
        if (longest == null || interval.end > longest.end) {
          longest = interval;
        }
      }
    }

    if (longest != null && longest.end > newInterval.end) {
      // Spill the longest interval
      final spilledReg = longest.vreg.physReg!;
      longest.vreg.isSpilled = true;
      longest.vreg.spillOffset = _allocSpillSlot();
      longest.vreg.physReg = null;

      // Assign to new interval
      newInterval.vreg.physReg = spilledReg;
      _gpAssignments[spilledReg] = newInterval.vreg;
      active.remove(longest);
      active.add(newInterval);
    } else {
      // Spill the new interval
      newInterval.vreg.isSpilled = true;
      newInterval.vreg.spillOffset = _allocSpillSlot();
    }
  }

  /// Spill an XMM register.
  void _spillXmmRegister(LiveInterval newInterval, List<LiveInterval> active) {
    LiveInterval? longest;
    for (final interval in active) {
      if (interval.vreg.regClass == RegClass.xmm ||
          interval.vreg.regClass == RegClass.ymm ||
          interval.vreg.regClass == RegClass.zmm) {
        if (longest == null || interval.end > longest.end) {
          longest = interval;
        }
      }
    }

    if (longest != null && longest.end > newInterval.end) {
      final spilledReg = longest.vreg.physXmm!;
      longest.vreg.isSpilled = true;
      longest.vreg.spillOffset = _allocSpillSlot();
      longest.vreg.physXmm = null;

      newInterval.vreg.physXmm = spilledReg;
      _xmmAssignments[spilledReg] = newInterval.vreg;
      active.remove(longest);
      active.add(newInterval);
    } else {
      newInterval.vreg.isSpilled = true;
      newInterval.vreg.spillOffset = _allocSpillSlot();
    }
  }

  /// Allocate a spill slot on the stack.
  int _allocSpillSlot() {
    final offset = _spillSlots * 8; // 8 bytes per slot
    _spillSlots++;
    return offset;
  }

  /// Get the total spill area size (aligned).
  int get spillAreaSize {
    if (_spillSlots == 0) return 0;
    final size = _spillSlots * 8;
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
    _spillSlots = 0;
    for (final reg in _availableGpRegs) {
      _gpAssignments[reg] = null;
    }
    for (final reg in _availableXmmRegs) {
      _xmmAssignments[reg] = null;
    }
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('SimpleRegAlloc:');
    sb.writeln('  Virtual registers: ${_vregs.length}');
    sb.writeln('  Live intervals: ${_intervals.length}');
    sb.writeln('  Spill slots: $_spillSlots');
    sb.writeln('  Spillarea size: $spillAreaSize bytes');
    for (final vreg in _vregs) {
      final reg = vreg.physReg ?? vreg.physXmm;
      final status = vreg.isSpilled
          ? 'spilled@${vreg.spillOffset}'
          : reg?.toString() ?? 'unassigned';
      sb.writeln('    $vreg -> $status');
    }
    return sb.toString();
  }

  /// Build intervals by iterating over the node list.
  void _buildIntervals(NodeList nodes) {
    int pos = 0;

    for (final node in nodes.nodes) {
      if (node is InstNode) {
        for (final op in node.operands) {
          if (op is RegOperand) {
            final reg = op.reg;
            if (reg is VirtReg) {
              recordUse(reg, pos);
            }
          } else if (op is MemOperand) {
            // Handle memory operands that use virtual registers
            // This requires MemOperand definition inspection.
            // Assuming MemOperand might contain VirtReg in index/base.
            // For now, complex memory operand reg alloc might need more work if MemOperand stores BaseReg.
            // check if op.mem is BaseMem, and check base/index.
            _scanMemOperand(op, pos);
          }
        }
        pos +=
            2; // Increment by 2 to allow for insertion between instructions if needed (standard RA trick)
      }
    }
  }

  void _scanMemOperand(MemOperand op, int pos) {
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
}
