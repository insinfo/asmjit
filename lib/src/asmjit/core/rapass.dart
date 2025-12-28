/// AsmJit Register Allocation Pass
///
/// Implements `RAPass`, which drives the register allocation process.
/// It uses `RALocalAllocator` for local allocation and handles block ordering,
/// function frames, and instruction processing.
///
/// Ported from asmjit/core/rapass.cpp

import 'arch.dart';
import 'compiler.dart';
import 'globals.dart'; // Needed for Globals.kNumVirtGroups
import 'radefs.dart';
import 'ralocal.dart';
import 'bitvector.dart';
import 'ranode_data.dart';
import '../x86/x86.dart';
import '../x86/x86_inst_db.g.dart';
import 'raassignment.dart';

/// Register Allocation Pass.
///
/// This pass performs register allocation on the function. It currently
/// supports local register allocation (RAPass::kLocal).
class RAPass extends CompilerPass {
  final RALocalAllocator _allocator = RALocalAllocator();

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

  RAPass(BaseCompiler compiler) : super(compiler);

  @override
  void run(NodeList nodes) {
    // 1. Initialize
    final compiler = super.compiler;
    _archTraits = ArchTraits.forArch(
        compiler.arch); // Assuming compiler has arch property

    // Iterate over functions (usually one per compiler instance in this simplified view,
    // but AsmJit handles stream of nodes).

    // Find FuncNode
    FuncNode? func;
    for (final node in nodes.nodes) {
      if (node is FuncNode) {
        func = node;
        break; // Only support one function for now or iterate all?
      }
    }

    if (func == null) return;

    _processFunction(func, nodes);
  }

  void _processFunction(FuncNode func, NodeList nodes) {
    _func = func;

    // 2. Initialize Allocator
    // We need availableRegs and preservedRegs.
    // Ideally these come from the Compiler/Arch.
    // For now hardcoding based on arch traits or FuncFrame.

    RARegMask availableRegs = RARegMask();
    RARegMask preservedRegs = RARegMask();

    // Fill masks from ArchTraits/ABI
    // TODO: Get these from internal DB or Compiler state
    _initRegMasks(availableRegs, preservedRegs);

    // 2a. Map Virtual Registers (Pre-pass)
    _mapVirtuals(nodes);

    // 2b. Global Allocation (RAGlobal)
    _buildGlobalLiveness(nodes);
    _buildBundles();
    _binPack(availableRegs);

    _allocator.init(compiler.arch, availableRegs, preservedRegs);

    // 3. Process Blocks
    final blocks = <BlockNode>[];
    for (final node in nodes.nodes) {
      if (node is BlockNode) blocks.add(node);
    }

    if (blocks.isNotEmpty) {
      // Initialize first block entry from global decisions/hints
      _initFirstBlockEntry(blocks.first);

      for (final block in blocks) {
        _processBlock(block);
        _propagateAssignments(block);
      }
    }

    // 4. Finalize
    _insertPrologEpilog();
  }

