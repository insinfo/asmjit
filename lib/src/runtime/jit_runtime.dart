/// AsmJit JIT Runtime
///
/// Manages JIT code generation and execution.
/// Ported from asmjit/core/jitruntime.h and jitruntime.cpp

import 'dart:ffi';
import 'dart:typed_data';

import '../core/error.dart';
import '../core/environment.dart';
import '../core/code_holder.dart';
import 'virtmem.dart';

/// A handle to a JIT-compiled function.
///
/// This holds the executable memory and provides a way to call the
/// generated code as a Dart function.
class JitFunction {
  final JitRuntime _runtime;
  final VirtMemBlock _block;

  JitFunction._({
    required JitRuntime runtime,
    required VirtMemBlock block,
  })  : _runtime = runtime,
        _block = block;

  /// The address of the generated code.
  int get address => _block.address;

  /// The size of the generated code in bytes.
  int get size => _block.size;

  /// Gets a pointer to the function for FFI.
  /// Gets a pointer to the function.
  ///
  /// Use this to create a callable Dart function:
  /// ```dart
  /// typedef NativeSig = Int64 Function(Int64, Int64);
  /// typedef DartSig = int Function(int, int);
  ///
  /// final ptr = fn.pointer.cast<NativeFunction<NativeSig>>();
  /// final add = ptr.asFunction<DartSig>();
  /// print(add(5, 3)); // 8
  /// ```
  Pointer<Void> get pointer => Pointer<Void>.fromAddress(address);

  /// Disposes the JIT function, freeing the executable memory.
  void dispose() {
    _runtime._release(_block);
  }
}

/// JIT Runtime - manages executable memory for generated code.
///
/// This is the main entry point for JIT code compilation.
/// It follows the W^X (Write XOR Execute) pattern:
/// 1. Allocate RW memory
/// 2. Write generated code
/// 3. Change protection to RX
/// 4. Execute
class JitRuntime {
  /// The target environment.
  final Environment environment;

  /// Whether executable memory allocation is enabled.
  final bool enableExecutableMemory;

  /// Virtual memory info (cached).
  late final VirtMemInfo _vmInfo;

  /// Track allocated blocks for cleanup.
  final List<VirtMemBlock> _allocatedBlocks = [];

  /// Creates a new JIT runtime.
  JitRuntime({
    Environment? environment,
    this.enableExecutableMemory = true,
  }) : environment = environment ?? Environment.host() {
    _vmInfo = VirtMem.info();
  }

  /// Returns virtual memory information.
  VirtMemInfo get virtMemInfo => _vmInfo;

  /// Adds code from a [CodeHolder] and returns a callable function.
  ///
  /// This is the main method to compile and get executable code:
  /// ```dart
  /// final code = CodeHolder();
  /// final asm = X86Assembler(code);
  /// asm.mov(rax, 42);
  /// asm.ret();
  ///
  /// final fn = runtime.add(code);
  /// final result = fn.asFunction<int Function()>()();
  /// print(result); // prints 42
  /// fn.dispose();
  /// ```
  JitFunction add(CodeHolder code) {
    if (!enableExecutableMemory) {
      throw AsmJitException.featureNotEnabled(
        'Executable memory allocation is disabled',
      );
    }

    // Finalize the code
    final finalized = code.finalize();
    final bytes = finalized.textBytes;

    if (bytes.isEmpty) {
      throw AsmJitException(
        AsmJitError.noCodeGenerated,
        'No code was generated',
      );
    }

    // Align size to page boundary
    final alignedSize = _vmInfo.alignToPage(bytes.length);

    // 1. Allocate RW memory
    final rwBlock = VirtMem.allocRW(alignedSize);

    try {
      // 2. Write the code
      VirtMem.writeBytes(rwBlock, bytes);

      // 3. Change protection to RX (W^X)
      final rxBlock = VirtMem.protectRX(rwBlock);

      // 4. Flush instruction cache
      VirtMem.flushInstructionCache(rxBlock.ptr.cast<Void>(), rxBlock.size);

      // Track the block
      _allocatedBlocks.add(rxBlock);

      return JitFunction._(
        runtime: this,
        block: rxBlock,
      );
    } catch (e) {
      // If anything fails, release the memory
      VirtMem.release(rwBlock);
      rethrow;
    }
  }

  /// Adds raw bytes as executable code.
  ///
  /// Use this when you already have pre-compiled machine code.
  JitFunction addBytes(Uint8List bytes) {
    if (!enableExecutableMemory) {
      throw AsmJitException.featureNotEnabled(
        'Executable memory allocation is disabled',
      );
    }

    if (bytes.isEmpty) {
      throw AsmJitException(
        AsmJitError.noCodeGenerated,
        'No code provided',
      );
    }

    // Align size to page boundary
    final alignedSize = _vmInfo.alignToPage(bytes.length);

    // 1. Allocate RW memory
    final rwBlock = VirtMem.allocRW(alignedSize);

    try {
      // 2. Write the code
      VirtMem.writeBytes(rwBlock, bytes);

      // 3. Change protection to RX (W^X)
      final rxBlock = VirtMem.protectRX(rwBlock);

      // 4. Flush instruction cache
      VirtMem.flushInstructionCache(rxBlock.ptr.cast<Void>(), rxBlock.size);

      // Track the block
      _allocatedBlocks.add(rxBlock);

      return JitFunction._(
        runtime: this,
        block: rxBlock,
      );
    } catch (e) {
      // If anything fails, release the memory
      VirtMem.release(rwBlock);
      rethrow;
    }
  }

  /// Releases a memory block.
  void _release(VirtMemBlock block) {
    _allocatedBlocks.remove(block);
    VirtMem.release(block);
  }

  /// Disposes all allocated memory.
  void dispose() {
    for (final block in _allocatedBlocks) {
      try {
        VirtMem.release(block);
      } catch (_) {
        // Ignore errors during cleanup
      }
    }
    _allocatedBlocks.clear();
  }
}
