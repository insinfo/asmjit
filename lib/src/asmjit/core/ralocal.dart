// This file is part of AsmJit project <https://asmjit.com>
//
// See <asmjit/core.h> or LICENSE.md for license and copyright information
// SPDX-License-Identifier: Zlib

/// Local Register Allocator
///
/// Implements the local register allocation algorithm used by AsmJit.
/// Ported faithfully from the C++ implementation in ralocal.cpp.

import 'arch.dart';
import 'error.dart';
import 'operand.dart' show RegGroup;
import 'radefs.dart';
import 'raassignment.dart';
import 'support.dart' as support;

/// Cost model constants for spill decisions.
class CostModel {
  static const int kCostOfFrequency = 1048576;
  static const int kCostOfDirtyFlag = kCostOfFrequency ~/ 4;
}

/// Local register allocator.
///
/// This allocator handles register assignment within a single basic block,
/// performing moves, swaps, loads, saves, and spills as needed to satisfy
/// instruction constraints.
class RALocalAllocator {
  /// Architecture traits.
  ArchTraits? _archTraits;

  /// Registers available to the allocator.
  final RARegMask _availableRegs = RARegMask();

  /// Registers clobbered by the allocator.
  final RARegMask _clobberedRegs = RARegMask();

  /// Registers that must be preserved by the function.
  final RARegMask _funcPreservedRegs = RARegMask();

  /// Register assignment (current).
  final RAAssignmentState _curAssignment = RAAssignmentState();

  /// Register assignment used temporarily during assignment switches.
  final RAAssignmentState _tmpAssignment = RAAssignmentState();

  /// Temporary work_to_phys_map for assignment switches (reserved for future use).
  // ignore: unused_field
  WorkToPhysMap? _tmpWorkToPhysMap;

  /// Count of all TiedReg's (reserved for future use).
  // ignore: unused_field
  int _tiedTotal = 0;

  /// TiedReg's total counter per group.
  final RARegCount _tiedCount = RARegCount();

  /// All work registers.
  final List<RAWorkReg> _workRegs = [];

  /// Physical register count per group.
  final RARegCount _physRegCount = RARegCount();

  RALocalAllocator();

  /// Initialize the allocator for a given architecture.
  AsmJitError init(
      Arch arch, RARegMask availableRegs, RARegMask preservedRegs) {
    _archTraits = ArchTraits.forArch(arch);
    _availableRegs.init(availableRegs);
    _funcPreservedRegs.init(preservedRegs);
    _clobberedRegs.reset();

    // Initialize physical register counts based on architecture
    for (final group in enumerateRegGroupsMax()) {
      final count = support.popcnt(availableRegs[group]);
      _physRegCount.set(group, count);
    }

    return _initMaps();
  }

  AsmJitError _initMaps() {
    final physTotal = _physRegCount.get(RegGroup.values[0]) +
        _physRegCount.get(RegGroup.values[1]) +
        _physRegCount.get(RegGroup.values[2]) +
        _physRegCount.get(RegGroup.values[3]);

    final physToWorkMap = PhysToWorkMap(physTotal);
    final workToPhysMap = WorkToPhysMap(_workRegs.length);

    _curAssignment.initLayout(_physRegCount, _workRegs);
    _curAssignment.initMaps(physToWorkMap, workToPhysMap);

    final tmpPhysToWork = PhysToWorkMap(physTotal);
    final tmpWorkToPhys = WorkToPhysMap(_workRegs.length);
    _tmpWorkToPhysMap = WorkToPhysMap(_workRegs.length);

    _tmpAssignment.initLayout(_physRegCount, _workRegs);
    _tmpAssignment.initMaps(tmpPhysToWork, tmpWorkToPhys);

    return AsmJitError.ok;
  }

  /// Get a work register by ID.
  RAWorkReg workRegById(RAWorkId workId) => _workRegs[workId];

  /// Get the physics-to-work map.
  PhysToWorkMap? get physToWorkMap => _curAssignment.physToWorkMap;

  /// Get the work-to-physics map.
  WorkToPhysMap? get workToPhysMap => _curAssignment.workToPhysMap;

