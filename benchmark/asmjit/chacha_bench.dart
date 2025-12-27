import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'impl/chacha20_asmjit.dart';

typedef _ChaCha20XorNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Uint64,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Uint32,
);
typedef _ChaCha20Xor = void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

class BenchResult {
  final String name;
  final int iterations;
  final double nsPerOp;
  final double mibPerSec;

  BenchResult(this.name, this.iterations, this.nsPerOp, this.mibPerSec);

  void print() {
    final ns = nsPerOp.toStringAsFixed(1).padLeft(10);
    final mib =
        mibPerSec > 0 ? mibPerSec.toStringAsFixed(1).padLeft(10) : '      N/A';
    stdout.writeln('  ${name.padRight(38)} | $ns ns/op | $mib MiB/s');
  }
}

BenchResult runBench(
  String name,
  int iterations,
  int bytesPerIter,
  void Function() fn,
) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    fn();
  }
  sw.stop();
  final totalNs = sw.elapsedMicroseconds * 1000.0;
  final nsPerOp = totalNs / iterations;
  final mibPerSec = bytesPerIter > 0
      ? (bytesPerIter * iterations) / (1024 * 1024) / (totalNs / 1e9)
      : 0.0;
  return BenchResult(name, iterations, nsPerOp, mibPerSec);
}

ffi.DynamicLibrary? _tryLoadChachaDll() {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final sep = Platform.pathSeparator;
  final dllPath = '${scriptDir.path}${sep}native${sep}chacha20_bench.dll';
  final file = File(dllPath);
  if (!file.existsSync()) {
    return null;
  }
  return ffi.DynamicLibrary.open(dllPath);
}

int _rotl32(int v, int c) {
  final v32 = v & 0xFFFFFFFF;
  return ((v32 << c) | (v32 >> (32 - c))) & 0xFFFFFFFF;
}

int _load32(Uint8List data, int offset) {
  return (data[offset]) |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

void _store32(Uint8List data, int offset, int v) {
  data[offset] = v & 0xFF;
  data[offset + 1] = (v >> 8) & 0xFF;
  data[offset + 2] = (v >> 16) & 0xFF;
  data[offset + 3] = (v >> 24) & 0xFF;
}

class ChaChaBaseline {
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  final List<int> _keyWords;
  final List<int> _nonceWords;
  final int initialCounter;
  final int rounds;

  ChaChaBaseline(
    Uint8List key,
    Uint8List nonce, {
    this.initialCounter = 0,
    this.rounds = 20,
  })  : _keyWords = _bytesToWordList(key),
        _nonceWords = _bytesToWordList(nonce) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be 12 bytes');
    }
  }

  static List<int> _bytesToWordList(Uint8List data) {
    if (data.length % 4 != 0) {
      throw ArgumentError('Input length must be multiple of 4');
    }
    final words = <int>[];
    final byteData =
        ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      words.add(byteData.getUint32(i, Endian.little));
    }
    return words;
  }

  static void _quarterRound(List<int> x, int a, int b, int c, int d) {
    x[a] = (x[a] + x[b]) & 0xFFFFFFFF;
    x[d] ^= x[a];
    x[d] = _rotl32(x[d], 16);

    x[c] = (x[c] + x[d]) & 0xFFFFFFFF;
    x[b] ^= x[c];
    x[b] = _rotl32(x[b], 12);

    x[a] = (x[a] + x[b]) & 0xFFFFFFFF;
    x[d] ^= x[a];
    x[d] = _rotl32(x[d], 8);

    x[c] = (x[c] + x[d]) & 0xFFFFFFFF;
    x[b] ^= x[c];
    x[b] = _rotl32(x[b], 7);
  }

  static List<int> _chachaBlock(
    List<int> keyWords,
    int counter,
    List<int> nonceWords,
    int rounds,
  ) {
    final state = List<int>.filled(16, 0);
    state.setRange(0, 4, _constants);
    state.setRange(4, 12, keyWords);
    state[12] = counter & 0xFFFFFFFF;
    state.setRange(13, 16, nonceWords);

    final working = List<int>.from(state, growable: false);
    for (var i = 0; i < rounds ~/ 2; i++) {
      _quarterRound(working, 0, 4, 8, 12);
      _quarterRound(working, 1, 5, 9, 13);
      _quarterRound(working, 2, 6, 10, 14);
      _quarterRound(working, 3, 7, 11, 15);
      _quarterRound(working, 0, 5, 10, 15);
      _quarterRound(working, 1, 6, 11, 12);
      _quarterRound(working, 2, 7, 8, 13);
      _quarterRound(working, 3, 4, 9, 14);
    }

    for (var i = 0; i < 16; i++) {
      working[i] = (working[i] + state[i]) & 0xFFFFFFFF;
    }
    return working;
  }

  static Uint8List _wordListToBytes(List<int> state) {
    final out = Uint8List(64);
    final data = ByteData.sublistView(out);
    for (var i = 0; i < 16; i++) {
      data.setUint32(i * 4, state[i], Endian.little);
    }
    return out;
  }

  void xor(Uint8List input, Uint8List output) {
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    const blockSize = 64;
    var counter = initialCounter;
    var offset = 0;

    while (offset < input.length) {
      final ksWords = _chachaBlock(_keyWords, counter, _nonceWords, rounds);
      final ksBytes = _wordListToBytes(ksWords);
      counter++;

      final chunk = min(blockSize, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ ksBytes[i];
      }
      offset += chunk;
    }
  }
}

