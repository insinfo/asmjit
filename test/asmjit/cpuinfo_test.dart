/// AsmJit Unit Tests - CPU Info
///
/// Tests for CPU feature detection.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  if (!Environment.host().isX86Family) {
    return;
  }
  group('CpuFeatures', () {
    test('baseline has required x86-64 features', () {
      const baseline = CpuFeatures.baseline();

      expect(baseline.x64, isTrue);
      expect(baseline.fpu, isTrue);
      expect(baseline.cmov, isTrue);
      expect(baseline.mmx, isTrue);
      expect(baseline.sse, isTrue);
      expect(baseline.sse2, isTrue);

      // These are optional
      expect(baseline.sse3, isFalse);
      expect(baseline.avx, isFalse);
      expect(baseline.avx2, isFalse);
    });

    test('all constructor enables all features', () {
      const all = CpuFeatures.all();

      expect(all.x64, isTrue);
      expect(all.sse, isTrue);
      expect(all.sse2, isTrue);
      expect(all.sse3, isTrue);
      expect(all.ssse3, isTrue);
      expect(all.sse41, isTrue);
      expect(all.sse42, isTrue);
      expect(all.avx, isTrue);
      expect(all.avx2, isTrue);
      expect(all.avx512f, isTrue);
      expect(all.bmi1, isTrue);
      expect(all.bmi2, isTrue);
      expect(all.adx, isTrue);
      expect(all.popcnt, isTrue);
      expect(all.lzcnt, isTrue);
    });

    test('toString contains feature names', () {
      const baseline = CpuFeatures.baseline();
      final str = baseline.toString();

      expect(str, contains('SSE'));
      expect(str, contains('SSE2'));
      expect(str, contains('x64'));
    });
  });

  group('CpuInfo', () {
    test('host() returns valid CpuInfo', () {
      final info = CpuInfo.host();

      // Should not be empty
      expect(info.vendor, isNotEmpty);
      expect(info.logicalProcessors, greaterThan(0));

      // Features should have baseline x86-64 features
      expect(info.features.sse, isTrue);
      expect(info.features.sse2, isTrue);
    });

    test('host() is cached', () {
      final info1 = CpuInfo.host();
      final info2 = CpuInfo.host();

      // Should be the same instance
      expect(identical(info1, info2), isTrue);
    });

    test('toString provides useful output', () {
      final info = CpuInfo.host();
      final str = info.toString();

      expect(str, contains('vendor:'));
      expect(str, contains('brand:'));
      expect(str, contains('processors:'));
      expect(str, contains('features:'));
    });

    test('detects actual CPU features', () {
      final info = CpuInfo.host();

      print('Detected CPU Info:');
      print(info);

      // Intel or AMD
      expect(
        info.vendor.contains('Intel') ||
            info.vendor.contains('AMD') ||
            info.vendor == 'Unknown',
        isTrue,
        reason: 'Vendor should be Intel, AMD, or Unknown',
      );

      // Modern CPUs should have at least SSE3
      // But we don't fail if they don't
      if (info.features.sse3) {
        print('CPU has SSE3');
      }

      if (info.features.avx) {
        print('CPU has AVX');
      }

      if (info.features.avx2) {
        print('CPU has AVX2');
      }

      if (info.features.bmi2) {
        print('CPU has BMI2 (MULX)');
      }

      if (info.features.adx) {
        print('CPU has ADX (ADCX/ADOX)');
      }
    });
  });
}