  /// Cost calculation based on frequency.
  int costByFrequency(double freq) {
    return (freq * CostModel.kCostOfFrequency).toInt();
  }

  /// Calculate spill cost for a register.
  int calcSpillCost(RegGroup group, RAWorkReg workReg, int assignedId) {
    int cost = costByFrequency(workReg.liveStats.freq);

    if (_curAssignment.isPhysDirty(group, assignedId)) {
      cost += CostModel.kCostOfDirtyFlag;
    }

    return cost;
  }

  /// Pick the best suitable register from allocable mask.
  int pickBestSuitableRegister(RegGroup group, int allocableRegs) {
    // These are registers that must be preserved by the function itself.
    final preservedRegs = _funcPreservedRegs[group];

    // Reduce the set by removing preserved registers when possible.
    final nonPreserved = allocableRegs & ~preservedRegs;
    if (nonPreserved != 0) {
      allocableRegs = nonPreserved;
    }

    return support.ctz(allocableRegs);
  }

  /// Decides on register assignment.
  int decideOnAssignment(
      RegGroup group, RAWorkReg workReg, int physId, int allocableRegs) {
    assert(allocableRegs != 0);

    // Prefer home register id, if possible.
    if (workReg.hasHomeRegId) {
      final homeId = workReg.homeRegId;
      if (support.bitTest(allocableRegs, homeId)) {
        return homeId;
      }
    }

    // Prefer registers used upon block entries.
    final previouslyAssignedRegs = workReg.allocatedMask;
    if ((allocableRegs & previouslyAssignedRegs) != 0) {
      allocableRegs &= previouslyAssignedRegs;
    }

    return pickBestSuitableRegister(group, allocableRegs);
  }

  /// Decides on whether to MOVE or SPILL the given WorkReg.
  ///
  /// Returns either `kPhysNone` (spill) or a valid physical register ID (move).
  int decideOnReassignment(RegGroup group, RAWorkReg workReg, int physId,
      int allocableRegs, List<RATiedReg>? raInst) {
    assert(allocableRegs != 0);

    // Prefer reassignment back to HomeId, if possible.
    if (workReg.hasHomeRegId) {
      if (support.bitTest(allocableRegs, workReg.homeRegId)) {
        return workReg.homeRegId;
      }
    }

    // Prefer assignment to a temporary register in case this register is
    // killed by the instruction (or has an out slot).
    if (raInst != null) {
      final tiedReg = _findTiedRegForWorkReg(raInst, group, workReg);
      if (tiedReg != null && tiedReg.isOutOrKill) {
        return support.ctz(allocableRegs);
      }
    }

    // Prefer reassignment if this register is only used within a single basic block.
    if (workReg.isWithinSingleBasicBlock) {
      final filteredRegs = allocableRegs & ~workReg.clobberSurvivalMask;
      if (filteredRegs != 0) {
        return pickBestSuitableRegister(group, filteredRegs);
      }
    }

    // Decided to SPILL.
    return RAAssignment.kPhysNone;
  }

  /// Decides on best spill given a register mask.
  (int, RAWorkId) decideOnSpillFor(
      RegGroup group, RAWorkReg workReg, int spillableRegs) {
    assert(spillableRegs != 0);

    int mask = spillableRegs;
    int bestPhysId = support.ctz(mask);
    mask &= mask - 1;

    RAWorkId bestWorkId = _curAssignment.physToWorkId(group, bestPhysId);

    // Avoid calculating the cost model if there is only one spillable register.
    if (mask != 0) {
      int bestCost = calcSpillCost(group, workRegById(bestWorkId), bestPhysId);

      while (mask != 0) {
        final localPhysId = support.ctz(mask);
        mask &= mask - 1;

        final localWorkId = _curAssignment.physToWorkId(group, localPhysId);
        final localCost =
            calcSpillCost(group, workRegById(localWorkId), localPhysId);

        if (localCost < bestCost) {
          bestCost = localCost;
          bestPhysId = localPhysId;
          bestWorkId = localWorkId;
        }
      }
    }

    return (bestPhysId, bestWorkId);
  }

