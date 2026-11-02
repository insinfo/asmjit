/// Maps A64 instruction IDs + operands (from the Builder/Compiler IR) to
/// [A64Assembler] calls.
///
/// Hand-maintained: every entry is instruction-specific glue, so it used to be
/// hand-written Dart embedded in strings inside `tool/gen_a64_db.dart`. The
/// generator now only produces the instruction database (`a64_inst_db.g.dart`).
///
/// Unsupported instructions or operand combinations throw [UnsupportedError]:
/// silently dropping an instruction produces corrupted machine code.
import '../core/labels.dart';
import 'a64.dart';
import 'a64_assembler.dart';
import 'a64_inst_db.g.dart';

/// Dispatches an A64 instruction to the matching [A64Assembler] method.
///
/// Every AArch64 instruction encodes to at least 4 bytes, so if nothing was
/// emitted the instruction (or its operand combination) is unsupported.
void a64Dispatch(A64Assembler asm, int instId, List<Object> ops) {
  final start = asm.offset;
  _dispatch(asm, instId, ops);
  if (asm.offset == start) {
    final name = instId >= 0 && instId < kA64InstDb.length
        ? kA64InstDb[instId].name
        : '#$instId';
    throw UnsupportedError(
        'A64 dispatcher: unsupported instruction/operands: $name $ops');
  }
}

