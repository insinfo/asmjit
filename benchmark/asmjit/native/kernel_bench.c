// Kernel Benchmark - C Implementation
// Compila com: clang -O3 -shared -o kernel_bench.dll kernel_bench.c
// Ou: gcc -O3 -shared -o kernel_bench.dll kernel_bench.c

#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32)
#  define EXPORT __declspec(dllexport)
#else
#  define EXPORT __attribute__((visibility("default")))
#endif

// Rotate left 32-bit
static inline uint32_t rotl32(uint32_t v, int c) {
  return (v << c) | (v >> (32 - c));
}

// Simple XOR-rotate kernel (representative of crypto operations)
// Processes data in 64-byte blocks using XOR and rotations
EXPORT void xor_rotate_kernel(
    const uint8_t* input,
    uint8_t* output,
    size_t length,
    uint32_t seed) {
  
  // State initialization
  uint32_t state[4] = {
    seed ^ 0x61707865,
    seed ^ 0x3320646e,
    seed ^ 0x79622d32,
    seed ^ 0x6b206574
  };
  
  size_t offset = 0;
  while (offset < length) {
    // Mix state (simplified quarter-round like operation)
    state[0] += state[1]; state[3] ^= state[0]; state[3] = rotl32(state[3], 16);
    state[2] += state[3]; state[1] ^= state[2]; state[1] = rotl32(state[1], 12);
    state[0] += state[1]; state[3] ^= state[0]; state[3] = rotl32(state[3], 8);
    state[2] += state[3]; state[1] ^= state[2]; state[1] = rotl32(state[1], 7);
    
    // XOR input with state bytes
    size_t chunk = length - offset;
    if (chunk > 16) chunk = 16;
    
    for (size_t i = 0; i < chunk; i++) {
      uint8_t key_byte = (state[i / 4] >> ((i % 4) * 8)) & 0xFF;
      output[offset + i] = input[offset + i] ^ key_byte;
    }
    
    offset += chunk;
  }
}

// Sum kernel - simple vectorizable loop
EXPORT uint64_t sum_u32_kernel(const uint32_t* data, size_t count) {
  uint64_t sum = 0;
  for (size_t i = 0; i < count; i++) {
    sum += data[i];
  }
  return sum;
}

// Memory copy kernel
EXPORT void memcpy_kernel(uint8_t* dst, const uint8_t* src, size_t length) {
  for (size_t i = 0; i < length; i++) {
    dst[i] = src[i];
  }
}

// XOR block kernel (simple)
EXPORT void xor_block_kernel(
    const uint8_t* src,
    uint8_t* dst,
    size_t length,
    uint8_t key) {
  for (size_t i = 0; i < length; i++) {
    dst[i] = src[i] ^ key;
  }
}

// XOR block with unroll (4x)
EXPORT void xor_block_unroll4(
    const uint8_t* src,
    uint8_t* dst,
    size_t length,
    uint8_t key) {
  size_t i = 0;
  size_t aligned = length & ~3ULL;
  
  for (; i < aligned; i += 4) {
    dst[i + 0] = src[i + 0] ^ key;
    dst[i + 1] = src[i + 1] ^ key;
    dst[i + 2] = src[i + 2] ^ key;
    dst[i + 3] = src[i + 3] ^ key;
  }
  
  for (; i < length; i++) {
    dst[i] = src[i] ^ key;
  }
}

// Fibonacci kernel (compute-bound, no memory)
EXPORT uint64_t fib_kernel(uint32_t n) {
  if (n <= 1) return n;
  uint64_t a = 0, b = 1;
  for (uint32_t i = 2; i <= n; i++) {
    uint64_t c = a + b;
    a = b;
    b = c;
  }
  return b;
}

// Add two numbers (minimal FFI overhead test)
EXPORT uint32_t add_two(uint32_t a, uint32_t b) {
  return a + b;
}

// Empty function (pure FFI call overhead)
EXPORT void noop(void) {
  // Does nothing
}
