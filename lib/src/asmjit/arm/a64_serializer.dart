import '../core/builder.dart' as ir;
import '../core/labels.dart';
import 'a64_assembler.dart';
import 'a64_dispatcher.g.dart';

/// Serializer that converts Builder IR to A64Assembler calls (subset).
class A64Serializer implements ir.SerializerContext {
  final A64Assembler asm;

  A64Serializer(this.asm);

  @override
  void onLabel(Label label) => asm.bind(label);

  @override
  void onAlign(ir.AlignMode mode, int alignment) {
    if (mode == ir.AlignMode.code) {
      // A64Assembler has no direct align; emit NOPs as padding if needed.
      final misalign = asm.code.text.buffer.length % alignment;
      if (misalign != 0) {
        final pad = alignment - misalign;
        for (var i = 0; i < pad; i++) {
          asm.nop();
        }
      }
    }
  }

  @override
  void onEmbedData(List<int> data, int typeSize) {
    asm.emitBytes(data);
  }

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
      if (op is ir.RegOperand) {
        ops.add(op.reg);
      } else if (op is ir.ImmOperand) {
        ops.add(op.value);
      } else if (op is ir.MemOperand) {
        ops.add(op.mem);
      } else if (op is ir.LabelOperand) {
        ops.add(op.label);
      }
    }
    a64Dispatch(asm, instId, ops);
  }
}
