import 'package:test/test.dart';
import 'package:asmjit/asmjit.dart';

void main() {
  group('TypeId', () {
    test('scalar types have correct sizes', () {
      expect(TypeId.int8.sizeInBytes, 1);
      expect(TypeId.uint8.sizeInBytes, 1);
      expect(TypeId.int16.sizeInBytes, 2);
      expect(TypeId.uint16.sizeInBytes, 2);
      expect(TypeId.int32.sizeInBytes, 4);
      expect(TypeId.uint32.sizeInBytes, 4);
      expect(TypeId.int64.sizeInBytes, 8);
      expect(TypeId.uint64.sizeInBytes, 8);
      expect(TypeId.float32.sizeInBytes, 4);
      expect(TypeId.float64.sizeInBytes, 8);
    });

    test('vector types have correct sizes', () {
      expect(TypeId.int32x4.sizeInBytes, 16);
      expect(TypeId.float32x4.sizeInBytes, 16);
      expect(TypeId.float64x2.sizeInBytes, 16);
      expect(TypeId.int32x8.sizeInBytes, 32);
      expect(TypeId.float32x8.sizeInBytes, 32);
      expect(TypeId.int32x16.sizeInBytes, 64);
    });

    test('isScalar identifies scalar types', () {
      expect(TypeId.int32.isScalar, isTrue);
      expect(TypeId.float64.isScalar, isTrue);
      expect(TypeId.int32x4.isScalar, isFalse);
    });

    test('isVec identifies vector types', () {
      expect(TypeId.int32.isVec, isFalse);
      expect(TypeId.int32x4.isVec, isTrue);
      expect(TypeId.float32x8.isVec, isTrue);
    });

    test('isVec128/256/512 identifies correct sizes', () {
      expect(TypeId.int32x4.isVec128, isTrue);
      expect(TypeId.int32x4.isVec256, isFalse);
      expect(TypeId.int32x8.isVec256, isTrue);
      expect(TypeId.int32x16.isVec512, isTrue);
    });

    test('isInt identifies integer types', () {
      expect(TypeId.int32.isInt, isTrue);
      expect(TypeId.uint64.isInt, isTrue);
      expect(TypeId.float32.isInt, isFalse);
    });

    test('isFloat identifies float types', () {
      expect(TypeId.float32.isFloat, isTrue);
      expect(TypeId.float64.isFloat, isTrue);
      expect(TypeId.int32.isFloat, isFalse);
    });

    test('isSigned and isUnsigned', () {
      expect(TypeId.int32.isSigned, isTrue);
      expect(TypeId.int32.isUnsigned, isFalse);
      expect(TypeId.uint32.isSigned, isFalse);
      expect(TypeId.uint32.isUnsigned, isTrue);
    });

    test('isAbstract identifies abstract types', () {
      expect(TypeId.intPtr.isAbstract, isTrue);
      expect(TypeId.uintPtr.isAbstract, isTrue);
      expect(TypeId.int32.isAbstract, isFalse);
    });

    test('deabstract converts to concrete type based on register size', () {
      expect(TypeId.intPtr.deabstract(8), TypeId.int64);
      expect(TypeId.uintPtr.deabstract(8), TypeId.uint64);
      expect(TypeId.intPtr.deabstract(4), TypeId.int32);
      expect(TypeId.uintPtr.deabstract(4), TypeId.uint32);
      // Non-abstract types return themselves
      expect(TypeId.int32.deabstract(8), TypeId.int32);
    });

    test('scalarType returns scalar of vector', () {
      expect(TypeId.int32x4.scalarType, TypeId.int32);
      expect(TypeId.float64x2.scalarType, TypeId.float64);
      expect(TypeId.uint8x16.scalarType, TypeId.uint8);
    });

    test('isMask identifies mask types', () {
      expect(TypeId.mask8.isMask, isTrue);
      expect(TypeId.mask64.isMask, isTrue);
      expect(TypeId.int32.isMask, isFalse);
    });

    test('vectorElementCount returns correct count', () {
      expect(vectorElementCount(TypeId.int32x4), 4);
      expect(vectorElementCount(TypeId.float64x2), 2);
      expect(vectorElementCount(TypeId.int8x16), 16);
      expect(vectorElementCount(TypeId.int32x8), 8);
      expect(vectorElementCount(TypeId.int32), 1);
    });
  });

  group('typeIdFromDart', () {
    test('maps Dart types to TypeId', () {
      expect(typeIdFromDart<int>(), TypeId.int64);
      expect(typeIdFromDart<double>(), TypeId.float64);
      expect(typeIdFromDart<bool>(), TypeId.uint8);
    });
  });
}
