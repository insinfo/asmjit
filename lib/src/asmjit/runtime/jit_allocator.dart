/// AsmJit JIT Allocator
///
/// A simple implementation of memory manager that uses [VirtMem] functions to
/// manage virtual memory for JIT compiled code.
///
/// Ported from asmjit/core/jitallocator.h and jitallocator.cpp.
///
/// Implementation notes (as upstream):
///
/// - Granularity of allocated blocks is different than granularity for a
///   typical C malloc. In addition, the allocator can use several memory pools
///   having a different granularity to minimize the maintenance overhead.
///   Multiple pools feature requires [JitAllocatorOptions.kUseMultiplePools].
///
/// - The allocator doesn't store any information in executable memory,
///   instead, the implementation uses two bit-vectors to manage allocated
///   memory of each allocator-block. The first bit-vector called 'used' is
///   used to track used memory (where each bit represents memory size defined
///   by granularity) and the second bit vector called 'stop' is used as a
///   sentinel to mark where the allocated area ends.
///
/// - Internally, the allocator also uses RB tree to keep track of all blocks
///   across all pools. Each inserted block is added to the tree so it can be
///   matched fast during [JitAllocator.release] and [JitAllocator.shrink].
///
/// Differences from upstream that are not algorithmic:
///
/// - Errors are returned as [AsmJitError] values, `Out<Span>` parameters are
///   [JitAllocatorSpan] objects filled by the callee.
/// - There is no lock: Dart objects are never shared between isolates, so a
///   [JitAllocator] is only ever used by one thread at a time.
/// - The block metadata (`JitAllocatorBlock` and its bit-vectors) lives in the
///   Dart heap instead of a `malloc()`ed chunk; the overhead reported by
///   [JitAllocatorStatistics.overheadSize] uses the upstream
///   `sizeof(JitAllocatorBlock)` so the statistics match upstream exactly.
/// - The destructor is [JitAllocator.dispose].
library;

import 'dart:ffi';
import 'dart:typed_data';

import '../core/error.dart';
import '../core/globals.dart' show ResetPolicy;
import '../support/arena_list.dart';
import '../support/arena_tree.dart';
import '../support/bit_vector_ops.dart';
import 'virtmem.dart';

// =============================================================================
// JitAllocator - Constants
// =============================================================================

/// Number of pools to use when [JitAllocatorOptions.kUseMultiplePools] is set.
///
/// Each pool increases granularity twice to make memory management more
/// efficient. Ideal number of pools appears to be 3 to 4 as it distributes
/// small and large functions properly.
const int _kJitAllocatorMultiPoolCount = 3;

/// Minimum granularity (and the default granularity for pool #0).
const int _kJitAllocatorBaseGranularity = 64;

/// Maximum block size (64MB).
const int _kJitAllocatorMaxBlockSize = 1024 * 1024 * 64;

/// `Support::BitWord` (`uintptr_t`).
final BitWordType _kBitWord =
    sizeOf<IntPtr>() == 8 ? BitWordType.u64 : BitWordType.u32;

/// `sizeof(Support::BitWord)`.
final int _kBitWordBytes = sizeOf<IntPtr>();

/// `sizeof(JitAllocatorBlock)` of upstream (used by the statistics only):
/// two tree links, two list links, pool pointer, dual mapping (2 pointers),
/// block size, six 32-bit fields and two bit-vector pointers.
final int _kJitAllocatorBlockStructSize = sizeOf<IntPtr>() * 10 + 6 * 4;

/// `JitAllocator_default_fill_pattern()`.
int _defaultFillPattern() {
  switch (Abi.current()) {
    case Abi.linuxX64:
    case Abi.linuxIA32:
    case Abi.macosX64:
    case Abi.windowsX64:
    case Abi.windowsIA32:
    case Abi.androidX64:
    case Abi.androidIA32:
    case Abi.fuchsiaX64:
      // X86 and X86_64 - 4x 'int3' instruction.
      return 0xCCCCCCCC;
    default:
      // Unknown...
      return 0;
  }
}

// =============================================================================
// JitAllocator - Options & Params
// =============================================================================

/// Options used by [JitAllocator] (`JitAllocatorOptions`).
abstract final class JitAllocatorOptions {
  /// No options.
  static const int kNone = 0;

  /// Enables the use of an anonymous memory-mapped memory that is mapped into
  /// two buffers having a different pointer. The first buffer has read and
  /// execute permissions and the second buffer has read+write permissions.
  ///
  /// See [VirtMem.allocDualMapping] for more details about this feature.
  ///
  /// Dual mapping would be automatically turned on by [JitAllocator] in case
  /// of hardened runtime that enforces `W^X` policy, so specifying this flag
  /// is essentially forcing to use dual mapped pages even when RWX pages can
  /// be allocated and dual mapping is not necessary.
  static const int kUseDualMapping = 0x00000001;

  /// Enables the use of multiple pools with increasing granularity instead of
  /// a single pool. This flag would enable 3 internal pools in total having
  /// 64, 128, and 256 bytes granularity.
  ///
  /// This feature is only recommended for users that generate a lot of code
  /// and would like to minimize the overhead of `JitAllocator` itself by
  /// having blocks of different allocation granularities. Using this feature
  /// only for few allocations won't pay off as the allocator may need to
  /// create more blocks initially before it can take the advantage of variable
  /// block granularity.
  static const int kUseMultiplePools = 0x00000002;

  /// Always fill reserved memory by a fill-pattern.
  ///
  /// Causes a new block to be cleared by the fill pattern and freshly released
  /// memory to be cleared before making it ready for another use.
  static const int kFillUnusedMemory = 0x00000004;

  /// When this flag is set the allocator would immediately release unused
  /// blocks during `release()` or `reset()`. When this flag is not set the
  /// allocator would keep one empty block in each pool to prevent excessive
  /// virtual memory allocations and deallocations in border cases, which
  /// involve constantly allocating and deallocating a single block caused by
  /// repetitive calling `alloc()` and `release()` when the allocator has
  /// either no blocks or have all blocks fully occupied.
  static const int kImmediateRelease = 0x00000008;

  /// This flag enables placing functions (or allocating memory) at the very
  /// beginning of each memory mapped region.
  ///
  /// Initially, this was the default behavior. However, LLVM developers
  /// working on undefined behavior sanitizer (UBSAN) decided that they want to
  /// store metadata before each function and to access such metadata before an
  /// indirect function call. This means that the instrumented code always
  /// reads from `[fn_ptr - 8]` to decode whether the function has his metadata
  /// present. However, reading 8 bytes below a function means that if a
  /// function is placed at the very beginning of a memory mapped region, it
  /// could try to read bytes that are inaccessible.
  ///
  /// This flag controls a workaround to make it possible to use LLVM UBSAN
  /// with AsmJit's [JitAllocator].
  static const int kDisableInitialPadding = 0x00000010;

  /// Enables the use of large pages, if they are supported and the process
  /// can actually allocate them.
  ///
  /// This flag is a hint - if large pages can be allocated, JitAllocator would
  /// try to allocate them. However, if the allocation fails, it will still try
  /// to fallback to use regular pages as [JitAllocator] is designed to
  /// minimize allocation failures, so a regular page is better than no page at
  /// all. Also, if a block [JitAllocator] wants to allocate is too small to
  /// consume a whole large page, regular page(s) will be allocated as well.
  static const int kUseLargePages = 0x00000020;

  /// Forces [JitAllocator] to always align block size to be at least as big
  /// as a large page, if large pages are enabled. This option does nothing if
  /// large pages are disabled.
  static const int kAlignBlockSizeToLargePage = 0x00000040;

  /// Use a custom fill pattern, must be combined with [kFillUnusedMemory].
  static const int kCustomFillPattern = 0x10000000;
}

/// Parameters that can be passed to [JitAllocator] constructor
/// (`JitAllocator::CreateParams`).
///
/// Zero means the default value.
class JitAllocatorCreateParams {
  /// Allocator options, see [JitAllocatorOptions].
  ///
  /// No options are used by default.
  int options;

