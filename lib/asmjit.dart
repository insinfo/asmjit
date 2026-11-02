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
export 'src/asmjit/core/code_writer.dart';
export 'src/asmjit/core/fixup.dart';
export 'src/asmjit/core/labels.dart';
export 'src/asmjit/core/operand.dart';
export 'src/asmjit/core/const_pool.dart';
export 'src/asmjit/core/formatter.dart';
export 'src/asmjit/core/emitter.dart';
export 'src/asmjit/core/assembler.dart';
export 'src/asmjit/core/inst_api.dart';
export 'src/asmjit/core/type.dart';
export 'src/asmjit/core/condcode.dart';
export 'src/asmjit/core/func.dart';

// UJIT (Universal JIT)
export 'src/asmjit/ujit/ujitbase.dart';
export 'src/asmjit/ujit/uniop.dart';
export 'src/asmjit/ujit/unicondition.dart';
export 'src/asmjit/ujit/unicompiler.dart';
export 'src/asmjit/ujit/vecconsttable.dart';

export 'src/asmjit/core/builder.dart'
    hide Operand, NodeType, InstNode, LabelNode;
export 'src/asmjit/core/compiler.dart';

// Runtime
export 'src/asmjit/runtime/libc.dart';
export 'src/asmjit/runtime/virtmem.dart';
export 'src/asmjit/runtime/jit_allocator.dart'
    show
        JitAllocator,
        JitAllocatorCreateParams,
        JitAllocatorOptions,
        JitAllocatorSpan,
        JitAllocatorSpanFlags,
        JitAllocatorStatistics,
        JitAllocatorWriteScope,
        JitAllocatorWriteScopeData;
export 'src/asmjit/runtime/jit_runtime.dart';
export 'src/asmjit/runtime/cpuinfo.dart' show CpuInfo, CpuFeatures;

// x86
export 'src/asmjit/x86/x86.dart';
export 'src/asmjit/x86/x86_operands.dart';
export 'src/asmjit/x86/x86_cond.dart';
export 'src/asmjit/x86/x86_assembler.dart';
export 'src/asmjit/x86/x86_emit.dart' show X86EmitOptions, X86EmitError;
export 'src/asmjit/x86/x86_opcode.dart'
    show X86Encoding, X86InstDbFlags, X86Avx512Flags;
export 'src/asmjit/x86/x86_compiler.dart';
export 'src/asmjit/x86/x86_func.dart';
export 'src/asmjit/x86/x86_simd.dart';
export 'src/asmjit/x86/x86_inst_db.g.dart';
export 'src/asmjit/x86/x86_serializer.dart';

// ARM64
export 'src/asmjit/arm/a64.dart' hide sp;
export 'src/asmjit/arm/a64_assembler.dart';
export 'src/asmjit/arm/a64_emit.dart' show A64EmitError;
export 'src/asmjit/arm/a64_predicate.dart';
export 'src/asmjit/arm/a64_compiler.dart';
export 'src/asmjit/arm/a64_code_builder.dart';
export 'src/asmjit/arm/a64_func.dart';
export 'src/asmjit/arm/a64_inst_db.g.dart';
export 'src/asmjit/arm/a64_serializer.dart';

// Inline
export 'src/inline/inline_bytes.dart';
export 'src/inline/inline_asm.dart';
