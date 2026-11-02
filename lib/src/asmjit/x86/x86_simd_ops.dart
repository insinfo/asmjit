/// Opcode table for SSE/AVX instructions encoded by [X86Encoder.simdLegacy]
/// and [X86Encoder.simdVex].
///
/// The legacy SSE form (`[66|F2|F3] [REX] 0F [38|3A] op /r`) and the VEX form
/// (`VEX.L.pp.mmmmm.W op /r`) of these instructions share prefix, opcode map
/// and opcode byte, so one entry describes both (`paddb` and `vpaddb`), which
/// is how asmjit's instruction database models them.
library;

/// Operand shape of a table entry.
enum X86SimdKind {
  /// `op xmm, xmm/m` (legacy: dst is read/write; VEX: dst, src1, src2).
  rm,

  /// `op xmm, xmm/m, imm8` (VEX: dst, src1, src2, imm8).
  rmi,

  /// Two-operand also in VEX form (`vpabsb xmm, xmm/m`): VEX.vvvv = 1111b.
  rm2,

  /// Two-operand + imm8 also in VEX form (`vpshufd xmm, xmm/m, imm8`).
  rm2i,

  /// Shift by immediate: `op xmm, imm8` with an opcode extension in ModRM.reg
  /// (legacy: dst is the r/m operand; VEX: `vpsllw dst(vvvv), src(rm), imm8`).
  shiftImm,

  /// VEX-only four operand form with the fourth register in imm8[7:4]
  /// (`vpblendvb dst, src1, src2/m, mask`). The legacy SSE4.1 form takes the
  /// mask implicitly in XMM0 and is not encoded through the table.
  is4,

  /// Store form `op mem, xmm` (ModRM.reg = xmm, r/m = memory, no VEX.vvvv).
  mr,

  /// Extract form `op mem|gp, xmm, imm8` (ModRM.reg = xmm, r/m = destination).
  mri,
}

class X86SimdOp {
  /// Mandatory prefix: 0 (none), 0x66, 0xF2 or 0xF3.
  final int prefix;

  /// Opcode map: 1 = 0F, 2 = 0F38, 3 = 0F3A.
  final int map;
  final int opcode;
  final X86SimdKind kind;

  /// ModRM.reg opcode extension for [X86SimdKind.shiftImm].
  final int regExt;

  /// VEX.W / REX.W.
  final bool w;

  /// The r/m operand must be memory (the register form is another
  /// instruction, e.g. `movlps xmm, xmm` would be MOVHLPS).
  final bool memOnly;

  /// The r/m operand may be a general purpose register (`pinsrd xmm, r32`,
  /// `pextrd r32, xmm`).
  final bool rmGp;

  const X86SimdOp(this.prefix, this.map, this.opcode,
      {this.kind = X86SimdKind.rm,
      this.regExt = 0,
      this.w = false,
      this.memOnly = false,
      this.rmGp = false});

  /// VEX.pp encoding of [prefix].
  int get pp => switch (prefix) { 0x66 => 1, 0xF3 => 2, 0xF2 => 3, _ => 0 };
}

const _66 = 0x66, _F2 = 0xF2, _F3 = 0xF3;
const _rmi = X86SimdKind.rmi, _rm2 = X86SimdKind.rm2;
const _rm2i = X86SimdKind.rm2i, _sh = X86SimdKind.shiftImm;