class ChaChaOptimized {
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  final Uint32List _keyWords = Uint32List(8);
  final Uint32List _nonceWords = Uint32List(3);
  final Uint32List _state = Uint32List(16);
  final Uint32List _working = Uint32List(16);
  final Uint8List _block = Uint8List(64);
  late final ByteData _blockData;
  final int initialCounter;

  ChaChaOptimized(Uint8List key, Uint8List nonce, {this.initialCounter = 0}) {
    _blockData = ByteData.sublistView(_block);
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be 12 bytes');
    }

    for (var i = 0; i < 8; i++) {
      _keyWords[i] = _load32(key, i * 4);
    }
    for (var i = 0; i < 3; i++) {
      _nonceWords[i] = _load32(nonce, i * 4);
    }
  }

  void _quarterRound(int a, int b, int c, int d) {
    _working[a] = (_working[a] + _working[b]) & 0xFFFFFFFF;
    _working[d] = _working[d] ^ _working[a];
    _working[d] = _rotl32(_working[d], 16);

    _working[c] = (_working[c] + _working[d]) & 0xFFFFFFFF;
    _working[b] = _working[b] ^ _working[c];
    _working[b] = _rotl32(_working[b], 12);

    _working[a] = (_working[a] + _working[b]) & 0xFFFFFFFF;
    _working[d] = _working[d] ^ _working[a];
    _working[d] = _rotl32(_working[d], 8);

    _working[c] = (_working[c] + _working[d]) & 0xFFFFFFFF;
    _working[b] = _working[b] ^ _working[c];
    _working[b] = _rotl32(_working[b], 7);
  }

  void _processBlock(int counter) {
    _state[0] = _constants[0];
    _state[1] = _constants[1];
    _state[2] = _constants[2];
    _state[3] = _constants[3];
    for (var i = 0; i < 8; i++) {
      _state[4 + i] = _keyWords[i];
    }
    _state[12] = counter & 0xFFFFFFFF;
    _state[13] = _nonceWords[0];
    _state[14] = _nonceWords[1];
    _state[15] = _nonceWords[2];

    for (var i = 0; i < 16; i++) {
      _working[i] = _state[i];
    }

    for (var i = 0; i < 10; i++) {
      _quarterRound(0, 4, 8, 12);
      _quarterRound(1, 5, 9, 13);
      _quarterRound(2, 6, 10, 14);
      _quarterRound(3, 7, 11, 15);
      _quarterRound(0, 5, 10, 15);
      _quarterRound(1, 6, 11, 12);
      _quarterRound(2, 7, 8, 13);
      _quarterRound(3, 4, 9, 14);
    }

    for (var i = 0; i < 16; i++) {
      final v = (_working[i] + _state[i]) & 0xFFFFFFFF;
      _blockData.setUint32(i * 4, v, Endian.little);
    }
  }

  void xor(Uint8List input, Uint8List output) {
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    var counter = initialCounter;
    var offset = 0;
    while (offset < input.length) {
      _processBlock(counter);
      counter++;
      final chunk = min(64, input.length - offset);
      for (var i = 0; i < chunk; i++) {
        output[offset + i] = input[offset + i] ^ _block[i];
      }
      offset += chunk;
    }
  }
}

class ChaChaPointer {
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  final ffi.Pointer<ffi.Uint32> _keyWords;
  final ffi.Pointer<ffi.Uint32> _nonceWords;
  final ffi.Pointer<ffi.Uint32> _state;
  final ffi.Pointer<ffi.Uint32> _working;
  final ffi.Pointer<ffi.Uint8> _blockBuffer;
  final int initialCounter;

