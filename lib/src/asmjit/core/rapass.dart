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
import 'compiler.dart';
import 'globals.dart'; // Needed for Globals.kNumVirtGroups
import 'radefs.dart';
import 'ralocal.dart';
import 'bitvector.dart';
import 'ranode_data.dart';
import '../x86/x86.dart';
import '../x86/x86_simd.dart';

import '../x86/x86_operands.dart';
import '../x86/x86_inst_db.g.dart';
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
  final List<_RACoalesceCandidate> _coalescingCandidates = [];

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
      _insertArgMoves(blocks.first);

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
          final workId = _virtIdToWorkId[virtId]!;
          final workReg = _allocator.workRegById(workId);
          final physArg = detail.args[i][0];

          if (physArg.isReg) {
            workReg.homeRegId = physArg.regId;
          }
          // TODO: Handle stack arguments
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

              int instId;
              if (virtReg.group == RegGroup.gp) {
                instId = X86InstId.kMov;
              } else {
                // Vector arguments
                instId = X86InstId.kMovaps;
              }

              final physReg = virtReg.toPhys(physArg.regId);
            print('RAPass: Insert Arg Move Virt${virtReg.id} <- Phys${physArg.regId}');
            final movNode = InstNode(instId, [virtReg, physReg]);
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

    final arch = compiler.arch;

    if (arch == Arch.x64) {
      // Use x64 masks from x86.dart
      // Support for both Windows (Win64) and Linux/Mac (System V)

      bool isWindows = false;
      try {
        // Basic check if we are running on Windows VM
        // Since 'dart:io' might not be available in all contexts (e.g. web), we wrap it or assume user config.
        // However, for this project which depends on FFI, dart:io is expected.
        // Ideally, the 'Compiler' instance should provide the target OS.
        // For now, we use a simple heuristic or Platform check if available.
        // import 'dart:io' is needed at file level.
        // Assuming explicit default to Windows if not specified, but here we try logic:
        // environment is not nullable in BaseCompiler
        isWindows = compiler.environment.os == 'windows';
      } catch (e) {
        // Fallback if env check fails for some reason
        isWindows = Platform.isWindows;
      }
      print('RAPass: isWindows=$isWindows');

      final preservedGp =
          isWindows ? x64WindowsPreservedGp : x64SystemVPreservedGp;
      // All GPs (0-15) are available except RSP (4). RBP (5) is usually preserved.
      // Available: All 16 minus Stack Pointer.
      // In AsmJit, available means "allocatable".

      int gpMask = 0xFFFF;
      gpMask &= ~(1 << 4); // Remove RSP
      gpMask &= ~(1 << 5); // Remove RBP (Frame Pointer)

      avail[RegGroup.gp] = gpMask;
      // Disponibiliza XMM0-XMM15 (Win64 tem 16 regs; AVX512 n�o est� habilitado aqui)
      avail[RegGroup.vec] = 0xFFFF;

      // Set preserved mask
      int presGp = 0;
      for (final reg in preservedGp) {
        presGp |= (1 << reg.id);
      }
      preserved[RegGroup.gp] = presGp;

      // XMM 6-15 are volatile on Win64?
      // Win64: XMM6-XMM15 are non-volatile (preserved). XMM0-XMM5 volatile.
      // SysV: All XMM volatile? No, check ABI.
      // Win64: XMM6-XMM15 must be preserved.

      // Win64: XMM6-XMM15 s�o preservados (callee-saved).
      if (isWindows) {
        int presVec = 0;
        for (int i = 6; i <= 15; i++) {
          presVec |= (1 << i);
        }
        preserved[RegGroup.vec] = presVec;
      } else {
        preserved[RegGroup.vec] = 0;
      }
    } else {
      // x86 (32-bit) defaults
      avail[RegGroup.gp] = 0xFF & ~(1 << 4); // Remove ESP
      avail[RegGroup.vec] = 0xFF; // 8 XMMs

      // Preserved: EBX, ESI, EDI, EBP
      int presGp = (1 << 3) | (1 << 6) | (1 << 7) | (1 << 5);
      preserved[RegGroup.gp] = presGp;
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

              final vIndex = op.id - Globals.kMinVirtId;
              if (vIndex >= 0 && vIndex < compiler.virtRegs.length) {
                if (compiler.virtRegs[vIndex].isStack) {
                  workReg.markStackSlot();
                }
              }
            }
          } else if (op is X86Mem) {
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
    print('RAPass: LiveSpans');
    for (int i = 0; i < _numWorkRegs; i++) {
      final workReg = _allocator.workRegById(i);
      final spans = workReg.liveSpans.data.map((s) => '[${s.a}, ${s.b}]').join(', ');
      print('  Virt${workReg.virtReg.id}: $spans');
    }
  }

  void _analyzeInstLiveness(InstNode node, RABlockData data) {
    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];
      
      // Handle direct virtual registers
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        final workId = _virtIdToWorkId[op.id];
        if (workId != null) {
          final workReg = _allocator.workRegById(workId);
          // Update frequency
          workReg.liveStats.freq += data.weight;

          if (i == 0 && node.instId == _archTraits.movId) {
            // DEF for Mov - simplified
            data.kill.setBit(workId);
          } else if (i == 0) {
            // Check for other Move instructions (SIMD, AVX)
            bool isMov = (node.instId == X86InstId.kMovaps ||
                node.instId == X86InstId.kMovups ||
                node.instId == X86InstId.kMovdqa ||
                node.instId == X86InstId.kMovdqu ||
                node.instId == X86InstId.kMovss ||
                node.instId == X86InstId.kMovsd ||
                node.instId == X86InstId.kMovd ||
                node.instId == X86InstId.kMovq ||
                node.instId == X86InstId.kVmovaps ||
                node.instId == X86InstId.kVmovups ||
                node.instId == X86InstId.kVmovdqa ||
                node.instId == X86InstId.kVmovdqu ||
                node.instId == X86InstId.kVmovss ||
                node.instId == X86InstId.kVmovsd ||
                node.instId == X86InstId.kVmovd ||
                node.instId == X86InstId.kVmovq);

            if (isMov) {
              data.kill.setBit(workId);
            } else {
              // RW for destructive (non-mov)
              if (!data.kill.testBit(workId)) {
                data.gen.setBit(workId);
              }
              data.kill.setBit(workId);
            }
          } else {
            // USE
            if (!data.kill.testBit(workId)) {
              data.gen.setBit(workId);
            }
          }
        }
      } else if (op is X86Mem) {
        // Handle memory operands (Base and Index are implicit USE)
        if (op.base != null && !op.base!.isPhysical) {
           final workId = _virtIdToWorkId[op.base!.id];
           if (workId != null) {
              final workReg = _allocator.workRegById(workId);
              workReg.liveStats.freq += data.weight;
              if (!data.kill.testBit(workId)) {
                 data.gen.setBit(workId);
              }
           }
        }
        if (op.index != null && !op.index!.isPhysical) {
           final workId = _virtIdToWorkId[op.index!.id];
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
    BlockNode? currentBlock;

    for (final node in nodes.nodes) {
      if (node is BlockNode) {
        // Close previous block
        if (currentBlock != null) {
           final data = _blockData[currentBlock.label.id]!;
           for (final workId in data.liveOut.setBits) {
              final workReg = _allocator.workRegById(workId);
              // Extend to current position (end of block)
              workReg.liveSpans.openAt(currentBlock.position, position);
           }
        }

        currentBlock = node;
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
          } else if (op is X86Mem) {
             // Handle Mem Liveness
             if (op.base != null && !op.base!.isPhysical) {
                final workId = _virtIdToWorkId[op.base!.id];
                if (workId != null) {
                   _lastUsePos[op.base!.id] = position;
                   _allocator.workRegById(workId).liveSpans.openAt(position, position + 2);
                }
             }
             if (op.index != null && !op.index!.isPhysical) {
                final workId = _virtIdToWorkId[op.index!.id];
                if (workId != null) {
                   _lastUsePos[op.index!.id] = position;
                   _allocator.workRegById(workId).liveSpans.openAt(position, position + 2);
                }
             }
          }
        }
        position += 2;
      }
    }

    // Close last block
    if (currentBlock != null) {
       final data = _blockData[currentBlock.label.id]!;
       for (final workId in data.liveOut.setBits) {
          final workReg = _allocator.workRegById(workId);
          workReg.liveSpans.openAt(currentBlock.position, position);
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
            workReg.setHomeRegId(consecutiveId);
            physRegsMask = (1 << consecutiveId);
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

    _emitTransitionMoves(from, fromState, toState, insertionPoint);
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
      final save = InstNode(_archTraits.movId, [mem, srcReg]);
      _insertResolution(block, insertionPoint, save);
    }

    // 2. Resolve Reg-Reg moves (cycle breaking)
    _resolveParallelMoves(block, insertionPoint, moves);

    // 3. Loads (Write to regs)
    for (final move in loads) {
      final dstReg = move.workReg.virtReg.toPhys(move.toPhys);
      final mem = _stackSlot(move.workReg);
      final load = InstNode(_archTraits.movId, [dstReg, mem]);
      _insertResolution(block, insertionPoint, load);
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
          final mov = InstNode(_archTraits.movId, [dstReg, srcReg]);
          _insertResolution(block, insertionPoint, mov);

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

      // Check if swap supported
      final xchg = InstNode(_archTraits.xchgId, [dstReg, srcReg]);
      _insertResolution(block, insertionPoint, xchg);

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
    if (node is FuncRetNode) {
      _analyzeRet(node, tiedRegs);
      return;
    }

    if (node.hasNoOperands) return;

    final id = node.instId;
    final opCount = node.opCount;

    // --- Heuristic Flags Determination ---
    int op0Flags = 0;
    int op1Flags = 0;
    int op2Flags = 0;
    int op3Flags = 0;

    // Detection of instruction groups
    // This is a simplified classifier. In full AsmJit, this comes from InstDB.

    bool isMov = (id == X86InstId.kMov ||
        id == X86InstId.kMovabs ||
        id == X86InstId.kMovaps ||
        id == X86InstId.kMovups ||
        id == X86InstId.kMovss ||
        id == X86InstId.kMovsd ||
        id == X86InstId.kMovd ||
        id == X86InstId.kMovq ||
        id == X86InstId.kMovdqa ||
        id == X86InstId.kMovdqu ||
        id == X86InstId.kMovzx ||
        id == X86InstId.kMovsx ||
        id == X86InstId.kMovsxd ||
        id == X86InstId.kVmovaps ||
        id == X86InstId.kVmovups ||
        id == X86InstId.kVmovss ||
        id == X86InstId.kVmovsd ||
        id == X86InstId.kVmovd ||
        id == X86InstId.kVmovq ||
        id == X86InstId.kVmovdqa ||
        id == X86InstId.kVmovdqu);

    bool isXchg = (id == X86InstId.kXchg);

    // Read-Only instructions (Test, Cmp)
    bool isTest = (id == X86InstId.kTest ||
        id == X86InstId.kCmp ||
        id == X86InstId.kComiss ||
        id == X86InstId.kComisd ||
        id == X86InstId.kUcomiss ||
        id == X86InstId.kUcomisd ||
        id == X86InstId.kPtest ||
        id == X86InstId.kVptest);

    bool isPush = (id == X86InstId.kPush);
    bool isPop = (id == X86InstId.kPop);

    // 3+ operand, usually AVX/AVX-512 non-destructive
    // OR Shift with imm/cl (Shl reg, imm -> RW)
    bool is3Op = (opCount >= 3);

    // Define flags per operand index
    if (isMov) {
      // MOV Op0, Op1
      // Op0 is Write (Out), Op1 is Read (Use)
      op0Flags = RATiedFlags.kOut | RATiedFlags.kWrite;
      if (opCount > 1) op1Flags = RATiedFlags.kUse | RATiedFlags.kRead;
    } else if (isXchg) {
      // XCHG Op0, Op1
      // Both are R/W
      op0Flags = RATiedFlags.kUse |
          RATiedFlags.kRead |
          RATiedFlags.kOut |
          RATiedFlags.kWrite;
      op1Flags = RATiedFlags.kUse |
          RATiedFlags.kRead |
          RATiedFlags.kOut |
          RATiedFlags.kWrite;
    } else if (isTest) {
      // TEST/CMP Op0, Op1
      // Both are Read
      op0Flags = RATiedFlags.kUse | RATiedFlags.kRead;
      if (opCount > 1) op1Flags = RATiedFlags.kUse | RATiedFlags.kRead;
    } else if (isPush) {
      // PUSH Op0
      // Read
      op0Flags = RATiedFlags.kUse | RATiedFlags.kRead;
    } else if (isPop) {
      // POP Op0
      // Write
      op0Flags = RATiedFlags.kOut | RATiedFlags.kWrite;
    } else if (is3Op) {
      // AVX: VADDPS zmm1, zmm2, zmm3
      // Op0 = Out, Op1 = Use, Op2 = Use
      // Note: Some legacy instructions/FMA might be different, but this covers 90% of AVX
      op0Flags = RATiedFlags.kOut | RATiedFlags.kWrite;
      op1Flags = RATiedFlags.kUse | RATiedFlags.kRead;
      op2Flags = RATiedFlags.kUse | RATiedFlags.kRead;
      if (opCount > 3) op3Flags = RATiedFlags.kUse | RATiedFlags.kRead;
    } else {
      // Default 2-operand destructive: ADD Op0, Op1
      // Op0 is R/W, Op1 is Read
      op0Flags = RATiedFlags.kUse |
          RATiedFlags.kRead |
          RATiedFlags.kOut |
          RATiedFlags.kWrite;
      if (opCount > 1) op1Flags = RATiedFlags.kUse | RATiedFlags.kRead;
    }

    // --- Operand Iteration ---

    for (int i = 0; i < opCount; i++) {
      final op = node.operands[i];
      int currentFlags = 0;
      if (i == 0)
        currentFlags = op0Flags;
      else if (i == 1)
        currentFlags = op1Flags;
      else if (i == 2)
        currentFlags = op2Flags;
      else
        currentFlags = op3Flags;

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
        final tied = RATiedReg();

        // Check for Last Use (Kill)
        if ((currentFlags & RATiedFlags.kRead) != 0) {
          if (_lastUsePos[op.id] == node.position) {
            currentFlags |= RATiedFlags.kKill;
          }
        }

        // Apply Masks
        int useMask = 0xFFFFFFFF;
        int outMask = 0xFFFFFFFF;
        int useId = RAAssignment.kPhysNone;
        int outId = RAAssignment.kPhysNone;

        // Constraint Logic (Basic DB replacement)
        if (i == 1 &&
            (id == X86InstId.kShl ||
                id == X86InstId.kShr ||
                id == X86InstId.kSar ||
                id == X86InstId.kRol ||
                id == X86InstId.kRor)) {
          // Shift count must be in CL (RCX)
          useMask = (1 << 1); // RCX=1
          useId = 1;
        }

        tied.init(workReg, currentFlags, useMask, useId, 0, outMask, outId, 0);
        tiedRegs.add(tied);
      } else if (op is X86Mem) {
        // Memory Operand - check for virtual registers in Base/Index
        // Memory operands are always READs effectively for the register allocator
        // (we listen to Base/Index reads).
        // Even if the instruction Writes to Mem (MOV [rax], rbx), 'rax' is Read.

        if (op.base != null && !op.base!.isPhysical) {
          _addImplicitUse(op.base!, tiedRegs, node.position);
        }
        if (op.index != null && !op.index!.isPhysical) {
          _addImplicitUse(op.index!, tiedRegs, node.position);
        }

        // Physical regs in Mem
        if (op.base != null && op.base!.isPhysical) {
          used[op.base!.group] |= (1 << op.base!.id);
        }
        if (op.index != null && op.index!.isPhysical) {
          used[op.index!.group] |= (1 << op.index!.id);
        }
      } else if (op is BaseReg && op.isPhysical) {
        // Physical Register Operand
        // Update Used/Clobbered masks
        if ((currentFlags & (RATiedFlags.kWrite | RATiedFlags.kOut)) != 0) {
          clobbered[op.group] |= (1 << op.id);
        }
        if ((currentFlags & (RATiedFlags.kRead | RATiedFlags.kUse)) != 0) {
          used[op.group] |= (1 << op.id);
        }
      }
    }

    // Implicit Definitions (DIV/MUL)
    if (id == X86InstId.kDiv || id == X86InstId.kIdiv || id == X86InstId.kMul) {
      clobbered[RegGroup.gp] |= (1 << 0) | (1 << 2); // RAX, RDX
      used[RegGroup.gp] |= (1 << 0) | (1 << 2); // Input also
    } else if (id == X86InstId.kCpuid) {
      clobbered[RegGroup.gp] |=
          (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3); // EAX, EBX, ECX, EDX
      used[RegGroup.gp] |= (1 << 0); // EAX input
    }
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
          final tied = RATiedReg();

          // Use | Read | UseFixed
          int flags =
              RATiedFlags.kUse | RATiedFlags.kRead | RATiedFlags.kUseFixed;
          if (_lastUsePos[op.id] == node.position) {
            flags |= RATiedFlags.kKill;
          }

          tied.init(workReg, flags, (1 << physId), physId, 0, 0,
              RAAssignment.kPhysNone, 0);
          tiedRegs.add(tied);
        }
      }
    }
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
    final tied = RATiedReg();
    int flags = RATiedFlags.kRead | RATiedFlags.kUse;

    if (_lastUsePos[reg.id] == pos) {
      flags |= RATiedFlags.kKill;
    }

    tied.init(workReg, flags, 0xFFFFFFFF, RAAssignment.kPhysNone, 0, 0xFFFFFFFF,
        RAAssignment.kPhysNone, 0);
    tiedRegs.add(tied);
  }

  void _rewriteInstruction(InstNode node, List<RATiedReg> tiedRegs) {
    int tiedIdx = 0;
    for (int i = 0; i < node.opCount; i++) {
      final op = node.operands[i];
      if (op is BaseReg && !op.isPhysical && !op.isNone) {
        if (tiedIdx < tiedRegs.length) {
          final tied = tiedRegs[tiedIdx++];
          final physId = _resolvePhysId(tied);

          if (physId != RAAssignment.kPhysNone) {
            node.operands[i] = tied.workReg.virtReg.toPhys(physId);
          }
        }
      } else if (op is X86Mem) {
        // Caso especial: operandos de stack criados via newStack (base = VirtReg
        // marcado como stack slot). Convertemos para [RBP+offset] imediatamente,
        // evitando que o registrador virtual seja tratado como ponteiro lixo.
        if (op.base != null && !op.base!.isPhysical) {
          final workId = _virtIdToWorkId[op.base!.id];
          if (workId != null) {
            final workReg = _allocator.workRegById(workId);
            if (workReg.isStackSlot) {
              // Consumir a entrada de tied para manter o cursor alinhado.
              if (tiedIdx < tiedRegs.length) tiedIdx++;

              BaseReg? newIndex = op.index;
              if (op.index != null && !op.index!.isPhysical) {
                if (tiedIdx < tiedRegs.length) {
                  final tied = tiedRegs[tiedIdx++];
                  final physId = _resolvePhysId(tied);
                  if (physId != RAAssignment.kPhysNone) {
                    newIndex = tied.workReg.virtReg.toPhys(physId);
                  }
                }
              }

              final stackMem = _stackSlot(workReg) as X86Mem;
              final disp = stackMem.displacement + op.displacement;
              final size = op.size != 0 ? op.size : stackMem.size;

              node.operands[i] = X86Mem(
                  base: stackMem.base,
                  index: newIndex,
                  scale: op.scale,
                  displacement: disp,
                  size: size,
                  segment: op.segment);
              continue;
            }
          }
        }

        BaseReg? newBase = op.base;
        BaseReg? newIndex = op.index;
        bool changed = false;

        if (op.base != null && !op.base!.isPhysical) {
          if (tiedIdx < tiedRegs.length) {
            final tied = tiedRegs[tiedIdx++];
            final physId = _resolvePhysId(tied);
            if (physId != RAAssignment.kPhysNone) {
              newBase = tied.workReg.virtReg.toPhys(physId);
              changed = true;
            }
          }
        }

        if (op.index != null && !op.index!.isPhysical) {
          if (tiedIdx < tiedRegs.length) {
            final tied = tiedRegs[tiedIdx++];
            final physId = _resolvePhysId(tied);
            if (physId != RAAssignment.kPhysNone) {
              newIndex = tied.workReg.virtReg.toPhys(physId);
              changed = true;
            }
          }
        }

        if (changed) {
          node.operands[i] = X86Mem(
              base: newBase,
              index: newIndex,
              scale: op.scale,
              displacement: op.displacement,
              size: op.size,
              segment: op.segment,
              label: op.label);
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
    final reg = workReg.virtReg.toPhys(physId);
    final mem = _stackSlot(workReg);
    
    int instId = _archTraits.movId;
    if (workReg.group == RegGroup.vec) {
      if (compiler.arch == Arch.x64 || compiler.arch == Arch.x86) {
        bool hasAvx = false;
        try {
          hasAvx = (compiler as dynamic).hasAvx;
        } catch (_) {}
        instId = hasAvx ? X86InstId.kVmovups : X86InstId.kMovups;
      }
    }

    final loadNode = InstNode(instId, [reg, mem]);
    _insertNodeBefore(ctx, loadNode);
  }

  void _emitSave(RAWorkReg workReg, int physId, InstNode ctx) {
    final reg = workReg.virtReg.toPhys(physId);
    final mem = _stackSlot(workReg);
    
    int instId = _archTraits.movId;
    if (workReg.group == RegGroup.vec) {
      if (compiler.arch == Arch.x64 || compiler.arch == Arch.x86) {
        bool hasAvx = false;
        try {
          hasAvx = (compiler as dynamic).hasAvx;
        } catch (_) {}
        instId = hasAvx ? X86InstId.kVmovups : X86InstId.kMovups;
      }
    }

    final saveNode = InstNode(instId, [mem, reg]);
    _insertNodeBefore(ctx, saveNode);
  }

  void _emitMove(RAWorkReg workReg, int dst, int src, InstNode ctx) {
    final dstReg = workReg.virtReg.toPhys(dst);
    final srcReg = workReg.virtReg.toPhys(src);
    
    int instId = _archTraits.movId;
    if (workReg.group == RegGroup.vec) {
      if (compiler.arch == Arch.x64 || compiler.arch == Arch.x86) {
        bool hasAvx = false;
        try {
          hasAvx = (compiler as dynamic).hasAvx;
        } catch (_) {}
        instId = hasAvx ? X86InstId.kVmovaps : X86InstId.kMovaps;
      }
    }

    final movNode = InstNode(instId, [dstReg, srcReg]);
    _insertNodeBefore(ctx, movNode);
  }

  void _emitSwap(
      RAWorkReg aReg, int aPhys, RAWorkReg bReg, int bPhys, InstNode ctx) {
    final rA = aReg.virtReg.toPhys(aPhys);
    final rB = bReg.virtReg.toPhys(bPhys);

    if (aReg.group == RegGroup.vec) {
      bool hasAvx = false;
      try {
        hasAvx = (compiler as dynamic).hasAvx;
      } catch (_) {}

      if (hasAvx) {
        // vpxor a, a, b
        _insertNodeBefore(ctx, InstNode(X86InstId.kVpxor, [rA, rA, rB]));
        // vpxor b, a, b
        _insertNodeBefore(ctx, InstNode(X86InstId.kVpxor, [rB, rA, rB]));
        // vpxor a, a, b
        _insertNodeBefore(ctx, InstNode(X86InstId.kVpxor, [rA, rA, rB]));
      } else {
        // pxor a, b
        _insertNodeBefore(ctx, InstNode(X86InstId.kPxor, [rA, rB]));
        // pxor b, a
        _insertNodeBefore(ctx, InstNode(X86InstId.kPxor, [rB, rA]));
        // pxor a, b
        _insertNodeBefore(ctx, InstNode(X86InstId.kPxor, [rA, rB]));
      }
      return;
    }

    final swapNode = InstNode(_archTraits.xchgId, [rA, rB]);
    _insertNodeBefore(ctx, swapNode);
  }

  BaseMem _stackSlot(RAWorkReg workReg) {
    // Stack allocation using FuncFrame logic
    if (workReg.stackOffset == 0 &&
        !workReg.hasFlag(RAWorkRegFlags.kStackUsed)) {
      final size = workReg.virtReg.size;
      final frame = _func!.frame;

      // Simple stack bump allocation with alignment
      int offset = _spillStackSize;

      // Align to 4 bytes minimally or size
      final align = size > 4 ? size : 4;
      if (offset % align != 0) {
        offset += align - (offset % align);
      }

      _spillStackSize = offset + size;

      // Update frame local stack size (accumulate)
      if (frame.localStackSize < _spillStackSize) {
        frame.setLocalStackSize(_spillStackSize);
      }

      // Store relative offset (negative from RBP)
      workReg.stackOffset = -(offset + size);

      workReg.addFlags(RAWorkRegFlags.kStackUsed);
    }

    return compiler.newStackSlot(
        _archTraits.fpRegId, workReg.stackOffset, workReg.virtReg.size);
  }

  int _spillStackSize = 0;

  void _insertPrologEpilog() {
    final func = _func;
    if (func == null) return;

    // Finalize frame to calculate total size
    func.frame.finalize();

    final arch = compiler.arch;
    final is64Bit = arch == Arch.x64;

    // Calculate registers to save
    final gpClobbered = _allocator.clobberedRegs[RegGroup.gp];
    final gpPreserved = _allocator.funcPreservedRegs[RegGroup.gp];
    final gpToSave = gpClobbered & gpPreserved;

    final vecClobbered = _allocator.clobberedRegs[RegGroup.vec];
    final vecPreserved = _allocator.funcPreservedRegs[RegGroup.vec];
    final vecToSave = vecClobbered & vecPreserved;

    final savedRegs = <X86Gp>[];
    for (int i = 0; i < 16; i++) {
      if ((gpToSave & (1 << i)) != 0) {
        savedRegs.add(X86Gp.r64(i));
      }
    }

    final savedVecRegs = <X86Xmm>[];
    for (int i = 0; i < 32; i++) {
      if ((vecToSave & (1 << i)) != 0) {
        savedVecRegs.add(X86Xmm(i));
      }
    }

    // Calculate layout (locals -> aligned vec spills -> aligned gp spills)
    int localsSize = _alignUp(_spillStackSize, 16);
    final vecSlots = <MapEntry<X86Xmm, int>>[];
    final gpSlots = <MapEntry<X86Gp, int>>[];

    int currentOffset = localsSize;

    if (savedVecRegs.isNotEmpty) {
      currentOffset = _alignUp(currentOffset, 16);
      for (final reg in savedVecRegs) {
        currentOffset += 16;
        vecSlots.add(MapEntry(reg, currentOffset));
      }
    }

    if (savedRegs.isNotEmpty) {
      currentOffset = _alignUp(currentOffset, 8);
      for (final reg in savedRegs) {
        currentOffset += 8;
        gpSlots.add(MapEntry(reg, currentOffset));
      }
    }

    int totalStackSize = _alignUp(currentOffset, 16);

    // Garanta que o frame conhe�a o tamanho real (locals + saves).
    if (func.frame.localStackSize < totalStackSize) {
      func.frame.setLocalStackSize(totalStackSize);
    }

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

      var lastNode = movRbpRsp;

      // Allocate stack (Locals + Saved Regs)
      if (totalStackSize > 0) {
        final subRsp = InstNode(X86InstId.kSub, [rsp, Imm(totalStackSize)]);
        _insertNodeAfter(lastNode, subRsp);
        lastNode = subRsp;
      }

      // Spill preserved vector registers using aligned stores.
      for (final slot in vecSlots) {
        final mem =
            X86Mem.baseDisp(rbp, -slot.value, size: 16);
        final save =
            InstNode(X86InstId.kMovdqu, [mem, slot.key]); // unaligned OK
        _insertNodeAfter(lastNode, save);
        lastNode = save;
      }

      // Spill preserved GP registers just below the vector area.
      for (final slot in gpSlots) {
        final mem = X86Mem.baseDisp(rbp, -slot.value);
        final save = InstNode(X86InstId.kMov, [mem, slot.key]);
        _insertNodeAfter(lastNode, save);
        lastNode = save;
      }
    }

    // Epilog - finding all Ret nodes
    final retNodes = <InstNode>[];
    for (final node in compiler.nodes.nodes) {
      if (node is InstNode && node.nodeType == NodeType.funcRet) {
        retNodes.add(node);
      }
    }

    for (final node in retNodes) {
      if (is64Bit) {
        final rbp = X86Gp.r64(X86RegId.rbp.index);
        final rsp = X86Gp.r64(X86RegId.rsp.index);

        // Restore registers (mirrors spill order)
        for (final slot in gpSlots.reversed) {
          final mem = X86Mem.baseDisp(rbp, -slot.value);
          final restore = InstNode(X86InstId.kMov, [slot.key, mem]);
          _insertNodeBefore(node, restore);
        }

        for (final slot in vecSlots.reversed) {
          final mem =
              X86Mem.baseDisp(rbp, -slot.value, size: 16);
          final restore =
              InstNode(X86InstId.kMovdqu, [slot.key, mem]); // unaligned OK
          _insertNodeBefore(node, restore);
        }

        // Restore RSP and RBP
        final movRspRbp = InstNode(X86InstId.kMov, [rsp, rbp]);
        final popRbp = InstNode(X86InstId.kPop, [rbp]);

        _insertNodeBefore(node, movRspRbp);
        _insertNodeBefore(node, popRbp);

        // Emit RET
        final retInst = InstNode(X86InstId.kRet, []);
        _insertNodeBefore(node, retInst);

        // Remove the abstract FuncRetNode
        compiler.nodes.remove(node);
      }
    }
  }

  int _alignUp(int value, int alignment) {
    if (alignment <= 0) return value;
    final mask = alignment - 1;
    return (value + mask) & ~mask;
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

class _RAMove {
  final RAWorkReg workReg;
  int fromPhys;
  int toPhys;
  _RAMove(this.workReg, this.fromPhys, this.toPhys);
}
