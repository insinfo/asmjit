// Port of asmjit/x86/x86opcode_p.h (`Opcode`) and of the encoder-facing parts
// of asmjit/x86/x86instdb_p.h / x86instdb.h (`EncodingId`, `InstFlags`,
// `Avx512Flags`).

/// AsmJit's 32-bit x86 opcode value (`x86::Opcode::Bits`).
///
/// Don't reorder any fields: the shifts and masks are designed to make the
/// construction of REX, VEX and EVEX prefixes fast.
abstract final class X86Opcode {
  // MM & VEX & EVEX & XOP.
  static const int kMM_Shift = 8;
  static const int kMM_Mask = 0x1F << kMM_Shift;
  static const int kMM_00 = 0x00 << kMM_Shift;
  static const int kMM_0F = 0x01 << kMM_Shift;
  static const int kMM_0F38 = 0x02 << kMM_Shift;
  static const int kMM_0F3A = 0x03 << kMM_Shift;
  static const int kMM_0F01 = 0x04 << kMM_Shift;
  static const int kMM_MAP5 = 0x05 << kMM_Shift;
  static const int kMM_MAP6 = 0x06 << kMM_Shift;
  static const int kMM_XOP08 = 0x08 << kMM_Shift;
  static const int kMM_XOP09 = 0x09 << kMM_Shift;
  static const int kMM_XOP0A = 0x0A << kMM_Shift;
  static const int kMM_IsXOP_Shift = kMM_Shift + 3;
  static const int kMM_IsXOP = kMM_XOP08;
  static const int kMM_ForceEvex = 0x10 << kMM_Shift;

  // FPU_2B - second byte of the opcode used by FPU.
  static const int kFPU_2B_Shift = 10;
  static const int kFPU_2B_Mask = 0xFF << kFPU_2B_Shift;

  // CDSHL & CDTT (compressed displacement).
  static const int kCDSHL_Shift = 13;
  static const int kCDSHL_Mask = 0x7 << kCDSHL_Shift;
  static const int kCDTT_Shift = 16;
  static const int kCDTT_Mask = 0x3 << kCDTT_Shift;
  static const int kCDTT_None = 0x0 << kCDTT_Shift;
  static const int kCDTT_ByLL = 0x1 << kCDTT_Shift;
  static const int kCDTT_T1W = 0x2 << kCDTT_Shift;
  static const int kCDTT_DUP = 0x3 << kCDTT_Shift;

  /// `kCDTT_<name>` aliases used by the instruction table.
  static const cdtt = {
    '_': kCDTT_None,
    'None': kCDTT_None,
    'ByLL': kCDTT_ByLL,
    'T1W': kCDTT_T1W,
    'DUP': kCDTT_DUP,
    'FV': kCDTT_ByLL,
    'HV': kCDTT_ByLL,
    'QV': kCDTT_ByLL,
    'FVM': kCDTT_ByLL,
    'T1S': kCDTT_None,
    'T1F': kCDTT_None,
    'T2': kCDTT_None,
    'T4': kCDTT_None,
    'T8': kCDTT_None,
    'HVM': kCDTT_ByLL,
    'QVM': kCDTT_ByLL,
    'OVM': kCDTT_ByLL,
    '128': kCDTT_None,
  };

  // `O` field in ModR/M (??:xxx:???).
  static const int kModO_Shift = 18;
  static const int kModO_Mask = 0x7 << kModO_Shift;

  // `RM` field in ModR/M (??:???:xxx).
  static const int kModRM_Shift = 13;
  static const int kModRM_Mask = 0x7 << kModRM_Shift;

  // `PP` field.
  static const int kPP_Shift = 21;
  static const int kPP_VEXMask = 0x03 << kPP_Shift;
  static const int kPP_FPUMask = 0x07 << kPP_Shift;
  static const int kPP_00 = 0x00 << kPP_Shift;
  static const int kPP_66 = 0x01 << kPP_Shift;
  static const int kPP_F3 = 0x02 << kPP_Shift;
  static const int kPP_F2 = 0x03 << kPP_Shift;
  static const int kPP_9B = 0x07 << kPP_Shift;

  // REX|VEX|EVEX B|X|R|W bits (binary compatible with instruction options).
  static const int kREX_Shift = 24;
  static const int kREX_Mask = 0x0F << kREX_Shift;
  static const int kB = 0x01 << kREX_Shift;
  static const int kX = 0x02 << kREX_Shift;
  static const int kR = 0x04 << kREX_Shift;
  static const int kW = 0x08 << kREX_Shift;
  static const int kW_Shift = kREX_Shift + 3;
  static const int kW_0 = 0;
  static const int kW_1 = 1 << kW_Shift;