  ChaChaPointer(Uint8List key, Uint8List nonce, {this.initialCounter = 0})
      : _keyWords = pkgffi.calloc<ffi.Uint32>(8),
        _nonceWords = pkgffi.calloc<ffi.Uint32>(3),
        _state = pkgffi.calloc<ffi.Uint32>(16),
        _working = pkgffi.calloc<ffi.Uint32>(16),
        _blockBuffer = pkgffi.calloc<ffi.Uint8>(64) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes');
    }
    if (nonce.length != 12) {
      throw ArgumentError('Nonce must be 12 bytes');
    }

    for (var i = 0; i < 8; i++) {
      _keyWords[i] = _load32(key, i * 4);
    }
    for (var i = 0; i < 3; i++) {
      _nonceWords[i] = _load32(nonce, i * 4);
    }
  }

  void dispose() {
    pkgffi.calloc.free(_keyWords);
    pkgffi.calloc.free(_nonceWords);
    pkgffi.calloc.free(_state);
    pkgffi.calloc.free(_working);
    pkgffi.calloc.free(_blockBuffer);
  }

  void _quarterRound(int a, int b, int c, int d) {
    var va = _working[a];
    var vb = _working[b];
    var vc = _working[c];
    var vd = _working[d];

    va = (va + vb) & 0xFFFFFFFF;
    vd ^= va;
    vd = _rotl32(vd, 16);

    vc = (vc + vd) & 0xFFFFFFFF;
    vb ^= vc;
    vb = _rotl32(vb, 12);

    va = (va + vb) & 0xFFFFFFFF;
    vd ^= va;
    vd = _rotl32(vd, 8);

    vc = (vc + vd) & 0xFFFFFFFF;
    vb ^= vc;
    vb = _rotl32(vb, 7);

    _working[a] = va;
    _working[b] = vb;
    _working[c] = vc;
    _working[d] = vd;
  }

  void _processBlock(int counter) {
    _state[0] = _constants[0];
    _state[1] = _constants[1];
    _state[2] = _constants[2];
    _state[3] = _constants[3];
    for (var i = 0; i < 8; i++) {
      _state[4 + i] = _keyWords[i];
    }
    _state[12] = counter & 0xFFFFFFFF;
    _state[13] = _nonceWords[0];
    _state[14] = _nonceWords[1];
    _state[15] = _nonceWords[2];

    for (var i = 0; i < 16; i++) {
      _working[i] = _state[i];
    }

    for (var i = 0; i < 10; i++) {
      _quarterRound(0, 4, 8, 12);
      _quarterRound(1, 5, 9, 13);
      _quarterRound(2, 6, 10, 14);
      _quarterRound(3, 7, 11, 15);
      _quarterRound(0, 5, 10, 15);
      _quarterRound(1, 6, 11, 12);
      _quarterRound(2, 7, 8, 13);
      _quarterRound(3, 4, 9, 14);
    }

    for (var i = 0; i < 16; i++) {
      final v = (_working[i] + _state[i]) & 0xFFFFFFFF;
      _blockBuffer[i * 4 + 0] = v & 0xFF;
      _blockBuffer[i * 4 + 1] = (v >> 8) & 0xFF;
      _blockBuffer[i * 4 + 2] = (v >> 16) & 0xFF;
      _blockBuffer[i * 4 + 3] = (v >> 24) & 0xFF;
    }
  }

  void xor(
    ffi.Pointer<ffi.Uint8> input,
    ffi.Pointer<ffi.Uint8> output,
    int length,
  ) {
    var counter = initialCounter;
    var offset = 0;
    while (offset < length) {
      _processBlock(counter);
      counter++;
      final chunk = min(64, length - offset);
      for (var i = 0; i < chunk; i++) {
        final v = input[offset + i] ^ _blockBuffer[i];
        output[offset + i] = v;
      }
      offset += chunk;
    }
  }
}

class ChaChaSimd {
  static const List<int> _constants = [
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
  ];

  final Uint32List _keyWords = Uint32List(8);
  final Uint32List _nonceWords = Uint32List(3);
  final int initialCounter;
  final ChaChaOptimized _fallback;
  final Uint8List _block4 = Uint8List(256);

  ChaChaSimd(Uint8List key, Uint8List nonce, {this.initialCounter = 0})
      : _fallback =
            ChaChaOptimized(key, nonce, initialCounter: initialCounter) {
    for (var i = 0; i < 8; i++) {
      _keyWords[i] = _load32(key, i * 4);
    }
    for (var i = 0; i < 3; i++) {
      _nonceWords[i] = _load32(nonce, i * 4);
    }
  }

