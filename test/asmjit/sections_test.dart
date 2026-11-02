// Sections, cross-section fixups and embedded labels (`BaseAssembler::
// section()`, `embed*()`, `CodeHolder::resolve_cross_section_fixups()`).
//
// The expected images were produced by upstream asmjit (flatten(),
// resolve_cross_section_fixups(), relocate_to_base(), copy_flattened_data())
// built with the `embed_label()` label check fixed (see
// BaseAssembler.embedLabel). The JIT tests follow
// asmjit-testing/tests/asmjit_test_x86_sections.cpp.
import 'dart:ffi';
import 'dart:io';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';

const _x64Base = 0x7FF612340000;
const _dataArray = [2, 9, 4, 7, 1, 3, 8, 5, 6, 0];

typedef _NativeIdx = Int64 Function(Int64);
typedef _DartIdx = int Function(int);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String _image(CodeHolder code, int base) {
  code.resolveLabelFixups();
  code.relocateToBase(base);
  return _hex(code.finalize().textBytes);
}

_DartIdx _fn(JitFunction f) =>
    f.pointer.cast<NativeFunction<_NativeIdx>>().asFunction<_DartIdx>();

void main() {
  group('x64 sections', () {
    test('asmjit_test_x86_sections: lea of a label in .data', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final data = code.newSection('.data', SectionFlags.none, alignment: 8);
      final a = X86Assembler(code);
      final l = a.newLabel();
      a
        ..emit(X86InstId.kMov, [rax, rdi])
        ..emit(X86InstId.kLea, [rcx, X86RipMem.label(l)])
        ..emit(X86InstId.kMovzx, [rax, X86Mem(base: rcx, index: rax, size: 1)])
        ..emit(X86InstId.kRet, [])
        ..section(data)
        ..bind(l)
        ..embed(_dataArray);
      expect(code.unresolvedFixupCount, 1);
      expect(_image(code, _x64Base),
          '4889F8488D0D06000000480FB60401C302090407010308050600');
      expect(code.unresolvedFixupCount, 0);
    });

    test('label bound in .data before the reference', () {
      // Upstream corrupts the label here (see CodeHolder.newFixup); the
      // displacements are .data+4 (offset 20) minus the end of each
      // instruction: 20 - 6 and 20 - 11.
      final code = CodeHolder(env: Environment.x64SysV());
      final data = code.newSection('.data', SectionFlags.none, alignment: 8);
      final a = X86Assembler(code);
      final l = a.newLabel();
      a
        ..section(data)
        ..embedUInt32(0x11223344)
        ..bind(l)
        ..embedUInt32(0x55667788)
        ..section(code.text)
        ..emit(X86InstId.kMov, [eax, X86RipMem.label(l, size: 4)])
        ..emit(X86InstId.kJmp, [l])
        ..emit(X86InstId.kRet, []);
      expect(code.getLabelOffset(l), 4);
      expect(_image(code, _x64Base),
          '8B050E000000E909000000C3000000004433221188776655');
    });

    test('embedLabel / embedLabelDelta', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final a = X86Assembler(code);
      final l = a.newLabel(), u = a.newLabel();
      a
        ..bind(l)
        ..emit(X86InstId.kNop, [])
        ..embedLabel(l)
        ..embedLabel(u, 4)
        ..embedLabelDelta(u, l, 4)
        ..embedLabelDelta(l, l, 2)
        ..bind(u)
        ..emit(X86InstId.kRet, []);
      expect(_image(code, 0x10000), '90000001000000000013000100130000000000C3');
    });

    test('embedLabel rejects an invalid label', () {
      final a = X86Assembler(CodeHolder(env: Environment.x64SysV()));
      expect(
          () => a.embedLabel(Label.invalid),
          throwsA(isA<AsmJitException>()
              .having((e) => e.code, 'code', AsmJitError.invalidLabel)));
    });

    test('jump table in .rodata', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final rodata =
          code.newSection('.rodata', SectionFlags.none, alignment: 8);
      final a = X86Assembler(code);
      final table = a.newLabel(), c0 = a.newLabel(), c1 = a.newLabel();
      a
        ..emit(X86InstId.kLea, [rcx, X86RipMem.label(table)])
        ..emit(
            X86InstId.kJmp, [X86Mem(base: rcx, index: rdi, scale: 8, size: 8)])
        ..bind(c0)
        ..emit(X86InstId.kMov, [eax, 10])
        ..emit(X86InstId.kRet, [])
        ..bind(c1)
        ..emit(X86InstId.kMov, [eax, 20])
        ..emit(X86InstId.kRet, [])
        ..section(rodata)
        ..bind(table)
        ..embedLabel(c0)
        ..embedLabel(c1);
      expect(
          _image(code, _x64Base),
          '488D0D11000000FF24F9B80A000000C3B814000000C300000A003412F67F0000'
          '10003412F67F0000');
    });
  });

  test('AArch64 adr of a label in .data and embedLabel', () {
    final code = CodeHolder(env: Environment.aarch64());
    final data = code.newSection('.data', SectionFlags.none, alignment: 8);
    final a = A64Assembler(code);
    final l = a.newLabel();
    a
      ..emit(A64InstId.kAdr, [x1, l])
      ..emit(A64InstId.kLdrb, [w0, A64Mem.baseIndex(x1, x0)])
      ..emit(A64InstId.kRet, [x30])
      ..section(data)
      ..bind(l)
      ..embed(_dataArray)
      ..embedLabel(l);
    expect(_image(code, 0x100004000),
        '8100001020686038C0035FD600000000020904070103080506001040000001000000');
  });

  group('JIT', () {
    late JitRuntime runtime;
    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    final arg = Platform.isWindows ? rcx : rdi;

    test('x64: data section lookup (asmjit_test_x86_sections)', () {
      final code = CodeHolder();
      final data = code.newSection('.data', SectionFlags.none, alignment: 8);
      final a = X86Assembler(code);
      final l = a.newLabel();
      a
        ..emit(X86InstId.kMov, [rax, arg])
        ..emit(X86InstId.kLea, [rcx, X86RipMem.label(l)])
        ..emit(X86InstId.kMovzx, [rax, X86Mem(base: rcx, index: rax, size: 1)])
        ..emit(X86InstId.kRet, [])
        ..section(data)
        ..bind(l)
        ..embed(_dataArray);
      final fn = _fn(runtime.add(code));
      for (final i in [0, 3, 6, 9]) {
        expect(fn(i), _dataArray[i]);
      }
    }, skip: skipUnlessX64Host);

    test('x64: jump table of embedded label addresses', () {
      final code = CodeHolder();
      final rodata =
          code.newSection('.rodata', SectionFlags.none, alignment: 8);
      final a = X86Assembler(code);
      final table = a.newLabel();
      final cases = [for (var i = 0; i < 3; i++) a.newLabel()];
      a
        ..emit(X86InstId.kLea, [rdx, X86RipMem.label(table)])
        ..emit(
            X86InstId.kJmp, [X86Mem(base: rdx, index: arg, scale: 8, size: 8)]);
      for (final (i, c) in cases.indexed) {
        a
          ..bind(c)
          ..emit(X86InstId.kMov, [eax, 100 + i])
          ..emit(X86InstId.kRet, []);
      }
      a
        ..section(rodata)
        ..bind(table);
      for (final c in cases) {
        a.embedLabel(c);
      }
      final fn = _fn(runtime.add(code));
      expect([fn(0), fn(1), fn(2)], [100, 101, 102]);
    }, skip: skipUnlessX64Host);

    test('AArch64: data section lookup', () {
      final code = CodeHolder();
      final data = code.newSection('.data', SectionFlags.none, alignment: 8);
      final a = A64Assembler(code);
      final l = a.newLabel();
      a
        ..emit(A64InstId.kAdr, [x1, l])
        ..emit(A64InstId.kLdrb, [w0, A64Mem.baseIndex(x1, x0)])
        ..emit(A64InstId.kRet, [x30])
        ..section(data)
        ..bind(l)
        ..embed(_dataArray);
      final fn = _fn(runtime.add(code));
      for (final i in [0, 3, 6, 9]) {
        expect(fn(i), _dataArray[i]);
      }
    }, skip: skipUnlessA64Host);
  });
}
