// Runs the upstream `test_jit_allocator_alloc_release()` sequence against the
// upstream JitAllocator and prints the statistics after every phase, so the
// Dart port can be checked against identical numbers.
//
// Build against the upstream static library (macOS arm64; U = upstream):
//
//   clang++ -std=c++17 -O2 -DASMJIT_STATIC -I$U jitallocator_stats.cpp \
//     libasmjit.a -o stats && ./stats 20000
//
// The numbers printed by `./stats 20000` are the expectations of
// test/asmjit/jit_allocator_test.dart (`upstreamStats`).
#include <asmjit/core.h>
#include <asmjit-testing/commons/random.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <utility>
#include <vector>

using namespace asmjit;

static void usage(const char* phase, JitAllocator& a) {
  JitAllocator::Statistics s = a.statistics();
  printf("  %-24s blocks=%zu allocs=%zu used=%zu reserved=%zu overhead=%zu\n", phase,
         s.block_count(), s.allocation_count(), s.used_size(), s.reserved_size(), s.overhead_size());
}

struct Wrapper {
  JitAllocator _allocator;
  TestUtils::Random _rng;
  explicit Wrapper(const JitAllocator::CreateParams* p) : _allocator(p), _rng(0x123456789u) {}

  void* alloc(size_t size) {
    JitAllocator::Span span;
    Error err = _allocator.alloc(Out(span), size);
    if (err != Error::kOk) { printf("alloc failed\n"); exit(1); }
    uint64_t pattern = _rng.next_uint64();
    {
      VirtMem::ProtectJitReadWriteScope scope(span.rw(), size);
      uint64_t* p = static_cast<uint64_t*>(span.rw());
      for (size_t i = 0; i < size / 8; i++) p[i] = pattern;
    }
    return span.rx();
  }
  void release(void* p) {
    if (_allocator.release(p) != Error::kOk) { printf("release failed\n"); exit(1); }
  }
  void shrink(void* p, size_t new_size) {
    JitAllocator::Span span;
    if (_allocator.query(Out(span), p) != Error::kOk) { printf("query failed\n"); exit(1); }
    if (_allocator.shrink(span, new_size) != Error::kOk) { printf("shrink failed\n"); exit(1); }
  }
};

static void shuffle(void** a, size_t count, TestUtils::Random& prng) {
  for (size_t i = 0; i < count; ++i) std::swap(a[i], a[size_t(prng.next_uint32() % count)]);
}

int main(int argc, char** argv) {
  size_t kCount = argc > 1 ? size_t(atoi(argv[1])) : 20000;
  using Opt = JitAllocatorOptions;
  struct TestInfo { const char* name; JitAllocatorOptions options; uint32_t block_size; uint32_t granularity; };
  TestInfo table[] = {
    { "Default", Opt::kNone, 0, 0 },
    { "16MB blocks", Opt::kNone, 16 * 1024 * 1024, 0 },
    { "256B granularity", Opt::kNone, 0, 256 },
    { "kUseMultiplePools", Opt::kUseMultiplePools, 0, 0 },
    { "kFillUnusedMemory", Opt::kFillUnusedMemory, 0, 0 },
    { "kImmediateRelease", Opt::kImmediateRelease, 0, 0 },
    { "kDisableInitialPadding", Opt::kDisableInitialPadding, 0, 0 },
    { "kUseLargePages", Opt::kUseLargePages, 0, 0 },
    { "kUseLargePages | kFillUnusedMemory", Opt::kUseLargePages | Opt::kFillUnusedMemory, 0, 0 },
    { "kUseLargePages | kAlignBlockSizeToLargePage", Opt::kUseLargePages | Opt::kAlignBlockSizeToLargePage, 0, 0 },
    { "kUseDualMapping", Opt::kUseDualMapping, 0, 0 },
    { "kUseDualMapping | kFillUnusedMemory", Opt::kUseDualMapping | Opt::kFillUnusedMemory, 0, 0 },
  };
  VirtMem::HardenedRuntimeInfo hri = VirtMem::hardened_runtime_info();
  VirtMem::Info vi = VirtMem::info();
  printf("page_size=%u page_granularity=%u large_page_size=%zu hardened=%u\n", vi.page_size, vi.page_granularity,
         VirtMem::large_page_size(), uint32_t(hri.flags));

  for (const TestInfo& ti : table) {
    if (Support::test(ti.options, Opt::kUseDualMapping) && !Support::test(hri.flags, VirtMem::HardenedRuntimeFlags::kDualMapping))
      continue;
    printf("JitAllocator(%s)\n", ti.name);
    JitAllocator::CreateParams params {};
    params.options = ti.options;
    params.block_size = ti.block_size;
    params.granularity = ti.granularity;
    size_t fixed = 256;
    Wrapper w(&params);
    TestUtils::Random prng(100);
    std::vector<void*> arr(kCount);
    size_t i;
    for (i = 0; i < kCount; i++) arr[i] = w.alloc((prng.next_uint32() % 1024) + 8);
    usage("alloc random", w._allocator);
    for (i = 0; i < kCount; i++) w.release(arr[i]);
    usage("release from begin", w._allocator);
    for (i = 0; i < kCount; i++) arr[i] = w.alloc((prng.next_uint32() % 1024) + 8);
    usage("alloc random again", w._allocator);
    shuffle(arr.data(), kCount, prng);
    for (i = 0; i < kCount / 2; i++) w.release(arr[i]);
    usage("release 50%", w._allocator);
    for (i = 0; i < kCount / 2; i++) arr[i] = w.alloc((prng.next_uint32() % 1024) + 8);
    usage("alloc 50% again", w._allocator);
    for (i = 0; i < kCount; i++) w.release(arr[kCount - i - 1]);
    usage("release from end", w._allocator);
    for (i = 0; i < kCount / 2; i++) arr[i] = w.alloc(fixed);
    usage("alloc fixed", w._allocator);
    for (i = 0; i < kCount / 2; i++) w.shrink(arr[i], 1);
    usage("shrink to 1", w._allocator);
    for (i = kCount / 2; i < kCount; i++) arr[i] = w.alloc(64);
    usage("alloc 64B", w._allocator);
    for (i = 0; i < kCount; i++) w.release(arr[i]);
    usage("release all from begin", w._allocator);
    for (i = 0; i < kCount; i++) arr[i] = w.alloc(fixed);
    usage("alloc fixed all", w._allocator);
    shuffle(arr.data(), kCount, prng);
    for (i = 0; i < kCount / 2; i++) w.release(arr[i]);
    usage("release 50% fixed", w._allocator);
    for (i = 0; i < kCount / 2; i++) arr[i] = w.alloc(fixed);
    usage("alloc 50% fixed again", w._allocator);
    for (i = 0; i < kCount; i++) w.release(arr[kCount - i - 1]);
    usage("release all from end", w._allocator);
  }
  return 0;
}
