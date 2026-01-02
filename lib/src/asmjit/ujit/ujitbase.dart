/// UJIT Base Types
///
/// Ported from asmjit/ujit/ujitbase.h

import '../core/operand.dart';
import '../core/reg_type.dart';
import '../core/reg_utils.dart';
import '../core/compiler.dart';
import '../core/builder.dart';

/// Data alignment.
enum Alignment {
  none(0),
  byte1(1),
  byte2(2),
  byte4(4),
  byte8(8),
  byte16(16),
  byte32(32),
  byte64(64);

  final int size;
  const Alignment(this.size);
}

/// The behavior of a floating point scalar operation.
enum ScalarOpBehavior {
  /// The rest of the elements are zeroed, only the first element would contain the result (AArch64).
  zeroing,

  /// The rest of the elements are unchanged, elements above 128-bits are zeroed.
  preservingVec128;
}

/// The behavior of floating point to int conversion.
enum FloatToIntOutsideRangeBehavior {
  /// In case that the floating point is outside of the integer range, the value is the smallest integer value,
  /// which would be `0x80`, `0x8000`, `0x80000000`, or `0x8000000000000000` depending on the target integer width.
  smallestValue,

  /// In case that the floating point is outside of the integer range, the resulting integer will be saturated. If
  /// the floating point is NaN, the resulting integer value would be zero.
  saturatedValue;
}

/// The behavior of a floating point min/max instructions when comparing against NaN.
enum FMinFMaxOpBehavior {
  /// Min and max selects a finite value if one of the compared values is NaN.
  finiteValue,

  /// Min and max is implemented like `if a <|> b ? a : b`.
  ternaryLogic;
}

/// The behavior of floating point `madd` instructions.
enum FMAddOpBehavior {
  /// FMA is not available, thus `madd` is translated into two instructions (MUL + ADD).
  noFMA,

  /// FMA is available, the ISA allows to store the result to any of the inputs (X86|X86_64).
  fmaStoreToAny,

  /// FMA is available, the ISA always uses accumulator register as a destination register (AArch64).
  fmaStoreToAccumulator;
}

/// SIMD data width.
enum DataWidth {
  /// 8-bit elements.
  k8(0),

  /// 16-bit elements.
  k16(1),

  /// 32-bit elements.
  k32(2),

  /// 64-bit elements or 64-bit wide data is used.
  k64(3),

  /// 128-bit elements or 128-bit wide data is used.
  k128(4);

  final int id;
  const DataWidth(this.id);
}

/// Vector register width.
enum VecWidth {
  /// 128-bit vector register (baseline, SSE/AVX, NEON, etc...).
  k128(0),

  /// 256-bit vector register (AVX2+).
  k256(1),

  /// 512-bit vector register (AVX512_DQ & AVX512_BW & AVX512_VL).
  k512(2),

  /// 1024-bit vector register (no backend at the moment).
  k1024(3);

  final int id;
  const VecWidth(this.id);

  // Helpers
  // static const kMaxPlatformWidth = VecWidth.k512; // Platform dependent, maybe moved
}

/// Broadcast width.
enum Bcst {
  /// Broadcast 8-bit elements.
  k8(0),

  /// Broadcast 16-bit elements.
  k16(1),

  /// Broadcast 32-bit elements.
  k32(2),

  /// Broadcast 64-bit elements.
  k64(3),

  kNA(0xFE),
  kNA_Unique(0xFF);

  final int id;
  const Bcst(this.id);
}

// Helpers for VecWidth
class VecWidthUtils {
  static OperandSignature signatureOf(VecWidth vw) {
    int regTypeValue = RegType.vec128.index + vw.id;
    int regSize = 16 << vw.id;

    var sig = OperandSignature.fromOpType(OperandSignature.kOpReg) |
        OperandSignature.fromRegTypeAndGroup(
            RegType.values[regTypeValue], RegGroup.vec) |
        OperandSignature.fromSize(regSize);
    return sig;
  }
}

/// Swizzle Parameter (2 elements)
class Swizzle2 {
  final int value;
  const Swizzle2(this.value);

  static Swizzle2 from(int b, int a) => Swizzle2((b << 8) | a);

  @override
  bool operator ==(Object other) => other is Swizzle2 && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

/// Swizzle Parameter (4 elements)
class Swizzle4 {
  final int value;
  const Swizzle4(this.value);

  static Swizzle4 from(int d, int c, int b, int a) =>
      Swizzle4((d << 24) | (c << 16) | (b << 8) | a);

  @override
  bool operator ==(Object other) => other is Swizzle4 && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

// Helpers
Swizzle2 swizzle2(int b, int a) => Swizzle2.from(b, a);
Swizzle4 swizzle4(int d, int c, int b, int a) => Swizzle4.from(d, c, b, a);

/// Provides scope-based code injection.
class ScopedInjector {
  final BaseCompiler cc;

  // This expects the hook to be passed by reference-ish or we manage it via callback/closure
  // Dart doesn't have pointers to pointers. We need a way to update the hook.
  // The C++ one updates `hook` which is `BaseNode**`.
  // We can model this by having the caller pass a "Context" object or similar.
  // Or just manual management.
  // The constructor `ScopedInjector(cc, &hook)` sets `prev = cc.cursor`, sets `cc.cursor = hook`.
  // The destructor restores it.
  // Since Dart doesn't have destructors, we must use `run()` method.

  ScopedInjector._(this.cc);

  static void inject(BaseCompiler cc, BaseNode hook, void Function() callback) {
    final prev = cc.cursor;
    cc.setCursor(hook);
    try {
      callback();
    } finally {
      // The C++ version updates the hook to be the current cursor if it wasn't valid (?)
      // Actually:
      // *_hook = _cc->cursor(); // Update the hook to point to the end of injected code!
      // if (!_hook_was_cursor) { _cc->set_cursor(_prev); }
      // This means subsequent injections will append to this one.

      // We can't update 'hook' variable of the caller easily.
      // This logic will need to be handled specifically in UniCompiler where the hook is a member.
      cc.setCursor(prev);
    }
  }
}
