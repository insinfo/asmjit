// Relocation of absolute targets emitted without a base address
// (`RelocEntry`, `CodeHolder::relocate_to_base()`). The expected images
// were produced by upstream asmjit: the same instructions assembled with
// `code.init(env)` (no base address), then `flatten()`,
// `relocate_to_base(base)` and `copy_flattened_data()`.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

import '../support/host.dart';

const _x64Base = 0x7FF612340000;
const _a64Base = 0x100004000;

typedef _NativeNoArgs = Int64 Function();
typedef _DartNoArgs = int Function();

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// Relocates [code] to [base] and returns `(image, codeSizeReduction)`.
(String, int) _relocate(CodeHolder code, int base) {
  code.flatten();
  final summary = code.relocateToBase(base);
  final bytes = code.finalize().textBytes;
  expect(bytes.length, code.codeSize);
  return (_hex(bytes), summary.codeSizeReduction);
}

(String, int) _x64(int base, void Function(X86Assembler a) emit) {
  final code = CodeHolder(env: Environment.x64SysV());
  emit(X86Assembler(code));
  return _relocate(code, base);
}

(String, int) _a64(int base, void Function(A64Assembler a) emit) {
  final code = CodeHolder(env: Environment.aarch64());
  emit(A64Assembler(code));
  return _relocate(code, base);
}