void _dispatch(A64Assembler asm, int instId, List<Object> ops) {
  switch (instId) {
    case A64InstId.kAbs:
      _vec2(asm, ops, (rd, rn) => asm.abs(rd, rn));
      break;
    case A64InstId.kAdd:
      _add(asm, ops);
      break;
    case A64InstId.kAdds:
      _adds(asm, ops);
      break;
    case A64InstId.kAdr:
      _adr(asm, ops);
      break;
    case A64InstId.kAdrp:
      _adrp(asm, ops);
      break;
    case A64InstId.kAnd:
      _and(asm, ops);
      break;
    case A64InstId.kAnds:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.ands(rd, rn, rm));
      break;
    case A64InstId.kAsr:
      _shift(asm, ops, A64Shift.asr);
      break;
    case A64InstId.kB:
      _b(asm, ops);
      break;
    case A64InstId.kB_cond:
      _bCond(asm, ops);
      break;
    case A64InstId.kBfc:
      if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int)
        asm.bfc(ops[0] as A64Gp, ops[1] as int, ops[2] as int);
      break;
    case A64InstId.kBfi:
      if (ops.length == 4 &&
          ops[0] is A64Gp &&
          ops[1] is A64Gp &&
          ops[2] is int &&
          ops[3] is int)
        asm.bfi(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int, ops[3] as int);
      break;
    case A64InstId.kBfxil:
      if (ops.length == 4 &&
          ops[0] is A64Gp &&
          ops[1] is A64Gp &&
          ops[2] is int &&
          ops[3] is int)
        asm.bfxil(
            ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int, ops[3] as int);
      break;
    case A64InstId.kBic:
      _bic(asm, ops);
      break;
    case A64InstId.kBics:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.bics(rd, rn, rm));
      break;
    case A64InstId.kBif:
      _vec3(asm, ops, (rd, rn, rm) => asm.bif(rd, rn, rm));
      break;
    case A64InstId.kBit:
      _vec3(asm, ops, (rd, rn, rm) => asm.bit(rd, rn, rm));
      break;
    case A64InstId.kBl:
      _bl(asm, ops);
      break;
    case A64InstId.kBlr:
      _blr(asm, ops);
      break;
    case A64InstId.kBr:
      _br(asm, ops);
      break;
    case A64InstId.kBrk:
      if (ops.length == 1 && ops[0] is int) asm.brk(ops[0] as int);
      break;
    case A64InstId.kBsl:
      _vec3(asm, ops, (rd, rn, rm) => asm.bsl(rd, rn, rm));
      break;
    case A64InstId.kCbnz:
      _cb(asm, ops, zero: false);
      break;
    case A64InstId.kCbz:
      _cb(asm, ops, zero: true);
      break;
    case A64InstId.kCcmn:
      _cc(asm, ops, true);
      break;
    case A64InstId.kCcmp:
      _cc(asm, ops, false);
      break;
    case A64InstId.kCinc:
      _binCond(asm, ops, (rd, rn, cond) => asm.cinc(rd, rn, cond));
      break;
    case A64InstId.kCinv:
      _binCond(asm, ops, (rd, rn, cond) => asm.cinv(rd, rn, cond));
      break;
    case A64InstId.kCls:
      _cls(asm, ops);
      break;
    case A64InstId.kClz:
      _clz(asm, ops);
      break;
    case A64InstId.kCmn:
      _cmn(asm, ops);
      break;
    case A64InstId.kCmp:
      _cmp(asm, ops);
      break;
    case A64InstId.kCneg:
      _binCond(asm, ops, (rd, rn, cond) => asm.cneg(rd, rn, cond));
      break;
    case A64InstId.kCnt:
      _vec2(asm, ops, (rd, rn) => asm.cntVec(rd, rn));
      break;
    case A64InstId.kCrc32b:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32b(rd, rn, rm));
      break;
    case A64InstId.kCrc32cb:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32cb(rd, rn, rm));
      break;
    case A64InstId.kCrc32ch:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32ch(rd, rn, rm));
      break;
    case A64InstId.kCrc32cw:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32cw(rd, rn, rm));
      break;
    case A64InstId.kCrc32cx:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32cx(rd, rn, rm));
      break;
    case A64InstId.kCrc32h:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32h(rd, rn, rm));
      break;
    case A64InstId.kCrc32w:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32w(rd, rn, rm));
      break;
    case A64InstId.kCrc32x:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.crc32x(rd, rn, rm));
      break;
    case A64InstId.kCsel:
      _csel(asm, ops, (rd, rn, rm, cond) => asm.csel(rd, rn, rm, cond));
      break;
    case A64InstId.kCset:
      _unaryCond(asm, ops, (rd, cond) => asm.cset(rd, cond));
      break;
    case A64InstId.kCsetm:
      _unaryCond(asm, ops, (rd, cond) => asm.csetm(rd, cond));
      break;
    case A64InstId.kCsinc:
      _csel(asm, ops, (rd, rn, rm, cond) => asm.csinc(rd, rn, rm, cond));
      break;
    case A64InstId.kCsinv:
      _csel(asm, ops, (rd, rn, rm, cond) => asm.csinv(rd, rn, rm, cond));
      break;
    case A64InstId.kCsneg:
      _csel(asm, ops, (rd, rn, rm, cond) => asm.csneg(rd, rn, rm, cond));
      break;
    case A64InstId.kDmb:
      if (ops.length == 1 && ops[0] is int) asm.dmb(ops[0] as int);
      break;
    case A64InstId.kDsb:
      if (ops.length == 1 && ops[0] is int) asm.dsb(ops[0] as int);
      break;
    case A64InstId.kDup:
      _dup(asm, ops);
      break;
    case A64InstId.kEor:
      _eor(asm, ops);
      break;
    case A64InstId.kExtr:
      if (ops.length == 4 &&
          ops[0] is A64Gp &&
          ops[1] is A64Gp &&
          ops[2] is A64Gp &&
          ops[3] is int)
        asm.extr(
            ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as int);
      break;
    case A64InstId.kFabs:
      _fp2(asm, ops, asm.fabs, asm.fabsVec);
      break;
    case A64InstId.kFadd:
      _fp3(asm, ops, asm.fadd, asm.faddVec);
      break;
    case A64InstId.kFaddp:
      _vec3(asm, ops, (rd, rn, rm) => asm.faddp(rd, rn, rm));
      break;
    case A64InstId.kFcmp:
      _vec2(asm, ops, (rn, rm) => asm.fcmp(rn, rm));
      break;
    case A64InstId.kFcsel:
      _fcsel(asm, ops);
      break;
    case A64InstId.kFdiv:
      _fp3(asm, ops, asm.fdiv, asm.fdivVec);
      break;
    case A64InstId.kFmax:
      _fp3(asm, ops, null, asm.fmaxVec);
      break;
    case A64InstId.kFmaxnm:
      _fp3(asm, ops, null, asm.fmaxnmVec);
      break;
    case A64InstId.kFmin:
      _fp3(asm, ops, null, asm.fminVec);
      break;
    case A64InstId.kFminnm:
      _fp3(asm, ops, null, asm.fminnmVec);
      break;
    case A64InstId.kFmul:
      _fp3(asm, ops, asm.fmul, asm.fmulVec);
      break;
    case A64InstId.kFneg:
      _fp2(asm, ops, asm.fneg, asm.fnegVec);
      break;
    case A64InstId.kFsqrt:
      _fp2(asm, ops, asm.fsqrt, asm.fsqrtVec);
      break;
    case A64InstId.kFsub:
      _fp3(asm, ops, asm.fsub, asm.fsubVec);
      break;
    case A64InstId.kIsb:
      if (ops.length == 1 && ops[0] is int) asm.isb(ops[0] as int);
      break;
    case A64InstId.kLdp:
      _ldp(asm, ops);
      break;
    case A64InstId.kLdr:
      _ldr(asm, ops);
      break;
    case A64InstId.kLdrb:
      _ldrb(asm, ops);
      break;
    case A64InstId.kLdrh:
      _ldrh(asm, ops);
      break;
    case A64InstId.kLdrsb:
      _ldrsb(asm, ops);
      break;
    case A64InstId.kLdrsh:
      _ldrsh(asm, ops);
      break;
    case A64InstId.kLdrsw:
      _ldrsw(asm, ops);
      break;
    case A64InstId.kLdur:
      _ldur(asm, ops);
      break;
    case A64InstId.kLsl:
      _shift(asm, ops, A64Shift.lsl);
      break;
    case A64InstId.kLsr:
      _shift(asm, ops, A64Shift.lsr);
      break;
    case A64InstId.kMadd:
      _madd(asm, ops);
      break;
    case A64InstId.kMov:
      _mov(asm, ops);
      break;
    case A64InstId.kMovk:
      _movk(asm, ops);
      break;
    case A64InstId.kMovn:
      _movn(asm, ops);
      break;
    case A64InstId.kMovz:
      _movz(asm, ops);
      break;
    case A64InstId.kMsub:
      _msub(asm, ops);
      break;
    case A64InstId.kMul:
      _mul(asm, ops);
      break;
    case A64InstId.kMvn:
      _mvn(asm, ops);
      break;
    case A64InstId.kNeg:
      _neg(asm, ops);
      break;
    case A64InstId.kNegs:
      _unaryReg(asm, ops, (rd, rm) => asm.negs(rd, rm));
      break;
    case A64InstId.kNgc:
      _unaryReg(asm, ops, (rd, rm) => asm.ngc(rd, rm));
      break;
    case A64InstId.kNgcs:
      _unaryReg(asm, ops, (rd, rm) => asm.ngcs(rd, rm));
      break;
    case A64InstId.kNop:
      if (ops.isEmpty) asm.nop();
      break;
    case A64InstId.kOrn:
      _orn(asm, ops);
      break;
    case A64InstId.kOrr:
      _orr(asm, ops);
      break;
    case A64InstId.kRbit:
      _unaryReg(asm, ops, (rd, rn) => asm.rbit(rd, rn));
      break;
    case A64InstId.kRet:
      _ret(asm, ops);
      break;
    case A64InstId.kRev16:
      _vec2(asm, ops, (rd, rn) => asm.rev16(rd, rn));
      break;
    case A64InstId.kRev32:
      _vec2(asm, ops, (rd, rn) => asm.rev32(rd, rn));
      break;
    case A64InstId.kRev64:
      _vec2(asm, ops, (rd, rn) => asm.rev64(rd, rn));
      break;
    case A64InstId.kSbfiz:
      if (ops.length == 4 &&
          ops[0] is A64Gp &&
          ops[1] is A64Gp &&
          ops[2] is int &&
          ops[3] is int)
        asm.sbfiz(
            ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int, ops[3] as int);
      break;
    case A64InstId.kSbfx:
      if (ops.length == 4 &&
          ops[0] is A64Gp &&
          ops[1] is A64Gp &&
          ops[2] is int &&
          ops[3] is int)
        asm.sbfx(
            ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int, ops[3] as int);
      break;
    case A64InstId.kSdiv:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.sdiv(rd, rn, rm));
      break;
    case A64InstId.kSmov:
      _smov(asm, ops);
      break;
    case A64InstId.kStp:
      _stp(asm, ops);
      break;
    case A64InstId.kStr:
      _str(asm, ops);
      break;
    case A64InstId.kStrb:
      _strb(asm, ops);
      break;
    case A64InstId.kStrh:
      _strh(asm, ops);
      break;
    case A64InstId.kStur:
      _stur(asm, ops);
      break;
    case A64InstId.kSub:
      _sub(asm, ops);
      break;
    case A64InstId.kSubs:
      _subs(asm, ops);
      break;
    case A64InstId.kSvc:
      if (ops.length == 1 && ops[0] is int) asm.svc(ops[0] as int);
      break;
    case A64InstId.kSxtb:
      if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp)
        asm.sxtb(ops[0] as A64Gp, ops[1] as A64Gp);
      break;
    case A64InstId.kSxth:
      if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp)
        asm.sxth(ops[0] as A64Gp, ops[1] as A64Gp);
      break;
    case A64InstId.kSxtw:
      if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp)
        asm.sxtw(ops[0] as A64Gp, ops[1] as A64Gp);
      break;
    case A64InstId.kUbfiz:
      if (ops.length == 4 &&
          ops[0] is A64Gp &&
          ops[1] is A64Gp &&
          ops[2] is int &&
          ops[3] is int)
        asm.ubfiz(
            ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int, ops[3] as int);
      break;
    case A64InstId.kUbfx:
      if (ops.length == 4 &&
          ops[0] is A64Gp &&
          ops[1] is A64Gp &&
          ops[2] is int &&
          ops[3] is int)
        asm.ubfx(
            ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int, ops[3] as int);
      break;
    case A64InstId.kUdiv:
      _ternaryReg(asm, ops, (rd, rn, rm) => asm.udiv(rd, rn, rm));
      break;
    case A64InstId.kUmov:
      _umov(asm, ops);
      break;
    case A64InstId.kUxtb:
      if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp)
        asm.uxtb(ops[0] as A64Gp, ops[1] as A64Gp);
      break;
    case A64InstId.kUxth:
      if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp)
        asm.uxth(ops[0] as A64Gp, ops[1] as A64Gp);
      break;
    case A64InstId.kSqadd:
      _v3(asm, ops, asm.sqaddVec);
      break;
    case A64InstId.kUqadd:
      _v3(asm, ops, asm.uqaddVec);
      break;
    case A64InstId.kSqsub:
      _v3(asm, ops, asm.sqsubVec);
      break;
    case A64InstId.kUqsub:
      _v3(asm, ops, asm.uqsubVec);
      break;
    case A64InstId.kSmax:
      _v3(asm, ops, asm.smaxVec);
      break;
    case A64InstId.kUmax:
      _v3(asm, ops, asm.umaxVec);
      break;
    case A64InstId.kSmin:
      _v3(asm, ops, asm.sminVec);
      break;
    case A64InstId.kUmin:
      _v3(asm, ops, asm.uminVec);
      break;
    case A64InstId.kCmeq:
      _v3(asm, ops, asm.cmeqVec);
      break;
    case A64InstId.kCmgt:
      _v3(asm, ops, asm.cmgtVec);
      break;
    case A64InstId.kCmhi:
      _v3(asm, ops, asm.cmhiVec);
      break;
    case A64InstId.kCmge:
      _v3(asm, ops, asm.cmgeVec);
      break;
    case A64InstId.kCmhs:
      _v3(asm, ops, asm.cmhsVec);
      break;
    case A64InstId.kCmtst:
      _v3(asm, ops, asm.cmtstVec);
      break;
    case A64InstId.kFcmeq:
      _v3(asm, ops, asm.fcmeqVec);
      break;
    case A64InstId.kFcmge:
      _v3(asm, ops, asm.fcmgeVec);
      break;
    case A64InstId.kFcmgt:
      _v3(asm, ops, asm.fcmgtVec);
      break;
    case A64InstId.kZip1:
      _v3(asm, ops, asm.zip1);
      break;
    case A64InstId.kZip2:
      _v3(asm, ops, asm.zip2);
      break;
    case A64InstId.kUzp1:
      _v3(asm, ops, asm.uzp1);
      break;
    case A64InstId.kUzp2:
      _v3(asm, ops, asm.uzp2);
      break;
    case A64InstId.kTrn1:
      _v3(asm, ops, asm.trn1);
      break;
    case A64InstId.kTrn2:
      _v3(asm, ops, asm.trn2);
      break;
    case A64InstId.kTbl:
      _v3(asm, ops, asm.tbl);
      break;
    case A64InstId.kSmull:
      _v3(asm, ops, asm.smullVec);
      break;
    case A64InstId.kUmull:
      _v3(asm, ops, asm.umullVec);
      break;
    case A64InstId.kSmull2:
      _v3(asm, ops, asm.smullVec);
      break;
    case A64InstId.kUmull2:
      _v3(asm, ops, asm.umullVec);
      break;
    case A64InstId.kSmlal:
      _v3(asm, ops, asm.smlalVec);
      break;
    case A64InstId.kUmlal:
      _v3(asm, ops, asm.umlalVec);
      break;
    case A64InstId.kSmlal2:
      _v3(asm, ops, asm.smlalVec);
      break;
    case A64InstId.kUmlal2:
      _v3(asm, ops, asm.umlalVec);
      break;
    case A64InstId.kSshl:
      _v3(asm, ops, asm.sshlVec);
      break;
    case A64InstId.kUshl:
      _v3(asm, ops, asm.ushlVec);
      break;
    case A64InstId.kMovi:
      if (ops.length == 2 && ops[0] is A64Vec && ops[1] is int) {
        asm.moviB(ops[0] as A64Vec, ops[1] as int);
      }
      break;
    case A64InstId.kUrhadd:
      _v3(asm, ops, asm.urhaddVec);
      break;
    case A64InstId.kExt:
      if (ops.length == 4 &&
          ops[0] is A64Vec &&
          ops[1] is A64Vec &&
          ops[2] is A64Vec &&
          ops[3] is int) {
        asm.extVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec,
            ops[3] as int);
      }
      break;
    case A64InstId.kSqxtn:
      _v2(asm, ops, asm.sqxtn);
      break;
    case A64InstId.kSqxtn2:
      _v2(asm, ops, asm.sqxtn2);
      break;
    case A64InstId.kSqxtun:
      _v2(asm, ops, asm.sqxtun);
      break;
    case A64InstId.kSqxtun2:
      _v2(asm, ops, asm.sqxtun2);
      break;
    case A64InstId.kXtn:
      _v2(asm, ops, asm.xtn);
      break;
    case A64InstId.kXtn2:
      _v2(asm, ops, asm.xtn2);
      break;
    case A64InstId.kUqxtn:
      _v2(asm, ops, asm.uqxtn);
      break;
    case A64InstId.kUqxtn2:
      _v2(asm, ops, asm.uqxtn2);
      break;
    case A64InstId.kShl:
      _vShift(asm, ops, asm.shlVec);
      break;
    case A64InstId.kSli:
      _vShift(asm, ops, asm.sliVec);
      break;
    case A64InstId.kSshr:
      _vShift(asm, ops, asm.sshrVec);
      break;
    case A64InstId.kUshr:
      _vShift(asm, ops, asm.ushrVec);
      break;
    case A64InstId.kSsra:
      _vShift(asm, ops, asm.ssraVec);
      break;
    case A64InstId.kUsra:
      _vShift(asm, ops, asm.usraVec);
      break;
    case A64InstId.kSri:
      _vShift(asm, ops, asm.sriVec);
      break;
    case A64InstId.kShrn:
      _vShift(asm, ops, asm.shrnVec);
      break;
    case A64InstId.kShrn2:
      _vShift(asm, ops, asm.shrnVec);
      break;
    case A64InstId.kSshll:
      _vShift(asm, ops, asm.sshllVec);
      break;
    case A64InstId.kUshll:
      _vShift(asm, ops, asm.ushllVec);
      break;
    case A64InstId.kSshll2:
      _vShift(asm, ops, asm.sshllVec);
      break;
    case A64InstId.kUshll2:
      _vShift(asm, ops, asm.ushllVec);
      break;
    case A64InstId.kUrshr:
      _vShift(asm, ops, asm.urshrVec);
      break;
    case A64InstId.kUrsra:
      _vShift(asm, ops, asm.ursraVec);
      break;
    case A64InstId.kRshrn:
      _vShift(asm, ops, asm.rshrnVec);
      break;
    case A64InstId.kRshrn2:
      _vShift(asm, ops, asm.rshrnVec);
      break;
    case A64InstId.kFrintn:
      _fp2(asm, ops, asm.frintnS, asm.frintnVec);
      break;
    case A64InstId.kFrintm:
      _fp2(asm, ops, asm.frintmS, asm.frintmVec);
      break;
    case A64InstId.kFrintp:
      _fp2(asm, ops, asm.frintpS, asm.frintpVec);
      break;
    case A64InstId.kFrintz:
      _fp2(asm, ops, asm.frintzS, asm.frintzVec);
      break;
    case A64InstId.kFrinta:
      _fp2(asm, ops, asm.frintaS, asm.frintaVec);
      break;
    case A64InstId.kFcvtns:
      _fp2(asm, ops, null, asm.fcvtnsVec);
      break;
    case A64InstId.kFcvtl:
      _fp2(asm, ops, null, asm.fcvtlVec);
      break;
    case A64InstId.kFcvtl2:
      _fp2(asm, ops, null, asm.fcvtlVec);
      break;
    case A64InstId.kFcvtn:
      _fp2(asm, ops, null, asm.fcvtnVec);
      break;
    case A64InstId.kFcvtn2:
      _fp2(asm, ops, null, asm.fcvtnVec);
      break;
    case A64InstId.kScvtf:
      _fp2(asm, ops, asm.scvtf, asm.scvtfVec);
      break;
    case A64InstId.kUcvtf:
      _fp2(asm, ops, null, asm.ucvtfVec);
      break;
    case A64InstId.kFcvtzs:
      _fp2(asm, ops, asm.fcvtzs, asm.fcvtzsVec);
      break;
    case A64InstId.kFcvt:
      _v2(asm, ops, asm.fcvt);
      break;
    default:
      break;
  }
}