  /// Base size of a single block in bytes (default 64kB).
  ///
  /// Block size must be equal to or greater than page size and must be power
  /// of 2. If the input is not valid then the default block size will be used
  /// instead.
  int blockSize;

  /// Base granularity (and also natural alignment) of allocations in bytes
  /// (default 64).
  ///
  /// Since the `JitAllocator` uses bit-arrays to mark used memory the
  /// granularity also specifies how many bytes correspond to a single bit in
  /// such bit-array. Higher granularity means more waste of virtual memory (as
  /// it increases the natural alignment), but smaller bit-arrays as less bits
  /// would be required per a single block.
  int granularity;

  /// Pattern to use to fill unused memory.
  ///
  /// Only used if [JitAllocatorOptions.kCustomFillPattern] is set.
  int fillPattern;

  JitAllocatorCreateParams({
    this.options = JitAllocatorOptions.kNone,
    this.blockSize = 0,
    this.granularity = 0,
    this.fillPattern = 0,
  });

  /// Reset the content of `CreateParams`.
  void reset() {
    options = JitAllocatorOptions.kNone;
    blockSize = 0;
    granularity = 0;
    fillPattern = 0;
  }
}

// =============================================================================
// JitAllocator - Span
// =============================================================================

/// [JitAllocatorSpan] flags (`JitAllocator::Span::Flags`).
abstract final class JitAllocatorSpanFlags {
  /// No flags.
  static const int kNone = 0;

  /// The process has never executed the region of the span.
  ///
  /// If this flag is set on a [JitAllocatorSpan] it would mean that the
  /// allocator can avoid flushing instruction cache after a code has been
  /// written to it.
  static const int kInstructionCacheClean = 0x00000001;
}

/// A memory reference returned by [JitAllocator.alloc]
/// (`JitAllocator::Span`).
///
/// Span contains everything needed to actually write new code to the memory
/// chunk it references.
final class JitAllocatorSpan {
  /// Address of memory that has Read and Execute permissions.
  Pointer<Void> _rx = nullptr;

  /// Address of memory that has Read and Write permissions.
  Pointer<Void> _rw = nullptr;

  /// Size of the span in bytes (rounded up to the allocation granularity).
  int _size = 0;

  /// Memory block maintained by [JitAllocator] (private).
  JitAllocatorBlock? _block;

  /// Span flags, see [JitAllocatorSpanFlags].
  int _flags = JitAllocatorSpanFlags.kNone;

  JitAllocatorSpan();

  /// `Span{}`.
  void _reset() {
    _rx = nullptr;
    _rw = nullptr;
    _size = 0;
    _block = null;
    _flags = JitAllocatorSpanFlags.kNone;
  }

  /// Returns a pointer having Read & Execute permissions (references
  /// executable memory).
  ///
  /// This pointer is never NULL if the allocation succeeded, it points to an
  /// executable memory.
  Pointer<Void> get rx => _rx;

  /// Returns a pointer having Read & Write permissions (references writable
  /// memory).
  ///
  /// Depending on the type of the allocation strategy this could either be:
  ///
  ///   - the same address as returned by `rx` if the allocator uses RWX
  ///     mapping (pages have all of Read, Write, and Execute permissions) or
  ///     MAP_JIT, which requires either [ProtectJitReadWriteScope] or to call
  ///     [VirtMem.protectJitMemory] manually.
  ///   - a valid pointer, but not the same as `rx` - this would be valid if
  ///     dual mapping is used.
  ///
  /// If `rw` returns a non-null pointer it's important to use either
  /// [VirtMem.protectJitMemory] or [ProtectJitReadWriteScope] to guard the
  /// write, because in case of `MAP_JIT` it would temporarily switch the
  /// permissions of the pointer to RW (that's per thread permissions).
  ///
  /// If [ProtectJitReadWriteScope] is not used it's important to clear the
  /// instruction cache via [VirtMem.flushInstructionCache] after the write is
  /// done.
  Pointer<Void> get rw => _rw;

  /// Returns size of this span, aligned to the allocator granularity.
  int get size => _size;

  /// Returns span flags, see [JitAllocatorSpanFlags].
  int get flags => _flags;

  /// Shrinks this span to `newSize`.
  ///
  /// This is the only function that is able to change the size of a span, and
  /// it's only use case is to shrink the span size during
  /// [JitAllocator.writeWith]. When the writer detects that the span size
  /// shrunk, it will automatically shrink the memory used by the span, and
  /// propagate the new aligned size to the caller.
  void shrink(int newSize) => _size = _size < newSize ? _size : newSize;

  /// Returns whether [rw] returns a non-null pointer.
  bool get isDirectlyWritable => _rw != nullptr;
}

// =============================================================================
// JitAllocator - Statistics
// =============================================================================

/// Statistics provided by [JitAllocator] (`JitAllocator::Statistics`).
final class JitAllocatorStatistics {
  int _blockCount = 0;
  int _allocationCount = 0;
  int _usedSize = 0;
  int _reservedSize = 0;
  int _overheadSize = 0;

  JitAllocatorStatistics();

  /// Resets the statistics to all zeros.
  void reset() {
    _blockCount = 0;
    _allocationCount = 0;
    _usedSize = 0;
    _reservedSize = 0;
    _overheadSize = 0;
  }

  /// Returns count of blocks managed by `JitAllocator` at the moment.
  int get blockCount => _blockCount;

  /// Returns the number of active allocations.
  int get allocationCount => _allocationCount;

  /// Returns how many bytes are currently used.
  int get usedSize => _usedSize;

  /// Returns the number of bytes unused by the allocator at the moment.
  int get unusedSize => _reservedSize - _usedSize;

  /// Returns the total number of bytes reserved by the allocator (sum of
  /// sizes of all blocks).
  int get reservedSize => _reservedSize;

  /// Returns the number of bytes the allocator needs to manage the allocated
  /// memory.
  int get overheadSize => _overheadSize;

  double get usedRatio => usedSize / (reservedSize + 1e-16);

  double get unusedRatio => unusedSize / (reservedSize + 1e-16);

  double get overheadRatio => overheadSize / (reservedSize + 1e-16);

  @override
  String toString() => 'JitAllocatorStatistics(blockCount: $blockCount, '
      'allocationCount: $allocationCount, usedSize: $usedSize, '
      'reservedSize: $reservedSize, overheadSize: $overheadSize)';
}

// =============================================================================
// JitAllocator - BitVectorRangeIterator
// =============================================================================

/// Iterates ranges of consecutive bits equal to `bit` in a bit-vector
/// (`BitVectorRangeIterator<T, B>`).
final class BitVectorRangeIterator {
  final List<int> _data;
  final BitWordType _type;
  final int _xorMask;

  int _ptr = 0;
  int _idx = 0;
  int _end = 0;
  int _bitWord = 0;

  /// The start of the range found by the last successful [nextRange].
  int rangeStart = 0;

  /// The end of the range found by the last successful [nextRange].
  int rangeEnd = 0;

  /// Creates an iterator of ranges of bits equal to [bit] in
  /// `[start, end)` (the whole vector if not given).
  BitVectorRangeIterator(
    this._data,
    int bitWordCount, {
    int bit = 0,
    BitWordType type = BitWordType.u64,
    int? start,
    int? end,
  })  : _type = type,
        _xorMask = bit == 0 ? type.ones : 0 {
    _init(bitWordCount, start ?? 0, end ?? bitWordCount * type.bitSize);
  }

  void _init(int bitWordCount, int start, int end) {
    final bitSize = _type.bitSize;
    assert(bitWordCount >= (end + bitSize - 1) ~/ bitSize);

    final idx = start - start % bitSize;
    final ptr = idx ~/ bitSize;

    var bitWord = 0;
    if (idx < end) {
      bitWord =
          ((_data[ptr] ^ _xorMask) & _type.shl(_type.ones, start % bitSize)) &
              _type.ones;
    }

    _ptr = ptr;
    _idx = idx;
    _end = end;
    _bitWord = bitWord;
  }

