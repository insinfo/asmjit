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

    _allocator.init(compiler.arch, availableRegs, preservedRegs);

    // 3. Process Blocks
    // We assume CFG is built or we iterate linearly if local.
    // For RALocal, we can iterate blocks.

    BlockNode? currentBlock;

    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        currentBlock = node;
        _processBlock(currentBlock);
      }
    }

    // 4. Finalize
    // Insert prolog/epilog (if handled by RAPass or another pass)
    // _insertPrologEpilog(func);
  }

  void _initRegMasks(RARegMask avail, RARegMask preserved) {
    if (_func == null) return;

    // Retrieve architecture traits to determine available registers.

    // Default: make all registers available except SP/PC/Reserved.
    // This is a simplification. Ideally, we query the ArchTraits for "allocatable" mask.
    // For now, enabling all general purpose regs.
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
  }

  void _processBlock(BlockNode block) {
    // Reset allocator state for the block
    // _allocator.makeAllClean? Or init per block.

    // Iterate instructions in block
    BaseNode? node = block;
    while (node != null && node != block.successors.firstOrNull) {
      // Simple iteration
      if (node is InstNode) {
        _processInstruction(node);
      }
      // Logic to stop at next block or end of block
      if (node.next is BlockNode) break;
      node = node.next;
    }
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
        if (i == 0) {
          flags |= RATiedFlags.kWrite | RATiedFlags.kOut; // Def
        } else {
          flags |= RATiedFlags.kRead | RATiedFlags.kUse; // Use
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
    // Emit BEFORE ctx
    // Insert new load instruction
    final loadNode =
        InstNode(0 /* Mov */, [reg, mem]); // ID 0 is wrong, need Arch specific
    _insertNodeBefore(ctx, loadNode);
  }

  void _emitSave(RAWorkReg workReg, int physId, InstNode ctx) {
    final reg = workReg.virtReg.toPhys(physId);
    final mem = _stackSlot(workReg);
    // Emit AFTER ctx? Or BEFORE if it's a spill of prev value?
    // Spill usually happens before the instruction that needs the reg?
    // Or if it's an OUT that spills, it's after.
    // RALocal spills clobbered regs.
    // If we spill to free a register for USE, we save it BEFORE ctx.
    // If we spill an OUT reg, we might save it AFTER.
    // RALocal logic: "onSpillReg" is called when we need to free a reg.

    final saveNode = InstNode(0 /* Mov */, [mem, reg]);
    _insertNodeBefore(ctx, saveNode); // Default to before for spills
  }

  void _emitMove(RAWorkReg workReg, int dst, int src, InstNode ctx) {
    final dstReg = workReg.virtReg.toPhys(dst);
    final srcReg = workReg.virtReg.toPhys(src);
    final movNode = InstNode(0 /* Mov */, [dstReg, srcReg]);
    _insertNodeBefore(ctx, movNode);
  }

  void _emitSwap(
      RAWorkReg aReg, int aPhys, RAWorkReg bReg, int bPhys, InstNode ctx) {
    final rA = aReg.virtReg.toPhys(aPhys);
    final rB = bReg.virtReg.toPhys(bPhys);
    final swapNode = InstNode(0 /* Xchg */, [rA, rB]);
    _insertNodeBefore(ctx, swapNode);
  }

  void _insertNodeBefore(InstNode ctx, InstNode newNode) {
    // Use NodeList logic
    if (ctx.prev != null) {
      ctx.prev!.next = newNode;
      newNode.prev = ctx.prev;
      newNode.next = ctx;
      ctx.prev = newNode;
    }
    // Note: This modifies the list structure.
  }

  BaseMem _stackSlot(RAWorkReg workReg) {
    // return BaseMem.baseOffset(sp, offset...);
    // For now, throw to indicate missing stack logic
    throw UnimplementedError("Stack slot not implemented");
  }
}
