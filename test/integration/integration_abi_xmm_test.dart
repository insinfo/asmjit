// Verifica que no Windows x64 o JIT preserva XMM6..XMM15 (callee-saved).
import 'dart:ffi' as ffi;

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:test/test.dart';

void main() {
  test('ABI Win64 preserva XMM6..XMM15', () {
    final abi = ffi.Abi.current();
    if (!abi.toString().toLowerCase().contains('windows')) {
      return;
    }

    final rt = JitRuntime();

    // Callee que clobbera vetores.
    final calleeCode = CodeHolder(env: rt.environment);
    final calleeCc = UniCompiler.auto(
      code: calleeCode,
      ctRef: const VecConstTableRef(null, VecConstTable.kSize),
    );
    calleeCc.initVecWidth(VecWidth.k128);
    calleeCc
        .addFunc(FuncSignature.build([], TypeId.void_, CallConvId.x64Windows));
    final cVecs = List<BaseReg>.generate(
        12, (i) => calleeCc.newVecWithWidth(VecWidth.k128, 'c$i'));
    final cTmp = calleeCc.newVecWithWidth(VecWidth.k128, 'ctmp');
    for (int i = 0; i < cVecs.length - 1; i++) {
      calleeCc.emit3v(UniOpVVV.xorU32, cVecs[i], cVecs[i], cVecs[i + 1]);
      calleeCc.emit3v(UniOpVVV.addU32, cVecs[i + 1], cVecs[i + 1], cVecs[i]);
    }
    calleeCc.emit2v(UniOpVV.mov, cTmp, cVecs.last);
    calleeCc.emit3v(UniOpVVV.xorU32, cVecs.first, cVecs.first, cTmp);
    calleeCc.ret();
    calleeCc.endFunc();
    calleeCc.cc.finalize();
    final calleeAsm = X86Assembler(calleeCode);
    calleeCc.cc.serializeToAssembler(calleeAsm);
    final calleeFn = rt.add(calleeCode);

    // Caller em assembler puro para controlar alinhamento/stack shadow.
    final callerCode = CodeHolder(env: rt.environment);
    final a = X86Assembler(callerCode);

    // Prologue: push rbp; mov rbp, rsp; sub rsp, 32 (Win64 shadow, keeps rsp 8 mod 16 before call).
    a.emit(X86InstId.kPush, [rbp]);
    a.emit(X86InstId.kMov, [rbp, rsp]);
    a.emit(X86InstId.kSub, [rsp, Imm(32)]);

    // Args (Win64): rcx=outBefore, rdx=outAfter, r8=canaryPtr
    final outBefore = rcx;
    final outAfter = rdx;
    final canaryPtr = r8;

    // Carrega canários em XMM6..XMM15 e grava outBefore.
    for (int i = 0; i < 10; i++) {
      final reg = X86Xmm(6 + i);
      a.emit(X86InstId.kMovdqu,
          [reg, X86Mem.baseDisp(canaryPtr, i * 16, size: 16)]);
      a.emit(X86InstId.kMovdqu,
          [X86Mem.baseDisp(outBefore, i * 16, size: 16), reg]);
    }

    // Call callee (shadow space já reservado)
    a.emit(X86InstId.kMov, [rax, Imm(calleeFn.address)]);
    a.emit(X86InstId.kCall, [rax]);

    // Após retorno, grava XMM6..XMM15 em outAfter.
    for (int i = 0; i < 10; i++) {
      final reg = X86Xmm(6 + i);
      a.emit(X86InstId.kMovdqu,
          [X86Mem.baseDisp(outAfter, i * 16, size: 16), reg]);
    }

    // Epilogue
    a.emit(X86InstId.kAdd, [rsp, Imm(32)]);
    a.emit(X86InstId.kPop, [rbp]);
    a.emit(X86InstId.kRet, []);

    final callerFn = rt.add(callerCode);

    final callerPtr = ffi.Pointer<
      ffi.NativeFunction<
        ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
          ffi.Pointer<ffi.Uint8>)>>.fromAddress(callerFn.address);
    final callerFnDart = callerPtr.asFunction<
      void Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
        ffi.Pointer<ffi.Uint8>)>();

    final outBeforeBuf = pkgffi.calloc<ffi.Uint8>(160);
    final outAfterBuf = pkgffi.calloc<ffi.Uint8>(160);
    final canaryBuf = pkgffi.calloc<ffi.Uint8>(160);
    for (int i = 0; i < 160; i++) {
      canaryBuf[i] = (i % 251);
    }

    try {
      callerFnDart(outBeforeBuf, outAfterBuf, canaryBuf);
      final expected = canaryBuf.asTypedList(160);
      expect(outBeforeBuf.asTypedList(160), expected);
      expect(outAfterBuf.asTypedList(160), expected);
    } finally {
      pkgffi.calloc.free(outBeforeBuf);
      pkgffi.calloc.free(outAfterBuf);
      pkgffi.calloc.free(canaryBuf);
    }
  });
}
