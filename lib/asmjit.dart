/// AsmJit - JIT Assembler for Dart
///
/// A port of the AsmJit library from C++ to Dart.
/// Provides JIT code generation capabilities using FFI.
library asmjit;

// Core
export 'src/core/error.dart';
export 'src/core/globals.dart';
export 'src/core/environment.dart';
export 'src/core/arch.dart';
export 'src/core/code_buffer.dart';
export 'src/core/code_holder.dart';
export 'src/core/labels.dart';
export 'src/core/operand.dart';
export 'src/core/const_pool.dart';
export 'src/core/formatter.dart';
export 'src/core/regalloc.dart';

// Runtime
export 'src/runtime/libc.dart';
export 'src/runtime/virtmem.dart';
export 'src/runtime/jit_runtime.dart';
export 'src/runtime/cpuinfo.dart' show CpuInfo, CpuFeatures;

// x86
export 'src/x86/x86.dart';
export 'src/x86/x86_operands.dart';
export 'src/x86/x86_encoder.dart';
export 'src/x86/x86_assembler.dart';
export 'src/x86/x86_func.dart';
export 'src/x86/x86_simd.dart';

// Inline
export 'src/inline/inline_bytes.dart';
export 'src/inline/inline_asm.dart';