  // EVEX.W field.
  static const int kEvex_W_Shift = 28;
  static const int kEvex_W_Mask = 1 << kEvex_W_Shift;
  static const int kEvex_W_0 = 0;
  static const int kEvex_W_1 = 1 << kEvex_W_Shift;

  // `L` or `LL` field in AVX/XOP/AVX-512.
  static const int kLL_Shift = 29;
  static const int kLL_Mask = 0x3 << kLL_Shift;
  static const int kLL_0 = 0x0 << kLL_Shift;
  static const int kLL_1 = 0x1 << kLL_Shift;
  static const int kLL_2 = 0x2 << kLL_Shift;

  // Opcode combinations.
  static const int k000000 = kPP_00 | kMM_00;
  static const int k000F00 = kPP_00 | kMM_0F;
  static const int k000F01 = kPP_00 | kMM_0F01;
  static const int k000F0F = kPP_00 | kMM_0F;
  static const int k000F38 = kPP_00 | kMM_0F38;
  static const int k000F3A = kPP_00 | kMM_0F3A;
  static const int k00MAP5 = kPP_00 | kMM_MAP5;
  static const int k00MAP6 = kPP_00 | kMM_MAP6;
  static const int k660000 = kPP_66 | kMM_00;
  static const int k660F00 = kPP_66 | kMM_0F;
  static const int k660F01 = kPP_66 | kMM_0F01;
  static const int k660F38 = kPP_66 | kMM_0F38;
  static const int k660F3A = kPP_66 | kMM_0F3A;
  static const int k66MAP5 = kPP_66 | kMM_MAP5;
  static const int k66MAP6 = kPP_66 | kMM_MAP6;
  static const int kF20000 = kPP_F2 | kMM_00;
  static const int kF20F00 = kPP_F2 | kMM_0F;
  static const int kF20F01 = kPP_F2 | kMM_0F01;
  static const int kF20F38 = kPP_F2 | kMM_0F38;
  static const int kF20F3A = kPP_F2 | kMM_0F3A;
  static const int kF2MAP5 = kPP_F2 | kMM_MAP5;
  static const int kF2MAP6 = kPP_F2 | kMM_MAP6;
  static const int kF30000 = kPP_F3 | kMM_00;
  static const int kF30F00 = kPP_F3 | kMM_0F;
  static const int kF30F01 = kPP_F3 | kMM_0F01;
  static const int kF30F38 = kPP_F3 | kMM_0F38;
  static const int kF30F3A = kPP_F3 | kMM_0F3A;
  static const int kF3MAP5 = kPP_F3 | kMM_MAP5;
  static const int kF3MAP6 = kPP_F3 | kMM_MAP6;
  static const int kFPU_00 = kPP_00 | kMM_00;
  static const int kFPU_9B = kPP_9B | kMM_00;
  static const int kXOP_M8 = kPP_00 | kMM_XOP08;
  static const int kXOP_M9 = kPP_00 | kMM_XOP09;
  static const int kXOP_MA = kPP_00 | kMM_XOP0A;

  /// Opcode combinations (`k000F00`, `kF30F38`, `kFPU_9B`, `kXOP_M8`...).
  static const prefixes = {
    '0': 0,
    '000000': kPP_00 | kMM_00,
    '000F00': kPP_00 | kMM_0F,
    '000F01': kPP_00 | kMM_0F01,
    '000F0F': kPP_00 | kMM_0F,
    '000F38': kPP_00 | kMM_0F38,
    '000F3A': kPP_00 | kMM_0F3A,
    '00MAP5': kPP_00 | kMM_MAP5,
    '00MAP6': kPP_00 | kMM_MAP6,
    '660000': kPP_66 | kMM_00,
    '660F00': kPP_66 | kMM_0F,
    '660F01': kPP_66 | kMM_0F01,
    '660F38': kPP_66 | kMM_0F38,
    '660F3A': kPP_66 | kMM_0F3A,
    '66MAP5': kPP_66 | kMM_MAP5,
    '66MAP6': kPP_66 | kMM_MAP6,
    'F20000': kPP_F2 | kMM_00,
    'F20F00': kPP_F2 | kMM_0F,
    'F20F01': kPP_F2 | kMM_0F01,
    'F20F38': kPP_F2 | kMM_0F38,
    'F20F3A': kPP_F2 | kMM_0F3A,
    'F2MAP5': kPP_F2 | kMM_MAP5,
    'F2MAP6': kPP_F2 | kMM_MAP6,
    'F30000': kPP_F3 | kMM_00,
    'F30F00': kPP_F3 | kMM_0F,
    'F30F01': kPP_F3 | kMM_0F01,
    'F30F38': kPP_F3 | kMM_0F38,
    'F30F3A': kPP_F3 | kMM_0F3A,
    'F3MAP5': kPP_F3 | kMM_MAP5,
    'F3MAP6': kPP_F3 | kMM_MAP6,
    'FPU_00': kPP_00 | kMM_00,
    'FPU_9B': kPP_9B | kMM_00,
    'XOP_M8': kPP_00 | kMM_XOP08,
    'XOP_M9': kPP_00 | kMM_XOP09,
    'XOP_MA': kPP_00 | kMM_XOP0A,
  };

