/// UJIT Condition
///
/// Ported from asmjit/ujit/unicondition.h

import '../core/operand.dart';
import '../core/condcode.dart';
import 'uniop.dart';

/// Condition represents either a condition or an assignment operation that can be checked.
class UniCondition {
  final UniOpCond op;
  final int
      cond; // CondCode is int or enum. Using int to match ConditionalCode values usually.
  final Operand a;
  final Operand b;

  const UniCondition(this.op, this.cond, this.a, this.b);

  // Helper constructors/factories
  static UniCondition and_z(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAnd, CondCode.kZero, a, b);
  static UniCondition and_nz(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAnd, CondCode.kNotZero, a, b);

  static UniCondition or_z(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignOr, CondCode.kZero, a, b);
  static UniCondition or_nz(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignOr, CondCode.kNotZero, a, b);

  static UniCondition xor_z(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignXor, CondCode.kZero, a, b);
  static UniCondition xor_nz(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignXor, CondCode.kNotZero, a, b);

  static UniCondition add_z(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAdd, CondCode.kZero, a, b);
  static UniCondition add_nz(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAdd, CondCode.kNotZero, a, b);
  static UniCondition add_c(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAdd, CondCode.kCarry, a, b);
  static UniCondition add_nc(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAdd, CondCode.kNotCarry, a, b);
  static UniCondition add_s(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAdd, CondCode.kSign, a, b);
  static UniCondition add_ns(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignAdd, CondCode.kNotSign, a, b);

  static UniCondition sub_z(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignSub, CondCode.kZero, a, b);
  static UniCondition sub_nz(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignSub, CondCode.kNotZero, a, b);
  static UniCondition sub_c(Operand a, Operand b) => UniCondition(
      UniOpCond.assignSub, CondCode.kUnsignedLT, a, b); // Carry/UnsignedLT
  static UniCondition sub_nc(Operand a, Operand b) => UniCondition(
      UniOpCond.assignSub, CondCode.kUnsignedGE, a, b); // NotCarry/UnsignedGE
  static UniCondition sub_s(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignSub, CondCode.kSign, a, b);
  static UniCondition sub_ns(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignSub, CondCode.kNotSign, a, b);
  static UniCondition sub_ugt(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignSub, CondCode.kUnsignedGT, a, b);

  static UniCondition shr_z(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignShr, CondCode.kZero, a, b);
  static UniCondition shr_nz(Operand a, Operand b) =>
      UniCondition(UniOpCond.assignShr, CondCode.kNotZero, a, b);

  static UniCondition cmp_eq(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kEqual, a, b);
  static UniCondition cmp_ne(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kNotEqual, a, b);

  static UniCondition scmp_lt(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kSignedLT, a, b);
  static UniCondition scmp_le(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kSignedLE, a, b);
  static UniCondition scmp_gt(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kSignedGT, a, b);
  static UniCondition scmp_ge(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kSignedGE, a, b);

  static UniCondition ucmp_lt(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kUnsignedLT, a, b);
  static UniCondition ucmp_le(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kUnsignedLE, a, b);
  static UniCondition ucmp_gt(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kUnsignedGT, a, b);
  static UniCondition ucmp_ge(Operand a, Operand b) =>
      UniCondition(UniOpCond.compare, CondCode.kUnsignedGE, a, b);

  static UniCondition test_z(Operand a, [Operand? b]) {
    if (b == null) {
      return UniCondition(UniOpCond.compare, CondCode.kEqual, a, const Imm(0));
    } else {
      return UniCondition(UniOpCond.test, CondCode.kZero, a, b);
    }
  }

  static UniCondition test_nz(Operand a, [Operand? b]) {
    if (b == null) {
      return UniCondition(
          UniOpCond.compare, CondCode.kNotEqual, a, const Imm(0));
    } else {
      return UniCondition(UniOpCond.test, CondCode.kNotZero, a, b);
    }
  }

  static UniCondition bt_z(Operand a, Operand b) =>
      UniCondition(UniOpCond.bitTest, CondCode.kBTZero, a, b);
  static UniCondition bt_nz(Operand a, Operand b) =>
      UniCondition(UniOpCond.bitTest, CondCode.kBTNotZero, a, b);
}
