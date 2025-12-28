/// AsmJit Unit Tests - Register Allocator
///
/// Tests for the simple linear-scan register allocator.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('VirtReg', () {
    test('can be created', () {
      final vreg = VirtReg(0);
      expect(vreg.id, equals(0));
      expect(vreg.size, equals(8));
      expect(vreg.regClass, equals(RegClass.gp));
      expect(vreg.physReg, isNull);
      expect(vreg.isSpilled, isFalse);
    });

    test('toString works', () {
      final vreg = VirtReg(5);
      expect(vreg.toString(), equals('v5'));
    });
  });

  group('LiveInterval', () {
    test('contains works', () {
      final vreg = VirtReg(0);
      final interval = LiveInterval(RAWorkReg(vreg, 0), 5, 10);

      expect(interval.contains(4), isFalse);
      expect(interval.contains(5), isTrue);
      expect(interval.contains(7), isTrue);
      expect(interval.contains(10), isTrue);
      expect(interval.contains(11), isFalse);
    });

    test('intersects works', () {
      final v1 = VirtReg(0);
      final v2 = VirtReg(1);

      final i1 = LiveInterval(RAWorkReg(v1, 0), 0, 10);
      final i2 = LiveInterval(RAWorkReg(v2, 1), 5, 15);
      final i3 = LiveInterval(RAWorkReg(v2, 2), 11, 20);

      expect(i1.intersects(i2), isTrue);
      expect(i1.intersects(i3), isFalse);
    });
  });

  group('RALocal', () {
    test('can create virtual registers', () {
      final ra = RALocal(Arch.x64);

      final v0 = ra.newVirtReg();
      final v1 = ra.newVirtReg(size: 4);
      final v2 = ra.newVirtReg(regClass: RegClass.xmm);

      expect(v0.id, equals(0));
      expect(v1.id, equals(1));
      expect(v1.size, equals(4));
      expect(v2.regClass, equals(RegClass.xmm));

      expect(ra.virtualRegs.length, equals(3));
    });

    test('records uses correctly', () {
      final ra = RALocal(Arch.x64);

      final v0 = ra.newVirtReg();
      ra.recordUse(v0, 0);
      ra.recordUse(v0, 5);
      ra.recordUse(v0, 10);

      expect(v0.firstUse, equals(0));
      expect(v0.lastUse, equals(10));
    });

    test('computes live intervals', () {
      final ra = RALocal(Arch.x64);

      final v0 = ra.newVirtReg();
      final v1 = ra.newVirtReg();

      ra.recordUse(v0, 0);
      ra.recordUse(v0, 10);
      ra.recordUse(v1, 5);
      ra.recordUse(v1, 15);

      ra.computeLiveIntervals();

      expect(ra.liveIntervals.length, equals(2));
      expect(ra.liveIntervals[0].workReg.vreg, equals(v0)); // Sorted by start
      expect(ra.liveIntervals[1].workReg.vreg, equals(v1));
    });

    test('allocates simple case without spilling', () {
      final ra = RALocal(Arch.x64);

      final v0 = ra.newVirtReg();
      final v1 = ra.newVirtReg();
      final v2 = ra.newVirtReg();

      ra.recordUse(v0, 0);
      ra.recordUse(v0, 5);
      ra.recordUse(v1, 1);
      ra.recordUse(v1, 6);
      ra.recordUse(v2, 2);
      ra.recordUse(v2, 7);

      ra.allocate();

      // All should get physical registers
      expect(v0.physReg, isNotNull);
      expect(v1.physReg, isNotNull);
      expect(v2.physReg, isNotNull);

      // All different registers
      expect(v0.physReg, isNot(equals(v1.physReg)));
      expect(v1.physReg, isNot(equals(v2.physReg)));
      expect(v0.physReg, isNot(equals(v2.physReg)));

      // No spilling needed
      expect(v0.isSpilled, isFalse);
      expect(v1.isSpilled, isFalse);
      expect(v2.isSpilled, isFalse);
    });

    test('register reuse when intervals do not overlap', () {
      final ra = RALocal(Arch.x64);

      final v0 = ra.newVirtReg();
      final v1 = ra.newVirtReg();

      // Non-overlapping intervals
      ra.recordUse(v0, 0);
      ra.recordUse(v0, 5);
      ra.recordUse(v1, 10); // Starts after v0 ends
      ra.recordUse(v1, 15);

      ra.allocate();

      // Both should get allocated (potentially the same register, reused)
      expect(v0.physReg, isNotNull);
      expect(v1.physReg, isNotNull);
      expect(v0.isSpilled, isFalse);
      expect(v1.isSpilled, isFalse);
    });

    test('XMM registers allocated correctly', () {
      final ra = RALocal(Arch.x64);

      final v0 = ra.newVirtReg(regClass: RegClass.xmm);
      final v1 = ra.newVirtReg(regClass: RegClass.xmm);

      ra.recordUse(v0, 0);
      ra.recordUse(v0, 10);
      ra.recordUse(v1, 0);
      ra.recordUse(v1, 10);

      ra.allocate();

      expect(v0.physXmm, isNotNull);
      expect(v1.physXmm, isNotNull);
      expect(v0.physXmm, isNot(equals(v1.physXmm)));
    });

    test('spill area size is calculated correctly', () {
      final ra = RALocal(Arch.x64);

      expect(ra.spillAreaSize, equals(0));

      // Force spilling by creating too many overlapping live intervals
      // We have 14 GP registers, create 15 overlapping intervals
      for (int i = 0; i < 15; i++) {
        final v = ra.newVirtReg();
        ra.recordUse(v, 0);
        ra.recordUse(v, 100);
      }

      ra.allocate();

      // At least one should be spilled
      final spilledCount = ra.virtualRegs.where((v) => v.isSpilled).length;
      expect(spilledCount, greaterThanOrEqualTo(1));
      expect(ra.spillAreaSize, greaterThan(0));
    });

    test('reset clears state', () {
      final ra = RALocal(Arch.x64);

      ra.newVirtReg();
      ra.recordUse(ra.virtualRegs[0], 0);
      ra.computeLiveIntervals();

      ra.reset();

      expect(ra.virtualRegs.length, equals(0));
      expect(ra.liveIntervals.length, equals(0));
      expect(ra.spillAreaSize, equals(0));
    });

    test('toString provides useful output', () {
      final ra = RALocal(Arch.x64);

      final v0 = ra.newVirtReg();
      ra.recordUse(v0, 0);
      ra.recordUse(v0, 5);
      ra.allocate();

      final str = ra.toString();
      expect(str, contains('RALocal'));
      expect(str, contains('Virtual registers: 1'));
    });
  });
}