  /// `extract_mod_o()`.
  static int extractModO(int v) => (v >> kModO_Shift) & 0x07;

  /// `extract_mod_rm()`.
  static int extractModRM(int v) => (v >> kModRM_Shift) & 0x07;

  /// `add_prefix_by_size()`.
  static int prefixBySize(int size) => switch (size & 0xF) {
        2 => kPP_66,
        8 => kW,
        _ => 0,
      };

  /// `add_arith_by_size()`.
  static int arithBySize(int size) => switch (size & 0xF) {
        2 => 1 | kPP_66,
        4 => 1,
        8 => 1 | kW,
        _ => 0,
      };
}

/// `x86::InstDB::EncodingId`.
abstract final class X86Encoding {
  static const int kEncodingNone = 0;
  static const int kEncodingX86Op = 1;
  static const int kEncodingX86Op_Mod11RM = 2;
  static const int kEncodingX86Op_Mod11RM_I8 = 3;
  static const int kEncodingX86Op_xAddr = 4;
  static const int kEncodingX86Op_xAX = 5;
  static const int kEncodingX86Op_xDX_xAX = 6;
  static const int kEncodingX86Op_MemZAX = 7;
  static const int kEncodingX86I_xAX = 8;
  static const int kEncodingX86M = 9;
  static const int kEncodingX86M_NoMemSize = 10;
  static const int kEncodingX86M_NoSize = 11;
  static const int kEncodingX86M_GPB = 12;
  static const int kEncodingX86M_GPB_MulDiv = 13;
  static const int kEncodingX86M_Only = 14;
  static const int kEncodingX86M_Only_EDX_EAX = 15;
  static const int kEncodingX86M_Nop = 16;
  static const int kEncodingX86R_Native = 17;
  static const int kEncodingX86R_FromM = 18;
  static const int kEncodingX86R32_EDX_EAX = 19;
  static const int kEncodingX86Rm = 20;
  static const int kEncodingX86Rm_Raw66H = 21;
  static const int kEncodingX86Rm_NoSize = 22;
  static const int kEncodingX86Mr = 23;
  static const int kEncodingX86Mr_NoSize = 24;
  static const int kEncodingX86Arith = 25;
  static const int kEncodingX86Bswap = 26;
  static const int kEncodingX86Bt = 27;
  static const int kEncodingX86Call = 28;
  static const int kEncodingX86Cmpxchg = 29;
  static const int kEncodingX86Cmpxchg8b_16b = 30;
  static const int kEncodingX86Crc = 31;
  static const int kEncodingX86Enter = 32;
  static const int kEncodingX86Imul = 33;
  static const int kEncodingX86In = 34;
  static const int kEncodingX86Ins = 35;
  static const int kEncodingX86IncDec = 36;
  static const int kEncodingX86Int = 37;
  static const int kEncodingX86Jcc = 38;
  static const int kEncodingX86JecxzLoop = 39;
  static const int kEncodingX86Jmp = 40;
  static const int kEncodingX86JmpRel = 41;
  static const int kEncodingX86LcallLjmp = 42;
  static const int kEncodingX86Lea = 43;
  static const int kEncodingX86Mov = 44;
  static const int kEncodingX86Movabs = 45;
  static const int kEncodingX86MovsxMovzx = 46;
  static const int kEncodingX86MovntiMovdiri = 47;
  static const int kEncodingX86EnqcmdMovdir64b = 48;
  static const int kEncodingX86Out = 49;
  static const int kEncodingX86Outs = 50;
  static const int kEncodingX86Push = 51;
  static const int kEncodingX86Pushw = 52;
  static const int kEncodingX86Pop = 53;
  static const int kEncodingX86Ret = 54;
  static const int kEncodingX86Rot = 55;
  static const int kEncodingX86Set = 56;
  static const int kEncodingX86ShldShrd = 57;
  static const int kEncodingX86StrRm = 58;
  static const int kEncodingX86StrMr = 59;
  static const int kEncodingX86StrMm = 60;
  static const int kEncodingX86Test = 61;
  static const int kEncodingX86Xadd = 62;
  static const int kEncodingX86Xchg = 63;
  static const int kEncodingX86Fence = 64;
  static const int kEncodingX86Bndmov = 65;
  static const int kEncodingFpuOp = 66;
  static const int kEncodingFpuArith = 67;
  static const int kEncodingFpuCom = 68;
  static const int kEncodingFpuFldFst = 69;
  static const int kEncodingFpuM = 70;
  static const int kEncodingFpuR = 71;
  static const int kEncodingFpuRDef = 72;
  static const int kEncodingFpuStsw = 73;
  static const int kEncodingExtRm = 74;
  static const int kEncodingExtRm_XMM0 = 75;
  static const int kEncodingExtRm_ZDI = 76;
  static const int kEncodingExtRm_P = 77;
  static const int kEncodingExtRm_Wx = 78;
  static const int kEncodingExtRm_Wx_GpqOnly = 79;
  static const int kEncodingExtRmRi = 80;
  static const int kEncodingExtRmRi_P = 81;
  static const int kEncodingExtRmi = 82;
  static const int kEncodingExtRmi_P = 83;
  static const int kEncodingExtPextrw = 84;
  static const int kEncodingExtExtract = 85;
  static const int kEncodingExtMov = 86;
  static const int kEncodingExtMovbe = 87;
  static const int kEncodingExtMovd = 88;
  static const int kEncodingExtMovq = 89;
  static const int kEncodingExtExtrq = 90;
  static const int kEncodingExtInsertq = 91;
  static const int kEncodingExt3dNow = 92;
  static const int kEncodingVexOp = 93;
  static const int kEncodingVexOpMod = 94;
  static const int kEncodingVexKmov = 95;
  static const int kEncodingVexR_Wx = 96;
  static const int kEncodingVexM = 97;
  static const int kEncodingVexMr_Lx = 98;
  static const int kEncodingVexMr_VM = 99;
  static const int kEncodingVexMri = 100;
  static const int kEncodingVexMri_Lx = 101;
  static const int kEncodingVexMri_Vpextrw = 102;
  static const int kEncodingVexMvr_Wx = 103;
  static const int kEncodingVexRm = 104;
  static const int kEncodingVexRm_ZDI = 105;
  static const int kEncodingVexRm_Wx = 106;
  static const int kEncodingVexRm_Lx = 107;
  static const int kEncodingVexRm_Lx_Narrow = 108;
  static const int kEncodingVexRm_Lx_Bcst = 109;
  static const int kEncodingVexRm_VM = 110;
  static const int kEncodingVexRmi = 111;
  static const int kEncodingVexRmi_Wx = 112;
  static const int kEncodingVexRmi_Lx = 113;
  static const int kEncodingVexRvm = 114;
  static const int kEncodingVexRvm_Wx = 115;
  static const int kEncodingVexRvm_ZDX_Wx = 116;
  static const int kEncodingVexRvm_Lx = 117;
  static const int kEncodingVexRvm_Lx_KEvex = 118;
  static const int kEncodingVexRvm_Lx_2xK = 119;
  static const int kEncodingVexRvmr = 120;
  static const int kEncodingVexRvmr_Lx = 121;
  static const int kEncodingVexRvmi = 122;
  static const int kEncodingVexRvmi_KEvex = 123;
  static const int kEncodingVexRvmi_Lx = 124;
  static const int kEncodingVexRvmi_Lx_KEvex = 125;
  static const int kEncodingVexRmv = 126;
  static const int kEncodingVexRmv_Wx = 127;
  static const int kEncodingVexRmv_VM = 128;
  static const int kEncodingVexRmvRm_VM = 129;
  static const int kEncodingVexRmvi = 130;
  static const int kEncodingVexRmMr = 131;
  static const int kEncodingVexRmMr_Lx = 132;
  static const int kEncodingVexRvmRmv = 133;
  static const int kEncodingVexRvmRmi = 134;
  static const int kEncodingVexRvmRmi_Lx = 135;
  static const int kEncodingVexRvmRmvRmi = 136;
  static const int kEncodingVexRvmMr = 137;
  static const int kEncodingVexRvmMvr = 138;
  static const int kEncodingVexRvmMvr_Lx = 139;
  static const int kEncodingVexRvmVmi = 140;
  static const int kEncodingVexRvmVmi_Lx = 141;
  static const int kEncodingVexRvmVmi_Lx_MEvex = 142;
  static const int kEncodingVexVm = 143;
  static const int kEncodingVexVm_Wx = 144;
  static const int kEncodingVexVmi = 145;
  static const int kEncodingVexVmi_Lx = 146;
  static const int kEncodingVexVmi4_Wx = 147;
  static const int kEncodingVexVmi_Lx_MEvex = 148;
  static const int kEncodingVexRvrmRvmr = 149;
  static const int kEncodingVexRvrmRvmr_Lx = 150;
  static const int kEncodingVexRvrmiRvmri_Lx = 151;
  static const int kEncodingVexMovdMovq = 152;
  static const int kEncodingVexMovssMovsd = 153;
  static const int kEncodingFma4 = 154;
  static const int kEncodingFma4_Lx = 155;
  static const int kEncodingAmxCfg = 156;
  static const int kEncodingAmxR = 157;
  static const int kEncodingAmxRm = 158;
  static const int kEncodingAmxMr = 159;
  static const int kEncodingAmxRmv = 160;

