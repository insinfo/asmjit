/// AsmJit Function Frame
///
/// Provides high-level function frame management with automatic
/// prologue/epilogue generation based on calling convention.

import '../core/arch.dart';
import '../core/environment.dart';
import 'x86.dart';

/// Function frame attributes.
class FuncFrameAttr {
  /// Whether to preserve the frame pointer (RBP).
  final bool preserveFramePointer;

  /// Additional stack space to allocate for local variables.
  final int localStackSize;

  /// Whether to align the stack to 16 bytes (required by x64 ABI).
  final bool alignStack;

  /// List of additional registers to preserve (callee-saved).
  final List<X86Gp> preservedRegs;

  /// Whether this function uses the red zone (SysV only).
  final bool useRedZone;

  const FuncFrameAttr({
    this.preserveFramePointer = true,
    this.localStackSize = 0,
    this.alignStack = true,
    this.preservedRegs = const [],
    this.useRedZone = false,
  });

  /// Creates attributes for a leaf function (no calls).
  factory FuncFrameAttr.leaf({int localStackSize = 0}) {
    return FuncFrameAttr(
      preserveFramePointer: false,
      localStackSize: localStackSize,
      alignStack: false,
      useRedZone: true,
    );
  }

  /// Creates attributes for a function that calls other functions.
  factory FuncFrameAttr.nonLeaf({
    int localStackSize = 0,
    List<X86Gp>? preservedRegs,
  }) {
    return FuncFrameAttr(
      preserveFramePointer: true,
      localStackSize: localStackSize,
      alignStack: true,
      preservedRegs: preservedRegs ?? const [],
    );
  }
}

/// Manages function prologue and epilogue generation.
///
/// Based on the calling convention, automatically handles:
/// - Stack alignment
/// - Frame pointer setup
/// - Callee-saved register preservation
/// - Local variable allocation
class FuncFrame {
  /// The calling convention.
  final CallingConvention callingConvention;

  /// The frame attributes.
  final FuncFrameAttr attr;

  /// Callee-saved registers that need to be preserved.
  final List<X86Gp> _savedRegs = [];

  /// Calculated stack frame size.
  int _frameSize = 0;

  /// Creates a function frame for the given calling convention.
  FuncFrame({
    CallingConvention? callingConvention,
    FuncFrameAttr? attr,
  })  : callingConvention = callingConvention ?? _defaultCallingConvention(),
        attr = attr ?? const FuncFrameAttr() {
    _calculateFrame();
  }

  /// Creates a function frame for the host environment.
  factory FuncFrame.host({FuncFrameAttr? attr}) {
    return FuncFrame(
      callingConvention: _defaultCallingConvention(),
      attr: attr,
    );
  }

  /// Gets the default calling convention for the host.
  static CallingConvention _defaultCallingConvention() {
    final env = Environment.host();
    return env.callingConvention;
  }

  /// Calculate the frame layout.
  void _calculateFrame() {
    _savedRegs.clear();

    // Collect registers that need to be saved
    if (attr.preserveFramePointer) {
      // RBP is handled separately in prologue/epilogue
    }

    // Add explicitly preserved registers
    _savedRegs.addAll(attr.preservedRegs);

    // Calculate total frame size
    int size = 0;

    // Space for saved registers (8 bytes each in x64)
    size += _savedRegs.length * 8;

    // Space for local variables
    size += attr.localStackSize;

    // Align to 16 bytes if required
    if (attr.alignStack && size > 0) {
      // In x64, after PUSH RBP, the stack is at 16n+8
      // We need to make it 16n after allocating space
      // The total with saved regs should be 16-byte aligned
      final totalPushes =
          (attr.preserveFramePointer ? 1 : 0) + _savedRegs.length;
      final pushBytes = totalPushes * 8;
      final returnAddressBytes = 8;

      // Stack after pushes: (16n) - returnAddress - pushes
      // We need to add padding to make it 16-byte aligned
      final currentMisalignment = (returnAddressBytes + pushBytes) % 16;
      if (currentMisalignment != 0) {
        size += 16 - currentMisalignment;
      }
    }

    _frameSize = size;
  }

  /// The total frame size (excluding pushed registers).
  int get frameSize => _frameSize;

  /// List of registers that will be saved.
  List<X86Gp> get savedRegisters => List.unmodifiable(_savedRegs);

  /// Whether this is a Win64 calling convention.
  bool get isWin64 => callingConvention == CallingConvention.win64;

