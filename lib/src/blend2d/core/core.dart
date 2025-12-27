// Blend2D Core Module
// Port of blend2d/core/*

// Color types
export 'rgba.dart';

// Pixel formats
export 'format.dart';

// Image container
export 'image.dart';

// TODO: Port from C++ (134 files):

// Base infrastructure:
// - api.h (1908 lines) - Main API definitions
// - object.h/cpp (54 KB) - Reference counting base
// - runtime.h/cpp - Runtime initialization
// - var.h/cpp - Variant type

// Essential rendering types:
// - context.h/cpp (213 KB + 81 KB) - BLContext (2D rendering API)
// - path.h/cpp (57 KB + 84 KB) - BLPath (vector paths)
// - matrix.h/cpp - BLMatrix2D (affine transforms)

// Styling:
// - gradient.h/cpp - BLGradient (linear, radial, conic)
// - pattern.h/cpp - BLPattern (image-based patterns)

// Fonts:
// - font.h/cpp - BLFont
// - fontface.h/cpp - BLFontFace
// - fontdata.h/cpp - BLFontData
// - glyphbuffer.h/cpp - BLGlyphBuffer

// Utilities:
// - pixelconverter.h/cpp - Format conversion
// - string.h/cpp - String container
// - array.h/cpp - Array container
// - bitarray.h/cpp - Bit array
