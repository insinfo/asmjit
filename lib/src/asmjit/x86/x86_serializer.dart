//C:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_serializer.dart
import '../core/builder.dart' as ir;
import '../core/code_holder.dart' show Section;
import '../core/labels.dart';
import 'x86_assembler.dart';

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
  void onAlign(ir.AlignMode mode, int alignment) => asm.align(mode, alignment);

  @override
  void onEmbedData(List<int> data, int typeSize) {
    asm.emitInline(data);
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
    // Comments are ignored by assembler
  }

  @override
  void onSentinel(ir.SentinelType type) {
    // Sentinels are ignored
  }

  @override
  void onInst(int instId, List<ir.Operand> operands, int options) =>
      onInstExtra(instId, operands, options, null);

  /// Emits the instruction with its options (`InstOptions`) and extra
  /// register (REP counter or AVX-512 `{k}`), as upstream
  /// `Builder::serialize_to()` passes `inst_options()` and `extra_reg()`.
  @override
  void onInstExtra(int instId, List<ir.Operand> operands, int options,
      ir.BaseReg? extraReg) {
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
    asm.instOptions |= options;
    if (extraReg != null) asm.extraReg = extraReg;
    asm.emit(instId, ops);
  }
}
