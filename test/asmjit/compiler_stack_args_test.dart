// Function arguments passed on the stack (beyond the ABI argument
// registers: 6 on SysV, 4 on Win64, 8 on AArch64; Apple packs them by their
// natural size) are loaded from the caller's argument area.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';

typedef _I64x12Native = Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64,
    Int64, Int64, Int64, Int64, Int64, Int64);
typedef _I64x12Dart = int Function(
    int, int, int, int, int, int, int, int, int, int, int, int);
typedef _MixedNative = Int32 Function(Int64, Int64, Int64, Int64, Int64, Int64,
    Int64, Int64, Int8, Int16, Int32, Uint8, Uint16);
typedef _MixedDart = int Function(
    int, int, int, int, int, int, int, int, int, int, int, int, int);

void main() {
  late JitRuntime rt;
  setUp(() => rt = JitRuntime());
  tearDown(() => rt.dispose());

  Pointer<Void> compile(
      List<TypeId> args, TypeId ret, void Function(UniCompiler cc) body) {
    final code = CodeHolder(env: rt.environment);
    final compiler = rt.environment.arch == Arch.aarch64
        ? A64Compiler(env: code.env, labelManager: code.labelManager)
        : X86Compiler(env: code.env, labelManager: code.labelManager);
    final cc = UniCompiler(compiler);
    cc.addFunc(FuncSignature.build(args, ret, CallConvId.cdecl));
    body(cc);
    cc.endFunc();
    cc.finalize();
    compiler.serializeToAssembler(rt.environment.arch == Arch.aarch64
        ? A64Assembler(code)
        : X86Assembler(code));
    return rt.add(code).pointer;
  }

  test('12 int64 arguments, weighted sum', () {
    final fn = compile(List.filled(12, TypeId.int64), TypeId.int64, (cc) {
      final args = [for (var i = 0; i < 12; i++) cc.newGp64('a$i')];
      for (final (i, a) in args.indexed) {
        cc.setArg(i, a);
      }
      final sum = cc.newGp64('sum');
      cc.emitMov(sum, Imm(0));
      for (final (i, a) in args.indexed) {
        // sum = sum * 2 + a (keeps the argument order observable).
        cc
          ..emit3i(UniOpRRR.add, sum, sum, sum)
          ..emit3i(UniOpRRR.add, sum, sum, a);
        expect(i, lessThan(12));
      }
      cc.ret([sum]);
    });
    final f =
        fn.cast<NativeFunction<_I64x12Native>>().asFunction<_I64x12Dart>();
    var expected = 0;
    for (var i = 1; i <= 12; i++) {
      expected = expected * 2 + i;
    }
    expect(f(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), expected);
  }, skip: skipUnlessJitHost);

  test('small and mixed-size arguments on the stack', () {
    const types = [
      ...[
        TypeId.int64, TypeId.int64, TypeId.int64, TypeId.int64, //
        TypeId.int64, TypeId.int64, TypeId.int64, TypeId.int64,
      ],
      TypeId.int8,
      TypeId.int16,
      TypeId.int32,
      TypeId.uint8,
      TypeId.uint16,
    ];
    final fn = compile(types, TypeId.int32, (cc) {
      for (var i = 0; i < 8; i++) {
        cc.setArg(i, cc.newGp64('filler$i'));
      }
      final small = [for (var i = 8; i < types.length; i++) cc.newGp32('s$i')];
      for (final (i, s) in small.indexed) {
        cc.setArg(8 + i, s);
      }
      final sum = cc.newGp32('sum');
      cc.emitMov(sum, Imm(0));
      for (final s in small) {
        cc.emit3i(UniOpRRR.add, sum, sum, s);
      }
      cc.ret([sum]);
    });
    final f = fn.cast<NativeFunction<_MixedNative>>().asFunction<_MixedDart>();
    expect(f(0, 0, 0, 0, 0, 0, 0, 0, -5, -300, 100000, 250, 60000),
        -5 - 300 + 100000 + 250 + 60000);
  }, skip: skipUnlessJitHost);
}
