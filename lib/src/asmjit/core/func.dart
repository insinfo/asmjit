// This file is part of AsmJit project <https://asmjit.com>
//

import 'dart:typed_data';
import 'arch.dart';
import 'environment.dart';
import 'error.dart';
import 'globals.dart';
import 'operand.dart';
import 'reg_type.dart';
import 'support.dart' as support;
import 'type.dart';
import 'reg_utils.dart'; // For RegMask etc

import '../x86/x86_func.dart';
import '../arm/a64_func.dart';

/// Calling convention id.
enum CallConvId {
  // Universal Calling Conventions
  cdecl(0),
  stdCall(1),
  fastCall(2),
  vectorCall(3),
  thisCall(4),
  regParm1(5),
  regParm2(6),
  regParm3(7),

  lightCall2(16),
  lightCall3(17),
  lightCall4(18),

  // ABI-Specific Calling Conventions
  softFloat(30),
  hardFloat(31),

  x64SystemV(32),
  x64Windows(33);

  final int value;
  const CallConvId(this.value);

  static const kMaxValue = x64Windows;
}

/// Strategy used by calling conventions to assign registers to function arguments.
enum CallConvStrategy {
  defaultStrategy(0),
  x64Windows(1),
  x64VectorCall(2),
  aarch64Apple(3);

  final int value;
  const CallConvStrategy(this.value);

  static const kMaxValue = x64VectorCall;
}

/// Calling convention flags.
class CallConvFlags {
  static const int kNone = 0;
  static const int kCalleePopsStack = 0x0001;
  static const int kIndirectVecArgs = 0x0002;
  static const int kPassFloatsByVec = 0x0004;
  static const int kPassVecByStackIfVA = 0x0008;
  static const int kPassMmxByGp = 0x0010;
  static const int kPassMmxByXmm = 0x0020;
  static const int kVarArgCompatible = 0x0080;
}

/// Function calling convention.
class CallConv {
  static const int kMaxRegArgsPerGroup = 16;

  Arch _arch = Arch.unknown;
  CallConvId _id = CallConvId.cdecl;
  CallConvStrategy _strategy = CallConvStrategy.defaultStrategy;

  int _redZoneSize = 0;
  int _spillZoneSize = 0;
  int _naturalStackAlignment = 0;

  int _flags = CallConvFlags.kNone;

  final List<int> _saveRestoreRegSize = List.filled(Globals.kNumVirtGroups, 0);
  final List<int> _saveRestoreAlignment =
      List.filled(Globals.kNumVirtGroups, 0);

  final List<int> _passedRegs = List.filled(Globals.kNumVirtGroups, 0);
  final List<int> _preservedRegs = List.filled(Globals.kNumVirtGroups, 0);

  final List<Uint8List> _passedOrder = List.generate(
      Globals.kNumVirtGroups,
      (_) => Uint8List(kMaxRegArgsPerGroup)
        ..fillRange(0, kMaxRegArgsPerGroup, 0xFF));

  CallConv();

  AsmJitError init(CallConvId id, Environment env) {
    reset();
    // Implementation is architecture specific. We'll need to call into X86FuncInternal.initCallConv etc.
    // This is typically handled by a registry or direct import.
    return _initCallConv(this, id, env);
  }

  void reset() {
    _arch = Arch.unknown;
    _id = CallConvId.cdecl;
    _strategy = CallConvStrategy.defaultStrategy;
    _redZoneSize = 0;
    _spillZoneSize = 0;
    _naturalStackAlignment = 0;
    _flags = CallConvFlags.kNone;

    _saveRestoreRegSize.fillRange(0, _saveRestoreRegSize.length, 0);
    _saveRestoreAlignment.fillRange(0, _saveRestoreAlignment.length, 0);
    _passedRegs.fillRange(0, _passedRegs.length, 0);
    _preservedRegs.fillRange(0, _preservedRegs.length, 0);

    for (var order in _passedOrder) {
      order.fillRange(0, kMaxRegArgsPerGroup, 0xFF);
    }
  }

  Arch get arch => _arch;
  void setArch(Arch arch) => _arch = arch;

  CallConvId get id => _id;
  void setId(CallConvId id) => _id = id;

  CallConvStrategy get strategy => _strategy;
  void setStrategy(CallConvStrategy strategy) => _strategy = strategy;

  bool hasFlag(int flag) => (_flags & flag) != 0;
  int get flags => _flags;
  void setFlags(int flags) => _flags = flags;
  void addFlags(int flags) => _flags |= flags;

  bool get hasRedZone => _redZoneSize != 0;
  bool get hasSpillZone => _spillZoneSize != 0;

  int get redZoneSize => _redZoneSize;
  void setRedZoneSize(int size) => _redZoneSize = size & 0xFF;

  int get spillZoneSize => _spillZoneSize;
  void setSpillZoneSize(int size) => _spillZoneSize = size & 0xFF;

  int get naturalStackAlignment => _naturalStackAlignment;
  void setNaturalStackAlignment(int alignment) =>
      _naturalStackAlignment = alignment & 0xFF;

  int saveRestoreRegSize(RegGroup group) => _saveRestoreRegSize[group.index];
  void setSaveRestoreRegSize(RegGroup group, int size) =>
      _saveRestoreRegSize[group.index] = size & 0xFF;

  int saveRestoreAlignment(RegGroup group) =>
      _saveRestoreAlignment[group.index];
  void setSaveRestoreAlignment(RegGroup group, int alignment) =>
      _saveRestoreAlignment[group.index] = alignment & 0xFF;

  Uint8List passedOrder(RegGroup group) => _passedOrder[group.index];

  int passedRegs(RegGroup group) => _passedRegs[group.index];

