/// AsmJit Unit Tests - Labels and Relocations
///
/// Tests for Label and Fixup functionality.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('Label', () {
    test('creates valid label', () {
      final label = Label(0);
      expect(label.id, equals(0));
      expect(label.isValid, isTrue);
      expect(label.isInvalid, isFalse);
    });

    test('invalid label has negative id', () {
      expect(Label.invalid.id, equals(-1));
      expect(Label.invalid.isInvalid, isTrue);
      expect(Label.invalid.isValid, isFalse);
    });

    test('label equality', () {
      final l1 = Label(5);
      final l2 = Label(5);
      final l3 = Label(6);
      expect(l1, equals(l2));
      expect(l1, isNot(equals(l3)));
    });
  });

  group('LabelManager', () {
    late LabelManager manager;

    setUp(() {
      manager = LabelManager();
    });

    test('creates new labels', () {
      final l1 = manager.newLabel();
      final l2 = manager.newLabel();
      expect(l1.id, equals(0));
      expect(l2.id, equals(1));
      expect(manager.labelCount, equals(2));
    });

    test('creates named labels', () {
      final label = manager.newNamedLabel('loop');
      expect(label.isValid, isTrue);
      expect(manager.getLabelByName('loop'), equals(label));
    });

    test('throws on duplicate named label', () {
      manager.newNamedLabel('entry');
      expect(
        () => manager.newNamedLabel('entry'),
        throwsA(isA<AsmJitException>()),
      );
    });

    test('binds label to offset', () {
      final label = manager.newLabel();
      expect(manager.isBound(label), isFalse);

      manager.bind(label, 100);
      expect(manager.isBound(label), isTrue);
      expect(manager.getBoundOffset(label), equals(100));
    });

    test('throws on rebind', () {
      final label = manager.newLabel();
      manager.bind(label, 0);
      expect(
        () => manager.bind(label, 10),
        throwsA(isA<AsmJitException>()),
      );
    });

    test('throws on invalid label access', () {
      expect(
        () => manager.getState(Label(999)),
        throwsA(isA<AsmJitException>()),
      );
    });

    test('clear removes all labels', () {
      manager.newLabel();
      manager.newNamedLabel('test');
      manager.clear();
      expect(manager.labelCount, equals(0));
      expect(manager.getLabelByName('test'), isNull);
    });
  });

  group('Fixup', () {
    OffsetFormat rel32() =>
        OffsetFormat()..resetToSimpleValue(OffsetType.kSignedOffset, 4);

    test('is resolved when the label is bound', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final l = code.newLabel();
      code.text.buffer.emitZeros(4);
      code.newFixup(l, code.text.id, 0, -4, rel32());
      expect(code.unresolvedFixupCount, 1);
      code.text.buffer.emitZeros(12);
      code.bind(l);
      expect(code.unresolvedFixupCount, 0);
      // target(16) - offset(0) + rel(-4).
      expect(code.text.buffer.read32At(0), 12);
    });

    test('rejects a displacement that does not fit', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final l = code.newLabel();
      code.text.buffer.emitZeros(1);
      code.newFixup(l, code.text.id, 0, -1,
          OffsetFormat()..resetToSimpleValue(OffsetType.kSignedOffset, 1));
      code.text.buffer.emitZeros(300);
      expect(
          () => code.bind(l),
          throwsA(isA<AsmJitException>()
              .having((e) => e.code, 'code', AsmJitError.invalidDisplacement)));
      expect(code.unresolvedFixupCount, 1);
    });

    test('finalize() fails for a referenced label that is never bound', () {
      final code = CodeHolder(env: Environment.x64SysV());
      final l = code.newLabel();
      code.text.buffer.emitZeros(4);
      code.newFixup(l, code.text.id, 0, -4, rel32());
      expect(
          () => code.finalize(),
          throwsA(isA<AsmJitException>().having(
              (e) => e.code, 'code', AsmJitError.expressionLabelNotBound)));
    });
  });
}