  static const names = [
    'None',
    'X86Op',
    'X86Op_Mod11RM',
    'X86Op_Mod11RM_I8',
    'X86Op_xAddr',
    'X86Op_xAX',
    'X86Op_xDX_xAX',
    'X86Op_MemZAX',
    'X86I_xAX',
    'X86M',
    'X86M_NoMemSize',
    'X86M_NoSize',
    'X86M_GPB',
    'X86M_GPB_MulDiv',
    'X86M_Only',
    'X86M_Only_EDX_EAX',
    'X86M_Nop',
    'X86R_Native',
    'X86R_FromM',
    'X86R32_EDX_EAX',
    'X86Rm',
    'X86Rm_Raw66H',
    'X86Rm_NoSize',
    'X86Mr',
    'X86Mr_NoSize',
    'X86Arith',
    'X86Bswap',
    'X86Bt',
    'X86Call',
    'X86Cmpxchg',
    'X86Cmpxchg8b_16b',
    'X86Crc',
    'X86Enter',
    'X86Imul',
    'X86In',
    'X86Ins',
    'X86IncDec',
    'X86Int',
    'X86Jcc',
    'X86JecxzLoop',
    'X86Jmp',
    'X86JmpRel',
    'X86LcallLjmp',
    'X86Lea',
    'X86Mov',
    'X86Movabs',
    'X86MovsxMovzx',
    'X86MovntiMovdiri',
    'X86EnqcmdMovdir64b',
    'X86Out',
    'X86Outs',
    'X86Push',
    'X86Pushw',
    'X86Pop',
    'X86Ret',
    'X86Rot',
    'X86Set',
    'X86ShldShrd',
    'X86StrRm',
    'X86StrMr',
    'X86StrMm',
    'X86Test',
    'X86Xadd',
    'X86Xchg',
    'X86Fence',
    'X86Bndmov',
    'FpuOp',
    'FpuArith',
    'FpuCom',
    'FpuFldFst',
    'FpuM',
    'FpuR',
    'FpuRDef',
    'FpuStsw',
    'ExtRm',
    'ExtRm_XMM0',
    'ExtRm_ZDI',
    'ExtRm_P',
    'ExtRm_Wx',
    'ExtRm_Wx_GpqOnly',
    'ExtRmRi',
    'ExtRmRi_P',
    'ExtRmi',
    'ExtRmi_P',
    'ExtPextrw',
    'ExtExtract',
    'ExtMov',
    'ExtMovbe',
    'ExtMovd',
    'ExtMovq',
    'ExtExtrq',
    'ExtInsertq',
    'Ext3dNow',
    'VexOp',
    'VexOpMod',
    'VexKmov',
    'VexR_Wx',
    'VexM',
    'VexMr_Lx',
    'VexMr_VM',
    'VexMri',
    'VexMri_Lx',
    'VexMri_Vpextrw',
    'VexMvr_Wx',
    'VexRm',
    'VexRm_ZDI',
    'VexRm_Wx',
    'VexRm_Lx',
    'VexRm_Lx_Narrow',
    'VexRm_Lx_Bcst',
    'VexRm_VM',
    'VexRmi',
    'VexRmi_Wx',
    'VexRmi_Lx',
    'VexRvm',
    'VexRvm_Wx',
    'VexRvm_ZDX_Wx',
    'VexRvm_Lx',
    'VexRvm_Lx_KEvex',
    'VexRvm_Lx_2xK',
    'VexRvmr',
    'VexRvmr_Lx',
    'VexRvmi',
    'VexRvmi_KEvex',
    'VexRvmi_Lx',
    'VexRvmi_Lx_KEvex',
    'VexRmv',
    'VexRmv_Wx',
    'VexRmv_VM',
    'VexRmvRm_VM',
    'VexRmvi',
    'VexRmMr',
    'VexRmMr_Lx',
    'VexRvmRmv',
    'VexRvmRmi',
    'VexRvmRmi_Lx',
    'VexRvmRmvRmi',
    'VexRvmMr',
    'VexRvmMvr',
    'VexRvmMvr_Lx',
    'VexRvmVmi',
    'VexRvmVmi_Lx',
    'VexRvmVmi_Lx_MEvex',
    'VexVm',
    'VexVm_Wx',
    'VexVmi',
    'VexVmi_Lx',
    'VexVmi4_Wx',
    'VexVmi_Lx_MEvex',
    'VexRvrmRvmr',
    'VexRvrmRvmr_Lx',
    'VexRvrmiRvmri_Lx',
    'VexMovdMovq',
    'VexMovssMovsd',
    'Fma4',
    'Fma4_Lx',
    'AmxCfg',
    'AmxR',
    'AmxRm',
    'AmxMr',
    'AmxRmv',
  ];
}