/// Keyed by the legacy mnemonic; the VEX form is `'v' + mnemonic`.
const Map<String, X86SimdOp> kX86SimdOps = {
  // SSE2 integer arithmetic (66 0F).
  'paddb': X86SimdOp(_66, 1, 0xFC),
  'paddw': X86SimdOp(_66, 1, 0xFD),
  'paddd': X86SimdOp(_66, 1, 0xFE),
  'paddq': X86SimdOp(_66, 1, 0xD4),
  'psubb': X86SimdOp(_66, 1, 0xF8),
  'psubw': X86SimdOp(_66, 1, 0xF9),
  'psubd': X86SimdOp(_66, 1, 0xFA),
  'psubq': X86SimdOp(_66, 1, 0xFB),
  'paddsb': X86SimdOp(_66, 1, 0xEC),
  'paddsw': X86SimdOp(_66, 1, 0xED),
  'paddusb': X86SimdOp(_66, 1, 0xDC),
  'paddusw': X86SimdOp(_66, 1, 0xDD),
  'psubsb': X86SimdOp(_66, 1, 0xE8),
  'psubsw': X86SimdOp(_66, 1, 0xE9),
  'psubusb': X86SimdOp(_66, 1, 0xD8),
  'psubusw': X86SimdOp(_66, 1, 0xD9),
  'pmullw': X86SimdOp(_66, 1, 0xD5),
  'pmulhw': X86SimdOp(_66, 1, 0xE5),
  'pmulhuw': X86SimdOp(_66, 1, 0xE4),
  'pmuludq': X86SimdOp(_66, 1, 0xF4),
  'pmaddwd': X86SimdOp(_66, 1, 0xF5),
  'pminub': X86SimdOp(_66, 1, 0xDA),
  'pmaxub': X86SimdOp(_66, 1, 0xDE),
  'pminsw': X86SimdOp(_66, 1, 0xEA),
  'pmaxsw': X86SimdOp(_66, 1, 0xEE),
  'pavgb': X86SimdOp(_66, 1, 0xE0),
  'pavgw': X86SimdOp(_66, 1, 0xE3),
  'psadbw': X86SimdOp(_66, 1, 0xF6),
  'pand': X86SimdOp(_66, 1, 0xDB),
  'pandn': X86SimdOp(_66, 1, 0xDF),
  'por': X86SimdOp(_66, 1, 0xEB),
  'pxor': X86SimdOp(_66, 1, 0xEF),
  'pcmpeqb': X86SimdOp(_66, 1, 0x74),
  'pcmpeqw': X86SimdOp(_66, 1, 0x75),
  'pcmpeqd': X86SimdOp(_66, 1, 0x76),
  'pcmpgtb': X86SimdOp(_66, 1, 0x64),
  'pcmpgtw': X86SimdOp(_66, 1, 0x65),
  'pcmpgtd': X86SimdOp(_66, 1, 0x66),
  'packsswb': X86SimdOp(_66, 1, 0x63),
  'packssdw': X86SimdOp(_66, 1, 0x6B),
  'packuswb': X86SimdOp(_66, 1, 0x67),
  'punpcklbw': X86SimdOp(_66, 1, 0x60),
  'punpcklwd': X86SimdOp(_66, 1, 0x61),
  'punpckldq': X86SimdOp(_66, 1, 0x62),
  'punpcklqdq': X86SimdOp(_66, 1, 0x6C),
  'punpckhbw': X86SimdOp(_66, 1, 0x68),
  'punpckhwd': X86SimdOp(_66, 1, 0x69),
  'punpckhdq': X86SimdOp(_66, 1, 0x6A),
  'punpckhqdq': X86SimdOp(_66, 1, 0x6D),

  // SSE2 shifts by xmm count and by immediate.
  'psllw': X86SimdOp(_66, 1, 0xF1),
  'pslld': X86SimdOp(_66, 1, 0xF2),
  'psllq': X86SimdOp(_66, 1, 0xF3),
  'psrlw': X86SimdOp(_66, 1, 0xD1),
  'psrld': X86SimdOp(_66, 1, 0xD2),
  'psrlq': X86SimdOp(_66, 1, 0xD3),
  'psraw': X86SimdOp(_66, 1, 0xE1),
  'psrad': X86SimdOp(_66, 1, 0xE2),
  'psllw_i': X86SimdOp(_66, 1, 0x71, kind: _sh, regExt: 6),
  'psrlw_i': X86SimdOp(_66, 1, 0x71, kind: _sh, regExt: 2),
  'psraw_i': X86SimdOp(_66, 1, 0x71, kind: _sh, regExt: 4),
  'pslld_i': X86SimdOp(_66, 1, 0x72, kind: _sh, regExt: 6),
  'psrld_i': X86SimdOp(_66, 1, 0x72, kind: _sh, regExt: 2),
  'psrad_i': X86SimdOp(_66, 1, 0x72, kind: _sh, regExt: 4),
  'psllq_i': X86SimdOp(_66, 1, 0x73, kind: _sh, regExt: 6),
  'psrlq_i': X86SimdOp(_66, 1, 0x73, kind: _sh, regExt: 2),
  'pslldq_i': X86SimdOp(_66, 1, 0x73, kind: _sh, regExt: 7),
  'psrldq_i': X86SimdOp(_66, 1, 0x73, kind: _sh, regExt: 3),

  // Shuffles.
  'pshufd': X86SimdOp(_66, 1, 0x70, kind: _rm2i),
  'pshuflw': X86SimdOp(_F2, 1, 0x70, kind: _rm2i),
  'pshufhw': X86SimdOp(_F3, 1, 0x70, kind: _rm2i),
  'shufps': X86SimdOp(0, 1, 0xC6, kind: _rmi),
  'shufpd': X86SimdOp(_66, 1, 0xC6, kind: _rmi),

  // SSSE3 (66 0F38 / 0F3A).
  'pshufb': X86SimdOp(_66, 2, 0x00),
  'phaddw': X86SimdOp(_66, 2, 0x01),
  'phaddd': X86SimdOp(_66, 2, 0x02),
  'pmaddubsw': X86SimdOp(_66, 2, 0x04),
  'pmulhrsw': X86SimdOp(_66, 2, 0x0B),
  'pabsb': X86SimdOp(_66, 2, 0x1C, kind: _rm2),
  'pabsw': X86SimdOp(_66, 2, 0x1D, kind: _rm2),
  'pabsd': X86SimdOp(_66, 2, 0x1E, kind: _rm2),
  'palignr': X86SimdOp(_66, 3, 0x0F, kind: _rmi),

  // SSE4.1 / SSE4.2.
  'pminsb': X86SimdOp(_66, 2, 0x38),
  'pminsd': X86SimdOp(_66, 2, 0x39),
  'pminuw': X86SimdOp(_66, 2, 0x3A),
  'pminud': X86SimdOp(_66, 2, 0x3B),
  'pmaxsb': X86SimdOp(_66, 2, 0x3C),
  'pmaxsd': X86SimdOp(_66, 2, 0x3D),
  'pmaxuw': X86SimdOp(_66, 2, 0x3E),
  'pmaxud': X86SimdOp(_66, 2, 0x3F),
  'pmulld': X86SimdOp(_66, 2, 0x40),
  'pmuldq': X86SimdOp(_66, 2, 0x28),
  'pcmpeqq': X86SimdOp(_66, 2, 0x29),
  'pcmpgtq': X86SimdOp(_66, 2, 0x37),
  'packusdw': X86SimdOp(_66, 2, 0x2B),
  'ptest': X86SimdOp(_66, 2, 0x17, kind: _rm2),
  'pmovsxbw': X86SimdOp(_66, 2, 0x20, kind: _rm2),
  'pmovsxbd': X86SimdOp(_66, 2, 0x21, kind: _rm2),
  'pmovsxbq': X86SimdOp(_66, 2, 0x22, kind: _rm2),
  'pmovsxwd': X86SimdOp(_66, 2, 0x23, kind: _rm2),
  'pmovsxwq': X86SimdOp(_66, 2, 0x24, kind: _rm2),
  'pmovsxdq': X86SimdOp(_66, 2, 0x25, kind: _rm2),
  'pmovzxbw': X86SimdOp(_66, 2, 0x30, kind: _rm2),
  'pmovzxbd': X86SimdOp(_66, 2, 0x31, kind: _rm2),
  'pmovzxbq': X86SimdOp(_66, 2, 0x32, kind: _rm2),
  'pmovzxwd': X86SimdOp(_66, 2, 0x33, kind: _rm2),
  'pmovzxwq': X86SimdOp(_66, 2, 0x34, kind: _rm2),
  'pmovzxdq': X86SimdOp(_66, 2, 0x35, kind: _rm2),
  'pblendw': X86SimdOp(_66, 3, 0x0E, kind: _rmi),
  'blendps': X86SimdOp(_66, 3, 0x0C, kind: _rmi),
  'blendpd': X86SimdOp(_66, 3, 0x0D, kind: _rmi),
  'pblendvb': X86SimdOp(_66, 3, 0x4C, kind: X86SimdKind.is4),
  'blendvps': X86SimdOp(_66, 3, 0x4A, kind: X86SimdKind.is4),
  'blendvpd': X86SimdOp(_66, 3, 0x4B, kind: X86SimdKind.is4),
  'roundps': X86SimdOp(_66, 3, 0x08, kind: _rm2i),
  'roundpd': X86SimdOp(_66, 3, 0x09, kind: _rm2i),
  'roundss': X86SimdOp(_66, 3, 0x0A, kind: _rmi),
  'roundsd': X86SimdOp(_66, 3, 0x0B, kind: _rmi),

  // Floating point.
  'addps': X86SimdOp(0, 1, 0x58),
  'addpd': X86SimdOp(_66, 1, 0x58),
  'addss': X86SimdOp(_F3, 1, 0x58),
  'addsd': X86SimdOp(_F2, 1, 0x58),
  'subps': X86SimdOp(0, 1, 0x5C),
  'subpd': X86SimdOp(_66, 1, 0x5C),
  'subss': X86SimdOp(_F3, 1, 0x5C),
  'subsd': X86SimdOp(_F2, 1, 0x5C),
  'mulps': X86SimdOp(0, 1, 0x59),
  'mulpd': X86SimdOp(_66, 1, 0x59),
  'mulss': X86SimdOp(_F3, 1, 0x59),
  'mulsd': X86SimdOp(_F2, 1, 0x59),
  'divps': X86SimdOp(0, 1, 0x5E),
  'divpd': X86SimdOp(_66, 1, 0x5E),
  'divss': X86SimdOp(_F3, 1, 0x5E),
  'divsd': X86SimdOp(_F2, 1, 0x5E),
  'minps': X86SimdOp(0, 1, 0x5D),
  'minpd': X86SimdOp(_66, 1, 0x5D),
  'minss': X86SimdOp(_F3, 1, 0x5D),
  'minsd': X86SimdOp(_F2, 1, 0x5D),
  'maxps': X86SimdOp(0, 1, 0x5F),
  'maxpd': X86SimdOp(_66, 1, 0x5F),
  'maxss': X86SimdOp(_F3, 1, 0x5F),
  'maxsd': X86SimdOp(_F2, 1, 0x5F),
  'andps': X86SimdOp(0, 1, 0x54),
  'andpd': X86SimdOp(_66, 1, 0x54),
  'andnps': X86SimdOp(0, 1, 0x55),
  'andnpd': X86SimdOp(_66, 1, 0x55),
  'orps': X86SimdOp(0, 1, 0x56),
  'orpd': X86SimdOp(_66, 1, 0x56),
  'xorps': X86SimdOp(0, 1, 0x57),
  'xorpd': X86SimdOp(_66, 1, 0x57),
  'cmpps': X86SimdOp(0, 1, 0xC2, kind: _rmi),
  'cmppd': X86SimdOp(_66, 1, 0xC2, kind: _rmi),
  'cmpss': X86SimdOp(_F3, 1, 0xC2, kind: _rmi),
  'cmpsd': X86SimdOp(_F2, 1, 0xC2, kind: _rmi),
  'unpcklps': X86SimdOp(0, 1, 0x14),
  'unpckhps': X86SimdOp(0, 1, 0x15),
  'unpcklpd': X86SimdOp(_66, 1, 0x14),
  'unpckhpd': X86SimdOp(_66, 1, 0x15),
  'sqrtss': X86SimdOp(_F3, 1, 0x51),
  'sqrtsd': X86SimdOp(_F2, 1, 0x51),
  'sqrtps': X86SimdOp(0, 1, 0x51, kind: _rm2),
  'sqrtpd': X86SimdOp(_66, 1, 0x51, kind: _rm2),
  'cvtdq2ps': X86SimdOp(0, 1, 0x5B, kind: _rm2),
  'cvtps2dq': X86SimdOp(_66, 1, 0x5B, kind: _rm2),
  'cvttps2dq': X86SimdOp(_F3, 1, 0x5B, kind: _rm2),
  'cvtps2pd': X86SimdOp(0, 1, 0x5A, kind: _rm2),
  'cvtpd2ps': X86SimdOp(_66, 1, 0x5A, kind: _rm2),
  'movddup': X86SimdOp(_F2, 1, 0x12, kind: _rm2),

  // 64-bit half loads (rm, memory only) and stores (`*_st`, mr).
  'movlps': X86SimdOp(0, 1, 0x12, memOnly: true),
  'movhps': X86SimdOp(0, 1, 0x16, memOnly: true),
  'movlpd': X86SimdOp(_66, 1, 0x12, memOnly: true),
  'movhpd': X86SimdOp(_66, 1, 0x16, memOnly: true),
  'movlps_st': X86SimdOp(0, 1, 0x13, kind: X86SimdKind.mr),
  'movhps_st': X86SimdOp(0, 1, 0x17, kind: X86SimdKind.mr),
  'movlpd_st': X86SimdOp(_66, 1, 0x13, kind: X86SimdKind.mr),
  'movhpd_st': X86SimdOp(_66, 1, 0x17, kind: X86SimdKind.mr),

  // Element insert/extract (SSE4.1 except pinsrw; the SSE2 pextrw r32 form is
  // handled by the hand-written dispatcher case).
  'pinsrw': X86SimdOp(_66, 1, 0xC4, kind: _rmi, rmGp: true),
  'pinsrb': X86SimdOp(_66, 3, 0x20, kind: _rmi, rmGp: true),
  'pinsrd': X86SimdOp(_66, 3, 0x22, kind: _rmi, rmGp: true),
  'pinsrq': X86SimdOp(_66, 3, 0x22, kind: _rmi, rmGp: true, w: true),
  'pextrb': X86SimdOp(_66, 3, 0x14, kind: X86SimdKind.mri, rmGp: true),
  'pextrw': X86SimdOp(_66, 3, 0x15, kind: X86SimdKind.mri),
  'pextrd': X86SimdOp(_66, 3, 0x16, kind: X86SimdKind.mri, rmGp: true),
  'pextrq': X86SimdOp(_66, 3, 0x16, kind: X86SimdKind.mri, rmGp: true, w: true),

  // MOVQ xmm, xmm/m64 (load form; zero-extends to 128 bits).
  'movq': X86SimdOp(_F3, 1, 0x7E, kind: _rm2),
  'cvtpd2dq': X86SimdOp(_F2, 1, 0xE6, kind: _rm2),
  'cvttpd2dq': X86SimdOp(_66, 1, 0xE6, kind: _rm2),
};