void _add(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.add(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.addVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  } else if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is int) {
    _addSubImm(asm, ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

/// ADD/SUB with an arbitrary immediate: negative values flip the operation
/// and multiples of 4096 use the `lsl #12` form.
void _addSubImm(A64Assembler asm, A64Gp rd, A64Gp rn, int imm,
    {bool sub = false}) {
  if (imm < 0) {
    imm = -imm;
    sub = !sub;
  }
  if (imm <= 0xFFF) {
    sub ? asm.subImm(rd, rn, imm) : asm.addImm(rd, rn, imm);
  } else if ((imm & 0xFFF) == 0 && (imm >> 12) <= 0xFFF) {
    sub
        ? asm.subImm(rd, rn, imm >> 12, shift: 12)
        : asm.addImm(rd, rn, imm >> 12, shift: 12);
  }
}

void _adds(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.addsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _sub(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.sub(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.subVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  } else if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is int) {
    _addSubImm(asm, ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int, sub: true);
  }
}

void _subs(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.subsImm(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  }
}

void _and(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.and(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.andVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}

void _orr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.orr(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.orrVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}

void _eor(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.eor(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.eorVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}

void _shift(A64Assembler asm, List<Object> ops, A64Shift shift) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    final dst = ops[0] as A64Gp;
    final src = ops[1] as A64Gp;
    final imm = ops[2] as int;
    final zr = dst.is64Bit ? xzr : wzr;
    if (shift == A64Shift.lsl) {
      asm.orr(dst, zr, src, shift: shift, amount: imm);
    } else {
      asm.eor(dst, zr, src, shift: shift, amount: imm);
    }
  }
}

void _cmp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    asm.cmp(ops[0] as A64Gp, ops[1] as A64Gp);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.cmpImm(ops[0] as A64Gp, ops[1] as int);
  }
}

