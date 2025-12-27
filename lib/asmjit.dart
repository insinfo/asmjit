/// AsmJit - JIT Assembler for Dart
///
/// A port of the AsmJit library from C++ to Dart.
/// Provides JIT code generation capabilities using FFI.
library asmjit;

// Core
export 'src/asmjit/core/error.dart';
export 'src/asmjit/core/globals.dart';
export 'src/asmjit/core/environment.dart';
export 'src/asmjit/core/arch.dart';
export 'src/asmjit/core/code_buffer.dart';
export 'src/asmjit/core/code_holder.dart';
export 'src/asmjit/core/labels.dart';
export 'src/asmjit/core/operand.dart';
export 'src/asmjit/core/const_pool.dart';
export 'src/asmjit/core/formatter.dart';
export 'src/asmjit/core/type.dart';
export 'src/asmjit/core/regalloc.dart';
export 'src/asmjit/core/code_builder.dart';
export 'src/asmjit/core/builder.dart' hide Operand;

// Runtime
export 'src/asmjit/runtime/libc.dart';
export 'src/asmjit/runtime/virtmem.dart';
export 'src/asmjit/runtime/jit_runtime.dart';
export 'src/asmjit/runtime/cpuinfo.dart' show CpuInfo, CpuFeatures;

// x86
export 'src/asmjit/x86/x86.dart';
export 'src/asmjit/x86/x86_operands.dart';
export 'src/asmjit/x86/x86_encoder.dart';
export 'src/asmjit/x86/x86_assembler.dart';
export 'src/asmjit/x86/x86_func.dart';
export 'src/asmjit/x86/x86_simd.dart';
export 'src/asmjit/x86/x86_inst_db.g.dart';
export 'src/asmjit/x86/x86_serializer.dart';

// ARM64
export 'src/asmjit/arm/a64.dart' hide sp;
export 'src/asmjit/arm/a64_assembler.dart';
export 'src/asmjit/arm/a64_code_builder.dart';
export 'src/asmjit/arm/a64_inst_db.g.dart';
export 'src/asmjit/arm/a64_serializer.dart';

// Inline
export 'src/inline/inline_bytes.dart';
export 'src/inline/inline_asm.dart';

// ASMTK (Assembly Toolkit - Text Parser)
export 'src/asmtk/tokenizer.dart';
export 'src/asmtk/parser.dart';
