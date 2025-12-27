// Blend2D Color Types
// Port of blend2d/core/rgba.h

/// RGBA color with 32-bit floating point components.
class BLRgba {
  final double r;
  final double g;
  final double b;
  final double a;

  const BLRgba(this.r, this.g, this.b, [this.a = 1.0]);

  const BLRgba.transparent()
      : r = 0.0,
        g = 0.0,
        b = 0.0,
        a = 0.0;

  const BLRgba.black()
      : r = 0.0,
        g = 0.0,
        b = 0.0,
        a = 1.0;

  const BLRgba.white()
      : r = 1.0,
        g = 1.0,
        b = 1.0,
        a = 1.0;

  /// Create from 8-bit components (0-255).
  factory BLRgba.fromRgba32(int r, int g, int b, [int a = 255]) {
    return BLRgba(
      r / 255.0,
      g / 255.0,
      b / 255.0,
      a / 255.0,
    );
  }

  /// Create from packed 32-bit ARGB value (0xAARRGGBB).
  factory BLRgba.fromArgb32(int argb) {
    return BLRgba(
      ((argb >> 16) & 0xFF) / 255.0,
      ((argb >> 8) & 0xFF) / 255.0,
      (argb & 0xFF) / 255.0,
      ((argb >> 24) & 0xFF) / 255.0,
    );
  }

  /// Convert to BLRgba32 (8-bit per channel).
  BLRgba32 toRgba32() {
    return BLRgba32(
      (r * 255.0).round().clamp(0, 255),
      (g * 255.0).round().clamp(0, 255),
      (b * 255.0).round().clamp(0, 255),
      (a * 255.0).round().clamp(0, 255),
    );
  }

  /// Convert to premultiplied alpha.
  BLRgba premultiplied() {
    return BLRgba(r * a, g * a, b * a, a);
  }

  /// Convert from premultiplied alpha.
  BLRgba unpremultiplied() {
    if (a == 0.0) return this;
    final invA = 1.0 / a;
    return BLRgba(r * invA, g * invA, b * invA, a);
  }

  @override
  String toString() => 'BLRgba($r, $g, $b, $a)';

  @override
  bool operator ==(Object other) =>
      other is BLRgba &&
      r == other.r &&
      g == other.g &&
      b == other.b &&
      a == other.a;

  @override
  int get hashCode => Object.hash(r, g, b, a);
}

/// RGBA color with 8-bit components (0xAARRGGBB format).
class BLRgba32 {
  final int value;

  const BLRgba32._(this.value);

  /// Create from components (0-255).
  factory BLRgba32(int r, int g, int b, [int a = 255]) {
    return BLRgba32._(
      ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF),
    );
  }

  /// Create from packed 32-bit value (0xAARRGGBB).
  factory BLRgba32.fromValue(int value) {
    return BLRgba32._(value);
  }

  const BLRgba32.transparent() : value = 0x00000000;
  const BLRgba32.black() : value = 0xFF000000;
  const BLRgba32.white() : value = 0xFFFFFFFF;

  int get r => (value >> 16) & 0xFF;
  int get g => (value >> 8) & 0xFF;
  int get b => value & 0xFF;
  int get a => (value >> 24) & 0xFF;

  /// Convert to BLRgba (floating point).
  BLRgba toRgba() {
    return BLRgba(
      r / 255.0,
      g / 255.0,
      b / 255.0,
      a / 255.0,
    );
  }

  /// Convert to premultiplied alpha.
  BLRgba32 premultiplied() {
    if (a == 255) return this;
    if (a == 0) return const BLRgba32.transparent();

    final rPre = (r * a + 127) ~/ 255;
    final gPre = (g * a + 127) ~/ 255;
    final bPre = (b * a + 127) ~/ 255;

    return BLRgba32(rPre, gPre, bPre, a);
  }

  @override
  String toString() => 'BLRgba32(0x${value.toRadixString(16).padLeft(8, '0')})';

  @override
  bool operator ==(Object other) => other is BLRgba32 && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// RGBA color with 16-bit components (0xAAAARRRRGGGGBBBB format).
class BLRgba64 {
  final int value;

  const BLRgba64._(this.value);

  /// Create from components (0-65535).
  factory BLRgba64(int r, int g, int b, [int a = 65535]) {
    return BLRgba64._(
      ((a & 0xFFFF) << 48) |
          ((r & 0xFFFF) << 32) |
          ((g & 0xFFFF) << 16) |
          (b & 0xFFFF),
    );
  }

  const BLRgba64.transparent() : value = 0x0000000000000000;
  const BLRgba64.black() : value = 0xFFFF000000000000;
  const BLRgba64.white() : value = 0xFFFFFFFFFFFFFFFF;

  int get r => (value >> 32) & 0xFFFF;
  int get g => (value >> 16) & 0xFFFF;
  int get b => value & 0xFFFF;
  int get a => (value >> 48) & 0xFFFF;

  /// Convert to BLRgba (floating point).
  BLRgba toRgba() {
    return BLRgba(
      r / 65535.0,
      g / 65535.0,
      b / 65535.0,
      a / 65535.0,
    );
  }

