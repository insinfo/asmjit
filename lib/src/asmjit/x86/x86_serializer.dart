//C:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_serializer.dart
import '../core/builder.dart' as ir;
import '../core/labels.dart';
import 'x86_assembler.dart';
import 'x86_dispatcher.dart';
import 'x86_inst_db.g.dart'; // Generated dispatcher

/// Serializer that converts Builder IR to X86Assembler calls.
class X86Serializer implements ir.SerializerContext {
  /// The target assembler.
  final X86Assembler asm;

  X86Serializer(this.asm);

  @override
  void onLabel(Label label) {
    asm.code.ensureLabelCount(label.id + 1);
    asm.bind(label);
  }

  @override
  void onAlign(ir.AlignMode mode, int alignment) {
    // Honor both code and data alignment so embedded constants are safely accessed.
    if (mode == ir.AlignMode.code || mode == ir.AlignMode.data) {
      asm.align(alignment);
    }
  }

  @override
  void onEmbedData(List<int> data, int typeSize) {
    asm.emitInline(data);
  }

  @override
  void onComment(String text) {
    // Comments are ignored by assembler
  }

  @override
  void onSentinel(ir.SentinelType type) {
    // Sentinels are ignored
  }

  @override
  void onInst(int instId, List<ir.Operand> operands, int options) {
    // Helper to extract X86 operands
    final ops = <Object>[];
    for (final op in operands) {
      if (op is ir.BaseReg) {
        ops.add(op);
      } else if (op is ir.Imm) {
        ops.add(op.value);
      } else if (op is ir.BaseMem) {
        ops.add(op);
      } else if (op is ir.LabelOp) {
        ops.add(op.label);
      }
    }
    emitInst(instId, ops, options);
  }

  /// Emits the instruction with pre-processed operands.
  void emitInst(int instId, List<Object> ops, int options) {
    // Every x86 instruction encodes to at least one byte: if the dispatcher
    // emitted nothing, the operand combination is unsupported and silently
    // dropping it would produce wrong machine code.
    final start = asm.offset;
    x86Dispatch(asm, instId, ops);
    if (asm.offset == start) {
      final name = instId >= 0 && instId < kX86InstDb.length
          ? kX86InstDb[instId].name
          : '#$instId';
      throw UnsupportedError(
          'x86 dispatcher: unsupported operands for "$name": $ops');
    }
  }
}
