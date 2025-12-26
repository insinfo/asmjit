/// ChaCha20 - Implementação com inline assembly (shellcode x86_64 SSE2)
/// Usa bytes de máquina pré-compilados + VirtualAlloc/mmap para código executável
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;

/// Gerenciador de memória executável
class ExecutableMemory {
  final ffi.Pointer<ffi.Void> pointer;
  final int size;
  bool _freed = false;

  ExecutableMemory._(this.pointer, this.size);

  /// Aloca memória executável e copia código
  static ExecutableMemory allocate(Uint8List code) {
    final ptr = _allocateExecutableMemory(code.length + 64);
    if (ptr == ffi.nullptr) {
      throw StateError('Failed to allocate executable memory');
    }
    final codePtr = ptr.cast<ffi.Uint8>();
    for (var i = 0; i < code.length; i++) {
      codePtr[i] = code[i];
    }
    return ExecutableMemory._(ptr, code.length + 64);
  }

  /// Libera memória
  void free() {
    if (_freed) return;
    _freeExecutableMemory(pointer, size);
    _freed = true;
  }

  static ffi.Pointer<ffi.Void> _allocateExecutableMemory(int size) {
    if (Platform.isWindows) {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final virtualAlloc = kernel32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>, ffi.IntPtr, ffi.Uint32, ffi.Uint32),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>, int, int, int)>('VirtualAlloc');
      // MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE
      return virtualAlloc(ffi.nullptr, size, 0x3000, 0x40);
    } else if (Platform.isLinux) {
      final libc = ffi.DynamicLibrary.open('libc.so.6');
      final mmap = libc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.IntPtr,
              ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int64),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>, int, int, int, int, int)>('mmap');
      // PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS
      return mmap(ffi.nullptr, size, 0x7, 0x22, -1, 0);
    } else {
      throw UnsupportedError('Platform not supported for inline assembly');
    }
  }

  static void _freeExecutableMemory(ffi.Pointer<ffi.Void> ptr, int size) {
    if (Platform.isWindows) {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final virtualFree = kernel32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr, ffi.Uint32),
          int Function(ffi.Pointer<ffi.Void>, int, int)>('VirtualFree');
      virtualFree(ptr, 0, 0x8000); // MEM_RELEASE
    } else if (Platform.isLinux) {
      final libc = ffi.DynamicLibrary.open('libc.so.6');
      final munmap = libc.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
          int Function(ffi.Pointer<ffi.Void>, int)>('munmap');
      munmap(ptr, size);
    }
  }
}

/// Verificação de suporte a SSE2
class ChaCha20InlineAsmSupport {
  static bool? _sse2Supported;

  static bool get isSSE2Supported {
    _sse2Supported ??= _checkSSE2Support();
    return _sse2Supported!;
  }

  static bool _checkSSE2Support() {
    if (!Platform.isWindows && !Platform.isLinux) return false;
    try {
      // CPUID check para SSE2 (bit 26 de EDX após CPUID com EAX=1)
      final code = Uint8List.fromList([
        0x53, // push rbx
        0xB8, 0x01, 0x00, 0x00, 0x00, // mov eax, 1
        0x0F, 0xA2, // cpuid
        0x89, 0xD0, // mov eax, edx
        0xC1, 0xE8, 0x1A, // shr eax, 26
        0x83, 0xE0, 0x01, // and eax, 1
        0x5B, // pop rbx
        0xC3, // ret
      ]);
      final mem = ExecutableMemory.allocate(code);
      try {
        final func = mem.pointer
            .cast<ffi.NativeFunction<ffi.Int32 Function()>>()
            .asFunction<int Function()>();
        return func() == 1;
      } finally {
        mem.free();
      }
    } catch (_) {
      return false;
    }
  }
}

/// Tipo da função de bloco ChaCha20
/// Windows: RCX=key, RDX=nonce, R8=constants, R9D=counter, [RSP+40]=output
/// Linux: RDI=key, RSI=nonce, RDX=constants, ECX=counter, R8=output
typedef ChaCha20BlockFunc = void Function(
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  ffi.Pointer<ffi.Uint8> constants,
  int counter,
  ffi.Pointer<ffi.Uint8> output,
);

