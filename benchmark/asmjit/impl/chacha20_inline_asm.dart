//C:\MyDartProjects\asmjit\benchmark\impl\chacha20_inline_asm.dart

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:asmjit/src/inline/asm_mnemonics_const_api.dart';
import 'package:ffi/ffi.dart' as pkgffi;

// =============================================================================
//  Implementação ChaCha20
// =============================================================================

class ExecutableMemory {
  final ffi.Pointer<ffi.Void> pointer;
  final int size;
  bool _freed = false;

  ExecutableMemory._(this.pointer, this.size);

  static ExecutableMemory allocate(Uint8List code) {
    final ptr = _allocateExecutableMemory(code.length + 64);
    if (ptr == ffi.nullptr) throw StateError('Alloc failed');
    final codePtr = ptr.cast<ffi.Uint8>();
    for (var i = 0; i < code.length; i++) codePtr[i] = code[i];
    return ExecutableMemory._(ptr, code.length + 64);
  }

  void free() {
    if (_freed) return;
    _freeExecutableMemory(pointer, size);
    _freed = true;
  }

  static ffi.Pointer<ffi.Void> _allocateExecutableMemory(int size) {
    if (Platform.isWindows) {
      final k32 = ffi.DynamicLibrary.open('kernel32.dll');
      final vAlloc = k32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>, ffi.IntPtr, ffi.Uint32, ffi.Uint32),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>, int, int, int)>('VirtualAlloc');
      return vAlloc(ffi.nullptr, size, 0x3000, 0x40);
    } else if (Platform.isLinux) {
      final libc = ffi.DynamicLibrary.open('libc.so.6');
      final mmap = libc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.IntPtr,
              ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int64),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>, int, int, int, int, int)>('mmap');
      return mmap(ffi.nullptr, size, 0x7, 0x22, -1, 0);
    }
    throw UnsupportedError('Plataforma não suportada');
  }

  static void _freeExecutableMemory(ffi.Pointer<ffi.Void> ptr, int size) {
    if (Platform.isWindows) {
      final k32 = ffi.DynamicLibrary.open('kernel32.dll');
      final vFree = k32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr, ffi.Uint32),
          int Function(ffi.Pointer<ffi.Void>, int, int)>('VirtualFree');
      vFree(ptr, 0, 0x8000);
    } else if (Platform.isLinux) {
      final libc = ffi.DynamicLibrary.open('libc.so.6');
      final munmap = libc.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
          int Function(ffi.Pointer<ffi.Void>, int)>('munmap');
      munmap(ptr, size);
    }
  }
}

class ChaCha20InlineAsmSupport {
  static bool get isSSE2Supported {
    if (!Platform.isWindows && !Platform.isLinux) return false;
    try {
      final code = Uint8List.fromList([
        push_rbx,
        mov_eax, 0x01, 0x00, 0x00, 0x00, // mov eax, 1
        x0f, cpuid, // cpuid
        0x89, 0xD0, // mov eax, edx
        0xC1, 0xE8, 0x1A, // shr eax, 26
        0x83, 0xE0, 0x01, // and eax, 1
        pop_rbx,
        ret,
      ]);
      final mem = ExecutableMemory.allocate(code);
      try {
        final f = mem.pointer
            .cast<ffi.NativeFunction<ffi.Int32 Function()>>()
            .asFunction<int Function()>();
        return f() == 1;
      } finally {
        mem.free();
      }
    } catch (_) {
      return false;
    }
  }
}

typedef ChaCha20BlockFunc = void Function(
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  ffi.Pointer<ffi.Uint8> consts,
  int counter,
  ffi.Pointer<ffi.Uint8> out,
);

class ChaCha20InlineAsm {
  static final _consts = Uint8List.fromList([
    0x65,
    0x78,
    0x70,
    0x61,
    0x6e,
    0x64,
    0x20,
    0x33,
    0x32,
    0x2d,
    0x62,
    0x79,
    0x74,
    0x65,
    0x20,
    0x6b
  ]);

  final Uint8List _key, _nonce;
  final int initialCounter;
  static ExecutableMemory? _mem;
  static ChaCha20BlockFunc? _fn;

  ffi.Pointer<ffi.Uint8>? _pKey, _pNonce, _pConst, _pOut;
  final Uint8List _ks = Uint8List(64);
  bool _disposed = false;

  ChaCha20InlineAsm(this._key, this._nonce, {this.initialCounter = 0}) {
    if (_key.length != 32 || _nonce.length != 12)
      throw ArgumentError('Key/Nonce invalid');
    _init();
    _alloc();
  }

