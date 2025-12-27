/// AsmJit Unit Tests - Inline Bytes
///
/// Tests for InlineBytes and InlineAsm functionality.

import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

// Native function signatures
typedef NativeNoArgs = Int64 Function();
typedef DartNoArgs = int Function();

typedef NativeOneArg = Int64 Function(Int64);
typedef DartOneArg = int Function(int);

typedef NativeTwoArgs = Int64 Function(Int64, Int64);
typedef DartTwoArgs = int Function(int, int);

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
  group('InlineBytes', () {
    test('creates from list', () {
      final inline = InlineBytes.fromList([0x90, 0x90, 0xC3]);
      expect(inline.length, equals(3));
      expect(inline.bytes, equals([0x90, 0x90, 0xC3]));
    });

    test('toString shows hex bytes', () {
      final inline = InlineBytes.fromList([0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3]);
      expect(inline.toString(), contains('b8 2a 00 00 00 c3'));
    });

    test('hasPatches returns false when no patches', () {
      final inline = InlineBytes.fromList([0xC3]);
      expect(inline.hasPatches, isFalse);
    });

    test('hasPatches returns true with patches', () {
      final inline = InlineBytes.fromList(
        [0xB8, 0x00, 0x00, 0x00, 0x00, 0xC3],
        patches: [
          InlinePatch(kind: InlinePatchKind.imm32, atOffset: 1, value: 42),
        ],
      );
      expect(inline.hasPatches, isTrue);
    });

    test('applyPatches applies imm32', () {
      final inline = InlineBytes.fromList(
        [0xB8, 0x00, 0x00, 0x00, 0x00, 0xC3],
        patches: [
          InlinePatch(kind: InlinePatchKind.imm32, atOffset: 1, value: 42),
        ],
      );
      final patched = inline.applyPatches();
      expect(patched, equals([0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3]));
    });

    test('applyPatches applies imm64', () {
      final inline = InlineBytes.fromList(
        [0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC3],
        patches: [
          InlinePatch(
            kind: InlinePatchKind.imm64,
            atOffset: 2,
            value: 0x123456789ABCDEF0,
          ),
        ],
      );
      final patched = inline.applyPatches();
      expect(
        patched,
        equals([
          0x48, 0xB8,
          0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12, // imm64 LE
          0xC3
        ]),
      );
    });

    test('append combines two InlineBytes', () {
      final a = InlineBytes.fromList([0x90, 0x90]);
      final b = InlineBytes.fromList([0xC3]);
      final combined = a.append(b);
      expect(combined.bytes, equals([0x90, 0x90, 0xC3]));
    });
  });

  group('InlinePatch', () {
    test('imm8 has size 1', () {
      final patch = InlinePatch(kind: InlinePatchKind.imm8, atOffset: 0);
      expect(patch.size, equals(1));
    });

    test('imm32 has size 4', () {
      final patch = InlinePatch(kind: InlinePatchKind.imm32, atOffset: 0);
      expect(patch.size, equals(4));
    });

    test('imm64 has size 8', () {
      final patch = InlinePatch(kind: InlinePatchKind.imm64, atOffset: 0);
      expect(patch.size, equals(8));
    });

    test('rel32 has size 4', () {
      final patch = InlinePatch(kind: InlinePatchKind.rel32, atOffset: 0);
      expect(patch.size, equals(4));
    });
  });

  group('InlineTemplate', () {
    test('instantiate applies values', () {
      // Template: mov eax, <imm32>; ret
      final template = InlineTemplate.fromList(
        [0xB8, 0x00, 0x00, 0x00, 0x00, 0xC3],
        [
          InlineTemplatePatch(
            name: 'value',
            kind: InlinePatchKind.imm32,
            atOffset: 1,
          ),
        ],
      );

      final inline = template.instantiate({'value': 99});
      final patched = inline.applyPatches();
      expect(patched, equals([0xB8, 0x63, 0x00, 0x00, 0x00, 0xC3]));
    });

    test('returnImm32 template works', () {
      final inline = X86Templates.returnImm32.instantiate({'value': 42});
      final patched = inline.applyPatches();
      expect(patched, equals([0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3]));
    });
  });

  group('X86Templates', () {
    test('nopSled creates correct size', () {
      final sled = X86Templates.nopSled(5);
      expect(sled.length, equals(5));
      expect(sled.bytes, equals([0x90, 0x90, 0x90, 0x90, 0x90]));
    });

    test('breakpoint is int3', () {
      expect(X86Templates.breakpoint.bytes, equals([0xCC]));
    });

    test('infiniteLoop is jmp \u0024-2', () {
      expect(X86Templates.infiniteLoop.bytes, equals([0xEB, 0xFE]));
    });
  });

  group('InlineAsm', () {
    late JitRuntime runtime;
    late InlineAsm asm;

    setUp(() {
      runtime = JitRuntime();
      asm = InlineAsm(runtime);
    });

    tearDown(() {
      runtime.dispose();
    });

    test('buildBytes executes correctly', () {
      // mov eax, 42; ret
      final fn = asm.buildBytes([0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3]);
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(42));

      fn.dispose();
    });

    test('buildInlineBytes with patches works', () {
      final inline = InlineBytes.fromList(
        [0xB8, 0x00, 0x00, 0x00, 0x00, 0xC3],
        patches: [
          InlinePatch(kind: InlinePatchKind.imm32, atOffset: 1, value: 123),
        ],
      );

      final fn = asm.buildInlineBytes(inline);
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(123));

      fn.dispose();
    });

    test('buildTemplate works', () {
      final fn = asm.buildTemplate(X86Templates.returnImm32, {'value': 999});
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(999));

      fn.dispose();
    });

    test('buildX86 works', () {
      final fn = asm.buildX86((a, code) {
        a.movRI64(rax, 777);
        a.ret();
      });
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(777));

      fn.dispose();
    });

    test('buildHybrid combines prologue and inline', () {
      final fn = asm.buildHybrid(
        prologue: (a) {
          a.nop(); // Just to test prologue is called
        },
        inlineBytes: [0xB8, 0x55, 0x00, 0x00, 0x00], // mov eax, 85
        epilogue: (a) {
          a.ret();
        },
      );
      final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
      final call = ptr.asFunction<DartNoArgs>();

      expect(call(), equals(85));

      fn.dispose();
    });

    test('pre-built add template for current platform', () {
      final inline =
          Platform.isWindows ? X86Templates.addWin64 : X86Templates.addSysV;

      final fn = asm.buildInlineBytes(inline);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final add = ptr.asFunction<DartTwoArgs>();

      expect(add(10, 20), equals(30));
      expect(add(100, 200), equals(300));

      fn.dispose();
    });

    test('pre-built mul template for current platform', () {
      final inline =
          Platform.isWindows ? X86Templates.mulWin64 : X86Templates.mulSysV;

      final fn = asm.buildInlineBytes(inline);
      final ptr = fn.pointer.cast<NativeFunction<NativeTwoArgs>>();
      final mul = ptr.asFunction<DartTwoArgs>();

      expect(mul(6, 7), equals(42));
      expect(mul(10, 10), equals(100));

      fn.dispose();
    });
  });
}
