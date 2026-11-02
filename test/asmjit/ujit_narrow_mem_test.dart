/// Regression tests for narrow memory loads/stores emitted by UniCompiler.
///
/// Root cause of the intermittent STATUS_HEAP_CORRUPTION (0xC0000374) crash:
/// `UniOpMR.storeU32` annotated the memory operand with size 4 but kept the
/// 64-bit source register, so the assembler emitted `mov qword ptr [mem], r64`
/// (REX.W) and wrote 8 bytes — 4 bytes past the end of user heap buffers.
/// The same class of bug affected narrow loads (8-byte reads) and
/// `UniOpMR.addU*` (which fell through to MOV instead of ADD).
///
/// These tests execute JIT code against heap buffers surrounded by sentinel
/// bytes and verify that not a single byte outside the target is touched.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:test/test.dart';

typedef _StoreNative = Void Function(Pointer<Uint8>, IntPtr);
typedef _StoreDart = void Function(Pointer<Uint8>, int);
typedef _LoadNative = IntPtr Function(Pointer<Uint8>);
typedef _LoadDart = int Function(Pointer<Uint8>);

JitFunction _compile(
    JitRuntime runtime, void Function(UniCompiler cc) generator) {
  final code = CodeHolder(env: runtime.environment);
  final isA64 = code.env.arch == Arch.aarch64;
  final BaseCompiler archCompiler = isA64
      ? A64Compiler(env: code.env, labelManager: code.labelManager)
      : X86Compiler(env: code.env, labelManager: code.labelManager);
  final cc = UniCompiler(archCompiler);

  generator(cc);

  archCompiler.finalize();
  archCompiler
      .serializeToAssembler(isA64 ? A64Assembler(code) : X86Assembler(code));
  return runtime.add(code);
}

UniMem _mem(BaseReg base, int disp) => UniMem(base is A64Gp
    ? A64Mem.baseOffset(base, disp)
    : X86Mem.baseDisp(base as X86Gp, disp));