void _cmn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.cmnImm(ops[0] as A64Gp, ops[1] as int);
  }
}

void _mov(A64Assembler asm, List<Object> ops) {
  // MOV (element), alias of INS: [Vd, dstIndex, Vn, srcIndex].
  if (ops.length == 4 &&
      ops[0] is A64Vec &&
      ops[1] is int &&
      ops[2] is A64Vec &&
      ops[3] is int) {
    asm.ins(ops[0] as A64Vec, ops[1] as int, ops[2] as A64Vec, ops[3] as int);
    return;
  }
  if (ops.length != 2) return;
  final dst = ops[0], src = ops[1];
  if (dst is A64Gp && src is int) {
    asm.movImm64(dst, src);
  } else if (dst is A64Gp && src is A64Gp) {
    asm.mov(dst, src);
  } else if (dst is A64Vec && src is A64Vec) {
    // MOV Vd.16B, Vn.16B (alias of ORR); copies the whole register.
    final d = A64Vec(dst.id, 128, A64Layout.b16);
    final n = A64Vec(src.id, 128, A64Layout.b16);
    asm.orrVec(d, n, n);
  }
}

void _movz(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movz(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}

void _movn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movn(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}

void _movk(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is int && ops[2] is int) {
    asm.movk(ops[0] as A64Gp, ops[1] as int, shift: ops[2] as int);
  }
}