/// ChaCha20 usando inline assembly x86_64 SSE2
class ChaCha20InlineAsm {
  static final Uint8List _constantsBytes = Uint8List.fromList([
    0x65, 0x78, 0x70, 0x61, // "expa"
    0x6e, 0x64, 0x20, 0x33, // "nd 3"
    0x32, 0x2d, 0x62, 0x79, // "2-by"
    0x74, 0x65, 0x20, 0x6b, // "te k"
  ]);

  final Uint8List _key;
  final Uint8List _nonce;
  final int initialCounter;

  // Código compilado e função
  static ExecutableMemory? _codeMemory;
  static ChaCha20BlockFunc? _blockFunc;

  // Buffers nativos
  ffi.Pointer<ffi.Uint8>? _keyPtr;
  ffi.Pointer<ffi.Uint8>? _noncePtr;
  ffi.Pointer<ffi.Uint8>? _constantsPtr;
  ffi.Pointer<ffi.Uint8>? _outputPtr;
  final Uint8List _keystream = Uint8List(64);
  bool _disposed = false;

  ChaCha20InlineAsm(this._key, this._nonce, {this.initialCounter = 0}) {
    if (_key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (_nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');
    _ensureInitialized();
    _initPointers();
  }

  static void _ensureInitialized() {
    if (_codeMemory != null) return;
    if (!ChaCha20InlineAsmSupport.isSSE2Supported) {
      throw UnsupportedError('SSE2 not supported on this CPU');
    }
    final code =
        Platform.isWindows ? _generateWindowsCode() : _generateLinuxCode();
    _codeMemory = ExecutableMemory.allocate(code);

    final funcPtr = _codeMemory!.pointer.cast<
        ffi.NativeFunction<
            ffi.Void Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Int32,
              ffi.Pointer<ffi.Uint8>,
            )>>();
    _blockFunc = funcPtr.asFunction();
  }

  void _initPointers() {
    _keyPtr = pkgffi.calloc<ffi.Uint8>(32);
    _noncePtr = pkgffi.calloc<ffi.Uint8>(12);
    _constantsPtr = pkgffi.calloc<ffi.Uint8>(16);
    _outputPtr = pkgffi.calloc<ffi.Uint8>(64);

    for (var i = 0; i < 32; i++) _keyPtr![i] = _key[i];
    for (var i = 0; i < 12; i++) _noncePtr![i] = _nonce[i];
    for (var i = 0; i < 16; i++) _constantsPtr![i] = _constantsBytes[i];
  }

  void dispose() {
    if (_disposed) return;
    if (_keyPtr != null) pkgffi.calloc.free(_keyPtr!);
    if (_noncePtr != null) pkgffi.calloc.free(_noncePtr!);
    if (_constantsPtr != null) pkgffi.calloc.free(_constantsPtr!);
    if (_outputPtr != null) pkgffi.calloc.free(_outputPtr!);
    _disposed = true;
  }

  /// Gera um bloco de keystream usando inline asm
  void _generateBlock(int counter) {
    _blockFunc!(_keyPtr!, _noncePtr!, _constantsPtr!, counter, _outputPtr!);
    for (var i = 0; i < 64; i++) {
      _keystream[i] = _outputPtr![i];
    }
  }

  /// Criptografa/Descriptografa
  Uint8List crypt(Uint8List input) {
    if (_disposed) throw StateError('Already disposed');

    final output = Uint8List(input.length);
    var counter = initialCounter;
    var offset = 0;

    while (offset < input.length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ _keystream[i];
      }
      offset += chunk;
    }

    return output;
  }

