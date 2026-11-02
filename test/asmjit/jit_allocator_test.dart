// Tests of the JitAllocator / VirtMem port.
//
// The "JitAllocator - upstream" group ports the `#if defined(ASMJIT_TEST)`
// section of asmjit/core/jitallocator.cpp (`UNIT(jit_allocator)`): the
// BitVectorRangeIterator random test, `test_jit_allocator_reset_empty()`,
// `test_jit_allocator_alloc_release()` (random alloc/release/shrink stress
// through `JitAllocatorWrapper`, which keeps every allocation in an RB-tree of
// records to detect overlaps and verifies a per-allocation pattern through
// both the RX and the RW pointers) and `test_jit_allocator_query()`.
//
// In addition the statistics after every phase of the stress test are
// compared with the numbers printed by the upstream library running the same
// sequence (tool/upstream_repro/jitallocator_stats.cpp, `./stats 20000`).
import 'dart:ffi';
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/runtime/jit_allocator.dart'
    show BitVectorRangeIterator;
import 'package:asmjit/src/asmjit/support/arena_tree.dart';
import 'package:asmjit/src/asmjit/support/bit_vector_ops.dart';
import 'package:test/test.dart';

import '../support/host.dart';

/// Number of allocations of the stress test (upstream `--quick`).
const int kCount = 20000;

// =============================================================================
// TestUtils::Random (asmjit-testing/commons/random.h)
// =============================================================================

/// A pseudo random number generator based on a paper by Sebastiano Vigna
/// (xorshift128+), as `TestUtils::Random`.
final class TestRandom {
  static const int kStep1Shl = 23;
  static const int kStep2Shr = 18;
  static const int kStep3Shr = 5;

  final List<int> _state = [0, 0];

  TestRandom([int seed = 0]) {
    reset(seed);
  }

  void reset([int seed = 0]) {
    // The number is arbitrary, it means nothing.
    const kZeroSeed = 0x1F0A2BE71D163FA0;

    // Generate the state data by using splitmix64.
    for (var i = 0; i < 2; i++) {
      seed += 0x9E3779B97F4A7C15;
      var x = seed;
      x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9;
      x = (x ^ (x >>> 27)) * 0x94D049BB133111EB;
      x = x ^ (x >>> 31);
      _state[i] = x != 0 ? x : kZeroSeed;
    }
  }

  int nextUint32() => nextUint64() >>> 32;

  int nextUint64() {
    var x = _state[0];
    var y = _state[1];

    x ^= x << kStep1Shl;
    y ^= y >>> kStep3Shr;
    x ^= x >>> kStep2Shr;
    x ^= y;

    _state[0] = y;
    _state[1] = x;
    return x + y;
  }
}

// =============================================================================
// JitAllocatorUtils / JitAllocatorWrapper
// =============================================================================

void _fillPattern64(Pointer<Void> p, int pattern, int sizeInBytes) {
  final n = sizeInBytes ~/ 8;
  if (n != 0) p.cast<Uint64>().asTypedList(n).fillRange(0, n, pattern);
}

bool _verifyPattern64(Pointer<Void> p, int pattern, int sizeInBytes) {
  final n = sizeInBytes ~/ 8;
  if (n == 0) return true;
  final words = p.cast<Uint64>().asTypedList(n);
  for (var i = 0; i < n; i++) {
    if (words[i] != pattern) return false;
  }
  return true;
}

/// Address to a memory region of a given size (`Record`), kept in an RB-tree
/// to verify that JitAllocator doesn't return addresses that overlap.
final class _Record extends ArenaTreeNode {
  final int addr;
  int size;

  /// Read/write address, in case this is a dual mapping.
  final int rw;

  /// Describes a pattern used to fill the allocated memory.
  final int pattern;

  _Record(this.addr, this.rw, this.size, this.pattern);

  Pointer<Void> get rxPtr => Pointer<Void>.fromAddress(addr);
  Pointer<Void> get rwPtr => Pointer<Void>.fromAddress(rw);

  static int compare(_Record a, _Record b) =>
      a.addr < b.addr ? -1 : (a.addr > b.addr ? 1 : 0);

  static int compareKey(_Record node, int key) =>
      (node.addr > key ? 1 : 0) - (node.addr + node.size <= key ? 1 : 0);
}

/// Helper class to verify that JitAllocator doesn't return addresses that
/// overlap (`JitAllocatorWrapper`).
final class _JitAllocatorWrapper {
  final ArenaTree<_Record> _records = ArenaTree<_Record>(_Record.compare);
  final JitAllocator allocator;
  final TestRandom _rng = TestRandom(0x123456789);

  _JitAllocatorWrapper(JitAllocatorCreateParams params)
      : allocator = JitAllocator(params);

  void _insert(Pointer<Void> rxPtr, Pointer<Void> rwPtr, int size) {
    final ptr = rxPtr.address;
    final endPtr = ptr + size - 1;

    var record = _records.get(ptr, _Record.compareKey);
    if (record != null) {
      fail('Address [${record.addr}:${record.addr + record.size}] collides '
          'with a newly allocated [$ptr:${ptr + size}]');
    }

    record = _records.get(endPtr, _Record.compareKey);
    if (record != null) {
      fail('Address [${record.addr}:${record.addr + record.size}] collides '
          'with a newly allocated [$ptr:${ptr + size}]');
    }

    final pattern = _rng.nextUint64();
    record = _Record(ptr, rwPtr.address, size, pattern);

    final scope = ProtectJitReadWriteScope(rwPtr, size);
    try {
      _fillPattern64(rwPtr, pattern, size);
    } finally {
      scope.close();
    }

    VirtMem.flushInstructionCache(rxPtr, size);
    if (!_verifyPattern64(rxPtr, pattern, size)) {
      fail('Pattern verification failed at $ptr (rx) after insert');
    }

    _records.insert(record);
  }