  static Int32x4 _shr(Int32x4 v, int n) {
    if (n == 0) return v;
    return Int32x4(
      v.x >>> n,
      v.y >>> n,
      v.z >>> n,
      v.w >>> n,
    );
  }

  static Int32x4 _shl(Int32x4 v, int n) {
    if (n == 0) return v;
    return Int32x4(
      v.x << n,
      v.y << n,
      v.z << n,
      v.w << n,
    );
  }

  static Int32x4 _rotl(Int32x4 v, int c) {
    return _shl(v, c) | _shr(v, 32 - c);
  }

  void _quarterRound(
    List<Int32x4> v,
    int a,
    int b,
    int c,
    int d,
  ) {
    v[a] = v[a] + v[b];
    v[d] = v[d] ^ v[a];
    v[d] = _rotl(v[d], 16);

    v[c] = v[c] + v[d];
    v[b] = v[b] ^ v[c];
    v[b] = _rotl(v[b], 12);

    v[a] = v[a] + v[b];
    v[d] = v[d] ^ v[a];
    v[d] = _rotl(v[d], 8);

    v[c] = v[c] + v[d];
    v[b] = v[b] ^ v[c];
    v[b] = _rotl(v[b], 7);
  }

  static Int32x4 _splat(int v) => Int32x4(v, v, v, v);

  void _processBlock4(int counter) {
    var v = List<Int32x4>.filled(16, Int32x4(0, 0, 0, 0));
    v[0] = _splat(_constants[0]);
    v[1] = _splat(_constants[1]);
    v[2] = _splat(_constants[2]);
    v[3] = _splat(_constants[3]);

    for (var i = 0; i < 8; i++) {
      v[4 + i] = _splat(_keyWords[i]);
    }

    v[12] = Int32x4(
      counter,
      counter + 1,
      counter + 2,
      counter + 3,
    );
    v[13] = _splat(_nonceWords[0]);
    v[14] = _splat(_nonceWords[1]);
    v[15] = _splat(_nonceWords[2]);

    final start = List<Int32x4>.from(v);
    for (var i = 0; i < 10; i++) {
      _quarterRound(v, 0, 4, 8, 12);
      _quarterRound(v, 1, 5, 9, 13);
      _quarterRound(v, 2, 6, 10, 14);
      _quarterRound(v, 3, 7, 11, 15);
      _quarterRound(v, 0, 5, 10, 15);
      _quarterRound(v, 1, 6, 11, 12);
      _quarterRound(v, 2, 7, 8, 13);
      _quarterRound(v, 3, 4, 9, 14);
    }

    for (var i = 0; i < 16; i++) {
      v[i] = v[i] + start[i];
    }

    for (var lane = 0; lane < 4; lane++) {
      final base = lane * 64;
      for (var i = 0; i < 16; i++) {
        final word = switch (lane) {
          0 => v[i].x,
          1 => v[i].y,
          2 => v[i].z,
          _ => v[i].w,
        };
        _store32(_block4, base + i * 4, word);
      }
    }
  }

  void xor(Uint8List input, Uint8List output) {
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    var counter = initialCounter;
    var offset = 0;

    while (offset + 256 <= input.length) {
      _processBlock4(counter);
      for (var i = 0; i < 256; i++) {
        output[offset + i] = input[offset + i] ^ _block4[i];
      }
      counter += 4;
      offset += 256;
    }

    if (offset < input.length) {
      final tailIn = input.sublist(offset);
      final tailOut = Uint8List(tailIn.length);
      _fallback.xor(tailIn, tailOut);
      output.setAll(offset, tailOut);
    }
  }
}

class ChaChaInlineAsmSupport {
  static bool? _sse2Supported;

  static bool get isSse2Supported {
    _sse2Supported ??= _checkSse2Support();
    return _sse2Supported!;
  }