void _adr(A64Assembler asm, List<Object> ops) {
  if (ops.length != 2 || ops[0] is! A64Gp) return;
  final rd = ops[0] as A64Gp, target = ops[1];
  if (target is Label) {
    asm.adrLabel(rd, target);
  } else if (target is int) {
    asm.adr(rd, target);
  }
}

void _adrp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is int) {
    asm.adrp(ops[0] as A64Gp, ops[1] as int);
  }
}

void _b(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.b(ops[0] as Label);
  }
}

/// Vector shift by immediate: `[A64Vec, A64Vec, int]`.
void _vShift(
    A64Assembler asm, List<Object> ops, void Function(A64Vec, A64Vec, int) fn) {
  if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is int) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as int);
  }
}

/// Vector two-register op with both operands [A64Vec].
void _v2(A64Assembler asm, List<Object> ops, void Function(A64Vec, A64Vec) fn) {
  if (ops.length == 2 && ops[0] is A64Vec && ops[1] is A64Vec) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec);
  }
}

/// Vector three-register op with all operands [A64Vec].
void _v3(A64Assembler asm, List<Object> ops,
    void Function(A64Vec, A64Vec, A64Vec) fn) {
  if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}

/// Whether [v] carries a vector arrangement (`.4S`, `.2D`, ...) rather than
/// being a scalar view (`s0`, `d0`).
bool _hasArrangement(A64Vec v) => v.layout != A64Layout.none;

