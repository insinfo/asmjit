/// AsmJit Function Frame
///
/// Provides high-level function frame management with automatic
/// prologue/epilogue generation based on calling convention.

import '../core/arch.dart';
import '../core/environment.dart';
import '../core/type.dart';
import 'x86.dart';

/// Maximum number of function arguments.
const int kMaxFuncArgs = 32;

/// Marker for no variable arguments.
const int kNoVarArgs = 0xFF;

/// Function signature.
///
/// Describes the return type and argument types of a function.
/// Used to calculate FuncDetail which maps types to registers/stack.
class FuncSignature {
  /// Calling convention ID.
  final CallConvId callConvId;

  /// Return type.
  TypeId retType;

  /// Argument types.
  final List<TypeId> argTypes;

  /// Index of first variadic argument (kNoVarArgs if none).
  int vaIndex;

  /// Creates a function signature.
  FuncSignature({
    this.callConvId = CallConvId.cdecl,
    this.retType = TypeId.void_,
    List<TypeId>? args,
    this.vaIndex = kNoVarArgs,
  }) : argTypes = args ?? [];

  /// Creates a signature for: int64 func().
  factory FuncSignature.noArgs({
    CallConvId callConv = CallConvId.cdecl,
    TypeId ret = TypeId.int64,
  }) {
    return FuncSignature(callConvId: callConv, retType: ret);
  }

  /// Creates a signature for: int64 func(int64).
  factory FuncSignature.i64i64({CallConvId callConv = CallConvId.cdecl}) {
    return FuncSignature(
      callConvId: callConv,
      retType: TypeId.int64,
      args: [TypeId.int64],
    );
  }

  /// Creates a signature for: int64 func(int64, int64).
  factory FuncSignature.i64i64i64({CallConvId callConv = CallConvId.cdecl}) {
    return FuncSignature(
      callConvId: callConv,
      retType: TypeId.int64,
      args: [TypeId.int64, TypeId.int64],
    );
  }

  /// Creates a signature for: int64 func(int64, int64, int64).
  factory FuncSignature.i64i64i64i64({CallConvId callConv = CallConvId.cdecl}) {
    return FuncSignature(
      callConvId: callConv,
      retType: TypeId.int64,
      args: [TypeId.int64, TypeId.int64, TypeId.int64],
    );
  }

  /// Creates a signature for: double func(double, double).
  factory FuncSignature.f64f64f64({CallConvId callConv = CallConvId.cdecl}) {
    return FuncSignature(
      callConvId: callConv,
      retType: TypeId.float64,
      args: [TypeId.float64, TypeId.float64],
    );
  }

  /// Number of arguments.
  int get argCount => argTypes.length;

  /// Whether function has a return value.
  bool get hasRet => retType != TypeId.void_;

  /// Whether function has variable arguments.
  bool get hasVarArgs => vaIndex != kNoVarArgs;

  /// Add an argument type.
  void addArg(TypeId type) {
    if (argTypes.length >= kMaxFuncArgs) {
      throw StateError('Too many function arguments');
    }
    argTypes.add(type);
  }

  /// Set return type.
  void setRet(TypeId type) {
    retType = type;
  }

  /// Get argument type at index.
  TypeId arg(int index) {
    if (index < 0 || index >= argTypes.length) {
      throw RangeError.index(index, argTypes, 'index');
    }
    return argTypes[index];
  }

  @override
  String toString() {
    final argsStr = argTypes.map((t) => t.name).join(', ');
    return 'FuncSignature(${retType.name} func($argsStr))';
  }
}

/// Calling convention IDs (matches AsmJit).
enum CallConvId {
  /// Standard C calling convention.
  cdecl,

  /// __stdcall (Windows 32-bit).
  stdCall,

  /// __fastcall (Windows 32-bit).
  fastCall,

  /// __vectorcall (Windows).
  vectorCall,

  /// __thiscall (Windows 32-bit).
  thisCall,

  /// X64 System V ABI.
  x64SystemV,