  static bool _checkSse2Support() {
    if (!Platform.isWindows && !Platform.isLinux) return false;
    try {
      final code = Uint8List.fromList([
        0x53,
        0xB8,
        0x01,
        0x00,
        0x00,
        0x00,
        0x0F,
        0xA2,
        0x89,
        0xD0,
        0xC1,
        0xE8,
        0x1A,
        0x83,
        0xE0,
        0x01,
        0x5B,
        0xC3,
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

class ExecutableMemory {
  final ffi.Pointer<ffi.Void> pointer;
  final int size;
  bool _freed = false;

  ExecutableMemory._(this.pointer, this.size);

  static ExecutableMemory allocate(Uint8List code) {
    final ptr = _allocateExecutableMemory(code.length + 64);
    if (ptr == ffi.nullptr) {
      throw StateError('Executable alloc failed');
    }
    final codePtr = ptr.cast<ffi.Uint8>();
    for (var i = 0; i < code.length; i++) {
      codePtr[i] = code[i];
    }
    return ExecutableMemory._(ptr, code.length + 64);
  }

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
      return virtualAlloc(ffi.nullptr, size, 0x3000, 0x40);
    } else {
      final libc = ffi.DynamicLibrary.open('libc.so.6');
      final mmap = libc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.IntPtr,
              ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int64),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>, int, int, int, int, int)>('mmap');
      return mmap(ffi.nullptr, size, 0x7, 0x22, -1, 0);
    }
  }

  static void _freeExecutableMemory(ffi.Pointer<ffi.Void> ptr, int size) {
    if (Platform.isWindows) {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final virtualFree = kernel32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr, ffi.Uint32),
          int Function(ffi.Pointer<ffi.Void>, int, int)>('VirtualFree');
      virtualFree(ptr, 0, 0x8000);
    } else {
      final libc = ffi.DynamicLibrary.open('libc.so.6');
      final munmap = libc.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr),
          int Function(ffi.Pointer<ffi.Void>, int)>('munmap');
      munmap(ptr, size);
    }
  }
}

class ChaChaAsmBytes {
  static Uint8List codeBytes() {
    return Platform.isWindows ? _windowsCode() : _linuxCode();
  }

  // Windows x64: RCX=key, RDX=nonce, R8=constants, R9=counter, [RSP+40]=output
  static Uint8List _windowsCode() {
    final code = <int>[];
    code.addAll([
      0x53,
      0x41,
      0x54,
      0x41,
      0x55,
      0x48,
      0x81,
      0xEC,
      0x80,
      0x00,
      0x00,
      0x00,
      0x0F,
      0x29,
      0x74,
      0x24,
      0x00,
      0x0F,
      0x29,
      0x7C,
      0x24,
      0x10,
      0x44,
      0x0F,
      0x29,
      0x44,
      0x24,
      0x20,
      0x44,
      0x0F,
      0x29,
      0x4C,
      0x24,
      0x30,
      0x44,
      0x0F,
      0x29,
      0x54,
      0x24,
      0x40,
      0x44,
      0x0F,
      0x29,
      0x5C,
      0x24,
      0x50,
      0x48,
      0x89,
      0xCB,
      0x49,
      0x89,
      0xD2,
      0x4D,
      0x89,
      0xC3,
      0x45,
      0x89,
      0xCC,
      0x4C,
      0x8B,
      0xAC,
      0x24,
      0xC0,
      0x00,
      0x00,
      0x00,
      0x41,
      0x0F,
      0x10,
      0x03,
      0x0F,
      0x10,
      0x0B,
      0x0F,
      0x10,
      0x53,
      0x10,
      0x44,
      0x89,
      0x64,
      0x24,
      0x60,
      0x41,
      0x8B,
      0x02,
      0x89,
      0x44,
      0x24,
      0x64,
      0x41,
      0x8B,
      0x42,
      0x04,
      0x89,
      0x44,
      0x24,
      0x68,
      0x41,
      0x8B,
      0x42,
      0x08,
      0x89,
      0x44,
      0x24,
      0x6C,
      0x0F,
      0x10,
      0x5C,
      0x24,
      0x60,
      0x44,
      0x0F,
      0x28,
      0xC0,
      0x44,
      0x0F,
      0x28,
      0xC9,
      0x44,
      0x0F,
      0x28,
      0xD2,
      0x44,
      0x0F,
      0x28,
      0xDB,
      0xB9,
      0x0A,
      0x00,
      0x00,
      0x00,
    ]);

    final loopStart = code.length;
    _addDoubleRound(code);
    code.addAll([0xFF, 0xC9]);
    code.addAll([0x0F, 0x85]);
    final offset = loopStart - (code.length + 4);
    code.addAll([
      offset & 0xFF,
      (offset >> 8) & 0xFF,
      (offset >> 16) & 0xFF,
      (offset >> 24) & 0xFF,
    ]);

    code.addAll([
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xC0,
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xC9,
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xD2,
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xDB,
      0x41,
      0x0F,
      0x11,
      0x45,
      0x00,
      0x41,
      0x0F,
      0x11,
      0x4D,
      0x10,
      0x41,
      0x0F,
      0x11,
      0x55,
      0x20,
      0x41,
      0x0F,
      0x11,
      0x5D,
      0x30,
      0x0F,
      0x28,
      0x74,
      0x24,
      0x00,
      0x0F,
      0x28,
      0x7C,
      0x24,
      0x10,
      0x44,
      0x0F,
      0x28,
      0x44,
      0x24,
      0x20,
      0x44,
      0x0F,
      0x28,
      0x4C,
      0x24,
      0x30,
      0x44,
      0x0F,
      0x28,
      0x54,
      0x24,
      0x40,
      0x44,
      0x0F,
      0x28,
      0x5C,
      0x24,
      0x50,
      0x48,
      0x81,
      0xC4,
      0x80,
      0x00,
      0x00,
      0x00,
      0x41,
      0x5D,
      0x41,
      0x5C,
      0x5B,
      0xC3,
    ]);

    return Uint8List.fromList(code);
  }

