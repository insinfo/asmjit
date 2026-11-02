// Golden encodings for AArch64 general purpose forms used by the UJIT:
// logical immediates, shifted registers, TST, ROR, REV and shifts by register,
// emitted through the instruction dispatcher. Expected words were
// cross-checked with the LLVM disassembler.
import 'dart:typed_data';

import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/asmjit/arm/a64_encoder.dart' show A64Encoder;
import 'package:test/test.dart';

A64Gp x(int id) => A64Gp(id, 64);
A64Gp w(int id) => A64Gp(id, 32);

const lsl = A64Shift.lsl, lsr = A64Shift.lsr, asr = A64Shift.asr;

int _word(int instId, List<Object> ops) {
  final code = CodeHolder(env: Environment.aarch64());
  A64Assembler(code).emit(instId, ops);
  final bytes = code.finalize().textBytes;
  expect(bytes.length, 4);
  return ByteData.sublistView(Uint8List.fromList(bytes))
      .getUint32(0, Endian.little);
}

void main() {
  final cases = <String, (int, List<Object>, int)>{
    'and x0, x1, #0xff00': (A64InstId.kAnd, [x(0), x(1), 0xFF00], 0x92781C20),
    'and w0, w1, #0xff': (A64InstId.kAnd, [w(0), w(1), 0xFF], 0x12001C20),
    'orr x2, x3, #0x5555555555555555': (
      A64InstId.kOrr,
      [x(2), x(3), 0x5555555555555555],
      0xB200F062
    ),
    'eor w4, w5, #0x80000000': (
      A64InstId.kEor,
      [w(4), w(5), 0x80000000],
      0x520100A4
    ),
    'ands x6, x7, #0xfffffffffffffff0': (
      A64InstId.kAnds,
      [x(6), x(7), -16],
      0xF27CECE6
    ),
    'orr x0, x1, x2, lsl #8': (
      A64InstId.kOrr,
      [x(0), x(1), x(2), const A64ShiftOp(lsl, 8)],
      0xAA022020
    ),
    'orr w0, w1, w2, lsl #16': (
      A64InstId.kOrr,
      [w(0), w(1), w(2), const A64ShiftOp(lsl, 16)],
      0x2A024020
    ),
    'and x3, x4, x5, lsr #3': (
      A64InstId.kAnd,
      [x(3), x(4), x(5), const A64ShiftOp(lsr, 3)],
      0x8A450C83
    ),
    'eor x3, x4, x5, asr #63': (
      A64InstId.kEor,
      [x(3), x(4), x(5), const A64ShiftOp(asr, 63)],
      0xCA85FC83
    ),
    'add x0, x1, x2, lsl #3': (
      A64InstId.kAdd,
      [x(0), x(1), x(2), const A64ShiftOp(lsl, 3)],
      0x8B020C20
    ),
    'sub w0, w1, w2, lsl #1': (
      A64InstId.kSub,
      [w(0), w(1), w(2), const A64ShiftOp(lsl, 1)],
      0x4B020420
    ),
    'adds x0, x1, x2, lsr #4': (
      A64InstId.kAdds,
      [x(0), x(1), x(2), const A64ShiftOp(lsr, 4)],
      0xAB421020
    ),
    'subs xzr, x1, x2, asr #2': (
      A64InstId.kSubs,
      [xzr, x(1), x(2), const A64ShiftOp(asr, 2)],
      0xEB82083F
    ),
    'bic x0, x1, x2, asr #63': (
      A64InstId.kBic,
      [x(0), x(1), x(2), const A64ShiftOp(asr, 63)],
      0x8AA2FC20
    ),
    'orn w0, w1, w2, asr #31': (
      A64InstId.kOrn,
      [w(0), w(1), w(2), const A64ShiftOp(asr, 31)],
      0x2AA27C20
    ),
    'bics x0, x1, x2': (A64InstId.kBics, [x(0), x(1), x(2)], 0xEA220020),
    'eon w0, w1, w2': (A64InstId.kEon, [w(0), w(1), w(2)], 0x4A220020),
    'tst x1, x2': (A64InstId.kTst, [x(1), x(2)], 0xEA02003F),
    'tst w1, w2, lsr #4': (
      A64InstId.kTst,
      [w(1), w(2), const A64ShiftOp(lsr, 4)],
      0x6A42103F
    ),
    'tst x3, #0x1': (A64InstId.kTst, [x(3), 1], 0xF240007F),
    'tst w3, #0x80000000': (A64InstId.kTst, [w(3), 0x80000000], 0x7201007F),
    'ror x0, x1, #7': (A64InstId.kRor, [x(0), x(1), 7], 0x93C11C20),
    'ror w0, w1, #31': (A64InstId.kRor, [w(0), w(1), 31], 0x13817C20),
    'ror x0, x1, x2': (A64InstId.kRor, [x(0), x(1), x(2)], 0x9AC22C20),
    'ror w0, w1, w2': (A64InstId.kRor, [w(0), w(1), w(2)], 0x1AC22C20),
    'lsl x0, x1, x2': (A64InstId.kLsl, [x(0), x(1), x(2)], 0x9AC22020),
    'lsr w0, w1, w2': (A64InstId.kLsr, [w(0), w(1), w(2)], 0x1AC22420),
    'asr x0, x1, x2': (A64InstId.kAsr, [x(0), x(1), x(2)], 0x9AC22820),
    'rev x0, x1': (A64InstId.kRev, [x(0), x(1)], 0xDAC00C20),
    'rev w2, w3': (A64InstId.kRev, [w(2), w(3)], 0x5AC00862),
    'cmp x1, #0x5, lsl #12': (A64InstId.kCmp, [x(1), 0x5000], 0xF140143F),
    'adds w2, w3, #0x1, lsl #12': (
      A64InstId.kAdds,
      [w(2), w(3), 0x1000],
      0x31400462
    ),
    'subs x4, x5, #0xfff': (A64InstId.kSubs, [x(4), x(5), 0xFFF], 0xF13FFCA4),
    'bic x0, x1, #0xff': (A64InstId.kBic, [x(0), x(1), 0xFF], 0x9278DC20),
    'bic w0, w1, #0xff00': (A64InstId.kBic, [w(0), w(1), 0xFF00], 0x12105C20),
  };
  cases.forEach((name, c) {
    test(name, () {
      expect(_word(c.$1, c.$2).toRadixString(16), c.$3.toRadixString(16));
    });
  });

  // MOV (immediate) follows a64assembler.cpp: single MOVZ/MOVN, then ORR
  // with a logical immediate, then MOVZ/MOVN + MOVK.
  final movCases = <String, (A64Gp, int, List<int>)>{
    'mov w1, #-1': (w(1), -1, [0x12800001]),
    'mov x1, #-1': (x(1), -1, [0x92800001]),
    'mov x1, #0x1234': (x(1), 0x1234, [0xD2824681]),
    'mov w1, #0xffff1234': (w(1), 0xFFFF1234, [0x129DB961]),
    'mov w1, #0x12340000': (w(1), 0x12340000, [0x52A24681]),
    'mov w1, #0x1234ffff': (w(1), 0x1234FFFF, [0x12BDB961]),
    'mov x1, #0x123456789ab': (
      x(1),
      0x123456789AB,
      [0xD2913561, 0xF2A8ACE1, 0xF2C02461]
    ),
    'mov x1, #0xffffffffffff1234': (x(1), -0xEDCC, [0x929DB961]),
    'mov x1, #0xfffffffe00000000': (x(1), -0x200000000, [0xB25F7BE1]),
    'mov x1, #0x5555555555555555': (x(1), 0x5555555555555555, [0xB200F3E1]),
    'mov w1, #0x12345678': (w(1), 0x12345678, [0x528ACF01, 0x72A24681]),
    'mov x1, #0xffff1234ffff5678': (
      x(1),
      0xFFFF1234FFFF5678,
      [0x929530E1, 0xF2C24681]
    ),
    // movn w1, #0 (zero extended), as in encode_mov_sequence_32().
    'mov x1, #0xffffffff': (x(1), 0xFFFFFFFF, [0x12800001]),
  };
  movCases.forEach((name, c) {
    test(name, () {
      final code = CodeHolder(env: Environment.aarch64());
      A64Assembler(code).emit(A64InstId.kMov, [c.$1, c.$2]);
      final bytes = Uint8List.fromList(code.finalize().textBytes);
      final words = [
        for (var i = 0; i < bytes.length; i += 4)
          ByteData.sublistView(bytes).getUint32(i, Endian.little)
      ];
      expect(words.map((w) => w.toRadixString(16)),
          c.$3.map((w) => w.toRadixString(16)));
    });
  });

  test('encodeLogicalImm rejects non-bitmask values', () {
    for (final v in [0, -1, 0x1234, 0xFFFFFFFF]) {
      expect(A64Encoder.encodeLogicalImm(v, v == 0xFFFFFFFF ? 32 : 64), isNull,
          reason: '0x${v.toRadixString(16)}');
    }
  });
}
