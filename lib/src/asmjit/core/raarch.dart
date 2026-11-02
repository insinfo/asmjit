/// Architecture-specific part of the register allocator.
///
/// asmjit's `BaseRAPass` is arch-neutral and delegates instruction analysis,
/// move/load/save emission and prolog/epilog insertion to virtual methods
/// implemented by `x86::X86RAPass` and `a64::ARMRAPass`. [RAArch] plays that
/// role for the Dart [RAPass].

import 'compiler.dart';
import 'labels.dart';
import 'radefs.dart';
import 'type.dart';

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

  /// Alignment of the local stack area ([RAArch.localStackAlignment]).
  final int stackAlignment;

  RAFrameContext({
    required this.compiler,
    required this.func,
    required this.spillSize,
    required this.available,
    required this.preserved,
    required this.clobbered,
    this.stackAlignment = 16,
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

/// One register of an instruction as seen by the register allocator: what
/// `RACFGBuilder::on_instruction()` passes to `RAInstBuilder::add()`, plus
/// where the register is in the instruction (its rewrite slot).
class RAInstOp {
  /// A register operand ([opIndex] is the operand).
  static const int kSlotReg = 0;

  /// The base register of the memory operand [opIndex].
  static const int kSlotMemBase = 1;

  /// The index register of the memory operand [opIndex].
  static const int kSlotMemIndex = 2;

  /// The extra register of the instruction ([InstNode.extraReg]).
  static const int kSlotExtra = 3;

  /// An argument of a function call ([InvokeNode]), tied to its argument
  /// register (`add_call_arg()`); not an operand of the instruction.
  static const int kSlotCallArg = 4;

  /// A return value of a function call, tied to its return register
  /// (`add_call_ret()`).
  static const int kSlotCallRet = 5;

  /// The register (virtual or physical).
  final BaseReg reg;
  final int slot;
  final int opIndex;

  /// [RATiedFlags]. The register is rewritten to the use id of its tied
  /// register when [RATiedFlags.kUse] is set, otherwise to the out id.
  int flags;

  /// Allowed registers and fixed physical ids ([RAAssignment.kPhysNone]).
  int useMask;
  int useId;
  int outMask;
  int outId;

  RAInstOp(this.reg, this.slot, this.opIndex, this.flags,
      {this.useMask = 0xFFFFFFFF,
      this.useId = RAAssignment.kPhysNone,
      this.outMask = 0xFFFFFFFF,
      this.outId = RAAssignment.kPhysNone});

  bool get isRead => (flags & RATiedFlags.kRead) != 0;
  bool get isWrite => (flags & RATiedFlags.kWrite) != 0;
  bool get isUseSide => (flags & RATiedFlags.kUse) != 0;

  /// `RATiedReg::make_read_only()`.
  void makeReadOnly() => flags =
      (flags & ~(RATiedFlags.kOut | RATiedFlags.kWrite)) | RATiedFlags.kUse;

  /// `RATiedReg::make_write_only()`.
  void makeWriteOnly() => flags =
      (flags & ~(RATiedFlags.kUse | RATiedFlags.kRead)) | RATiedFlags.kOut;
}

/// Architecture hooks used by [RAPass].
abstract class RAArch {
  /// Registers of [node] with their read/write flags and constraints
  /// (`RACFGBuilder::on_instruction()`), or null to use [operandFlags],
  /// [fixedUseId] and [implicitRegs] instead.
  List<RAInstOp>? analyzeInst(BaseCompiler cc, InstNode node) => null;

  /// `RACFGBuilder::on_before_invoke()`: inserts the instructions that
  /// move the immediate and stack arguments of [node] (a call in [func]).
  void onBeforeInvoke(BaseCompiler cc, FuncNode func, InvokeNode node) =>
      throw UnsupportedError(
          'function calls are not supported by $runtimeType');

  /// `emit_pre_call()`: instructions right before the call [node] after
  /// its registers were allocated ([insert] adds one before the call).
  void emitPreCall(
      BaseCompiler cc, InvokeNode node, void Function(InstNode) insert) {}

  /// Size of the outgoing call argument area at the bottom of the frame
  /// (the largest argument area of the calls of the function), set by
  /// [RAPass] before allocation.
  int callStackSize = 0;

  /// Alignment of the local stack area (spill slots and stack areas) of the
  /// function being allocated, set by [RAPass] before allocation: more than
  /// 16 when a stack area created by `newStack()` asks for it.
  int localStackAlignment = 16;

  /// The register operand of the declared type of [vr] (whose operand id is
  /// the id of [seen], a register operand that uses it); [seen] by default.
  BaseReg virtRegOperand(VirtReg vr, BaseReg seen) => seen;

  /// Fills allocatable ([avail]) and callee-saved ([preserved]) registers.
  ///
  /// [func] is the function being allocated: its calling convention gives
  /// the registers it must preserve.
  void initRegMasks(BaseCompiler cc, RARegMask avail, RARegMask preserved,
      {FuncNode? func});

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

  /// Loads the function argument passed at [stackOffset] of the caller's
  /// argument area into [dst] ([typeId] gives the width). The prolog keeps
  /// the frame pointer, so the area starts at `fp + 16` (after the saved
  /// frame pointer and the return address / link register).
  InstNode loadStackArg(BaseReg dst, int stackOffset, TypeId typeId);

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