  // Linux SysV: RDI=key, RSI=nonce, RDX=constants, RCX=counter, R8=output
  static Uint8List _linuxCode() {
    final code = <int>[];
    code.addAll([0x48, 0x83, 0xEC, 0x18]);
    code.addAll([
      0x0F,
      0x10,
      0x02,
      0x0F,
      0x10,
      0x0F,
      0x0F,
      0x10,
      0x57,
      0x10,
      0x89,
      0x0C,
      0x24,
      0x8B,
      0x06,
      0x89,
      0x44,
      0x24,
      0x04,
      0x8B,
      0x46,
      0x04,
      0x89,
      0x44,
      0x24,
      0x08,
      0x8B,
      0x46,
      0x08,
      0x89,
      0x44,
      0x24,
      0x0C,
      0x0F,
      0x10,
      0x1C,
      0x24,
      0x44,
      0x0F,
      0x28,
      0xC0,
      0x44,
      0x0F,
      0x28,
      0xC9,
      0x44,
      0x0F,
      0x28,
      0xD2,
      0x44,
      0x0F,
      0x28,
      0xDB,
      0xB9,
      0x0A,
      0x00,
      0x00,
      0x00,
    ]);

    final loopStart = code.length;
    _addDoubleRound(code);
    code.addAll([0xFF, 0xC9]);
    code.addAll([0x0F, 0x85]);
    final offset = loopStart - (code.length + 4);
    code.addAll([
      offset & 0xFF,
      (offset >> 8) & 0xFF,
      (offset >> 16) & 0xFF,
      (offset >> 24) & 0xFF,
    ]);

    code.addAll([
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xC0,
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xC9,
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xD2,
      0x66,
      0x41,
      0x0F,
      0xFE,
      0xDB,
      0x41,
      0x0F,
      0x11,
      0x00,
      0x41,
      0x0F,
      0x11,
      0x48,
      0x10,
      0x41,
      0x0F,
      0x11,
      0x50,
      0x20,
      0x41,
      0x0F,
      0x11,
      0x58,
      0x30,
      0x48,
      0x83,
      0xC4,
      0x18,
      0xC3,
    ]);

    return Uint8List.fromList(code);
  }

  static void _addDoubleRound(List<int> code) {
    _addQuarterRound(code);
    code.addAll([0x66, 0x0F, 0x70, 0xC9, 0x39]);
    code.addAll([0x66, 0x0F, 0x70, 0xD2, 0x4E]);
    code.addAll([0x66, 0x0F, 0x70, 0xDB, 0x93]);
    _addQuarterRound(code);
    code.addAll([0x66, 0x0F, 0x70, 0xC9, 0x93]);
    code.addAll([0x66, 0x0F, 0x70, 0xD2, 0x4E]);
    code.addAll([0x66, 0x0F, 0x70, 0xDB, 0x39]);
  }