  static void _init() {
    if (_mem != null) return;
    if (!ChaCha20InlineAsmSupport.isSSE2Supported)
      throw UnsupportedError('SSE2 required');
    final code = Platform.isWindows ? _genWin() : _genLin();
    _mem = ExecutableMemory.allocate(code);
    _fn = _mem!.pointer
        .cast<
            ffi.NativeFunction<
                ffi.Void Function(
                    ffi.Pointer<ffi.Uint8>,
                    ffi.Pointer<ffi.Uint8>,
                    ffi.Pointer<ffi.Uint8>,
                    ffi.Int32,
                    ffi.Pointer<ffi.Uint8>)>>()
        .asFunction();
  }

  void _alloc() {
    _pKey = pkgffi.calloc<ffi.Uint8>(32);
    _pNonce = pkgffi.calloc<ffi.Uint8>(12);
    _pConst = pkgffi.calloc<ffi.Uint8>(16);
    _pOut = pkgffi.calloc<ffi.Uint8>(64);
    for (var i = 0; i < 32; i++) _pKey![i] = _key[i];
    for (var i = 0; i < 12; i++) _pNonce![i] = _nonce[i];
    for (var i = 0; i < 16; i++) _pConst![i] = _consts[i];
  }

  void dispose() {
    if (_disposed) return;
    pkgffi.calloc.free(_pKey!);
    pkgffi.calloc.free(_pNonce!);
    pkgffi.calloc.free(_pConst!);
    pkgffi.calloc.free(_pOut!);
    _disposed = true;
  }

  Uint8List crypt(Uint8List input) {
    if (_disposed) throw StateError('Disposed');
    final output = Uint8List(input.length);
    var ctr = initialCounter;
    var off = 0;
    while (off < input.length) {
      _fn!(_pKey!, _pNonce!, _pConst!, ctr++, _pOut!);
      for (var i = 0; i < 64; i++) _ks[i] = _pOut![i];
      final chunk = min(64, input.length - off);
      for (var i = 0; i < chunk; i++) output[off + i] = input[off + i] ^ _ks[i];
      off += chunk;
    }
    return output;
  }

  /// Criptografa/Descriptografa escrevendo diretamente no buffer de saída (Zero allocation)
  void cryptInto(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Disposed');
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    var ctr = initialCounter;
    var off = 0;

    while (off < input.length) {
      // Chama o assembly para gerar o keystream de 64 bytes em _pOut
      _fn!(_pKey!, _pNonce!, _pConst!, ctr++, _pOut!);

      // Copia do buffer nativo para o buffer temporário Dart _ks
      for (var i = 0; i < 64; i++) {
        _ks[i] = _pOut![i];
      }

      // Faz o XOR com o input e grava no output
      final chunk = min(64, input.length - off);
      for (var i = 0; i < chunk; i++) {
        output[off + i] = input[off + i] ^ _ks[i];
      }
      off += chunk;
    }
  }
  // --- GERAÇÃO DE CÓDIGO (Assembly Puro) ---

