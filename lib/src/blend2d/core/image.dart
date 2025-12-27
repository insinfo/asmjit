// Blend2D Image Container
// Port of blend2d/core/image.h

import 'dart:ffi';
import 'dart:typed_data';

import 'package:asmjit/src/asmjit/runtime/ffi_utils/allocation.dart' as ffi;
import 'format.dart';
import 'rgba.dart';
import '../geometry/geometry.dart';

/// Image container that holds pixel data.
class BLImage {
  Pointer<Uint8>? _data;
  int _width;
  int _height;
  int _stride;
  BLFormat _format;
  bool _ownsData;

  BLImage._(
    this._data,
    this._width,
    this._height,
    this._stride,
    this._format,
    this._ownsData,
  );

  /// Create an empty image.
  BLImage.empty()
      : _data = null,
        _width = 0,
        _height = 0,
        _stride = 0,
        _format = BLFormat.none,
        _ownsData = false;

  /// Create a new image with the given dimensions and format.
  factory BLImage.create(int width, int height, BLFormat format) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid image dimensions: ${width}x$height');
    }

    final depth = format.depth;
    if (depth == 0) {
      throw ArgumentError('Invalid format: $format');
    }

    final stride = width * depth;
    final byteSize = stride * height;

    // Allocate memory
    final data = ffi.calloc<Uint8>(byteSize);

    return BLImage._(data, width, height, stride, format, true);
  }

  /// Create an image from existing data (non-owning).
  factory BLImage.fromData(
    Pointer<Uint8> data,
    int width,
    int height,
    int stride,
    BLFormat format,
  ) {
    return BLImage._(data, width, height, stride, format, false);
  }

  /// Create an image from a Uint8List (copies data).
  factory BLImage.fromBytes(
    Uint8List bytes,
    int width,
    int height,
    BLFormat format, {
    int? stride,
  }) {
    final depth = format.depth;
    final actualStride = stride ?? (width * depth);

    if (bytes.length < actualStride * height) {
      throw ArgumentError(
        'Insufficient bytes: expected ${actualStride * height}, got ${bytes.length}',
      );
    }

    final data = ffi.calloc<Uint8>(bytes.length);
    final dataList = data.asTypedList(bytes.length);
    dataList.setAll(0, bytes);

    return BLImage._(data, width, height, actualStride, format, true);
  }

  /// Width of the image in pixels.
  int get width => _width;

  /// Height of the image in pixels.
  int get height => _height;

  /// Stride (bytes per row).
  int get stride => _stride;

  /// Pixel format.
  BLFormat get format => _format;

  /// Size of the image.
  BLSizeI get size => BLSizeI(_width, _height);

  /// Returns true if the image is empty (no pixel data).
  bool get isEmpty => _data == null || _width == 0 || _height == 0;

  /// Returns the pixel data pointer.
  Pointer<Uint8>? get data => _data;

  /// Get pixels as Uint8List (read-only view).
  Uint8List? get pixels {
    if (_data == null) return null;
    return _data!.asTypedList(_stride * _height);
  }

  /// Get pixel value at (x, y) as BLRgba32.
  BLRgba32? getPixel(int x, int y) {
    if (x < 0 || x >= _width || y < 0 || y >= _height || _data == null) {
      return null;
    }

    final offset = y * _stride + x * _format.depth;

    switch (_format) {
      case BLFormat.prgb32:
      case BLFormat.xrgb32:
        final ptr = Pointer<Uint32>.fromAddress(_data!.address + offset);
        return BLRgba32.fromValue(ptr.value);

      case BLFormat.a8:
        final alpha = (_data! + offset).value;
        return BLRgba32(0, 0, 0, alpha);

      case BLFormat.none:
        return null;
    }
  }

  /// Set pixel value at (x, y) from BLRgba32.
  void setPixel(int x, int y, BLRgba32 color) {
    if (x < 0 || x >= _width || y < 0 || y >= _height || _data == null) {
      return;
    }

    final offset = y * _stride + x * _format.depth;

    switch (_format) {
      case BLFormat.prgb32:
        final premul = color.premultiplied();
        final ptr = Pointer<Uint32>.fromAddress(_data!.address + offset);
        ptr.value = premul.value;
        break;

      case BLFormat.xrgb32:
        final ptr = Pointer<Uint32>.fromAddress(_data!.address + offset);
        ptr.value = color.value | 0xFF000000; // Force alpha to 255
        break;

      case BLFormat.a8:
        (_data! + offset).value = color.a;
        break;

      case BLFormat.none:
        break;
    }
  }

  /// Fill the entire image with a solid color.
  void fillAll(BLRgba32 color) {
    if (_data == null) return;

    switch (_format) {
      case BLFormat.prgb32:
        final premul = color.premultiplied();
        _fillAll32(premul.value);
        break;

      case BLFormat.xrgb32:
        _fillAll32(color.value | 0xFF000000);
        break;

      case BLFormat.a8:
        _fillAll8(color.a);
        break;

      case BLFormat.none:
        break;
    }
  }

  void _fillAll32(int value) {
    for (var y = 0; y < _height; y++) {
      final rowPtr = Pointer<Uint32>.fromAddress(_data!.address + y * _stride);
      for (var x = 0; x < _width; x++) {
        (rowPtr + x).value = value;
      }
    }
  }

  void _fillAll8(int value) {
    for (var y = 0; y < _height; y++) {
      final rowPtr = _data! + (y * _stride);
      for (var x = 0; x < _width; x++) {
        (rowPtr + x).value = value;
      }
    }
  }

  /// Clear the image (fill with transparent black).
  void clear() {
    if (_data == null) return;
    final totalBytes = _stride * _height;
    for (var i = 0; i < totalBytes; i++) {
      (_data! + i).value = 0;
    }
  }

  /// Dispose the image and free memory if owned.
  void dispose() {
    if (_data != null && _ownsData) {
      ffi.calloc.free(_data!);
    }
    _data = null;
    _width = 0;
    _height = 0;
    _stride = 0;
    _format = BLFormat.none;
    _ownsData = false;
  }

  @override
  String toString() =>
      'BLImage(${_width}x$_height, format=$_format, stride=$_stride)';
}
