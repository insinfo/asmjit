// Vector constants loaded from the function-local constant table.
//
// Regression: the table was never embedded (or the RIP/ADR displacement was
// never relocated), so constants were read from the instruction stream.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:test/test.dart';

import '../support/host.dart';

Uint8List _materialize(List<VecConst> consts) {
  final rt = JitRuntime();
  try {
    final code = CodeHolder(env: rt.environment);
    final isA64 = code.env.arch == Arch.aarch64;
    final BaseCompiler archCc = isA64
        ? A64Compiler(env: code.env, labelManager: code.labelManager)
        : X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(archCc);
    cc.addFunc(
        FuncSignature.build([TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
    final p = cc.newGpPtr('p');
    cc.setArg(0, p);
    for (int i = 0; i < consts.length; i++) {
      final k = cc.simdConst(consts[i], Bcst.kNA_Unique, VecWidth.k128);
      final v = cc.newVec('v$i');
      cc.emit2v(UniOpVV.mov, v, k);
      final mem = p is A64Gp
          ? A64Mem.baseOffset(p, i * 16)
          : X86Mem.baseDisp(p as X86Gp, i * 16);
      cc.emitMV(UniOpMV.store128U32, mem, v);
    }
    cc.ret();
    cc.endFunc();
    archCc.finalize();
    archCc
        .serializeToAssembler(isA64 ? A64Assembler(code) : X86Assembler(code));
    final fn = rt.add(code);
    final buf = pkgffi.calloc<Uint8>(16 * consts.length);
    try {
      fn.pointer
          .cast<NativeFunction<Void Function(Pointer<Uint8>)>>()
          .asFunction<void Function(Pointer<Uint8>)>()(buf);
      return Uint8List.fromList(buf.asTypedList(16 * consts.length));
    } finally {
      pkgffi.calloc.free(buf);
    }
  } finally {
    rt.dispose();
  }
}

void main() {
  test('constants are loaded from the embedded table', () {
    final consts = [
      VecConstTable.p_8000000080000000,
      VecConstTable.p_7FFFFFFF7FFFFFFF,
      VecConstTable.p_FFFFFFFFFFFFFFFF,
      VecConstTable.p_8000000000000000,
    ];
    final out = _materialize(consts);
    for (int i = 0; i < consts.length; i++) {
      expect(out.sublist(i * 16, i * 16 + 16), consts[i].data.sublist(0, 16),
          reason: 'constant #$i');
    }
  }, skip: skipUnlessJitHost);
}