  void setPassedToNone(RegGroup group) {
    _passedOrder[group.index].fillRange(0, kMaxRegArgsPerGroup, 0xFF);
    _passedRegs[group.index] = 0;
  }

  void setPassedOrder(RegGroup group,
      [int a0 = 0xFF,
      int a1 = 0xFF,
      int a2 = 0xFF,
      int a3 = 0xFF,
      int a4 = 0xFF,
      int a5 = 0xFF,
      int a6 = 0xFF,
      int a7 = 0xFF]) {
    final order = _passedOrder[group.index];
    order[0] = a0 & 0xFF;
    order[1] = a1 & 0xFF;
    order[2] = a2 & 0xFF;
    order[3] = a3 & 0xFF;
    order[4] = a4 & 0xFF;
    order[5] = a5 & 0xFF;
    order[6] = a6 & 0xFF;
    order[7] = a7 & 0xFF;

    int mask = 0;
    if (a0 != 0xFF) mask |= (1 << a0);
    if (a1 != 0xFF) mask |= (1 << a1);
    if (a2 != 0xFF) mask |= (1 << a2);
    if (a3 != 0xFF) mask |= (1 << a3);
    if (a4 != 0xFF) mask |= (1 << a4);
    if (a5 != 0xFF) mask |= (1 << a5);
    if (a6 != 0xFF) mask |= (1 << a6);
    if (a7 != 0xFF) mask |= (1 << a7);
    _passedRegs[group.index] = mask;
  }

  int preservedRegs(RegGroup group) => _preservedRegs[group.index];
  void setPreservedRegs(RegGroup group, int regs) =>
      _preservedRegs[group.index] = regs;
}

/// Function signature.
class FuncSignature {
  static const int kNoVarArgs = 0xFF;

  CallConvId _callConvId = CallConvId.cdecl;
  int _argCount = 0;
  int _vaIndex = kNoVarArgs;
  TypeId _ret = TypeId.void_;
  final List<TypeId> _args = List.filled(Globals.kMaxFuncArgs, TypeId.void_);

  FuncSignature({
    CallConvId callConvId = CallConvId.cdecl,
    int vaIndex = kNoVarArgs,
    TypeId? retType,
    List<TypeId>? args,
  }) {
    setCallConvId(callConvId);
    setVaIndex(vaIndex);
    if (retType != null) {
      setRet(retType);
    }
    if (args != null) {
      for (var i = 0; i < args.length; i++) {
        setArg(i, args[i]);
      }
    }
  }

  void reset() {
    _callConvId = CallConvId.cdecl;
    _argCount = 0;
    _vaIndex = kNoVarArgs;
    _ret = TypeId.void_;
    _args.fillRange(0, _args.length, TypeId.void_);
  }

  CallConvId get callConvId => _callConvId;
  void setCallConvId(CallConvId id) => _callConvId = id;

  bool get hasRet => _ret != TypeId.void_;
  TypeId get ret => _ret;
  TypeId get retType => _ret;
  void setRet(TypeId typeId) => _ret = typeId;

  int get argCount => _argCount;
  TypeId arg(int i) => _args[i];

  void setArg(int index, TypeId typeId) {
    _args[index] = typeId;
    if (index >= _argCount) _argCount = index + 1;
  }

  void addArg(TypeId typeId) {
    if (_argCount < Globals.kMaxFuncArgs) {
      _args[_argCount++] = typeId;
    }
  }

  bool get hasVarArgs => _vaIndex != kNoVarArgs;
  int get vaIndex => _vaIndex;
  void setVaIndex(int index) => _vaIndex = index & 0xFF;