  /// X64 Windows ABI.
  x64Windows,
}

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
  int getStackArgOffset(int argIndex, {bool includeShadowSpace = false}) {
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
    final shadow = includeShadowSpace && isWin64 ? shadowSpaceSize : 0;
    return 16 + shadow + (stackIndex * stackSlotSize);
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
    // frameSize includes saved registers + locals + alignment padding.
    // We already pushed saved registers. So we only need to alloc the rest.
    final savedSize = frame.savedRegisters.length * 8;
    final remaining = frame.frameSize - savedSize;
    if (remaining > 0) {
      _asm.subRI(rsp, remaining);
    }

    // Win64: Allocate shadow space for calls
    // (Usually done by adding extra to frameSize)
  }

  /// Emits the function epilogue.
  void emitEpilogue() {
    // Deallocate stack space
    final savedSize = frame.savedRegisters.length * 8;
    final remaining = frame.frameSize - savedSize;
    if (remaining > 0) {
      _asm.addRI(rsp, remaining);
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

/// Describes how a function value (argument or return) is passed.
class FuncValue {
  /// Type of the value.
  final TypeId typeId;

  /// Whether passed in a register.
  final bool isReg;

  /// Whether passed on stack.
  final bool isStack;

  /// Whether passed indirectly (by pointer).
  final bool isIndirect;

  /// Register ID (if isReg).
  final int regId;

  /// Register type (GP, XMM, etc).
  final FuncRegType regType;

  /// Stack offset (if isStack).
  final int stackOffset;

  // ignore: unused_element - reserved for Win64 vectorcall indirect args
  const FuncValue._({
    this.typeId = TypeId.void_,
    this.isReg = false,
    this.isStack = false,
    // ignore: unused_element
    this.isIndirect = false,
    this.regId = 0,
    this.regType = FuncRegType.gp,
    this.stackOffset = 0,
  });

  /// Creates a value passed in a GP register.
  factory FuncValue.gpReg(TypeId type, int regId) {
    return FuncValue._(
      typeId: type,
      isReg: true,
      regId: regId,
      regType: FuncRegType.gp,
    );
  }

  /// Creates a value passed in an XMM register.
  factory FuncValue.xmmReg(TypeId type, int regId) {
    return FuncValue._(
      typeId: type,
      isReg: true,
      regId: regId,
      regType: FuncRegType.xmm,
    );
  }

  /// Creates a value passed in a YMM register.
  factory FuncValue.ymmReg(TypeId type, int regId) {
    return FuncValue._(
      typeId: type,
      isReg: true,
      regId: regId,
      regType: FuncRegType.ymm,
    );
  }

  /// Creates a value passed in a ZMM register.
  factory FuncValue.zmmReg(TypeId type, int regId) {
    return FuncValue._(
      typeId: type,
      isReg: true,
      regId: regId,
      regType: FuncRegType.zmm,
    );
  }

  /// Creates a value passed on stack.
  factory FuncValue.stack(TypeId type, int offset) {
    return FuncValue._(
      typeId: type,
      isStack: true,
      stackOffset: offset,
    );
  }

  /// Returns the X86 GP register if this is a GP reg value.
  X86Gp? get gpReg {
    if (!isReg || regType != FuncRegType.gp) return null;
    return X86Gp.r64(regId);
  }

  @override
  String toString() {
    if (isReg) {
      return 'FuncValue(${typeId.name} in ${regType.name}[$regId])';
    } else if (isStack) {
      return 'FuncValue(${typeId.name} at stack+$stackOffset)';
    }
    return 'FuncValue(${typeId.name})';
  }
}

/// Register type for FuncValue.
enum FuncRegType {
  gp,
  xmm,
  ymm,
  zmm,
}

/// Detailed function info with argument/return value allocation.
///
/// Takes a FuncSignature and resolves how each argument and
/// return value is passed according to the calling convention.
class FuncDetail {
  /// The original signature.
  final FuncSignature signature;

  /// Calling convention.
  final CallingConvention callingConvention;

  /// Allocated return value.
  late final FuncValue retValue;

  /// Allocated argument values.
  late final List<FuncValue> argValues;

  /// Total stack space needed for arguments.
  int stackArgsSize = 0;

  /// Creates function detail from signature.
  FuncDetail(this.signature, {CallingConvention? cc})
      : callingConvention = cc ?? _detectCallingConvention() {
    _allocate();
  }

  /// Detect host calling convention.
  static CallingConvention _detectCallingConvention() {
    final env = Environment.host();
    return env.callingConvention;
  }

  /// Allocate arguments and return value.
  void _allocate() {
    // Allocate return value
    if (signature.hasRet) {
      retValue = _allocateReturnValue(signature.retType);
    } else {
      retValue = const FuncValue._();
    }

    // Allocate arguments
    argValues = [];
    int gpIndex = 0;
    int xmmIndex = 0;
    int stackOffset = callingConvention == CallingConvention.win64 ? 32 : 0;

    final gpOrder = _getGpOrder();
    final xmmOrder = _getXmmOrder();

    for (int i = 0; i < signature.argCount; i++) {
      final type = signature.arg(i);
      final size = type.sizeInBytes > 0 ? type.sizeInBytes : 8;

      if (type.isVec || type.isFloat) {
        // Float and vector types go in SIMD registers.
        if (xmmIndex < xmmOrder.length) {
          if (type.isVec256) {
            argValues.add(FuncValue.ymmReg(type, xmmOrder[xmmIndex++]));
          } else if (type.isVec512) {
            argValues.add(FuncValue.zmmReg(type, xmmOrder[xmmIndex++]));
          } else {
            argValues.add(FuncValue.xmmReg(type, xmmOrder[xmmIndex++]));
          }
          if (callingConvention == CallingConvention.win64) {
            gpIndex++; // Win64: XMM and GP share slots
          }
        } else {
          if (type.isVec && (stackOffset & 15) != 0) {
            stackOffset = (stackOffset + 15) & ~15;
          }
          argValues.add(FuncValue.stack(type, stackOffset));
          final slotSize = size < 8 ? 8 : size;
          stackOffset += slotSize;
        }
      } else {
        // Integer types go in GP registers
        if (gpIndex < gpOrder.length) {
          argValues.add(FuncValue.gpReg(type, gpOrder[gpIndex++]));
          if (callingConvention == CallingConvention.win64) {
            xmmIndex++; // Win64: GP and XMM share slots
          }
        } else {
          argValues.add(FuncValue.stack(type, stackOffset));
          stackOffset += 8;
        }
      }
    }

    stackArgsSize = stackOffset;
  }

  /// Allocate return value register.
  FuncValue _allocateReturnValue(TypeId type) {
    if (type.isVec) {
      if (type.isVec256) {
        return FuncValue.ymmReg(type, 0);
      }
      if (type.isVec512) {
        return FuncValue.zmmReg(type, 0);
      }
      return FuncValue.xmmReg(type, 0);
    }
    if (type.isFloat) {
      return FuncValue.xmmReg(type, 0); // XMM0
    } else {
      return FuncValue.gpReg(type, 0); // RAX
    }
  }

  /// Get GP register order for arguments.
  List<int> _getGpOrder() {
    if (callingConvention == CallingConvention.win64) {
      return [1, 2, 8, 9]; // RCX, RDX, R8, R9
    } else {
      return [7, 6, 2, 1, 8, 9]; // RDI, RSI, RDX, RCX, R8, R9
    }
  }

  /// Get XMM register order for arguments.
  List<int> _getXmmOrder() {
    if (callingConvention == CallingConvention.win64) {
      return [0, 1, 2, 3]; // XMM0-3
    } else {
      return [0, 1, 2, 3, 4, 5, 6, 7]; // XMM0-7
    }
  }

  /// Get the FuncValue for argument at index.
  FuncValue getArg(int index) {
    if (index < 0 || index >= argValues.length) {
      throw RangeError.index(index, argValues, 'index');
    }
    return argValues[index];
  }

  /// Number of arguments passed in GP registers.
  int get gpArgCount =>
      argValues.where((v) => v.isReg && v.regType == FuncRegType.gp).length;

  /// Number of arguments passed in XMM registers.
  int get xmmArgCount =>
      argValues.where((v) => v.isReg && v.regType == FuncRegType.xmm).length;

  /// Number of arguments passed on stack.
  int get stackArgCount => argValues.where((v) => v.isStack).length;

  @override
  String toString() {
    final args = argValues.map((v) => v.toString()).join(', ');
    return 'FuncDetail(ret: $retValue, args: [$args])';
  }
}
