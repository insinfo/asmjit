// ChaCha20 - Implementação C pura (RFC 7539)
// Compila com: clang -O3 -shared -o chacha20_impl.dll chacha20_impl.c
// Ou: gcc -O3 -shared -o chacha20_impl.dll chacha20_impl.c

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#if defined(_WIN32)
#  define EXPORT __declspec(dllexport)
#else
#  define EXPORT __attribute__((visibility("default")))
#endif

// Constantes ChaCha20 "expand 32-byte k"
static const uint32_t CHACHA_CONSTANTS[4] = {
    0x61707865, 0x3320646e, 0x79622d32, 0x6b206574
};

// Rotate left 32-bit
static inline uint32_t rotl32(uint32_t v, int c) {
    return (v << c) | (v >> (32 - c));
}

// Load 32-bit little-endian
static inline uint32_t load32_le(const uint8_t* p) {
    return ((uint32_t)p[0])       |
           ((uint32_t)p[1] << 8)  |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

// Store 32-bit little-endian
static inline void store32_le(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)(v);
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

// Quarter round
static inline void quarter_round(uint32_t* a, uint32_t* b, uint32_t* c, uint32_t* d) {
    *a += *b; *d ^= *a; *d = rotl32(*d, 16);
    *c += *d; *b ^= *c; *b = rotl32(*b, 12);
    *a += *b; *d ^= *a; *d = rotl32(*d, 8);
    *c += *d; *b ^= *c; *b = rotl32(*b, 7);
}

// Gera um bloco de 64 bytes de keystream
static void chacha20_block(uint8_t out[64], const uint8_t key[32], 
                           const uint8_t nonce[12], uint32_t counter) {
    uint32_t state[16];
    uint32_t working[16];

    // Inicializa estado
    state[0] = CHACHA_CONSTANTS[0];
    state[1] = CHACHA_CONSTANTS[1];
    state[2] = CHACHA_CONSTANTS[2];
    state[3] = CHACHA_CONSTANTS[3];

    // Key (8 palavras)
    for (int i = 0; i < 8; i++) {
        state[4 + i] = load32_le(key + i * 4);
    }

    // Counter + Nonce
    state[12] = counter;
    state[13] = load32_le(nonce + 0);
    state[14] = load32_le(nonce + 4);
    state[15] = load32_le(nonce + 8);

    // Copia para working state
    for (int i = 0; i < 16; i++) {
        working[i] = state[i];
    }

    // 20 rounds (10 double rounds)
    for (int i = 0; i < 10; i++) {
        // Column rounds
        quarter_round(&working[0], &working[4], &working[8],  &working[12]);
        quarter_round(&working[1], &working[5], &working[9],  &working[13]);
        quarter_round(&working[2], &working[6], &working[10], &working[14]);
        quarter_round(&working[3], &working[7], &working[11], &working[15]);

        // Diagonal rounds
        quarter_round(&working[0], &working[5], &working[10], &working[15]);
        quarter_round(&working[1], &working[6], &working[11], &working[12]);
        quarter_round(&working[2], &working[7], &working[8],  &working[13]);
        quarter_round(&working[3], &working[4], &working[9],  &working[14]);
    }

    // Adiciona estado inicial
    for (int i = 0; i < 16; i++) {
        working[i] += state[i];
        store32_le(out + i * 4, working[i]);
    }
}

// Encrypt/Decrypt (XOR com keystream)
EXPORT void chacha20_crypt(
    uint8_t* output,
    const uint8_t* input,
    size_t length,
    const uint8_t key[32],
    const uint8_t nonce[12],
    uint32_t initial_counter) {
    
    uint8_t block[64];
    uint32_t counter = initial_counter;
    size_t offset = 0;

    while (offset < length) {
        chacha20_block(block, key, nonce, counter);
        counter++;

        size_t chunk = length - offset;
        if (chunk > 64) chunk = 64;

        for (size_t i = 0; i < chunk; i++) {
            output[offset + i] = input[offset + i] ^ block[i];
        }

        offset += chunk;
    }
}

// Versão que gera apenas um bloco (para benchmarks de geração de keystream)
EXPORT void chacha20_block_export(
    uint8_t out[64],
    const uint8_t key[32],
    const uint8_t nonce[12],
    uint32_t counter) {
    chacha20_block(out, key, nonce, counter);
}

// Versão otimizada com unroll manual
EXPORT void chacha20_crypt_unroll(
    uint8_t* output,
    const uint8_t* input,
    size_t length,
    const uint8_t key[32],
    const uint8_t nonce[12],
    uint32_t initial_counter) {
    
    uint32_t state[16];
    uint32_t working[16];
    uint32_t counter = initial_counter;
    size_t offset = 0;

    // Pre-load key words
    uint32_t k0 = load32_le(key + 0);
    uint32_t k1 = load32_le(key + 4);
    uint32_t k2 = load32_le(key + 8);
    uint32_t k3 = load32_le(key + 12);
    uint32_t k4 = load32_le(key + 16);
    uint32_t k5 = load32_le(key + 20);
    uint32_t k6 = load32_le(key + 24);
    uint32_t k7 = load32_le(key + 28);

    // Pre-load nonce words
    uint32_t n0 = load32_le(nonce + 0);
    uint32_t n1 = load32_le(nonce + 4);
    uint32_t n2 = load32_le(nonce + 8);

    while (offset < length) {
        // Setup state
        state[0]  = CHACHA_CONSTANTS[0]; state[1]  = CHACHA_CONSTANTS[1];
        state[2]  = CHACHA_CONSTANTS[2]; state[3]  = CHACHA_CONSTANTS[3];
        state[4]  = k0; state[5]  = k1; state[6]  = k2; state[7]  = k3;
        state[8]  = k4; state[9]  = k5; state[10] = k6; state[11] = k7;
        state[12] = counter;
        state[13] = n0; state[14] = n1; state[15] = n2;

        // Copy to working
        working[0]  = state[0];  working[1]  = state[1];
        working[2]  = state[2];  working[3]  = state[3];
        working[4]  = state[4];  working[5]  = state[5];
        working[6]  = state[6];  working[7]  = state[7];
        working[8]  = state[8];  working[9]  = state[9];
        working[10] = state[10]; working[11] = state[11];
        working[12] = state[12]; working[13] = state[13];
        working[14] = state[14]; working[15] = state[15];

        // Unrolled double rounds
        #define QR(a, b, c, d) \
            working[a] += working[b]; working[d] ^= working[a]; working[d] = rotl32(working[d], 16); \
            working[c] += working[d]; working[b] ^= working[c]; working[b] = rotl32(working[b], 12); \
            working[a] += working[b]; working[d] ^= working[a]; working[d] = rotl32(working[d], 8);  \
            working[c] += working[d]; working[b] ^= working[c]; working[b] = rotl32(working[b], 7);

        for (int i = 0; i < 10; i++) {
            QR(0, 4, 8, 12); QR(1, 5, 9, 13); QR(2, 6, 10, 14); QR(3, 7, 11, 15);
            QR(0, 5, 10, 15); QR(1, 6, 11, 12); QR(2, 7, 8, 13); QR(3, 4, 9, 14);
        }
        #undef QR

        // Add and XOR
        size_t chunk = length - offset;
        if (chunk > 64) chunk = 64;

        for (int i = 0; i < 16 && (size_t)(i * 4) < chunk; i++) {
            uint32_t v = working[i] + state[i];
            size_t base = i * 4;
            if (base + 0 < chunk) output[offset + base + 0] = input[offset + base + 0] ^ (uint8_t)(v);
            if (base + 1 < chunk) output[offset + base + 1] = input[offset + base + 1] ^ (uint8_t)(v >> 8);
            if (base + 2 < chunk) output[offset + base + 2] = input[offset + base + 2] ^ (uint8_t)(v >> 16);
            if (base + 3 < chunk) output[offset + base + 3] = input[offset + base + 3] ^ (uint8_t)(v >> 24);
        }

        counter++;
        offset += chunk;
    }
}

// Função para medir overhead de chamada FFI (noop)
EXPORT void chacha20_noop(void) {
    // Faz nada
}

// Retorna a versão da implementação
EXPORT uint32_t chacha20_version(void) {
    return 0x01000000; // 1.0.0.0
}
