import '../core/builder.dart' as ir;
import '../core/code_holder.dart' show Section;
import '../core/labels.dart';
import 'a64_assembler.dart';
import 'a64.dart';

/// Serializer that converts Builder IR to A64Assembler calls (subset).
class A64Serializer implements ir.SerializerContext {
  final A64Assembler asm;

  A64Serializer(this.asm);

  @override
  void onLabel(Label label) {
    asm.code.ensureLabelCount(label.id + 1);
    asm.bind(label);
  }

  @override
  void onAlign(ir.AlignMode mode, int alignment) => asm.align(mode, alignment);

  @override
  void onEmbedData(List<int> data, int typeSize) {
    asm.emitBytes(data);
  }

  @override
  void onSection(Section section) => asm.section(section);

  @override
  void onEmbedLabel(Label label, int dataSize) =>
      asm.embedLabel(label, dataSize);

  @override
  void onEmbedLabelDelta(Label label, Label base, int dataSize) =>
      asm.embedLabelDelta(label, base, dataSize);

  @override
  void onComment(String text) {
    // Ignored in binary output
  }

  @override
  void onSentinel(ir.SentinelType type) {
    // No-op
  }

  @override
  void onInst(int instId, List<ir.Operand> operands, int options) {
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
      } else if (op is A64ShiftOp) {
        ops.add(op);
      } else if (op is A64CondOp) {
        ops.add(op.cond);
      }
    }
    asm.emit(instId, ops);
  }

  @override
  void onInstExtra(int instId, List<ir.Operand> operands, int options,
          ir.BaseReg? extraReg) =>
      onInst(instId, operands, options);
}