  RATiedReg? _findTiedRegForWorkReg(
      List<RATiedReg> tiedRegs, RegGroup group, RAWorkReg workReg) {
    for (final tied in tiedRegs) {
      if (tied.workReg == workReg) {
        return tied;
      }
    }
    return null;
  }

  // ============================================================================
  // Assignment Operations
  // ============================================================================

  /// Assigns a register, the content is undefined at this point.
  AsmJitError assignReg(
      RegGroup group, RAWorkId workId, int physId, bool dirty) {
    _curAssignment.assign(group, workId, physId, dirty);
    return AsmJitError.ok;
  }

  /// Unassigns a register.
  void unassignReg(RegGroup group, RAWorkId workId, int physId) {
    _curAssignment.unassign(group, workId, physId);
  }

  /// Emits a load from spill slot to physical register and makes it assigned and clean.
  AsmJitError onLoadReg(
    RegGroup group,
    RAWorkReg workReg,
    RAWorkId workId,
    int physId,
    void Function(RAWorkReg workReg, int physId) emitLoad,
  ) {
    _curAssignment.assign(group, workId, physId, false);
    emitLoad(workReg, physId);
    return AsmJitError.ok;
  }

  /// Emits a save from physical register to spill slot, keeps it assigned, makes it clean.
  AsmJitError onSaveReg(
    RegGroup group,
    RAWorkReg workReg,
    RAWorkId workId,
    int physId,
    void Function(RAWorkReg workReg, int physId) emitSave,
  ) {
    assert(_curAssignment.workToPhysId(group, workId) == physId);
    assert(_curAssignment.physToWorkId(group, physId) == workId);

    _curAssignment.makeClean(group, workId, physId);
    emitSave(workReg, physId);
    return AsmJitError.ok;
  }

  /// Emits a move between registers and fixes the register assignment.
  AsmJitError onMoveReg(
    RegGroup group,
    RAWorkReg workReg,
    RAWorkId workId,
    int dstPhysId,
    int srcPhysId,
    void Function(RAWorkReg workReg, int dstPhysId, int srcPhysId) emitMove,
  ) {
    if (dstPhysId == srcPhysId) {
      return AsmJitError.ok;
    }

    _curAssignment.reassign(group, workId, dstPhysId, srcPhysId);
    emitMove(workReg, dstPhysId, srcPhysId);
    return AsmJitError.ok;
  }

  /// Spills a variable/register, saves the content to memory-home if modified.
  AsmJitError onSpillReg(
    RegGroup group,
    RAWorkReg workReg,
    RAWorkId workId,
    int physId,
    void Function(RAWorkReg workReg, int physId) emitSave,
  ) {
    if (_curAssignment.isPhysDirty(group, physId)) {
      final err = onSaveReg(group, workReg, workId, physId, emitSave);
      if (err != AsmJitError.ok) return err;
    }
    unassignReg(group, workId, physId);
    return AsmJitError.ok;
  }

  /// Emits a swap between two physical registers and fixes their assignment.
  AsmJitError onSwapReg(
    RegGroup group,
    RAWorkReg aReg,
    RAWorkId aWorkId,
    int aPhysId,
    RAWorkReg bReg,
    RAWorkId bWorkId,
    int bPhysId,
    void Function(RAWorkReg aReg, int aPhysId, RAWorkReg bReg, int bPhysId)
        emitSwap,
  ) {
    _curAssignment.swap(group, aWorkId, aPhysId, bWorkId, bPhysId);
    emitSwap(aReg, aPhysId, bReg, bPhysId);
    return AsmJitError.ok;
  }

  // ============================================================================
  // Instruction Allocation
  // ============================================================================

