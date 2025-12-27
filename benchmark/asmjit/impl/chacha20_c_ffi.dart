/// ChaCha20 - Wrapper FFI para a DLL C
/// Chama a implementação C pura via dart:ffi
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;

// Tipos FFI para as funções C
typedef _ChaCha20CryptNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> output,
  ffi.Pointer<ffi.Uint8> input,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  ffi.Uint32 counter,
);

typedef _ChaCha20Crypt = void Function(
  ffi.Pointer<ffi.Uint8> output,
  ffi.Pointer<ffi.Uint8> input,
  int length,
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  int counter,
);

typedef _ChaCha20CryptUnrollNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> output,
  ffi.Pointer<ffi.Uint8> input,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  ffi.Uint32 counter,
);

typedef _ChaCha20CryptUnroll = void Function(
  ffi.Pointer<ffi.Uint8> output,
  ffi.Pointer<ffi.Uint8> input,
  int length,
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  int counter,
);

typedef _ChaCha20BlockNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> output,
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  ffi.Uint32 counter,
);

typedef _ChaCha20Block = void Function(
  ffi.Pointer<ffi.Uint8> output,
  ffi.Pointer<ffi.Uint8> key,
  ffi.Pointer<ffi.Uint8> nonce,
  int counter,
);

typedef _ChaCha20NoopNative = ffi.Void Function();
typedef _ChaCha20Noop = void Function();

typedef _ChaCha20VersionNative = ffi.Uint32 Function();
typedef _ChaCha20Version = int Function();

/// Carrega e gerencia a DLL C do ChaCha20
class ChaCha20DLL {
  static ffi.DynamicLibrary? _lib;
  static _ChaCha20Crypt? _crypt;
  static _ChaCha20CryptUnroll? _cryptUnroll;
  static _ChaCha20Block? _block;
  static _ChaCha20Noop? _noop;
  static _ChaCha20Version? _version;
  static bool _loaded = false;
  static String? _loadError;

  /// Tenta carregar a DLL
  static bool load() {
    if (_loaded) return true;
    if (_loadError != null) return false;

    try {
      final scriptDir = File(Platform.script.toFilePath()).parent;
      final sep = Platform.pathSeparator;

      // Tenta múltiplos caminhos
      final paths = [
        '${scriptDir.path}${sep}native${sep}chacha20_impl.dll',
        '${scriptDir.path}${sep}..${sep}native${sep}chacha20_impl.dll',
        'benchmark${sep}native${sep}chacha20_impl.dll',
        'chacha20_impl.dll',
      ];

      for (final path in paths) {
        final file = File(path);
        if (file.existsSync()) {
          _lib = ffi.DynamicLibrary.open(path);
          break;
        }
      }

      if (_lib == null) {
        _loadError = 'DLL not found in: ${paths.join(", ")}';
        return false;
      }

      _crypt = _lib!.lookupFunction<_ChaCha20CryptNative, _ChaCha20Crypt>(
        'chacha20_crypt',
      );
      _cryptUnroll = _lib!
          .lookupFunction<_ChaCha20CryptUnrollNative, _ChaCha20CryptUnroll>(
        'chacha20_crypt_unroll',
      );
      _block = _lib!.lookupFunction<_ChaCha20BlockNative, _ChaCha20Block>(
        'chacha20_block_export',
      );
      _noop = _lib!.lookupFunction<_ChaCha20NoopNative, _ChaCha20Noop>(
        'chacha20_noop',
      );
      _version = _lib!.lookupFunction<_ChaCha20VersionNative, _ChaCha20Version>(
        'chacha20_version',
      );

      _loaded = true;
      return true;
    } catch (e) {
      _loadError = e.toString();
      return false;
    }
  }

  static String? get loadError => _loadError;
  static bool get isLoaded => _loaded;

  static _ChaCha20Crypt? get crypt => _crypt;
  static _ChaCha20CryptUnroll? get cryptUnroll => _cryptUnroll;
  static _ChaCha20Block? get block => _block;
  static _ChaCha20Noop? get noop => _noop;
  static _ChaCha20Version? get version => _version;
}

/// ChaCha20 usando a DLL C
class ChaCha20CLib {
  final Uint8List _key;
  final Uint8List _nonce;
  final int initialCounter;

  // Ponteiros nativos
  ffi.Pointer<ffi.Uint8>? _keyPtr;
  ffi.Pointer<ffi.Uint8>? _noncePtr;
  bool _disposed = false;

