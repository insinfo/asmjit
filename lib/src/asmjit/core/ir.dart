// AsmJit Compiler IR (Intermediate Representation)
// Port of asmjit/core/compiler.h

import 'operand.dart';
import 'labels.dart';

/// Node type identifier.
enum NodeType {
  /// No node (invalid).
  none,

  /// Function entry node.
  func,

  /// Basic block node.
  block,

  /// Instruction node.
  inst,

  /// Label node.
  label,

  /// Jump node.
  jump,

  /// Return node.
  ret,

  /// Virtual register (SSA variable).
  virtualReg,

  /// Comment/annotation node.
  comment,
}

/// Base class for all IR nodes.
abstract class Node {
  final NodeType type;
  Node? prev;
  Node? next;

  Node(this.type);

  /// Returns true if this is a function node.
  bool get isFunc => type == NodeType.func;

  /// Returns true if this is a basic block node.
  bool get isBlock => type == NodeType.block;

  /// Returns true if this is an instruction node.
  bool get isInst => type == NodeType.inst;

  /// Returns true if this is a label node.
  bool get isLabel => type == NodeType.label;
}

/// Function node - represents a function with arguments, locals, and blocks.
class FuncNode extends Node {
  /// Function signature (arguments + return type).
  final String name;

  /// List of basic blocks in this function.
  final List<BlockNode> blocks = [];

  /// Entry block (first block in the function).
  BlockNode? entryBlock;

  /// Exit block (return block).
  BlockNode? exitBlock;

  /// Virtual registers allocated in this function.
  final List<VirtualReg> virtualRegs = [];

  /// Stack size needed for locals and spills (in bytes).
  int stackSize = 0;

  FuncNode(this.name) : super(NodeType.func);

  /// Create a new basic block in this function.
  BlockNode createBlock(String? name) {
    final block = BlockNode(name ?? 'BB${blocks.length}', this);
    blocks.add(block);
    return block;
  }

  /// Create a new virtual register.
  VirtualReg createVirtualReg(RegType type, {String? name}) {
    final reg = VirtualReg(
      virtualRegs.length,
      type,
      name: name ?? 'v${virtualRegs.length}',
    );
    virtualRegs.add(reg);
    return reg;
  }

  @override
  String toString() => 'FuncNode($name, ${blocks.length} blocks)';
}

/// Basic block node - represents a sequence of instructions with single entry/exit.
class BlockNode extends Node {
  /// Block name/label.
  final String name;

  /// Parent function.
  final FuncNode function;

  /// Instructions in this block.
  final List<InstNode> instructions = [];

  /// Predecessor blocks (blocks that jump to this block).
  final List<BlockNode> predecessors = [];

  /// Successor blocks (blocks this block can jump to).
  final List<BlockNode> successors = [];

  /// Label associated with this block.
  Label? label;

  /// Liveness information (in/out sets).
  final Set<VirtualReg> liveIn = {};
  final Set<VirtualReg> liveOut = {};

  BlockNode(this.name, this.function) : super(NodeType.block);

  /// Add an instruction to this block.
  void addInst(InstNode inst) {
    instructions.add(inst);
    inst.block = this;
  }

  /// Add a successor block (this block can jump to `succ`).
  void addSuccessor(BlockNode succ) {
    if (!successors.contains(succ)) {
      successors.add(succ);
      succ.predecessors.add(this);
    }
  }

  @override
  String toString() => 'BlockNode($name, ${instructions.length} insts)';
}

/// Instruction node - represents a single machine instruction.
class InstNode extends Node {
  /// Instruction mnemonic/opcode.
  final String mnemonic;

  /// Parent block.
  BlockNode? block;

  /// Operands (registers, immediates, memory).
  final List<Operand> operands = [];

  /// Virtual registers defined (written) by this instruction.
  final Set<VirtualReg> defs = {};

  /// Virtual registers used (read) by this instruction.
  final Set<VirtualReg> uses = {};

  InstNode(this.mnemonic) : super(NodeType.inst);

  /// Add an operand to this instruction.
  void addOperand(Operand op) {
    operands.add(op);
  }

  /// Mark a virtual register as defined by this instruction.
  void addDef(VirtualReg reg) {
    defs.add(reg);
  }

  /// Mark a virtual register as used by this instruction.
  void addUse(VirtualReg reg) {
    uses.add(reg);
  }

  @override
  String toString() =>
      'InstNode($mnemonic, ${operands.length} ops, defs=${defs.length}, uses=${uses.length})';
}

/// Label node - represents a code location.
class LabelNode extends Node {
  /// The label itself.
  final Label label;

  /// Name hint for debugging.
  final String? name;

  LabelNode(this.label, {this.name}) : super(NodeType.label);