  /// Main allocation entry point for a single instruction.
  ///
  /// This is the core algorithm that:
  /// 1. Calculates will_use and will_free masks based on tied registers
  /// 2. Handles consecutive register requirements
  /// 3. Decides on assignments for USE registers
  /// 4. Frees registers that need to be freed
  /// 5. Allocates/shuffles USE registers
  /// 6. Kills OUT/KILL registers
  /// 7. Spills CLOBBERED registers
  /// 8. Handles duplication
  /// 9. Assigns OUT registers
  AsmJitError allocInstruction({
    required List<RATiedReg> tiedRegs,
    required RARegMask usedRegs,
    required RARegMask clobberedRegs,
    required void Function(RAWorkReg, int) emitLoad,
    required void Function(RAWorkReg, int) emitSave,
    required void Function(RAWorkReg, int, int) emitMove,
    required void Function(RAWorkReg, int, RAWorkReg, int) emitSwap,
  }) {
    final outTiedRegs = <RATiedReg>[];
    final dupTiedRegs = <RATiedReg>[];
    final consecutiveRegs = List<RATiedReg?>.filled(kMaxConsecutiveRegs, null);

    _tiedTotal = tiedRegs.length;
    _tiedCount.reset();

    for (final group in enumerateRegGroupsMax()) {
      final groupTied =
          tiedRegs.where((t) => t.workReg.group == group).toList();
      final count = groupTied.length;
      _tiedCount.set(group, count);

      int willUse = usedRegs[group];
      int willOut = clobberedRegs[group];
      int willFree = 0;

      int usePendingCount = count;
      int outTiedCount = 0;
      int consecutiveMask = 0;

      outTiedRegs.clear();
      dupTiedRegs.clear();
      for (int i = 0; i < kMaxConsecutiveRegs; i++) {
        consecutiveRegs[i] = null;
      }

      // STEP 1: Calculate willUse and willFree masks
      for (int i = 0; i < count; i++) {
        final tiedReg = groupTied[i];

        if (tiedReg.hasAnyConsecutiveFlag) {
          final consecutiveOffset =
              tiedReg.isLeadConsecutive ? 0 : tiedReg.consecutiveData;

          if (support.bitTest(consecutiveMask, consecutiveOffset)) {
            return AsmJitError.invalidState;
          }

          consecutiveMask |= support.bitMask(consecutiveOffset);
          consecutiveRegs[consecutiveOffset] = tiedReg;
        }

        if (tiedReg.isOutOrKill) {
          outTiedRegs.add(tiedReg);
          outTiedCount++;
        }

        if (tiedReg.isDuplicate) {
          dupTiedRegs.add(tiedReg);
        }

        if (!tiedReg.isUse) {
          tiedReg.markUseDone();
          usePendingCount--;
          continue;
        }

        if (tiedReg.isUseConsecutive) {
          continue;
        }

        final workReg = tiedReg.workReg;
        final workId = workReg.workId;
        final assignedId = _curAssignment.workToPhysId(group, workId);

        if (tiedReg.hasUseId) {
          final useMask = support.bitMask(tiedReg.useId);

          if (assignedId == tiedReg.useId) {
            tiedReg.markUseDone();
            if (tiedReg.isWrite) {
              _curAssignment.makeDirty(group, workId, assignedId);
            }
            usePendingCount--;
            willUse |= useMask;
          } else {
            willFree |= useMask & _curAssignment.assignedGroup(group);
          }
        } else {
          final allocableRegs = tiedReg.useRegMask;
          if (assignedId != RAAssignment.kPhysNone) {
            final assignedMask = support.bitMask(assignedId);
            if ((allocableRegs & ~willUse) & assignedMask != 0) {
              tiedReg.useId = assignedId;
              tiedReg.markUseDone();
              if (tiedReg.isWrite) {
                _curAssignment.makeDirty(group, workId, assignedId);
              }
              usePendingCount--;
              willUse |= assignedMask;
            } else {
              willFree |= assignedMask;
            }
          }
        }
      }

      // STEP 2: Verify consecutive registers
      int consecutiveCount = 0;
      if (consecutiveMask != 0) {
        if ((consecutiveMask & (consecutiveMask + 1)) != 0) {
          return AsmJitError.invalidState;
        }
        consecutiveCount = support.ctz(~consecutiveMask);

        final lead = consecutiveRegs[0];
        if (lead != null && lead.isUseConsecutive) {
          int bestScore = 0;
          int bestLeadReg = 0xFFFFFFFF;
          int allocableRegs = (_availableRegs[group] | willFree) & ~willUse;

          final assignments = List<int>.filled(kMaxConsecutiveRegs, 0);
          for (int i = 0; i < consecutiveCount; i++) {
            assignments[i] = _curAssignment.workToPhysId(
                group, consecutiveRegs[i]!.workReg.workId);
          }

          int mask = lead.useRegMask;
          while (mask != 0) {
            final regIndex = support.ctz(mask);
            mask &= mask - 1;

            int score = 15;
            for (int i = 0; i < consecutiveCount; i++) {
              final consecutiveIndex = regIndex + i;
              if (!support.bitTest(allocableRegs, consecutiveIndex)) {
                score = 0;
                break;
              }

              final workReg = consecutiveRegs[i]!.workReg;
              score += (workReg.homeRegId == consecutiveIndex) ? 1 : 0;
              score += (assignments[i] == consecutiveIndex) ? 2 : 0;
            }

            if (score > bestScore) {
              bestScore = score;
              bestLeadReg = regIndex;
            }
          }

          if (bestLeadReg == 0xFFFFFFFF) {
            return AsmJitError.invalidAssignment;
          }

          for (int i = 0; i < consecutiveCount; i++) {
            final consecutiveIndex = bestLeadReg + i;
            final tiedReg = consecutiveRegs[i]!;
            final useMask = support.bitMask(consecutiveIndex);

            final workReg = tiedReg.workReg;
            final workId = workReg.workId;
            final assignedId = _curAssignment.workToPhysId(group, workId);

            tiedReg.useId = consecutiveIndex;

            if (assignedId == consecutiveIndex) {
              tiedReg.markUseDone();
              if (tiedReg.isWrite) {
                _curAssignment.makeDirty(group, workId, assignedId);
              }
              usePendingCount--;
              willUse |= useMask;
            } else {
              willUse |= useMask;
              willFree |= useMask & _curAssignment.assignedGroup(group);
            }
          }
        }
      }

      // STEP 3: Decision making for assignments
      if (usePendingCount > 0) {
        int liveRegs = _curAssignment.assignedGroup(group) & ~willFree;

        for (int i = 0; i < count; i++) {
          final tiedReg = groupTied[i];
          if (tiedReg.isUseDone) continue;

          final workReg = tiedReg.workReg;
          final workId = workReg.workId;
          final assignedId = _curAssignment.workToPhysId(group, workId);

          if (!tiedReg.hasUseId) {
            final allocableRegs = tiedReg.useRegMask & ~(willFree | willUse);
            final useId =
                decideOnAssignment(group, workReg, assignedId, allocableRegs);

            final useMask = support.bitMask(useId);
            willUse |= useMask;
            willFree |= useMask & liveRegs;
            tiedReg.useId = useId;

            if (assignedId != RAAssignment.kPhysNone) {
              final assignedMask = support.bitMask(assignedId);
              willFree |= assignedMask;
              liveRegs &= ~assignedMask;

              if ((liveRegs & useMask) == 0) {
                final err = onMoveReg(
                    group, workReg, workId, useId, assignedId, emitMove);
                if (err != AsmJitError.ok) return err;

                tiedReg.markUseDone();
                if (tiedReg.isWrite) {
                  _curAssignment.makeDirty(group, workId, useId);
                }
                usePendingCount--;
              }
            } else {
              if ((liveRegs & useMask) == 0) {
                final err = onLoadReg(group, workReg, workId, useId, emitLoad);
                if (err != AsmJitError.ok) return err;

                tiedReg.markUseDone();
                if (tiedReg.isWrite) {
                  _curAssignment.makeDirty(group, workId, useId);
                }
                usePendingCount--;
              }
            }

            liveRegs |= useMask;
          }
        }
      }

      int clobberedByInst = willUse | willOut;

      // STEP 4: Free registers marked as willFree
      if (willFree != 0) {
        int allocableRegs = _availableRegs[group] &
            ~(_curAssignment.assignedGroup(group) |
                willFree |
                willUse |
                willOut);

        int mask = willFree;
        while (mask != 0) {
          final assignedId = support.ctz(mask);
          mask &= mask - 1;

          if (_curAssignment.isPhysAssigned(group, assignedId)) {
            final workId = _curAssignment.physToWorkId(group, assignedId);
            final workReg = workRegById(workId);

            if (allocableRegs != 0) {
              final reassignedId = decideOnReassignment(
                  group, workReg, assignedId, allocableRegs, groupTied);
              if (reassignedId != RAAssignment.kPhysNone) {
                final err = onMoveReg(
                    group, workReg, workId, reassignedId, assignedId, emitMove);
                if (err != AsmJitError.ok) return err;

                allocableRegs ^= support.bitMask(reassignedId);
                _clobberedRegs[group] |= support.bitMask(reassignedId);
                continue;
              }
            }

            final err =
                onSpillReg(group, workReg, workId, assignedId, emitSave);
            if (err != AsmJitError.ok) return err;
          }
        }
      }

      // STEP 5: Allocate/shuffle USE registers
      if (usePendingCount > 0) {
        bool mustSwap = false;
        while (usePendingCount > 0) {
          int oldPendingCount = usePendingCount;

          for (int i = 0; i < count; i++) {
            final thisTiedReg = groupTied[i];
            if (thisTiedReg.isUseDone) continue;

            final thisWorkReg = thisTiedReg.workReg;
            final thisWorkId = thisWorkReg.workId;
            final thisPhysId = _curAssignment.workToPhysId(group, thisWorkId);

            final targetPhysId = thisTiedReg.useId;
            assert(targetPhysId != thisPhysId);

            final targetWorkId =
                _curAssignment.physToWorkId(group, targetPhysId);

            if (targetWorkId != kBadWorkId) {
              final targetWorkReg = workRegById(targetWorkId);

              if (_archTraits!.hasRegSwap(group) &&
                  thisPhysId != RAAssignment.kPhysNone) {
                final err = onSwapReg(
                  group,
                  thisWorkReg,
                  thisWorkId,
                  thisPhysId,
                  targetWorkReg,
                  targetWorkId,
                  targetPhysId,
                  emitSwap,
                );
                if (err != AsmJitError.ok) return err;

                thisTiedReg.markUseDone();
                if (thisTiedReg.isWrite) {
                  _curAssignment.makeDirty(group, thisWorkId, targetPhysId);
                }
                usePendingCount--;

                // Double-hit
                final targetTiedReg =
                    _findTiedRegForWorkReg(groupTied, group, targetWorkReg);
                if (targetTiedReg != null &&
                    targetTiedReg.useId == thisPhysId) {
                  targetTiedReg.markUseDone();
                  if (targetTiedReg.isWrite) {
                    _curAssignment.makeDirty(group, targetWorkId, thisPhysId);
                  }
                  usePendingCount--;
                }
                continue;
              }

              if (!mustSwap) continue;

              // Fallback: Move to temp or spill
              int availableRegs =
                  _availableRegs[group] & ~_curAssignment.assignedGroup(group);
              if (availableRegs != 0) {
                final tmpRegId = pickBestSuitableRegister(group, availableRegs);
                final err = onMoveReg(group, thisWorkReg, thisWorkId, tmpRegId,
                    thisPhysId, emitMove);
                if (err != AsmJitError.ok) return err;

                _clobberedRegs[group] |= support.bitMask(tmpRegId);
                break;
              }

              final err = onSpillReg(
                  group, targetWorkReg, targetWorkId, targetPhysId, emitSave);
              if (err != AsmJitError.ok) return err;
            }

            if (thisPhysId != RAAssignment.kPhysNone) {
              final err = onMoveReg(group, thisWorkReg, thisWorkId,
                  targetPhysId, thisPhysId, emitMove);
              if (err != AsmJitError.ok) return err;

              thisTiedReg.markUseDone();
              if (thisTiedReg.isWrite) {
                _curAssignment.makeDirty(group, thisWorkId, targetPhysId);
              }
              usePendingCount--;
            } else {
              final err = onLoadReg(
                  group, thisWorkReg, thisWorkId, targetPhysId, emitLoad);
              if (err != AsmJitError.ok) return err;

              thisTiedReg.markUseDone();
              if (thisTiedReg.isWrite) {
                _curAssignment.makeDirty(group, thisWorkId, targetPhysId);
              }
              usePendingCount--;
            }
          }

          mustSwap = (oldPendingCount == usePendingCount);
        }
      }

      // STEP 6: Kill OUT/KILL registers
      int outPendingCount = outTiedCount;
      if (outTiedCount > 0) {
        for (final tiedReg in outTiedRegs) {
          final workReg = tiedReg.workReg;
          final workId = workReg.workId;
          final physId = _curAssignment.workToPhysId(group, workId);

          if (physId != RAAssignment.kPhysNone) {
            unassignReg(group, workId, physId);
            willOut &= ~support.bitMask(physId);
          }

          outPendingCount -= tiedReg.isOut ? 0 : 1;
        }
      }

      // STEP 7: Spill CLOBBERED registers
      if (willOut != 0) {
        int mask = willOut;
        while (mask != 0) {
          final physId = support.ctz(mask);
          mask &= mask - 1;

          final workId = _curAssignment.physToWorkId(group, physId);
          if (workId == kBadWorkId) continue;

          final err =
              onSpillReg(group, workRegById(workId), workId, physId, emitSave);
          if (err != AsmJitError.ok) return err;
        }
      }

      // STEP 8: Duplication (skipped in this simplified version)

      // STEP 9: Assign OUT registers
      if (outPendingCount > 0) {
        int liveRegs = _curAssignment.assignedGroup(group);
        int outRegs = 0;
        int avoidRegs = willUse & ~clobberedByInst;

        for (final tiedReg in outTiedRegs) {
          if (!tiedReg.isOut) continue;

          int avoidOut = avoidRegs;
          if (tiedReg.isUnique) {
            avoidOut |= willUse;
          }

          final workReg = tiedReg.workReg;
          final workId = workReg.workId;
          final assignedId = _curAssignment.workToPhysId(group, workId);

          if (assignedId != RAAssignment.kPhysNone) {
            unassignReg(group, workId, assignedId);
          }

          int physId = tiedReg.outId;
          if (physId == RAAssignment.kPhysNone) {
            int allocableRegs = tiedReg.outRegMask & ~(outRegs | avoidOut);

            if ((allocableRegs & ~liveRegs) == 0) {
              final (spillPhysId, spillWorkId) =
                  decideOnSpillFor(group, workReg, allocableRegs & liveRegs);
              final err = onSpillReg(group, workRegById(spillWorkId),
                  spillWorkId, spillPhysId, emitSave);
              if (err != AsmJitError.ok) return err;
              physId = spillPhysId;
            } else {
              physId = decideOnAssignment(group, workReg,
                  RAAssignment.kPhysNone, allocableRegs & ~liveRegs);
            }
          }

          assert(!_curAssignment.isPhysAssigned(group, physId));

          if (!tiedReg.isKill) {
            final err = assignReg(group, workId, physId, true);
            if (err != AsmJitError.ok) return err;
          }

          tiedReg.outId = physId;
          tiedReg.markOutDone();

          outRegs |= support.bitMask(physId);
          liveRegs &= ~support.bitMask(physId);
          outPendingCount--;
        }

        clobberedByInst |= outRegs;
        assert(outPendingCount == 0);
      }

      _clobberedRegs[group] |= clobberedByInst;
    }

    return AsmJitError.ok;
  }

  /// Replace the current assignment with a new one.
  AsmJitError replaceAssignment(PhysToWorkMap physToWorkMap) {
    _curAssignment.copyFromPhysToWork(physToWorkMap);
    return AsmJitError.ok;
  }

  /// Get clobbered registers.
  RARegMask get clobberedRegs => _clobberedRegs;

  /// Get available registers.
  RARegMask get availableRegs => _availableRegs;

  /// Add a work register.
  RAWorkReg addWorkReg(RegGroup group) {
    final workId = _workRegs.length;
    final workReg = RAWorkReg(workId, group);
    _workRegs.add(workReg);
    return workReg;
  }

  /// Get all work registers.
  List<RAWorkReg> get workRegs => _workRegs;

  /// Reset the allocator.
  void reset() {
    _workRegs.clear();
    _clobberedRegs.reset();
    _tiedTotal = 0;
    _tiedCount.reset();
  }
}
