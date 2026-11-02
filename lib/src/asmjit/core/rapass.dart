//C:\MyDartProjects\asmjit\lib\src\asmjit\core\rapass.dart
/// AsmJit Register Allocation Pass
///
/// Implements `RAPass`, which drives the register allocation process.
/// It uses `RALocalAllocator` for local allocation and handles block ordering,
/// function frames, and instruction processing.
///
/// Ported from asmjit/core/rapass.cpp

import 'dart:io';
import 'arch.dart';
import 'error.dart';
import 'compiler.dart';
import 'globals.dart'; // Needed for Globals.kNumVirtGroups
import 'radefs.dart';
import 'ralocal.dart';
import 'bitvector.dart';
import 'ranode_data.dart';
import 'raarch.dart';
import 'raassignment.dart';

class _RAConsecutiveReg {
  final RAWorkReg workReg;
  final RAWorkReg? parentReg;
  _RAConsecutiveReg(this.workReg, this.parentReg);
}

class _RACoalesceCandidate {
  final RAWorkId a;
  final RAWorkId b;
  _RACoalesceCandidate(this.a, this.b);
}

/// Register Allocation Pass.
///
/// This pass performs register allocation on the function. It currently
/// supports local register allocation (RAPass::kLocal).
class RAPass extends CompilerPass {
  /// Enables verbose register-allocation logging (`ASMJIT_RA_DEBUG=1`).
  static final bool debugLog = Platform.environment['ASMJIT_RA_DEBUG'] == '1';

  final RALocalAllocator _allocator = RALocalAllocator();

  /// Architecture-specific hooks (instruction analysis, emission, frame).
  final RAArch _arch;

  // Map from Virtual Register ID to RAWorkId
  final Map<int, RAWorkId> _virtIdToWorkId = {};

  // Arch traits (cached).
  late ArchTraits _archTraits;

  // Current function being compiled.
  FuncNode? _func;

  // Liveness info (block-local)
  final Map<int, int> _lastUsePos = {};

  // Global Liveness data
  final Map<int, RABlockData> _blockData = {};
  int _numWorkRegs = 0;

  final List<RALiveBundle> _bundles = [];
  final List<_RACoalesceCandidate> _coalescingCandidates = [];

  RAPass(BaseCompiler compiler, [RAArch? arch])
      : _arch = arch ?? compiler.createRAArch(),
        super(compiler);

  @override
  void run(NodeList nodes) {
    // 1. Initialize
    final compiler = super.compiler;
    _archTraits = ArchTraits.forArch(
        compiler.arch); // Assuming compiler has arch property

    // As `FuncPass::run()`: every function is allocated on its own, with
    // a fresh pass state (`run_on_function()`).
    final funcs = [
      for (final node in nodes.nodes)
        if (node is FuncNode) node
    ];
    for (final func in funcs) {
      final pass = RAPass(compiler, _arch).._archTraits = _archTraits;
      pass._processFunction(func, NodeRange(func, func.end ?? nodes.last!));
    }
  }

