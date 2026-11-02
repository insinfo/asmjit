// 1) JitAllocator::is_initialized() result for a working allocator.
// 2) Whether reset(ResetPolicy::kSoft) with kFillUnusedMemory wipes the memory
//    that was in use in the block it keeps (JitAllocatorImpl_wipeOutBlock()).
//
// Build against the upstream static library (macOS arm64; U = upstream):
//
//   clang++ -std=c++17 -O1 -DASMJIT_STATIC -I$U jitallocator_misc.cpp \
//     libasmjit.a -o misc
//
// Observed with upstream asmjit-master (2026-11-02):
//
//   is_initialized()=0 (alloc err=0, block_size=65536)
//   before reset: a[0]=0x5A b[0]=0x5A
//   after release(b): b[0]=0xCC
//   after reset(kSoft): a[0]=0x5A (fill pattern is 0xCC)
//   new span after reset: c==a 1, c[0]=0x5A
//
// With `BitVectorRangeIterator<Support::BitWord, 1>` in
// JitAllocatorImpl_wipeOutBlock() (instead of `<..., 0>`) the last two lines
// read 0xCC.
#include <asmjit/core.h>
#include <stdio.h>
#include <string.h>

using namespace asmjit;

int main() {
  {
    JitAllocator allocator;
    JitAllocator::Span span;
    Error err = allocator.alloc(Out(span), 64);
    printf("is_initialized()=%d (alloc err=%u, block_size=%u)\n", int(allocator.is_initialized()), uint32_t(err),
           allocator.block_size());
  }

  {
    JitAllocator::CreateParams params {};
    params.options = JitAllocatorOptions::kFillUnusedMemory | JitAllocatorOptions::kCustomFillPattern;
    params.fill_pattern = 0xCCCCCCCCu;
    JitAllocator allocator(&params);

    JitAllocator::Span a, b;
    (void)allocator.alloc(Out(a), 256);
    (void)allocator.alloc(Out(b), 256);
    uint8_t code[256];
    memset(code, 0x5A, sizeof(code));
    (void)allocator.write(a, 0, code, sizeof(code));
    (void)allocator.write(b, 0, code, sizeof(code));
    printf("before reset: a[0]=0x%02X b[0]=0x%02X\n", static_cast<uint8_t*>(a.rx())[0], static_cast<uint8_t*>(b.rx())[0]);

    // Release `b`, it must be filled by the pattern.
    (void)allocator.release(b.rx());
    printf("after release(b): b[0]=0x%02X\n", static_cast<uint8_t*>(b.rx())[0]);

    // Soft reset keeps the block; the memory used by `a` must be wiped.
    allocator.reset(ResetPolicy::kSoft);
    printf("after reset(kSoft): a[0]=0x%02X (fill pattern is 0xCC)\n", static_cast<uint8_t*>(a.rx())[0]);

    JitAllocator::Span c;
    (void)allocator.alloc(Out(c), 256);
    printf("new span after reset: c==a %d, c[0]=0x%02X\n", int(c.rx() == a.rx()), static_cast<uint8_t*>(c.rx())[0]);
  }
  return 0;
}