void main() {
  final host = Environment.host().arch;
  final skip = host == Arch.x64 || host == Arch.aarch64
      ? false
      : 'requires an x86-64 or AArch64 host';

  group('UJIT narrow store safety', () {
    late JitRuntime runtime;

    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    /// Builds `void fn(uint8_t* p, intptr_t val)` performing a single
    /// narrow store at [p + disp], then verifies sentinel bytes around the
    /// written range stay intact.
    void checkStore({
      required UniOpMR op,
      required int width,
      required int disp,
      required int value,
      required List<int> expectedBytes,
    }) {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        final v = cc.newGpPtr('v');
        cc.setArg(0, p);
        cc.setArg(1, v);
        cc.emitMR(op, _mem(p, disp), v);
        cc.ret();
        cc.endFunc();
      });

      const bufSize = 32;
      final buf = pkgffi.calloc<Uint8>(bufSize);
      try {
        for (int i = 0; i < bufSize; i++) {
          buf[i] = 0xA5; // sentinel
        }

        final call = fn.pointer
            .cast<NativeFunction<_StoreNative>>()
            .asFunction<_StoreDart>();
        call(buf, value);

        for (int i = 0; i < bufSize; i++) {
          final inTarget = i >= disp && i < disp + width;
          if (inTarget) {
            expect(buf[i], equals(expectedBytes[i - disp]),
                reason: 'byte $i (inside store target) has wrong value');
          } else {
            expect(buf[i], equals(0xA5),
                reason: 'byte $i outside the $width-byte store target at '
                    '+$disp was clobbered — store wrote too many bytes');
          }
        }
      } finally {
        pkgffi.calloc.free(buf);
      }
    }

    test('storeU32 writes exactly 4 bytes', () {
      checkStore(
        op: UniOpMR.storeU32,
        width: 4,
        disp: 8,
        value: 0x11223344,
        expectedBytes: [0x44, 0x33, 0x22, 0x11],
      );
    });

    test('storeU32 ignores high 32 bits of the source register', () {
      // High garbage bits in the 64-bit register must not reach memory.
      checkStore(
        op: UniOpMR.storeU32,
        width: 4,
        disp: 4,
        value: 0x7FFFFFFF11223344,
        expectedBytes: [0x44, 0x33, 0x22, 0x11],
      );
    });

    test('storeU16 writes exactly 2 bytes', () {
      checkStore(
        op: UniOpMR.storeU16,
        width: 2,
        disp: 6,
        value: 0x1122EEFF,
        expectedBytes: [0xFF, 0xEE],
      );
    });

    test('storeU8 writes exactly 1 byte', () {
      checkStore(
        op: UniOpMR.storeU8,
        width: 1,
        disp: 3,
        value: 0x11223377,
        expectedBytes: [0x77],
      );
    });

    test('storeU64 writes exactly 8 bytes', () {
      checkStore(
        op: UniOpMR.storeU64,
        width: 8,
        disp: 8,
        value: 0x1122334455667788,
        expectedBytes: [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11],
      );
    });

    test('crash repro shape: two u32 stores fill an 8-byte heap buffer', () {
      // Exact pattern from integration_abi_test 'Pointer Access (Context)':
      // ctx[0] = val; ctx[1] = val + 1 on a calloc'd 2 x int32 buffer.
      // The old 8-byte store at +4 corrupted the heap allocator's metadata.
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final ctx = cc.newGpPtr('ctx');
        final val = cc.newGpPtr('val');
        cc.setArg(0, ctx);
        cc.setArg(1, val);
        cc.emitMR(UniOpMR.storeU32, _mem(ctx, 0), val);
        cc.emitRRI(UniOpRRR.add, val, val, 1);
        cc.emitMR(UniOpMR.storeU32, _mem(ctx, 4), val);
        cc.ret();
        cc.endFunc();
      });

      final call = fn.pointer
          .cast<NativeFunction<Void Function(Pointer<Int32>, IntPtr)>>()
          .asFunction<void Function(Pointer<Int32>, int)>();

      // Loop to give the heap plenty of chances to detect an overflow.
      for (int i = 0; i < 1000; i++) {
        final mem = pkgffi.calloc<Int32>(2);
        try {
          call(mem, i);
          expect(mem[0], equals(i));
          expect(mem[1], equals(i + 1));
        } finally {
          pkgffi.calloc.free(mem);
        }
      }
    });
  }, skip: skip);

  group('UJIT memory add (UniOpMR.add*)', () {
    late JitRuntime runtime;

    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    test('addU32 performs ADD (not MOV) and writes exactly 4 bytes', () {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        final v = cc.newGpPtr('v');
        cc.setArg(0, p);
        cc.setArg(1, v);
        cc.emitMR(UniOpMR.addU32, _mem(p, 0), v);
        cc.ret();
        cc.endFunc();
      });

      final buf = pkgffi.calloc<Uint32>(2);
      try {
        buf[0] = 100;
        buf[1] = 0xCAFEBABE; // sentinel

        final call = fn.pointer
            .cast<NativeFunction<_StoreNative>>()
            .asFunction<_StoreDart>();
        call(buf.cast<Uint8>(), 23);

        expect(buf[0], equals(123),
            reason: 'addU32 must ADD to memory, not overwrite it');
        expect(buf[1], equals(0xCAFEBABE),
            reason: 'addU32 must not touch bytes past the 4-byte target');
      } finally {
        pkgffi.calloc.free(buf);
      }
    });

    test('addU64 adds 8 bytes in place', () {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        final v = cc.newGpPtr('v');
        cc.setArg(0, p);
        cc.setArg(1, v);
        cc.emitMR(UniOpMR.addU64, _mem(p, 0), v);
        cc.ret();
        cc.endFunc();
      });

      final buf = pkgffi.calloc<Int64>(1);
      try {
        buf.value = 0x100000000; // forces a carry into the high dword
        final call = fn.pointer
            .cast<NativeFunction<_StoreNative>>()
            .asFunction<_StoreDart>();
        call(buf.cast<Uint8>(), 7);
        expect(buf.value, equals(0x100000007));
      } finally {
        pkgffi.calloc.free(buf);
      }
    });
  }, skip: skip);

  group('UJIT narrow load correctness', () {
    late JitRuntime runtime;

    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    /// Builds `intptr_t fn(uint8_t* p)` performing a single narrow load at
    /// [p + disp] and returning it. The buffer is filled with 0xFF beyond the
    /// loaded range, so an over-wide load produces a detectably wrong value.
    int runLoad({required UniOpRM op, required int disp}) {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr], TypeId.intPtr, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        cc.setArg(0, p);
        final out = cc.newGpPtr('out');
        cc.emitRM(op, out, _mem(p, disp));
        cc.ret([out]);
        cc.endFunc();
      });

      const bufSize = 32;
      final buf = pkgffi.calloc<Uint8>(bufSize);
      try {
        // Little-endian payload 0x8899AABBCCDDEEFF at +8; 0xFF elsewhere so
        // an 8-byte read where 4 was intended is guaranteed to differ.
        for (int i = 0; i < bufSize; i++) {
          buf[i] = 0xFF;
        }
        final payload = [0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88];
        for (int i = 0; i < payload.length; i++) {
          buf[8 + i] = payload[i];
        }

        final call = fn.pointer
            .cast<NativeFunction<_LoadNative>>()
            .asFunction<_LoadDart>();
        return call(buf);
      } finally {
        pkgffi.calloc.free(buf);
      }
    }

    test('loadU32 reads 4 bytes and zero-extends', () {
      expect(runLoad(op: UniOpRM.loadU32, disp: 8), equals(0xCCDDEEFF));
    });

    test('loadI32 reads 4 bytes and sign-extends', () {
      expect(runLoad(op: UniOpRM.loadI32, disp: 8),
          equals(0xCCDDEEFF - 0x100000000)); // 0xCCDDEEFF has the sign bit set
    });

    test('loadU16 reads 2 bytes and zero-extends', () {
      expect(runLoad(op: UniOpRM.loadU16, disp: 8), equals(0xEEFF));
    });

    test('loadI16 reads 2 bytes and sign-extends', () {
      expect(runLoad(op: UniOpRM.loadI16, disp: 8), equals(0xEEFF - 0x10000));
    });

    test('loadU8 reads 1 byte and zero-extends', () {
      expect(runLoad(op: UniOpRM.loadU8, disp: 8), equals(0xFF));
    });

    test('loadI8 reads 1 byte and sign-extends', () {
      expect(runLoad(op: UniOpRM.loadI8, disp: 8), equals(-1));
    });

    test('loadU64 reads 8 bytes', () {
      // 0x8899AABBCCDDEEFF interpreted as a signed 64-bit integer.
      expect(
          runLoad(op: UniOpRM.loadU64, disp: 8),
          equals(BigInt.parse('8899AABBCCDDEEFF', radix: 16)
              .toSigned(64)
              .toInt()));
    });
  }, skip: skip);

  group('UJIT vector narrow load/store (UniOpVM/UniOpMV)', () {
    late JitRuntime runtime;

    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    /// Builds `void fn(uint8_t* p)`: loads a narrow value into a vector reg
    /// from [p], stores it back to [p + 16] with the matching narrow store,
    /// then verifies only the target bytes changed.
    void roundTrip({
      required UniOpVM loadOp,
      required UniOpMV storeOp,
      required int width,
    }) {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        cc.setArg(0, p);
        final v = cc.newVec('v');
        cc.emitVM(loadOp, v, _mem(p, 0).mem);
        cc.emitMV(storeOp, _mem(p, 16).mem, v);
        cc.ret();
        cc.endFunc();
      });

      const bufSize = 32;
      final buf = pkgffi.calloc<Uint8>(bufSize);
      try {
        for (int i = 0; i < bufSize; i++) {
          buf[i] = i < 16 ? (0x10 + i) : 0xA5; // payload | sentinels
        }

        fn.pointer
            .cast<NativeFunction<Void Function(Pointer<Uint8>)>>()
            .asFunction<void Function(Pointer<Uint8>)>()(buf);

        for (int i = 16; i < bufSize; i++) {
          final inTarget = i < 16 + width;
          if (inTarget) {
            expect(buf[i], equals(0x10 + (i - 16)),
                reason: 'byte $i must hold the copied payload');
          } else {
            expect(buf[i], equals(0xA5),
                reason: 'byte $i outside the $width-byte vector store target '
                    'was clobbered');
          }
        }
      } finally {
        pkgffi.calloc.free(buf);
      }
    }

    test('load8/store8 copies exactly 1 byte', () {
      roundTrip(loadOp: UniOpVM.load8, storeOp: UniOpMV.store8, width: 1);
    });

    test('load16U16/store16U16 copies exactly 2 bytes', () {
      roundTrip(
          loadOp: UniOpVM.load16U16, storeOp: UniOpMV.store16U16, width: 2);
    });

    test('load32U32/store32U32 copies exactly 4 bytes', () {
      roundTrip(
          loadOp: UniOpVM.load32U32, storeOp: UniOpMV.store32U32, width: 4);
    });

    test('load64U64/store64U64 copies exactly 8 bytes', () {
      roundTrip(
          loadOp: UniOpVM.load64U64, storeOp: UniOpMV.store64U64, width: 8);
    });

    test('load128U32/store128U32 copies exactly 16 bytes', () {
      roundTrip(
          loadOp: UniOpVM.load128U32, storeOp: UniOpMV.store128U32, width: 16);
    });
  }, skip: skip);
}
