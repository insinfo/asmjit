// Blend2D Pipeline Module
// Port of blend2d/pipeline/*

// Pipeline operations and types
export 'pipeline_ops.dart';
export 'pipeline_types.dart';

// TODO: Port from C++:
// Pipeline runtime and definitions:
// - pipedefs.cpp (25 KB) - format/flag definitions
// - piperuntime.cpp/h - dynamic dispatch

// JIT components (~700 KB total):
// - jit/compoppart.cpp (153 KB) - 30+ composition operators
// - jit/fetchgradientpart.cpp (48 KB) - gradient fetchers
// - jit/fetchpatternpart.cpp (80 KB) - pattern fetchers
// - jit/fetchsolidpart.cpp - solid color fetch
// - jit/fillpart.cpp (60 KB) - fill operations
// - jit/pipecompiler.cpp/h (15 KB) - pipeline composer
// - jit/pipeprimitives_p.h (16 KB) - SIMD primitives
// - jit/fetchutils*.cpp (~200 KB) - bilinear, pixel gather

// Reference components:
// - reference/compopgeneric_p.h - additional CompOps
// - reference/fetchgeneric_p.h (40 KB) - generic fetchers
// - reference/fillgeneric_p.h (12 KB) - generic fills
// - reference/pixelgeneric_p.h (34 KB) - pixel ops