  static void _addQuarterRound(List<int> code) {
    code.addAll([0x66, 0x0F, 0xFE, 0xC1]);
    code.addAll([0x66, 0x0F, 0xEF, 0xD8]);
    code.addAll([
      0x66,
      0x0F,
      0x6F,
      0xE3,
      0x66,
      0x0F,
      0x72,
      0xF4,
      0x10,
      0x66,
      0x0F,
      0x72,
      0xD3,
      0x10,
      0x66,
      0x0F,
      0xEB,
      0xDC,
    ]);
    code.addAll([0x66, 0x0F, 0xFE, 0xD3]);
    code.addAll([0x66, 0x0F, 0xEF, 0xCA]);
    code.addAll([
      0x66,
      0x0F,
      0x6F,
      0xE1,
      0x66,
      0x0F,
      0x72,
      0xF4,
      0x0C,
      0x66,
      0x0F,
      0x72,
      0xD1,
      0x14,
      0x66,
      0x0F,
      0xEB,
      0xCC,
    ]);
    code.addAll([0x66, 0x0F, 0xFE, 0xC1]);
    code.addAll([0x66, 0x0F, 0xEF, 0xD8]);
    code.addAll([
      0x66,
      0x0F,
      0x6F,
      0xE3,
      0x66,
      0x0F,
      0x72,
      0xF4,
      0x08,
      0x66,
      0x0F,
      0x72,
      0xD3,
      0x18,
      0x66,
      0x0F,
      0xEB,
      0xDC,
    ]);
    code.addAll([0x66, 0x0F, 0xFE, 0xD3]);
    code.addAll([0x66, 0x0F, 0xEF, 0xCA]);
    code.addAll([
      0x66,
      0x0F,
      0x6F,
      0xE1,
      0x66,
      0x0F,
      0x72,
      0xF4,
      0x07,
      0x66,
      0x0F,
      0x72,
      0xD1,
      0x19,
      0x66,
      0x0F,
      0xEB,
      0xCC,
    ]);
  }
}

class ChaChaInlineAsm {
  static final Uint8List _constants = Uint8List.fromList([
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
    0x6b,
  ]);

  final Uint8List _key;
  final Uint8List _nonce;
  final int initialCounter;

