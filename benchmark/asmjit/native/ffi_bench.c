// Simple C microbench helpers for Dart FFI overhead experiments.
// Build into a shared library and call from Dart via dart:ffi.
#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif

EXPORT uint32_t add_u32(uint32_t a, uint32_t b) {
  return a + b;
}

EXPORT uint64_t sum_u32(const uint32_t* data, size_t n) {
  uint64_t sum = 0;
  for (size_t i = 0; i < n; i++) {
    sum += data[i];
  }
  return sum;
}

EXPORT void fill_u32(uint32_t* data, size_t n, uint32_t value) {
  for (size_t i = 0; i < n; i++) {
    data[i] = value;
  }
}

EXPORT uint32_t pointer_chase_u32(const uint32_t* next, uint32_t start, size_t steps) {
  uint32_t idx = start;
  for (size_t i = 0; i < steps; i++) {
    idx = next[idx];
  }
  return idx;
}

EXPORT void xor_u8(const uint8_t* src, uint8_t* dst, size_t n, uint8_t key) {
  for (size_t i = 0; i < n; i++) {
    dst[i] = src[i] ^ key;
  }
}