  /// Convert to BLRgba32 (8-bit per channel).
  BLRgba32 toRgba32() {
    return BLRgba32(
      r >> 8,
      g >> 8,
      b >> 8,
      a >> 8,
    );
  }

  @override
  String toString() =>
      'BLRgba64(0x${value.toRadixString(16).padLeft(16, '0')})';

  @override
  bool operator ==(Object other) => other is BLRgba64 && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Common color constants.
class BLColors {
  // Named colors (CSS/HTML standard)
  static const aliceBlue = BLRgba32._(0xFFF0F8FF);
  static const antiqueWhite = BLRgba32._(0xFFFAEBD7);
  static const aqua = BLRgba32._(0xFF00FFFF);
  static const aquamarine = BLRgba32._(0xFF7FFFD4);
  static const azure = BLRgba32._(0xFFF0FFFF);
  static const beige = BLRgba32._(0xFFF5F5DC);
  static const bisque = BLRgba32._(0xFFFFE4C4);
  static const black = BLRgba32.black();
  static const blanchedAlmond = BLRgba32._(0xFFFFEBCD);
  static const blue = BLRgba32._(0xFF0000FF);
  static const blueViolet = BLRgba32._(0xFF8A2BE2);
  static const brown = BLRgba32._(0xFFA52A2A);
  static const burlyWood = BLRgba32._(0xFFDEB887);
  static const cadetBlue = BLRgba32._(0xFF5F9EA0);
  static const chartreuse = BLRgba32._(0xFF7FFF00);
  static const chocolate = BLRgba32._(0xFFD2691E);
  static const coral = BLRgba32._(0xFFFF7F50);
  static const cornflowerBlue = BLRgba32._(0xFF6495ED);
  static const cornsilk = BLRgba32._(0xFFFFF8DC);
  static const crimson = BLRgba32._(0xFFDC143C);
  static const cyan = BLRgba32._(0xFF00FFFF);
  static const darkBlue = BLRgba32._(0xFF00008B);
  static const darkCyan = BLRgba32._(0xFF008B8B);
  static const darkGoldenRod = BLRgba32._(0xFFB8860B);
  static const darkGray = BLRgba32._(0xFFA9A9A9);
  static const darkGreen = BLRgba32._(0xFF006400);
  static const darkKhaki = BLRgba32._(0xFFBDB76B);
  static const darkMagenta = BLRgba32._(0xFF8B008B);
  static const darkOliveGreen = BLRgba32._(0xFF556B2F);
  static const darkOrange = BLRgba32._(0xFFFF8C00);
  static const darkOrchid = BLRgba32._(0xFF9932CC);
  static const darkRed = BLRgba32._(0xFF8B0000);
  static const darkSalmon = BLRgba32._(0xFFE9967A);
  static const darkSeaGreen = BLRgba32._(0xFF8FBC8F);
  static const darkSlateBlue = BLRgba32._(0xFF483D8B);
  static const darkSlateGray = BLRgba32._(0xFF2F4F4F);
  static const darkTurquoise = BLRgba32._(0xFF00CED1);
  static const darkViolet = BLRgba32._(0xFF9400D3);
  static const deepPink = BLRgba32._(0xFFFF1493);
  static const deepSkyBlue = BLRgba32._(0xFF00BFFF);
  static const dimGray = BLRgba32._(0xFF696969);
  static const dodgerBlue = BLRgba32._(0xFF1E90FF);
  static const fireBrick = BLRgba32._(0xFFB22222);
  static const floralWhite = BLRgba32._(0xFFFFFAF0);
  static const forestGreen = BLRgba32._(0xFF228B22);
  static const fuchsia = BLRgba32._(0xFFFF00FF);
  static const gainsboro = BLRgba32._(0xFFDCDCDC);
  static const ghostWhite = BLRgba32._(0xFFF8F8FF);
  static const gold = BLRgba32._(0xFFFFD700);
  static const goldenRod = BLRgba32._(0xFFDAA520);
  static const gray = BLRgba32._(0xFF808080);
  static const green = BLRgba32._(0xFF008000);
  static const greenYellow = BLRgba32._(0xFFADFF2F);
  static const honeyDew = BLRgba32._(0xFFF0FFF0);
  static const hotPink = BLRgba32._(0xFFFF69B4);
  static const indianRed = BLRgba32._(0xFFCD5C5C);
  static const indigo = BLRgba32._(0xFF4B0082);
  static const ivory = BLRgba32._(0xFFFFFFF0);
  static const khaki = BLRgba32._(0xFFF0E68C);
  static const lavender = BLRgba32._(0xFFE6E6FA);
  static const lavenderBlush = BLRgba32._(0xFFFFF0F5);
  static const lawnGreen = BLRgba32._(0xFF7CFC00);
  static const lemonChiffon = BLRgba32._(0xFFFFFACD);
  static const lightBlue = BLRgba32._(0xFFADD8E6);
  static const lightCoral = BLRgba32._(0xFFF08080);
  static const lightCyan = BLRgba32._(0xFFE0FFFF);
  static const lightGoldenRodYellow = BLRgba32._(0xFFFAFAD2);
  static const lightGray = BLRgba32._(0xFFD3D3D3);
  static const lightGreen = BLRgba32._(0xFF90EE90);
  static const lightPink = BLRgba32._(0xFFFFB6C1);
  static const lightSalmon = BLRgba32._(0xFFFFA07A);
  static const lightSeaGreen = BLRgba32._(0xFF20B2AA);
  static const lightSkyBlue = BLRgba32._(0xFF87CEFA);
  static const lightSlateGray = BLRgba32._(0xFF778899);
  static const lightSteelBlue = BLRgba32._(0xFFB0C4DE);
  static const lightYellow = BLRgba32._(0xFFFFFFE0);
  static const lime = BLRgba32._(0xFF00FF00);
  static const limeGreen = BLRgba32._(0xFF32CD32);
  static const linen = BLRgba32._(0xFFFAF0E6);
  static const magenta = BLRgba32._(0xFFFF00FF);
  static const maroon = BLRgba32._(0xFF800000);
  static const mediumAquaMarine = BLRgba32._(0xFF66CDAA);
  static const mediumBlue = BLRgba32._(0xFF0000CD);
  static const mediumOrchid = BLRgba32._(0xFFBA55D3);
  static const mediumPurple = BLRgba32._(0xFF9370DB);
  static const mediumSeaGreen = BLRgba32._(0xFF3CB371);
  static const mediumSlateBlue = BLRgba32._(0xFF7B68EE);
  static const mediumSpringGreen = BLRgba32._(0xFF00FA9A);
  static const mediumTurquoise = BLRgba32._(0xFF48D1CC);
  static const mediumVioletRed = BLRgba32._(0xFFC71585);
  static const midnightBlue = BLRgba32._(0xFF191970);
  static const mintCream = BLRgba32._(0xFFF5FFFA);
  static const mistyRose = BLRgba32._(0xFFFFE4E1);
  static const moccasin = BLRgba32._(0xFFFFE4B5);
  static const navajoWhite = BLRgba32._(0xFFFFDEAD);
  static const navy = BLRgba32._(0xFF000080);
  static const oldLace = BLRgba32._(0xFFFDF5E6);
  static const olive = BLRgba32._(0xFF808000);
  static const oliveDrab = BLRgba32._(0xFF6B8E23);
  static const orange = BLRgba32._(0xFFFFA500);
  static const orangeRed = BLRgba32._(0xFFFF4500);
  static const orchid = BLRgba32._(0xFFDA70D6);
  static const paleGoldenRod = BLRgba32._(0xFFEEE8AA);
  static const paleGreen = BLRgba32._(0xFF98FB98);
  static const paleTurquoise = BLRgba32._(0xFFAFEEEE);
  static const paleVioletRed = BLRgba32._(0xFFDB7093);
  static const papayaWhip = BLRgba32._(0xFFFFEFD5);
  static const peachPuff = BLRgba32._(0xFFFFDAB9);
  static const peru = BLRgba32._(0xFFCD853F);
  static const pink = BLRgba32._(0xFFFFC0CB);
  static const plum = BLRgba32._(0xFFDDA0DD);
  static const powderBlue = BLRgba32._(0xFFB0E0E6);
  static const purple = BLRgba32._(0xFF800080);
  static const red = BLRgba32._(0xFFFF0000);
  static const rosyBrown = BLRgba32._(0xFFBC8F8F);
  static const royalBlue = BLRgba32._(0xFF4169E1);
  static const saddleBrown = BLRgba32._(0xFF8B4513);
  static const salmon = BLRgba32._(0xFFFA8072);
  static const sandyBrown = BLRgba32._(0xFFF4A460);
  static const seaGreen = BLRgba32._(0xFF2E8B57);
  static const seaShell = BLRgba32._(0xFFFFF5EE);
  static const sienna = BLRgba32._(0xFFA0522D);
  static const silver = BLRgba32._(0xFFC0C0C0);
  static const skyBlue = BLRgba32._(0xFF87CEEB);
  static const slateBlue = BLRgba32._(0xFF6A5ACD);
  static const slateGray = BLRgba32._(0xFF708090);
  static const snow = BLRgba32._(0xFFFFFAFA);
  static const springGreen = BLRgba32._(0xFF00FF7F);
  static const steelBlue = BLRgba32._(0xFF4682B4);
  static const tan = BLRgba32._(0xFFD2B48C);
  static const teal = BLRgba32._(0xFF008080);
  static const thistle = BLRgba32._(0xFFD8BFD8);
  static const tomato = BLRgba32._(0xFFFF6347);
  static const transparent = BLRgba32.transparent();
  static const turquoise = BLRgba32._(0xFF40E0D0);
  static const violet = BLRgba32._(0xFFEE82EE);
  static const wheat = BLRgba32._(0xFFF5DEB3);
  static const white = BLRgba32.white();
  static const whiteSmoke = BLRgba32._(0xFFF5F5F5);
  static const yellow = BLRgba32._(0xFFFFFF00);
  static const yellowGreen = BLRgba32._(0xFF9ACD32);
}
