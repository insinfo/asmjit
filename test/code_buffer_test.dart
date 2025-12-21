/// AsmJit Unit Tests - Code Buffer
///
/// Tests for CodeBuffer functionality.

import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('CodeBuffer', () {
    late CodeBuffer buffer;

    setUp(() {
      buffer = CodeBuffer();
    });

    test('initial state', () {
      expect(buffer.length, equals(0));
      expect(buffer.isEmpty, isTrue);
      expect(buffer.isNotEmpty, isFalse);
    });

    test('emit8 adds single byte', () {
      buffer.emit8(0x90);
      expect(buffer.length, equals(1));
      expect(buffer.bytes[0], equals(0x90));
    });

    test('emit8 truncates to 8 bits', () {
      buffer.emit8(0x12345678);
      expect(buffer.bytes[0], equals(0x78));
    });

    test('emit16 little-endian', () {
      buffer.emit16(0x1234);
      expect(buffer.bytes, equals([0x34, 0x12]));
    });

    test('emit32 little-endian', () {
      buffer.emit32(0x12345678);
      expect(buffer.bytes, equals([0x78, 0x56, 0x34, 0x12]));
    });

    test('emit64 little-endian', () {
      buffer.emit64(0x0102030405060708);
      expect(buffer.bytes,
          equals([0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]));
    });

    test('emitBytes adds multiple bytes', () {
      buffer.emitBytes([0x48, 0x89, 0xC8]);
      expect(buffer.length, equals(3));
      expect(buffer.bytes, equals([0x48, 0x89, 0xC8]));
    });

    test('buffer grows when needed', () {
      // Emit more than initial capacity (256)
      for (int i = 0; i < 300; i++) {
        buffer.emit8(i & 0xFF);
      }
      expect(buffer.length, equals(300));
      expect(buffer.capacity, greaterThanOrEqualTo(300));
    });

    test('patch8 modifies byte in place', () {
      buffer.emitBytes([0x00, 0x00, 0x00, 0x00]);
      buffer.patch8(2, 0xFF);
      expect(buffer.bytes, equals([0x00, 0x00, 0xFF, 0x00]));
    });

    test('patch32 modifies 4 bytes in place', () {
      buffer.emitBytes([0x00, 0x00, 0x00, 0x00, 0x00]);
      buffer.patch32(1, 0x12345678);
      expect(buffer.bytes, equals([0x00, 0x78, 0x56, 0x34, 0x12]));
    });

    test('align pads to boundary', () {
      buffer.emit8(0x90);
      buffer.align(4);
      expect(buffer.length, equals(4));
    });

    test('alignWithNops uses NOP padding', () {
      buffer.emit8(0xC3); // ret
      final padding = buffer.alignWithNops(8);
      expect(padding, equals(7));
      expect(buffer.length, equals(8));
      // Check padding bytes are 0x90 (NOP)
      for (int i = 1; i < 8; i++) {
        expect(buffer.bytes[i], equals(0x90));
      }
    });

    test('clear resets length', () {
      buffer.emitBytes([1, 2, 3, 4, 5]);
      buffer.clear();
      expect(buffer.length, equals(0));
      expect(buffer.isEmpty, isTrue);
    });

    test('reserve allocates space', () {
      final offset = buffer.reserve(4);
      expect(offset, equals(0));
      expect(buffer.length, equals(4));
      // Reserved bytes should be zero
      expect(buffer.bytes, equals([0, 0, 0, 0]));
    });

    test('emitZeros adds zero bytes', () {
      buffer.emitZeros(5);
      expect(buffer.bytes, equals([0, 0, 0, 0, 0]));
    });

    test('emitFill adds pattern bytes', () {
      buffer.emitFill(3, 0xCC);
      expect(buffer.bytes, equals([0xCC, 0xCC, 0xCC]));
    });

    test('indexer read/write', () {
      buffer.emitBytes([1, 2, 3]);
      expect(buffer[1], equals(2));
      buffer[1] = 42;
      expect(buffer[1], equals(42));
    });
  });
}