/// Whether the arrangement uses the full 128-bit register (Q=1).
bool _isWideArrangement(A64Vec v) =>
    v.layout == A64Layout.b16 ||
    v.layout == A64Layout.h8 ||
    v.layout == A64Layout.s4 ||
    v.layout == A64Layout.d2;

/// FP two-operand op: vector form when the destination has an arrangement,
/// scalar form otherwise.
void _fp2(
    A64Assembler asm,
    List<Object> ops,
    void Function(A64Vec, A64Vec)? scalar,
    void Function(A64Vec, A64Vec) vector) {
  if (ops.length != 2 || ops[0] is! A64Vec || ops[1] is! A64Vec) return;
  final rd = ops[0] as A64Vec, rn = ops[1] as A64Vec;
  if (_hasArrangement(rd)) {
    vector(rd, rn);
  } else if (scalar != null) {
    scalar(rd, rn);
  }
}

/// FP three-operand op: vector form when the destination has an arrangement,
/// scalar form otherwise.
void _fp3(
    A64Assembler asm,
    List<Object> ops,
    void Function(A64Vec, A64Vec, A64Vec)? scalar,
    void Function(A64Vec, A64Vec, A64Vec, {bool wide}) vector) {
  if (ops.length != 3 ||
      ops[0] is! A64Vec ||
      ops[1] is! A64Vec ||
      ops[2] is! A64Vec) {
    return;
  }
  final rd = ops[0] as A64Vec, rn = ops[1] as A64Vec, rm = ops[2] as A64Vec;
  if (_hasArrangement(rd)) {
    vector(rd, rn, rm, wide: _isWideArrangement(rd));
  } else if (scalar != null) {
    scalar(rd, rn, rm);
  }
}

/// B.cond: operands are `[label, cond]` (cond as [A64Cond] or its encoding).
void _bCond(A64Assembler asm, List<Object> ops) {
  if (ops.length != 2 || ops[0] is! Label) return;
  final c = ops[1];
  final cond = c is A64Cond
      ? c
      : c is int
          ? A64Cond.values.firstWhere((e) => e.encoding == c)
          : null;
  if (cond != null) asm.bCond(cond, ops[0] as Label);
}

void _bl(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is Label) {
    asm.bl(ops[0] as Label);
  }
}

void _cb(A64Assembler asm, List<Object> ops, {required bool zero}) {
  if (ops.length != 2) return;
  final rt = ops[0];
  final lbl = ops[1];
  if (rt is A64Gp && lbl is Label) {
    if (zero) {
      asm.cbz(rt, lbl);
    } else {
      asm.cbnz(rt, lbl);
    }
  }
}

void _br(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is A64Gp) {
    asm.br(ops[0] as A64Gp);
  }
}

void _blr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 1 && ops[0] is A64Gp) {
    asm.blr(ops[0] as A64Gp);
  }
}

void _ret(A64Assembler asm, List<Object> ops) {
  if (ops.isEmpty) {
    asm.ret();
  } else if (ops.length == 1 && ops[0] is A64Gp) {
    asm.ret(ops[0] as A64Gp);
  }
}

void _ldr(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.ldr(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.ldrVec(ops[0] as A64Vec, base, off);
    }
  } else if (ops.length == 2 && ops[1] is A64Mem) {
    _ldStMem(asm, ops[0], ops[1] as A64Mem, load: true);
  }
}

void _str(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.str(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.strVec(ops[0] as A64Vec, base, off);
    }
  } else if (ops.length == 2 && ops[1] is A64Mem) {
    _ldStMem(asm, ops[0], ops[1] as A64Mem, load: false);
  }
}