  static Uint8List _genWin() {
    final c = <int>[];

    // Prologue & Save Non-Volatile
    c.addAll([
      push_rbx,
      rex_b, push_rsp, // push r12 (encode manual: REX.B + 54)
      rex_b, push_rbp, // push r13 (encode manual: REX.B + 55)
      rex_w, sub_rm64, 0xEC, 0x80, 0x00, 0x00, 0x00, // sub rsp, 128
    ]);

    // Save XMM6-XMM11 (Win ABI)
    c.addAll([
      x0f, movaps_st, 0x74, rsp_disp, 0x00, // [rsp] = xmm6
      x0f, movaps_st, 0x7C, rsp_disp, 0x10, // [rsp+16] = xmm7
      rex_r, x0f, movaps_st, 0x44, rsp_disp, 0x20, // ... xmm8
      rex_r, x0f, movaps_st, 0x4C, rsp_disp, 0x30, // ... xmm9
      rex_r, x0f, movaps_st, 0x54, rsp_disp, 0x40, // ... xmm10
      rex_r, x0f, movaps_st, 0x5C, rsp_disp, 0x50, // ... xmm11
    ]);

    // Params -> Registers
    c.addAll([
      rex_w, mov_rm_r, 0xCB, // mov rbx, rcx (key)
      rex_wb, mov_rm_r, 0xD2, // mov r10, rdx (nonce)
      rex_wrb, mov_rm_r, 0xC3, // mov r11, r8 (const)
      rex_r, mov_rm_r, 0xCC, // mov r12d, r9d (counter)
      rex_wr, mov_r_rm, 0xAC, rsp_disp, 0xC0, 0x00, 0x00,
      0x00, // mov r13, [rsp+192] (output param)
    ]);

    // Load Initial State
    c.addAll([
      rex_b, x0f, movups, 0x03, // movups xmm0, [r11]
      x0f, movups, 0x0B, // movups xmm1, [rbx]
      x0f, movups, 0x53, 0x10, // movups xmm2, [rbx+16]
    ]);

    // Build XMM3 (Counter + Nonce)
    c.addAll([
      rex_r, mov_rm_r, 0x64, rsp_disp, 0x60, // mov [rsp+96], r12d
      rex_b, mov_r_rm, 0x02, // mov eax, [r10]
      0x89, 0x44, rsp_disp, 0x64, // mov [rsp+100], eax
      rex_b, mov_r_rm, 0x42, 0x04, // mov eax, [r10+4]
      0x89, 0x44, rsp_disp, 0x68, // mov [rsp+104], eax
      rex_b, mov_r_rm, 0x42, 0x08, // mov eax, [r10+8]
      0x89, 0x44, rsp_disp, 0x6C, // mov [rsp+108], eax
      x0f, movups, 0x5C, rsp_disp, 0x60, // movups xmm3, [rsp+96]
    ]);

    // Backup State
    c.addAll([
      rex_r, x0f, movaps, 0xC0, // movaps xmm8, xmm0
      rex_r, x0f, movaps, 0xC9, // movaps xmm9, xmm1
      rex_r, x0f, movaps, 0xD2, // movaps xmm10, xmm2
      rex_r, x0f, movaps, 0xDB, // movaps xmm11, xmm3
    ]);

    // Loop
    c.addAll([mov_ecx, 0x0A, 0x00, 0x00, 0x00]); // mov ecx, 10
    final start = c.length;
    _rounds(c);
    c.addAll([0xFF, dec_ecx]); // dec ecx
    c.addAll([x0f, jnz_rel]); // jnz
    final off = start - (c.length + 4);
    c.addAll([
      off & 0xFF,
      (off >> 8) & 0xFF,
      (off >> 16) & 0xFF,
      (off >> 24) & 0xFF
    ]);

    // Add State
    c.addAll([
      sse, rex_b, x0f, paddd, 0xC0, // paddd xmm0, xmm8
      sse, rex_b, x0f, paddd, 0xC9, // paddd xmm1, xmm9
      sse, rex_b, x0f, paddd, 0xD2, // paddd xmm2, xmm10
      sse, rex_b, x0f, paddd, 0xDB, // paddd xmm3, xmm11
    ]);

    // Write Output
    c.addAll([
      rex_b, x0f, movups_st, 0x45, 0x00, // movups [r13], xmm0
      rex_b, x0f, movups_st, 0x4D, 0x10, // movups [r13+16], xmm1
      rex_b, x0f, movups_st, 0x55, 0x20, // movups [r13+32], xmm2
      rex_b, x0f, movups_st, 0x5D, 0x30, // movups [r13+48], xmm3
    ]);

    // Restore & Ret
    c.addAll([
      x0f, movaps, 0x74, rsp_disp, 0x00, // restore xmm6
      x0f, movaps, 0x7C, rsp_disp, 0x10, // restore xmm7
      rex_r, x0f, movaps, 0x44, rsp_disp, 0x20, // ...
      rex_r, x0f, movaps, 0x4C, rsp_disp, 0x30,
      rex_r, x0f, movaps, 0x54, rsp_disp, 0x40,
      rex_r, x0f, movaps, 0x5C, rsp_disp, 0x50,
      rex_w, add_rm64, 0xC4, 0x80, 0x00, 0x00, 0x00, // add rsp, 128
      rex_b, pop_rbp, // pop r13
      rex_b, pop_rsp, // pop r12
      pop_rbx,
      ret,
    ]);
    return Uint8List.fromList(c);
  }