  void _processFunction(FuncNode func, NodeList nodes) {
    _func = func;
    _spillStackSize = 0; // Reset for new function

    // 2. Initialize Allocator
    // We need availableRegs and preservedRegs.
    // Ideally these come from the Compiler/Arch.
    // For now hardcoding based on arch traits or FuncFrame.

    RARegMask availableRegs = RARegMask();
    RARegMask preservedRegs = RARegMask();

    // Fill masks from ArchTraits/ABI
    // Ideally these come from internal DB or Compiler state.
    _initRegMasks(availableRegs, preservedRegs);

    // 2a. Map Virtual Registers (Pre-pass)
    _mapVirtuals(nodes);

    // 2b. Assign Arguments to WorkRegs (Hints)
    _assignArgIndexToWorkRegs(func);

    // [FIX] Insert Arg Moves BEFORE Liveness Analysis
    BlockNode? firstBlock;
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        firstBlock = node;
        break;
      }
    }
    if (firstBlock != null) {
      _insertArgMoves(firstBlock);
    }

    // 2c. Global Allocation (RAGlobal)
    _buildGlobalLiveness(nodes);
    _buildBundles();
    _coalesce();
    _binPack(availableRegs);

    _allocator.init(compiler.arch, availableRegs, preservedRegs);

    // 3. Process Blocks
    final blocks = <BlockNode>[];
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        blocks.add(node);
      }
    }

    if (blocks.isNotEmpty) {
      // Initialize first block entry from global decisions/hints
      _initFirstBlockEntry(blocks.first);
      // _insertArgMoves(blocks.first); // Moved up

      for (final block in blocks) {
        _processBlock(block);
        _propagateAssignments(block);
      }
    }

    // 4. Finalize
    _insertPrologEpilog();
  }

  void _assignArgIndexToWorkRegs(FuncNode func) {
    final detail = func.detail;
    final argCount = func.argCount;

    for (int i = 0; i < argCount; i++) {
      final pack = func.argPacks![i];
      final argVal = pack[0];

      if (argVal.isReg) {
        final virtId = argVal.regId;
        // Only process if the virtual register is actually used (mapped to a WorkReg)
        if (_virtIdToWorkId.containsKey(virtId)) {
          final physArg = detail.args[i][0];

          if (physArg.isReg) {
            // workReg.homeRegId = physArg.regId;
          }
          // Stack arguments are handled later (only register arguments enter here).
        }
      }
    }
  }

  void _insertArgMoves(BlockNode block) {
    if (_func == null) return;
    final func = _func!;
    final detail = func.detail;

    // Insert at the beginning of the block
    BaseNode? insertPoint = block;

    for (int i = 0; i < func.argCount; i++) {
      final pack = func.argPacks![i];
      final argVal = pack[0];

      if (argVal.isReg) {
        final virtId = argVal.regId;
        if (_virtIdToWorkId.containsKey(virtId)) {
          final physArg = detail.args[i][0];
          if (physArg.isReg) {
            final workId = _virtIdToWorkId[virtId]!;
            final workReg = _allocator.workRegById(workId);
            final virtReg = workReg.virtReg;
            // For argumentos, force o alocador a preferir (e manter) o
            // registrador f�sico definido pela ABI. Isso garante que os
            // ponteiros de entrada/sa�da cheguem corretos mesmo antes de
            // qualquer instru��o de movimenta��o.
            workReg.homeRegId = physArg.regId;
            workReg.restrictPreferredMask(1 << physArg.regId);

            final movNode = _arch.move(virtReg, virtReg.toPhys(physArg.regId));
            _insertNodeAfter(insertPoint!, movNode);
            insertPoint = movNode;
          }
        }
      }
    }
  }

  void _initRegMasks(RARegMask avail, RARegMask preserved) {
    if (_func == null) return;

    avail.reset();
    preserved.reset();

    _arch.initRegMasks(compiler, avail, preserved);
  }

  void _mapVirtuals(NodeList nodes) {
    for (final node in nodes.nodes) {
      if (node is InstNode) {
        for (int i = 0; i < node.opCount; i++) {
          final op = node.operands[i];
          if (op is BaseReg && !op.isPhysical && !op.isNone) {
            if (!_virtIdToWorkId.containsKey(op.id)) {
              final workReg = _allocator.addWorkReg(op.group, op);
              _virtIdToWorkId[op.id] = workReg.workId;

              final vIndex = op.id - Globals.kMinVirtId;
              if (vIndex >= 0 && vIndex < compiler.virtRegs.length) {
                if (compiler.virtRegs[vIndex].isStack) {
                  workReg.markStackSlot();
                }
              }
            }
          } else if (op is BaseMem) {
            // Deep scan memory operands (Base/Index)
            if (op.base != null && !op.base!.isPhysical && !op.base!.isNone) {
              if (!_virtIdToWorkId.containsKey(op.base!.id)) {
                final workReg = _allocator.addWorkReg(op.base!.group, op.base!);
                _virtIdToWorkId[op.base!.id] = workReg.workId;

                final vIndex = op.base!.id - Globals.kMinVirtId;
                if (vIndex >= 0 && vIndex < compiler.virtRegs.length) {
                  if (compiler.virtRegs[vIndex].isStack) {
                    workReg.markStackSlot();
                  }
                }
              }
            }
            if (op.index != null &&
                !op.index!.isPhysical &&
                !op.index!.isNone) {
              if (!_virtIdToWorkId.containsKey(op.index!.id)) {
                final workReg =
                    _allocator.addWorkReg(op.index!.group, op.index!);
                _virtIdToWorkId[op.index!.id] = workReg.workId;

                final vIndex = op.index!.id - Globals.kMinVirtId;
                if (vIndex >= 0 && vIndex < compiler.virtRegs.length) {
                  if (compiler.virtRegs[vIndex].isStack) {
                    workReg.markStackSlot();
                  }
                }
              }
            }
          }
        }
      }
    }
    _numWorkRegs = _virtIdToWorkId.length;
  }

  void _buildGlobalLiveness(NodeList nodes) {
    _blockData.clear();
    _coalescingCandidates.clear();
    final blocks = <BlockNode>[];

    // 1. Initialize block data
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        _blockData[node.label.id] = RABlockData(node.label.id, _numWorkRegs);
        blocks.add(node);
      }
    }

    // 1b. Calculate Block Weights (heuristics for loops)
    _calculateBlockWeights(blocks, nodes);

    // 2. Calculate GEN and KILL for each block
    BlockNode? current;
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        current = node;
      } else if (node is InstNode && current != null) {
        final data = _blockData[current.label.id]!;
        _analyzeInstLiveness(node, data);
        _analyzePreferenceHints(node);
      }
    }

    // 3. Solve iteratively (Backward)
    bool changed = true;
    while (changed) {
      changed = false;
      for (final block in blocks.reversed) {
        final data = _blockData[block.label.id]!;

        final liveOut = BitVector(_numWorkRegs);
        for (final succ in block.successors) {
          final succData = _blockData[succ.label.id];
          if (succData != null) {
            liveOut.or(succData.liveIn);
          }
        }

        if (!data.liveOut.isEqual(liveOut)) {
          data.liveOut.copyFrom(liveOut);
          changed = true;
        }

        final liveIn = BitVector(_numWorkRegs);
        liveIn.copyFrom(data.liveOut);
        liveIn.andNot(data.kill);
        liveIn.or(data.gen);

        if (!data.liveIn.isEqual(liveIn)) {
          data.liveIn.copyFrom(liveIn);
          changed = true;
        }
      }
    }

    // 4. Build LiveSpans
    _buildLiveSpans(nodes);

    // Debug: Print LiveSpans
    if (debugLog) {
      print('RAPass: LiveSpans');
      for (int i = 0; i < _numWorkRegs; i++) {
        final workReg = _allocator.workRegById(i);
        final spans =
            workReg.liveSpans.data.map((s) => '[${s.a}, ${s.b}]').join(', ');
        print('  Virt${workReg.virtReg.id}: $spans');
      }
    }
  }

  void _analyzeInstLiveness(InstNode node, RABlockData data) {
    final flags = _arch.preciseLiveness ? _operandFlags(node) : null;
    final writes = <int>[];

    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];

      // Handle direct virtual registers
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        final workId = _virtIdToWorkId[op.id];
        if (workId != null) {
          final workReg = _allocator.workRegById(workId);
          // Update frequency
          workReg.liveStats.freq += data.weight;

          if (flags != null) {
            // Reads see the value from before the instruction; writes are
            // applied afterwards so `add a, a, b` keeps `a` live-in.
            final f = i < flags.length ? flags[i] : 0;
            if ((f & (RATiedFlags.kRead | RATiedFlags.kUse)) != 0 &&
                !data.kill.testBit(workId)) {
              data.gen.setBit(workId);
            }
            if ((f & (RATiedFlags.kWrite | RATiedFlags.kOut)) != 0) {
              writes.add(workId);
            }
          } else if (i == 0 && _arch.isMove(node)) {
            // DEF for moves
            data.kill.setBit(workId);
          } else if (i == 0) {
            // RW for destructive (non-mov)
            if (!data.kill.testBit(workId)) {
              data.gen.setBit(workId);
            }
            data.kill.setBit(workId);
          } else {
            // USE
            if (!data.kill.testBit(workId)) {
              data.gen.setBit(workId);
            }
          }
        }
      } else if (op is BaseMem) {
        // Handle memory operands (Base and Index are implicit USE)
        for (final reg in [op.base, op.index]) {
          if (reg == null || reg.isPhysical) continue;
          final workId = _virtIdToWorkId[reg.id];
          if (workId != null) {
            final workReg = _allocator.workRegById(workId);
            workReg.liveStats.freq += data.weight;
            if (!data.kill.testBit(workId)) {
              data.gen.setBit(workId);
            }
          }
        }
      }
    }

    for (final workId in writes) {
      data.kill.setBit(workId);
    }
  }

  void _calculateBlockWeights(List<BlockNode> blocks, NodeList nodes) {
    // Basic heuristic: Detect backward jumps based on label position (assuming linear block layout matches list order).
    // If Jmp/Jcc to a label that is in an earlier block -> Loop.

    final labelToBlockId = <int, int>{}; // Label ID -> Block Index
    for (int i = 0; i < blocks.length; i++) {
      labelToBlockId[blocks[i].label.id] = i;
    }

    // Iterate instructions to find backward jumps
    int currentBlockIndex = -1;
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        currentBlockIndex++;
      } else if (node is InstNode) {
        // Check if jump
        // We can use generic analyze check or assume we have jump analyzer,
        // but basic check for Jmp/Jcc by opcode range (if available) or checking operands implies Jcc.
        // Or simpler: check if it branches to a label.
        if (node.opCount > 0 && node.operands[0] is LabelOp) {
          final targetLabelId = (node.operands[0] as LabelOp).label.id;
          if (labelToBlockId.containsKey(targetLabelId)) {
            final targetIndex = labelToBlockId[targetLabelId]!;
            if (targetIndex <= currentBlockIndex) {
              // Loop detected from targetIndex to currentBlockIndex
              // Increase weight of blocks in this range.
              // Multiplier
              const double loopWeight = 10.0; // Standard heuristic
              for (int k = targetIndex; k <= currentBlockIndex; k++) {
                final block = blocks[k];
                _blockData[block.label.id]!.weight *= loopWeight;
              }
            }
          }
        }
      }
    }
  }

  void _analyzePreferenceHints(InstNode node) {
    // Basic Coalescing Hint for mov v0, v1
    if (node.instId == _archTraits.movId && node.opCount == 2) {
      final dst = node.operands[0];
      final src = node.operands[1];

      if (dst is BaseReg && src is BaseReg) {
        if (!dst.isPhysical && !src.isPhysical) {
          // Both virtual - they should eventually share the same physical register
          final dstWorkId = _virtIdToWorkId[dst.id];
          final srcWorkId = _virtIdToWorkId[src.id];
          if (dstWorkId != null && srcWorkId != null) {
            _coalescingCandidates
                .add(_RACoalesceCandidate(dstWorkId, srcWorkId));
          }
        } else if (!dst.isPhysical && src.isPhysical) {
          final workId = _virtIdToWorkId[dst.id];
          if (workId != null) {
            final workReg = _allocator.workRegById(workId);
            workReg.homeRegId = src.id; // Hint to use this physical reg
          }
        } else if (dst.isPhysical && !src.isPhysical) {
          final workId = _virtIdToWorkId[src.id];
          if (workId != null) {
            final workReg = _allocator.workRegById(workId);
            workReg.homeRegId = dst.id; // Hint to use this physical reg
          }
        }
      }
    }
  }

  void _buildLiveSpans(NodeList nodes) {
    int position = 2;
    // 1. Assign Positions
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        node.position = position;
        position += 2;
      } else if (node is InstNode) {
        node.position = position;
        position += 2;
      }
    }

    // 2. Process Blocks
    final activeRegs = BitVector(_numWorkRegs);
    final startPos = <int, int>{};

    BlockNode? currentBlock;
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        if (currentBlock != null) {
          // Finish previous
          final endPos = node.position;
          for (final workId in activeRegs.setBits) {
            final s = startPos[workId]!;
            _allocator.workRegById(workId).liveSpans.openAt(s, endPos);
          }
        }
        currentBlock = node;

        // Start new
        activeRegs.clearAll();
        startPos.clear();
        final data = _blockData[node.label.id]!;
        for (final workId in data.liveIn.setBits) {
          activeRegs.setBit(workId);
          startPos[workId] = node.position;
        }
      } else if (node is InstNode && currentBlock != null) {
        // Process Inst
        if (_arch.preciseLiveness) {
          final flags = _operandFlags(node);
          // 1. Uses (registers read and every memory base/index).
          for (int i = 0; i < node.opCount; i++) {
            final op = node.operands[i];
            final f = i < flags.length ? flags[i] : 0;
            if (op is BaseMem ||
                (f & (RATiedFlags.kRead | RATiedFlags.kUse)) != 0) {
              _activateUse(op, activeRegs, startPos, node.position);
            }
          }
          // 2. Defs.
          for (int i = 0; i < node.opCount; i++) {
            final f = i < flags.length ? flags[i] : 0;
            if ((f & (RATiedFlags.kWrite | RATiedFlags.kOut)) != 0) {
              _handleDef(node.operands[i], activeRegs, startPos, node.position);
            }
          }
          continue;
        }

        final isMov = _arch.isMove(node);

        // 1. Handle Uses (Gen)
        for (int i = 0; i < node.opCount; i++) {
          bool isUse = true;
          // A MOV register destination is a pure definition. A memory
          // destination still reads its virtual base/index registers to form
          // the address, so it must participate in last-use tracking.
          if (i == 0 && isMov && node.operands[i] is BaseReg) isUse = false;

          if (isUse) {
            final op = node.operands[i];
            _activateUse(op, activeRegs, startPos, node.position);
          }
        }

        // 2. Handle Defs (Kill)
        if (node.opCount > 0) {
          final op = node.operands[0];
          _handleDef(op, activeRegs, startPos, node.position);
        }
      }
    }

    // Finish last block
    if (currentBlock != null) {
      for (final workId in activeRegs.setBits) {
        final s = startPos[workId]!;
        _allocator.workRegById(workId).liveSpans.openAt(s, position);
      }
    }
  }

  void _activateUse(
      dynamic op, BitVector activeRegs, Map<int, int> startPos, int pos) {
    if (op is BaseReg && !op.isPhysical && !op.isNone) {
      final workId = _virtIdToWorkId[op.id];
      if (workId != null) {
        if (!activeRegs.testBit(workId)) {
          activeRegs.setBit(workId);
          startPos[workId] = pos;
        }
        _lastUsePos[op.id] = pos;
      }
    } else if (op is BaseMem) {
      if (op.base != null && !op.base!.isPhysical) {
        _activateUse(op.base!, activeRegs, startPos, pos);
      }
      if (op.index != null && !op.index!.isPhysical) {
        _activateUse(op.index!, activeRegs, startPos, pos);
      }
    }
  }

  void _handleDef(
      dynamic op, BitVector activeRegs, Map<int, int> startPos, int pos) {
    if (op is BaseReg && !op.isPhysical && !op.isNone) {
      final workId = _virtIdToWorkId[op.id];
      if (workId != null) {
        if (activeRegs.testBit(workId)) {
          // Close range
          final s = startPos[workId]!;
          _allocator.workRegById(workId).liveSpans.openAt(s, pos + 2);
        }
        // Start new range (output is live immediately)
        activeRegs.setBit(workId);
        startPos[workId] = pos;
      }
    }
  }

  void _buildBundles() {
    _bundles.clear();
    for (int i = 0; i < _numWorkRegs; i++) {
      final workReg = _allocator.workRegById(i);
      final bundle = RALiveBundle();
      bundle.addWorkId(i);
      workReg.bundleId = _bundles.length;

      // Calculate priority based on calculated frequency
      bundle.priority = workReg.liveStats.freq;

      _bundles.add(bundle);
    }
  }

  void _coalesce() {
    bool changed = true;
    while (changed) {
      changed = false;
      for (final candidate in _coalescingCandidates) {
        final workRegA = _allocator.workRegById(candidate.a);
        final workRegB = _allocator.workRegById(candidate.b);

        if (workRegA.bundleId == workRegB.bundleId) continue;
        if (workRegA.group != workRegB.group) continue;

        final bundleA = _bundles[workRegA.bundleId];
        final bundleB = _bundles[workRegB.bundleId];

        // Check conflict
        bool conflict = false;

        // Check if any workReg in A conflicts with any in B
        for (final idA in bundleA.workIds) {
          final regA = _allocator.workRegById(idA);
          for (final idB in bundleB.workIds) {
            final regB = _allocator.workRegById(idB);
            if (regA.liveSpans.intersects(regB.liveSpans)) {
              conflict = true;
              break;
            }
          }
          if (conflict) break;
        }

        if (!conflict) {
          // Merge B into A
          for (final idB in bundleB.workIds) {
            bundleA.addWorkId(idB);
            final regB = _allocator.workRegById(idB);
            regB.bundleId = workRegA.bundleId;

            // Merge priority (sum)
            bundleA.priority += regB.liveSpans.totalWidth.toDouble();
          }

          // Clear B
          bundleB.workIds.clear(); // Effectively removed
          changed = true;
        }
      }
    }
  }

  void _binPack(RARegMask availableRegs) {
    for (RegGroup group in RegGroup.values) {
      if (group == RegGroup.gp ||
          group == RegGroup.vec) // Only core groups for now
        _binPackGroup(group, availableRegs);
    }
  }

  void _binPackGroup(RegGroup group, RARegMask availableRegs) {
    // Collect workRegs for this group
    final work_regs = <RAWorkReg>[];
    for (int i = 0; i < _numWorkRegs; i++) {
      final wr = _allocator.workRegById(i);
      if (wr.group == group) work_regs.add(wr);
    }
    if (work_regs.isEmpty) return;

    // 1. Sort bundles by priority (Using bundles of this group only?)
    // Actually our bundles list is global, but we iterate it.
    // The previous logic iterated all bundles.
    // Let's stick to iterating all bundles, but filter by group.

    final sortedBundleIndices = <int>[];
    for (int i = 0; i < _bundles.length; i++) {
      if (_allocator.workRegById(_bundles[i].workIds.first).group == group) {
        sortedBundleIndices.add(i);
      }
    }
    sortedBundleIndices
        .sort((a, b) => _bundles[b].priority.compareTo(_bundles[a].priority));

    final globalSpans = List.generate(
        Globals.numVirtGroups, (_) => List.generate(32, (_) => RALiveSpans()));

    // (Code continues with Consecutive Alloc logic inserted here...)

    // 2. Prepare Consecutive Registers
    // Allocate consecutive registers - both leads and all consecutives. This is important and prioritized over the rest.
    final consecutiveRegs = <_RAConsecutiveReg>[];

    // Check for lead consecutive
    for (final workReg in work_regs) {
      if (workReg.isLeadConsecutive) {
        consecutiveRegs.add(_RAConsecutiveReg(workReg, null));
        workReg.markProcessedConsecutive();
      }
    }

    if (consecutiveRegs.isNotEmpty) {
      // Append others
      for (int i = 0;;) {
        int stop = consecutiveRegs.length;
        if (i == stop) break;

        while (i < stop) {
          final regInfo = consecutiveRegs[i];
          final workReg = regInfo.workReg;

          if (workReg.hasImmediateConsecutives) {
            for (final id in workReg.immediateConsecutives) {
              final consecutiveReg = _allocator.workRegById(id);
              if (!consecutiveReg.isProcessedConsecutive) {
                consecutiveRegs.add(_RAConsecutiveReg(consecutiveReg, workReg));
                consecutiveReg.markProcessedConsecutive();
              }
            }
          }
          i++;
        }
      }

      // Allocate them
      for (final consecutiveInfo in consecutiveRegs) {
        final workReg = consecutiveInfo.workReg;
        if (workReg.isAllocated) continue;

        final parentReg = consecutiveInfo.parentReg;
        int physRegsMask = 0;

        if (parentReg == null) {
          // Lead register
          physRegsMask = availableRegs[group] & workReg.preferredMask;
          if (physRegsMask == 0) {
            // Fallback (should be rare)
            physRegsMask = availableRegs[group] & workReg.consecutiveMask;
          }
        } else if (parentReg.hasHomeRegId) {
          // Follower register
          final consecutiveId = parentReg.homeRegId + 1;
          // Simple check for availability
          if (consecutiveId < 32 &&
              ((availableRegs[group] >> consecutiveId) & 1) != 0) {
            final live = globalSpans[group.index][consecutiveId];
            if (!live.intersects(workReg.liveSpans)) {
              live.addFrom(workReg.liveSpans);
              workReg.setHomeRegId(consecutiveId);
              physRegsMask = (1 << consecutiveId);
              workReg.markAllocated();
            } else {
              throw StateError(
                  'Failed to allocate consecutive register: Interference at Phys$consecutiveId');
            }
          } else {
            // Failed to allocate consecutive sequence
            // In C++ this returns an error kConsecutiveRegsAllocation
            // For now we just log/break or throw
            throw StateError('Failed to allocate consecutive register');
          }
        }

        // Find slot if not already set (for Lead)
        if (!workReg.hasHomeRegId && physRegsMask != 0) {
          // Iterate bits
          for (int physId = 0; physId < 32; physId++) {
            if ((physRegsMask & (1 << physId)) != 0) {
              final live = globalSpans[group.index][physId];
              if (!live.intersects(workReg.liveSpans)) {
                // Success
                live.addFrom(workReg.liveSpans); // Merge spans to global
                workReg.setHomeRegId(physId);
                workReg.markAllocated();
                break;
              }
            }
          }
        } else if (workReg.hasHomeRegId) {
          // Already set (follower), update spans
          final physId = workReg.homeRegId;
          globalSpans[group.index][physId].addFrom(workReg.liveSpans);
          workReg.markAllocated();
        }
      }
    }

    // 3. First Pass: Handle fixed hints (homeRegId) for non-consecutive
    for (final bid in sortedBundleIndices) {
      final bundle = _bundles[bid];
      // For simplicity, take hint from the first workReg in bundle
      final firstWorkReg = _allocator.workRegById(bundle.workIds.first);

      // Skip if already allocated (e.g. consecutive)
      if (firstWorkReg.isAllocated) {
        if (firstWorkReg.hasHomeRegId) {
          bundle.physId = firstWorkReg.homeRegId;
        }
        continue;
      }

      if (firstWorkReg.hasHomeRegId) {
        final group = firstWorkReg.group;
        final physId = firstWorkReg.homeRegId;
        bool conflict = false;

        // Check intersection for all workregs in bundle
        for (final workId in bundle.workIds) {
          final workReg = _allocator.workRegById(workId);
          if (globalSpans[group.index][physId].intersects(workReg.liveSpans)) {
            conflict = true;
            break;
          }
        }

        if (!conflict) {
          bundle.physId = physId;
          for (final workId in bundle.workIds) {
            final workReg = _allocator.workRegById(workId);
            for (final span in workReg.liveSpans.data) {
              globalSpans[group.index][physId].openAt(span.a, span.b);
            }
            workReg.markAllocated();
          }
        } else {
          bundle.physId = RAAssignment.kPhysNone;
        }
      }
    }

    // 4. Second Pass: Allocate others
    for (final bid in sortedBundleIndices) {
      final bundle = _bundles[bid];
      if (bundle.physId != RAAssignment.kPhysNone) continue;

      final firstWorkReg = _allocator.workRegById(bundle.workIds.first);
      if (firstWorkReg.isAllocated) continue; // Should have been handled

      final group = firstWorkReg.group;
      int availMask = availableRegs[group] & firstWorkReg.preferredMask;

      for (int physId = 0; physId < 32; physId++) {
        if ((availMask & (1 << physId)) != 0) {
          bool conflict = false;
          for (final workId in bundle.workIds) {
            final workReg = _allocator.workRegById(workId);
            if (globalSpans[group.index][physId]
                .intersects(workReg.liveSpans)) {
              conflict = true;
              break;
            }
          }

          if (!conflict) {
            bundle.physId = physId;
            for (final workId in bundle.workIds) {
              final workReg = _allocator.workRegById(workId);
              workReg.homeRegId = physId; // Update homeRegId as well
              workReg.markAllocated();
              for (final span in workReg.liveSpans.data) {
                globalSpans[group.index][physId].openAt(span.a, span.b);
              }
            }
            break;
          }
        }
      }
    }
  }

  void _initFirstBlockEntry(BlockNode block) {
    final data = _blockData[block.label.id]!;
    data.entryAssignment = _createAssignmentState();

    // Initial assignment: use homeRegId for registers in liveIn
    for (final workId in data.liveIn.setBits) {
      final workReg = _allocator.workRegById(workId);
      if (workReg.hasHomeRegId) {
        data.entryAssignment!
            .assign(workReg.group, workId, workReg.homeRegId, false);
      }
    }
  }

  RAAssignmentState _createAssignmentState() {
    final state = RAAssignmentState();
    final physCount = _allocator.physRegCount;
    final physIndex = RARegIndex();
    physIndex.buildIndexes(physCount);

    final physTotal = physIndex.get(RegGroup.values[RegGroup.kMaxVirt]) +
        physCount.get(RegGroup.values[RegGroup.kMaxVirt]);

    state.initLayout(physCount, _allocator.workRegs);
    final physToWorkMap = PhysToWorkMap(physTotal);
    final workToPhysMap = WorkToPhysMap(_numWorkRegs);
    state.initMaps(physToWorkMap, workToPhysMap);
    return state;
  }

  void _propagateAssignments(BlockNode block) {
    final data = _blockData[block.label.id]!;
    var exitAssignment = data.exitAssignment;
    if (exitAssignment == null) return;

    final lastNode = block.lastNode;
    final analyzer = compiler.instructionAnalyzer;
    if (lastNode is InstNode &&
        analyzer != null &&
        analyzer.isJump(lastNode) &&
        analyzer.getJumpTarget(lastNode) == null &&
        block.successors.length > 1) {
      exitAssignment =
          _shareJumpTableAssignment(block, lastNode, exitAssignment);
    }

    for (final succ in block.successors) {
      final succData = _blockData[succ.label.id];
      if (succData == null) continue;

      if (succData.entryAssignment == null) {
        // First visit - copy assignment
        succData.entryAssignment = _createAssignmentState();
        succData.entryAssignment!.copyFrom(exitAssignment);
      } else {
        // Resolve transition if different
        if (!succData.entryAssignment!.equals(exitAssignment)) {
          _resolveTransition(
              block, succ, exitAssignment, succData.entryAssignment!);
        }
      }
    }
  }

  /// `RALocalAllocator::alloc_jump_table()`: all targets of a jump through
  /// a register or memory operand share one entry assignment
  /// (`share_assignment_across_successors()`), since no move can be placed
  /// on a single edge. If a target already has one, the moves to it go
  /// before the jump and the other targets get it too.
  RAAssignmentState _shareJumpTableAssignment(
      BlockNode block, InstNode jump, RAAssignmentState exitAssignment) {
    RAAssignmentState? shared;
    for (final succ in block.successors) {
      final entry = _blockData[succ.label.id]?.entryAssignment;
      if (entry == null) continue;
      if (shared == null) {
        shared = entry;
      } else if (!shared.equals(entry)) {
        throw AsmJitException(AsmJitError.invalidState,
            'Jump table targets were entered with different assignments');
      }
    }
    if (shared == null || shared.equals(exitAssignment)) return exitAssignment;

    // The moves must not overwrite the registers the jump reads.
    final jumpRegs = <int>{};
    for (final op in jump.operands) {
      if (op is BaseReg && op.isPhysical) jumpRegs.add(op.id);
      if (op is BaseMem) {
        for (final r in [op.base, op.index]) {
          if (r is BaseReg && r.isPhysical) jumpRegs.add(r.id);
        }
      }
    }
    for (var i = 0; i < _numWorkRegs; i++) {
      final workReg = _allocator.workRegById(i);
      if (workReg.group != RegGroup.gp) continue;
      final toPhys = shared.workToPhysId(workReg.group, i);
      if (toPhys != RAAssignment.kPhysNone &&
          toPhys != exitAssignment.workToPhysId(workReg.group, i) &&
          jumpRegs.contains(toPhys)) {
        throw AsmJitException(
            AsmJitError.invalidState,
            'Jump table: the moves to the shared assignment overwrite the '
            'jump target register');
      }
    }
    _emitTransitionMoves(block, exitAssignment, shared, jump);
    return shared;
  }

  /// Emits the moves that switch from [fromState] (exit of [from]) to
  /// [toState] (entry of [to]) on the edge `from -> to`.
  ///
  /// As in upstream `RALocalAllocator::alloc_branch()`: on a jump edge the
  /// moves go before an unconditional jump; a conditional jump is redirected
  /// to a trampoline placed after the function body that performs the moves
  /// and jumps to [to]. On a fallthrough edge they go after the last node of
  /// [from].
  void _resolveTransition(BlockNode from, BlockNode to,
      RAAssignmentState fromState, RAAssignmentState toState) {
    final lastNode = from.lastNode;
    if (lastNode == null) return;

    final analyzer = compiler.instructionAnalyzer;
    if (lastNode is InstNode &&
        analyzer != null &&
        analyzer.isJump(lastNode) &&
        analyzer.getJumpTarget(lastNode)?.id == to.label.id) {
      // A conditional jump to the block that also follows it: both edges
      // need the same moves, which do not change the flags.
      final fallsThroughToTarget = _nextBlock(lastNode) == to;
      if (analyzer.isUnconditionalJump(lastNode) || fallsThroughToTarget) {
        _emitTransitionMoves(from, fromState, toState, lastNode);
      } else {
        _emitTrampoline(from, lastNode, to, fromState, toState);
      }
      return;
    }

    _emitTransitionMoves(from, fromState, toState, null);
  }

  static BlockNode? _nextBlock(BaseNode node) {
    var next = node.next;
    while (next != null && next is! BlockNode) {
      next = next.next;
    }
    return next as BlockNode?;
  }

  void _emitTrampoline(BlockNode from, InstNode jump, BlockNode to,
      RAAssignmentState fromState, RAAssignmentState toState) {
    final exit = _func!.exitNode!;
    final trampoline = compiler.newLabel();
    _insertNodeBefore(exit, LabelNode(trampoline));
    final jmp = _arch.jump(to.label);
    _insertNodeBefore(exit, jmp);
    _emitTransitionMoves(from, fromState, toState, jmp);
    final i = jump.operands
        .indexWhere((op) => op is LabelOp && op.label.id == to.label.id);
    jump.operands[i] = LabelOp(trampoline);
  }

  void _emitTransitionMoves(BlockNode block, RAAssignmentState fromState,
      RAAssignmentState toState, InstNode? insertionPoint) {
    // Collect all pending moves
    final moves = <_RAMove>[];
    final spills = <_RAMove>[];
    final loads = <_RAMove>[];

    for (int i = 0; i < _numWorkRegs; i++) {
      final workReg = _allocator.workRegById(i);
      final fromPhys = fromState.workToPhysId(workReg.group, i);
      final toPhys = toState.workToPhysId(workReg.group, i);

      if (fromPhys == toPhys) continue;

      if (fromPhys != RAAssignment.kPhysNone &&
          toPhys != RAAssignment.kPhysNone) {
        moves.add(_RAMove(workReg, fromPhys, toPhys));
      } else if (fromPhys != RAAssignment.kPhysNone &&
          toPhys == RAAssignment.kPhysNone) {
        // Spill if live-out
        final data = _blockData[block.label.id]!;
        if (data.liveOut.testBit(i)) {
          spills.add(_RAMove(workReg, fromPhys, toPhys));
        }
      } else if (fromPhys == RAAssignment.kPhysNone &&
          toPhys != RAAssignment.kPhysNone) {
        loads.add(_RAMove(workReg, fromPhys, toPhys));
      }
    }

    // 1. Spills (Safe to do first as they just read)
    for (final move in spills) {
      final srcReg = move.workReg.virtReg.toPhys(move.fromPhys);
      final mem = _stackSlot(move.workReg);
      _insertResolution(block, insertionPoint, _arch.save(mem, srcReg));
    }

    // 2. Resolve Reg-Reg moves (cycle breaking)
    _resolveParallelMoves(block, insertionPoint, moves);

    // 3. Loads (Write to regs)
    for (final move in loads) {
      final dstReg = move.workReg.virtReg.toPhys(move.toPhys);
      final mem = _stackSlot(move.workReg);
      _insertResolution(block, insertionPoint, _arch.load(dstReg, mem));
    }
  }

  void _resolveParallelMoves(
      BlockNode block, InstNode? insertionPoint, List<_RAMove> moves) {
    if (moves.isEmpty) return;

    // We only care about registers involved in the moves.

    // Simpler: Just track 'pending' moves and use 'ready' set.
    // 'Ready' move: Its destination is not a source of any other pending move.

    // NOTE: This assumes destination registers are not "live" otherwise?
    // We only care about registers involved in the moves.

    // Using a simple iterative approach with Swap for cycles.
    bool progress = true;
    while (moves.isNotEmpty && progress) {
      progress = false;
      for (int i = 0; i < moves.length; i++) {
        final move = moves[i];

        // Check if move.toPhys is source of any other move
        bool isDestRead = false;
        for (int k = 0; k < moves.length; k++) {
          if (i == k) continue;
          if (moves[k].fromPhys == move.toPhys) {
            isDestRead = true;
            break;
          }
        }

        if (!isDestRead) {
          // Safe to move
          final srcReg = move.workReg.virtReg.toPhys(move.fromPhys);
          final dstReg = move.workReg.virtReg.toPhys(move.toPhys);
          _insertResolution(block, insertionPoint, _arch.move(dstReg, srcReg));

          moves.removeAt(i);
          progress = true;
          break; // Restart loop to re-evaluate dependencies
        }
      }
    }

    // Cycles remaining
    while (moves.isNotEmpty) {
      // Pick first move (A->B)
      final move = moves.removeAt(0);

      // Perform Swap A, B
      // This effectively does A->B AND B->A.
      // We wanted A->B.
      // B->A might not be what the other move wanted, but for Swap logic:
      // If we have Cycle A->B->A.
      // Swap(A, B) solves both?
      // Value at A goes to B. Value at B goes to A.
      // Desired: A->B, B->A.
      // Yes, Swap works for 2-cycle.

      // For longer cycles A->B->C->A.
      // Swap(A, B). A has B's value. B has A's value.
      // Pending: B->C (now A has B's value, so it becomes A->C?), C->A (C->B?).
      // It gets complex.

      // Simpler Cycle Break: Use Temp (Stack).
      // Or XCHG if supported.

      // For robustness: Push A, Move A<-Source??
      // Let's use Swap for x86 if possible, or just emit Move and handle spill?

      // Let's use simple XOR swap or similar? No, standard `XCHG`.
      // XCHG dst, src.
      // This performs move.toPhys <-> move.fromPhys.
      // The value at move.fromPhys is now at move.toPhys (Correct).
      // The value at move.toPhys is now at move.fromPhys (Garbage/Old).
      // Any move waiting for move.toPhys (as source) now needs to look at move.fromPhys.

      final srcReg = move.workReg.virtReg.toPhys(move.fromPhys);
      final dstReg = move.workReg.virtReg.toPhys(move.toPhys);

      for (final node in _arch.swap(dstReg, srcReg)) {
        _insertResolution(block, insertionPoint, node);
      }

      // Update pending moves that sourced from 'toPhys' to now source from 'fromPhys'.
      for (final other in moves) {
        if (other.fromPhys == move.toPhys) {
          other.fromPhys = move.fromPhys;
        }
      }
    }
  }

  void _insertResolution(
      BlockNode block, InstNode? beforeNode, InstNode newNode) {
    if (beforeNode != null) {
      _insertNodeBefore(beforeNode, newNode);
    } else {
      // Append at the end of block
      BaseNode? last = block;
      while (last?.next != null && last?.next is! BlockNode) {
        last = last!.next;
      }
      if (last != null) {
        compiler.nodes.insertAfter(newNode, last);
      }
    }
  }

  void _processBlock(BlockNode block) {
    final data = _blockData[block.label.id]!;

    if (data.entryAssignment != null) {
      _allocator.copyAssignmentFrom(data.entryAssignment!);
    } else {
      _allocator.makeAllClean();
    }

    // Iterate instructions in block
    BaseNode? node = block;
    while (node != null) {
      BaseNode? next = node.next;
      if (node is InstNode) {
        _processInstruction(node);
      }
      if (next is BlockNode) break;
      node = next;
    }

    data.exitAssignment = _createAssignmentState();
    data.exitAssignment!.copyFrom(_allocator.curAssignment);
  }

  void _processInstruction(InstNode node) {
    // 1. Prepare masks (used, clobbered)
    // 2. Prepare tied regs
    // 3. Call allocator.allocInstruction

    final tiedRegs = <RATiedReg>[];
    final usedRegs = RARegMask();
    final clobberedRegs = RARegMask();

    // Need InstructionAnalyzer to fill these details from definitions
    // Using a placeholder analysis here
    _analyzeInstruction(node, tiedRegs, usedRegs, clobberedRegs);

    _allocator.allocInstruction(
        tiedRegs: tiedRegs,
        usedRegs: usedRegs,
        clobberedRegs: clobberedRegs,
        emitLoad: (workReg, physId) => _emitLoad(workReg, physId, node),
        emitSave: (workReg, physId) => _emitSave(workReg, physId, node),
        emitMove: (workReg, dst, src) => _emitMove(workReg, dst, src, node),
        emitSwap: (aReg, aPhys, bReg, bPhys) =>
            _emitSwap(aReg, aPhys, bReg, bPhys, node));

    // Apply assignments to operands
    _rewriteInstruction(node, tiedRegs);

    // Redundant move elimination
    if (node.instId == _archTraits.movId && node.opCount == 2) {
      if (node.operands[0] == node.operands[1]) {
        _removeNode(node);
      }
    }
  }

  void _removeNode(BaseNode node) {
    compiler.nodes.remove(node);
  }

  void _analyzeInstruction(InstNode node, List<RATiedReg> tiedRegs,
      RARegMask used, RARegMask clobbered) {
    if (node is FuncRetNode) {
      _analyzeRet(node, tiedRegs);
      return;
    }

    if (node.hasNoOperands) return;

    final opCount = node.opCount;
    final opFlags = _operandFlags(node);

    for (int i = 0; i < opCount; i++) {
      final op = node.operands[i];
      int currentFlags = i < opFlags.length ? opFlags[i] : 0;

      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        // Virtual Register
        RAWorkId workId;
        if (_virtIdToWorkId.containsKey(op.id)) {
          workId = _virtIdToWorkId[op.id]!;
        } else {
          final workReg = _allocator.addWorkReg(op.group, op);
          workId = workReg.workId;
          _virtIdToWorkId[op.id] = workId;
        }

        final workReg = _allocator.workRegById(workId);

        // Check for Last Use (Kill)
        if ((currentFlags & RATiedFlags.kRead) != 0) {
          if (_lastUsePos[op.id] == node.position) {
            currentFlags |= RATiedFlags.kKill;
          }
        }

        int useMask = 0xFFFFFFFF;
        int useId = _arch.fixedUseId(node, i);
        if (useId != RAAssignment.kPhysNone) {
          useMask = 1 << useId;
          // Like RAInstBuilder::add(): a fixed register is used by the
          // instruction, so no other operand may keep it.
          used[workReg.group] |= useMask;
        }

        _tie(tiedRegs, workReg, currentFlags, useMask, useId, 0xFFFFFFFF,
            RAAssignment.kPhysNone);
      } else if (op is BaseMem) {
        // Base/index of a memory operand are always read, even when the
        // instruction writes to memory (MOV [rax], rbx reads rax).
        for (final reg in [op.base, op.index]) {
          if (reg == null) continue;
          if (reg.isPhysical) {
            used[reg.group] |= 1 << reg.id;
          } else {
            _addImplicitUse(reg, tiedRegs, node.position);
          }
        }
      } else if (op is BaseReg && op.isPhysical) {
        // Physical Register Operand: update used/clobbered masks.
        if ((currentFlags & (RATiedFlags.kWrite | RATiedFlags.kOut)) != 0) {
          clobbered[op.group] |= (1 << op.id);
        }
        if ((currentFlags & (RATiedFlags.kRead | RATiedFlags.kUse)) != 0) {
          used[op.group] |= (1 << op.id);
        }
      }
    }

    _arch.implicitRegs(node, used, clobbered);
  }

  void _analyzeRet(FuncRetNode node, List<RATiedReg> tiedRegs) {
    final detail = _func!.detail;
    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        // Assuming 1-to-1 mapping for now (simple scalar return)
        final retVal = detail.rets[i];
        if (retVal.isReg) {
          final physId = retVal.regId;

          RAWorkId workId;
          if (_virtIdToWorkId.containsKey(op.id)) {
            workId = _virtIdToWorkId[op.id]!;
          } else {
            final workReg = _allocator.addWorkReg(op.group, op);
            workId = workReg.workId;
            _virtIdToWorkId[op.id] = workId;
          }

          final workReg = _allocator.workRegById(workId);

          // Use | Read | UseFixed
          int flags =
              RATiedFlags.kUse | RATiedFlags.kRead | RATiedFlags.kUseFixed;
          if (_lastUsePos[op.id] == node.position) {
            flags |= RATiedFlags.kKill;
          }

          _tie(tiedRegs, workReg, flags, 1 << physId, physId, 0,
              RAAssignment.kPhysNone);
        }
      }
    }
  }

  /// Operand read/write flags of [node]. Function return operands are
  /// always uses (their instruction id is not a real instruction).
  List<int> _operandFlags(InstNode node) {
    if (node is FuncRetNode) {
      return List<int>.filled(
          node.opCount, RATiedFlags.kUse | RATiedFlags.kRead);
    }
    return _arch.operandFlags(node);
  }

  /// Adds a tied register, merging with an existing tie of the same work
  /// register in this instruction (as `RAInstBuilder::add()` does).
  void _tie(List<RATiedReg> tiedRegs, RAWorkReg workReg, int flags, int useMask,
      int useId, int outMask, int outId) {
    for (final t in tiedRegs) {
      if (identical(t.workReg, workReg)) {
        t.merge(flags, useMask, useId, outMask, outId);
        return;
      }
    }
    final tied = RATiedReg();
    tied.init(workReg, flags, useMask, useId, 0, outMask, outId, 0);
    tiedRegs.add(tied);
  }

  void _addImplicitUse(BaseReg reg, List<RATiedReg> tiedRegs, int pos) {
    RAWorkId workId;
    if (_virtIdToWorkId.containsKey(reg.id)) {
      workId = _virtIdToWorkId[reg.id]!;
    } else {
      final workReg = _allocator.addWorkReg(reg.group, reg);
      workId = workReg.workId;
      _virtIdToWorkId[reg.id] = workId;
    }
    final workReg = _allocator.workRegById(workId);
    int flags = RATiedFlags.kRead | RATiedFlags.kUse;

    if (_lastUsePos[reg.id] == pos) {
      flags |= RATiedFlags.kKill;
    }

    _tie(tiedRegs, workReg, flags, 0xFFFFFFFF, RAAssignment.kPhysNone,
        0xFFFFFFFF, RAAssignment.kPhysNone);
  }

  void _rewriteInstruction(InstNode node, List<RATiedReg> tiedRegs) {
    // Prefer usar o mapeamento definitivo do curAssignment para garantir que
    // todo virtual (incluindo bases/índices de memória) vire o registrador
    // físico correto, evitando perda de base ou conversão incorreta para
    // RIP-relative.
    // Ties are merged per work register, so look them up by register rather
    // than by operand position. Like asmjit's rewriter, an operand that is
    // written uses the tie's output register and a read-only operand (or a
    // memory base/index) its input register.
    final opFlags = _operandFlags(node);
    int physOf(BaseReg reg, {bool write = false}) {
      final workId = _virtIdToWorkId[reg.id];
      if (workId == null) return RAAssignment.kPhysNone;
      for (final t in tiedRegs) {
        if (t.workReg.workId != workId) continue;
        if (write && t.isOut && t.outId != RAAssignment.kPhysNone) {
          return t.outId;
        }
        if (t.isUse && t.useId != RAAssignment.kPhysNone) return t.useId;
        final id = _resolvePhysId(t);
        if (id != RAAssignment.kPhysNone) return id;
      }
      return _allocator.curAssignment.workToPhysId(reg.group, workId);
    }

    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        final f = i < opFlags.length ? opFlags[i] : 0;
        final physId = physOf(op,
            write: (f & (RATiedFlags.kOut | RATiedFlags.kWrite)) != 0);
        if (physId != RAAssignment.kPhysNone) {
          node.operands[i] = op.toPhys(physId);
        }
      } else if (op is BaseMem) {
        // Caso especial: operandos de stack criados via newStack (base = VirtReg
        // marcado como stack slot). Convertemos para [RBP+offset] imediatamente,
        // evitando que o registrador virtual seja tratado como ponteiro lixo.
        if (op.base != null && !op.base!.isPhysical) {
          final workId = _virtIdToWorkId[op.base!.id];
          if (workId != null) {
            final workReg = _allocator.workRegById(workId);
            if (workReg.isStackSlot) {
              BaseReg? newIndex = op.index;
              if (op.index != null && !op.index!.isPhysical) {
                final physId = physOf(op.index!);
                if (physId != RAAssignment.kPhysNone) {
                  newIndex = op.index!.toPhys(physId);
                }
              }

              final stackMem = _stackSlot(workReg);
              node.operands[i] = _arch.rebuildMem(op,
                  base: stackMem.base,
                  index: newIndex,
                  displacement: stackMem.displacement + op.displacement,
                  size: op.size != 0 ? op.size : stackMem.size);
              continue;
            }
          }
        }

        BaseReg? newBase = op.base;
        BaseReg? newIndex = op.index;

        if (op.base != null && !op.base!.isPhysical) {
          final physId = physOf(op.base!);
          if (physId != RAAssignment.kPhysNone) {
            newBase = op.base!.toPhys(physId);
          }
        }

        if (op.index != null && !op.index!.isPhysical) {
          final physId = physOf(op.index!);
          if (physId != RAAssignment.kPhysNone) {
            newIndex = op.index!.toPhys(physId);
          }
        }

        if (!identical(newBase, op.base) || !identical(newIndex, op.index)) {
          node.operands[i] = _arch.rebuildMem(op,
              base: newBase,
              index: newIndex,
              displacement: op.displacement,
              size: op.size);
        }
      }
    }
  }

  int _resolvePhysId(RATiedReg tied) {
    if (tied.isOut && tied.outId != RAAssignment.kPhysNone) {
      return tied.outId;
    } else if (tied.isUse && tied.useId != RAAssignment.kPhysNone) {
      return tied.useId;
    }
    return RAAssignment.kPhysNone;
  }

  // Emission callbacks
  void _emitLoad(RAWorkReg workReg, int physId, InstNode ctx) {
    _insertNodeBefore(
        ctx, _arch.load(workReg.virtReg.toPhys(physId), _stackSlot(workReg)));
  }

  void _emitSave(RAWorkReg workReg, int physId, InstNode ctx) {
    _insertNodeBefore(
        ctx, _arch.save(_stackSlot(workReg), workReg.virtReg.toPhys(physId)));
  }

  void _emitMove(RAWorkReg workReg, int dst, int src, InstNode ctx) {
    _insertNodeBefore(ctx,
        _arch.move(workReg.virtReg.toPhys(dst), workReg.virtReg.toPhys(src)));
  }

  void _emitSwap(
      RAWorkReg aReg, int aPhys, RAWorkReg bReg, int bPhys, InstNode ctx) {
    for (final node
        in _arch.swap(aReg.virtReg.toPhys(aPhys), bReg.virtReg.toPhys(bPhys))) {
      _insertNodeBefore(ctx, node);
    }
  }

  /// Size and alignment of the stack slot of [workReg].
  ///
  /// Stack areas created by newStack() have their own size and alignment;
  /// the size is rounded up to the alignment so the slot is aligned both when
  /// addressed upwards from the stack pointer (AArch64) and downwards from
  /// the frame pointer (x86), which are 16-byte aligned.
  (int, int) _stackSlotLayout(RAWorkReg workReg) {
    final vIndex = workReg.virtReg.id - Globals.kMinVirtId;
    if (workReg.isStackSlot &&
        vIndex >= 0 &&
        vIndex < compiler.virtRegs.length) {
      final vr = compiler.virtRegs[vIndex];
      if (vr.alignment > 16) {
        throw UnsupportedError(
            'stack area alignment ${vr.alignment} > 16 is not supported');
      }
      final align = vr.alignment < 4 ? 4 : vr.alignment;
      return ((vr.size + align - 1) & ~(align - 1), align);
    }
    final size = _arch.spillSize(workReg.virtReg);
    return (size, size > 4 ? size : 4);
  }

  BaseMem _stackSlot(RAWorkReg workReg) {
    final (size, align) = _stackSlotLayout(workReg);
    // Stack allocation using FuncFrame logic
    if (workReg.stackOffset == 0 &&
        !workReg.hasFlag(RAWorkRegFlags.kStackUsed)) {
      final frame = _func!.frame;

      // Simple stack bump allocation with alignment
      int offset = _spillStackSize;
      if (offset % align != 0) {
        offset += align - (offset % align);
      }

      _spillStackSize = offset + size;

      // Update frame local stack size (accumulate)
      if (frame.localStackSize < _spillStackSize) {
        frame.setLocalStackSize(_spillStackSize);
      }

      // Offset inside the spill area; RAArch maps it to a frame address.
      workReg.stackOffset = offset;

      workReg.addFlags(RAWorkRegFlags.kStackUsed);
    }

    return _arch.spillSlot(compiler, workReg.stackOffset, size);
  }

  int _spillStackSize = 0;

  void _insertPrologEpilog() {
    final func = _func;
    if (func == null) return;

    _arch.insertPrologEpilog(RAFrameContext(
      compiler: compiler,
      func: func,
      spillSize: _spillStackSize,
      available: _allocator.availableRegs,
      preserved: _allocator.funcPreservedRegs,
      clobbered: _allocator.clobberedRegs,
    ));
  }

  void _insertNodeAfter(BaseNode after, BaseNode newNode) {
    compiler.nodes.insertAfter(newNode, after);
  }

  void _insertNodeBefore(BaseNode before, BaseNode newNode) {
    compiler.nodes.insertBefore(newNode, before);
  }
}

class _RAMove {
  final RAWorkReg workReg;
  int fromPhys;
  int toPhys;
  _RAMove(this.workReg, this.fromPhys, this.toPhys);
}
