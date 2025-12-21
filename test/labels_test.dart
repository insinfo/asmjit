/// AsmJit Unit Tests - Labels and Relocations
///
/// Tests for Label and Reloc functionality.

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

  group('Reloc', () {
    test('rel32 has size 4', () {
      final reloc = Reloc(
        kind: RelocKind.rel32,
        atOffset: 0,
        target: Label(0),
      );
      expect(reloc.size, equals(4));
    });

    test('rel8 has size 1', () {
      final reloc = Reloc(
        kind: RelocKind.rel8,
        atOffset: 0,
        target: Label(0),
      );
      expect(reloc.size, equals(1));
    });

    test('abs64 has size 8', () {
      final reloc = Reloc(
        kind: RelocKind.abs64,
        atOffset: 0,
        target: Label(0),
      );
      expect(reloc.size, equals(8));
    });
  });
}