  void cryptInto(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Already disposed');
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    var counter = initialCounter;
    var offset = 0;

    while (offset < input.length) {
      _generateBlock(counter);
      counter++;

      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ _keystream[i];
      }
      offset += chunk;
    }
  }

  /// Gera shellcode Windows x64 para ChaCha20 block
  /// Calling convention: RCX=key, RDX=nonce, R8=constants, R9D=counter, [RSP+40]=output
  static Uint8List _generateWindowsCode() {
    final code = <int>[];

    // Prólogo - salva registradores non-volatile
    code.addAll([
      0x53, // push rbx
      0x41, 0x54, // push r12
      0x41, 0x55, // push r13
      0x48, 0x81, 0xEC, 0x80, 0x00, 0x00, 0x00, // sub rsp, 128
    ]);

    // Salva XMM6-XMM11 (Windows non-volatile)
    code.addAll([
      0x0F, 0x29, 0x74, 0x24, 0x00, // movaps [rsp+0], xmm6
      0x0F, 0x29, 0x7C, 0x24, 0x10, // movaps [rsp+16], xmm7
      0x44, 0x0F, 0x29, 0x44, 0x24, 0x20, // movaps [rsp+32], xmm8
      0x44, 0x0F, 0x29, 0x4C, 0x24, 0x30, // movaps [rsp+48], xmm9
      0x44, 0x0F, 0x29, 0x54, 0x24, 0x40, // movaps [rsp+64], xmm10
      0x44, 0x0F, 0x29, 0x5C, 0x24, 0x50, // movaps [rsp+80], xmm11
    ]);

    // Salva parâmetros
    code.addAll([
      0x48, 0x89, 0xCB, // mov rbx, rcx (key)
      0x49, 0x89, 0xD2, // mov r10, rdx (nonce)
      0x4D, 0x89, 0xC3, // mov r11, r8 (constants)
      0x45, 0x89, 0xCC, // mov r12d, r9d (counter)
      0x4C, 0x8B, 0xAC, 0x24, 0xC0, 0x00, 0x00,
      0x00, // mov r13, [rsp+192] (output)
    ]);

    // Carrega estado inicial para XMM0-XMM3
    code.addAll([
      0x41, 0x0F, 0x10, 0x03, // movups xmm0, [r11] (constants)
      0x0F, 0x10, 0x0B, // movups xmm1, [rbx] (key[0:16])
      0x0F, 0x10, 0x53, 0x10, // movups xmm2, [rbx+16] (key[16:32])
    ]);

    // Constrói XMM3 = [counter, nonce0, nonce1, nonce2]
    code.addAll([
      0x44, 0x89, 0x64, 0x24, 0x60, // mov [rsp+96], r12d (counter)
      0x41, 0x8B, 0x02, // mov eax, [r10] (nonce[0:4])
      0x89, 0x44, 0x24, 0x64, // mov [rsp+100], eax
      0x41, 0x8B, 0x42, 0x04, // mov eax, [r10+4]
      0x89, 0x44, 0x24, 0x68, // mov [rsp+104], eax
      0x41, 0x8B, 0x42, 0x08, // mov eax, [r10+8]
      0x89, 0x44, 0x24, 0x6C, // mov [rsp+108], eax
      0x0F, 0x10, 0x5C, 0x24, 0x60, // movups xmm3, [rsp+96]
    ]);

    // Salva estado inicial em XMM8-XMM11
    code.addAll([
      0x44, 0x0F, 0x28, 0xC0, // movaps xmm8, xmm0
      0x44, 0x0F, 0x28, 0xC9, // movaps xmm9, xmm1
      0x44, 0x0F, 0x28, 0xD2, // movaps xmm10, xmm2
      0x44, 0x0F, 0x28, 0xDB, // movaps xmm11, xmm3
      0xB9, 0x0A, 0x00, 0x00, 0x00, // mov ecx, 10 (10 double rounds)
    ]);

    // Loop de rounds
    final loopStart = code.length;
    _addDoubleRound(code);

    // dec ecx; jnz loop
    code.addAll([0xFF, 0xC9]); // dec ecx
    code.addAll([0x0F, 0x85]); // jnz rel32
    final offset = loopStart - (code.length + 4);
    code.addAll([
      offset & 0xFF,
      (offset >> 8) & 0xFF,
      (offset >> 16) & 0xFF,
      (offset >> 24) & 0xFF,
    ]);

    // Soma estado inicial
    code.addAll([
      0x66, 0x41, 0x0F, 0xFE, 0xC0, // paddd xmm0, xmm8
      0x66, 0x41, 0x0F, 0xFE, 0xC9, // paddd xmm1, xmm9
      0x66, 0x41, 0x0F, 0xFE, 0xD2, // paddd xmm2, xmm10
      0x66, 0x41, 0x0F, 0xFE, 0xDB, // paddd xmm3, xmm11
    ]);

    // Escreve output
    code.addAll([
      0x41, 0x0F, 0x11, 0x45, 0x00, // movups [r13], xmm0
      0x41, 0x0F, 0x11, 0x4D, 0x10, // movups [r13+16], xmm1
      0x41, 0x0F, 0x11, 0x55, 0x20, // movups [r13+32], xmm2
      0x41, 0x0F, 0x11, 0x5D, 0x30, // movups [r13+48], xmm3
    ]);

    // Epílogo
    code.addAll([
      0x0F, 0x28, 0x74, 0x24, 0x00, // movaps xmm6, [rsp+0]
      0x0F, 0x28, 0x7C, 0x24, 0x10, // movaps xmm7, [rsp+16]
      0x44, 0x0F, 0x28, 0x44, 0x24, 0x20, // movaps xmm8, [rsp+32]
      0x44, 0x0F, 0x28, 0x4C, 0x24, 0x30, // movaps xmm9, [rsp+48]
      0x44, 0x0F, 0x28, 0x54, 0x24, 0x40, // movaps xmm10, [rsp+64]
      0x44, 0x0F, 0x28, 0x5C, 0x24, 0x50, // movaps xmm11, [rsp+80]
      0x48, 0x81, 0xC4, 0x80, 0x00, 0x00, 0x00, // add rsp, 128
      0x41, 0x5D, // pop r13
      0x41, 0x5C, // pop r12
      0x5B, // pop rbx
      0xC3, // ret
    ]);

    return Uint8List.fromList(code);
  }

  /// Gera shellcode Linux SysV x64 para ChaCha20 block
  /// Calling convention: RDI=key, RSI=nonce, RDX=constants, ECX=counter, R8=output
  static Uint8List _generateLinuxCode() {
    final code = <int>[];

    // Prólogo
    code.addAll([
      0x48, 0x83, 0xEC, 0x18, // sub rsp, 24 (alinha stack + espaço temp)
    ]);

    // Carrega estado
    code.addAll([
      0x0F, 0x10, 0x02, // movups xmm0, [rdx] (constants)
      0x0F, 0x10, 0x0F, // movups xmm1, [rdi] (key[0:16])
      0x0F, 0x10, 0x57, 0x10, // movups xmm2, [rdi+16] (key[16:32])
    ]);

    // XMM3 = [counter, nonce]
    code.addAll([
      0x89, 0x0C, 0x24, // mov [rsp], ecx (counter)
      0x8B, 0x06, // mov eax, [rsi]
      0x89, 0x44, 0x24, 0x04, // mov [rsp+4], eax
      0x8B, 0x46, 0x04, // mov eax, [rsi+4]
      0x89, 0x44, 0x24, 0x08, // mov [rsp+8], eax
      0x8B, 0x46, 0x08, // mov eax, [rsi+8]
      0x89, 0x44, 0x24, 0x0C, // mov [rsp+12], eax
      0x0F, 0x10, 0x1C, 0x24, // movups xmm3, [rsp]
    ]);

    // Salva estado inicial
    code.addAll([
      0x44, 0x0F, 0x28, 0xC0, // movaps xmm8, xmm0
      0x44, 0x0F, 0x28, 0xC9, // movaps xmm9, xmm1
      0x44, 0x0F, 0x28, 0xD2, // movaps xmm10, xmm2
      0x44, 0x0F, 0x28, 0xDB, // movaps xmm11, xmm3
      0xB9, 0x0A, 0x00, 0x00, 0x00, // mov ecx, 10
    ]);

    final loopStart = code.length;
    _addDoubleRound(code);

    code.addAll([0xFF, 0xC9]); // dec ecx
    code.addAll([0x0F, 0x85]); // jnz
    final offset = loopStart - (code.length + 4);
    code.addAll([
      offset & 0xFF,
      (offset >> 8) & 0xFF,
      (offset >> 16) & 0xFF,
      (offset >> 24) & 0xFF,
    ]);

    // Soma estado inicial
    code.addAll([
      0x66, 0x41, 0x0F, 0xFE, 0xC0, // paddd xmm0, xmm8
      0x66, 0x41, 0x0F, 0xFE, 0xC9, // paddd xmm1, xmm9
      0x66, 0x41, 0x0F, 0xFE, 0xD2, // paddd xmm2, xmm10
      0x66, 0x41, 0x0F, 0xFE, 0xDB, // paddd xmm3, xmm11
    ]);

    // Escreve output (R8)
    code.addAll([
      0x41, 0x0F, 0x11, 0x00, // movups [r8], xmm0
      0x41, 0x0F, 0x11, 0x48, 0x10, // movups [r8+16], xmm1
      0x41, 0x0F, 0x11, 0x50, 0x20, // movups [r8+32], xmm2
      0x41, 0x0F, 0x11, 0x58, 0x30, // movups [r8+48], xmm3
    ]);

    // Epílogo
    code.addAll([
      0x48, 0x83, 0xC4, 0x18, // add rsp, 24
      0xC3, // ret
    ]);

    return Uint8List.fromList(code);
  }

  /// Adiciona uma double round (column + diagonal) usando SSE2
  static void _addDoubleRound(List<int> code) {
    // Column round
    _addQuarterRound(code);

    // Shuffle para diagonal: rot(1), rot(2), rot(3)
    code.addAll(
        [0x66, 0x0F, 0x70, 0xC9, 0x39]); // pshufd xmm1, xmm1, 0x39 (rot 1)
    code.addAll(
        [0x66, 0x0F, 0x70, 0xD2, 0x4E]); // pshufd xmm2, xmm2, 0x4E (rot 2)
    code.addAll(
        [0x66, 0x0F, 0x70, 0xDB, 0x93]); // pshufd xmm3, xmm3, 0x93 (rot 3)

    // Diagonal round
    _addQuarterRound(code);

    // Reverse shuffle
    code.addAll([0x66, 0x0F, 0x70, 0xC9, 0x93]); // pshufd xmm1, xmm1, 0x93
    code.addAll([0x66, 0x0F, 0x70, 0xD2, 0x4E]); // pshufd xmm2, xmm2, 0x4E
    code.addAll([0x66, 0x0F, 0x70, 0xDB, 0x39]); // pshufd xmm3, xmm3, 0x39
  }

  /// Adiciona quarter round SSE2
  /// XMM0=a, XMM1=b, XMM2=c, XMM3=d, XMM4=temp
  static void _addQuarterRound(List<int> code) {
    // a += b
    code.addAll([0x66, 0x0F, 0xFE, 0xC1]); // paddd xmm0, xmm1
    // d ^= a
    code.addAll([0x66, 0x0F, 0xEF, 0xD8]); // pxor xmm3, xmm0
    // d <<<= 16 (usando pslld + psrld + por)
    code.addAll([
      0x66, 0x0F, 0x6F, 0xE3, // movdqa xmm4, xmm3
      0x66, 0x0F, 0x72, 0xF4, 0x10, // pslld xmm4, 16
      0x66, 0x0F, 0x72, 0xD3, 0x10, // psrld xmm3, 16
      0x66, 0x0F, 0xEB, 0xDC, // por xmm3, xmm4
    ]);

    // c += d
    code.addAll([0x66, 0x0F, 0xFE, 0xD3]); // paddd xmm2, xmm3
    // b ^= c
    code.addAll([0x66, 0x0F, 0xEF, 0xCA]); // pxor xmm1, xmm2
    // b <<<= 12
    code.addAll([
      0x66, 0x0F, 0x6F, 0xE1, // movdqa xmm4, xmm1
      0x66, 0x0F, 0x72, 0xF4, 0x0C, // pslld xmm4, 12
      0x66, 0x0F, 0x72, 0xD1, 0x14, // psrld xmm1, 20
      0x66, 0x0F, 0xEB, 0xCC, // por xmm1, xmm4
    ]);

    // a += b
    code.addAll([0x66, 0x0F, 0xFE, 0xC1]); // paddd xmm0, xmm1
    // d ^= a
    code.addAll([0x66, 0x0F, 0xEF, 0xD8]); // pxor xmm3, xmm0
    // d <<<= 8
    code.addAll([
      0x66, 0x0F, 0x6F, 0xE3, // movdqa xmm4, xmm3
      0x66, 0x0F, 0x72, 0xF4, 0x08, // pslld xmm4, 8
      0x66, 0x0F, 0x72, 0xD3, 0x18, // psrld xmm3, 24
      0x66, 0x0F, 0xEB, 0xDC, // por xmm3, xmm4
    ]);

    // c += d
    code.addAll([0x66, 0x0F, 0xFE, 0xD3]); // paddd xmm2, xmm3
    // b ^= c
    code.addAll([0x66, 0x0F, 0xEF, 0xCA]); // pxor xmm1, xmm2
    // b <<<= 7
    code.addAll([
      0x66, 0x0F, 0x6F, 0xE1, // movdqa xmm4, xmm1
      0x66, 0x0F, 0x72, 0xF4, 0x07, // pslld xmm4, 7
      0x66, 0x0F, 0x72, 0xD1, 0x19, // psrld xmm1, 25
      0x66, 0x0F, 0xEB, 0xCC, // por xmm1, xmm4
    ]);
  }
}
