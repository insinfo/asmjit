// ChaCha20 reference implementation for FFI benchmarks.
// Exports: chacha20_xor(out, in, len, key, nonce, counter)

#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32)
#  define EXPORT __declspec(dllexport)
#else
#  define EXPORT __attribute__((visibility("default")))
#endif

static inline uint32_t rotl32(uint32_t v, int c) {
  return (v << c) | (v >> (32 - c));
}

static inline void quarter_round(uint32_t* a, uint32_t* b, uint32_t* c, uint32_t* d) {
  *a += *b; *d ^= *a; *d = rotl32(*d, 16);
  *c += *d; *b ^= *c; *b = rotl32(*b, 12);
  *a += *b; *d ^= *a; *d = rotl32(*d, 8);
  *c += *d; *b ^= *c; *b = rotl32(*b, 7);
}

static inline uint32_t load32_le(const uint8_t* p) {
  return ((uint32_t)p[0]) |
         ((uint32_t)p[1] << 8) |
         ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

static inline void store32_le(uint8_t* p, uint32_t v) {
  p[0] = (uint8_t)(v);
  p[1] = (uint8_t)(v >> 8);
  p[2] = (uint8_t)(v >> 16);
  p[3] = (uint8_t)(v >> 24);
}

static void chacha20_block(uint8_t out[64], const uint8_t key[32], const uint8_t nonce[12], uint32_t counter) {
  uint32_t state[16];
  uint32_t working[16];

  state[0] = 0x61707865;
  state[1] = 0x3320646e;
  state[2] = 0x79622d32;
  state[3] = 0x6b206574;

  state[4] = load32_le(key + 0);
  state[5] = load32_le(key + 4);
  state[6] = load32_le(key + 8);
  state[7] = load32_le(key + 12);
  state[8] = load32_le(key + 16);
  state[9] = load32_le(key + 20);
  state[10] = load32_le(key + 24);
  state[11] = load32_le(key + 28);

  state[12] = counter;
  state[13] = load32_le(nonce + 0);
  state[14] = load32_le(nonce + 4);
  state[15] = load32_le(nonce + 8);

  for (int i = 0; i < 16; i++) {
    working[i] = state[i];
  }

  for (int i = 0; i < 10; i++) {
    // Column rounds.
    quarter_round(&working[0], &working[4], &working[8], &working[12]);
    quarter_round(&working[1], &working[5], &working[9], &working[13]);
    quarter_round(&working[2], &working[6], &working[10], &working[14]);
    quarter_round(&working[3], &working[7], &working[11], &working[15]);

    // Diagonal rounds.
    quarter_round(&working[0], &working[5], &working[10], &working[15]);
    quarter_round(&working[1], &working[6], &working[11], &working[12]);
    quarter_round(&working[2], &working[7], &working[8], &working[13]);
    quarter_round(&working[3], &working[4], &working[9], &working[14]);
  }

  for (int i = 0; i < 16; i++) {
    working[i] += state[i];
    store32_le(out + i * 4, working[i]);
  }
}

EXPORT void chacha20_xor(
    uint8_t* out,
    const uint8_t* in,
    size_t len,
    const uint8_t* key,
    const uint8_t* nonce,
    uint32_t counter) {
  uint8_t block[64];
  size_t offset = 0;

  while (offset < len) {
    chacha20_block(block, key, nonce, counter);
    counter++;

    size_t chunk = len - offset;
    if (chunk > 64) {
      chunk = 64;
    }

    for (size_t i = 0; i < chunk; i++) {
      out[offset + i] = in[offset + i] ^ block[i];
    }

    offset += chunk;
  }
}