void main() {
  group('x64 relocation', () {
    final cases = <String, (int, void Function(X86Assembler), String, int)>{
      'add [abs], imm (AbsToRel)': (
        _x64Base,
        (a) => a.emit(
            X86InstId.kAdd, [X86Mem.abs(_x64Base + 0x2000, size: 4), 0x12345]),
        '8105F61F000045230100',
        0
      ),
      'lea rcx, [abs] (AbsToRel)': (
        _x64Base,
        (a) => a.emit(X86InstId.kLea, [rcx, const X86Mem.abs(_x64Base - 0x80)]),
        '488D0D79FFFFFF',
        0
      ),
      'mov rax, [abs32] (absolute)': (
        _x64Base,
        (a) => a.emit(X86InstId.kMov, [rax, const X86Mem.abs(0x1000)]),
        '488B042500100000',
        0
      ),
      'mov rax, [abs64] (movabs)': (
        _x64Base,
        (a) => a
          ..emit(X86InstId.kNop, [])
          ..emit(X86InstId.kMov, [rax, const X86Mem.abs(_x64Base + 0x1000)]),
        '9048A100103412F67F0000',
        0
      ),
      'call near (address table not needed)': (
        _x64Base,
        (a) => a
          ..emit(X86InstId.kNop, [])
          ..emit(X86InstId.kCall, [_x64Base + 0x5000]),
        '9040E8F94F000000',
        8
      ),
      'jmp near (address table not needed)': (
        _x64Base,
        (a) => a.emit(X86InstId.kJmp, [_x64Base - 0x5000]),
        '40E9FAAFFFFF0000',
        8
      ),
      'jz near': (
        _x64Base,
        (a) => a.emit(X86InstId.kJz, [_x64Base + 0x100]),
        '0F84FA000000',
        0
      ),
      'call/jmp far (address table trampolines)': (
        _x64Base,
        (a) => a
          ..emit(X86InstId.kCall, [0x1122334455])
          ..emit(X86InstId.kJmp, [0x1122334455])
          ..emit(X86InstId.kCall, [0x2122334455])
          ..emit(X86InstId.kRet, []),
        'FF1512000000FF250C000000FF150E000000C3000000000055443322110000005544'
            '332221000000',
        0
      ),
      'call far small base': (
        0x1000,
        (a) => a.emit(X86InstId.kCall, [0x2000]),
        '40E8FA0F00000000',
        8
      ),
      'label fixup and address table': (
        _x64Base,
        (a) {
          final l = a.code.newLabel();
          a
            ..emit(X86InstId.kJmp, [l])
            ..emit(X86InstId.kCall, [0x1122334455]);
          a.code.bind(l);
          a.emit(X86InstId.kRet, []);
        },
        'E906000000FF1505000000C3000000005544332211000000',
        0
      ),
    };
    for (final MapEntry(key: name, value: (base, emit, image, reduction))
        in cases.entries) {
      test(name, () => expect(_x64(base, emit), (image, reduction)));
    }

    test('jz out of 32-bit range cannot be relocated', () {
      final code = CodeHolder(env: Environment.x64SysV());
      X86Assembler(code).emit(X86InstId.kJz, [0x1122334455]);
      code.flatten();
      expect(
          () => code.relocateToBase(_x64Base),
          throwsA(isA<AsmJitException>().having(
              (e) => e.code, 'code', AsmJitError.relocOffsetOutOfRange)));
    });

    test('finalize() refuses code that still needs relocation', () {
      final code = CodeHolder(env: Environment.x64SysV());
      X86Assembler(code).emit(X86InstId.kCall, [0x1122334455]);
      expect(code.needsRelocation, isTrue);
      expect(() => code.finalize(), throwsA(isA<AsmJitException>()));
    });
  });

  group('AArch64 relocation', () {
    final cases = <String, (void Function(A64Assembler), String)>{
      'b': (
        (a) => a
          ..emit(A64InstId.kNop, [])
          ..emit(A64InstId.kB, [_a64Base + 0x1000]),
        '1F2003D5FF030014'
      ),
      'bl backwards': (
        (a) => a.emit(A64InstId.kBl, [_a64Base - 0x100]),
        'C0FFFF97'
      ),
      'b.eq': (
        (a) => a.emit(A64InstId.kB_cond, [_a64Base + 0x40, A64Cond.eq]),
        '00020054'
      ),
      'cbz': ((a) => a.emit(A64InstId.kCbz, [x1, _a64Base + 0x40]), '010200B4'),
      'tbz': (
        (a) => a.emit(A64InstId.kTbz, [x1, 3, _a64Base + 0x40]),
        '01021836'
      ),
      'adr': (
        (a) => a
          ..emit(A64InstId.kNop, [])
          ..emit(A64InstId.kAdr, [x0, _a64Base + 0x123]),
        '1F2003D5E0080070'
      ),
    };
    for (final MapEntry(key: name, value: (emit, image)) in cases.entries) {
      test(name, () => expect(_a64(_a64Base, emit), (image, 0)));
    }

    // Upstream: AbsToRel of ADRP is a plain byte displacement, so a target
    // that is not a multiple of 4096 bytes away is rejected; B beyond
    // +-128MB as well.
    for (final (name, emit) in [
      (
        'adrp to an unaligned distance',
        (A64Assembler a) => a
          ..emit(A64InstId.kNop, [])
          ..emit(A64InstId.kAdrp, [x0, _a64Base + 0x12345678])
      ),
      (
        'b out of range',
        (A64Assembler a) => a.emit(A64InstId.kB, [_a64Base + 0x10000000])
      ),
    ]) {
      test('$name cannot be relocated', () {
        final code = CodeHolder(env: Environment.aarch64());
        emit(A64Assembler(code));
        code.flatten();
        expect(
            () => code.relocateToBase(_a64Base),
            throwsA(isA<AsmJitException>()
                .having((e) => e.code, 'code', AsmJitError.invalidRelocEntry)));
      });
    }
  });

  group('JitRuntime relocates absolute targets', () {
    late JitRuntime runtime;
    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    test('tail call to another JIT function by address', () {
      final targetCode = CodeHolder();
      X86Assembler(targetCode)
        ..emit(X86InstId.kMov, [eax, 42])
        ..emit(X86InstId.kRet, []);
      final target = runtime.add(targetCode);

      // `jmp imm`: AbsToRel when close enough, else an .addrtab trampoline.
      final code = CodeHolder();
      X86Assembler(code).emit(X86InstId.kJmp, [target.pointer.address]);
      expect(code.needsRelocation, isTrue);
      final fn = runtime.add(code);
      expect(
          fn.pointer
              .cast<NativeFunction<_NativeNoArgs>>()
              .asFunction<_DartNoArgs>()(),
          42);
    });
  }, skip: skipUnlessX64Host);
}
