// JIT harness shared by the UniCompiler semantics tests.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;

typedef _FnNative = Void Function(Pointer<Uint8>);
typedef _FnDart = void Function(Pointer<Uint8>);

/// Signature of the code emitted by [runUjit]: `dst` and the three inputs
/// `a`, `b` and `c` are 128-bit vectors; `mem` addresses the 16 bytes of `c`
/// (16-byte aligned) and may be used as a memory operand or as scratch.
typedef UjitEmit = void Function(
    UniCompiler cc, BaseReg d, BaseReg a, BaseReg b, BaseReg c, BaseMem mem);

/// JIT-compiles [emit] for the host architecture, runs it with the inputs
/// [a], [b] and [c] (16 bytes each) and returns the 16 bytes of `dst`.
Uint8List runUjit(UjitEmit emit, Uint8List a, Uint8List b, Uint8List c,
    {CpuFeatures? features}) {
  final rt = JitRuntime();
  try {
    final code = CodeHolder(env: rt.environment);
    final isA64 = code.env.arch == Arch.aarch64;
    final BaseCompiler archCc = isA64
        ? A64Compiler(env: code.env, labelManager: code.labelManager)
        : X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(archCc, features: features);
    BaseMem mem(BaseReg p, int off) => p is A64Gp
        ? A64Mem.baseOffset(p, off)
        : X86Mem.baseDisp(p as X86Gp, off, size: 16);

    cc.addFunc(
        FuncSignature.build([TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
    final p = cc.newGpPtr('p');
    cc.setArg(0, p);
    final va = cc.newVec('a');
    final vb = cc.newVec('b');
    final vc = cc.newVec('c');
    final vd = cc.newVec('d');
    cc.emitVM(UniOpVM.load128U32, va, mem(p, 0));
    cc.emitVM(UniOpVM.load128U32, vb, mem(p, 16));
    cc.emitVM(UniOpVM.load128U32, vc, mem(p, 32));
    emit(cc, vd, va, vb, vc, mem(p, 32));
    cc.emitMV(UniOpMV.store128U32, mem(p, 48), vd);
    cc.ret();
    cc.endFunc();
    archCc.finalize();
    archCc
        .serializeToAssembler(isA64 ? A64Assembler(code) : X86Assembler(code));

    final fn = rt.add(code);
    // 16-byte aligned: legacy SSE memory operands require it.
    final raw = pkgffi.calloc<Uint8>(64 + 16);
    try {
      final buf = Pointer<Uint8>.fromAddress((raw.address + 15) & ~15);
      buf.asTypedList(64)
        ..setAll(0, a)
        ..setAll(16, b)
        ..setAll(32, c);
      fn.pointer.cast<NativeFunction<_FnNative>>().asFunction<_FnDart>()(buf);
      return Uint8List.fromList(buf.asTypedList(64).sublist(48, 64));
    } finally {
      pkgffi.calloc.free(raw);
    }
  } finally {
    rt.dispose();
  }
}