  @override
  bool operator ==(Object other) {
    if (other is! FuncSignature) return false;
    if (_callConvId != other._callConvId ||
        _argCount != other._argCount ||
        _vaIndex != other._vaIndex ||
        _ret != other._ret) return false;
    for (int i = 0; i < _argCount; i++) {
      if (_args[i] != other._args[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int h = _callConvId.index ^ _argCount ^ _vaIndex ^ _ret.index;
    for (int i = 0; i < _argCount; i++) {
      h ^= _args[i].index;
    }
    return h;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.write('FuncSignature(');
    sb.write('conv=${_callConvId.name}, ');
    sb.write('ret=${_ret.name}, ');
    sb.write('args=[');
    for (int i = 0; i < _argCount; i++) {
      if (i > 0) sb.write(', ');
      sb.write(_args[i].name);
    }
    sb.write('])');
    return sb.toString();
  }

  // --- Helper methods for tests / concise construction ---

  static FuncSignature noArgs(
      {TypeId ret = TypeId.int32, CallConvId cc = CallConvId.cdecl}) {
    final sig = FuncSignature();
    sig.setRet(ret);
    sig.setCallConvId(cc);
    return sig;
  }

  static FuncSignature build(List<TypeId> args,
      [TypeId ret = TypeId.void_, CallConvId cc = CallConvId.cdecl]) {
    final sig = FuncSignature();
    sig.setRet(ret);
    sig.setCallConvId(cc);
    for (final arg in args) {
      sig.addArg(arg);
    }
    return sig;
  }

  static FuncSignature build32<T>(List<TypeId> args,
      [CallConvId cc = CallConvId.cdecl]) {
    return build(args, TypeId.int32, cc);
  }

  static FuncSignature i64([TypeId ret = TypeId.int64]) {
    final sig = FuncSignature();
    sig.setRet(ret);
    sig.addArg(TypeId.int64);
    return sig;
  }

  static FuncSignature i64i64([TypeId ret = TypeId.int64]) {
    final sig = FuncSignature();
    sig.setRet(ret);
    sig.addArg(TypeId.int64);
    sig.addArg(TypeId.int64);
    return sig;
  }

  static FuncSignature i64i64i64([TypeId ret = TypeId.int64]) {
    final sig = FuncSignature();
    sig.setRet(ret);
    sig.addArg(TypeId.int64);
    sig.addArg(TypeId.int64);
    sig.addArg(TypeId.int64);
    return sig;
  }

  static FuncSignature f64f64([TypeId ret = TypeId.float64]) {
    final sig = FuncSignature();
    sig.setRet(ret);
    sig.addArg(TypeId.float64);
    sig.addArg(TypeId.float64);
    return sig;
  }

  static FuncSignature f64f64f64([TypeId ret = TypeId.float64]) {
    final sig = FuncSignature();
    sig.setRet(ret);
    sig.addArg(TypeId.float64);
    sig.addArg(TypeId.float64);
    sig.addArg(TypeId.float64);
    return sig;
  }
}

/// Compatibility enum for register types in function assignments.
enum FuncRegType {
  none,
  gp,
  vec,
  mask,
  x86Mm,
  x86St,
  xmm,
  ymm,
  zmm;
}

/// Argument or return value assignment bits.
class FuncValueBits {
  static const int kTypeIdShift = 0;
  static const int kTypeIdMask = 0x000000FF;

  static const int kFlagIsReg = 0x00000100;
  static const int kFlagIsStack = 0x00000200;
  static const int kFlagIsIndirect = 0x00000400;
  static const int kFlagIsDone = 0x00000800;

  static const int kStackOffsetShift = 12;
  static const int kStackOffsetMask = 0xFFFFF000;

  static const int kRegIdShift = 16;
  static const int kRegIdMask = 0x00FF0000;

  static const int kRegTypeShift = 24;
  static const int kRegTypeMask = 0xFF000000;
}

/// Argument or return value assignment.
class FuncValue {
  int _data = 0;

  FuncValue();

  factory FuncValue.from(FuncValue other) {
    final val = FuncValue();
    val._data = other._data;
    return val;
  }

  void initTypeId(TypeId typeId) {
    _data = typeId.index << FuncValueBits.kTypeIdShift;
  }

  void initReg(RegType regType, int regId, TypeId typeId, [int flags = 0]) {
    _data = (regType.index << FuncValueBits.kRegTypeShift) |
        (regId << FuncValueBits.kRegIdShift) |
        (typeId.index << FuncValueBits.kTypeIdShift) |
        FuncValueBits.kFlagIsReg |
        flags;
  }

  void initStack(int offset, TypeId typeId) {
    _data = (offset << FuncValueBits.kStackOffsetShift) |
        (typeId.index << FuncValueBits.kTypeIdShift) |
        FuncValueBits.kFlagIsStack;
  }

  void reset() {
    _data = 0;
  }

  void assignRegData(RegType regType, int regId) {
    _data |= (regType.index << FuncValueBits.kRegTypeShift) |
        (regId << FuncValueBits.kRegIdShift) |
        FuncValueBits.kFlagIsReg;
  }

  void assignStackOffset(int offset) {
    _data |= (offset << FuncValueBits.kStackOffsetShift) |
        FuncValueBits.kFlagIsStack;
  }

  bool get isInitialized => _data != 0;
  bool get isReg => (_data & FuncValueBits.kFlagIsReg) != 0;
  bool get isStack => (_data & FuncValueBits.kFlagIsStack) != 0;
  bool get isAssigned =>
      (_data & (FuncValueBits.kFlagIsReg | FuncValueBits.kFlagIsStack)) != 0;
  bool get isIndirect => (_data & FuncValueBits.kFlagIsIndirect) != 0;
  bool get isDone => (_data & FuncValueBits.kFlagIsDone) != 0;

  void addFlags(int flags) => _data |= flags;
  void clearFlags(int flags) => _data &= ~flags;

  FuncRegType get regType {
    final rt = fullRegType;
    if (rt == RegType.none) return FuncRegType.none;
    final group = RegUtils.groupOf(rt);
    if (group == RegGroup.gp) return FuncRegType.gp;
    if (group == RegGroup.vec) {
      if (rt == RegType.vec128) return FuncRegType.xmm;
      if (rt == RegType.vec256) return FuncRegType.ymm;
      if (rt == RegType.vec512) return FuncRegType.zmm;
      return FuncRegType.vec;
    }
    if (group == RegGroup.mask) return FuncRegType.mask;
    if (group == RegGroup.x86Mm) return FuncRegType.x86Mm;
    return FuncRegType.none;
  }

  RegType get fullRegType => RegType.values[
      (_data & FuncValueBits.kRegTypeMask) >> FuncValueBits.kRegTypeShift];

  void setRegType(RegType regType) {
    _data = (_data & ~FuncValueBits.kRegTypeMask) |
        (regType.index << FuncValueBits.kRegTypeShift);
  }

  int get regId =>
      (_data & FuncValueBits.kRegIdMask) >> FuncValueBits.kRegIdShift;
  void setRegId(int regId) {
    _data = (_data & ~FuncValueBits.kRegIdMask) |
        (regId << FuncValueBits.kRegIdShift);
  }

  /// Gets the stack offset (sign-extended from 20-bit field).
  int get stackOffset {
    final raw = (_data & FuncValueBits.kStackOffsetMask) >>
        FuncValueBits.kStackOffsetShift;
    // Sign extend from 20 bits
    if ((raw & 0x80000) != 0) {
      return raw | 0xFFF00000; // Extend sign bit
    }
    return raw;
  }

  void setStackOffset(int offset) {
    _data = (_data & ~FuncValueBits.kStackOffsetMask) |
        ((offset & 0xFFFFF) << FuncValueBits.kStackOffsetShift);
  }

  TypeId get typeId => TypeId.values[
      (_data & FuncValueBits.kTypeIdMask) >> FuncValueBits.kTypeIdShift];
  void setTypeId(TypeId typeId) {
    _data = (_data & ~FuncValueBits.kTypeIdMask) |
        (typeId.index << FuncValueBits.kTypeIdShift);
  }

  @override
  int get hashCode => _data;
}

/// Multiple FuncValues.
class FuncValuePack {
  static const int kMaxValuePack = Globals.kMaxValuePack;
  final List<FuncValue> _values =
      List.generate(kMaxValuePack, (_) => FuncValue());

  FuncValuePack();

  void reset() {
    for (var value in _values) {
      value.reset();
    }
  }

  int count() {
    int n = Globals.kMaxValuePack;
    while (n > 0 && !_values[n - 1].isInitialized) n--;
    return n;
  }

  FuncValue operator [](int index) => _values[index];

  void resetValue(int index) => _values[index].reset();
  bool hasValue(int index) => _values[index].isInitialized;

  void assignReg(int index, Reg reg, [TypeId typeId = TypeId.void_]) {
    _values[index].initReg(reg.regType, reg.id, typeId);
  }

  void assignStack(int index, int offset, [TypeId typeId = TypeId.void_]) {
    _values[index].initStack(offset, typeId);
  }
}

/// Function and Frame attributes.
class FuncFrameAttributes {
  static const int kNoAttributes = 0;
  static const int kHasVarArgs = 0x00000001;
  static const int kHasPreservedFP = 0x00000010;
  static const int kHasFuncCalls = 0x00000020;
  static const int kAlignedVecSR = 0x00000040;
  static const int kIndirectBranchProtection = 0x00000080;
  static const int kIsFinalized = 0x00000800;

  static const int kX86_AVXEnabled = 0x00010000;
  static const int kX86_AVX512Enabled = 0x00020000;
  static const int kX86_MMXCleanup = 0x00040000;
  static const int kX86_AVXCleanup = 0x00080000;
  static const int kX86_AVXAutoCleanup = 0x00100000;

  final int attributes;
  final int localStackSize;
  final Map<RegGroup, int> preservedRegs;

  FuncFrameAttributes({
    this.attributes = kNoAttributes,
    this.localStackSize = 0,
    Map<RegGroup, int>? preservedRegs,
  }) : preservedRegs = preservedRegs != null
            ? Map<RegGroup, int>.from(preservedRegs)
            : const {};

  FuncFrameAttributes copyWith({
    int? attributes,
    int? localStackSize,
    Map<RegGroup, int>? preservedRegs,
  }) {
    return FuncFrameAttributes(
      attributes: attributes ?? this.attributes,
      localStackSize: localStackSize ?? this.localStackSize,
      preservedRegs: preservedRegs ?? this.preservedRegs,
    );
  }

  static FuncFrameAttributes nonLeaf({
    int attributes = kHasFuncCalls,
    int localStackSize = 0,
    Iterable<BaseReg>? preservedRegs,
  }) {
    return FuncFrameAttributes(
      attributes: attributes | kHasFuncCalls,
      localStackSize: localStackSize,
      preservedRegs: _maskFromRegs(preservedRegs),
    );
  }

  static FuncFrameAttributes build({
    int attributes = kNoAttributes,
    int localStackSize = 0,
    Iterable<BaseReg>? preservedRegs,
  }) {
    return FuncFrameAttributes(
      attributes: attributes,
      localStackSize: localStackSize,
      preservedRegs: _maskFromRegs(preservedRegs),
    );
  }
}

Environment _environmentForCallingConvention(CallingConvention cc) {
  switch (cc) {
    case CallingConvention.win64:
      return Environment.x64Windows();
    case CallingConvention.sysV64:
      return Environment.x64SysV();
    default:
      return Environment.host();
  }
}

Map<RegGroup, int> _maskFromRegs(Iterable<BaseReg>? regs) {
  final masks = <RegGroup, int>{};
  if (regs == null) return masks;
  for (final reg in regs) {
    final mask = masks[reg.group] ?? 0;
    masks[reg.group] = mask | (1 << reg.id);
  }
  return masks;
}

typedef FuncAttributes = FuncFrameAttributes;
typedef FuncFrameAttr = FuncFrameAttributes;

/// Expanded function signature.
class FuncDetail {
  final CallConv _callConv = CallConv();
  int _argCount = 0;
  int _vaIndex = FuncSignature.kNoVarArgs;
  final List<int> _usedRegs = List.filled(Globals.kNumVirtGroups, 0);
  int _argStackSize = 0;
  final FuncValuePack _rets = FuncValuePack();
  final List<FuncValuePack> _args =
      List.generate(Globals.kMaxFuncArgs, (_) => FuncValuePack());

  FuncDetail([FuncSignature? signature, CallingConvention? cc]) {
    if (signature != null) {
      final env =
          _environmentForCallingConvention(cc ?? CallingConvention.sysV64);
      final err = init(signature, env);
      if (err != AsmJitError.ok) {
        throw StateError('FuncDetail.init failed: $err');
      }
    }
  }

  AsmJitError init(FuncSignature signature, Environment env) {
    CallConvId callConvId = signature.callConvId;
    int argCount = signature.argCount;

    if (argCount > Globals.kMaxFuncArgs) return AsmJitError.invalidArgument;

    AsmJitError err = _callConv.init(callConvId, env);
    if (err != AsmJitError.ok) return err;

    int registerSize = Environment.regSizeOfArch(_callConv.arch);
    // Shortcut for deabstract logic

    for (int i = 0; i < argCount; i++) {
      _args[i][0].initTypeId(signature.arg(i).deabstract(registerSize));
    }

    _argCount = argCount;
    _vaIndex = signature.vaIndex;

    if (signature.hasRet) {
      _rets[0].initTypeId(signature.ret.deabstract(registerSize));
    }

    return _initFuncDetail(this, signature, registerSize);
  }

  void reset() {
    _callConv.reset();
    _argCount = 0;
    _vaIndex = FuncSignature.kNoVarArgs;
    _usedRegs.fillRange(0, _usedRegs.length, 0);
    _argStackSize = 0;
    _rets.reset();
    for (var arg in _args) {
      arg.reset();
    }
  }

  CallConv get callConv => _callConv;
  int get flags => _callConv.flags;
  bool hasFlag(int flag) => _callConv.hasFlag(flag);

  bool hasRet() => _rets[0].isInitialized;
  int get argCount => _argCount;

  FuncValuePack get rets => _rets;
  FuncValue ret(int index) => _rets[index];

  List<FuncValuePack> get args => _args;
  FuncValue arg(int argIndex, [int valueIndex = 0]) =>
      _args[argIndex][valueIndex];

  bool get hasVarArgs => _vaIndex != FuncSignature.kNoVarArgs;
  int get vaIndex => _vaIndex;

  bool get hasStackArgs => _argStackSize != 0;
  int get argStackSize => _argStackSize;

  int redZoneSize() => _callConv.redZoneSize;
  int spillZoneSize() => _callConv.spillZoneSize;
  int naturalStackAlignment() => _callConv.naturalStackAlignment;

  int passedRegs(RegGroup group) => _callConv.passedRegs(group);
  int preservedRegs(RegGroup group) => _callConv.preservedRegs(group);

  int usedRegs(RegGroup group) => _usedRegs[group.index];
  void addUsedRegs(RegGroup group, int regs) => _usedRegs[group.index] |= regs;

  void setArgStackSize(int size) => _argStackSize = size;

  FuncValue getArg(int index) => _args[index][0];
  FuncValue get retValue => _rets[0];
  int get stackArgsSize => _argStackSize;
  int get stackArgCount => (_argStackSize + 7) ~/ 8; // Approximation

  int get gpArgCount {
    int count = 0;
    for (int i = 0; i < _argCount; i++) {
      if (_args[i][0].isReg && _args[i][0].regType == FuncRegType.gp) {
        count++;
      }
    }
    return count;
  }
}

/// Function frame.
class FuncFrame {
  static const int kTagInvalidOffset = 0xFFFFFFFF;

  int _attributes = 0;
  Arch _arch = Arch.unknown;
  int _spRegId = Reg.kIdBad;
  int _saRegId = Reg.kIdBad;

  int _redZoneSize = 0;
  int _spillZoneSize = 0;
  int _naturalStackAlignment = 0;
  int _minDynamicAlignment = 0;

  int _callStackAlignment = 0;
  int _localStackAlignment = 0;
  int _finalStackAlignment = 0;

  int _calleeStackCleanup = 0;

  int _callStackSize = 0;
  int _localStackSize = 0;
  int _finalStackSize = 0;

  int _localStackOffset = 0;
  int _daOffset = 0;
  int _saOffsetFromSp = 0;
  int _saOffsetFromSa = 0;

  int _stackAdjustment = 0;

  final List<int> _dirtyRegs = List.filled(Globals.kNumVirtGroups, 0);
  final List<int> _preservedRegs = List.filled(Globals.kNumVirtGroups, 0);
  final List<int> _unavailableRegs = List.filled(Globals.kNumVirtGroups, 0);

  final List<int> _saveRestoreRegSize = List.filled(Globals.kNumVirtGroups, 0);
  final List<int> _saveRestoreAlignment =
      List.filled(Globals.kNumVirtGroups, 0);

  int _pushPopSaveSize = 0;
  int _extraRegSaveSize = 0;
  int _pushPopSaveOffset = 0;
  int _extraRegSaveOffset = 0;

  FuncFrame();

  factory FuncFrame.host({
    FuncFrameAttr? attr,
    int localStackSize = 0,
    Iterable<BaseReg>? preservedRegs,
  }) {
    final frame = FuncFrame();
    frame._arch = Arch.host;
    frame._attributes = attr?.attributes ?? FuncAttributes.kNoAttributes;

    final baseLocalStack = attr?.localStackSize ?? 0;
    frame._localStackSize = baseLocalStack + localStackSize;
    frame._finalStackSize = frame._localStackSize;

    final combinedPreserved = <RegGroup, int>{};
    if (attr?.preservedRegs.isNotEmpty ?? false) {
      combinedPreserved.addAll(attr!.preservedRegs);
    }

    final explicitMasks = _maskFromRegs(preservedRegs);
    explicitMasks.forEach((group, mask) {
      combinedPreserved[group] = (combinedPreserved[group] ?? 0) | mask;
    });

    for (final group in RegGroup.values) {
      if (group.index >= Globals.kNumVirtGroups) continue;
      frame._preservedRegs[group.index] = combinedPreserved[group] ?? 0;
    }

    return frame;
  }

  AsmJitError init(FuncDetail func) {
    Arch arch = func.callConv.arch;
    if (arch == Arch.unknown) return AsmJitError.invalidArch;

    final archTraits = ArchTraits.forArch(arch);

    reset();

    _arch = arch;
    _spRegId = archTraits.spRegId;
    _saRegId = Reg.kIdBad;

    int naturalStackAlignment = func.callConv.naturalStackAlignment;
    int minDynamicAlignment = support.max(naturalStackAlignment, 16);

    if (minDynamicAlignment == naturalStackAlignment) {
      minDynamicAlignment <<= 1;
    }

    _naturalStackAlignment = naturalStackAlignment;
    _minDynamicAlignment = minDynamicAlignment;
    _redZoneSize = func.redZoneSize();
    _spillZoneSize = func.spillZoneSize();
    _finalStackAlignment = _naturalStackAlignment;

    if (func.hasFlag(CallConvFlags.kCalleePopsStack)) {
      _calleeStackCleanup = func.argStackSize;
    }

    for (var group in RegGroup.values) {
      if (group.index >= Globals.kNumVirtGroups) continue;
      _dirtyRegs[group.index] = func.usedRegs(group);
      _preservedRegs[group.index] = func.preservedRegs(group);
    }

    _preservedRegs[RegGroup.gp.index] &= ~support.bitMask(archTraits.spRegId);

    for (var group in RegGroup.values) {
      if (group.index >= Globals.kNumVirtGroups) continue;
      _saveRestoreRegSize[group.index] =
          func.callConv.saveRestoreRegSize(group);
      _saveRestoreAlignment[group.index] =
          func.callConv.saveRestoreAlignment(group);
    }

    return AsmJitError.ok;
  }

  void reset() {
    _attributes = FuncAttributes.kNoAttributes;
    _arch = Arch.unknown;
    _spRegId = Reg.kIdBad;
    _saRegId = Reg.kIdBad;
    _redZoneSize = 0;
    _spillZoneSize = 0;
    _naturalStackAlignment = 0;
    _minDynamicAlignment = 0;
    _callStackAlignment = 0;
    _localStackAlignment = 0;
    _finalStackAlignment = 0;
    _calleeStackCleanup = 0;
    _callStackSize = 0;
    _localStackSize = 0;
    _finalStackSize = 0;
    _localStackOffset = 0;
    _daOffset = 0;
    _saOffsetFromSp = 0;
    _saOffsetFromSa = 0;
    _stackAdjustment = 0;

    _dirtyRegs.fillRange(0, _dirtyRegs.length, 0);
    _preservedRegs.fillRange(0, _preservedRegs.length, 0);
    _unavailableRegs.fillRange(0, _unavailableRegs.length, 0);
    _saveRestoreRegSize.fillRange(0, _saveRestoreRegSize.length, 0);
    _saveRestoreAlignment.fillRange(0, _saveRestoreAlignment.length, 0);

    _pushPopSaveSize = 0;
    _extraRegSaveSize = 0;
    _pushPopSaveOffset = 0;
    _extraRegSaveOffset = 0;
  }

  Arch get arch => _arch;
  int get attributes => _attributes;
  bool hasAttribute(int attr) => (_attributes & attr) != 0;
  void addAttributes(int attrs) => _attributes |= attrs;
  void clearAttributes(int attrs) => _attributes &= ~attrs;

  bool get hasVarArgs => hasAttribute(FuncAttributes.kHasVarArgs);
  void setVarArgs() => addAttributes(FuncAttributes.kHasVarArgs);
  void resetVarArgs() => clearAttributes(FuncAttributes.kHasVarArgs);

  bool get hasPreservedFP => hasAttribute(FuncAttributes.kHasPreservedFP);
  void setPreservedFP() => addAttributes(FuncAttributes.kHasPreservedFP);
  void resetPreservedFP() => clearAttributes(FuncAttributes.kHasPreservedFP);

  bool get hasFuncCalls => hasAttribute(FuncAttributes.kHasFuncCalls);
  void setFuncCalls() => addAttributes(FuncAttributes.kHasFuncCalls);
  void resetFuncCalls() => clearAttributes(FuncAttributes.kHasFuncCalls);

  bool isAvxEnabled() => hasAttribute(FuncAttributes.kX86_AVXEnabled);
  void setAvxEnabled() => addAttributes(FuncAttributes.kX86_AVXEnabled);
  void resetAvxEnabled() => clearAttributes(FuncAttributes.kX86_AVXEnabled);

  bool isAvx512Enabled() => hasAttribute(FuncAttributes.kX86_AVX512Enabled);
  void setAvx512Enabled() => addAttributes(FuncAttributes.kX86_AVX512Enabled);
  void resetAvx512Enabled() =>
      clearAttributes(FuncAttributes.kX86_AVX512Enabled);

  bool get hasCallStack => _callStackSize != 0;
  bool get hasLocalStack => _localStackSize != 0;
  bool get hasAlignedVecSaveRestore =>
      hasAttribute(FuncAttributes.kAlignedVecSR);

  bool hasDynamicAlignment() => _finalStackAlignment >= _minDynamicAlignment;
  bool get hasDA => hasDynamicAlignment();

  bool get hasRedZone => _redZoneSize != 0;
  int get redZoneSize => _redZoneSize;
  bool get hasSpillZone => _spillZoneSize != 0;
  int get spillZoneSize => _spillZoneSize;

  int naturalStackAlignment() => _naturalStackAlignment;
  int minDynamicAlignment() => _minDynamicAlignment;

  bool hasCalleeStackCleanup() => _calleeStackCleanup != 0;
  int get calleeStackCleanup => _calleeStackCleanup;

  int get callStackAlignment => _callStackAlignment;
  int get localStackAlignment => _localStackAlignment;
  int get finalStackAlignment => _finalStackAlignment;

  void setCallStackAlignment(int alignment) {
    _callStackAlignment = alignment & 0xFF;
    _finalStackAlignment = support.max3(
        _naturalStackAlignment, _callStackAlignment, _localStackAlignment);
  }

  void setLocalStackAlignment(int alignment) {
    _localStackAlignment = alignment & 0xFF;
    _finalStackAlignment = support.max3(
        _naturalStackAlignment, _callStackAlignment, _localStackAlignment);
  }

  void updateCallStackAlignment(int alignment) {
    _callStackAlignment = support.max(_callStackAlignment, alignment) & 0xFF;
    _finalStackAlignment =
        support.max(_finalStackAlignment, _callStackAlignment);
  }

  void updateLocalStackAlignment(int alignment) {
    _localStackAlignment = support.max(_localStackAlignment, alignment) & 0xFF;
    _finalStackAlignment =
        support.max(_finalStackAlignment, _localStackAlignment);
  }

  int get callStackSize => _callStackSize;
  int get localStackSize => _localStackSize;
  void setCallStackSize(int size) => _callStackSize = size;
  void setLocalStackSize(int size) => _localStackSize = size;

  void updateCallStackSize(int size) =>
      _callStackSize = support.max(_callStackSize, size);
  void updateLocalStackSize(int size) =>
      _localStackSize = support.max(_localStackSize, size);

  int get finalStackSize => _finalStackSize;
  int get localStackOffset => _localStackOffset;

  bool hasDaOffset() => _daOffset != kTagInvalidOffset;
  int get daOffset => _daOffset;

  int saOffset(int regId) =>
      regId == _spRegId ? _saOffsetFromSp : _saOffsetFromSa;
  int get saOffsetFromSp => _saOffsetFromSp;
  int get saOffsetFromSa => _saOffsetFromSa;

  int dirtyRegs(RegGroup group) => _dirtyRegs[group.index];
  void setDirtyRegs(RegGroup group, int regs) => _dirtyRegs[group.index] = regs;
  void addDirtyRegs(RegGroup group, int regs) =>
      _dirtyRegs[group.index] |= regs;

  int savedRegs(RegGroup group) =>
      _dirtyRegs[group.index] & _preservedRegs[group.index];

  int preservedRegs(RegGroup group) => _preservedRegs[group.index];
  void setPreservedRegs(RegGroup group, int regs) =>
      _preservedRegs[group.index] = regs;

  int unavailableRegs(RegGroup group) => _unavailableRegs[group.index];
  void setUnavailableRegs(RegGroup group, int regs) =>
      _unavailableRegs[group.index] = regs;
  void addUnavailableRegs(RegGroup group, int regs) =>
      _unavailableRegs[group.index] |= regs;

  int saveRestoreRegSize(RegGroup group) => _saveRestoreRegSize[group.index];
  int saveRestoreAlignment(RegGroup group) =>
      _saveRestoreAlignment[group.index];

  int get spRegId => _spRegId;
  int get saRegId => _saRegId;
  void setSaRegId(int id) => _saRegId = id & 0xFF;

  int get pushPopSaveSize => _pushPopSaveSize;
  int get pushPopSaveOffset => _pushPopSaveOffset;
  int get extraRegSaveSize => _extraRegSaveSize;
  int get extraRegSaveOffset => _extraRegSaveOffset;

  int get stackAdjustment => _stackAdjustment;

  int get frameSize => _finalStackSize;

  int getLocalOffset(int slotIndex) => _localStackOffset + slotIndex * 8;
  int getStackArgOffset(int index,
      [CallingConvention? cc, bool includeShadowSpace = false]) {
    if (cc != null) {
      int regCount = 0;
      if (cc == CallingConvention.win64) {
        regCount = 4;
      } else if (cc == CallingConvention.sysV64) {
        regCount = 6;
      }

      if (index < regCount) {
        throw ArgumentError('Argument $index is passed in register');
      }
    }

    final base = _spillZoneSize + index * 8;
    if (includeShadowSpace && cc == CallingConvention.win64) {
      return base + 32;
    }
    return base;
  }

  /// Returns the argument register ID for the given index and calling convention.
  /// This is a convenience for tests.
  int getArgRegId(int index, [CallingConvention? cc]) {
    if (cc == CallingConvention.win64) {
      const regs = [1, 2, 8, 9]; // rcx, rdx, r8, r9
      return index < regs.length ? regs[index] : Reg.kIdBad;
    } else if (cc == CallingConvention.sysV64) {
      const regs = [7, 6, 2, 1, 8, 9]; // rdi, rsi, rdx, rcx, r8, r9
      return index < regs.length ? regs[index] : Reg.kIdBad;
    }
    return Reg.kIdBad;
  }

  int get calleeSavedRegs => _preservedRegs[RegGroup.gp.index];

  AsmJitError finalize() {
    if (!Environment.isValidArch(arch)) return AsmJitError.invalidArch;

    final archTraits = ArchTraits.forArch(arch);

    int registerSize = _saveRestoreRegSize[RegGroup.gp.index];
    int vectorSize = _saveRestoreRegSize[RegGroup.vec.index];
    int returnAddressSize = archTraits.hasLinkReg ? 0 : registerSize;

    int stackAlignment = _finalStackAlignment;

    bool hasFp = hasPreservedFP;
    bool hasDa = hasDynamicAlignment();

    int kSp = archTraits.spRegId;
    int kFp = archTraits.fpRegId;
    int kLr = archTraits.linkRegId;

    if (hasFp) {
      _dirtyRegs[RegGroup.gp.index] |= support.bitMask(kFp);
      if (kLr >= 0 && kLr != Reg.kIdBad) {
        _dirtyRegs[RegGroup.gp.index] |= support.bitMask(kLr);
      }
    }

    int saRegId = _saRegId;
    if (saRegId == Reg.kIdBad) {
      saRegId = kSp;
    }

    if (hasDa && saRegId == kSp) {
      saRegId = kFp;
    }

    if (saRegId != kSp) {
      _dirtyRegs[RegGroup.gp.index] |= support.bitMask(saRegId);
    }

    _spRegId = kSp;
    _saRegId = saRegId;

    List<int> saveRestoreSizes = [0, 0];
    for (var group in RegGroup.values) {
      if (group.index >= Globals.kNumVirtGroups) continue;
      // Use different index based on whether this group supports push/pop
      int idx = archTraits.hasInstPushPop(group) ? 0 : 1;
      saveRestoreSizes[idx] += support.alignUp(
          support.popcnt(savedRegs(group)) * saveRestoreRegSize(group),
          saveRestoreAlignment(group));
    }

    _pushPopSaveSize = saveRestoreSizes[0];
    _extraRegSaveSize = saveRestoreSizes[1];

    int v = 0;
    v += callStackSize;
    v = support.alignUp(v, stackAlignment);

    _localStackOffset = v;
    v += localStackSize;

    if (stackAlignment >= vectorSize && _extraRegSaveSize != 0) {
      addAttributes(FuncAttributes.kAlignedVecSR);
      v = support.alignUp(v, vectorSize);
    }

    _extraRegSaveOffset = v;
    v += _extraRegSaveSize;

    if (hasDa && !hasFp) {
      _daOffset = v;
      v += registerSize;
    } else {
      _daOffset = kTagInvalidOffset;
    }

    if (v != 0 || hasFuncCalls || returnAddressSize == 0) {
      v += support.alignUpDiff(
          v + _pushPopSaveSize + returnAddressSize, stackAlignment);
    }

    _pushPopSaveOffset = v;
    _stackAdjustment = v;
    v += _pushPopSaveSize;
    _finalStackSize = v;

    if (!archTraits.hasLinkReg) {
      v += registerSize;
    }

    if (hasDa) {
      _stackAdjustment = support.alignUp(_stackAdjustment, stackAlignment);
    }

    _saOffsetFromSp = hasDa ? kTagInvalidOffset : v;
    _saOffsetFromSa = hasFp
        ? returnAddressSize + registerSize
        : returnAddressSize + _pushPopSaveSize;

    addAttributes(FuncAttributes.kIsFinalized);
    return AsmJitError.ok;
  }
}

/// Function arguments assignment.
class FuncArgsAssignment {
  FuncDetail? _funcDetail;
  int _saRegId = Reg.kIdBad;
  final List<FuncValuePack> _argPacks =
      List.generate(Globals.kMaxFuncArgs, (_) => FuncValuePack());

  FuncArgsAssignment([this._funcDetail]);

  void reset([FuncDetail? fd]) {
    _funcDetail = fd;
    _saRegId = Reg.kIdBad;
    for (var pack in _argPacks) {
      pack.reset();
    }
  }

  FuncDetail? get funcDetail => _funcDetail;
  void setFuncDetail(FuncDetail fd) => _funcDetail = fd;

  bool get hasSaRegId => _saRegId != Reg.kIdBad;
  int get saRegId => _saRegId;
  void setSaRegId(int id) => _saRegId = id & 0xFF;
  void resetSaRegId() => _saRegId = Reg.kIdBad;

  FuncValue arg(int argIndex, int valueIndex) =>
      _argPacks[argIndex][valueIndex];

  bool isAssigned(int argIndex, int valueIndex) =>
      _argPacks[argIndex][valueIndex].isAssigned;

  void assignReg(int argIndex, Reg reg, [TypeId typeId = TypeId.void_]) {
    _argPacks[argIndex][0].initReg(reg.regType, reg.id, typeId);
  }

  void assignRegInPack(int argIndex, int valueIndex, Reg reg,
      [TypeId typeId = TypeId.void_]) {
    _argPacks[argIndex][valueIndex].initReg(reg.regType, reg.id, typeId);
  }

  void assignStack(int argIndex, int offset, [TypeId typeId = TypeId.void_]) {
    _argPacks[argIndex][0].initStack(offset, typeId);
  }

  void assignStackInPack(int argIndex, int valueIndex, int offset,
      [TypeId typeId = TypeId.void_]) {
    _argPacks[argIndex][valueIndex].initStack(offset, typeId);
  }

  AsmJitError updateFuncFrame(FuncFrame frame) {
    if (_funcDetail == null) return AsmJitError.invalidState;
    // This requires FuncArgsContext which we'll implement in emit_helper.dart or similar
    // For now we'll delegate it.
    return _updateFuncFrame(this, frame);
  }
}

// Global registry for architecture specific logic
typedef InitCallConvFn = AsmJitError Function(
    CallConv cc, CallConvId id, Environment env);
typedef InitFuncDetailFn = AsmJitError Function(
    FuncDetail func, FuncSignature signature, int registerSize);
typedef UpdateFuncFrameFn = AsmJitError Function(
    FuncArgsAssignment assignment, FuncFrame frame);

AsmJitError _initCallConv(CallConv cc, CallConvId id, Environment env) {
  if (env.archFamily == ArchFamily.x86) {
    return X86FuncInternal.initCallConv(cc, id, env);
  }
  if (env.archFamily == ArchFamily.aarch64) {
    return A64FuncInternal.initCallConv(cc, id, env);
  }
  return AsmJitError.invalidArgument;
}

AsmJitError _initFuncDetail(
    FuncDetail func, FuncSignature signature, int registerSize) {
  final family = func.callConv.arch.family;
  if (family == ArchFamily.x86) {
    return X86FuncInternal.initFuncDetail(func, signature, registerSize);
  }
  if (family == ArchFamily.aarch64) {
    return A64FuncInternal.initFuncDetail(func, signature, registerSize);
  }
  return AsmJitError.invalidArgument;
}

AsmJitError _updateFuncFrame(FuncArgsAssignment assignment, FuncFrame frame) {
  final family = frame.arch.family;
  if (family == ArchFamily.x86) {
    return X86FuncInternal.updateFuncFrame(assignment, frame);
  }
  if (family == ArchFamily.aarch64) {
    return A64FuncInternal.updateFuncFrame(assignment, frame);
  }
  return AsmJitError.invalidState;
}

// Deprecated dynamic registration code removed.
