/// AsmJit Example: Simple Add Function
///
/// Demonstrates JIT compilation of a simple add function.

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:asmjit/asmjit.dart';

// Native function signatures
typedef NativeNoArgs = Int64 Function();
typedef DartNoArgs = int Function();

typedef NativeAdd = Int64 Function(Int64, Int64);
typedef DartAdd = int Function(int, int);

void main() {
  print('AsmJit Dart Example');
  print('==================');
  print('Platform: ${Platform.operatingSystem}');
  print('Architecture: ${Arch.host}');
  print('');

  // Example 1: Simple function that returns a constant
  example1ReturnConstant();

  // Example 2: Add function (with ABI handling)
  example2AddFunction();

  print('\nAll examples completed!');
}

/// Example 1: Create a function that returns 42.
void example1ReturnConstant() {
  print('Example 1: Return Constant');
  print('--------------------------');

  final runtime = JitRuntime();

  try {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    // Generate: return 42
    asm.movRI64(rax, 42);
    asm.ret();

    print('Generated ${code.text.buffer.length} bytes of code');
    _printBytes(code.text.buffer.bytes);

    final fn = runtime.add(code);
    print('Function address: 0x${fn.address.toRadixString(16)}');

    // Get the function as a callable Dart function
    final ptr = fn.pointer.cast<NativeFunction<NativeNoArgs>>();
    final callable = ptr.asFunction<DartNoArgs>();
    final result = callable();
    print('Result: $result');
    assert(result == 42, 'Expected 42, got $result');
    print('✓ Test passed!');

    fn.dispose();
  } finally {
    runtime.dispose();
  }

  print('');
}

/// Example 2: Create an add function.
void example2AddFunction() {
  print('Example 2: Add Function');
  print('-----------------------');

  final runtime = JitRuntime();

  try {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    // Get argument registers based on calling convention
    final arg0 = asm.getArgReg(0);
    final arg1 = asm.getArgReg(1);

    print('Calling convention: ${asm.callingConvention}');
    print('Arg0 register: $arg0');
    print('Arg1 register: $arg1');

    // Generate: return arg0 + arg1
    // mov rax, arg0
    // add rax, arg1
    // ret
    asm.movRR(rax, arg0);
    asm.addRR(rax, arg1);
    asm.ret();

    print('Generated ${code.text.buffer.length} bytes of code');
    _printBytes(code.text.buffer.bytes);

    final fn = runtime.add(code);
    print('Function address: 0x${fn.address.toRadixString(16)}');

    // Get the function as a callable
    final ptr = fn.pointer.cast<NativeFunction<NativeAdd>>();
    final add = ptr.asFunction<DartAdd>();

    // Test the function
    final tests = [
      (5, 3, 8),
      (100, 200, 300),
      (-10, 25, 15),
      (0, 0, 0),
      (1000000, 2000000, 3000000),
    ];

    for (final (a, b, expected) in tests) {
      final result = add(a, b);
      final status = result == expected ? '✓' : '✗';
      print('  $a + $b = $result $status');
      assert(result == expected, 'Expected $expected, got $result');
    }

    print('✓ All tests passed!');

    fn.dispose();
  } finally {
    runtime.dispose();
  }

  print('');
}

/// Prints bytes as hex.
void _printBytes(List<int> bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  print('Bytes: $hex');
}