  /// Finds the next range, stores it to [rangeStart] and [rangeEnd] and
  /// returns true; returns false (leaving [rangeStart] and [rangeEnd]
  /// unchanged) if there are no more ranges.
  ///
  /// A range of consecutive bits is extended across bit words only until it
  /// is at least [rangeHint] bits long.
  bool nextRange([int rangeHint = -1]) {
    final t = _type;
    final bitSize = t.bitSize;
    final ones = t.ones;
    // `std::numeric_limits<size_t>::max()`.
    final hint = rangeHint < 0 ? 0x7FFFFFFFFFFFFFFF : rangeHint;

    // Skip all empty BitWords.
    while (_bitWord == 0) {
      _idx += bitSize;
      if (_idx >= _end) return false;
      _bitWord = (_data[++_ptr] ^ _xorMask) & ones;
    }

    final i = bitWordCtz(_bitWord);

    final start = _idx + i;
    var end = 0;
    _bitWord = t.not(_bitWord ^ t.not(t.shl(ones, i)));

    if (_bitWord == 0) {
      end = _min(_idx + bitSize, _end);
      while (end - start < hint) {
        _idx += bitSize;
        if (_idx >= _end) break;

        _bitWord = (_data[++_ptr] ^ _xorMask) & ones;
        if (_bitWord != ones) {
          final j = bitWordCtz(t.not(_bitWord));
          end = _min(_idx + j, _end);
          _bitWord = (_bitWord ^ t.not(t.shl(ones, j))) & ones;
          break;
        }

        end = _min(_idx + bitSize, _end);
        _bitWord = 0;
        continue;
      }
    } else {
      final j = bitWordCtz(_bitWord);
      end = _min(_idx + j, _end);

      _bitWord = t.not(_bitWord ^ t.not(t.shl(ones, j)));
    }

    rangeStart = start;
    rangeEnd = end;
    return true;
  }
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;
int _alignUp(int x, int alignment) => (x + alignment - 1) & ~(alignment - 1);
bool _isPowerOf2(int x) => x != 0 && (x & (x - 1)) == 0;
int _ctz(int x) => bitWordCtz(x);

// =============================================================================
// JitAllocator - Pool
// =============================================================================

final class _JitAllocatorPool {
  /// Double linked list of blocks.
  final ArenaList<JitAllocatorBlock> blocks = ArenaList<JitAllocatorBlock>();

  /// Where to start looking first.
  JitAllocatorBlock? cursor;

  /// Count of blocks.
  int blockCount = 0;

  /// Allocation granularity.
  final int granularity;

  /// Log2(granularity).
  final int granularityLog2;

  /// Count of empty blocks (either 0 or 1 as we won't keep more blocks empty).
  int emptyBlockCount = 0;

  /// Number of bits reserved across all blocks.
  final List<int> totalAreaSize = [0, 0];

  /// Number of bits used across all blocks.
  final List<int> totalAreaUsed = [0, 0];

  /// Overhead of all blocks (in bytes).
  int totalOverheadBytes = 0;

  _JitAllocatorPool(this.granularity) : granularityLog2 = _ctz(granularity);

  void reset() {
    blocks.reset();
    cursor = null;
    blockCount = 0;
    totalAreaSize[0] = 0;
    totalAreaSize[1] = 0;
    totalAreaUsed[0] = 0;
    totalAreaUsed[1] = 0;
    totalOverheadBytes = 0;
  }

  int byteSizeFromAreaSize(int areaSize) => areaSize * granularity;

  int areaSizeFromByteSize(int size) =>
      (size + granularity - 1) >>> granularityLog2;

