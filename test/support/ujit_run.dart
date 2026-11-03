// JIT harness shared by the UniCompiler semantics tests.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;

typedef _FnNative = Void Function(Pointer<Uint8>);
typedef _FnDart = void Function(Pointer<Uint8>);

/// Signature of the code emitted by [runUjit]: `dst` and the three inputs
/// `a`, `b` and `c` are vectors of the [runUjit] width (128-bit by default);
/// `mem` addresses the bytes of `c` (aligned to the width) and may be used as
/// a memory operand or as scratch.
typedef UjitEmit = void Function(
    UniCompiler cc, BaseReg d, BaseReg a, BaseReg b, BaseReg c, BaseMem mem);

/// JIT-compiles [emit] for the host architecture, runs it with the inputs
/// [a], [b] and [c] (16 bytes each, 32/64 with a 256/512-bit [width]) and
/// returns the
/// bytes of `dst`.
Uint8List runUjit(UjitEmit emit, Uint8List a, Uint8List b, Uint8List c,
    {CpuFeatures? features, VecWidth width = VecWidth.k128}) {
  final n = switch (width) {
    VecWidth.k256 => 32,
    VecWidth.k512 => 64,
    _ => 16,
  };
  final rt = JitRuntime();
  try {
    final code = CodeHolder(env: rt.environment);
    final isA64 = code.env.arch == Arch.aarch64;
    final BaseCompiler archCc = isA64
        ? A64Compiler(env: code.env, labelManager: code.labelManager)
        : X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(archCc, features: features)..initVecWidth(width);
    BaseMem mem(BaseReg p, int off) => p is A64Gp
        ? A64Mem.baseOffset(p, off)
        : X86Mem.baseDisp(p as X86Gp, off, size: n);
    final load = switch (n) {
      32 => UniOpVM.load256U32,
      64 => UniOpVM.load512U32,
      _ => UniOpVM.load128U32,
    };
    final store = switch (n) {
      32 => UniOpMV.store256U32,
      64 => UniOpMV.store512U32,
      _ => UniOpMV.store128U32,
    };

    cc.addFunc(
        FuncSignature.build([TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
    final p = cc.newGpPtr('p');
    cc.setArg(0, p);
    final va = cc.newVec('a');
    final vb = cc.newVec('b');
    final vc = cc.newVec('c');
    final vd = cc.newVec('d');
    cc.emitVM(load, va, mem(p, 0));
    cc.emitVM(load, vb, mem(p, n));
    cc.emitVM(load, vc, mem(p, 2 * n));
    emit(cc, vd, va, vb, vc, mem(p, 2 * n));
    cc.emitMV(store, mem(p, 3 * n), vd);
    cc.ret();
    cc.endFunc();
    archCc.finalize();
    archCc
        .serializeToAssembler(isA64 ? A64Assembler(code) : X86Assembler(code));

    final fn = rt.add(code);
    // Aligned to the width: legacy SSE memory operands require it.
    final raw = pkgffi.calloc<Uint8>(4 * n + n);
    try {
      final buf = Pointer<Uint8>.fromAddress((raw.address + n - 1) & ~(n - 1));
      buf.asTypedList(4 * n)
        ..setAll(0, a)
        ..setAll(n, b)
        ..setAll(2 * n, c);
      fn.pointer.cast<NativeFunction<_FnNative>>().asFunction<_FnDart>()(buf);
      return Uint8List.fromList(buf.asTypedList(4 * n).sublist(3 * n, 4 * n));
    } finally {
      pkgffi.calloc.free(raw);
    }
  } finally {
    rt.dispose();
  }
}