  void _initRegMasks(RARegMask avail, RARegMask preserved) {
    if (_func == null) return;

    // Retrieve architecture traits to determine available registers.

    // Default: make all registers available except SP/PC/Reserved.
    // This is a simplification. Ideally, we query the ArchTraits for "allocatable" mask.
    avail.reset();
    preserved.reset();

    // Assume 32 registers for GP/Vec for simplicity or based on Arch.
    for (var group in RegGroup.values) {
      if (group.index >= Globals.kNumVirtGroups) continue;
      // TODO: Get real mask from ArchTraits
      avail[group] = 0xFFFFFFFF;

      // Remove reserved registers (SP, FP, LR/PC) based on Arch
      if (group == RegGroup.gp) {
        final traits = _archTraits;
        if (traits.spRegId != -1) avail.clear(group, 1 << traits.spRegId);
        if (traits.fpRegId != -1) avail.clear(group, 1 << traits.fpRegId);
        // Verify other reserved
      }
    }
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
            }
          }
        }
      }
    }
    _numWorkRegs = _virtIdToWorkId.length;
  }

  void _buildGlobalLiveness(NodeList nodes) {
    _blockData.clear();
    final blocks = <BlockNode>[];

    // 1. Initialize block data
    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        _blockData[node.label.id] = RABlockData(node.label.id, _numWorkRegs);
        blocks.add(node);
      }
    }

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
  }

  void _analyzeInstLiveness(InstNode node, RABlockData data) {
    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        final workId = _virtIdToWorkId[op.id];
        if (workId != null) {
          if (i == 0 && node.instId == _archTraits.movId) {
            // DEF for Mov - simplified
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
          // This is where we could merge RAWorkRegs or just set hints.
          // For now, we don't have a deep merge, so we just continue.
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

    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        final data = _blockData[node.label.id]!;
        node.position = position;

        for (final workId in data.liveIn.setBits) {
          final workReg = _allocator.workRegById(workId);
          workReg.liveSpans.openAt(position, position + 2);
        }
      }

      if (node is InstNode) {
        node.position = position;
        for (final op in node.operands) {
          if (op is BaseReg && !op.isPhysical && !op.isNone) {
            final workId = _virtIdToWorkId[op.id];
            if (workId != null) {
              _lastUsePos[op.id] = position;
              final workReg = _allocator.workRegById(workId);
              workReg.liveSpans.openAt(position, position + 2);
            }
          }
        }
        position += 2;
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

      // Calculate priority: usage frequency * total width
      // For now frequency is 1.0 (TODO: integrate block frequency)
      bundle.priority = workReg.liveSpans.totalWidth.toDouble();

      _bundles.add(bundle);
    }
  }

  void _binPack(RARegMask availableRegs) {
    // 1. Sort bundles by priority
    final sortedBundleIndices = List.generate(_bundles.length, (i) => i);
    sortedBundleIndices
        .sort((a, b) => _bundles[b].priority.compareTo(_bundles[a].priority));

    final globalSpans = List.generate(
        Globals.numVirtGroups, (_) => List.generate(32, (_) => RALiveSpans()));

    // 2. First Pass: Handle fixed hints (homeRegId)
    for (final bid in sortedBundleIndices) {
      final bundle = _bundles[bid];
      // For simplicity, take hint from the first workReg in bundle
      final firstWorkReg = _allocator.workRegById(bundle.workIds.first);

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
          }
        } else {
          bundle.physId = RAAssignment.kPhysNone;
        }
      }
    }

    // 3. Second Pass: Allocate others
    for (final bid in sortedBundleIndices) {
      final bundle = _bundles[bid];
      if (bundle.physId != RAAssignment.kPhysNone) continue;

      final firstWorkReg = _allocator.workRegById(bundle.workIds.first);
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
    final exitAssignment = data.exitAssignment;
    if (exitAssignment == null) return;

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

  void _resolveTransition(BlockNode from, BlockNode to,
      RAAssignmentState fromState, RAAssignmentState toState) {
    // Basic state resolution (matching C++ logic but simplified for non-critical edges)

    // 1. Identify where to insert resolution instructions.
    // If 'from' has multiple successors, it's safer to insert at the beginning of 'to'.
    // If 'to' has multiple predecessors, we should have split the edge.
    // Assuming we insert at the end of 'from' for now.

    final lastNode = from.lastNode;
    if (lastNode == null) return;

    final insertionPoint = (lastNode is JumpNode) ? lastNode : null;

    for (int i = 0; i < _numWorkRegs; i++) {
      final workReg = _allocator.workRegById(i);
      final fromPhys = fromState.workToPhysId(workReg.group, i);
      final toPhys = toState.workToPhysId(workReg.group, i);

      if (fromPhys == toPhys) continue; // Already matching

      if (fromPhys != RAAssignment.kPhysNone &&
          toPhys != RAAssignment.kPhysNone) {
        // Move from fromPhys to toPhys
        final srcReg = workReg.virtReg.toPhys(fromPhys);
        final dstReg = workReg.virtReg.toPhys(toPhys);
        final mov = InstNode(_archTraits.movId, [dstReg, srcReg]);
        _insertResolution(from, insertionPoint, mov);
      } else if (fromPhys != RAAssignment.kPhysNone &&
          toPhys == RAAssignment.kPhysNone) {
        // Spill (if needed - checking liveOut)
        final data = _blockData[from.label.id]!;
        if (data.liveOut.testBit(i)) {
          final srcReg = workReg.virtReg.toPhys(fromPhys);
          final mem = _stackSlot(workReg);
          final save = InstNode(_archTraits.movId, [mem, srcReg]);
          _insertResolution(from, insertionPoint, save);
        }
      } else if (fromPhys == RAAssignment.kPhysNone &&
          toPhys != RAAssignment.kPhysNone) {
        // Load
        final dstReg = workReg.virtReg.toPhys(toPhys);
        final mem = _stackSlot(workReg);
        final load = InstNode(_archTraits.movId, [dstReg, mem]);
        _insertResolution(from, insertionPoint, load);
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
        newNode.prev = last;
        newNode.next = last.next;
        if (last.next != null) last.next!.prev = newNode;
        last.next = newNode;
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
    if (node.prev != null) node.prev!.next = node.next;
    if (node.next != null) node.next!.prev = node.prev;
    // Note: NodeList doesn't know about this removal unless we use its methods.
    // However, NodeList.nodes uses the links, so it works.
  }

  void _analyzeInstruction(InstNode node, List<RATiedReg> tiedRegs,
      RARegMask used, RARegMask clobbered) {
    if (node.hasNoOperands) return;

    // We need to look at operands and create TiedRegs.
    // This requires knowing which operands are READ/WRITE.
    // We need InstructionAnalyzer for this!
    // But BaseCompiler might not have one exposed easily.
    // Assuming naive "RW" for now or using a helper.

    // Simple logic:
    // - First op is usually Def (Write) or RW
    // - Others are Use (Read)

    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        RAWorkId workId;
        if (_virtIdToWorkId.containsKey(op.id)) {
          workId = _virtIdToWorkId[op.id]!;
        } else {
          final workReg = _allocator.addWorkReg(op.group, op);
          workId = workReg.workId;
          _virtIdToWorkId[op.id] = workId;
        }

        final workReg = _allocator.workRegById(workId);
        final tied = RATiedReg();

        // Flags logic (Simplified)
        int flags = 0;
        if (i == 0 && node.instId == _archTraits.movId) {
          flags |= RATiedFlags.kWrite | RATiedFlags.kOut; // Def (Mov)
        } else if (i == 0) {
          flags |= RATiedFlags.kWrite |
              RATiedFlags.kRead |
              RATiedFlags.kOut |
              RATiedFlags.kUse; // Def (destructive)
        } else {
          flags |= RATiedFlags.kRead | RATiedFlags.kUse; // Use
        }

        if (_lastUsePos[op.id] == node.position) {
          flags |= RATiedFlags.kKill;
        }

        // TODO: Real constraints (useRegMask etc)
        int useMask = 0xFFFFFFFF;
        int outMask = 0xFFFFFFFF;

        tied.init(workReg, flags, useMask, RAAssignment.kPhysNone, 0, outMask,
            RAAssignment.kPhysNone, 0);
        tiedRegs.add(tied);
      } else if (op is BaseReg && op.isPhysical) {
        // Physical register usage
        if (i == 0)
          clobbered[op.group] |= (1 << op.id);
        else
          used[op.group] |= (1 << op.id);
      }
    }
  }

  void _rewriteInstruction(InstNode node, List<RATiedReg> tiedRegs) {
    // Create a map/list to identify which operand index corresponds to which tiedReg?
    // Our _analyzeInstruction iterated indices. We need to match them back.
    // For this simplified version, assuming tiedRegs order matches virtual operands order seen.

    int tiedIdx = 0;
    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        if (tiedIdx < tiedRegs.length) {
          final tied = tiedRegs[tiedIdx++];

          // Replace virtual with physical
          int physId = RAAssignment.kPhysNone;
          if (tied.isOut && tied.outId != RAAssignment.kPhysNone) {
            physId = tied.outId;
          } else if (tied.isUse && tied.useId != RAAssignment.kPhysNone) {
            physId = tied.useId;
          }

          if (physId != RAAssignment.kPhysNone) {
            // Replace!
            node.operands[i] = tied.workReg.virtReg.toPhys(physId);
          }
        }
      }
    }
  }

  // Emission callbacks
  void _emitLoad(RAWorkReg workReg, int physId, InstNode ctx) {
    final reg = workReg.virtReg.toPhys(physId);
    final mem = _stackSlot(workReg);
    final loadNode = InstNode(_archTraits.movId, [reg, mem]);
    _insertNodeBefore(ctx, loadNode);
  }

  void _emitSave(RAWorkReg workReg, int physId, InstNode ctx) {
    final reg = workReg.virtReg.toPhys(physId);
    final mem = _stackSlot(workReg);
    final saveNode = InstNode(_archTraits.movId, [mem, reg]);
    _insertNodeBefore(ctx, saveNode);
  }

  void _emitMove(RAWorkReg workReg, int dst, int src, InstNode ctx) {
    final dstReg = workReg.virtReg.toPhys(dst);
    final srcReg = workReg.virtReg.toPhys(src);
    final movNode = InstNode(_archTraits.movId, [dstReg, srcReg]);
    _insertNodeBefore(ctx, movNode);
  }

  void _emitSwap(
      RAWorkReg aReg, int aPhys, RAWorkReg bReg, int bPhys, InstNode ctx) {
    final rA = aReg.virtReg.toPhys(aPhys);
    final rB = bReg.virtReg.toPhys(bPhys);
    final swapNode = InstNode(_archTraits.xchgId, [rA, rB]);
    _insertNodeBefore(ctx, swapNode);
  }

  BaseMem _stackSlot(RAWorkReg workReg) {
    final traits = _archTraits;
    // For now simple stack allocation: each work reg gets its own slot if spilled.
    if (workReg.stackOffset == 0 &&
        !workReg.hasFlag(RAWorkRegFlags.kStackUsed)) {
      // Allocate new slot
      // This is VERY primitive, doesn't reuse slots.
      // Need a StackManager or FuncFrame to manage this.
      final size = workReg.virtReg.size;
      // Just an example offset, real logic should use FuncFrame.
      workReg.stackOffset = _func!.funcDetail.argStackSize;
      _func!.funcDetail.setArgStackSize(workReg.stackOffset + size);
      workReg.addFlags(RAWorkRegFlags.kStackUsed);
    }

    return compiler.newStackSlot(
        traits.spRegId, workReg.stackOffset, workReg.virtReg.size);
  }

  void _insertPrologEpilog() {
    final func = _func;
    if (func == null) return;

    // Simplistic prolog for now
    final arch = compiler.arch;
    final is64Bit = arch == Arch.x64;

    // Prolog
    if (is64Bit) {
      // push rbp; mov rbp, rsp
      final rbp = X86Gp.r64(X86RegId.rbp.index);
      final rsp = X86Gp.r64(X86RegId.rsp.index);

      final pushRbp = InstNode(X86InstId.kPush, [rbp]);
      final movRbpRsp = InstNode(X86InstId.kMov, [rbp, rsp]);

      // Insert at beginning of function
      _insertNodeAfter(func, pushRbp);
      _insertNodeAfter(pushRbp, movRbpRsp);
    }

    // Epilog - finding all Ret nodes
    for (final node in compiler.nodes.nodes) {
      if (node is InstNode && node.nodeType == NodeType.funcRet) {
        if (is64Bit) {
          final rbp = X86Gp.r64(X86RegId.rbp.index);
          final rsp = X86Gp.r64(X86RegId.rsp.index);

          final movRspRbp = InstNode(X86InstId.kMov, [rsp, rbp]);
          final popRbp = InstNode(X86InstId.kPop, [rbp]);

          _insertNodeBefore(node, movRspRbp);
          _insertNodeBefore(node, popRbp);
        }
      }
    }
  }

  void _insertNodeAfter(BaseNode after, BaseNode newNode) {
    newNode.prev = after;
    newNode.next = after.next;
    if (after.next != null) after.next!.prev = newNode;
    after.next = newNode;
  }

  void _insertNodeBefore(BaseNode before, BaseNode newNode) {
    newNode.next = before;
    newNode.prev = before.prev;
    if (before.prev != null) before.prev!.next = newNode;
    before.prev = newNode;
  }
}
