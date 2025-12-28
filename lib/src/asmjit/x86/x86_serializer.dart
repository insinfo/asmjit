import '../core/builder.dart' as ir;
import '../core/labels.dart';
import 'x86_assembler.dart';
import 'x86_dispatcher.g.dart'; // Generated dispatcher

/// Serializer that converts Builder IR to X86Assembler calls.
class X86Serializer implements ir.SerializerContext {
  /// The target assembler.
  final X86Assembler asm;

  X86Serializer(this.asm);

  @override
  void onLabel(Label label) {
    asm.bind(label);
  }

  @override
  void onAlign(ir.AlignMode mode, int alignment) {
    if (mode == ir.AlignMode.code) {
      asm.align(alignment);
    }
    // Data alignment not fully supported in text section mixed with code
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
    // Switch-based dispatcher is the single path now (Map fallback removed).
    x86Dispatch(asm, instId, ops);
  }
}
