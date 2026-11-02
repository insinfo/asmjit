// Section, embedded label and alignment nodes through the compiler and the
// serializers (`BaseBuilder::section()`, `embed_label()`, `align()`).
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';

const _dataArray = [2, 9, 4, 7, 1, 3, 8, 5, 6, 0];

typedef _NativeIdx = Int64 Function(Int64);
typedef _DartIdx = int Function(int);

void main() {
  group('X86Compiler', () {
    late JitRuntime runtime;
    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    test('data section lookup and embedded label addresses', () {
      final code = CodeHolder(env: Environment.host());
      final data = code.newSection('.data', SectionFlags.none, alignment: 8);
      final cc = X86Compiler(env: code.env, labelManager: code.labelManager);
      final isWindows = cc.env.platform == TargetPlatform.windows;

      final bytes = cc.newLabel();
      final table = cc.newLabel();
      final cases = [cc.newLabel(), cc.newLabel()];

      cc.addFunc(FuncSignature(retType: TypeId.int64, args: [TypeId.int64]));
      final idx = cc.newGp64('idx');
      final addr = cc.newGp64('addr');
      cc
        ..mov(idx, isWindows ? rcx : rdi)
        ..lea(addr, X86RipMem.label(bytes))
        ..movzx(rax, X86Mem(base: addr, index: idx, size: 1))
        ..ret()
        ..endFunc();

      // Two labels in the code whose addresses go to .data (a jump table
      // through the compiler also needs upstream's JumpAnnotation, which
      // the port does not have yet).
      cc.addFunc(FuncSignature(retType: TypeId.int64, args: []));
      for (final (i, c) in cases.indexed) {
        cc
          ..bind(c)
          ..mov(eax, Imm(100 + i))
          ..ret();
      }
      cc.endFunc();

      cc
        ..section(data)
        ..bind(bytes)
        ..embedData(_dataArray)
        ..align(AlignMode.data, 8)
        ..bind(table)
        ..embedLabel(cases[0])
        ..embedLabel(cases[1])
        ..embedLabelDelta(cases[1], cases[0], 4);

      cc.finalize();
      final a = X86Assembler(code);
      cc.serializeToAssembler(a);

      // .data: the bytes, 0xCC padding up to 16, two addresses and a delta.
      expect(data.buffer.bytes.sublist(10, 16), List.filled(6, 0xCC));
      expect(data.buffer.length, 16 + 8 + 8 + 4);

      final fn = runtime.add(code);
      final base = fn.pointer.address;
      final lookup =
          fn.pointer.cast<NativeFunction<_NativeIdx>>().asFunction<_DartIdx>();
      for (final i in [0, 3, 9]) {
        expect(lookup(i), _dataArray[i]);
      }
      // The table holds the absolute addresses of the cases, then the delta.
      final tableAt = data.offset + 16;
      final words = (fn.pointer.cast<Uint8>() + tableAt).cast<Int64>();
      final c0 = words.value, c1 = (words + 1).value;
      expect(c0 - base, code.getLabelOffset(cases[0]));
      expect(c1 - base, code.getLabelOffset(cases[1]));
      expect((words + 2).cast<Int32>().value, c1 - c0);
    }, skip: skipUnlessX64Host);
  });

  test('align() pads code and data as upstream', () {
    final x = X86Assembler(CodeHolder(env: Environment.x64SysV()));
    x
      ..emit(X86InstId.kRet, [])
      ..align(AlignMode.code, 4)
      ..align(AlignMode.data, 8)
      ..embedUInt8(1)
      ..align(AlignMode.zero, 4);
    expect(x.buffer.bytes,
        [0xC3, 0x90, 0x90, 0x90, 0xCC, 0xCC, 0xCC, 0xCC, 1, 0, 0, 0]);

    final xo = X86Assembler(CodeHolder(env: Environment.x64SysV()))
      ..encodingOptions = EncodingOptions.kOptimizedAlign;
    xo
      ..emit(X86InstId.kRet, [])
      ..align(AlignMode.code, 8);
    expect(xo.buffer.bytes, [0xC3, 0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00]);

    final a = A64Assembler(CodeHolder(env: Environment.aarch64()));
    a
      ..emit(A64InstId.kRet, [x30])
      ..align(AlignMode.code, 16)
      ..embedUInt8(7)
      ..align(AlignMode.data, 4);
    expect(a.buffer.bytes, [
      0xC0, 0x03, 0x5F, 0xD6, //
      for (var i = 0; i < 3; i++) ...[0x1F, 0x20, 0x03, 0xD5],
      7, 0, 0, 0,
    ]);
    expect(() => a.align(AlignMode.code, 128), throwsA(isA<AsmJitException>()));
  });
}