  int bitWordCountFromAreaSize(int areaSize) {
    final kBitWordSizeInBits = _kBitWord.bitSize;
    return _alignUp(areaSize, kBitWordSizeInBits) ~/ kBitWordSizeInBits;
  }
}

// =============================================================================
// JitAllocator - Block
// =============================================================================

/// A block of virtual memory managed by [JitAllocator]
/// (`JitAllocatorBlock`).
///
/// This class is considered private and should never be used nor inspected
/// outside of AsmJit.
final class JitAllocatorBlock extends ArenaTreeNode
    with ArenaListNode<JitAllocatorBlock> {
  /// Block has initial padding, see
  /// [JitAllocatorOptions.kDisableInitialPadding].
  static const int kFlagInitialPadding = 0x00000001;

  /// Block is empty.
  static const int kFlagEmpty = 0x00000002;

  /// Block is dirty (dirty largestUnusedArea, searchStart, searchEnd, ...).
  static const int kFlagDirty = 0x00000004;

  /// Block is in incremental mode, which means that there is no memory used
  /// after searchStart.
  static const int kFlagIncremental = 0x00000008;

  /// Block represents memory that is using large pages.
  static const int kFlagLargePages = 0x00000010;

  /// Block represents memory that is dual-mapped.
  static const int kFlagDualMapped = 0x00000020;

  static int _initialAreaStartByFlags(int flags) => flags & kFlagInitialPadding;

  /// Link to the pool that owns this block.
  final _JitAllocatorPool _pool;

  /// Virtual memory mapping - either single mapping (both pointers equal) or
  /// dual mapping, where one pointer is Read+Execute and the second
  /// Read+Write.
  final DualMapping _mapping;

  /// Virtual memory size (block size) [bytes].
  final int _blockSize;

  /// Block flags.
  int _flags;

  /// Size of the whole block area (bit-vector size).
  final int _areaSize;

  /// Used area (number of bits in bit-vector used).
  int _areaUsed = 0;

  /// The largest unused continuous area in the bit-vector (or `areaSize` to
  /// initiate rescan).
  int _largestUnusedArea = 0;

  /// Start of a search range (for unused bits).
  int _searchStart = 0;

  /// End of a search range (for unused bits).
  int _searchEnd = 0;

  /// Used bit-vector (0 = unused, 1 = used).
  final List<int> _usedBitVector;

  /// Stop bit-vector (0 = don't care, 1 = stop).
  final List<int> _stopBitVector;

  JitAllocatorBlock._(
    this._pool,
    this._mapping,
    this._blockSize,
    this._flags,
    this._usedBitVector,
    this._stopBitVector,
    this._areaSize,
  ) {
    _clearBlock();
  }

  /// Base address of the Read+Execute mapping.
  int get rxAddress => _mapping.rx.address;

  /// Base address of the Read+Write mapping.
  int get rwAddress => _mapping.rw.address;

  /// Virtual memory size of the block in bytes.
  int get blockSize => _blockSize;

  /// Tests whether the block represents dual-mapped memory.
  bool get isDualMapped => _hasFlag(kFlagDualMapped);

  /// Tests whether the block represents memory that uses large pages.
  bool get hasLargePages => _hasFlag(kFlagLargePages);

  Pointer<Uint8> get _rwPtr => _mapping.rw.cast<Uint8>();

  bool _hasFlag(int f) => (_flags & f) != 0;
  void _addFlags(int f) => _flags |= f;
  void _clearFlags(int f) => _flags &= ~f;

  bool get _isEmpty => _hasFlag(kFlagEmpty);
  bool get _isDirty => _hasFlag(kFlagDirty);
  bool get _isIncremental => _hasFlag(kFlagIncremental);
  bool get _hasInitialPadding => _hasFlag(kFlagInitialPadding);
  int get _initialAreaStart => _initialAreaStartByFlags(_flags);
  int get _statIndex => hasLargePages ? 1 : 0;

  int get _areaAvailable => _areaSize - _areaUsed;

  void _clearBlock() {
    final bit = _hasInitialPadding;

    _usedBitVector.fillRange(0, _usedBitVector.length, 0);
    _stopBitVector.fillRange(0, _stopBitVector.length, 0);

    bitVectorSetBit(_usedBitVector, 0, bit, _kBitWord);
    bitVectorSetBit(_stopBitVector, 0, bit, _kBitWord);

    final start = _initialAreaStartByFlags(_flags);
    _areaUsed = start;
    _largestUnusedArea = _areaSize - start;
    _searchStart = start;
    _searchEnd = _areaSize;

    _addFlags(kFlagEmpty | kFlagIncremental);
    _clearFlags(kFlagDirty);
  }

  void _markAllocatedArea(int allocatedAreaStart, int allocatedAreaEnd) {
    final allocatedAreaSize = allocatedAreaEnd - allocatedAreaStart;

    // Mark the newly allocated space as occupied and also the sentinel.
    bitVectorFill(
        _usedBitVector, allocatedAreaStart, allocatedAreaSize, _kBitWord);
    bitVectorSetBit(_stopBitVector, allocatedAreaEnd - 1, true, _kBitWord);

    // Update search region and statistics.
    _pool.totalAreaUsed[_statIndex] += allocatedAreaSize;
    _areaUsed += allocatedAreaSize;

    if (_areaAvailable == 0) {
      _searchStart = _areaSize;
      _searchEnd = 0;
      _largestUnusedArea = 0;

      _clearFlags(kFlagDirty | kFlagEmpty);
    } else {
      if (_searchStart == allocatedAreaStart) {
        _searchStart = allocatedAreaEnd;
      }

      if (_searchEnd == allocatedAreaEnd) {
        _searchEnd = allocatedAreaStart;
      }

      _addFlags(kFlagDirty);
      _clearFlags(kFlagEmpty);
    }
  }

  void _markReleasedArea(int releasedAreaStart, int releasedAreaEnd) {
    final releasedAreaSize = releasedAreaEnd - releasedAreaStart;

    // Update the search region and statistics.
    _pool.totalAreaUsed[_statIndex] -= releasedAreaSize;
    _areaUsed -= releasedAreaSize;

    // Unmark occupied bits and also the sentinel.
    bitVectorClear(
        _usedBitVector, releasedAreaStart, releasedAreaSize, _kBitWord);
    bitVectorSetBit(_stopBitVector, releasedAreaEnd - 1, false, _kBitWord);

    if (_isIncremental && _searchStart == releasedAreaEnd) {
      // Incremental mode: If the area released is at the end of the fully
      // used area, we would like to keep the incremental mode of the block.
      // In order to do that, we are going to use a different approach -
      // decrement `_searchStart` and increment `_largestUnusedArea`, which are
      // essential for incremental mode blocks.
      assert(_searchStart >= releasedAreaSize);
      _searchStart -= releasedAreaSize;
      _largestUnusedArea += releasedAreaSize;
    } else {
      _searchStart = _min(_searchStart, releasedAreaStart);
      _searchEnd = _max(_searchEnd, releasedAreaEnd);
      _clearFlags(kFlagDirty | kFlagIncremental);

      if (_areaUsed == _initialAreaStart) {
        _searchStart = _initialAreaStart;
        _searchEnd = _areaSize;
        _largestUnusedArea = _areaSize - _initialAreaStart;
        _addFlags(kFlagEmpty);
      } else {
        _addFlags(kFlagDirty);
      }
    }
  }

  void _markShrunkArea(int shrunkAreaStart, int shrunkAreaEnd) {
    final shrunkAreaSize = shrunkAreaEnd - shrunkAreaStart;

    // Shrunk area cannot start at zero as it would mean that we have shrunk
    // the first block to zero bytes, which is not allowed as such block must
    // be released instead.
    assert(shrunkAreaStart != 0);
    assert(shrunkAreaSize != 0);

    // Update the search region and statistics.
    _pool.totalAreaUsed[_statIndex] -= shrunkAreaSize;
    _areaUsed -= shrunkAreaSize;

    if (_isIncremental && _searchStart == shrunkAreaEnd) {
      _searchStart -= shrunkAreaSize;
      _largestUnusedArea += shrunkAreaSize;
    } else {
      _searchStart = _min(_searchStart, shrunkAreaStart);
      _searchEnd = _max(_searchEnd, shrunkAreaEnd);

      _clearFlags(kFlagIncremental);
      _addFlags(kFlagDirty);
    }

    // Unmark the released space and move the sentinel.
    bitVectorClear(_usedBitVector, shrunkAreaStart, shrunkAreaSize, _kBitWord);
    bitVectorSetBit(_stopBitVector, shrunkAreaEnd - 1, false, _kBitWord);
    bitVectorSetBit(_stopBitVector, shrunkAreaStart - 1, true, _kBitWord);
  }

  /// RBTree default CMP uses '<' and '>' operators.
  static int _compare(JitAllocatorBlock a, JitAllocatorBlock b) {
    final ax = a.rxAddress;
    final bx = b.rxAddress;
    return ax < bx ? -1 : (ax > bx ? 1 : 0);
  }

  /// Special implementation for querying blocks by `key`, which must be in
  /// `[BlockPtr, BlockPtr + BlockSize)` range.
  static int _compareKey(JitAllocatorBlock node, int key) {
    final rx = node.rxAddress;
    final lt = rx + node._blockSize <= key;
    final gt = rx > key;
    return (gt ? 1 : 0) - (lt ? 1 : 0);
  }
}

// =============================================================================
// JitAllocator - PrivateImpl
// =============================================================================

final class _JitAllocatorPrivateImpl {
  /// Allocator options.
  final int options;

  /// Base block size (0 if the allocator is not initialized).
  final int blockSize;

  /// Base granularity (0 if the allocator is not initialized).
  final int granularity;

  /// A pattern that is used to fill unused memory if secure mode is enabled.
  final int fillPattern;

  /// System page size (also a minimum block size).
  final int pageSize;

  /// Number of active allocations.
  int allocationCount = 0;

  /// Blocks from all pools in RBTree.
  final ArenaTree<JitAllocatorBlock> tree =
      ArenaTree<JitAllocatorBlock>(JitAllocatorBlock._compare);

  /// Allocator pools.
  final List<_JitAllocatorPool> pools;

  _JitAllocatorPrivateImpl({
    required this.options,
    required this.blockSize,
    required this.granularity,
    required this.fillPattern,
    required this.pageSize,
    required this.pools,
  });