  void _remove(Pointer<Void> p) {
    final record = _records.get(p.address, _Record.compareKey);
    if (record == null) fail('No record for ${p.address}');

    if (!_verifyPattern64(record.rxPtr, record.pattern, record.size)) {
      fail('Pattern verification failed at ${record.addr} (rx)');
    }
    if (!_verifyPattern64(record.rwPtr, record.pattern, record.size)) {
      fail('Pattern verification failed at ${record.rw} (rw)');
    }

    _records.remove(record);
  }

  Pointer<Void> alloc(int size) {
    final span = JitAllocatorSpan();
    final err = allocator.alloc(span, size);
    if (err != AsmJitError.ok) {
      fail('JitAllocator failed to allocate $size bytes: $err');
    }

    _insert(span.rx, span.rw, size);
    return span.rx;
  }

  void release(Pointer<Void> p) {
    _remove(p);
    final err = allocator.release(p);
    if (err != AsmJitError.ok) {
      fail("JitAllocator failed to release '${p.address}': $err");
    }
  }

  void shrink(Pointer<Void> p, int newSize) {
    final record = _records.get(p.address, _Record.compareKey);
    if (record == null) fail('No record for ${p.address}');

    if (newSize == 0) return release(p);

    final span = JitAllocatorSpan();
    expect(allocator.query(span, p), AsmJitError.ok);
    final err = allocator.shrink(span, newSize);
    if (err != AsmJitError.ok) {
      fail('JitAllocator failed to shrink ${p.address} to $newSize bytes');
    }

    record.size = newSize;
  }
}

void _shuffle(List<Pointer<Void>> ptrArray, int count, TestRandom prng) {
  for (var i = 0; i < count; ++i) {
    final j = prng.nextUint32() % count;
    final tmp = ptrArray[i];
    ptrArray[i] = ptrArray[j];
    ptrArray[j] = tmp;
  }
}

// =============================================================================
// Upstream statistics (tool/upstream_repro/jitallocator_stats.cpp, 20000)
// =============================================================================

