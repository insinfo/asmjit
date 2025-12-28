import '../core/func.dart';
import '../x86/x86_assembler.dart';
import '../x86/x86.dart';
import '../core/operand.dart';

/// Emits function prologue and epilogue based on [FuncFrame].
class FuncFrameEmitter {
  final FuncFrame frame;
  final X86Assembler asm;

  FuncFrameEmitter(this.frame, this.asm);

  /// Emits the function prologue.
  void emitPrologue() {
    // 1. Push RBP and setup stack frame
    if (frame.hasAttribute(FuncAttributes.kHasPreservedFP)) {
      asm.push(X86Gp.rbp);
      asm.movRR(X86Gp.rbp, X86Gp.rsp);
    }

    // 2. Adjust stack pointer
    final stackAdjustment = frame.stackAdjustment;
    if (stackAdjustment > 0) {
      asm.subRI(X86Gp.rsp, stackAdjustment);
    }

    // 3. Save preserved registers
    _emitSaveRestoreRegs(true);
  }

  /// Emits the function epilogue.
  void emitEpilogue() {
    // 1. Restore preserved registers
    _emitSaveRestoreRegs(false);

    // 2. Adjust stack pointer back
    final stackAdjustment = frame.stackAdjustment;
    if (stackAdjustment > 0) {
      asm.addRI(X86Gp.rsp, stackAdjustment);
    }

    // 3. Restore RBP
    if (frame.hasAttribute(FuncAttributes.kHasPreservedFP)) {
      asm.pop(X86Gp.rbp);
    }

    // 4. Return
    asm.ret();
  }

  void _emitSaveRestoreRegs(bool save) {
    for (var group in RegGroup.values) {
      final regs = frame.savedRegs(group);
      if (regs == 0) continue;

      if (group == RegGroup.gp) {
        // X86 push/pop for GP
        for (int i = 0; i < 16; i++) {
          if ((regs & (1 << i)) != 0) {
            final reg = X86Gp.r64(i);
            if (save) {
              asm.push(reg);
            } else {
              asm.pop(reg);
            }
          }
        }
      } else {
        // SIMD registers (TODO: use movaps/movups based on alignment)
      }
    }
  }
}