  @override
  String toString() => 'LabelNode(${name ?? label.id})';
}

/// Virtual register (SSA variable).
class VirtualReg {
  /// Unique ID within the function.
  final int id;

  /// Register type (GP, XMM, etc.).
  final RegType type;

  /// Name hint for debugging.
  final String name;

  /// Physical register assigned by RA (null if not yet allocated).
  int? physicalReg;

  /// Spill slot index (if spilled to stack).
  int? spillSlot;

  /// Live range (instruction indices where this register is live).
  final Set<int> liveRange = {};

  VirtualReg(this.id, this.type, {required this.name});

  /// Returns true if this register has been allocated to a physical register.
  bool get isAllocated => physicalReg != null;

  /// Returns true if this register has been spilled to the stack.
  bool get isSpilled => spillSlot != null;

  @override
  String toString() {
    final buf = StringBuffer('VirtualReg($name, type=$type');
    if (physicalReg != null) {
      buf.write(', phys=$physicalReg');
    }
    if (spillSlot != null) {
      buf.write(', spill=$spillSlot');
    }
    buf.write(')');
    return buf.toString();
  }

  @override
  bool operator ==(Object other) => other is VirtualReg && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Control Flow Graph (CFG) for a function.
class CFG {
  /// The function this CFG represents.
  final FuncNode function;

  /// All blocks in reverse post-order (RPO).
  final List<BlockNode> rpo = [];

  /// Dominator tree (block -> immediate dominator).
  final Map<BlockNode, BlockNode> dominators = {};

  CFG(this.function);

  /// Build the CFG from the function's blocks.
  void build() {
    // Compute reverse post-order traversal
    _computeRPO();

    // Compute dominators
    _computeDominators();
  }

  void _computeRPO() {
    rpo.clear();
    final visited = <BlockNode>{};

    void visit(BlockNode block) {
      if (visited.contains(block)) return;
      visited.add(block);

      for (final succ in block.successors) {
        visit(succ);
      }

      rpo.insert(0, block); // Prepend for reverse post-order
    }

    if (function.entryBlock != null) {
      visit(function.entryBlock!);
    }
  }

  void _computeDominators() {
    // Simplified dominator calculation (iterative algorithm)
    dominators.clear();

    if (function.entryBlock == null || rpo.isEmpty) return;

    final entry = function.entryBlock!;
    dominators[entry] = entry; // Entry dominates itself

    bool changed = true;
    while (changed) {
      changed = false;

      for (final block in rpo.skip(1)) {
        // Skip entry
        BlockNode? newIdom;

        for (final pred in block.predecessors) {
          if (dominators.containsKey(pred)) {
            newIdom = _intersect(pred, newIdom);
          }
        }

        if (newIdom != null && dominators[block] != newIdom) {
          dominators[block] = newIdom;
          changed = true;
        }
      }
    }
  }

  BlockNode? _intersect(BlockNode b1, BlockNode? b2) {
    if (b2 == null) return b1;

    var finger1 = b1;
    var finger2 = b2;

    while (finger1 != finger2) {
      while (rpo.indexOf(finger1) < rpo.indexOf(finger2)) {
        finger1 = dominators[finger1]!;
      }
      while (rpo.indexOf(finger2) < rpo.indexOf(finger1)) {
        finger2 = dominators[finger2]!;
      }
    }

    return finger1;
  }

  /// Compute liveness information for all blocks.
  void computeLiveness() {
    // Backward dataflow analysis
    bool changed = true;
    while (changed) {
      changed = false;

      for (final block in rpo.reversed) {
        // liveOut[B] = union of liveIn[S] for all successors S
        final oldOut = Set<VirtualReg>.from(block.liveOut);
        block.liveOut.clear();

        for (final succ in block.successors) {
          block.liveOut.addAll(succ.liveIn);
        }

        // liveIn[B] = use[B] union (liveOut[B] - def[B])
        final oldIn = Set<VirtualReg>.from(block.liveIn);
        block.liveIn.clear();

        for (final inst in block.instructions) {
          block.liveIn.addAll(inst.uses);
        }

        final liveOutMinusDef = Set<VirtualReg>.from(block.liveOut);
        for (final inst in block.instructions) {
          liveOutMinusDef.removeAll(inst.defs);
        }

        block.liveIn.addAll(liveOutMinusDef);

        if (!_setEquals(oldIn, block.liveIn) ||
            !_setEquals(oldOut, block.liveOut)) {
          changed = true;
        }
      }
    }
  }

  bool _setEquals<T>(Set<T> a, Set<T> b) {
    return a.length == b.length && a.containsAll(b);
  }

  @override
  String toString() => 'CFG(${rpo.length} blocks in RPO)';
}
