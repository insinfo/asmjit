// Several functions in one compiler (`FuncPass::run()` allocates each
// function on its own): every function gets its own prolog/epilog and the
// control flow never falls through from one function into the next.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';

typedef _BinNative = Int64 Function(Int64, Int64);
typedef _BinDart = int Function(int, int);

void main() {
  late JitRuntime rt;
  setUp(() => rt = JitRuntime());
  tearDown(() => rt.dispose());

  test('three functions in one compiler', () {
    final code = CodeHolder(env: rt.environment);
    final compiler = rt.environment.arch == Arch.aarch64
        ? A64Compiler(env: code.env, labelManager: code.labelManager)
        : X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(compiler);
    final sig = FuncSignature.build(
        [TypeId.int64, TypeId.int64], TypeId.int64, CallConvId.cdecl);

    final funcs = <FuncNode>[];
    // f0 = a * b + a, f1 = a + b + 100 (with a branch), f2 = a - b.
    for (var f = 0; f < 3; f++) {
      funcs.add(cc.addFunc(sig));
      final a = cc.newGp64('a$f');
      final b = cc.newGp64('b$f');
      cc
        ..setArg(0, a)
        ..setArg(1, b);
      final t = cc.newGp64('t$f');
      switch (f) {
        case 0:
          cc
            ..emit3i(UniOpRRR.mul, t, a, b)
            ..emit3i(UniOpRRR.add, t, t, a);
        case 1:
          final skip = cc.newLabel();
          cc
            ..emit3i(UniOpRRR.add, t, a, b)
            ..emitJIf(skip, UniCondition.cmp_eq(a, b))
            ..emit3i(UniOpRRR.add, t, t, Imm(100))
            ..bind(skip);
        case 2:
          cc.emit3i(UniOpRRR.sub, t, a, b);
      }
      cc
        ..ret([t])
        ..endFunc();
    }
    cc.finalize();
    compiler.serializeToAssembler(rt.environment.arch == Arch.aarch64
        ? A64Assembler(code)
        : X86Assembler(code));

    final fn = rt.add(code);
    _BinDart at(FuncNode func) =>
        (fn.pointer.cast<Uint8>() + code.getLabelOffset(func.label)!)
            .cast<NativeFunction<_BinNative>>()
            .asFunction<_BinDart>();
    expect(code.getLabelOffset(funcs[0].label), 0);
    expect(at(funcs[0])(6, 7), 48);
    expect(at(funcs[1])(6, 7), 113);
    expect(at(funcs[1])(5, 5), 10);
    expect(at(funcs[2])(6, 7), -1);
  }, skip: skipUnlessJitHost);
}