  int get poolCount => pools.length;
}

// =============================================================================
// JitAllocator - Utilities
// =============================================================================

_JitAllocatorPrivateImpl _jitAllocatorNewImpl(
    JitAllocatorCreateParams? params) {
  final vmInfo = VirtMem.info();

  params ??= JitAllocatorCreateParams();

  var options = params.options;
  var blockSize = params.blockSize;
  var granularity = params.granularity;
  var fillPattern = params.fillPattern;

  // Setup pool count to [1..3].
  var poolCount = 1;
  if ((options & JitAllocatorOptions.kUseMultiplePools) != 0) {
    poolCount = _kJitAllocatorMultiPoolCount;
  }

  // Setup block size [64kB..256MB].
  if (blockSize < 64 * 1024 ||
      blockSize > 256 * 1024 * 1024 ||
      !_isPowerOf2(blockSize)) {
    blockSize = vmInfo.pageGranularity;
  }

  // Setup granularity [64..256].
  if (granularity < 64 || granularity > 256 || !_isPowerOf2(granularity)) {
    granularity = _kJitAllocatorBaseGranularity;
  }

  // Setup fill-pattern.
  if ((options & JitAllocatorOptions.kCustomFillPattern) == 0) {
    fillPattern = _defaultFillPattern();
  }

  final hardenedRtInfo = VirtMem.hardenedRuntimeInfo();
  if (hardenedRtInfo.hasFlag(HardenedRuntimeFlags.kEnabled)) {
    // If we are running within a hardened environment (mapping RWX is not
    // allowed) then we have to use dual mapping or other runtime capabilities
    // like Apple specific MAP_JIT. There is no point in not enabling these as
    // otherwise the allocation would fail and JitAllocator would not be able
    // to allocate memory.
    if (!hardenedRtInfo.hasFlag(HardenedRuntimeFlags.kMapJit)) {
      options |= JitAllocatorOptions.kUseDualMapping;
    }
  }

  return _JitAllocatorPrivateImpl(
    options: options,
    blockSize: blockSize,
    granularity: granularity,
    fillPattern: fillPattern & 0xFFFFFFFF,
    pageSize: vmInfo.pageSize,
    pools: [
      for (var poolId = 0; poolId < poolCount; poolId++)
        _JitAllocatorPool(granularity << poolId),
    ],
  );
}

int _jitAllocatorSizeToPoolId(_JitAllocatorPrivateImpl impl, int size) {
  var poolId = impl.poolCount - 1;
  var granularity = impl.granularity << poolId;

  while (poolId != 0) {
    if (_alignUp(size, granularity) == size) break;
    poolId--;
    granularity >>= 1;
  }

  return poolId;
}

int _jitAllocatorBitVectorSizeToByteSize(int areaSize) {
  final kBitWordSizeInBits = _kBitWord.bitSize;
  return ((areaSize + kBitWordSizeInBits - 1) ~/ kBitWordSizeInBits) *
      _kBitWordBytes;
}

int _jitAllocatorCalculateIdealBlockSize(
    _JitAllocatorPrivateImpl impl, _JitAllocatorPool pool, int allocationSize) {
  final last = pool.blocks.last;
  var blockSize = last != null ? last.blockSize : impl.blockSize;

  // We have to increase the allocationSize if we know that the block must
  // provide padding.
  if ((impl.options & JitAllocatorOptions.kDisableInitialPadding) == 0) {
    allocationSize += pool.granularity;
  }

  if (blockSize < _kJitAllocatorMaxBlockSize) blockSize *= 2;

  if (allocationSize > blockSize) {
    blockSize = _alignUp(allocationSize, impl.blockSize);
  }

  return blockSize;
}

/// `JitAllocator_fill_pattern()`.
void _jitAllocatorFillPattern(Pointer<Uint8> mem, int pattern, int byteSize) {
  // NOTE: This is always used to fill a pattern in allocated / freed memory.
  // The allocation has always a granularity that is greater than the pattern,
  // however, when shrink() is used, we may end up having an unaligned start,
  // so deal with it here and then copy aligned pattern in the loop.
  if ((mem.address & 0x1) != 0 && byteSize >= 1) {
    mem[0] = pattern & 0xFF;
    mem = mem + 1;
    byteSize--;
  }

  if ((mem.address & 0x2) != 0 && byteSize >= 2) {
    mem.cast<Uint16>()[0] = pattern & 0xFFFF;
    mem = mem + 2;
    byteSize -= 2;
  }

  // Something would be seriously broken if we end up with aligned `mem`, but
  // unaligned `byteSize`.
  assert((byteSize & 0x3) == 0);

  final n = byteSize ~/ 4;
  if (n != 0) mem.cast<Uint32>().asTypedList(n).fillRange(0, n, pattern);
}

/// Allocate a new `JitAllocatorBlock` for the given `blockSize`.
///
/// NOTE: The block doesn't have `kFlagEmpty` flag set, because the new block
/// is only allocated when it's actually needed, so it would be cleared anyway.
(AsmJitError, JitAllocatorBlock?) _jitAllocatorNewBlock(
    _JitAllocatorPrivateImpl impl, _JitAllocatorPool pool, int blockSize) {
  var blockFlags = 0;
  if ((impl.options & JitAllocatorOptions.kDisableInitialPadding) == 0) {
    blockFlags |= JitAllocatorBlock.kFlagInitialPadding;
  }

  final virtMem = DualMapping();
  const memFlags = MemoryFlags.kAccessRWX;

  if ((impl.options & JitAllocatorOptions.kUseDualMapping) != 0) {
    final err = VirtMem.allocDualMapping(virtMem, blockSize, memFlags);
    if (err != AsmJitError.ok) return (err, null);
    blockFlags |= JitAllocatorBlock.kFlagDualMapped;
  } else {
    var allocateRegularPages = true;
    if ((impl.options & JitAllocatorOptions.kUseLargePages) != 0) {
      final largePageSize = VirtMem.largePageSize();
      final tryLargePage = blockSize >= largePageSize ||
          (impl.options & JitAllocatorOptions.kAlignBlockSizeToLargePage) != 0;

      // Only proceed if we can actually allocate large pages.
      if (largePageSize != 0 && tryLargePage) {
        final largeBlockSize = _alignUp(blockSize, largePageSize);
        final (err, ptr) = VirtMem.alloc(
            largeBlockSize, memFlags | MemoryFlags.kMMapLargePages);

        // Fallback to regular pages if large page(s) allocation failed.
        if (err == AsmJitError.ok) {
          virtMem.rx = ptr;
          allocateRegularPages = false;
          blockSize = largeBlockSize;
          blockFlags |= JitAllocatorBlock.kFlagLargePages;
        }
      }
    }

    // Called either if large pages were not requested or large page(s)
    // allocation failed.
    if (allocateRegularPages) {
      final (err, ptr) = VirtMem.alloc(blockSize, memFlags);
      if (err != AsmJitError.ok) return (err, null);
      virtMem.rx = ptr;
    }

    virtMem.rw = virtMem.rx;
  }

  final areaSize = (blockSize + pool.granularity - 1) >>> pool.granularityLog2;
  final kBitWordSizeInBits = _kBitWord.bitSize;
  final bitWordCount =
      (areaSize + kBitWordSizeInBits - 1) ~/ kBitWordSizeInBits;

  // Fill the allocated virtual memory if secure mode is enabled.
  if ((impl.options & JitAllocatorOptions.kFillUnusedMemory) != 0) {
    final scope = ProtectJitReadWriteScope(virtMem.rw, blockSize);
    try {
      _jitAllocatorFillPattern(
          virtMem.rw.cast<Uint8>(), impl.fillPattern, blockSize);
    } finally {
      scope.close();
    }
  }

  List<int> newBitVector() => _kBitWord.bitSize == 64
      ? Uint64List(bitWordCount)
      : Uint32List(bitWordCount);

  final block = JitAllocatorBlock._(pool, virtMem, blockSize, blockFlags,
      newBitVector(), newBitVector(), areaSize);
  return (AsmJitError.ok, block);
}

void _jitAllocatorImplDeleteBlock(
    _JitAllocatorPrivateImpl impl, JitAllocatorBlock block) {
  if (block._hasFlag(JitAllocatorBlock.kFlagDualMapped)) {
    VirtMem.releaseDualMapping(block._mapping, block.blockSize);
  } else {
    VirtMem.release(block._mapping.rx, block.blockSize);
  }
}

void _jitAllocatorImplInsertBlock(
    _JitAllocatorPrivateImpl impl, JitAllocatorBlock block) {
  final pool = block._pool;

  pool.cursor ??= block;

  // Add to RBTree and List.
  impl.tree.insert(block);
  pool.blocks.append(block);

  // Update statistics.
  final statIndex = block._statIndex;
  pool.blockCount++;
  pool.totalAreaSize[statIndex] += block._areaSize;
  pool.totalAreaUsed[statIndex] += block._areaUsed;
  pool.totalOverheadBytes += _kJitAllocatorBlockStructSize +
      _jitAllocatorBitVectorSizeToByteSize(block._areaSize) * 2;
}

void _jitAllocatorImplRemoveBlock(
    _JitAllocatorPrivateImpl impl, JitAllocatorBlock block) {
  final pool = block._pool;

  // Remove from RBTree and List.
  if (identical(pool.cursor, block)) {
    pool.cursor = block.hasPrev ? block.prev : block.next;
  }

  impl.tree.remove(block);
  pool.blocks.unlink(block);

  // Update statistics.
  final statIndex = block._statIndex;
  pool.blockCount--;
  pool.totalAreaSize[statIndex] -= block._areaSize;
  pool.totalAreaUsed[statIndex] -= block._areaUsed;
  pool.totalOverheadBytes -= _kJitAllocatorBlockStructSize +
      _jitAllocatorBitVectorSizeToByteSize(block._areaSize) * 2;
}

void _jitAllocatorImplWipeOutBlock(
    _JitAllocatorPrivateImpl impl, JitAllocatorBlock block) {
  if (block._hasFlag(JitAllocatorBlock.kFlagEmpty)) return;

  final pool = block._pool;
  if ((impl.options & JitAllocatorOptions.kFillUnusedMemory) != 0) {
    VirtMem.protectJitMemory(ProtectJitAccess.readWrite);
    try {
      final granularity = pool.granularity;
      final rwPtr = block._rwPtr;

      // Deviation from upstream: upstream iterates the used bit-vector with
      // `BitVectorRangeIterator<Support::BitWord, 0>`, which yields the ranges
      // of *zero* bits (the unused areas, already filled when released), so
      // the memory that was in use is never wiped and `reset(kSoft)` hands
      // out spans still holding the old code although `kFillUnusedMemory`
      // promises released memory is cleared. Proof (upstream release build,
      // tool/upstream_repro/jitallocator_misc.cpp): with kFillUnusedMemory
      // and fill pattern 0xCC, a span written with 0x5A still reads 0x5A
      // after `reset(ResetPolicy::kSoft)` and the next `alloc()` returns the
      // same address still holding 0x5A; iterating set bits (`B = 1`) gives
      // 0xCC. The set bits (used areas) are iterated here.
      final it = BitVectorRangeIterator(
          block._usedBitVector, pool.bitWordCountFromAreaSize(block._areaSize),
          bit: 1, type: _kBitWord);

      while (it.nextRange()) {
        final spanPtr = rwPtr + it.rangeStart * granularity;
        final spanSize = (it.rangeEnd - it.rangeStart) * granularity;

        _jitAllocatorFillPattern(spanPtr, impl.fillPattern, spanSize);
        VirtMem.flushInstructionCache(spanPtr.cast<Void>(), spanSize);
      }
    } finally {
      VirtMem.protectJitMemory(ProtectJitAccess.readExecute);
    }
  }

  block._clearBlock();
}

// =============================================================================
// JitAllocator - Write Scope
// =============================================================================

/// Write scope data (`JitAllocator::WriteScopeData`).
///
/// This is mostly for internal purposes, please use [JitAllocatorWriteScope]
/// instead.
final class JitAllocatorWriteScopeData {
  /// Cache policy passed to [JitAllocator.beginWriteScope].
  CachePolicy policy = CachePolicy.defaultPolicy;