/// `[blockCount, allocationCount, usedSize, reservedSize, overheadSize]`
/// after each phase of `test_jit_allocator_alloc_release()`, printed by the
/// upstream library (macOS arm64, page granularity 64kB, 64-bit BitWord).
const Map<String, List<List<int>>> upstreamStats = {
  'Default': [
    [7, 20000, 10994240, 16646144, 65752], // alloc random
    [1, 0, 64, 131072, 616], // release from begin
    [7, 20000, 10957504, 16646144, 65752], // alloc random again
    [7, 10000, 5449024, 16646144, 65752], // release 50%
    [7, 20000, 10966272, 16646144, 65752], // alloc 50% again
    [1, 0, 64, 8388608, 32872], // release from end
    [1, 10000, 2560064, 8388608, 32872], // alloc fixed
    [1, 10000, 640064, 8388608, 32872], // shrink to 1
    [1, 20000, 1280064, 8388608, 32872], // alloc 64B
    [1, 0, 64, 8388608, 32872], // release all from begin
    [1, 20000, 5120064, 8388608, 32872], // alloc fixed all
    [1, 10000, 2560064, 8388608, 32872], // release 50% fixed
    [1, 20000, 5120064, 8388608, 32872], // alloc 50% fixed again
    [1, 0, 64, 8388608, 32872], // release all from end
  ],
  '16MB blocks': [
    [1, 20000, 10993856, 33554432, 131176], // alloc random
    [1, 0, 64, 33554432, 131176], // release from begin
    [1, 20000, 10957120, 33554432, 131176], // alloc random again
    [1, 10000, 5448640, 33554432, 131176], // release 50%
    [1, 20000, 10965888, 33554432, 131176], // alloc 50% again
    [1, 0, 64, 33554432, 131176], // release from end
    [1, 10000, 2560064, 33554432, 131176], // alloc fixed
    [1, 10000, 640064, 33554432, 131176], // shrink to 1
    [1, 20000, 1280064, 33554432, 131176], // alloc 64B
    [1, 0, 64, 33554432, 131176], // release all from begin
    [1, 20000, 5120064, 33554432, 131176], // alloc fixed all
    [1, 10000, 2560064, 33554432, 131176], // release 50% fixed
    [1, 20000, 5120064, 33554432, 131176], // alloc 50% fixed again
    [1, 0, 64, 33554432, 131176], // release all from end
  ],
  '256B granularity': [
    [7, 20000, 12931328, 16646144, 16984], // alloc random
    [1, 0, 256, 131072, 232], // release from begin
    [7, 20000, 12898048, 16646144, 16984], // alloc random again
    [7, 10000, 6411776, 16646144, 16984], // release 50%
    [7, 20000, 12885504, 16646144, 16984], // alloc 50% again
    [1, 0, 256, 8388608, 8296], // release from end
    [1, 10000, 2560256, 8388608, 8296], // alloc fixed
    [1, 10000, 2560256, 8388608, 8296], // shrink to 1
    [1, 20000, 5120256, 8388608, 8296], // alloc 64B
    [1, 0, 256, 8388608, 8296], // release all from begin
    [1, 20000, 5120256, 8388608, 8296], // alloc fixed all
    [1, 10000, 2560256, 8388608, 8296], // release 50% fixed
    [1, 20000, 5120256, 8388608, 8296], // alloc 50% fixed again
    [1, 0, 256, 8388608, 8296], // release all from end
  ],
  'kUseMultiplePools': [
    [16, 20000, 10996096, 16384000, 45824], // alloc random
    [3, 0, 448, 393216, 1208], // release from begin
    [16, 20000, 10959360, 16384000, 45824], // alloc random again
    [16, 10000, 5450880, 16384000, 45824], // release 50%
    [16, 20000, 10968128, 16384000, 45824], // alloc 50% again
    [3, 0, 448, 8388608, 22840], // release from end
    [4, 10000, 2560704, 12582912, 27040], // alloc fixed
    [4, 10000, 2560704, 12582912, 27040], // shrink to 1
    [4, 20000, 3200704, 12582912, 27040], // alloc 64B
    [3, 0, 448, 8388608, 22840], // release all from begin
    [4, 20000, 5120704, 12582912, 27040], // alloc fixed all
    [4, 10000, 2560704, 12582912, 27040], // release 50% fixed
    [4, 20000, 5120704, 12582912, 27040], // alloc 50% fixed again
    [3, 0, 448, 10485760, 24888], // release all from end
  ],
  'kFillUnusedMemory': [
    [7, 20000, 10994240, 16646144, 65752], // alloc random
    [1, 0, 64, 131072, 616], // release from begin
    [7, 20000, 10957504, 16646144, 65752], // alloc random again
    [7, 10000, 5449024, 16646144, 65752], // release 50%
    [7, 20000, 10966272, 16646144, 65752], // alloc 50% again
    [1, 0, 64, 8388608, 32872], // release from end
    [1, 10000, 2560064, 8388608, 32872], // alloc fixed
    [1, 10000, 640064, 8388608, 32872], // shrink to 1
    [1, 20000, 1280064, 8388608, 32872], // alloc 64B
    [1, 0, 64, 8388608, 32872], // release all from begin
    [1, 20000, 5120064, 8388608, 32872], // alloc fixed all
    [1, 10000, 2560064, 8388608, 32872], // release 50% fixed
    [1, 20000, 5120064, 8388608, 32872], // alloc 50% fixed again
    [1, 0, 64, 8388608, 32872], // release all from end
  ],
  'kImmediateRelease': [
    [7, 20000, 10994240, 16646144, 65752], // alloc random
    [0, 0, 0, 0, 0], // release from begin
    [7, 20000, 10957504, 16646144, 65752], // alloc random again
    [7, 10000, 5449024, 16646144, 65752], // release 50%
    [7, 20000, 10966272, 16646144, 65752], // alloc 50% again
    [0, 0, 0, 0, 0], // release from end
    [5, 10000, 2560320, 4063232, 16392], // alloc fixed
    [5, 10000, 640320, 4063232, 16392], // shrink to 1
    [5, 20000, 1280320, 4063232, 16392], // alloc 64B
    [0, 0, 0, 0, 0], // release all from begin
    [6, 20000, 5120384, 8257536, 32880], // alloc fixed all
    [6, 10000, 2560384, 8257536, 32880], // release 50% fixed
    [6, 20000, 5120384, 8257536, 32880], // alloc 50% fixed again
    [0, 0, 0, 0, 0], // release all from end
  ],
  'kDisableInitialPadding': [
    [7, 20000, 10993792, 16646144, 65752], // alloc random
    [1, 0, 0, 131072, 616], // release from begin
    [7, 20000, 10957056, 16646144, 65752], // alloc random again
    [7, 10000, 5448576, 16646144, 65752], // release 50%
    [7, 20000, 10965824, 16646144, 65752], // alloc 50% again
    [1, 0, 0, 8388608, 32872], // release from end
    [1, 10000, 2560000, 8388608, 32872], // alloc fixed
    [1, 10000, 640000, 8388608, 32872], // shrink to 1
    [1, 20000, 1280000, 8388608, 32872], // alloc 64B
    [1, 0, 0, 8388608, 32872], // release all from begin
    [1, 20000, 5120000, 8388608, 32872], // alloc fixed all
    [1, 10000, 2560000, 8388608, 32872], // release 50% fixed
    [1, 20000, 5120000, 8388608, 32872], // alloc 50% fixed again
    [1, 0, 0, 8388608, 32872], // release all from end
  ],
};

/// Upstream numbers for the configurations that upstream could not run on
/// the reference host: large pages (not available on macOS arm64, so the
/// numbers are those of the regular page configurations, which is what a
/// failed large page allocation falls back to) and dual mapping (not
/// supported on Apple Silicon; dual mapping only changes how a block is
/// mapped, not the block sizes nor the bit-vector algorithm).
const Map<String, String> upstreamStatsAlias = {
  'kUseLargePages': 'Default',
  'kUseLargePages | kFillUnusedMemory': 'kFillUnusedMemory',
  'kUseLargePages | kAlignBlockSizeToLargePage': 'Default',
  'kUseDualMapping': 'Default',
  'kUseDualMapping | kFillUnusedMemory': 'kFillUnusedMemory',
};