/// Offset of a `[base, #offset]` operand if it fits the scaled unsigned
/// 12-bit form for an access of [bytes] bytes, otherwise null.
int? _scaledOffset(A64Mem mem, int bytes) {
  if (mem.base == null ||
      mem.index != null ||
      mem.addrMode != A64AddrMode.offset) {
    return null;
  }
  final off = mem.displacement;
  return (off >= 0 && off % bytes == 0 && off ~/ bytes <= 0xFFF) ? off : null;
}

/// LDR/STR of a GP or SIMD&FP register through a `[base, #offset]` operand.
/// Uses the scaled unsigned-offset form when possible, otherwise LDUR/STUR.
void _ldStMem(A64Assembler asm, Object reg, A64Mem mem, {required bool load}) {
  final base = mem.base;
  if (base == null || mem.index != null || mem.addrMode != A64AddrMode.offset) {
    return;
  }
  final off = mem.displacement;
  if (reg is A64Gp) {
    final bytes = reg.size;
    if (off >= 0 && off % bytes == 0 && off ~/ bytes <= 0xFFF) {
      load ? asm.ldr(reg, base, off) : asm.str(reg, base, off);
    } else if (off >= -256 && off <= 255) {
      load ? asm.ldur(reg, base, off) : asm.stur(reg, base, off);
    }
  } else if (reg is A64Vec) {
    final bytes = reg.sizeBits ~/ 8;
    if (off >= 0 && off % bytes == 0 && off ~/ bytes <= 0xFFF) {
      load ? asm.ldrVec(reg, base, off) : asm.strVec(reg, base, off);
    } else if (off >= -256 && off <= 255) {
      load
          ? asm.ldrVecUnscaled(reg, base, off)
          : asm.strVecUnscaled(reg, base, off);
    }
  }
}

void _ldrb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Mem) {
    final off = _scaledOffset(ops[1] as A64Mem, 1);
    if (off != null) {
      asm.ldrb(ops[0] as A64Gp, (ops[1] as A64Mem).base!, off);
    }
  }
}

void _ldrh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Mem) {
    final off = _scaledOffset(ops[1] as A64Mem, 2);
    if (off != null) {
      asm.ldrh(ops[0] as A64Gp, (ops[1] as A64Mem).base!, off);
    }
  }
}

void _ldrsb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Mem) {
    final off = _scaledOffset(ops[1] as A64Mem, 1);
    if (off != null) {
      asm.ldrsb(ops[0] as A64Gp, (ops[1] as A64Mem).base!, off);
    }
  }
}

void _ldrsh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Mem) {
    final off = _scaledOffset(ops[1] as A64Mem, 2);
    if (off != null) {
      asm.ldrsh(ops[0] as A64Gp, (ops[1] as A64Mem).base!, off);
    }
  }
}

void _ldrsw(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.ldrsw(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Mem) {
    final off = _scaledOffset(ops[1] as A64Mem, 4);
    if (off != null) {
      asm.ldrsw(ops[0] as A64Gp, (ops[1] as A64Mem).base!, off);
    }
  }
}

void _strb(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.strb(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Mem) {
    final off = _scaledOffset(ops[1] as A64Mem, 1);
    if (off != null) {
      asm.strb(ops[0] as A64Gp, (ops[1] as A64Mem).base!, off);
    }
  }
}

void _strh(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Gp && ops[2] is int) {
    asm.strh(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as int);
  } else if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Mem) {
    final off = _scaledOffset(ops[1] as A64Mem, 2);
    if (off != null) {
      asm.strh(ops[0] as A64Gp, (ops[1] as A64Mem).base!, off);
    }
  }
}

void _ldur(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.ldur(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.ldrVecUnscaled(ops[0] as A64Vec, base, off);
    }
  }
}

void _stur(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[1] is A64Gp && ops[2] is int) {
    final base = ops[1] as A64Gp;
    final off = ops[2] as int;
    if (ops[0] is A64Gp) {
      asm.stur(ops[0] as A64Gp, base, off);
    } else if (ops[0] is A64Vec) {
      asm.strVecUnscaled(ops[0] as A64Vec, base, off);
    }
  }
}

void _ldp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is int) {
    asm.ldp(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as int);
  } else if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Mem) {
    final m = ops[2] as A64Mem;
    final rt = ops[0] as A64Gp, rt2 = ops[1] as A64Gp;
    if (m.base == null || m.index != null) return;
    switch (m.addrMode) {
      case A64AddrMode.offset:
        asm.ldp(rt, rt2, m.base!, m.displacement);
      case A64AddrMode.postIndex:
        asm.ldpPost(rt, rt2, m.base!, m.displacement);
      case A64AddrMode.preIndex:
        break; // Not needed yet; reported as unsupported.
    }
  }
}

void _stp(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is int) {
    asm.stp(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as int);
  } else if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Mem) {
    final m = ops[2] as A64Mem;
    final rt = ops[0] as A64Gp, rt2 = ops[1] as A64Gp;
    if (m.base == null || m.index != null) return;
    switch (m.addrMode) {
      case A64AddrMode.offset:
        asm.stp(rt, rt2, m.base!, m.displacement);
      case A64AddrMode.preIndex:
        asm.stpPre(rt, rt2, m.base!, m.displacement);
      case A64AddrMode.postIndex:
        break; // Not needed yet; reported as unsupported.
    }
  }
}