  /// Internal flags used by the implementation.
  int flags = 0;

  /// Internal data that can be used by the implementation.
  final List<int> data = [0, 0];
}

/// Write scope can be used to create a single scope that is optimized for
/// writing multiple spans (`JitAllocator::WriteScope`).
///
/// Dart has no destructors: call [end] when done (the upstream destructor).
final class JitAllocatorWriteScope {
  final JitAllocator _allocator;
  final JitAllocatorWriteScopeData _scopeData = JitAllocatorWriteScopeData();

  /// Begins a write scope.
  JitAllocatorWriteScope(this._allocator,
      [CachePolicy policy = CachePolicy.defaultPolicy]) {
    _allocator.beginWriteScope(_scopeData, policy);
  }

  /// Ends a write scope.
  void end() => _allocator.endWriteScope(_scopeData);

  /// Returns [JitAllocator] associated with this write scope.
  JitAllocator get allocator => _allocator;

  /// Returns cache policy this write scope is using.
  CachePolicy get policy => _scopeData.policy;

  /// Similar to [JitAllocator.write], but under a write scope.
  AsmJitError write(JitAllocatorSpan span, int offset, Uint8List src,
          [int? size]) =>
      _allocator.scopedWrite(_scopeData, span, offset, src, size);

  /// Similar to [JitAllocator.writeWith], but under a write scope.
  AsmJitError writeWith(
          JitAllocatorSpan span, AsmJitError Function(JitAllocatorSpan) fn) =>
      _allocator.scopedWriteWith(_scopeData, span, fn);

  /// Flushes accumulated changes in this write scope.
  AsmJitError flush() => _allocator.flushWriteScope(_scopeData);
}

// =============================================================================
// JitAllocator
// =============================================================================

/// A simple implementation of memory manager that uses [VirtMem] functions
/// to manage virtual memory for JIT compiled code (`JitAllocator`).
class JitAllocator {
  /// Allocator implementation (private), null after [dispose]
  /// (upstream `JitAllocatorImpl_none`).
  _JitAllocatorPrivateImpl? _impl;

  /// Creates a `JitAllocator` instance.
  JitAllocator([JitAllocatorCreateParams? params])
      : _impl = _jitAllocatorNewImpl(params);

  /// Destroys the `JitAllocator` instance and release all blocks held (the
  /// upstream destructor). The allocator is not initialized afterwards.
  void dispose() {
    if (_impl == null) return;
    reset(ResetPolicy.hard);
    _impl = null;
  }

  /// Tests whether the JitAllocator has been initialized.
  ///
  /// Deviation from upstream: upstream returns `_impl->block_size == 0`,
  /// which is true only for a *not* initialized allocator. Proof (upstream
  /// release build, tool/upstream_repro/jitallocator_misc.cpp): a default
  /// constructed allocator that successfully allocates and reports
  /// `block_size() == 65536` returns `is_initialized() == false`.
  bool get isInitialized => (_impl?.blockSize ?? 0) != 0;

  /// Free all allocated memory - makes all pointers returned by [alloc]
  /// invalid.
  ///
  /// This function is designed to be used when nobody else is using the
  /// JitAllocator.
  void reset([ResetPolicy resetPolicy = ResetPolicy.soft]) {
    final impl = _impl;
    if (impl == null) return;

    impl.tree.reset();

    for (final pool in impl.pools) {
      var block = pool.blocks.first;

      pool.reset();

      if (block != null) {
        JitAllocatorBlock? blockToKeep;
        if (resetPolicy != ResetPolicy.hard &&
            (impl.options & JitAllocatorOptions.kImmediateRelease) == 0) {
          blockToKeep = block;
          block = block.next;
        }

        while (block != null) {
          final next = block.next;
          _jitAllocatorImplDeleteBlock(impl, block);
          block = next;
        }

        if (blockToKeep != null) {
          blockToKeep.listNodes[0] = null;
          blockToKeep.listNodes[1] = null;
          // Deviation from upstream: upstream clears only the list links of
          // the kept block, its RB-tree links still reference the blocks
          // deleted above while it becomes the root of the reset tree. Proof
          // (tool/upstream_repro/jitallocator_reset_soft.cpp): when the kept
          // block is an inner node, an upstream debug build asserts
          // `!node->has_left()` in `ArenaTree::insert()` and an ASan release
          // build reports heap-use-after-free in `ArenaTree::get()` from
          // `JitAllocator::query()`; clearing the tree links fixes both.
          blockToKeep.resetTreeNode();
          _jitAllocatorImplWipeOutBlock(impl, blockToKeep);
          _jitAllocatorImplInsertBlock(impl, blockToKeep);
          pool.emptyBlockCount = 1;
        }
      }
    }
  }

  /// Returns allocator options, see [JitAllocatorOptions].
  int get options => _impl?.options ?? 0;

  /// Tests whether the allocator has the given `option` set.
  bool hasOption(int option) => (options & option) != 0;

  /// Returns a base block size (a minimum size of block that the allocator
  /// would allocate).
  int get blockSize => _impl?.blockSize ?? 0;

  /// Returns granularity of the allocator.
  int get granularity => _impl?.granularity ?? 0;

  /// Returns pattern that is used to fill unused memory if
  /// [JitAllocatorOptions.kFillUnusedMemory] is set.
  int get fillPattern => _impl?.fillPattern ?? 0;

  /// Returns JIT allocator statistics.
  JitAllocatorStatistics statistics() {
    final statistics = JitAllocatorStatistics();
    statistics.reset();

    final impl = _impl;
    if (impl != null) {
      for (final pool in impl.pools) {
        statistics._blockCount += pool.blockCount;
        statistics._reservedSize +=
            (pool.totalAreaSize[0] + pool.totalAreaSize[1]) * pool.granularity;
        statistics._usedSize +=
            (pool.totalAreaUsed[0] + pool.totalAreaUsed[1]) * pool.granularity;
        statistics._overheadSize += pool.totalOverheadBytes;
      }

      statistics._allocationCount = impl.allocationCount;
    }

    return statistics;
  }

