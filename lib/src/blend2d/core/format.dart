// Blend2D Pixel Formats
// Port of blend2d/core/format.h

/// Pixel format identifier.
enum BLFormat {
  /// None or invalid format.
  none,

  /// 32-bit premultiplied ARGB pixel format (8-bit components).
  prgb32,

  /// 32-bit (X)RGB pixel format (8-bit components, alpha ignored).
  xrgb32,

  /// 8-bit alpha-only format.
  a8;

  /// Returns the number of bytes per pixel.
  int get depth {
    switch (this) {
      case BLFormat.none:
        return 0;
      case BLFormat.prgb32:
      case BLFormat.xrgb32:
        return 4;
      case BLFormat.a8:
        return 1;
    }
  }

  /// Returns true if the format has an alpha channel.
  bool get hasAlpha {
    switch (this) {
      case BLFormat.none:
      case BLFormat.xrgb32:
        return false;
      case BLFormat.prgb32:
      case BLFormat.a8:
        return true;
    }
  }

  /// Returns true if the format uses premultiplied alpha.
  bool get isPremultiplied {
    switch (this) {
      case BLFormat.prgb32:
        return true;
      default:
        return false;
    }
  }
}

/// Pixel format flags.
class BLFormatFlags {
  static const int none = 0;
  static const int rgb = 0x00000001; // RGB components.
  static const int alpha = 0x00000002; // Alpha component.
  static const int rgba = rgb | alpha; // RGBA.
  static const int lum = 0x00000004; // Luminance.
  static const int luma = lum | alpha; // Luminance + Alpha.
  static const int indexed = 0x00000010; // Indexed color.
  static const int premultiplied = 0x00000100; // Premultiplied alpha.
  static const int byteSwap = 0x00000200; // Byte-swapped (BE).
}

/// Pixel format information.
class BLFormatInfo {
  final BLFormat format;
  final int flags;
  final int depth; // Bytes per pixel.
  final List<int> sizes; // Bit sizes of components [R, G, B, A].
  final List<int> shifts; // Bit shifts of components [R, G, B, A].

  const BLFormatInfo({
    required this.format,
    required this.flags,
    required this.depth,
    required this.sizes,
    required this.shifts,
  });

  static const prgb32 = BLFormatInfo(
    format: BLFormat.prgb32,
    flags: BLFormatFlags.rgba | BLFormatFlags.premultiplied,
    depth: 4,
    sizes: [8, 8, 8, 8],
    shifts: [16, 8, 0, 24],
  );

  static const xrgb32 = BLFormatInfo(
    format: BLFormat.xrgb32,
    flags: BLFormatFlags.rgb,
    depth: 4,
    sizes: [8, 8, 8, 0],
    shifts: [16, 8, 0, 0],
  );

  static const a8 = BLFormatInfo(
    format: BLFormat.a8,
    flags: BLFormatFlags.alpha,
    depth: 1,
    sizes: [0, 0, 0, 8],
    shifts: [0, 0, 0, 0],
  );

  static BLFormatInfo fromFormat(BLFormat format) {
    switch (format) {
      case BLFormat.prgb32:
        return prgb32;
      case BLFormat.xrgb32:
        return xrgb32;
      case BLFormat.a8:
        return a8;
      case BLFormat.none:
        return const BLFormatInfo(
          format: BLFormat.none,
          flags: BLFormatFlags.none,
          depth: 0,
          sizes: [0, 0, 0, 0],
          shifts: [0, 0, 0, 0],
        );
    }
  }
}