List<int> _statsRow(JitAllocator allocator) {
  final s = allocator.statistics();
  return [
    s.blockCount,
    s.allocationCount,
    s.usedSize,
    s.reservedSize,
    s.overheadSize,
  ];
}

/// Whether large pages can actually be mapped by this process.
bool _largePagesWork() {
  final lpSize = VirtMem.largePageSize();
  if (lpSize == 0) return false;
  final (err, p) = VirtMem.alloc(
      lpSize, MemoryFlags.kAccessRWX | MemoryFlags.kMMapLargePages);
  if (err != AsmJitError.ok) return false;
  VirtMem.release(p, lpSize);
  return true;
}

// =============================================================================
// BitVectorRangeIterator_testRandom
// =============================================================================

void _bitVectorRangeIteratorTestRandom(
    TestRandom rnd, int count, BitWordType type) {
  const kPatternSize = 64;
  const bit = 0;

  final List<int> input =
      type.bitSize == 64 ? Uint64List(kPatternSize) : Uint32List(kPatternSize);
  final List<int> output =
      type.bitSize == 64 ? Uint64List(kPatternSize) : Uint32List(kPatternSize);

  for (var i = 0; i < count; i++) {
    for (var j = 0; j < kPatternSize; j++) {
      input[j] = ((rnd.nextUint32() & 0xFF) * 0x0101010101010101) & type.ones;
      output[j] = bit == 0 ? type.ones : 0;
    }

    final it =
        BitVectorRangeIterator(input, kPatternSize, bit: bit, type: type);
    while (it.nextRange()) {
      if (bit != 0) {
        bitVectorFill(output, it.rangeStart, it.rangeEnd - it.rangeStart, type);
      } else {
        bitVectorClear(
            output, it.rangeStart, it.rangeEnd - it.rangeStart, type);
      }
    }

    for (var j = 0; j < kPatternSize; j++) {
      if (input[j] != output[j]) {
        fail('Invalid pattern detected at [$j] '
            '(${input[j].toRadixString(16)} != ${output[j].toRadixString(16)})');
      }
    }
  }
}

// =============================================================================
// Tests
// =============================================================================

class _TestInfo {
  final String name;
  final int options;
  final int blockSize;
  final int granularity;

  const _TestInfo(this.name, this.options, this.blockSize, this.granularity);
}

const List<_TestInfo> _testInfoTable = [
  _TestInfo('Default', JitAllocatorOptions.kNone, 0, 0),
  _TestInfo('16MB blocks', JitAllocatorOptions.kNone, 16 * 1024 * 1024, 0),
  _TestInfo('256B granularity', JitAllocatorOptions.kNone, 0, 256),
  _TestInfo('kUseMultiplePools', JitAllocatorOptions.kUseMultiplePools, 0, 0),
  _TestInfo('kFillUnusedMemory', JitAllocatorOptions.kFillUnusedMemory, 0, 0),
  _TestInfo('kImmediateRelease', JitAllocatorOptions.kImmediateRelease, 0, 0),
  _TestInfo('kDisableInitialPadding',
      JitAllocatorOptions.kDisableInitialPadding, 0, 0),
  _TestInfo('kUseLargePages', JitAllocatorOptions.kUseLargePages, 0, 0),
  _TestInfo(
      'kUseLargePages | kFillUnusedMemory',
      JitAllocatorOptions.kUseLargePages |
          JitAllocatorOptions.kFillUnusedMemory,
      0,
      0),
  _TestInfo(
      'kUseLargePages | kAlignBlockSizeToLargePage',
      JitAllocatorOptions.kUseLargePages |
          JitAllocatorOptions.kAlignBlockSizeToLargePage,
      0,
      0),
  _TestInfo('kUseDualMapping', JitAllocatorOptions.kUseDualMapping, 0, 0),
  _TestInfo(
      'kUseDualMapping | kFillUnusedMemory',
      JitAllocatorOptions.kUseDualMapping |
          JitAllocatorOptions.kFillUnusedMemory,
      0,
      0),
];

/// x86 and x86-64 hosts fill unused memory with `int3` (0xCC).
final _hostIsX86Family =
    Environment.host().arch == Arch.x64 || Environment.host().arch == Arch.x86;