  // ===========================================================================
  // Alloc & Release
  // ===========================================================================

  /// Allocates a new memory span of the requested `size` and stores it to
  /// `out`.
  AsmJitError alloc(JitAllocatorSpan out, int size) {
    const noIndex = 0xFFFFFFFF;
    const maxRequestSize = 0xFFFFFFFF ~/ 2;

    final impl = _impl;
    out._reset();

    if (impl == null) return AsmJitError.notInitialized;
    // `size_t` is unsigned: a negative size is a huge request.
    if (size < 0) return AsmJitError.tooLarge;

    // Align to the minimum granularity by default.
    size = _alignUp(size, impl.granularity);

    if (size == 0 || size - 1 >= maxRequestSize) {
      return size == 0 ? AsmJitError.invalidArgument : AsmJitError.tooLarge;
    }

    final pool = impl.pools[_jitAllocatorSizeToPoolId(impl, size)];

    var areaIndex = noIndex;
    final areaSize = pool.areaSizeFromByteSize(size);

    // Try to find the requested memory area in existing blocks.
    var block = pool.cursor;

    if (block != null) {
      final initial = block;

      do {
        final largestUnusedArea = block!._largestUnusedArea;

        if (block._isIncremental && largestUnusedArea >= areaSize) {
          // Fast path: If the block is in incremental mode, which means that
          // it's guaranteed it's full before `searchStart` and completely
          // empty after it, we can just quickly increment `searchStart` and
          // be done with the allocation. This is a little bit faster than
          // constructing a BitVectorRangeIterator and searching for zero bit
          // clusters. When a block is in incremental mode its
          // `largestUnusedArea` is basically the free space after
          // `searchStart`, so that's the only thing to check.
          areaIndex = block._searchStart;
          block._largestUnusedArea -= areaSize;
          break;
        } else if (block._areaAvailable >= areaSize) {
          // Regular path: Search for a cluster of bits that would mark an
          // empty area we want to allocate.
          if (block._isDirty || largestUnusedArea >= areaSize) {
            final it = BitVectorRangeIterator(
              block._usedBitVector,
              pool.bitWordCountFromAreaSize(block._areaSize),
              bit: 0,
              type: _kBitWord,
              start: block._searchStart,
              end: block._searchEnd,
            );

            var rangeStart = 0;
            var rangeEnd = block._areaSize;

            var searchStart = -1; // SIZE_MAX
            var largestArea = 0;

            while (it.nextRange(areaSize)) {
              rangeStart = it.rangeStart;
              rangeEnd = it.rangeEnd;

              final rangeSize = rangeEnd - rangeStart;
              if (rangeSize >= areaSize) {
                areaIndex = rangeStart;
                break;
              }

              searchStart = searchStart == -1
                  ? rangeStart
                  : _min(searchStart, rangeStart);
              largestArea = _max(largestArea, rangeSize);
            }

            if (areaIndex != noIndex) break;

            if (searchStart != -1) {
              // Because we have iterated over the entire block, we can now
              // mark the largest unused area that can be used to cache the
              // next traversal.
              final searchEnd = rangeEnd;

              block._searchStart = searchStart;
              block._searchEnd = searchEnd;
              block._largestUnusedArea = largestArea;
              block._clearFlags(JitAllocatorBlock.kFlagDirty);
            }
          }
        }

        // The block cursor doesn't have to start with the first block and we
        // want to iterate all before concluding that there is no free space
        // in any block.
        block = block.hasNext ? block.next : pool.blocks.first;
      } while (!identical(block, initial));
    }

    // Allocate a new block if there is no region of a required size.
    if (areaIndex == noIndex) {
      final blockSize = _jitAllocatorCalculateIdealBlockSize(impl, pool, size);
      if (blockSize == 0) return AsmJitError.outOfMemory;

      final (err, newBlock) = _jitAllocatorNewBlock(impl, pool, blockSize);
      if (err != AsmJitError.ok) return err;
      block = newBlock!;
      areaIndex = block._initialAreaStart;

      _jitAllocatorImplInsertBlock(impl, block);
      block._searchStart += areaSize;
      block._largestUnusedArea -= areaSize;
    } else if (block!._hasFlag(JitAllocatorBlock.kFlagEmpty)) {
      pool.emptyBlockCount--;
      block._clearFlags(JitAllocatorBlock.kFlagEmpty);
    }

    // Update statistics.
    impl.allocationCount++;
    block._markAllocatedArea(areaIndex, areaIndex + areaSize);

    // Return a span referencing the allocated memory.
    final offset = pool.byteSizeFromAreaSize(areaIndex);
    assert(offset <= block.blockSize - size);

    out._rx = Pointer<Void>.fromAddress(block.rxAddress + offset);
    out._rw = Pointer<Void>.fromAddress(block.rwAddress + offset);
    out._size = size;
    out._block = block;

    return AsmJitError.ok;
  }

  /// Releases a memory block returned by [alloc].
  AsmJitError release(Pointer<Void> rx) {
    final impl = _impl;
    if (impl == null || rx == nullptr) {
      return impl == null
          ? AsmJitError.notInitialized
          : AsmJitError.invalidArgument;
    }

    final block = impl.tree.get(rx.address, JitAllocatorBlock._compareKey);
    if (block == null) return AsmJitError.invalidState;

    // Offset relative to the start of the block.
    final pool = block._pool;
    final offset = rx.address - block.rxAddress;

    // The first bit representing the allocated area and its size.
    final areaIndex = offset >>> pool.granularityLog2;
    final areaEnd =
        bitVectorIndexOf(block._stopBitVector, areaIndex, true, _kBitWord) + 1;
    final areaSize = areaEnd - areaIndex;

    impl.allocationCount--;
    block._markReleasedArea(areaIndex, areaEnd);

    // Fill the released memory if the secure mode is enabled.
    if ((impl.options & JitAllocatorOptions.kFillUnusedMemory) != 0) {
      final spanPtr = block._rwPtr + areaIndex * pool.granularity;
      final spanSize = areaSize * pool.granularity;

      final scope = ProtectJitReadWriteScope(spanPtr.cast<Void>(), spanSize);
      try {
        _jitAllocatorFillPattern(spanPtr, impl.fillPattern, spanSize);
      } finally {
        scope.close();
      }
    }

    // Release the whole block if it became empty.
    if (block._isEmpty) {
      if (pool.emptyBlockCount != 0 ||
          (impl.options & JitAllocatorOptions.kImmediateRelease) != 0) {
        _jitAllocatorImplRemoveBlock(impl, block);
        _jitAllocatorImplDeleteBlock(impl, block);
      } else {
        pool.emptyBlockCount++;
      }
    }

    return AsmJitError.ok;
  }

