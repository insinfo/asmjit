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
      calleeCode,
      ctRef: const VecConstTableRef(null, VecConstTable.kSize),
    );
    calleeCc.initVecWidth(VecWidth.k128);
    calleeCc.addFunc(FuncSignature.build([], TypeId.void_, CallConvId.x64Windows));
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

    // Caller: recebe outBefore, outAfter, canaryPtr.
    final callerCode = CodeHolder(env: rt.environment);
    final caller = X86Compiler(env: callerCode.env, labelManager: callerCode.labelManager);
    caller.addFunc(FuncSignature.build(
        [TypeId.intPtr, TypeId.intPtr, TypeId.intPtr],
        TypeId.void_,
        CallConvId.x64Windows));

    final outBefore = caller.newGpPtr('outBefore');
    final outAfter = caller.newGpPtr('outAfter');
    final canaryPtr = caller.newGpPtr('canaryPtr');
    caller.setArg(0, outBefore);
    caller.setArg(1, outAfter);
    caller.setArg(2, canaryPtr);

    final tmpPtr = caller.newGpPtr('tmpPtr');
    caller.addNode(InstNode(X86InstId.kMov, [tmpPtr, canaryPtr]));

    // Carrega canários em XMM6..XMM15 e grava outBefore.
    for (int i = 0; i < 10; i++) {
      final reg = X86Xmm(6 + i);
      caller.addNode(InstNode(
          X86InstId.kMovdqu, [reg, X86Mem.baseDisp(tmpPtr, i * 16, size: 16)]));
      caller.addNode(InstNode(
          X86InstId.kMovdqu, [X86Mem.baseDisp(outBefore, i * 16, size: 16), reg]));
    }

    // shadow space Win64
    caller.addNode(
        InstNode(X86InstId.kSub, [X86Gp.r64(X86RegId.rsp.index), Imm(32)]));
    final callReg = caller.newGpPtr('callReg');
    caller.addNode(InstNode(X86InstId.kMov, [callReg, Imm(calleeFn.address)]));
    caller.addNode(InstNode(X86InstId.kCall, [callReg]));
    caller.addNode(
        InstNode(X86InstId.kAdd, [X86Gp.r64(X86RegId.rsp.index), Imm(32)]));

    // Após retorno, grava XMM6..XMM15 em outAfter.
    for (int i = 0; i < 10; i++) {
      final reg = X86Xmm(6 + i);
      caller.addNode(InstNode(
          X86InstId.kMovdqu, [X86Mem.baseDisp(outAfter, i * 16, size: 16), reg]));
    }

    caller.ret();
    caller.endFunc();
    caller.finalize();
    final callerAsm = X86Assembler(callerCode);
    caller.serializeToAssembler(callerAsm);
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