void _ternaryReg(
    A64Assembler asm, List<Object> ops, void Function(A64Gp, A64Gp, A64Gp) fn) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  }
}

void _mul(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.mul(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.mulVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}

void _madd(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is A64Gp) {
    asm.madd(
        ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as A64Gp);
  }
}

void _msub(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is A64Gp) {
    asm.msub(
        ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as A64Gp);
  }
}

void _vec3(A64Assembler asm, List<Object> ops,
    void Function(A64Vec, A64Vec, A64Vec) fn) {
  if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}

void _vec2(
    A64Assembler asm, List<Object> ops, void Function(A64Vec, A64Vec) fn) {
  if (ops.length == 2 && ops[0] is A64Vec && ops[1] is A64Vec) {
    fn(ops[0] as A64Vec, ops[1] as A64Vec);
  }
}

void _fcsel(A64Assembler asm, List<Object> ops) {
  if (ops.length == 4 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec &&
      ops[3] is A64Cond) {
    asm.fcsel(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec,
        ops[3] as A64Cond);
  }
}

void _dup(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Vec && ops[1] is A64Gp) {
    asm.dupGp(ops[0] as A64Vec, ops[1] as A64Gp);
    return;
  }
  if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is int) {
    asm.dup(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as int);
  }
}

void _umov(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Vec && ops[2] is int) {
    asm.umov(ops[0] as A64Gp, ops[1] as A64Vec, ops[2] as int);
  }
}

void _smov(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 && ops[0] is A64Gp && ops[1] is A64Vec && ops[2] is int) {
    asm.smov(ops[0] as A64Gp, ops[1] as A64Vec, ops[2] as int);
  }
}

void _neg(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    asm.neg(ops[0] as A64Gp, ops[1] as A64Gp);
  } else if (ops.length == 2 && ops[0] is A64Vec && ops[1] is A64Vec) {
    asm.negVec(ops[0] as A64Vec, ops[1] as A64Vec);
  }
}

void _mvn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    asm.mvn(ops[0] as A64Gp, ops[1] as A64Gp);
  } else if (ops.length == 2 && ops[0] is A64Vec && ops[1] is A64Vec) {
    asm.mvnVec(ops[0] as A64Vec, ops[1] as A64Vec);
  }
}

void _csel(A64Assembler asm, List<Object> ops,
    void Function(A64Gp, A64Gp, A64Gp, A64Cond) fn) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp &&
      ops[3] is A64Cond) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp, ops[3] as A64Cond);
  }
}

void _binCond(A64Assembler asm, List<Object> ops,
    void Function(A64Gp, A64Gp, A64Cond) fn) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Cond) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Cond);
  }
}

void _unaryCond(
    A64Assembler asm, List<Object> ops, void Function(A64Gp, A64Cond) fn) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Cond) {
    fn(ops[0] as A64Gp, ops[1] as A64Cond);
  }
}

void _unaryReg(
    A64Assembler asm, List<Object> ops, void Function(A64Gp, A64Gp) fn) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    fn(ops[0] as A64Gp, ops[1] as A64Gp);
  }
}

void _cls(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    asm.cls(ops[0] as A64Gp, ops[1] as A64Gp);
  } else if (ops.length == 2 && ops[0] is A64Vec && ops[1] is A64Vec) {
    asm.clsVec(ops[0] as A64Vec, ops[1] as A64Vec);
  }
}

void _clz(A64Assembler asm, List<Object> ops) {
  if (ops.length == 2 && ops[0] is A64Gp && ops[1] is A64Gp) {
    asm.clz(ops[0] as A64Gp, ops[1] as A64Gp);
  } else if (ops.length == 2 && ops[0] is A64Vec && ops[1] is A64Vec) {
    asm.clzVec(ops[0] as A64Vec, ops[1] as A64Vec);
  }
}

void _cc(A64Assembler asm, List<Object> ops, bool negative) {
  if (ops.length == 4 &&
      ops[0] is A64Gp &&
      ops[2] is int &&
      ops[3] is A64Cond) {
    if (negative) {
      asm.ccmn(ops[0] as A64Gp, ops[1], ops[2] as int, ops[3] as A64Cond);
    } else {
      asm.ccmp(ops[0] as A64Gp, ops[1], ops[2] as int, ops[3] as A64Cond);
    }
  }
}

void _bic(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.bic(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.bicVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}

void _orn(A64Assembler asm, List<Object> ops) {
  if (ops.length == 3 &&
      ops[0] is A64Gp &&
      ops[1] is A64Gp &&
      ops[2] is A64Gp) {
    asm.orn(ops[0] as A64Gp, ops[1] as A64Gp, ops[2] as A64Gp);
  } else if (ops.length == 3 &&
      ops[0] is A64Vec &&
      ops[1] is A64Vec &&
      ops[2] is A64Vec) {
    asm.ornVec(ops[0] as A64Vec, ops[1] as A64Vec, ops[2] as A64Vec);
  }
}