  ChaCha20CLib(this._key, this._nonce, {this.initialCounter = 0}) {
    if (_key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (_nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');

    if (!ChaCha20DLL.load()) {
      throw StateError('Failed to load ChaCha20 DLL: ${ChaCha20DLL.loadError}');
    }

    _keyPtr = pkgffi.calloc<ffi.Uint8>(32);
    _noncePtr = pkgffi.calloc<ffi.Uint8>(12);

    for (var i = 0; i < 32; i++) _keyPtr![i] = _key[i];
    for (var i = 0; i < 12; i++) _noncePtr![i] = _nonce[i];
  }

  void dispose() {
    if (_disposed) return;
    if (_keyPtr != null) pkgffi.calloc.free(_keyPtr!);
    if (_noncePtr != null) pkgffi.calloc.free(_noncePtr!);
    _disposed = true;
  }

  /// Criptografa usando a função C padrão
  Uint8List crypt(Uint8List input) {
    if (_disposed) throw StateError('Already disposed');

    final output = Uint8List(input.length);
    cryptInto(input, output);
    return output;
  }

  /// Versão que escreve em buffer existente
  void cryptInto(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Already disposed');
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    final inputPtr = pkgffi.calloc<ffi.Uint8>(input.length);
    final outputPtr = pkgffi.calloc<ffi.Uint8>(input.length);

    try {
      // Copia input
      for (var i = 0; i < input.length; i++) {
        inputPtr[i] = input[i];
      }

      // Chama C
      ChaCha20DLL.crypt!(
        outputPtr,
        inputPtr,
        input.length,
        _keyPtr!,
        _noncePtr!,
        initialCounter,
      );

      // Copia output
      for (var i = 0; i < input.length; i++) {
        output[i] = outputPtr[i];
      }
    } finally {
      pkgffi.calloc.free(inputPtr);
      pkgffi.calloc.free(outputPtr);
    }
  }

  /// Criptografa usando a função C com unroll
  Uint8List cryptUnroll(Uint8List input) {
    if (_disposed) throw StateError('Already disposed');

    final output = Uint8List(input.length);
    cryptUnrollInto(input, output);
    return output;
  }

  void cryptUnrollInto(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Already disposed');
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }

    final inputPtr = pkgffi.calloc<ffi.Uint8>(input.length);
    final outputPtr = pkgffi.calloc<ffi.Uint8>(input.length);

    try {
      for (var i = 0; i < input.length; i++) {
        inputPtr[i] = input[i];
      }

      ChaCha20DLL.cryptUnroll!(
        outputPtr,
        inputPtr,
        input.length,
        _keyPtr!,
        _noncePtr!,
        initialCounter,
      );

      for (var i = 0; i < input.length; i++) {
        output[i] = outputPtr[i];
      }
    } finally {
      pkgffi.calloc.free(inputPtr);
      pkgffi.calloc.free(outputPtr);
    }
  }

  /// Versão otimizada que evita cópia extra usando ponteiros pre-alocados
  void cryptIntoNative(
    ffi.Pointer<ffi.Uint8> input,
    ffi.Pointer<ffi.Uint8> output,
    int length,
  ) {
    if (_disposed) throw StateError('Already disposed');

    ChaCha20DLL.crypt!(
      output,
      input,
      length,
      _keyPtr!,
      _noncePtr!,
      initialCounter,
    );
  }
}

/// Versão com buffers pré-alocados para evitar alocações repetidas
class ChaCha20CLibPooled {
  final Uint8List _key;
  final Uint8List _nonce;
  final int initialCounter;
  final int maxBufferSize;

  ffi.Pointer<ffi.Uint8>? _keyPtr;
  ffi.Pointer<ffi.Uint8>? _noncePtr;
  ffi.Pointer<ffi.Uint8>? _inputPtr;
  ffi.Pointer<ffi.Uint8>? _outputPtr;
  bool _disposed = false;

  ChaCha20CLibPooled(
    this._key,
    this._nonce, {
    this.initialCounter = 0,
    this.maxBufferSize = 65536,
  }) {
    if (_key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (_nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');

    if (!ChaCha20DLL.load()) {
      throw StateError('Failed to load ChaCha20 DLL: ${ChaCha20DLL.loadError}');
    }

    _keyPtr = pkgffi.calloc<ffi.Uint8>(32);
    _noncePtr = pkgffi.calloc<ffi.Uint8>(12);
    _inputPtr = pkgffi.calloc<ffi.Uint8>(maxBufferSize);
    _outputPtr = pkgffi.calloc<ffi.Uint8>(maxBufferSize);

    for (var i = 0; i < 32; i++) _keyPtr![i] = _key[i];
    for (var i = 0; i < 12; i++) _noncePtr![i] = _nonce[i];
  }

  void dispose() {
    if (_disposed) return;
    if (_keyPtr != null) pkgffi.calloc.free(_keyPtr!);
    if (_noncePtr != null) pkgffi.calloc.free(_noncePtr!);
    if (_inputPtr != null) pkgffi.calloc.free(_inputPtr!);
    if (_outputPtr != null) pkgffi.calloc.free(_outputPtr!);
    _disposed = true;
  }

  /// Criptografa usando buffers pré-alocados
  void cryptInto(Uint8List input, Uint8List output) {
    if (_disposed) throw StateError('Already disposed');
    if (input.length != output.length) {
      throw ArgumentError('Input/output length mismatch');
    }
    if (input.length > maxBufferSize) {
      throw ArgumentError('Input too large (max $maxBufferSize)');
    }

    // Usa asTypedList para view sem cópia
    final inputView = _inputPtr!.asTypedList(input.length);
    final outputView = _outputPtr!.asTypedList(input.length);

    // Copia input
    inputView.setAll(0, input);

    // Chama C
    ChaCha20DLL.crypt!(
      _outputPtr!,
      _inputPtr!,
      input.length,
      _keyPtr!,
      _noncePtr!,
      initialCounter,
    );

    // Copia output
    output.setAll(0, outputView);
  }

  Uint8List crypt(Uint8List input) {
    final output = Uint8List(input.length);
    cryptInto(input, output);
    return output;
  }
}
