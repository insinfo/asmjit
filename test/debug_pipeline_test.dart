/// Debug test for pipeline JIT crash
///
/// Minimal reproduction case with instrumentation.

import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

typedef NativeReadMem = Int32 Function(IntPtr ptr);
typedef DartReadMem = int Function(int ptr);

typedef NativeWriteMem = Void Function(IntPtr dst);
typedef DartWriteMem = void Function(int dst);

void main() {
  group('Debug Pipeline JIT with Instrumentation', () {
    test('Memory read with debug output', () {
      final runtime = JitRuntime();
      final env = Environment.host();
      final builder = X86CodeBuilder.create(env: env);

      // Function: int readMem(int* ptr)
      final sig = FuncSignature(
        callConvId: env.callingConvention == CallingConvention.win64
            ? CallConvId.x64Windows
            : CallConvId.x64SystemV,
        retType: TypeId.int32,
        args: const [
          TypeId.intPtr,
        ],
      );

      builder.addFunc(sig, name: 'read_mem');

      final ptr = builder.getArgReg(0);
      final result = builder.newGpReg(size: 4);

      print('=== VirtReg info ===');
      print(
          'ptr (arg0): id=${ptr.id}, size=${ptr.size}, physReg=${ptr.physReg}');
      print(
          'result: id=${result.id}, size=${result.size}, physReg=${result.physReg}');

      // Read from memory
      builder.mov(result, X86Mem.baseDisp(ptr, 0, size: 4));
      // Return the result
      builder.ret(result);

      print('\n=== IR Nodes before build ===');
      for (final node in builder.nodes.nodes) {
        print('  $node');
      }

      // Build with debug
      print('\n=== Building function ===');
      final fn = builder.build(runtime);

      print('\n=== VirtReg allocation after build ===');
      print('ptr (arg0): physReg=${ptr.physReg}, isSpilled=${ptr.isSpilled}');
      print('result: physReg=${result.physReg}, isSpilled=${result.isSpilled}');

      print('\n=== Generated code info ===');
      print('  Function pointer: 0x${fn.pointer.address.toRadixString(16)}');

      // Allocate memory
      final mem = calloc(1, 4).cast<Uint32>();
      mem.value = 0x12345678;

      print('\n=== Executing function ===');
      print('  Memory address: 0x${mem.address.toRadixString(16)}');
      print('  Memory value before: 0x${mem.value.toRadixString(16)}');

      final entry = fn.pointer
          .cast<NativeFunction<NativeReadMem>>()
          .asFunction<DartReadMem>();

      try {
        final readValue = entry(mem.address);
        print('  Read value: 0x${readValue.toRadixString(16)}');
        expect(readValue, 0x12345678);
        print('\nSUCCESS!');
      } catch (e) {
        print('  Error: $e');
        rethrow;
      }

      free(mem.cast<Void>());
      fn.dispose();
      runtime.dispose();
    });

    test('Memory write with debug output', () {
      final runtime = JitRuntime();
      final env = Environment.host();
      final builder = X86CodeBuilder.create(env: env);

      final sig = FuncSignature(
        callConvId: env.callingConvention == CallingConvention.win64
            ? CallConvId.x64Windows
            : CallConvId.x64SystemV,
        retType: TypeId.void_,
        args: const [
          TypeId.intPtr,
        ],
      );

      builder.addFunc(sig, name: 'write_mem');

      final dst = builder.getArgReg(0);
      final tmp = builder.newGpReg(size: 4);

      print('=== VirtReg info ===');
      print(
          'dst (arg0): id=${dst.id}, size=${dst.size}, physReg=${dst.physReg}');
      print('tmp: id=${tmp.id}, size=${tmp.size}, physReg=${tmp.physReg}');

      builder.mov(tmp, 0x12345678);
      builder.mov(X86Mem.baseDisp(dst, 0, size: 4), tmp);

      builder.endFunc();

      print('\n=== IR Nodes before build ===');
      for (final node in builder.nodes.nodes) {
        print('  $node');
      }

      print('\n=== Building function ===');
      final fn = builder.build(runtime);

      print('\n=== VirtReg allocation after build ===');
      print('dst (arg0): physReg=${dst.physReg}, isSpilled=${dst.isSpilled}');
      print('tmp: physReg=${tmp.physReg}, isSpilled=${tmp.isSpilled}');

      print('\n=== Generated code info ===');
      print('  Function pointer: 0x${fn.pointer.address.toRadixString(16)}');

      // Allocate memory
      final mem = calloc(1, 4).cast<Uint32>();
      mem.value = 0;

      print('\n=== Executing function ===');
      print('  Memory address: 0x${mem.address.toRadixString(16)}');
      print('  Memory value before: 0x${mem.value.toRadixString(16)}');

      final entry = fn.pointer
          .cast<NativeFunction<NativeWriteMem>>()
          .asFunction<DartWriteMem>();

      try {
        entry(mem.address);
        print('  Memory value after: 0x${mem.value.toRadixString(16)}');
        expect(mem.value, 0x12345678);
        print('\nSUCCESS!');
      } catch (e) {
        print('  Error: $e');
        rethrow;
      }

      free(mem.cast<Void>());
      fn.dispose();
      runtime.dispose();
    });
  });
}
