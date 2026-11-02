/// Architecture-specific part of the register allocator.
///
/// asmjit's `BaseRAPass` is arch-neutral and delegates instruction analysis,
/// move/load/save emission and prolog/epilog insertion to virtual methods
/// implemented by `x86::X86RAPass` and `a64::ARMRAPass`. [RAArch] plays that
/// role for the Dart [RAPass].

import 'compiler.dart';
import 'labels.dart';
import 'radefs.dart';

/// Information [RAArch.insertPrologEpilog] needs once allocation finished.
class RAFrameContext {
  /// The compiler whose node list is being rewritten.
  final BaseCompiler compiler;

  /// The function being finalized.
  final FuncNode func;

  /// Bytes used by spill slots (allocated through [RAArch.spillSlot]).
  final int spillSize;

  /// Registers allocatable by the RA.
  final RARegMask available;

  /// Callee-saved registers of the function's calling convention.
  final RARegMask preserved;

  /// Registers written anywhere in the function.
  final RARegMask clobbered;

  RAFrameContext({
    required this.compiler,
    required this.func,
    required this.spillSize,
    required this.available,
    required this.preserved,
    required this.clobbered,
  });

  void insertAfter(BaseNode after, BaseNode node) =>
      compiler.nodes.insertAfter(node, after);

  void insertBefore(BaseNode before, BaseNode node) =>
      compiler.nodes.insertBefore(node, before);

  /// The nodes of [func], from the function node to its end sentinel.
  Iterable<BaseNode> get funcNodes =>
      NodeRange(func, func.end ?? compiler.nodes.last!).nodes;

  /// The return nodes of [func] (lowered by the epilog).
  List<InstNode> get retNodes => [
        for (final node in funcNodes)
          if (node is InstNode && node.nodeType == NodeType.funcRet) node
      ];
}

/// Architecture hooks used by [RAPass].
abstract class RAArch {
  /// Fills allocatable ([avail]) and callee-saved ([preserved]) registers.
  void initRegMasks(BaseCompiler cc, RARegMask avail, RARegMask preserved);

  /// Whether liveness is computed from [operandFlags] (precise) instead of
  /// the legacy x86 heuristic "operand 0 is read/write unless [isMove]".
  bool get preciseLiveness => false;

  /// Whether operand 0 of [node] is written without being read.
  bool isMove(InstNode node);

  /// [RATiedFlags] (`kUse`/`kRead`/`kOut`/`kWrite`) for each operand of
  /// [node]. Memory operands are ignored: their base/index are always read.
  List<int> operandFlags(InstNode node);

  /// Physical register operand [opIndex] of [node] must use, or
  /// [RAAssignment.kPhysNone].
  int fixedUseId(InstNode node, int opIndex) => RAAssignment.kPhysNone;

  /// Physical registers implicitly read/written by [node].
  void implicitRegs(InstNode node, RARegMask used, RARegMask clobbered) {}

  /// `dst = src` (both physical, same group).
  InstNode move(BaseReg dst, BaseReg src);

  /// Loads [dst] from a spill slot.
  InstNode load(BaseReg dst, BaseMem src);

  /// Stores [src] into a spill slot.
  InstNode save(BaseMem dst, BaseReg src);

  /// Exchanges two physical registers of the same group.
  List<InstNode> swap(BaseReg a, BaseReg b);

  /// Unconditional jump to [target].
  InstNode jump(Label target);

  /// Bytes reserved when spilling the virtual register [reg].
  int spillSize(BaseReg reg) => reg.size;

  /// Memory operand of a spill slot that starts [offset] bytes into the
  /// spill area and is [size] bytes long.
  BaseMem spillSlot(BaseCompiler cc, int offset, int size);

  /// Copy of [mem] with the given base/index/displacement/size (other
  /// attributes such as scale or segment are kept).
  BaseMem rebuildMem(BaseMem mem,
      {required BaseReg? base,
      required BaseReg? index,
      required int displacement,
      required int size});

  /// Inserts prolog/epilog and lowers every `FuncRetNode`.
  void insertPrologEpilog(RAFrameContext ctx);
}