  AsmJitError _shrinkImpl(
      JitAllocatorSpan span, int newSize, bool alreadyUnderWriteScope) {
    final impl = _impl!;
    final block = span._block;
    if (block == null) return AsmJitError.invalidArgument;

    // Offset relative to the start of the block.
    final pool = block._pool;
    final offset = span.rx.address - block.rxAddress;

    // The first bit representing the allocated area and its size.
    final areaStart = offset >>> pool.granularityLog2;

    // Don't trust `span.size` - if it has been already truncated we would be
    // off...
    final isUsed = bitVectorGetBit(block._usedBitVector, areaStart, _kBitWord);
    if (!isUsed) return AsmJitError.invalidArgument;

    final areaEnd =
        bitVectorIndexOf(block._stopBitVector, areaStart, true, _kBitWord) + 1;
    final areaPrevSize = areaEnd - areaStart;
    final spanPrevSize = areaPrevSize * pool.granularity;
    final areaShrunkSize = pool.areaSizeFromByteSize(newSize);

    if (areaShrunkSize > areaPrevSize) return AsmJitError.invalidArgument;

    final areaDiff = areaPrevSize - areaShrunkSize;
    if (areaDiff != 0) {
      block._markShrunkArea(areaStart + areaShrunkSize, areaEnd);
      span._size = pool.byteSizeFromAreaSize(areaShrunkSize);
    }

    // Fill released memory if the secure mode is enabled.
    if (newSize < spanPrevSize &&
        (impl.options & JitAllocatorOptions.kFillUnusedMemory) != 0) {
      final spanPtr =
          block._rwPtr + (areaStart + areaShrunkSize) * pool.granularity;
      final spanSize = areaDiff * pool.granularity;

      if (!alreadyUnderWriteScope) {
        final scope = ProtectJitReadWriteScope(
            spanPtr.cast<Void>(), spanSize, CachePolicy.neverFlush);
        try {
          _jitAllocatorFillPattern(spanPtr, impl.fillPattern, spanSize);
        } finally {
          scope.close();
        }
      } else {
        _jitAllocatorFillPattern(spanPtr, impl.fillPattern, spanSize);
      }
    }

    return AsmJitError.ok;
  }

  /// Frees extra memory allocated with `span` by shrinking it to the given
  /// `newSize`.
  AsmJitError shrink(JitAllocatorSpan span, int newSize) {
    final impl = _impl;
    if (impl == null || span.rx == nullptr) {
      return impl == null
          ? AsmJitError.notInitialized
          : AsmJitError.invalidArgument;
    }

    if (newSize == 0) {
      final err = release(span.rx);
      span._reset();
      return err;
    }

    return _shrinkImpl(span, newSize, false);
  }

  /// Queries information about an allocated memory block that contains the
  /// given `rx`, and writes it to `out`.
  ///
  /// If the pointer is matched, the function returns [AsmJitError.ok] and
  /// fills `out` with the corresponding span.
  AsmJitError query(JitAllocatorSpan out, Pointer<Void> rx) {
    out._reset();

    final impl = _impl;
    if (impl == null) return AsmJitError.notInitialized;

    final block = impl.tree.get(rx.address, JitAllocatorBlock._compareKey);
    if (block == null) return AsmJitError.invalidArgument;

    // Offset relative to the start of the block.
    final pool = block._pool;
    final offset = rx.address - block.rxAddress;

    // The first bit representing the allocated area and its size.
    final areaStart = offset >>> pool.granularityLog2;

    final isUsed = bitVectorGetBit(block._usedBitVector, areaStart, _kBitWord);
    if (!isUsed) return AsmJitError.invalidArgument;

    final areaEnd =
        bitVectorIndexOf(block._stopBitVector, areaStart, true, _kBitWord) + 1;
    final byteOffset = pool.byteSizeFromAreaSize(areaStart);
    final byteSize = pool.byteSizeFromAreaSize(areaEnd - areaStart);

    out._rx = Pointer<Void>.fromAddress(block.rxAddress + byteOffset);
    out._rw = Pointer<Void>.fromAddress(block.rwAddress + byteOffset);
    out._size = byteSize;
    out._block = block;

    return AsmJitError.ok;
  }

  // ===========================================================================
  // Write Operations
  // ===========================================================================

  static CachePolicy _defaultPolicyForSpan(JitAllocatorSpan span) {
    if ((span.flags & JitAllocatorSpanFlags.kInstructionCacheClean) != 0) {
      return CachePolicy.neverFlush;
    }
    return CachePolicy.flushAfterWrite;
  }

  /// Makes the memory pointed out by `span` writable and writes data to it at
  /// the given `offset`.
  ///
  /// This function reads `src` and writes to `span` at `offset` the number of
  /// bytes specified by `size` (the whole `src` by default).
  ///
  /// Use `policy` argument to specify an instruction cache flush behavior.
  AsmJitError write(JitAllocatorSpan span, int offset, Uint8List src,
      [int? size, CachePolicy policy = CachePolicy.defaultPolicy]) {
    size ??= src.length;
    if (span._block == null ||
        offset < 0 ||
        size < 0 ||
        size > src.length ||
        offset > span.size ||
        span.size - offset < size) {
      return AsmJitError.invalidArgument;
    }

    if (size == 0) return AsmJitError.ok;

    if (policy == CachePolicy.defaultPolicy) {
      policy = _defaultPolicyForSpan(span);
    }

    final writeScope = ProtectJitReadWriteScope(span.rx, span.size, policy);
    try {
      (span.rw.cast<Uint8>() + offset).asTypedList(size).setRange(0, size, src);
    } finally {
      writeScope.close();
    }
    return AsmJitError.ok;
  }

  /// Makes the memory pointed out by `span` writable and calls the provided
  /// callback `writeFn` to perform the write operation (the upstream
  /// `write(span, write_fn, user_data)` and `write(span, lambda)`).
  ///
  /// The callback must write through [JitAllocatorSpan.rw] and must be
  /// synchronous. If it calls [JitAllocatorSpan.shrink], the memory used by
  /// the span is shrunk accordingly.
  ///
  /// Use `policy` argument to specify an instruction cache flush behavior.
  AsmJitError writeWith(
      JitAllocatorSpan span, AsmJitError Function(JitAllocatorSpan) writeFn,
      [CachePolicy policy = CachePolicy.defaultPolicy]) {
    if (span._block == null || span.size == 0) {
      return AsmJitError.invalidArgument;
    }

    var size = span.size;
    if (size == 0) return AsmJitError.ok;

    if (policy == CachePolicy.defaultPolicy) {
      policy = _defaultPolicyForSpan(span);
    }

    final writeScope = ProtectJitReadWriteScope(span.rx, span.size, policy);
    try {
      final err = writeFn(span);
      if (err != AsmJitError.ok) return err;

      // Check whether span.truncate() has been called.
      if (span.size != size) {
        // OK, this is a bit awkward... However, shrink wants the original
        // span and newSize, so we have to swap.
        final newSize = span._size;
        span._size = size;
        size = newSize;
        return _shrinkImpl(span, size, true);
      }

      return AsmJitError.ok;
    } finally {
      writeScope.close();
    }
  }

  // ===========================================================================
  // Write Operations with Scope
  // ===========================================================================

  /// Begins a write `scope`.
  ///
  /// This is mostly for internal purposes, please use [JitAllocatorWriteScope]
  /// constructor instead.
  AsmJitError beginWriteScope(JitAllocatorWriteScopeData scope,
      [CachePolicy policy = CachePolicy.defaultPolicy]) {
    scope.policy = policy;
    scope.flags = 0;
    scope.data[0] = 0;
    scope.data[1] = 0;
    return AsmJitError.ok;
  }

  /// Ends a write `scope`.
  ///
  /// This is mostly for internal purposes, please use
  /// [JitAllocatorWriteScope.end] instead.
  AsmJitError endWriteScope(JitAllocatorWriteScopeData scope) => AsmJitError.ok;

  /// Flushes accumulated changes in a write `scope`.
  ///
  /// This is mostly for internal purposes, please use
  /// [JitAllocatorWriteScope.flush] instead.
  AsmJitError flushWriteScope(JitAllocatorWriteScopeData scope) =>
      AsmJitError.ok;

  /// Alternative to [write], but under a write `scope`.
  ///
  /// This is mostly for internal purposes, please use
  /// [JitAllocatorWriteScope.write] instead.
  AsmJitError scopedWrite(JitAllocatorWriteScopeData scope,
          JitAllocatorSpan span, int offset, Uint8List src,
          [int? size]) =>
      write(span, offset, src, size, scope.policy);

  /// Alternative to [writeWith], but under a write `scope`.
  ///
  /// This is mostly for internal purposes, please use
  /// [JitAllocatorWriteScope.writeWith] instead.
  AsmJitError scopedWriteWith(JitAllocatorWriteScopeData scope,
          JitAllocatorSpan span, AsmJitError Function(JitAllocatorSpan) fn) =>
      writeWith(span, fn, scope.policy);
}
