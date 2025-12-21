/// AsmJit Inline Assembly API
///
/// Provides a high-level API for building JIT functions using
/// inline bytes, assembler, or a combination.

import 'dart:typed_data';

import '../core/code_holder.dart';
import '../runtime/jit_runtime.dart';
import '../x86/x86_assembler.dart';
import 'inline_bytes.dart';

/// Inline Assembly Builder.
///
/// Provides a convenient way to build JIT functions using:
/// - Raw inline bytes (pre-compiled shellcode)
/// - The X86Assembler
/// - A combination of both
///
/// Example:
/// ```dart
/// final asm = InlineAsm(runtime);
///
/// // Using assembler
/// final addFn = asm.buildX86((a, code) {
///   a.mov(rax, a.getArgReg(0));
///   a.add(rax, a.getArgReg(1));
///   a.ret();
/// });
///
/// // Using inline bytes
/// final retFn = asm.buildBytes([0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3]);
/// ```
class InlineAsm {
  /// The JIT runtime.
  final JitRuntime runtime;

  /// Whether to cache generated functions by key.
  final bool enableCache;

  /// Cache of generated functions by key.
  final Map<String, JitFunction> _cache = {};

  /// Creates an InlineAsm builder.
  InlineAsm(
    this.runtime, {
    this.enableCache = false,
  });

  /// Builds a function using the X86Assembler.
  ///
  /// The [build] callback receives an assembler and code holder.
  /// The function is compiled and executed when called.
  JitFunction buildX86(void Function(X86Assembler a, CodeHolder code) build) {
    final code = CodeHolder();
    final asm = X86Assembler(code);
    build(asm, code);
    return runtime.add(code);
  }

  /// Builds a function using the X86Assembler with caching.
  ///
  /// If [key] was previously used, returns the cached function.
  JitFunction buildX86Cached(
    String key,
    void Function(X86Assembler a, CodeHolder code) build,
  ) {
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }
    final fn = buildX86(build);
    if (enableCache) {
      _cache[key] = fn;
    }
    return fn;
  }

  /// Builds a function from raw bytes.
  JitFunction buildBytes(List<int> bytes) {
    return runtime.addBytes(Uint8List.fromList(bytes));
  }

  /// Builds a function from InlineBytes with patches applied.
  JitFunction buildInlineBytes(InlineBytes inline) {
    final patched = inline.applyPatches();
    return runtime.addBytes(patched);
  }

  /// Builds a function from a template with values.
  JitFunction buildTemplate(InlineTemplate template, Map<String, int> values) {
    final inline = template.instantiate(values);
    return buildInlineBytes(inline);
  }

  /// Builds a function that combines assembler setup with inline bytes.
  ///
  /// Useful for adding prologues/epilogues around pre-compiled code.
  JitFunction buildHybrid({
    void Function(X86Assembler a)? prologue,
    required List<int> inlineBytes,
    void Function(X86Assembler a)? epilogue,
  }) {
    final code = CodeHolder();
    final asm = X86Assembler(code);

    if (prologue != null) {
      prologue(asm);
    }

    asm.emitBytes(inlineBytes);

    if (epilogue != null) {
      epilogue(asm);
    }

    return runtime.add(code);
  }

  /// Disposes all cached functions.
  void clearCache() {
    for (final fn in _cache.values) {
      fn.dispose();
    }
    _cache.clear();
  }

  /// Disposes a specific cached function.
  void disposeCached(String key) {
    final fn = _cache.remove(key);
    fn?.dispose();
  }
}

// =============================================================================
// Pre-built x86-64 instruction sequences
// =============================================================================

/// Common x86-64 shellcode templates.
class X86Templates {
  X86Templates._();

  /// Returns a constant value template.
  ///
  /// Template: mov eax, <imm32>; ret
  /// Parameters: 'value' (imm32)
  static final returnImm32 = InlineTemplate.fromList(
    [0xB8, 0x00, 0x00, 0x00, 0x00, 0xC3],
    [
      InlineTemplatePatch(
        name: 'value',
        kind: InlinePatchKind.imm32,
        atOffset: 1,
      ),
    ],
  );

  /// Returns a 64-bit constant value template (movabs).
  ///
  /// Template: movabs rax, <imm64>; ret
  /// Parameters: 'value' (imm64)
  static final returnImm64 = InlineTemplate.fromList(
    [0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC3],
    [
      InlineTemplatePatch(
        name: 'value',
        kind: InlinePatchKind.imm64,
        atOffset: 2,
      ),
    ],
  );

  /// Identity function for Win64 (returns first argument).
  ///
  /// Code: mov rax, rcx; ret
  static final identityWin64 = InlineBytes.fromList([
    0x48, 0x89, 0xC8, // mov rax, rcx
    0xC3, // ret
  ]);

  /// Identity function for SysV (returns first argument).
  ///
  /// Code: mov rax, rdi; ret
  static final identitySysV = InlineBytes.fromList([
    0x48, 0x89, 0xF8, // mov rax, rdi
    0xC3, // ret
  ]);

  /// Add two integers (Win64).
  ///
  /// Code: mov rax, rcx; add rax, rdx; ret
  static final addWin64 = InlineBytes.fromList([
    0x48, 0x89, 0xC8, // mov rax, rcx
    0x48, 0x01, 0xD0, // add rax, rdx
    0xC3, // ret
  ]);

  /// Add two integers (SysV).
  ///
  /// Code: mov rax, rdi; add rax, rsi; ret
  static final addSysV = InlineBytes.fromList([
    0x48, 0x89, 0xF8, // mov rax, rdi
    0x48, 0x01, 0xF0, // add rax, rsi
    0xC3, // ret
  ]);

  /// Subtract two integers (Win64).
  ///
  /// Code: mov rax, rcx; sub rax, rdx; ret
  static final subWin64 = InlineBytes.fromList([
    0x48, 0x89, 0xC8, // mov rax, rcx
    0x48, 0x29, 0xD0, // sub rax, rdx
    0xC3, // ret
  ]);

  /// Subtract two integers (SysV).
  ///
  /// Code: mov rax, rdi; sub rax, rsi; ret
  static final subSysV = InlineBytes.fromList([
    0x48, 0x89, 0xF8, // mov rax, rdi
    0x48, 0x29, 0xF0, // sub rax, rsi
    0xC3, // ret
  ]);

  /// Multiply two integers (Win64).
  ///
  /// Code: mov rax, rcx; imul rax, rdx; ret
  static final mulWin64 = InlineBytes.fromList([
    0x48, 0x89, 0xC8, // mov rax, rcx
    0x48, 0x0F, 0xAF, 0xC2, // imul rax, rdx
    0xC3, // ret
  ]);

  /// Multiply two integers (SysV).
  ///
  /// Code: mov rax, rdi; imul rax, rsi; ret
  static final mulSysV = InlineBytes.fromList([
    0x48, 0x89, 0xF8, // mov rax, rdi
    0x48, 0x0F, 0xAF, 0xC6, // imul rax, rsi
    0xC3, // ret
  ]);

  /// NOP sled of various sizes.
  static InlineBytes nopSled(int size) {
    final bytes = List<int>.filled(size, 0x90);
    return InlineBytes.fromList(bytes);
  }

  /// Int3 breakpoint.
  static final breakpoint = InlineBytes.fromList([0xCC]);

  /// Infinite loop (for debugging).
  ///
  /// Code: jmp $-2
  static final infiniteLoop = InlineBytes.fromList([0xEB, 0xFE]);
}
