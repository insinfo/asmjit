// Jump tables through the compiler: ports of X86Test_JumpTable1..4
// (asmjit-testing/tests/asmjit_test_compiler_x86.cpp). A jump through a
// register is annotated with its targets (`JumpAnnotation`) or, without an
// annotation, may reach any block of the function.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';

typedef _FloatOpNative = Float Function(Float, Float, Uint32);
typedef _FloatOpDart = double Function(double, double, int);
typedef _IntNative = Int32 Function(Int32);
typedef _IntDart = int Function(int);
typedef _VoidIntNative = Int32 Function();
typedef _VoidIntDart = int Function();

void main() {
  late JitRuntime rt;
  setUp(() => rt = JitRuntime());
  tearDown(() => rt.dispose());

  Pointer<Void> compile(void Function(X86Compiler cc) body) {
    final code = CodeHolder(env: rt.environment);
    final cc = X86Compiler(env: code.env, labelManager: code.labelManager);
    body(cc);
    cc.finalize();
    cc.serializeToAssembler(X86Assembler(code));
    return rt.add(code).pointer;
  }

  for (final annotated in [false, true]) {
    test('JumpTable1 {${annotated ? 'Annotated' : 'Unknown Reg/Mem'}}', () {
      final fn = compile((cc) {
        final a = cc.newXmmF32x1('a');
        final b = cc.newXmmF32x1('b');
        final op = cc.newGp32('op');
        final target = cc.newGpPtr('target');
        final offset = cc.newGpPtr('offset');

        final lTable = cc.newLabel();
        final lAdd = cc.newLabel();
        final lSub = cc.newLabel();
        final lMul = cc.newLabel();
        final lDiv = cc.newLabel();
        final lEnd = cc.newLabel();

        cc.addFunc(FuncSignature.build(
            [TypeId.float32, TypeId.float32, TypeId.uint32],
            TypeId.float32,
            CallConvId.cdecl));
        cc
          ..setArg(0, a)
          ..setArg(1, b)
          ..setArg(2, op)
          ..lea(offset, X86RipMem.label(lTable))
          ..movsxd(
              target, X86Mem(base: offset, index: op.as64, scale: 4, size: 4))
          ..add(target, offset);

        if (annotated) {
          final annotation = cc.newJumpAnnotation()
            ..addLabel(lAdd)
            ..addLabel(lSub)
            ..addLabel(lMul)
            ..addLabel(lDiv);
          cc.jmpIndirect(target, annotation);
        } else {
          cc.jmpIndirect(target);
        }

        for (final (l, id) in [
          (lAdd, X86InstId.kAddss),
          (lSub, X86InstId.kSubss),
          (lMul, X86InstId.kMulss),
          (lDiv, X86InstId.kDivss),
        ]) {
          cc
            ..bind(l)
            ..inst(id, [a, b])
            ..jmp(lEnd);
        }

        cc
          ..bind(lEnd)
          ..ret([a])
          ..endFunc();

        cc.bind(lTable);
        for (final l in [lAdd, lSub, lMul, lDiv]) {
          cc.embedLabelDelta(l, lTable, 4);
        }
      });
      final f =
          fn.cast<NativeFunction<_FloatOpNative>>().asFunction<_FloatOpDart>();
      expect([f(33, 14, 0), f(33, 14, 1), f(10, 6, 2), f(80, 8, 3)],
          [47.0, 19.0, 60.0, 10.0]);
    }, skip: skipUnlessX64Host);
  }

  test('JumpTable2 {Jumping to Begin}', () {
    final fn = compile((cc) {
      final result = cc.newGp32('result');
      final value = cc.newGp32('value');
      final target = cc.newGpPtr('target');
      final offset = cc.newGpPtr('offset');

      final lTable = cc.newLabel();
      final lBegin = cc.newLabel();
      final lCase0 = cc.newLabel();
      final lCase1 = cc.newLabel();
      final lEnd = cc.newLabel();

      cc.addFunc(
          FuncSignature.build([TypeId.int32], TypeId.int32, CallConvId.cdecl));
      cc
        ..setArg(0, value)
        ..bind(lBegin)
        ..lea(offset, X86RipMem.label(lTable))
        ..movsxd(
            target, X86Mem(base: offset, index: value.as64, scale: 4, size: 4))
        ..add(target, offset);

      final annotation = cc.newJumpAnnotation()
        ..addLabel(lCase0)
        ..addLabel(lCase1)
        ..addLabel(lBegin); // Never used, just for the purpose of the test.
      cc
        ..jmpIndirect(target, annotation)
        ..bind(lCase0)
        ..mov(result, Imm(0))
        ..jmp(lEnd)
        ..bind(lCase1)
        ..mov(result, Imm(1))
        ..jmp(lEnd)
        ..bind(lEnd)
        ..ret([result])
        ..endFunc();

      cc
        ..bind(lTable)
        ..embedLabelDelta(lCase0, lTable, 4)
        ..embedLabelDelta(lCase1, lTable, 4);
    });
    final f = fn.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>();
    expect([f(0), f(1)], [0, 1]);
  }, skip: skipUnlessX64Host);

  test('JumpTable3 {Jumping to a single label}', () {
    final fn = compile((cc) {
      cc.addFunc(FuncSignature.build([], TypeId.int32, CallConvId.cdecl));
      final lTarget = cc.newLabel();
      final target = cc.newGpPtr('target');
      final result = cc.newGp32('result');

      final annotation = cc.newJumpAnnotation()..addLabel(lTarget);
      cc
        ..lea(target, X86RipMem.label(lTarget))
        ..jmpIndirect(target, annotation)
        ..bind(lTarget)
        ..mov(result, Imm(1234))
        ..ret([result])
        ..endFunc();
    });
    final f =
        fn.cast<NativeFunction<_VoidIntNative>>().asFunction<_VoidIntDart>();
    expect(f(), 1234);
  }, skip: skipUnlessX64Host);

  test('JumpTable4 {Jumping to a single label and multiple labels}', () {
    final fn = compile((cc) {
      final result = cc.newGp32('result');
      final condition = cc.newGp32('condition');

      cc.addFunc(
          FuncSignature.build([TypeId.int32], TypeId.int32, CallConvId.cdecl));
      cc.setArg(0, condition);

      final lNonZero = cc.newLabel();
      cc
        ..test(condition, condition)
        ..jnz(lNonZero);

      {
        final lTarget = cc.newLabel();
        final annotation = cc.newJumpAnnotation()..addLabel(lTarget);
        final target = cc.newGpPtr('target');
        cc
          ..lea(target, X86RipMem.label(lTarget))
          ..jmpIndirect(target, annotation)
          ..bind(lTarget)
          ..mov(result, Imm(1234))
          ..ret([result]);
      }

      {
        final lTarget1 = cc.newLabel();
        final lTarget2 = cc.newLabel();
        final annotation = cc.newJumpAnnotation()
          ..addLabel(lTarget1)
          ..addLabel(lTarget2);
        cc.bind(lNonZero);
        final target = cc.newGpPtr('target');
        cc
          ..lea(target, X86RipMem.label(lTarget1))
          ..jmpIndirect(target, annotation)
          ..bind(lTarget1)
          ..mov(result, Imm(4321))
          ..ret([result])
          // Never executed.
          ..bind(lTarget2)
          ..mov(result, Imm(0))
          ..ret([result]);
      }

      cc.endFunc();
    });
    final f = fn.cast<NativeFunction<_IntNative>>().asFunction<_IntDart>();
    expect([f(0), f(1)], [1234, 4321]);
  }, skip: skipUnlessX64Host);
}