void main() {
  final hri = VirtMem.hardenedRuntimeInfo();
  final is64Bit = sizeOf<IntPtr>() == 8;

  group('JitAllocator - upstream', () {
    test('BitVectorRangeIterator<uint32_t>', () {
      _bitVectorRangeIteratorTestRandom(TestRandom(), kCount, BitWordType.u32);
    });

    test('BitVectorRangeIterator<uint64_t>', () {
      _bitVectorRangeIteratorTestRandom(TestRandom(), kCount, BitWordType.u64);
    });

    test('reset empty', () {
      final allocator = JitAllocator();
      allocator.reset(ResetPolicy.soft);
      allocator.dispose();
    });

    final largePagesWork = _largePagesWork();

    for (final testInfo in _testInfoTable) {
      // Don't try to allocate dual-mapping if dual mapping is not possible -
      // it would fail the test.
      final dualMappingUnsupported =
          (testInfo.options & JitAllocatorOptions.kUseDualMapping) != 0 &&
              !hri.hasFlag(HardenedRuntimeFlags.kDualMapping);

      test('alloc/release - JitAllocator(${testInfo.name})', () {
        final params = JitAllocatorCreateParams(
          options: testInfo.options,
          blockSize: testInfo.blockSize,
          granularity: testInfo.granularity,
        );

        const fixedBlockSize = 256;

        final wrapper = _JitAllocatorWrapper(params);
        final prng = TestRandom(100);

        final expected = upstreamStats[testInfo.name] ??
            upstreamStats[upstreamStatsAlias[testInfo.name]]!;
        final usesLargePages =
            (testInfo.options & JitAllocatorOptions.kUseLargePages) != 0;
        final compareStats = is64Bit && !(usesLargePages && largePagesWork);
        var phase = 0;

        void usage(String name) {
          final row = _statsRow(wrapper.allocator);
          if (compareStats) {
            expect(row, expected[phase],
                reason: '${testInfo.name}: statistics after "$name"');
          }
          phase++;
        }

        final ptrArray = List<Pointer<Void>>.filled(kCount, nullptr);
        int i;

        // Random blocks tests...
        for (i = 0; i < kCount; i++) {
          ptrArray[i] = wrapper.alloc((prng.nextUint32() % 1024) + 8);
        }
        usage('alloc random');

        for (i = 0; i < kCount; i++) {
          wrapper.release(ptrArray[i]);
        }
        usage('release from begin');

        for (i = 0; i < kCount; i++) {
          ptrArray[i] = wrapper.alloc((prng.nextUint32() % 1024) + 8);
        }
        usage('alloc random again');

        _shuffle(ptrArray, kCount, prng);

        for (i = 0; i < kCount ~/ 2; i++) {
          wrapper.release(ptrArray[i]);
        }
        usage('release 50%');

        for (i = 0; i < kCount ~/ 2; i++) {
          ptrArray[i] = wrapper.alloc((prng.nextUint32() % 1024) + 8);
        }
        usage('alloc 50% again');

        for (i = 0; i < kCount; i++) {
          wrapper.release(ptrArray[kCount - i - 1]);
        }
        usage('release from end');

        // Fixed blocks tests...
        for (i = 0; i < kCount ~/ 2; i++) {
          ptrArray[i] = wrapper.alloc(fixedBlockSize);
        }
        usage('alloc fixed');

        for (i = 0; i < kCount ~/ 2; i++) {
          wrapper.shrink(ptrArray[i], 1);
        }
        usage('shrink to 1');

        for (i = kCount ~/ 2; i < kCount; i++) {
          ptrArray[i] = wrapper.alloc(64);
        }
        usage('alloc 64B');

        for (i = 0; i < kCount; i++) {
          wrapper.release(ptrArray[i]);
        }
        usage('release all from begin');

        for (i = 0; i < kCount; i++) {
          ptrArray[i] = wrapper.alloc(fixedBlockSize);
        }
        usage('alloc fixed all');

        _shuffle(ptrArray, kCount, prng);

        for (i = 0; i < kCount ~/ 2; i++) {
          wrapper.release(ptrArray[i]);
        }
        usage('release 50% fixed');

        for (i = 0; i < kCount ~/ 2; i++) {
          ptrArray[i] = wrapper.alloc(fixedBlockSize);
        }
        usage('alloc 50% fixed again');

        for (i = 0; i < kCount; i++) {
          wrapper.release(ptrArray[kCount - i - 1]);
        }
        usage('release all from end');

        wrapper.allocator.dispose();
        expect(_statsRow(wrapper.allocator), [0, 0, 0, 0, 0]);
      },
          skip: dualMappingUnsupported
              ? 'dual mapping is not supported by this host'
              : false);
    }

    test('query', () {
      final allocator = JitAllocator();
      const allocatedSize = 100;

      final allocatedSpan = JitAllocatorSpan();
      expect(allocator.alloc(allocatedSpan, allocatedSize), AsmJitError.ok);
      expect(allocatedSpan.rx, isNot(nullptr));
      expect(allocatedSpan.size, greaterThanOrEqualTo(allocatedSize));

      final queriedSpan = JitAllocatorSpan();
      expect(allocator.query(queriedSpan, allocatedSpan.rx), AsmJitError.ok);
      expect(allocatedSpan.rx, queriedSpan.rx);
      expect(allocatedSpan.rw, queriedSpan.rw);
      expect(allocatedSpan.size, queriedSpan.size);

      allocator.dispose();
    });
  });

  group('JitAllocator - basic', () {
    test('defaults', () {
      final allocator = JitAllocator();
      expect(allocator.isInitialized, isTrue);
      expect(allocator.blockSize, VirtMem.info().pageGranularity);
      expect(allocator.granularity, 64);
      expect(allocator.fillPattern, _hostIsX86Family ? 0xCCCCCCCC : 0);
      expect(allocator.statistics().blockCount, 0);

      allocator.dispose();
      expect(allocator.isInitialized, isFalse);
      final span = JitAllocatorSpan();
      expect(allocator.alloc(span, 64), AsmJitError.notInitialized);
      expect(allocator.release(Pointer<Void>.fromAddress(64)),
          AsmJitError.notInitialized);
    });

    test('invalid params fall back to defaults', () {
      final allocator = JitAllocator(JitAllocatorCreateParams(
          blockSize: 12345, granularity: 100, fillPattern: 0x12345678));
      expect(allocator.blockSize, VirtMem.info().pageGranularity);
      expect(allocator.granularity, 64);
      // kCustomFillPattern not set: the custom pattern is ignored.
      expect(allocator.fillPattern, _hostIsX86Family ? 0xCCCCCCCC : 0);
      allocator.dispose();

      final custom = JitAllocator(JitAllocatorCreateParams(
          options: JitAllocatorOptions.kFillUnusedMemory |
              JitAllocatorOptions.kCustomFillPattern,
          blockSize: 1024 * 1024,
          granularity: 128,
          fillPattern: 0x12345678));
      expect(custom.blockSize, 1024 * 1024);
      expect(custom.granularity, 128);
      expect(custom.fillPattern, 0x12345678);
      custom.dispose();
    });

    test('alloc errors', () {
      final allocator = JitAllocator();
      final span = JitAllocatorSpan();
      expect(allocator.alloc(span, 0), AsmJitError.invalidArgument);
      expect(allocator.alloc(span, 0x80000000), AsmJitError.tooLarge);
      expect(allocator.release(nullptr), AsmJitError.invalidArgument);
      expect(allocator.release(Pointer<Void>.fromAddress(64)),
          AsmJitError.invalidState);
      expect(allocator.query(span, Pointer<Void>.fromAddress(64)),
          AsmJitError.invalidArgument);
      allocator.dispose();
    });

    test('spans are granularity aligned and share a block', () {
      final allocator = JitAllocator();
      final spans = List.generate(10, (_) => JitAllocatorSpan());
      for (final span in spans) {
        expect(allocator.alloc(span, 10), AsmJitError.ok);
        expect(span.size, 64);
        expect(span.rx.address % 64, 0);
      }
      // Initial padding: the first span starts one granule into the block.
      for (var i = 1; i < spans.length; i++) {
        expect(spans[i].rx.address - spans[i - 1].rx.address, 64);
      }

      final stats = allocator.statistics();
      expect(stats.blockCount, 1);
      expect(stats.allocationCount, 10);
      expect(stats.usedSize, 64 + 10 * 64);
      expect(stats.reservedSize, 2 * allocator.blockSize);

      // Releasing a span in the middle and allocating again reuses it.
      expect(allocator.release(spans[4].rx), AsmJitError.ok);
      final again = JitAllocatorSpan();
      expect(allocator.alloc(again, 64), AsmJitError.ok);
      expect(again.rx, spans[4].rx);

      allocator.dispose();
    });

    test('write, writeWith and shrink through writeWith', () {
      final allocator = JitAllocator();
      final span = JitAllocatorSpan();
      expect(allocator.alloc(span, 256), AsmJitError.ok);

      final bytes = Uint8List.fromList(List.generate(16, (i) => i + 1));
      expect(allocator.write(span, 8, bytes), AsmJitError.ok);
      expect(span.rx.cast<Uint8>().asTypedList(24).sublist(8), bytes);
      expect(allocator.write(span, 250, bytes), AsmJitError.invalidArgument);

      expect(
          allocator.writeWith(span, (s) {
            s.rw.cast<Uint8>()[0] = 0xAB;
            s.shrink(65);
            return AsmJitError.ok;
          }),
          AsmJitError.ok);
      expect(span.rx.cast<Uint8>()[0], 0xAB);
      expect(span.size, 128);

      final queried = JitAllocatorSpan();
      expect(allocator.query(queried, span.rx), AsmJitError.ok);
      expect(queried.size, 128);

      final scope = JitAllocatorWriteScope(allocator);
      expect(scope.write(span, 0, bytes), AsmJitError.ok);
      expect(scope.flush(), AsmJitError.ok);
      scope.end();
      expect(span.rx.cast<Uint8>().asTypedList(16), bytes);

      // Shrinking to zero releases the span.
      expect(allocator.shrink(span, 0), AsmJitError.ok);
      expect(span.rx, nullptr);
      expect(allocator.statistics().allocationCount, 0);

      allocator.dispose();
    });

    test('kFillUnusedMemory fills new blocks and released spans', () {
      final allocator = JitAllocator(JitAllocatorCreateParams(
          options: JitAllocatorOptions.kFillUnusedMemory |
              JitAllocatorOptions.kCustomFillPattern,
          fillPattern: 0xA5A5A5A5));
      final a = JitAllocatorSpan();
      final b = JitAllocatorSpan();
      expect(allocator.alloc(a, 256), AsmJitError.ok);
      expect(allocator.alloc(b, 256), AsmJitError.ok);
      expect(b.rx.cast<Uint8>().asTypedList(256), everyElement(0xA5));

      expect(allocator.write(b, 0, Uint8List(256)..fillRange(0, 256, 0x5A)),
          AsmJitError.ok);
      expect(allocator.release(b.rx), AsmJitError.ok);
      expect(b.rx.cast<Uint8>().asTypedList(256), everyElement(0xA5));
      allocator.dispose();
    });

    // Deviation from upstream (tool/upstream_repro/jitallocator_misc.cpp).
    test('reset(soft) with kFillUnusedMemory wipes the memory in use', () {
      final allocator = JitAllocator(JitAllocatorCreateParams(
          options: JitAllocatorOptions.kFillUnusedMemory |
              JitAllocatorOptions.kCustomFillPattern,
          fillPattern: 0xCCCCCCCC));
      final a = JitAllocatorSpan();
      expect(allocator.alloc(a, 256), AsmJitError.ok);
      expect(allocator.write(a, 0, Uint8List(256)..fillRange(0, 256, 0x5A)),
          AsmJitError.ok);

      allocator.reset(ResetPolicy.soft);
      expect(allocator.statistics().blockCount, 1);
      expect(a.rx.cast<Uint8>().asTypedList(256), everyElement(0xCC));

      final c = JitAllocatorSpan();
      expect(allocator.alloc(c, 256), AsmJitError.ok);
      expect(c.rx, a.rx);
      expect(c.rx.cast<Uint8>().asTypedList(256), everyElement(0xCC));
      allocator.dispose();
    });

    // Deviation from upstream (tool/upstream_repro/jitallocator_reset_soft.cpp).
    test('reset(soft) keeps one block without stale tree links', () {
      // Create three blocks B1, B2, B3 (equally sized spans fill every block
      // before the next one is created, so the block count right after an
      // allocation tells which block the span is in).
      final allocator = JitAllocator();
      final byBlock = <int, List<Pointer<Void>>>{};
      while (true) {
        final span = JitAllocatorSpan();
        expect(allocator.alloc(span, 1000), AsmJitError.ok);
        final blockCount = allocator.statistics().blockCount;
        if (blockCount == 4) {
          expect(allocator.release(span.rx), AsmJitError.ok);
          break;
        }
        byBlock.putIfAbsent(blockCount, () => []).add(span.rx);
      }
      expect(allocator.statistics().blockCount, 4);

      // Empty B3 (kept as the pool's empty block), then B1 (deleted), then
      // allocate into B3 again. Whatever the address order of the blocks,
      // B2 (now the first block of the pool, the one reset() keeps) is the
      // root of the RB-tree with B3 as its child.
      for (final p in byBlock[3]!) {
        expect(allocator.release(p), AsmJitError.ok);
      }
      for (final p in byBlock[1]!) {
        expect(allocator.release(p), AsmJitError.ok);
      }
      final inB3 = <Pointer<Void>>[];
      for (var i = 0; i < 10; i++) {
        final span = JitAllocatorSpan();
        expect(allocator.alloc(span, 1000), AsmJitError.ok);
        inB3.add(span.rx);
      }

      allocator.reset(ResetPolicy.soft);
      final stats = allocator.statistics();
      expect(stats.blockCount, 1);
      expect(stats.allocationCount, 0);

      // No pointer can be found any more: B3 was deleted (with stale links of
      // the kept block the lookup would still reach it and see its spans in
      // use) and the kept block is empty.
      final span = JitAllocatorSpan();
      for (final p in [...inB3, ...byBlock[2]!]) {
        expect(allocator.query(span, p), AsmJitError.invalidArgument);
      }

      // The tree stays consistent for new blocks.
      final again = <Pointer<Void>>[];
      for (var i = 0; i < 4000; i++) {
        final s = JitAllocatorSpan();
        expect(allocator.alloc(s, 1000), AsmJitError.ok);
        again.add(s.rx);
      }
      for (final p in again) {
        expect(allocator.release(p), AsmJitError.ok);
      }
      expect(allocator.statistics().allocationCount, 0);

      allocator.reset(ResetPolicy.hard);
      expect(allocator.statistics().blockCount, 0);
      allocator.dispose();
    });

    test('kUseMultiplePools selects the pool by size alignment', () {
      final allocator = JitAllocator(JitAllocatorCreateParams(
          options: JitAllocatorOptions.kUseMultiplePools));
      final s64 = JitAllocatorSpan();
      final s128 = JitAllocatorSpan();
      final s256 = JitAllocatorSpan();
      expect(allocator.alloc(s64, 64), AsmJitError.ok);
      expect(allocator.alloc(s128, 128), AsmJitError.ok);
      expect(allocator.alloc(s256, 256), AsmJitError.ok);
      // One block per pool.
      expect(allocator.statistics().blockCount, 3);
      allocator.dispose();
    });
  });

  group('VirtMem', () {
    test('info', () {
      final info = VirtMem.info();
      expect(info.pageSize, greaterThan(0));
      expect(info.pageSize & (info.pageSize - 1), 0);
      expect(info.pageGranularity, greaterThanOrEqualTo(info.pageSize));
      expect(info.pageGranularity, greaterThanOrEqualTo(65536));
    });

    test('hardened runtime info', () {
      final flags = hri.flags;
      if (Abi.current() == Abi.macosArm64) {
        expect(flags,
            HardenedRuntimeFlags.kEnabled | HardenedRuntimeFlags.kMapJit);
      } else if (Abi.current() == Abi.windowsX64) {
        expect(flags, HardenedRuntimeFlags.kDualMapping);
      } else if (Abi.current() == Abi.linuxX64 ||
          Abi.current() == Abi.linuxArm64) {
        expect(hri.hasFlag(HardenedRuntimeFlags.kDualMapping), isTrue);
        expect(hri.hasFlag(HardenedRuntimeFlags.kMapJit), isFalse);
      }
    });

    test('alloc / protect / release', () {
      final size = VirtMem.info().pageSize;
      final (err, p) = VirtMem.alloc(size, MemoryFlags.kAccessRW);
      expect(err, AsmJitError.ok);
      p.cast<Uint8>().asTypedList(size).fillRange(0, size, 0x42);
      expect(VirtMem.protect(p, size, MemoryFlags.kAccessRead), AsmJitError.ok);
      expect(p.cast<Uint8>()[size - 1], 0x42);
      expect(VirtMem.release(p, size), AsmJitError.ok);

      expect(VirtMem.alloc(0, MemoryFlags.kAccessRW).$1,
          AsmJitError.invalidArgument);
    });

    test('dual mapping', () {
      final size = VirtMem.info().pageGranularity;
      final dm = DualMapping();
      expect(VirtMem.allocDualMapping(dm, size, MemoryFlags.kAccessRWX),
          AsmJitError.ok);
      expect(dm.rx, isNot(nullptr));
      expect(dm.rw, isNot(nullptr));
      expect(dm.rx, isNot(dm.rw));

      dm.rw.cast<Uint32>().asTypedList(size ~/ 4).fillRange(0, size ~/ 4, 7);
      expect(dm.rx.cast<Uint32>()[size ~/ 4 - 1], 7);

      expect(VirtMem.releaseDualMapping(dm, size), AsmJitError.ok);
      expect(dm.rx, nullptr);
    },
        skip: hri.hasFlag(HardenedRuntimeFlags.kDualMapping)
            ? false
            : 'dual mapping is not supported by this host');
  });

  group('JitRuntime', () {
    JitFunction addReturnConstant(JitRuntime rt, int value) {
      final code = CodeHolder(env: rt.environment);
      if (hostIsA64) {
        final a = A64Assembler(code);
        a.movz(x0, value);
        a.ret();
      } else {
        final a = X86Assembler(code);
        a.movRI32(eax, value);
        a.ret();
      }
      return rt.add(code);
    }

    test('1000 small functions share one block and are released', () {
      const count = 1000;
      final rt = JitRuntime();
      final allocator = rt.allocator;

      final fns = <JitFunction>[];
      for (var i = 0; i < count; i++) {
        fns.add(addReturnConstant(rt, i));
      }

      // Every function runs and returns its own constant.
      for (var i = 0; i < count; i++) {
        final f = fns[i]
            .pointer
            .cast<NativeFunction<Int32 Function()>>()
            .asFunction<int Function()>();
        expect(f(), i);
      }

      // All functions live in the same block: one granule (64 bytes) each,
      // allocated back to back after the initial padding granule.
      final stats = allocator.statistics();
      expect(stats.allocationCount, count);
      expect(stats.blockCount, 1);
      expect(stats.usedSize, 64 + count * 64);
      expect(stats.reservedSize, 2 * allocator.blockSize);

      final addresses = fns.map((f) => f.address).toList()..sort();
      expect(addresses.last - addresses.first, (count - 1) * 64);
      expect(addresses.toSet().length, count);
      final span = JitAllocatorSpan();
      for (final fn in fns) {
        expect(fn.size, 64);
        expect(allocator.query(span, fn.pointer), AsmJitError.ok);
        expect(span.rx, fn.pointer);
        expect(span.size, 64);
      }

      // Releasing every second function frees its granule, which the next
      // functions reuse.
      for (var i = 0; i < count; i += 2) {
        fns[i].dispose();
        expect(fns[i].isDisposed, isTrue);
      }
      expect(allocator.statistics().allocationCount, count ~/ 2);
      expect(allocator.statistics().usedSize, 64 + (count ~/ 2) * 64);

      final freed = {for (var i = 0; i < count; i += 2) fns[i].address};
      for (var i = 0; i < count; i += 2) {
        fns[i] = addReturnConstant(rt, i + 30000);
        expect(freed.contains(fns[i].address), isTrue);
      }
      for (var i = 0; i < count; i++) {
        final f = fns[i]
            .pointer
            .cast<NativeFunction<Int32 Function()>>()
            .asFunction<int Function()>();
        expect(f(), i.isEven ? i + 30000 : i);
      }
      expect(allocator.statistics().blockCount, 1);

      // Release all: the (now empty) block is kept for next allocations.
      for (final fn in fns) {
        fn.dispose();
      }
      final released = allocator.statistics();
      expect(released.allocationCount, 0);
      expect(released.usedSize, 64);
      expect(released.blockCount, 1);

      // Disposing the runtime releases the virtual memory.
      rt.dispose();
      final disposed = allocator.statistics();
      expect(disposed.blockCount, 0);
      expect(disposed.reservedSize, 0);
    }, skip: skipUnlessJitHost);

    test('dispose invalidates outstanding functions', () {
      final rt = JitRuntime();
      final fn = addReturnConstant(rt, 7);
      expect(rt.allocator.statistics().allocationCount, 1);
      rt.dispose();
      expect(fn.isDisposed, isTrue);
      fn.dispose(); // no-op
      expect(rt.allocator.statistics().blockCount, 0);

      // The runtime can still be used.
      final fn2 = addReturnConstant(rt, 8);
      final f = fn2.pointer
          .cast<NativeFunction<Int32 Function()>>()
          .asFunction<int Function()>();
      expect(f(), 8);
      rt.dispose();
    }, skip: skipUnlessJitHost);

    test('custom allocator params', () {
      final rt = JitRuntime(
          allocatorParams: JitAllocatorCreateParams(
              options: JitAllocatorOptions.kImmediateRelease,
              granularity: 128));
      expect(rt.allocator.granularity, 128);
      final fn = rt.addBytes(Uint8List.fromList([0xC3]));
      expect(fn.size, 128);
      expect(rt.allocator.statistics().blockCount, 1);
      fn.dispose();
      // kImmediateRelease: the empty block is released right away (deviation
      // from upstream, tool/upstream_repro/jitallocator_counts.cpp: upstream
      // keeps a block whose last allocation is released in incremental mode).
      expect(rt.allocator.statistics().blockCount, 0);
      rt.dispose();
    });
  });
}