  /// Whether this is a SysV calling convention.
  bool get isSysV => callingConvention == CallingConvention.sysV64;

  /// Gets the argument register for the given index.
  X86Gp getArgReg(int index) {
    if (isWin64) {
      const regs = [rcx, rdx, r8, r9];
      if (index >= regs.length) {
        throw ArgumentError('Win64 only has ${regs.length} register arguments');
      }
      return regs[index];
    } else {
      // System V AMD64
      const regs = [rdi, rsi, rdx, rcx, r8, r9];
      if (index >= regs.length) {
        throw ArgumentError('SysV only has ${regs.length} register arguments');
      }
      return regs[index];
    }
  }

  /// Gets the standard callee-saved registers.
  List<X86Gp> get calleeSavedRegs {
    if (isWin64) {
      return win64CalleeSaved;
    } else {
      return sysVCalleeSaved;
    }
  }

  /// Win64 shadow space size (32 bytes).
  int get shadowSpaceSize => isWin64 ? 32 : 0;

  /// Stack slot size for an argument.
  int get stackSlotSize => 8;

  /// Get the offset of a stack-based argument (beyond register args).
  ///
  /// For Win64, args 0-3 are in registers, arg 4+ on stack.
  /// For SysV, args 0-5 are in registers, arg 6+ on stack.
  /// This returns the offset from RBP (after standard prologue).
  int getStackArgOffset(int argIndex) {
    final registerArgs = isWin64 ? 4 : 6;
    if (argIndex < registerArgs) {
      throw ArgumentError(
          'Argument $argIndex is passed in a register, not on stack');
    }

    // Standard layout after prologue:
    // [RBP+16]: first stack argument (arg 4 for Win64, arg 6 for SysV)
    // [RBP+8]:  return address
    // [RBP+0]:  saved RBP (frame pointer)
    final stackIndex = argIndex - registerArgs;
    return 16 + (stackIndex * stackSlotSize);
  }

  /// Get the offset for accessing a local variable from RBP.
  ///
  /// Local variable 0 is at [RBP - offset], where offset depends on
  /// the number of saved registers and alignment.
  int getLocalOffset(int localIndex, {int size = 8}) {
    // Start after saved registers
    var offset = _savedRegs.length * 8;
    offset += localIndex * size;
    return -(offset + size);
  }
}

/// Helper class to emit function prologues and epilogues.
///
/// Usage:
/// ```dart
/// final frame = FuncFrame.host(attr: FuncFrameAttr.nonLeaf(localStackSize: 32));
/// final emitter = FuncFrameEmitter(frame, asm);
///
/// emitter.emitPrologue();
/// // ... function body ...
/// emitter.emitEpilogue();
/// ```
class FuncFrameEmitter {
  final FuncFrame frame;
  final dynamic _asm; // X86Assembler, but keep weak dependency

  FuncFrameEmitter(this.frame, this._asm);

  /// Emits the function prologue.
  void emitPrologue() {
    // Push frame pointer
    if (frame.attr.preserveFramePointer) {
      _asm.push(rbp);
      _asm.movRR(rbp, rsp);
    }

    // Push callee-saved registers
    for (final reg in frame.savedRegisters) {
      _asm.push(reg);
    }

    // Allocate stack space
    if (frame.frameSize > 0) {
      _asm.subRI(rsp, frame.frameSize);
    }

    // Win64: Allocate shadow space for calls
    // (Usually done by adding extra to frameSize)
  }

  /// Emits the function epilogue.
  void emitEpilogue() {
    // Deallocate stack space
    if (frame.frameSize > 0) {
      _asm.addRI(rsp, frame.frameSize);
    }

    // Pop callee-saved registers (reverse order)
    for (int i = frame.savedRegisters.length - 1; i >= 0; i--) {
      _asm.pop(frame.savedRegisters[i]);
    }

    // Restore frame pointer and return
    if (frame.attr.preserveFramePointer) {
      _asm.pop(rbp);
    }

    _asm.ret();
  }

  /// Emits a LEAVE instruction followed by RET.
  ///
  /// Equivalent to: mov rsp, rbp; pop rbp; ret
  /// Only valid if preserveFramePointer is true.
  void emitLeaveRet() {
    if (!frame.attr.preserveFramePointer) {
      throw StateError('Cannot use LEAVE without frame pointer');
    }
    _asm.leave();
    _asm.ret();
  }
}
