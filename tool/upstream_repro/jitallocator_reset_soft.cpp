// Checks whether JitAllocator::reset(ResetPolicy::kSoft) leaves stale RB-tree
// links in the block it keeps (the block's `_tree_nodes` are not cleared before
// it is re-inserted into the freshly reset tree).
//
// JitAllocatorBlock layout (64-bit): _tree_nodes[2] @0, _list_nodes[2] @16,
// _pool @32, _mapping.rx @40, _mapping.rw @48, _block_size @56.
//
// Build against the upstream sources (macOS arm64; U = upstream checkout):
//
//   # debug build (ASMJIT_ASSERT enabled):
//   clang++ -std=c++17 -O1 -g -fsanitize=address -DASMJIT_STATIC \
//     -DASMJIT_NO_X86 -DASMJIT_NO_AARCH64 -I$U jitallocator_reset_soft.cpp \
//     $U/asmjit/core/*.cpp $U/asmjit/support/*.cpp -o reset_soft
//   # release build: add -DNDEBUG
//
// Observed with upstream asmjit-master (2026-11-02):
//
//   debug:   [asmjit] Assertion failed at asmjit/support/arenatree.h (line 173):
//            [asmjit] !node->has_left()
//   release: ERROR: AddressSanitizer: heap-use-after-free ... READ of size 8
//            #0 ArenaTree<JitAllocatorBlock>::get<unsigned char*>() arenatree.h:358
//            #1 JitAllocator::query() jitallocator.cpp:1137
//            freed by: JitAllocatorImpl_deleteBlock() <- JitAllocator::reset()
//
// With `block_to_keep->_tree_nodes[0] = 0; block_to_keep->_tree_nodes[1] = 0;`
// added next to the `_list_nodes` reset in JitAllocator::reset() the program
// runs clean under ASan and reports the kept block with null links.
#include <asmjit/core.h>
#include <stdio.h>
#include <stdint.h>
#include <vector>

using namespace asmjit;

static uintptr_t block_rx(void* block) { return reinterpret_cast<uintptr_t*>(block)[5]; }

int main() {
  // Make the second block of the tested allocator land below the first one
  // and the third one above it: map a 256kB hole below the first block.
  void* hole = nullptr;
  if (VirtMem::alloc(&hole, 256 * 1024, VirtMem::MemoryFlags::kAccessRW) != Error::kOk) return 1;
  printf("hole=%p\n", hole);

  JitAllocator allocator;
  std::vector<void*> ptrs;
  void* first_block = nullptr;
  void* last_block = nullptr;

  for (int i = 0; i < 400; i++) {
    JitAllocator::Span span;
    if (allocator.alloc(Out(span), 1000) != Error::kOk) { printf("alloc failed\n"); return 1; }
    ptrs.push_back(span.rx());
    if (!first_block) {
      first_block = span._block;
      (void)VirtMem::release(hole, 256 * 1024);
    }
    if (span._block != last_block) {
      last_block = span._block;
      printf("block #%zu rx=%p\n", allocator.statistics().block_count(), (void*)block_rx(span._block));
    }
  }

  uintptr_t* tn = reinterpret_cast<uintptr_t*>(first_block);
  printf("first block tree links before reset: left=%p right=%p\n", (void*)(tn[0] & ~uintptr_t(1)), (void*)tn[1]);

  allocator.reset(ResetPolicy::kSoft);
  printf("after reset: blocks=%zu\n", allocator.statistics().block_count());
  printf("kept block tree links after reset: left=%p right=%p red=%d\n", (void*)(tn[0] & ~uintptr_t(1)), (void*)tn[1], int(tn[0] & 1));

  // Pointers into blocks deleted by reset() must not be found; with stale
  // links the lookup walks into the freed JitAllocatorBlock objects.
  int found = 0;
  for (void* p : ptrs) {
    JitAllocator::Span span;
    if (allocator.query(Out(span), p) == Error::kOk) found++;
  }
  printf("query of pointers in deleted blocks succeeded: %d\n", found);
  return 0;
}