  static ExecutableMemory? _codeMemory;
  static void Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>)? _blockFunc;

  ChaChaInlineAsm(this._key, this._nonce, {this.initialCounter = 0}) {
    if (_key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (_nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');
    _ensureInitialized();
  }

  static void _ensureInitialized() {
    if (_codeMemory != null) return;
    if (!ChaChaInlineAsmSupport.isSse2Supported) {
      throw UnsupportedError('SSE2 not supported');
    }
    _codeMemory = ExecutableMemory.allocate(ChaChaAsmBytes.codeBytes());
    final funcPtr = _codeMemory!.pointer.cast<
        ffi.NativeFunction<
            ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
                ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>)>>();
    _blockFunc = funcPtr.asFunction();
  }

  ffi.Pointer<ffi.Uint8>? _keyPtr;
  ffi.Pointer<ffi.Uint8>? _noncePtr;
  ffi.Pointer<ffi.Uint8>? _constantsPtr;
  ffi.Pointer<ffi.Uint8>? _outputPtr;
  final Uint8List _keystream = Uint8List(64);

  void _initPtrs() {
    if (_keyPtr != null) return;
    _keyPtr = pkgffi.calloc<ffi.Uint8>(32);
    _noncePtr = pkgffi.calloc<ffi.Uint8>(12);
    _constantsPtr = pkgffi.calloc<ffi.Uint8>(16);
    _outputPtr = pkgffi.calloc<ffi.Uint8>(64);
    for (var i = 0; i < 32; i++) _keyPtr![i] = _key[i];
    for (var i = 0; i < 12; i++) _noncePtr![i] = _nonce[i];
    for (var i = 0; i < 16; i++) _constantsPtr![i] = _constants[i];
  }

  void _generateBlock(int counter) {
    _initPtrs();
    _blockFunc!(_keyPtr!, _noncePtr!, _constantsPtr!, counter, _outputPtr!);
    for (var i = 0; i < 64; i++) {
      _keystream[i] = _outputPtr![i];
    }
  }

  void xor(Uint8List input, Uint8List output) {
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    var offset = 0;
    var counter = initialCounter;
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

  void dispose() {
    if (_keyPtr == null) return;
    pkgffi.calloc.free(_keyPtr!);
    pkgffi.calloc.free(_noncePtr!);
    pkgffi.calloc.free(_constantsPtr!);
    pkgffi.calloc.free(_outputPtr!);
    _keyPtr = null;
  }
}

class ChaChaAsmJit extends ChaCha20AsmJit {
  ChaChaAsmJit(Uint8List key, Uint8List nonce, {int initialCounter = 0})
      : super(key, nonce, initialCounter: initialCounter);
}

void main(List<String> args) {
  final quick = args.contains('--quick');
  final sizes = [64, 256, 1024, 4096, 16384, 65536];

  stdout.writeln('ChaCha20 Bench (C / Dart / FFI / ASM / SIMD)');
  stdout.writeln('Mode: ${quick ? "quick" : "full"}');
  stdout.writeln('');

  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final nonce = Uint8List.fromList(List.generate(12, (i) => 0xA0 + i));

  final baseline = ChaChaBaseline(key, nonce);
  final optimized = ChaChaOptimized(key, nonce);
  final simd = ChaChaSimd(key, nonce);
  final pointer = ChaChaPointer(key, nonce);

  ChaChaInlineAsm? inlineAsm;
  ChaChaAsmJit? asmjit;
  if (ChaChaInlineAsmSupport.isSse2Supported) {
    inlineAsm = ChaChaInlineAsm(key, nonce);
    asmjit = ChaChaAsmJit(key, nonce);
  }

  final benchLib = _tryLoadChachaDll();
  _ChaCha20Xor? cXor;
  if (benchLib != null) {
    cXor = benchLib
        .lookupFunction<_ChaCha20XorNative, _ChaCha20Xor>('chacha20_xor');
  }

  for (final size in sizes) {
    final input = Uint8List.fromList(List.generate(size, (i) => i & 0xFF));
    final output = Uint8List(size);
    final output2 = Uint8List(size);
    final output3 = Uint8List(size);

    final iterations =
        quick ? (size <= 1024 ? 2000 : 200) : (size <= 1024 ? 20000 : 2000);

    stdout.writeln('Size: $size bytes');

    // Baseline.
    runBench('Dart baseline', iterations, size, () {
      baseline.xor(input, output);
    }).print();

    // Optimized.
    runBench('Dart optimized', iterations, size, () {
      optimized.xor(input, output2);
    }).print();

    // SIMD API.
    runBench('Dart SIMD (Int32x4)', iterations, size, () {
      simd.xor(input, output3);
    }).print();

    // Pointer version.
    final nativeIn = pkgffi.calloc<ffi.Uint8>(size);
    final nativeOut = pkgffi.calloc<ffi.Uint8>(size);
    nativeIn.asTypedList(size).setAll(0, input);

    runBench('Dart FFI pointers', iterations, size, () {
      pointer.xor(nativeIn, nativeOut, size);
    }).print();

    pkgffi.calloc.free(nativeIn);
    pkgffi.calloc.free(nativeOut);

    // Inline asm.
    if (inlineAsm != null) {
      runBench('Inline asm bytes (SSE2)', iterations, size, () {
        inlineAsm!.xor(input, output);
      }).print();
    } else {
      stdout.writeln('  Inline asm bytes (SSE2)         | N/A (no SSE2)');
    }

    // asmjit (bytes stub).
    if (asmjit != null) {
      runBench('AsmJit JIT bytes (SSE2)', iterations, size, () {
        asmjit!.xor(input, output);
      }).print();
    } else {
      stdout.writeln('  AsmJit JIT bytes (SSE2)          | N/A (no SSE2)');
    }

    // C DLL.
    if (cXor != null) {
      final cin = pkgffi.calloc<ffi.Uint8>(size);
      final cout = pkgffi.calloc<ffi.Uint8>(size);
      final ckey = pkgffi.calloc<ffi.Uint8>(32);
      final cnonce = pkgffi.calloc<ffi.Uint8>(12);
      cin.asTypedList(size).setAll(0, input);
      ckey.asTypedList(32).setAll(0, key);
      cnonce.asTypedList(12).setAll(0, nonce);

      runBench('C DLL (chacha20_xor)', iterations, size, () {
        cXor!(cout, cin, size, ckey, cnonce, 0);
      }).print();

      pkgffi.calloc.free(cin);
      pkgffi.calloc.free(cout);
      pkgffi.calloc.free(ckey);
      pkgffi.calloc.free(cnonce);
    } else {
      stdout.writeln('  C DLL (chacha20_xor)             | N/A (dll missing)');
    }

    stdout.writeln('');
  }

  // Simple correctness check.
  final input = Uint8List.fromList(List.generate(1024, (i) => i & 0xFF));
  final outBase = Uint8List(1024);
  final outOpt = Uint8List(1024);
  baseline.xor(input, outBase);
  optimized.xor(input, outOpt);
  var ok = true;
  for (var i = 0; i < outBase.length; i++) {
    if (outBase[i] != outOpt[i]) {
      ok = false;
      stdout.writeln('Mismatch at $i: base=${outBase[i]} opt=${outOpt[i]}');
      break;
    }
  }
  stdout.writeln('Correctness baseline vs optimized: $ok');

  pointer.dispose();
  inlineAsm?.dispose();
  asmjit?.dispose();
}