/// `x86::InstDB::InstFlags`.
abstract final class X86InstDbFlags {
  static const int kNone = 0x00000000;
  static const int kFpu = 0x00000100;
  static const int kMmx = 0x00000200;
  static const int kVec = 0x00000400;
  static const int kFpuM16 = 0x00000800;
  static const int kFpuM32 = 0x00001000;
  static const int kFpuM64 = 0x00002000;
  static const int kFpuM80 = 0x00000800;
  static const int kRep = 0x00004000;
  static const int kRepIgnored = 0x00008000;
  static const int kLock = 0x00010000;
  static const int kXAcquire = 0x00020000;
  static const int kXRelease = 0x00040000;
  static const int kMib = 0x00080000;
  static const int kVsib = 0x00100000;
  static const int kTsib = 0x00200000;
  static const int kVex = 0x00400000;
  static const int kEvex = 0x00800000;
  static const int kPreferEvex = 0x01000000;
  static const int kEvexCompat = 0x02000000;
  static const int kEvexKReg = 0x04000000;
  static const int kEvexTwoOp = 0x08000000;
  static const int kEvexTransformable = 0x10000000;
  static const int kConsecutiveRegs = 0x20000000;

  static const byName = {
    'Fpu': kFpu,
    'Mmx': kMmx,
    'Vec': kVec,
    'FpuM16': kFpuM16,
    'FpuM32': kFpuM32,
    'FpuM64': kFpuM64,
    'FpuM80': kFpuM80,
    'Rep': kRep,
    'RepIgnored': kRepIgnored,
    'Lock': kLock,
    'XAcquire': kXAcquire,
    'XRelease': kXRelease,
    'Mib': kMib,
    'Vsib': kVsib,
    'Tsib': kTsib,
    'Vex': kVex,
    'Evex': kEvex,
    'PreferEvex': kPreferEvex,
    'EvexCompat': kEvexCompat,
    'EvexKReg': kEvexKReg,
    'EvexTwoOp': kEvexTwoOp,
    'EvexTransformable': kEvexTransformable,
    'ConsecutiveRegs': kConsecutiveRegs,
  };
}

/// `x86::InstDB::Avx512Flags`.
abstract final class X86Avx512Flags {
  static const int kNone = 0;
  static const int kK = 0x00000001;
  static const int kZ = 0x00000002;
  static const int kER = 0x00000004;
  static const int kSAE = 0x00000008;
  static const int kB16 = 0x00000010;
  static const int kB32 = 0x00000020;
  static const int kB64 = 0x00000040;
  static const int kImplicitZ = 0x00000100;

  static const byName = {
    'K': kK,
    'Z': kZ,
    'ER': kER,
    'SAE': kSAE,
    'B16': kB16,
    'B32': kB32,
    'B64': kB64,
    'ImplicitZ': kImplicitZ,
  };
}