  static Uint8List _genLin() {
    final c = <int>[];
    c.addAll([rex_w, sub_rm64, 0xEC, 0x18]); // sub rsp, 24

    // Load Args
    c.addAll([
      x0f, movups, 0x02, // movups xmm0, [rdx] (const)
      x0f, movups, 0x0F, // movups xmm1, [rdi] (key)
      x0f, movups, 0x57, 0x10, // movups xmm2, [rdi+16]
    ]);

    // Build XMM3 (Stack)
    c.addAll([
      0x89, 0x0C, rsp_disp, // mov [rsp], ecx (counter)
      0x8B, 0x06, // mov eax, [rsi]
      0x89, 0x44, rsp_disp, 0x04, // mov [rsp+4], eax
      0x8B, 0x46, 0x04, // mov eax, [rsi+4]
      0x89, 0x44, rsp_disp, 0x08, // mov [rsp+8], eax
      0x8B, 0x46, 0x08, // mov eax, [rsi+8]
      0x89, 0x44, rsp_disp, 0x0C, // mov [rsp+12], eax
      x0f, movups, 0x1C, rsp_disp, // movups xmm3, [rsp]
    ]);

    // Backup
    c.addAll([
      rex_r,
      x0f,
      movaps,
      0xC0,
      rex_r,
      x0f,
      movaps,
      0xC9,
      rex_r,
      x0f,
      movaps,
      0xD2,
      rex_r,
      x0f,
      movaps,
      0xDB,
      mov_ecx,
      0x0A,
      0x00,
      0x00,
      0x00,
    ]);

    final start = c.length;
    _rounds(c);
    c.addAll([0xFF, dec_ecx, x0f, jnz_rel]);
    final off = start - (c.length + 4);
    c.addAll([
      off & 0xFF,
      (off >> 8) & 0xFF,
      (off >> 16) & 0xFF,
      (off >> 24) & 0xFF
    ]);

    // Add
    c.addAll([
      sse,
      rex_b,
      x0f,
      paddd,
      0xC0,
      sse,
      rex_b,
      x0f,
      paddd,
      0xC9,
      sse,
      rex_b,
      x0f,
      paddd,
      0xD2,
      sse,
      rex_b,
      x0f,
      paddd,
      0xDB,
    ]);

    // Out
    c.addAll([
      rex_b, x0f, movups_st, 0x00, // [r8]
      rex_b, x0f, movups_st, 0x48, 0x10, // [r8+16]
      rex_b, x0f, movups_st, 0x50, 0x20, // [r8+32]
      rex_b, x0f, movups_st, 0x58, 0x30, // [r8+48]
    ]);

    c.addAll([rex_w, add_rm64, 0xC4, 0x18, ret]);
    return Uint8List.fromList(c);
  }

  static void _rounds(List<int> c) {
    _qr(c); // Column
    // Diagonal Rotations
    c.addAll([sse, x0f, pshufd, 0xC9, 0x39]);
    c.addAll([sse, x0f, pshufd, 0xD2, 0x4E]);
    c.addAll([sse, x0f, pshufd, 0xDB, 0x93]);
    _qr(c); // Diagonal
    // Undo Rotations
    c.addAll([sse, x0f, pshufd, 0xC9, 0x93]);
    c.addAll([sse, x0f, pshufd, 0xD2, 0x4E]);
    c.addAll([sse, x0f, pshufd, 0xDB, 0x39]);
  }

  static void _qr(List<int> c) {
    // a+=b; d^=a; d<<<=16
    c.addAll([sse, x0f, paddd, 0xC1]);
    c.addAll([sse, x0f, pxor, 0xD8]);
    c.addAll([sse, x0f, movdqa, 0xE3]);
    c.addAll([sse, x0f, shift_imm, 0xF4, 0x10]); // pslld
    c.addAll([sse, x0f, shift_imm, 0xD3, 0x10]); // psrld
    c.addAll([sse, x0f, por, 0xDC]);

    // c+=d; b^=c; b<<<=12
    c.addAll([sse, x0f, paddd, 0xD3]);
    c.addAll([sse, x0f, pxor, 0xCA]);
    c.addAll([sse, x0f, movdqa, 0xE1]);
    c.addAll([sse, x0f, shift_imm, 0xF4, 0x0C]);
    c.addAll([sse, x0f, shift_imm, 0xD1, 0x14]);
    c.addAll([sse, x0f, por, 0xCC]);

    // a+=b; d^=a; d<<<=8
    c.addAll([sse, x0f, paddd, 0xC1]);
    c.addAll([sse, x0f, pxor, 0xD8]);
    c.addAll([sse, x0f, movdqa, 0xE3]);
    c.addAll([sse, x0f, shift_imm, 0xF4, 0x08]);
    c.addAll([sse, x0f, shift_imm, 0xD3, 0x18]);
    c.addAll([sse, x0f, por, 0xDC]);

    // c+=d; b^=c; b<<<=7
    c.addAll([sse, x0f, paddd, 0xD3]);
    c.addAll([sse, x0f, pxor, 0xCA]);
    c.addAll([sse, x0f, movdqa, 0xE1]);
    c.addAll([sse, x0f, shift_imm, 0xF4, 0x07]);
    c.addAll([sse, x0f, shift_imm, 0xD1, 0x19]);
    c.addAll([sse, x0f, por, 0xCC]);
  }
}
