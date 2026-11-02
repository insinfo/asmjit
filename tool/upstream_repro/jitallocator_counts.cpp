// 1) JitAllocator statistics after reset(): allocation_count().
// 2) kImmediateRelease: is a block released when its only allocation (made
//    while the block is in incremental mode) is released?
//
// Build against the upstream static library (macOS arm64; U = upstream):
//
//   clang++ -std=c++17 -O1 -DASMJIT_STATIC -I$U jitallocator_counts.cpp \
//     libasmjit.a -o counts
//
// Observed with upstream asmjit-master (2026-11-02):
//
//   before reset: allocation_count=100
//   after reset(kSoft): allocation_count=100 block_count=1
//   after reset(kHard): allocation_count=100 block_count=0
//   kImmediateRelease: after alloc block_count=1
//   kImmediateRelease: after release block_count=1 allocation_count=0 used=64
//
// With `impl->allocation_count = 0;` in JitAllocator::reset() and the
// incremental branch of JitAllocatorBlock::mark_released_area() marking the
// block empty when `area_used() == initial_area_start()` (as the other branch
// does), the output is allocation_count=0 after both resets and block_count=0,
// used=0 after the release; `jitallocator_stats 20000` prints the same numbers
// with and without these changes.
#include <asmjit/core.h>
#include <stdio.h>

using namespace asmjit;

int main() {
  {
    JitAllocator allocator;
    for (int i = 0; i < 100; i++) {
      JitAllocator::Span span;
      (void)allocator.alloc(Out(span), 100);
    }
    printf("before reset: allocation_count=%zu\n", allocator.statistics().allocation_count());
    allocator.reset(ResetPolicy::kSoft);
    printf("after reset(kSoft): allocation_count=%zu block_count=%zu\n",
           allocator.statistics().allocation_count(), allocator.statistics().block_count());
    allocator.reset(ResetPolicy::kHard);
    printf("after reset(kHard): allocation_count=%zu block_count=%zu\n",
           allocator.statistics().allocation_count(), allocator.statistics().block_count());
  }

  {
    JitAllocator::CreateParams params {};
    params.options = JitAllocatorOptions::kImmediateRelease;
    JitAllocator allocator(&params);
    JitAllocator::Span span;
    (void)allocator.alloc(Out(span), 100);
    printf("kImmediateRelease: after alloc block_count=%zu\n", allocator.statistics().block_count());
    (void)allocator.release(span.rx());
    printf("kImmediateRelease: after release block_count=%zu allocation_count=%zu used=%zu\n",
           allocator.statistics().block_count(), allocator.statistics().allocation_count(),
           allocator.statistics().used_size());
  }
  return 0;
}
