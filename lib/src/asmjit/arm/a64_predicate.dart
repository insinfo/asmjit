// Port of the `a64::Predicate` namespace (asmjit/arm/a64globals.h):
// immediates of AT, BTI, DMB/DSB, DC, IC, ISB, PRFM, PSB, TLBI, TSB, MSR
// (PState) and MRS/MSR system registers. Generated once from upstream by a
// script that evaluates the `encode()` values; names keep upstream spelling.

// ignore_for_file: constant_identifier_names

/// `a64::Predicate::AT`.
abstract final class A64AT {
  /// `encode()`.
  static int encode(int op1, int crn, int crm, int op2) =>
      (op1 << 11) | (crn << 7) | (crm << 3) | (op2 << 0);

  static const int kS1E1R = 0x3C0;
  static const int kS1E2R = 0x23C0;
  static const int kS1E3R = 0x33C0;
  static const int kS1E1W = 0x3C1;
  static const int kS1E2W = 0x23C1;
  static const int kS1E3W = 0x33C1;
  static const int kS1E0R = 0x3C2;
  static const int kS1E0W = 0x3C3;
  static const int kS12E1R = 0x23C4;
  static const int kS12E1W = 0x23C5;
  static const int kS12E0R = 0x23C6;
  static const int kS12E0W = 0x23C7;
  static const int kS1E1RP = 0x3C8;
  static const int kS1E1WP = 0x3C9;
}

/// `a64::Predicate::BTI`: Branch target identification targets.
abstract final class A64BTI {
  static const int kNone = 0x0;
  static const int kC = 0x1;
  static const int kJ = 0x2;
  static const int kJC = 0x3;
}

/// `a64::Predicate::DB`: Data barrier immediate values.
abstract final class A64DB {
  static const int kOSHLD = 0x1;
  static const int kOSHST = 0x2;
  static const int kOSH = 0x3;
  static const int kNSHLD = 0x5;
  static const int kNSHST = 0x6;
  static const int kNSH = 0x7;
  static const int kISHLD = 0x9;
  static const int kISHST = 0xA;
  static const int kISH = 0xB;
  static const int kLD = 0xD;
  static const int kST = 0xE;
  static const int kSY = 0xF;
}

/// `a64::Predicate::DC`: Data cache maintenance immediate values.
abstract final class A64DC {
  /// `encode()`.
  static int encode(int op1, int crn, int crm, int op2) =>
      (op1 << 11) | (crn << 7) | (crm << 3) | (op2 << 0);

  static const int kZVA = 0x1BA1;
  static const int kIVAC = 0x3B1;
  static const int kISW = 0x3B2;
  static const int kCVAC = 0x1BD1;
  static const int kCSW = 0x3D2;
  static const int kCVAU = 0x1BD9;
  static const int kCIVAC = 0x1BF1;
  static const int kCISW = 0x3F2;
  static const int kCVAP = 0x1BE1;
  static const int kCVADP = 0x1BE9;
  static const int kIGVAC = 0x3B3;
  static const int kIGSW = 0x3B4;
  static const int kCGSW = 0x3D4;
  static const int kCIGSW = 0x3F4;
  static const int kCGVAC = 0x1BD3;
  static const int kCGVAP = 0x1BE3;
  static const int kCGVADP = 0x1BEB;
  static const int kCIGVAC = 0x1BF3;
  static const int kGVA = 0x1BA3;
  static const int kIGDVAC = 0x3B5;
  static const int kIGDSW = 0x3B6;
  static const int kCGDSW = 0x3D6;
  static const int kCIGDSW = 0x3F6;
  static const int kCGDVAC = 0x1BD5;
  static const int kCGDVAP = 0x1BE5;
  static const int kCGDVADP = 0x1BED;
  static const int kCIGDVAC = 0x1BF5;
  static const int kGZVA = 0x1BA4;
}

/// `a64::Predicate::IC`: Instruction cache maintenance immediate values.
abstract final class A64IC {
  /// `encode()`.
  static int encode(int op1, int crn, int crm, int op2) =>
      (op1 << 11) | (crn << 7) | (crm << 3) | (op2 << 0);

  static const int kIALLUIS = 0x388;
  static const int kIALLU = 0x3A8;
  static const int kIVAU = 0x1BA9;
}

/// `a64::Predicate::ISB`: Instruction-fetch barrier immediate values.
abstract final class A64ISB {
  static const int kSY = 0xF;
}

/// `a64::Predicate::PRFOp`: Prefetch immediate values.
abstract final class A64PRFOp {
  static const int kPLDL1KEEP = 0x0;
  static const int kPLDL1STRM = 0x1;
  static const int kPLDL2KEEP = 0x2;
  static const int kPLDL2STRM = 0x3;
  static const int kPLDL3KEEP = 0x4;
  static const int kPLDL3STRM = 0x5;
  static const int kPLIL1KEEP = 0x8;
  static const int kPLIL1STRM = 0x9;
  static const int kPLIL2KEEP = 0xA;
  static const int kPLIL2STRM = 0xB;
  static const int kPLIL3KEEP = 0xC;
  static const int kPLIL3STRM = 0xD;
  static const int kPSTL1KEEP = 0x10;
  static const int kPSTL1STRM = 0x11;
  static const int kPSTL2KEEP = 0x12;
  static const int kPSTL2STRM = 0x13;
  static const int kPSTL3KEEP = 0x14;
  static const int kPSTL3STRM = 0x15;
}

/// `a64::Predicate::PSB`: PSB immediate values.
abstract final class A64PSB {
  static const int kCSYNC = 0x11;
}

/// `a64::Predicate::TLBI`.
abstract final class A64TLBI {
  /// `encode()`.
  static int encode(int op1, int crn, int crm, int op2) =>
      (op1 << 11) | (crn << 7) | (crm << 3) | (op2 << 0);

  static const int kIPAS2E1IS = 0x2401;
  static const int kIPAS2LE1IS = 0x2405;
  static const int kVMALLE1IS = 0x418;
  static const int kALLE2IS = 0x2418;
  static const int kALLE3IS = 0x3418;
  static const int kVAE1IS = 0x419;
  static const int kVAE2IS = 0x2419;
  static const int kVAE3IS = 0x3419;
  static const int kASIDE1IS = 0x41A;
  static const int kVAAE1IS = 0x41B;
  static const int kALLE1IS = 0x241C;
  static const int kVALE1IS = 0x41D;
  static const int kVALE2IS = 0x241D;
  static const int kVALE3IS = 0x341D;
  static const int kVMALLS12E1IS = 0x241E;
  static const int kVAALE1IS = 0x41F;
  static const int kIPAS2E1 = 0x2421;
  static const int kIPAS2LE1 = 0x2425;
  static const int kVMALLE1 = 0x438;
  static const int kALLE2 = 0x2438;
  static const int kALLE3 = 0x3438;
  static const int kVAE1 = 0x439;
  static const int kVAE2 = 0x2439;
  static const int kVAE3 = 0x3439;
  static const int kASIDE1 = 0x43A;
  static const int kVAAE1 = 0x43B;
  static const int kALLE1 = 0x243C;
  static const int kVALE1 = 0x43D;
  static const int kVALE2 = 0x243D;
  static const int kVALE3 = 0x343D;
  static const int kVMALLS12E1 = 0x243E;
  static const int kVAALE1 = 0x43F;
  static const int kVMALLE1OS = 0x408;
  static const int kVAE1OS = 0x409;
  static const int kASIDE1OS = 0x40A;
  static const int kVAAE1OS = 0x40B;
  static const int kVALE1OS = 0x40D;
  static const int kVAALE1OS = 0x40F;
  static const int kIPAS2E1OS = 0x2420;
  static const int kIPAS2LE1OS = 0x2424;
  static const int kVAE2OS = 0x2409;
  static const int kVALE2OS = 0x240D;
  static const int kVMALLS12E1OS = 0x240E;
  static const int kVAE3OS = 0x3409;
  static const int kVALE3OS = 0x340D;
  static const int kALLE2OS = 0x2408;
  static const int kALLE1OS = 0x240C;
  static const int kALLE3OS = 0x3408;
  static const int kRVAE1 = 0x431;
  static const int kRVAAE1 = 0x433;
  static const int kRVALE1 = 0x435;
  static const int kRVAALE1 = 0x437;
  static const int kRVAE1IS = 0x411;
  static const int kRVAAE1IS = 0x413;
  static const int kRVALE1IS = 0x415;
  static const int kRVAALE1IS = 0x417;
  static const int kRVAE1OS = 0x429;
  static const int kRVAAE1OS = 0x42B;
  static const int kRVALE1OS = 0x42D;
  static const int kRVAALE1OS = 0x42F;
  static const int kRIPAS2E1IS = 0x2402;
  static const int kRIPAS2LE1IS = 0x2406;
  static const int kRIPAS2E1 = 0x2422;
  static const int kRIPAS2LE1 = 0x2426;
  static const int kRIPAS2E1OS = 0x2423;
  static const int kRIPAS2LE1OS = 0x2427;
  static const int kRVAE2 = 0x2431;
  static const int kRVALE2 = 0x2435;
  static const int kRVAE2IS = 0x2411;
  static const int kRVALE2IS = 0x2415;
  static const int kRVAE2OS = 0x2429;
  static const int kRVALE2OS = 0x242D;
  static const int kRVAE3 = 0x3431;
  static const int kRVALE3 = 0x3435;
  static const int kRVAE3IS = 0x3411;
  static const int kRVALE3IS = 0x3415;
  static const int kRVAE3OS = 0x3429;
  static const int kRVALE3OS = 0x342D;
}

/// `a64::Predicate::TSB`: Trace synchronization immediate values.
abstract final class A64TSB {
  static const int kCSYNC = 0x0;
}

/// `a64::Predicate::PState`: Encodes a pstate from `op0` and `op1`.
abstract final class A64PState {
  /// `encode()`.
  static int encode(int op0, int op1) => (op0 << 3) | (op1 << 0);

  static const int kSPSel = 0x5;
  static const int kDAIFSet = 0x1E;
  static const int kDAIFClr = 0x1F;
  static const int kPAN = 0x4;
  static const int kUAO = 0x3;
  static const int kDIT = 0x1A;
  static const int kSSBS = 0x19;
  static const int kTCO = 0x1C;
}

/// `a64::Predicate::SysReg`: System register fields.
abstract final class A64SysReg {
  /// `encode()`.
  static int encode(int op0, int op1, int crn, int crm, int op2) =>
      (op0 << 14) | (op1 << 11) | (crn << 7) | (crm << 3) | (op2 << 0);

  static const int kACTLR_EL1 = 0xC081;
  static const int kACTLR_EL2 = 0xE081;
  static const int kACTLR_EL3 = 0xF081;
  static const int kAFSR0_EL1 = 0xC288;
  static const int kAFSR0_EL12 = 0xEA88;
  static const int kAFSR0_EL2 = 0xE288;
  static const int kAFSR0_EL3 = 0xF288;
  static const int kAFSR1_EL1 = 0xC289;
  static const int kAFSR1_EL12 = 0xEA89;
  static const int kAFSR1_EL2 = 0xE289;
  static const int kAFSR1_EL3 = 0xF289;
  static const int kAIDR_EL1 = 0xC807;
  static const int kAMAIR_EL1 = 0xC518;
  static const int kAMAIR_EL12 = 0xED18;
  static const int kAMAIR_EL2 = 0xE518;
  static const int kAMAIR_EL3 = 0xF518;
  static const int kAMCFGR_EL0 = 0xDE91;
  static const int kAMCGCR_EL0 = 0xDE92;
  static const int kAMCNTENCLR0_EL0 = 0xDE94;
  static const int kAMCNTENCLR1_EL0 = 0xDE98;
  static const int kAMCNTENSET0_EL0 = 0xDE95;
  static const int kAMCNTENSET1_EL0 = 0xDE99;
  static const int kAMCR_EL0 = 0xDE90;
  static const int kAMEVCNTR00_EL0 = 0xDEA0;
  static const int kAMEVCNTR01_EL0 = 0xDEA1;
  static const int kAMEVCNTR02_EL0 = 0xDEA2;
  static const int kAMEVCNTR03_EL0 = 0xDEA3;
  static const int kAMEVCNTR10_EL0 = 0xDEE0;
  static const int kAMEVCNTR110_EL0 = 0xDEEA;
  static const int kAMEVCNTR111_EL0 = 0xDEEB;
  static const int kAMEVCNTR112_EL0 = 0xDEEC;
  static const int kAMEVCNTR113_EL0 = 0xDEED;
  static const int kAMEVCNTR114_EL0 = 0xDEEE;
  static const int kAMEVCNTR115_EL0 = 0xDEEF;
  static const int kAMEVCNTR11_EL0 = 0xDEE1;
  static const int kAMEVCNTR12_EL0 = 0xDEE2;
  static const int kAMEVCNTR13_EL0 = 0xDEE3;
  static const int kAMEVCNTR14_EL0 = 0xDEE4;
  static const int kAMEVCNTR15_EL0 = 0xDEE5;
  static const int kAMEVCNTR16_EL0 = 0xDEE6;
  static const int kAMEVCNTR17_EL0 = 0xDEE7;
  static const int kAMEVCNTR18_EL0 = 0xDEE8;
  static const int kAMEVCNTR19_EL0 = 0xDEE9;
  static const int kAMEVTYPER00_EL0 = 0xDEB0;
  static const int kAMEVTYPER01_EL0 = 0xDEB1;
  static const int kAMEVTYPER02_EL0 = 0xDEB2;
  static const int kAMEVTYPER03_EL0 = 0xDEB3;
  static const int kAMEVTYPER10_EL0 = 0xDEF0;
  static const int kAMEVTYPER110_EL0 = 0xDEFA;
  static const int kAMEVTYPER111_EL0 = 0xDEFB;
  static const int kAMEVTYPER112_EL0 = 0xDEFC;
  static const int kAMEVTYPER113_EL0 = 0xDEFD;
  static const int kAMEVTYPER114_EL0 = 0xDEFE;
  static const int kAMEVTYPER115_EL0 = 0xDEFF;
  static const int kAMEVTYPER11_EL0 = 0xDEF1;
  static const int kAMEVTYPER12_EL0 = 0xDEF2;
  static const int kAMEVTYPER13_EL0 = 0xDEF3;
  static const int kAMEVTYPER14_EL0 = 0xDEF4;
  static const int kAMEVTYPER15_EL0 = 0xDEF5;
  static const int kAMEVTYPER16_EL0 = 0xDEF6;
  static const int kAMEVTYPER17_EL0 = 0xDEF7;
  static const int kAMEVTYPER18_EL0 = 0xDEF8;
  static const int kAMEVTYPER19_EL0 = 0xDEF9;
  static const int kAMUSERENR_EL0 = 0xDE93;
  static const int kAPDAKeyHi_EL1 = 0xC111;
  static const int kAPDAKeyLo_EL1 = 0xC110;
  static const int kAPDBKeyHi_EL1 = 0xC113;
  static const int kAPDBKeyLo_EL1 = 0xC112;
  static const int kAPGAKeyHi_EL1 = 0xC119;
  static const int kAPGAKeyLo_EL1 = 0xC118;
  static const int kAPIAKeyHi_EL1 = 0xC109;
  static const int kAPIAKeyLo_EL1 = 0xC108;
  static const int kAPIBKeyHi_EL1 = 0xC10B;
  static const int kAPIBKeyLo_EL1 = 0xC10A;
  static const int kCCSIDR2_EL1 = 0xC802;
  static const int kCCSIDR_EL1 = 0xC800;
  static const int kCLIDR_EL1 = 0xC801;
  static const int kCNTFRQ_EL0 = 0xDF00;
  static const int kCNTHCTL_EL2 = 0xE708;
  static const int kCNTHPS_CTL_EL2 = 0xE729;
  static const int kCNTHPS_CVAL_EL2 = 0xE72A;
  static const int kCNTHPS_TVAL_EL2 = 0xE728;
  static const int kCNTHP_CTL_EL2 = 0xE711;
  static const int kCNTHP_CVAL_EL2 = 0xE712;
  static const int kCNTHP_TVAL_EL2 = 0xE710;
  static const int kCNTHVS_CTL_EL2 = 0xE721;
  static const int kCNTHVS_CVAL_EL2 = 0xE722;
  static const int kCNTHVS_TVAL_EL2 = 0xE720;
  static const int kCNTHV_CTL_EL2 = 0xE719;
  static const int kCNTHV_CVAL_EL2 = 0xE71A;
  static const int kCNTHV_TVAL_EL2 = 0xE718;
  static const int kCNTISCALE_EL2 = 0xE705;
  static const int kCNTKCTL_EL1 = 0xC708;
  static const int kCNTKCTL_EL12 = 0xEF08;
  static const int kCNTPCTSS_EL0 = 0xDF05;
  static const int kCNTPCT_EL0 = 0xDF01;
  static const int kCNTPOFF_EL2 = 0xE706;
  static const int kCNTPS_CTL_EL1 = 0xFF11;
  static const int kCNTPS_CVAL_EL1 = 0xFF12;
  static const int kCNTPS_TVAL_EL1 = 0xFF10;
  static const int kCNTP_CTL_EL0 = 0xDF11;
  static const int kCNTP_CTL_EL02 = 0xEF11;
  static const int kCNTP_CVAL_EL0 = 0xDF12;
  static const int kCNTP_CVAL_EL02 = 0xEF12;
  static const int kCNTP_TVAL_EL0 = 0xDF10;
  static const int kCNTP_TVAL_EL02 = 0xEF10;
  static const int kCNTSCALE_EL2 = 0xE704;
  static const int kCNTVCTSS_EL0 = 0xDF06;
  static const int kCNTVCT_EL0 = 0xDF02;
  static const int kCNTVFRQ_EL2 = 0xE707;
  static const int kCNTVOFF_EL2 = 0xE703;
  static const int kCNTV_CTL_EL0 = 0xDF19;
  static const int kCNTV_CTL_EL02 = 0xEF19;
  static const int kCNTV_CVAL_EL0 = 0xDF1A;
  static const int kCNTV_CVAL_EL02 = 0xEF1A;
  static const int kCNTV_TVAL_EL0 = 0xDF18;
  static const int kCNTV_TVAL_EL02 = 0xEF18;
  static const int kCONTEXTIDR_EL1 = 0xC681;
  static const int kCONTEXTIDR_EL12 = 0xEE81;
  static const int kCONTEXTIDR_EL2 = 0xE681;
  static const int kCPACR_EL1 = 0xC082;
  static const int kCPACR_EL12 = 0xE882;
  static const int kCPM_IOACC_CTL_EL3 = 0xFF90;
  static const int kCPTR_EL2 = 0xE08A;
  static const int kCPTR_EL3 = 0xF08A;
  static const int kCSSELR_EL1 = 0xD000;
  static const int kCTR_EL0 = 0xD801;
  static const int kCurrentEL = 0xC212;
  static const int kDACR32_EL2 = 0xE180;
  static const int kDAIF = 0xDA11;
  static const int kDBGAUTHSTATUS_EL1 = 0x83F6;
  static const int kDBGBCR0_EL1 = 0x8005;
  static const int kDBGBCR10_EL1 = 0x8055;
  static const int kDBGBCR11_EL1 = 0x805D;
  static const int kDBGBCR12_EL1 = 0x8065;
  static const int kDBGBCR13_EL1 = 0x806D;
  static const int kDBGBCR14_EL1 = 0x8075;
  static const int kDBGBCR15_EL1 = 0x807D;
  static const int kDBGBCR1_EL1 = 0x800D;
  static const int kDBGBCR2_EL1 = 0x8015;
  static const int kDBGBCR3_EL1 = 0x801D;
  static const int kDBGBCR4_EL1 = 0x8025;
  static const int kDBGBCR5_EL1 = 0x802D;
  static const int kDBGBCR6_EL1 = 0x8035;
  static const int kDBGBCR7_EL1 = 0x803D;
  static const int kDBGBCR8_EL1 = 0x8045;
  static const int kDBGBCR9_EL1 = 0x804D;
  static const int kDBGBVR0_EL1 = 0x8004;
  static const int kDBGBVR10_EL1 = 0x8054;
  static const int kDBGBVR11_EL1 = 0x805C;
  static const int kDBGBVR12_EL1 = 0x8064;
  static const int kDBGBVR13_EL1 = 0x806C;
  static const int kDBGBVR14_EL1 = 0x8074;
  static const int kDBGBVR15_EL1 = 0x807C;
  static const int kDBGBVR1_EL1 = 0x800C;
  static const int kDBGBVR2_EL1 = 0x8014;
  static const int kDBGBVR3_EL1 = 0x801C;
  static const int kDBGBVR4_EL1 = 0x8024;
  static const int kDBGBVR5_EL1 = 0x802C;
  static const int kDBGBVR6_EL1 = 0x8034;
  static const int kDBGBVR7_EL1 = 0x803C;
  static const int kDBGBVR8_EL1 = 0x8044;
  static const int kDBGBVR9_EL1 = 0x804C;
  static const int kDBGCLAIMCLR_EL1 = 0x83CE;
  static const int kDBGCLAIMSET_EL1 = 0x83C6;
  static const int kDBGDTRRX_EL0 = 0x9828;
  static const int kDBGDTRTX_EL0 = 0x9828;
  static const int kDBGDTR_EL0 = 0x9820;
  static const int kDBGPRCR_EL1 = 0x80A4;
  static const int kDBGVCR32_EL2 = 0xA038;
  static const int kDBGWCR0_EL1 = 0x8007;
  static const int kDBGWCR10_EL1 = 0x8057;
  static const int kDBGWCR11_EL1 = 0x805F;
  static const int kDBGWCR12_EL1 = 0x8067;
  static const int kDBGWCR13_EL1 = 0x806F;
  static const int kDBGWCR14_EL1 = 0x8077;
  static const int kDBGWCR15_EL1 = 0x807F;
  static const int kDBGWCR1_EL1 = 0x800F;
  static const int kDBGWCR2_EL1 = 0x8017;
  static const int kDBGWCR3_EL1 = 0x801F;
  static const int kDBGWCR4_EL1 = 0x8027;
  static const int kDBGWCR5_EL1 = 0x802F;
  static const int kDBGWCR6_EL1 = 0x8037;
  static const int kDBGWCR7_EL1 = 0x803F;
  static const int kDBGWCR8_EL1 = 0x8047;
  static const int kDBGWCR9_EL1 = 0x804F;
  static const int kDBGWVR0_EL1 = 0x8006;
  static const int kDBGWVR10_EL1 = 0x8056;
  static const int kDBGWVR11_EL1 = 0x805E;
  static const int kDBGWVR12_EL1 = 0x8066;
  static const int kDBGWVR13_EL1 = 0x806E;
  static const int kDBGWVR14_EL1 = 0x8076;
  static const int kDBGWVR15_EL1 = 0x807E;
  static const int kDBGWVR1_EL1 = 0x800E;
  static const int kDBGWVR2_EL1 = 0x8016;
  static const int kDBGWVR3_EL1 = 0x801E;
  static const int kDBGWVR4_EL1 = 0x8026;
  static const int kDBGWVR5_EL1 = 0x802E;
  static const int kDBGWVR6_EL1 = 0x8036;
  static const int kDBGWVR7_EL1 = 0x803E;
  static const int kDBGWVR8_EL1 = 0x8046;
  static const int kDBGWVR9_EL1 = 0x804E;
  static const int kDCZID_EL0 = 0xD807;
  static const int kDISR_EL1 = 0xC609;
  static const int kDIT = 0xDA15;
  static const int kDLR_EL0 = 0xDA29;
  static const int kDSPSR_EL0 = 0xDA28;
  static const int kELR_EL1 = 0xC201;
  static const int kELR_EL12 = 0xEA01;
  static const int kELR_EL2 = 0xE201;
  static const int kELR_EL3 = 0xF201;
  static const int kERRIDR_EL1 = 0xC298;
  static const int kERRSELR_EL1 = 0xC299;
  static const int kERXADDR_EL1 = 0xC2A3;
  static const int kERXCTLR_EL1 = 0xC2A1;
  static const int kERXFR_EL1 = 0xC2A0;
  static const int kERXMISC0_EL1 = 0xC2A8;
  static const int kERXMISC1_EL1 = 0xC2A9;
  static const int kERXMISC2_EL1 = 0xC2AA;
  static const int kERXMISC3_EL1 = 0xC2AB;
  static const int kERXPFGCDN_EL1 = 0xC2A6;
  static const int kERXPFGCTL_EL1 = 0xC2A5;
  static const int kERXPFGF_EL1 = 0xC2A4;
  static const int kERXSTATUS_EL1 = 0xC2A2;
  static const int kESR_EL1 = 0xC290;
  static const int kESR_EL12 = 0xEA90;
  static const int kESR_EL2 = 0xE290;
  static const int kESR_EL3 = 0xF290;
  static const int kFAR_EL1 = 0xC300;
  static const int kFAR_EL12 = 0xEB00;
  static const int kFAR_EL2 = 0xE300;
  static const int kFAR_EL3 = 0xF300;
  static const int kFPCR = 0xDA20;
  static const int kFPEXC32_EL2 = 0xE298;
  static const int kFPSR = 0xDA21;
  static const int kGCR_EL1 = 0xC086;
  static const int kGMID_EL1 = 0xC804;
  static const int kHACR_EL2 = 0xE08F;
  static const int kHCR_EL2 = 0xE088;
  static const int kHDFGRTR_EL2 = 0xE18C;
  static const int kHDFGWTR_EL2 = 0xE18D;
  static const int kHFGITR_EL2 = 0xE08E;
  static const int kHFGRTR_EL2 = 0xE08C;
  static const int kHFGWTR_EL2 = 0xE08D;
  static const int kHPFAR_EL2 = 0xE304;
  static const int kHSTR_EL2 = 0xE08B;
  static const int kICC_AP0R0_EL1 = 0xC644;
  static const int kICC_AP0R1_EL1 = 0xC645;
  static const int kICC_AP0R2_EL1 = 0xC646;
  static const int kICC_AP0R3_EL1 = 0xC647;
  static const int kICC_AP1R0_EL1 = 0xC648;
  static const int kICC_AP1R1_EL1 = 0xC649;
  static const int kICC_AP1R2_EL1 = 0xC64A;
  static const int kICC_AP1R3_EL1 = 0xC64B;
  static const int kICC_ASGI1R_EL1 = 0xC65E;
  static const int kICC_BPR0_EL1 = 0xC643;
  static const int kICC_BPR1_EL1 = 0xC663;
  static const int kICC_CTLR_EL1 = 0xC664;
  static const int kICC_CTLR_EL3 = 0xF664;
  static const int kICC_DIR_EL1 = 0xC659;
  static const int kICC_EOIR0_EL1 = 0xC641;
  static const int kICC_EOIR1_EL1 = 0xC661;
  static const int kICC_HPPIR0_EL1 = 0xC642;
  static const int kICC_HPPIR1_EL1 = 0xC662;
  static const int kICC_IAR0_EL1 = 0xC640;
  static const int kICC_IAR1_EL1 = 0xC660;
  static const int kICC_IGRPEN0_EL1 = 0xC666;
  static const int kICC_IGRPEN1_EL1 = 0xC667;
  static const int kICC_IGRPEN1_EL3 = 0xF667;
  static const int kICC_PMR_EL1 = 0xC230;
  static const int kICC_RPR_EL1 = 0xC65B;
  static const int kICC_SGI0R_EL1 = 0xC65F;
  static const int kICC_SGI1R_EL1 = 0xC65D;
  static const int kICC_SRE_EL1 = 0xC665;
  static const int kICC_SRE_EL2 = 0xE64D;
  static const int kICC_SRE_EL3 = 0xF665;
  static const int kICH_AP0R0_EL2 = 0xE640;
  static const int kICH_AP0R1_EL2 = 0xE641;
  static const int kICH_AP0R2_EL2 = 0xE642;
  static const int kICH_AP0R3_EL2 = 0xE643;
  static const int kICH_AP1R0_EL2 = 0xE648;
  static const int kICH_AP1R1_EL2 = 0xE649;
  static const int kICH_AP1R2_EL2 = 0xE64A;
  static const int kICH_AP1R3_EL2 = 0xE64B;
  static const int kICH_EISR_EL2 = 0xE65B;
  static const int kICH_ELRSR_EL2 = 0xE65D;
  static const int kICH_HCR_EL2 = 0xE658;
  static const int kICH_LR0_EL2 = 0xE660;
  static const int kICH_LR10_EL2 = 0xE66A;
  static const int kICH_LR11_EL2 = 0xE66B;
  static const int kICH_LR12_EL2 = 0xE66C;
  static const int kICH_LR13_EL2 = 0xE66D;
  static const int kICH_LR14_EL2 = 0xE66E;
  static const int kICH_LR15_EL2 = 0xE66F;
  static const int kICH_LR1_EL2 = 0xE661;
  static const int kICH_LR2_EL2 = 0xE662;
  static const int kICH_LR3_EL2 = 0xE663;
  static const int kICH_LR4_EL2 = 0xE664;
  static const int kICH_LR5_EL2 = 0xE665;
  static const int kICH_LR6_EL2 = 0xE666;
  static const int kICH_LR7_EL2 = 0xE667;
  static const int kICH_LR8_EL2 = 0xE668;
  static const int kICH_LR9_EL2 = 0xE669;
  static const int kICH_MISR_EL2 = 0xE65A;
  static const int kICH_VMCR_EL2 = 0xE65F;
  static const int kICH_VTR_EL2 = 0xE659;
  static const int kID_AA64AFR0_EL1 = 0xC02C;
  static const int kID_AA64AFR1_EL1 = 0xC02D;
  static const int kID_AA64DFR0_EL1 = 0xC028;
  static const int kID_AA64DFR1_EL1 = 0xC029;
  static const int kID_AA64ISAR0_EL1 = 0xC030;
  static const int kID_AA64ISAR1_EL1 = 0xC031;
  static const int kID_AA64ISAR2_EL1 = 0xC032;
  static const int kID_AA64MMFR0_EL1 = 0xC038;
  static const int kID_AA64MMFR1_EL1 = 0xC039;
  static const int kID_AA64MMFR2_EL1 = 0xC03A;
  static const int kID_AA64MMFR3_EL1 = 0xC03B;
  static const int kID_AA64MMFR4_EL1 = 0xC03C;
  static const int kID_AA64PFR0_EL1 = 0xC020;
  static const int kID_AA64PFR1_EL1 = 0xC021;
  static const int kID_AA64ZFR0_EL1 = 0xC024;
  static const int kID_AFR0_EL1 = 0xC00B;
  static const int kID_DFR0_EL1 = 0xC00A;
  static const int kID_ISAR0_EL1 = 0xC010;
  static const int kID_ISAR1_EL1 = 0xC011;
  static const int kID_ISAR2_EL1 = 0xC012;
  static const int kID_ISAR3_EL1 = 0xC013;
  static const int kID_ISAR4_EL1 = 0xC014;
  static const int kID_ISAR5_EL1 = 0xC015;
  static const int kID_ISAR6_EL1 = 0xC017;
  static const int kID_MMFR0_EL1 = 0xC00C;
  static const int kID_MMFR1_EL1 = 0xC00D;
  static const int kID_MMFR2_EL1 = 0xC00E;
  static const int kID_MMFR3_EL1 = 0xC00F;
  static const int kID_MMFR4_EL1 = 0xC016;
  static const int kID_MMFR5_EL1 = 0xC01E;
  static const int kID_PFR0_EL1 = 0xC008;
  static const int kID_PFR1_EL1 = 0xC009;
  static const int kID_PFR2_EL1 = 0xC01C;
  static const int kIFSR32_EL2 = 0xE281;
  static const int kISR_EL1 = 0xC608;
  static const int kLORC_EL1 = 0xC523;
  static const int kLOREA_EL1 = 0xC521;
  static const int kLORID_EL1 = 0xC527;
  static const int kLORN_EL1 = 0xC522;
  static const int kLORSA_EL1 = 0xC520;
  static const int kMAIR_EL1 = 0xC510;
  static const int kMAIR_EL12 = 0xED10;
  static const int kMAIR_EL2 = 0xE510;
  static const int kMAIR_EL3 = 0xF510;
  static const int kMDCCINT_EL1 = 0x8010;
  static const int kMDCCSR_EL0 = 0x9808;
  static const int kMDCR_EL2 = 0xE089;
  static const int kMDCR_EL3 = 0xF099;
  static const int kMDRAR_EL1 = 0x8080;
  static const int kMDSCR_EL1 = 0x8012;
  static const int kMIDR_EL1 = 0xC000;
  static const int kMPAM0_EL1 = 0xC529;
  static const int kMPAM1_EL1 = 0xC528;
  static const int kMPAM1_EL12 = 0xED28;
  static const int kMPAM2_EL2 = 0xE528;
  static const int kMPAM3_EL3 = 0xF528;
  static const int kMPAMHCR_EL2 = 0xE520;
  static const int kMPAMIDR_EL1 = 0xC524;
  static const int kMPAMVPM0_EL2 = 0xE530;
  static const int kMPAMVPM1_EL2 = 0xE531;
  static const int kMPAMVPM2_EL2 = 0xE532;
  static const int kMPAMVPM3_EL2 = 0xE533;
  static const int kMPAMVPM4_EL2 = 0xE534;
  static const int kMPAMVPM5_EL2 = 0xE535;
  static const int kMPAMVPM6_EL2 = 0xE536;
  static const int kMPAMVPM7_EL2 = 0xE537;
  static const int kMPAMVPMV_EL2 = 0xE521;
  static const int kMPIDR_EL1 = 0xC005;
  static const int kMVFR0_EL1 = 0xC018;
  static const int kMVFR1_EL1 = 0xC019;
  static const int kMVFR2_EL1 = 0xC01A;
  static const int kNZCV = 0xDA10;
  static const int kOSDLR_EL1 = 0x809C;
  static const int kOSDTRRX_EL1 = 0x8002;
  static const int kOSDTRTX_EL1 = 0x801A;
  static const int kOSECCR_EL1 = 0x8032;
  static const int kOSLAR_EL1 = 0x8084;
  static const int kOSLSR_EL1 = 0x808C;
  static const int kPAN = 0xC213;
  static const int kPAR_EL1 = 0xC3A0;
  static const int kPMBIDR_EL1 = 0xC4D7;
  static const int kPMBLIMITR_EL1 = 0xC4D0;
  static const int kPMBPTR_EL1 = 0xC4D1;
  static const int kPMBSR_EL1 = 0xC4D3;
  static const int kPMCCFILTR_EL0 = 0xDF7F;
  static const int kPMCCNTR_EL0 = 0xDCE8;
  static const int kPMCEID0_EL0 = 0xDCE6;
  static const int kPMCEID1_EL0 = 0xDCE7;
  static const int kPMCNTENCLR_EL0 = 0xDCE2;
  static const int kPMCNTENSET_EL0 = 0xDCE1;
  static const int kPMCR_EL0 = 0xDCE0;
  static const int kPMEVCNTR0_EL0 = 0xDF40;
  static const int kPMEVCNTR10_EL0 = 0xDF4A;
  static const int kPMEVCNTR11_EL0 = 0xDF4B;
  static const int kPMEVCNTR12_EL0 = 0xDF4C;
  static const int kPMEVCNTR13_EL0 = 0xDF4D;
  static const int kPMEVCNTR14_EL0 = 0xDF4E;
  static const int kPMEVCNTR15_EL0 = 0xDF4F;
  static const int kPMEVCNTR16_EL0 = 0xDF50;
  static const int kPMEVCNTR17_EL0 = 0xDF51;
  static const int kPMEVCNTR18_EL0 = 0xDF52;
  static const int kPMEVCNTR19_EL0 = 0xDF53;
  static const int kPMEVCNTR1_EL0 = 0xDF41;
  static const int kPMEVCNTR20_EL0 = 0xDF54;
  static const int kPMEVCNTR21_EL0 = 0xDF55;
  static const int kPMEVCNTR22_EL0 = 0xDF56;
  static const int kPMEVCNTR23_EL0 = 0xDF57;
  static const int kPMEVCNTR24_EL0 = 0xDF58;
  static const int kPMEVCNTR25_EL0 = 0xDF59;
  static const int kPMEVCNTR26_EL0 = 0xDF5A;
  static const int kPMEVCNTR27_EL0 = 0xDF5B;
  static const int kPMEVCNTR28_EL0 = 0xDF5C;
  static const int kPMEVCNTR29_EL0 = 0xDF5D;
  static const int kPMEVCNTR2_EL0 = 0xDF42;
  static const int kPMEVCNTR30_EL0 = 0xDF5E;
  static const int kPMEVCNTR3_EL0 = 0xDF43;
  static const int kPMEVCNTR4_EL0 = 0xDF44;
  static const int kPMEVCNTR5_EL0 = 0xDF45;
  static const int kPMEVCNTR6_EL0 = 0xDF46;
  static const int kPMEVCNTR7_EL0 = 0xDF47;
  static const int kPMEVCNTR8_EL0 = 0xDF48;
  static const int kPMEVCNTR9_EL0 = 0xDF49;
  static const int kPMEVTYPER0_EL0 = 0xDF60;
  static const int kPMEVTYPER10_EL0 = 0xDF6A;
  static const int kPMEVTYPER11_EL0 = 0xDF6B;
  static const int kPMEVTYPER12_EL0 = 0xDF6C;
  static const int kPMEVTYPER13_EL0 = 0xDF6D;
  static const int kPMEVTYPER14_EL0 = 0xDF6E;
  static const int kPMEVTYPER15_EL0 = 0xDF6F;
  static const int kPMEVTYPER16_EL0 = 0xDF70;
  static const int kPMEVTYPER17_EL0 = 0xDF71;
  static const int kPMEVTYPER18_EL0 = 0xDF72;
  static const int kPMEVTYPER19_EL0 = 0xDF73;
  static const int kPMEVTYPER1_EL0 = 0xDF61;
  static const int kPMEVTYPER20_EL0 = 0xDF74;
  static const int kPMEVTYPER21_EL0 = 0xDF75;
  static const int kPMEVTYPER22_EL0 = 0xDF76;
  static const int kPMEVTYPER23_EL0 = 0xDF77;
  static const int kPMEVTYPER24_EL0 = 0xDF78;
  static const int kPMEVTYPER25_EL0 = 0xDF79;
  static const int kPMEVTYPER26_EL0 = 0xDF7A;
  static const int kPMEVTYPER27_EL0 = 0xDF7B;
  static const int kPMEVTYPER28_EL0 = 0xDF7C;
  static const int kPMEVTYPER29_EL0 = 0xDF7D;
  static const int kPMEVTYPER2_EL0 = 0xDF62;
  static const int kPMEVTYPER30_EL0 = 0xDF7E;
  static const int kPMEVTYPER3_EL0 = 0xDF63;
  static const int kPMEVTYPER4_EL0 = 0xDF64;
  static const int kPMEVTYPER5_EL0 = 0xDF65;
  static const int kPMEVTYPER6_EL0 = 0xDF66;
  static const int kPMEVTYPER7_EL0 = 0xDF67;
  static const int kPMEVTYPER8_EL0 = 0xDF68;
  static const int kPMEVTYPER9_EL0 = 0xDF69;
  static const int kPMINTENCLR_EL1 = 0xC4F2;
  static const int kPMINTENSET_EL1 = 0xC4F1;
  static const int kPMMIR_EL1 = 0xC4F6;
  static const int kPMOVSCLR_EL0 = 0xDCE3;
  static const int kPMOVSSET_EL0 = 0xDCF3;
  static const int kPMSCR_EL1 = 0xC4C8;
  static const int kPMSCR_EL12 = 0xECC8;
  static const int kPMSCR_EL2 = 0xE4C8;
  static const int kPMSELR_EL0 = 0xDCE5;
  static const int kPMSEVFR_EL1 = 0xC4CD;
  static const int kPMSFCR_EL1 = 0xC4CC;
  static const int kPMSICR_EL1 = 0xC4CA;
  static const int kPMSIDR_EL1 = 0xC4CF;
  static const int kPMSIRR_EL1 = 0xC4CB;
  static const int kPMSLATFR_EL1 = 0xC4CE;
  static const int kPMSWINC_EL0 = 0xDCE4;
  static const int kPMUSERENR_EL0 = 0xDCF0;
  static const int kPMXEVCNTR_EL0 = 0xDCEA;
  static const int kPMXEVTYPER_EL0 = 0xDCE9;
  static const int kREVIDR_EL1 = 0xC006;
  static const int kRGSR_EL1 = 0xC085;
  static const int kRMR_EL1 = 0xC602;
  static const int kRMR_EL2 = 0xE602;
  static const int kRMR_EL3 = 0xF602;
  static const int kRNDR = 0xD920;
  static const int kRNDRRS = 0xD921;
  static const int kRVBAR_EL1 = 0xC601;
  static const int kRVBAR_EL2 = 0xE601;
  static const int kRVBAR_EL3 = 0xF601;
  static const int kSCR_EL3 = 0xF088;
  static const int kSCTLR_EL1 = 0xC080;
  static const int kSCTLR_EL12 = 0xE880;
  static const int kSCTLR_EL2 = 0xE080;
  static const int kSCTLR_EL3 = 0xF080;
  static const int kSCXTNUM_EL0 = 0xDE87;
  static const int kSCXTNUM_EL1 = 0xC687;
  static const int kSCXTNUM_EL12 = 0xEE87;
  static const int kSCXTNUM_EL2 = 0xE687;
  static const int kSCXTNUM_EL3 = 0xF687;
  static const int kSDER32_EL2 = 0xE099;
  static const int kSDER32_EL3 = 0xF089;
  static const int kSPSR_EL1 = 0xC200;
  static const int kSPSR_EL12 = 0xEA00;
  static const int kSPSR_EL2 = 0xE200;
  static const int kSPSR_EL3 = 0xF200;
  static const int kSPSR_abt = 0xE219;
  static const int kSPSR_fiq = 0xE21B;
  static const int kSPSR_irq = 0xE218;
  static const int kSPSR_und = 0xE21A;
  static const int kSPSel = 0xC210;
  static const int kSP_EL0 = 0xC208;
  static const int kSP_EL1 = 0xE208;
  static const int kSP_EL2 = 0xF208;
  static const int kSSBS = 0xDA16;
  static const int kTCO = 0xDA17;
  static const int kTCR_EL1 = 0xC102;
  static const int kTCR_EL12 = 0xE902;
  static const int kTCR_EL2 = 0xE102;
  static const int kTCR_EL3 = 0xF102;
  static const int kTEECR32_EL1 = 0x9000;
  static const int kTEEHBR32_EL1 = 0x9080;
  static const int kTFSRE0_EL1 = 0xC2B1;
  static const int kTFSR_EL1 = 0xC2B0;
  static const int kTFSR_EL12 = 0xEAB0;
  static const int kTFSR_EL2 = 0xE2B0;
  static const int kTFSR_EL3 = 0xF2B0;
  static const int kTPIDRRO_EL0 = 0xDE83;
  static const int kTPIDR_EL0 = 0xDE82;
  static const int kTPIDR_EL1 = 0xC684;
  static const int kTPIDR_EL2 = 0xE682;
  static const int kTPIDR_EL3 = 0xF682;
  static const int kTRBBASER_EL1 = 0xC4DA;
  static const int kTRBIDR_EL1 = 0xC4DF;
  static const int kTRBLIMITR_EL1 = 0xC4D8;
  static const int kTRBMAR_EL1 = 0xC4DC;
  static const int kTRBPTR_EL1 = 0xC4D9;
  static const int kTRBSR_EL1 = 0xC4DB;
  static const int kTRBTRG_EL1 = 0xC4DE;
  static const int kTRCACATR0 = 0x8902;
  static const int kTRCACATR1 = 0x8912;
  static const int kTRCACATR10 = 0x8923;
  static const int kTRCACATR11 = 0x8933;
  static const int kTRCACATR12 = 0x8943;
  static const int kTRCACATR13 = 0x8953;
  static const int kTRCACATR14 = 0x8963;
  static const int kTRCACATR15 = 0x8973;
  static const int kTRCACATR2 = 0x8922;
  static const int kTRCACATR3 = 0x8932;
  static const int kTRCACATR4 = 0x8942;
  static const int kTRCACATR5 = 0x8952;
  static const int kTRCACATR6 = 0x8962;
  static const int kTRCACATR7 = 0x8972;
  static const int kTRCACATR8 = 0x8903;
  static const int kTRCACATR9 = 0x8913;
  static const int kTRCACVR0 = 0x8900;
  static const int kTRCACVR1 = 0x8910;
  static const int kTRCACVR10 = 0x8921;
  static const int kTRCACVR11 = 0x8931;
  static const int kTRCACVR12 = 0x8941;
  static const int kTRCACVR13 = 0x8951;
  static const int kTRCACVR14 = 0x8961;
  static const int kTRCACVR15 = 0x8971;
  static const int kTRCACVR2 = 0x8920;
  static const int kTRCACVR3 = 0x8930;
  static const int kTRCACVR4 = 0x8940;
  static const int kTRCACVR5 = 0x8950;
  static const int kTRCACVR6 = 0x8960;
  static const int kTRCACVR7 = 0x8970;
  static const int kTRCACVR8 = 0x8901;
  static const int kTRCACVR9 = 0x8911;
  static const int kTRCAUTHSTATUS = 0x8BF6;
  static const int kTRCAUXCTLR = 0x8830;
  static const int kTRCBBCTLR = 0x8878;
  static const int kTRCCCCTLR = 0x8870;
  static const int kTRCCIDCCTLR0 = 0x8982;
  static const int kTRCCIDCCTLR1 = 0x898A;
  static const int kTRCCIDCVR0 = 0x8980;
  static const int kTRCCIDCVR1 = 0x8990;
  static const int kTRCCIDCVR2 = 0x89A0;
  static const int kTRCCIDCVR3 = 0x89B0;
  static const int kTRCCIDCVR4 = 0x89C0;
  static const int kTRCCIDCVR5 = 0x89D0;
  static const int kTRCCIDCVR6 = 0x89E0;
  static const int kTRCCIDCVR7 = 0x89F0;
  static const int kTRCCIDR0 = 0x8BE7;
  static const int kTRCCIDR1 = 0x8BEF;
  static const int kTRCCIDR2 = 0x8BF7;
  static const int kTRCCIDR3 = 0x8BFF;
  static const int kTRCCLAIMCLR = 0x8BCE;
  static const int kTRCCLAIMSET = 0x8BC6;
  static const int kTRCCNTCTLR0 = 0x8825;
  static const int kTRCCNTCTLR1 = 0x882D;
  static const int kTRCCNTCTLR2 = 0x8835;
  static const int kTRCCNTCTLR3 = 0x883D;
  static const int kTRCCNTRLDVR0 = 0x8805;
  static const int kTRCCNTRLDVR1 = 0x880D;
  static const int kTRCCNTRLDVR2 = 0x8815;
  static const int kTRCCNTRLDVR3 = 0x881D;
  static const int kTRCCNTVR0 = 0x8845;
  static const int kTRCCNTVR1 = 0x884D;
  static const int kTRCCNTVR2 = 0x8855;
  static const int kTRCCNTVR3 = 0x885D;
  static const int kTRCCONFIGR = 0x8820;
  static const int kTRCDEVAFF0 = 0x8BD6;
  static const int kTRCDEVAFF1 = 0x8BDE;
  static const int kTRCDEVARCH = 0x8BFE;
  static const int kTRCDEVID = 0x8B97;
  static const int kTRCDEVTYPE = 0x8B9F;
  static const int kTRCDVCMR0 = 0x8906;
  static const int kTRCDVCMR1 = 0x8926;
  static const int kTRCDVCMR2 = 0x8946;
  static const int kTRCDVCMR3 = 0x8966;
  static const int kTRCDVCMR4 = 0x8907;
  static const int kTRCDVCMR5 = 0x8927;
  static const int kTRCDVCMR6 = 0x8947;
  static const int kTRCDVCMR7 = 0x8967;
  static const int kTRCDVCVR0 = 0x8904;
  static const int kTRCDVCVR1 = 0x8924;
  static const int kTRCDVCVR2 = 0x8944;
  static const int kTRCDVCVR3 = 0x8964;
  static const int kTRCDVCVR4 = 0x8905;
  static const int kTRCDVCVR5 = 0x8925;
  static const int kTRCDVCVR6 = 0x8945;
  static const int kTRCDVCVR7 = 0x8965;
  static const int kTRCEVENTCTL0R = 0x8840;
  static const int kTRCEVENTCTL1R = 0x8848;
  static const int kTRCEXTINSELR = 0x8844;
  static const int kTRCEXTINSELR0 = 0x8844;
  static const int kTRCEXTINSELR1 = 0x884C;
  static const int kTRCEXTINSELR2 = 0x8854;
  static const int kTRCEXTINSELR3 = 0x885C;
  static const int kTRCIDR0 = 0x8847;
  static const int kTRCIDR1 = 0x884F;
  static const int kTRCIDR10 = 0x8816;
  static const int kTRCIDR11 = 0x881E;
  static const int kTRCIDR12 = 0x8826;
  static const int kTRCIDR13 = 0x882E;
  static const int kTRCIDR2 = 0x8857;
  static const int kTRCIDR3 = 0x885F;
  static const int kTRCIDR4 = 0x8867;
  static const int kTRCIDR5 = 0x886F;
  static const int kTRCIDR6 = 0x8877;
  static const int kTRCIDR7 = 0x887F;
  static const int kTRCIDR8 = 0x8806;
  static const int kTRCIDR9 = 0x880E;
  static const int kTRCIMSPEC0 = 0x8807;
  static const int kTRCIMSPEC1 = 0x880F;
  static const int kTRCIMSPEC2 = 0x8817;
  static const int kTRCIMSPEC3 = 0x881F;
  static const int kTRCIMSPEC4 = 0x8827;
  static const int kTRCIMSPEC5 = 0x882F;
  static const int kTRCIMSPEC6 = 0x8837;
  static const int kTRCIMSPEC7 = 0x883F;
  static const int kTRCITCTRL = 0x8B84;
  static const int kTRCLAR = 0x8BE6;
  static const int kTRCLSR = 0x8BEE;
  static const int kTRCOSLAR = 0x8884;
  static const int kTRCOSLSR = 0x888C;
  static const int kTRCPDCR = 0x88A4;
  static const int kTRCPDSR = 0x88AC;
  static const int kTRCPIDR0 = 0x8BC7;
  static const int kTRCPIDR1 = 0x8BCF;
  static const int kTRCPIDR2 = 0x8BD7;
  static const int kTRCPIDR3 = 0x8BDF;
  static const int kTRCPIDR4 = 0x8BA7;
  static const int kTRCPIDR5 = 0x8BAF;
  static const int kTRCPIDR6 = 0x8BB7;
  static const int kTRCPIDR7 = 0x8BBF;
  static const int kTRCPRGCTLR = 0x8808;
  static const int kTRCPROCSELR = 0x8810;
  static const int kTRCQCTLR = 0x8809;
  static const int kTRCRSCTLR10 = 0x88D0;
  static const int kTRCRSCTLR11 = 0x88D8;
  static const int kTRCRSCTLR12 = 0x88E0;
  static const int kTRCRSCTLR13 = 0x88E8;
  static const int kTRCRSCTLR14 = 0x88F0;
  static const int kTRCRSCTLR15 = 0x88F8;
  static const int kTRCRSCTLR16 = 0x8881;
  static const int kTRCRSCTLR17 = 0x8889;
  static const int kTRCRSCTLR18 = 0x8891;
  static const int kTRCRSCTLR19 = 0x8899;
  static const int kTRCRSCTLR2 = 0x8890;
  static const int kTRCRSCTLR20 = 0x88A1;
  static const int kTRCRSCTLR21 = 0x88A9;
  static const int kTRCRSCTLR22 = 0x88B1;
  static const int kTRCRSCTLR23 = 0x88B9;
  static const int kTRCRSCTLR24 = 0x88C1;
  static const int kTRCRSCTLR25 = 0x88C9;
  static const int kTRCRSCTLR26 = 0x88D1;
  static const int kTRCRSCTLR27 = 0x88D9;
  static const int kTRCRSCTLR28 = 0x88E1;
  static const int kTRCRSCTLR29 = 0x88E9;
  static const int kTRCRSCTLR3 = 0x8898;
  static const int kTRCRSCTLR30 = 0x88F1;
  static const int kTRCRSCTLR31 = 0x88F9;
  static const int kTRCRSCTLR4 = 0x88A0;
  static const int kTRCRSCTLR5 = 0x88A8;
  static const int kTRCRSCTLR6 = 0x88B0;
  static const int kTRCRSCTLR7 = 0x88B8;
  static const int kTRCRSCTLR8 = 0x88C0;
  static const int kTRCRSCTLR9 = 0x88C8;
  static const int kTRCRSR = 0x8850;
  static const int kTRCSEQEVR0 = 0x8804;
  static const int kTRCSEQEVR1 = 0x880C;
  static const int kTRCSEQEVR2 = 0x8814;
  static const int kTRCSEQRSTEVR = 0x8834;
  static const int kTRCSEQSTR = 0x883C;
  static const int kTRCSSCCR0 = 0x8882;
  static const int kTRCSSCCR1 = 0x888A;
  static const int kTRCSSCCR2 = 0x8892;
  static const int kTRCSSCCR3 = 0x889A;
  static const int kTRCSSCCR4 = 0x88A2;
  static const int kTRCSSCCR5 = 0x88AA;
  static const int kTRCSSCCR6 = 0x88B2;
  static const int kTRCSSCCR7 = 0x88BA;
  static const int kTRCSSCSR0 = 0x88C2;
  static const int kTRCSSCSR1 = 0x88CA;
  static const int kTRCSSCSR2 = 0x88D2;
  static const int kTRCSSCSR3 = 0x88DA;
  static const int kTRCSSCSR4 = 0x88E2;
  static const int kTRCSSCSR5 = 0x88EA;
  static const int kTRCSSCSR6 = 0x88F2;
  static const int kTRCSSCSR7 = 0x88FA;
  static const int kTRCSSPCICR0 = 0x8883;
  static const int kTRCSSPCICR1 = 0x888B;
  static const int kTRCSSPCICR2 = 0x8893;
  static const int kTRCSSPCICR3 = 0x889B;
  static const int kTRCSSPCICR4 = 0x88A3;
  static const int kTRCSSPCICR5 = 0x88AB;
  static const int kTRCSSPCICR6 = 0x88B3;
  static const int kTRCSSPCICR7 = 0x88BB;
  static const int kTRCSTALLCTLR = 0x8858;
  static const int kTRCSTATR = 0x8818;
  static const int kTRCSYNCPR = 0x8868;
  static const int kTRCTRACEIDR = 0x8801;
  static const int kTRCTSCTLR = 0x8860;
  static const int kTRCVDARCCTLR = 0x8852;
  static const int kTRCVDCTLR = 0x8842;
  static const int kTRCVDSACCTLR = 0x884A;
  static const int kTRCVICTLR = 0x8802;
  static const int kTRCVIIECTLR = 0x880A;
  static const int kTRCVIPCSSCTLR = 0x881A;
  static const int kTRCVISSCTLR = 0x8812;
  static const int kTRCVMIDCCTLR0 = 0x8992;
  static const int kTRCVMIDCCTLR1 = 0x899A;
  static const int kTRCVMIDCVR0 = 0x8981;
  static const int kTRCVMIDCVR1 = 0x8991;
  static const int kTRCVMIDCVR2 = 0x89A1;
  static const int kTRCVMIDCVR3 = 0x89B1;
  static const int kTRCVMIDCVR4 = 0x89C1;
  static const int kTRCVMIDCVR5 = 0x89D1;
  static const int kTRCVMIDCVR6 = 0x89E1;
  static const int kTRCVMIDCVR7 = 0x89F1;
  static const int kTRFCR_EL1 = 0xC091;
  static const int kTRFCR_EL12 = 0xE891;
  static const int kTRFCR_EL2 = 0xE091;
  static const int kTTBR0_EL1 = 0xC100;
  static const int kTTBR0_EL12 = 0xE900;
  static const int kTTBR0_EL2 = 0xE100;
  static const int kTTBR0_EL3 = 0xF100;
  static const int kTTBR1_EL1 = 0xC101;
  static const int kTTBR1_EL12 = 0xE901;
  static const int kTTBR1_EL2 = 0xE101;
  static const int kUAO = 0xC214;
  static const int kVBAR_EL1 = 0xC600;
  static const int kVBAR_EL12 = 0xEE00;
  static const int kVBAR_EL2 = 0xE600;
  static const int kVBAR_EL3 = 0xF600;
  static const int kVDISR_EL2 = 0xE609;
  static const int kVMPIDR_EL2 = 0xE005;
  static const int kVNCR_EL2 = 0xE110;
  static const int kVPIDR_EL2 = 0xE000;
  static const int kVSESR_EL2 = 0xE293;
  static const int kVSTCR_EL2 = 0xE132;
  static const int kVSTTBR_EL2 = 0xE130;
  static const int kVTCR_EL2 = 0xE10A;
  static const int kVTTBR_EL2 = 0xE108;
  static const int kZCR_EL1 = 0xC090;
  static const int kZCR_EL12 = 0xE890;
  static const int kZCR_EL2 = 0xE090;
  static const int kZCR_EL3 = 0xF090;
}

/// Every predicate by upstream name (`PRFOp::kPLDL1KEEP`).
const kA64Predicates = <String, int>{
  'AT::kS1E1R': A64AT.kS1E1R,
  'AT::kS1E2R': A64AT.kS1E2R,
  'AT::kS1E3R': A64AT.kS1E3R,
  'AT::kS1E1W': A64AT.kS1E1W,
  'AT::kS1E2W': A64AT.kS1E2W,
  'AT::kS1E3W': A64AT.kS1E3W,
  'AT::kS1E0R': A64AT.kS1E0R,
  'AT::kS1E0W': A64AT.kS1E0W,
  'AT::kS12E1R': A64AT.kS12E1R,
  'AT::kS12E1W': A64AT.kS12E1W,
  'AT::kS12E0R': A64AT.kS12E0R,
  'AT::kS12E0W': A64AT.kS12E0W,
  'AT::kS1E1RP': A64AT.kS1E1RP,
  'AT::kS1E1WP': A64AT.kS1E1WP,
  'BTI::kNone': A64BTI.kNone,
  'BTI::kC': A64BTI.kC,
  'BTI::kJ': A64BTI.kJ,
  'BTI::kJC': A64BTI.kJC,
  'DB::kOSHLD': A64DB.kOSHLD,
  'DB::kOSHST': A64DB.kOSHST,
  'DB::kOSH': A64DB.kOSH,
  'DB::kNSHLD': A64DB.kNSHLD,
  'DB::kNSHST': A64DB.kNSHST,
  'DB::kNSH': A64DB.kNSH,
  'DB::kISHLD': A64DB.kISHLD,
  'DB::kISHST': A64DB.kISHST,
  'DB::kISH': A64DB.kISH,
  'DB::kLD': A64DB.kLD,
  'DB::kST': A64DB.kST,
  'DB::kSY': A64DB.kSY,
  'DC::kZVA': A64DC.kZVA,
  'DC::kIVAC': A64DC.kIVAC,
  'DC::kISW': A64DC.kISW,
  'DC::kCVAC': A64DC.kCVAC,
  'DC::kCSW': A64DC.kCSW,
  'DC::kCVAU': A64DC.kCVAU,
  'DC::kCIVAC': A64DC.kCIVAC,
  'DC::kCISW': A64DC.kCISW,
  'DC::kCVAP': A64DC.kCVAP,
  'DC::kCVADP': A64DC.kCVADP,
  'DC::kIGVAC': A64DC.kIGVAC,
  'DC::kIGSW': A64DC.kIGSW,
  'DC::kCGSW': A64DC.kCGSW,
  'DC::kCIGSW': A64DC.kCIGSW,
  'DC::kCGVAC': A64DC.kCGVAC,
  'DC::kCGVAP': A64DC.kCGVAP,
  'DC::kCGVADP': A64DC.kCGVADP,
  'DC::kCIGVAC': A64DC.kCIGVAC,
  'DC::kGVA': A64DC.kGVA,
  'DC::kIGDVAC': A64DC.kIGDVAC,
  'DC::kIGDSW': A64DC.kIGDSW,
  'DC::kCGDSW': A64DC.kCGDSW,
  'DC::kCIGDSW': A64DC.kCIGDSW,
  'DC::kCGDVAC': A64DC.kCGDVAC,
  'DC::kCGDVAP': A64DC.kCGDVAP,
  'DC::kCGDVADP': A64DC.kCGDVADP,
  'DC::kCIGDVAC': A64DC.kCIGDVAC,
  'DC::kGZVA': A64DC.kGZVA,
  'IC::kIALLUIS': A64IC.kIALLUIS,
  'IC::kIALLU': A64IC.kIALLU,
  'IC::kIVAU': A64IC.kIVAU,
  'ISB::kSY': A64ISB.kSY,
  'PRFOp::kPLDL1KEEP': A64PRFOp.kPLDL1KEEP,
  'PRFOp::kPLDL1STRM': A64PRFOp.kPLDL1STRM,
  'PRFOp::kPLDL2KEEP': A64PRFOp.kPLDL2KEEP,
  'PRFOp::kPLDL2STRM': A64PRFOp.kPLDL2STRM,
  'PRFOp::kPLDL3KEEP': A64PRFOp.kPLDL3KEEP,
  'PRFOp::kPLDL3STRM': A64PRFOp.kPLDL3STRM,
  'PRFOp::kPLIL1KEEP': A64PRFOp.kPLIL1KEEP,
  'PRFOp::kPLIL1STRM': A64PRFOp.kPLIL1STRM,
  'PRFOp::kPLIL2KEEP': A64PRFOp.kPLIL2KEEP,
  'PRFOp::kPLIL2STRM': A64PRFOp.kPLIL2STRM,
  'PRFOp::kPLIL3KEEP': A64PRFOp.kPLIL3KEEP,
  'PRFOp::kPLIL3STRM': A64PRFOp.kPLIL3STRM,
  'PRFOp::kPSTL1KEEP': A64PRFOp.kPSTL1KEEP,
  'PRFOp::kPSTL1STRM': A64PRFOp.kPSTL1STRM,
  'PRFOp::kPSTL2KEEP': A64PRFOp.kPSTL2KEEP,
  'PRFOp::kPSTL2STRM': A64PRFOp.kPSTL2STRM,
  'PRFOp::kPSTL3KEEP': A64PRFOp.kPSTL3KEEP,
  'PRFOp::kPSTL3STRM': A64PRFOp.kPSTL3STRM,
  'PSB::kCSYNC': A64PSB.kCSYNC,
  'TLBI::kIPAS2E1IS': A64TLBI.kIPAS2E1IS,
  'TLBI::kIPAS2LE1IS': A64TLBI.kIPAS2LE1IS,
  'TLBI::kVMALLE1IS': A64TLBI.kVMALLE1IS,
  'TLBI::kALLE2IS': A64TLBI.kALLE2IS,
  'TLBI::kALLE3IS': A64TLBI.kALLE3IS,
  'TLBI::kVAE1IS': A64TLBI.kVAE1IS,
  'TLBI::kVAE2IS': A64TLBI.kVAE2IS,
  'TLBI::kVAE3IS': A64TLBI.kVAE3IS,
  'TLBI::kASIDE1IS': A64TLBI.kASIDE1IS,
  'TLBI::kVAAE1IS': A64TLBI.kVAAE1IS,
  'TLBI::kALLE1IS': A64TLBI.kALLE1IS,
  'TLBI::kVALE1IS': A64TLBI.kVALE1IS,
  'TLBI::kVALE2IS': A64TLBI.kVALE2IS,
  'TLBI::kVALE3IS': A64TLBI.kVALE3IS,
  'TLBI::kVMALLS12E1IS': A64TLBI.kVMALLS12E1IS,
  'TLBI::kVAALE1IS': A64TLBI.kVAALE1IS,
  'TLBI::kIPAS2E1': A64TLBI.kIPAS2E1,
  'TLBI::kIPAS2LE1': A64TLBI.kIPAS2LE1,
  'TLBI::kVMALLE1': A64TLBI.kVMALLE1,
  'TLBI::kALLE2': A64TLBI.kALLE2,
  'TLBI::kALLE3': A64TLBI.kALLE3,
  'TLBI::kVAE1': A64TLBI.kVAE1,
  'TLBI::kVAE2': A64TLBI.kVAE2,
  'TLBI::kVAE3': A64TLBI.kVAE3,
  'TLBI::kASIDE1': A64TLBI.kASIDE1,
  'TLBI::kVAAE1': A64TLBI.kVAAE1,
  'TLBI::kALLE1': A64TLBI.kALLE1,
  'TLBI::kVALE1': A64TLBI.kVALE1,
  'TLBI::kVALE2': A64TLBI.kVALE2,
  'TLBI::kVALE3': A64TLBI.kVALE3,
  'TLBI::kVMALLS12E1': A64TLBI.kVMALLS12E1,
  'TLBI::kVAALE1': A64TLBI.kVAALE1,
  'TLBI::kVMALLE1OS': A64TLBI.kVMALLE1OS,
  'TLBI::kVAE1OS': A64TLBI.kVAE1OS,
  'TLBI::kASIDE1OS': A64TLBI.kASIDE1OS,
  'TLBI::kVAAE1OS': A64TLBI.kVAAE1OS,
  'TLBI::kVALE1OS': A64TLBI.kVALE1OS,
  'TLBI::kVAALE1OS': A64TLBI.kVAALE1OS,
  'TLBI::kIPAS2E1OS': A64TLBI.kIPAS2E1OS,
  'TLBI::kIPAS2LE1OS': A64TLBI.kIPAS2LE1OS,
  'TLBI::kVAE2OS': A64TLBI.kVAE2OS,
  'TLBI::kVALE2OS': A64TLBI.kVALE2OS,
  'TLBI::kVMALLS12E1OS': A64TLBI.kVMALLS12E1OS,
  'TLBI::kVAE3OS': A64TLBI.kVAE3OS,
  'TLBI::kVALE3OS': A64TLBI.kVALE3OS,
  'TLBI::kALLE2OS': A64TLBI.kALLE2OS,
  'TLBI::kALLE1OS': A64TLBI.kALLE1OS,
  'TLBI::kALLE3OS': A64TLBI.kALLE3OS,
  'TLBI::kRVAE1': A64TLBI.kRVAE1,
  'TLBI::kRVAAE1': A64TLBI.kRVAAE1,
  'TLBI::kRVALE1': A64TLBI.kRVALE1,
  'TLBI::kRVAALE1': A64TLBI.kRVAALE1,
  'TLBI::kRVAE1IS': A64TLBI.kRVAE1IS,
  'TLBI::kRVAAE1IS': A64TLBI.kRVAAE1IS,
  'TLBI::kRVALE1IS': A64TLBI.kRVALE1IS,
  'TLBI::kRVAALE1IS': A64TLBI.kRVAALE1IS,
  'TLBI::kRVAE1OS': A64TLBI.kRVAE1OS,
  'TLBI::kRVAAE1OS': A64TLBI.kRVAAE1OS,
  'TLBI::kRVALE1OS': A64TLBI.kRVALE1OS,
  'TLBI::kRVAALE1OS': A64TLBI.kRVAALE1OS,
  'TLBI::kRIPAS2E1IS': A64TLBI.kRIPAS2E1IS,
  'TLBI::kRIPAS2LE1IS': A64TLBI.kRIPAS2LE1IS,
  'TLBI::kRIPAS2E1': A64TLBI.kRIPAS2E1,
  'TLBI::kRIPAS2LE1': A64TLBI.kRIPAS2LE1,
  'TLBI::kRIPAS2E1OS': A64TLBI.kRIPAS2E1OS,
  'TLBI::kRIPAS2LE1OS': A64TLBI.kRIPAS2LE1OS,
  'TLBI::kRVAE2': A64TLBI.kRVAE2,
  'TLBI::kRVALE2': A64TLBI.kRVALE2,
  'TLBI::kRVAE2IS': A64TLBI.kRVAE2IS,
  'TLBI::kRVALE2IS': A64TLBI.kRVALE2IS,
  'TLBI::kRVAE2OS': A64TLBI.kRVAE2OS,
  'TLBI::kRVALE2OS': A64TLBI.kRVALE2OS,
  'TLBI::kRVAE3': A64TLBI.kRVAE3,
  'TLBI::kRVALE3': A64TLBI.kRVALE3,
  'TLBI::kRVAE3IS': A64TLBI.kRVAE3IS,
  'TLBI::kRVALE3IS': A64TLBI.kRVALE3IS,
  'TLBI::kRVAE3OS': A64TLBI.kRVAE3OS,
  'TLBI::kRVALE3OS': A64TLBI.kRVALE3OS,
  'TSB::kCSYNC': A64TSB.kCSYNC,
  'PState::kSPSel': A64PState.kSPSel,
  'PState::kDAIFSet': A64PState.kDAIFSet,
  'PState::kDAIFClr': A64PState.kDAIFClr,
  'PState::kPAN': A64PState.kPAN,
  'PState::kUAO': A64PState.kUAO,
  'PState::kDIT': A64PState.kDIT,
  'PState::kSSBS': A64PState.kSSBS,
  'PState::kTCO': A64PState.kTCO,
  'SysReg::kACTLR_EL1': A64SysReg.kACTLR_EL1,
  'SysReg::kACTLR_EL2': A64SysReg.kACTLR_EL2,
  'SysReg::kACTLR_EL3': A64SysReg.kACTLR_EL3,
  'SysReg::kAFSR0_EL1': A64SysReg.kAFSR0_EL1,
  'SysReg::kAFSR0_EL12': A64SysReg.kAFSR0_EL12,
  'SysReg::kAFSR0_EL2': A64SysReg.kAFSR0_EL2,
  'SysReg::kAFSR0_EL3': A64SysReg.kAFSR0_EL3,
  'SysReg::kAFSR1_EL1': A64SysReg.kAFSR1_EL1,
  'SysReg::kAFSR1_EL12': A64SysReg.kAFSR1_EL12,
  'SysReg::kAFSR1_EL2': A64SysReg.kAFSR1_EL2,
  'SysReg::kAFSR1_EL3': A64SysReg.kAFSR1_EL3,
  'SysReg::kAIDR_EL1': A64SysReg.kAIDR_EL1,
  'SysReg::kAMAIR_EL1': A64SysReg.kAMAIR_EL1,
  'SysReg::kAMAIR_EL12': A64SysReg.kAMAIR_EL12,
  'SysReg::kAMAIR_EL2': A64SysReg.kAMAIR_EL2,
  'SysReg::kAMAIR_EL3': A64SysReg.kAMAIR_EL3,
  'SysReg::kAMCFGR_EL0': A64SysReg.kAMCFGR_EL0,
  'SysReg::kAMCGCR_EL0': A64SysReg.kAMCGCR_EL0,
  'SysReg::kAMCNTENCLR0_EL0': A64SysReg.kAMCNTENCLR0_EL0,
  'SysReg::kAMCNTENCLR1_EL0': A64SysReg.kAMCNTENCLR1_EL0,
  'SysReg::kAMCNTENSET0_EL0': A64SysReg.kAMCNTENSET0_EL0,
  'SysReg::kAMCNTENSET1_EL0': A64SysReg.kAMCNTENSET1_EL0,
  'SysReg::kAMCR_EL0': A64SysReg.kAMCR_EL0,
  'SysReg::kAMEVCNTR00_EL0': A64SysReg.kAMEVCNTR00_EL0,
  'SysReg::kAMEVCNTR01_EL0': A64SysReg.kAMEVCNTR01_EL0,
  'SysReg::kAMEVCNTR02_EL0': A64SysReg.kAMEVCNTR02_EL0,
  'SysReg::kAMEVCNTR03_EL0': A64SysReg.kAMEVCNTR03_EL0,
  'SysReg::kAMEVCNTR10_EL0': A64SysReg.kAMEVCNTR10_EL0,
  'SysReg::kAMEVCNTR110_EL0': A64SysReg.kAMEVCNTR110_EL0,
  'SysReg::kAMEVCNTR111_EL0': A64SysReg.kAMEVCNTR111_EL0,
  'SysReg::kAMEVCNTR112_EL0': A64SysReg.kAMEVCNTR112_EL0,
  'SysReg::kAMEVCNTR113_EL0': A64SysReg.kAMEVCNTR113_EL0,
  'SysReg::kAMEVCNTR114_EL0': A64SysReg.kAMEVCNTR114_EL0,
  'SysReg::kAMEVCNTR115_EL0': A64SysReg.kAMEVCNTR115_EL0,
  'SysReg::kAMEVCNTR11_EL0': A64SysReg.kAMEVCNTR11_EL0,
  'SysReg::kAMEVCNTR12_EL0': A64SysReg.kAMEVCNTR12_EL0,
  'SysReg::kAMEVCNTR13_EL0': A64SysReg.kAMEVCNTR13_EL0,
  'SysReg::kAMEVCNTR14_EL0': A64SysReg.kAMEVCNTR14_EL0,
  'SysReg::kAMEVCNTR15_EL0': A64SysReg.kAMEVCNTR15_EL0,
  'SysReg::kAMEVCNTR16_EL0': A64SysReg.kAMEVCNTR16_EL0,
  'SysReg::kAMEVCNTR17_EL0': A64SysReg.kAMEVCNTR17_EL0,
  'SysReg::kAMEVCNTR18_EL0': A64SysReg.kAMEVCNTR18_EL0,
  'SysReg::kAMEVCNTR19_EL0': A64SysReg.kAMEVCNTR19_EL0,
  'SysReg::kAMEVTYPER00_EL0': A64SysReg.kAMEVTYPER00_EL0,
  'SysReg::kAMEVTYPER01_EL0': A64SysReg.kAMEVTYPER01_EL0,
  'SysReg::kAMEVTYPER02_EL0': A64SysReg.kAMEVTYPER02_EL0,
  'SysReg::kAMEVTYPER03_EL0': A64SysReg.kAMEVTYPER03_EL0,
  'SysReg::kAMEVTYPER10_EL0': A64SysReg.kAMEVTYPER10_EL0,
  'SysReg::kAMEVTYPER110_EL0': A64SysReg.kAMEVTYPER110_EL0,
  'SysReg::kAMEVTYPER111_EL0': A64SysReg.kAMEVTYPER111_EL0,
  'SysReg::kAMEVTYPER112_EL0': A64SysReg.kAMEVTYPER112_EL0,
  'SysReg::kAMEVTYPER113_EL0': A64SysReg.kAMEVTYPER113_EL0,
  'SysReg::kAMEVTYPER114_EL0': A64SysReg.kAMEVTYPER114_EL0,
  'SysReg::kAMEVTYPER115_EL0': A64SysReg.kAMEVTYPER115_EL0,
  'SysReg::kAMEVTYPER11_EL0': A64SysReg.kAMEVTYPER11_EL0,
  'SysReg::kAMEVTYPER12_EL0': A64SysReg.kAMEVTYPER12_EL0,
  'SysReg::kAMEVTYPER13_EL0': A64SysReg.kAMEVTYPER13_EL0,
  'SysReg::kAMEVTYPER14_EL0': A64SysReg.kAMEVTYPER14_EL0,
  'SysReg::kAMEVTYPER15_EL0': A64SysReg.kAMEVTYPER15_EL0,
  'SysReg::kAMEVTYPER16_EL0': A64SysReg.kAMEVTYPER16_EL0,
  'SysReg::kAMEVTYPER17_EL0': A64SysReg.kAMEVTYPER17_EL0,
  'SysReg::kAMEVTYPER18_EL0': A64SysReg.kAMEVTYPER18_EL0,
  'SysReg::kAMEVTYPER19_EL0': A64SysReg.kAMEVTYPER19_EL0,
  'SysReg::kAMUSERENR_EL0': A64SysReg.kAMUSERENR_EL0,
  'SysReg::kAPDAKeyHi_EL1': A64SysReg.kAPDAKeyHi_EL1,
  'SysReg::kAPDAKeyLo_EL1': A64SysReg.kAPDAKeyLo_EL1,
  'SysReg::kAPDBKeyHi_EL1': A64SysReg.kAPDBKeyHi_EL1,
  'SysReg::kAPDBKeyLo_EL1': A64SysReg.kAPDBKeyLo_EL1,
  'SysReg::kAPGAKeyHi_EL1': A64SysReg.kAPGAKeyHi_EL1,
  'SysReg::kAPGAKeyLo_EL1': A64SysReg.kAPGAKeyLo_EL1,
  'SysReg::kAPIAKeyHi_EL1': A64SysReg.kAPIAKeyHi_EL1,
  'SysReg::kAPIAKeyLo_EL1': A64SysReg.kAPIAKeyLo_EL1,
  'SysReg::kAPIBKeyHi_EL1': A64SysReg.kAPIBKeyHi_EL1,
  'SysReg::kAPIBKeyLo_EL1': A64SysReg.kAPIBKeyLo_EL1,
  'SysReg::kCCSIDR2_EL1': A64SysReg.kCCSIDR2_EL1,
  'SysReg::kCCSIDR_EL1': A64SysReg.kCCSIDR_EL1,
  'SysReg::kCLIDR_EL1': A64SysReg.kCLIDR_EL1,
  'SysReg::kCNTFRQ_EL0': A64SysReg.kCNTFRQ_EL0,
  'SysReg::kCNTHCTL_EL2': A64SysReg.kCNTHCTL_EL2,
  'SysReg::kCNTHPS_CTL_EL2': A64SysReg.kCNTHPS_CTL_EL2,
  'SysReg::kCNTHPS_CVAL_EL2': A64SysReg.kCNTHPS_CVAL_EL2,
  'SysReg::kCNTHPS_TVAL_EL2': A64SysReg.kCNTHPS_TVAL_EL2,
  'SysReg::kCNTHP_CTL_EL2': A64SysReg.kCNTHP_CTL_EL2,
  'SysReg::kCNTHP_CVAL_EL2': A64SysReg.kCNTHP_CVAL_EL2,
  'SysReg::kCNTHP_TVAL_EL2': A64SysReg.kCNTHP_TVAL_EL2,
  'SysReg::kCNTHVS_CTL_EL2': A64SysReg.kCNTHVS_CTL_EL2,
  'SysReg::kCNTHVS_CVAL_EL2': A64SysReg.kCNTHVS_CVAL_EL2,
  'SysReg::kCNTHVS_TVAL_EL2': A64SysReg.kCNTHVS_TVAL_EL2,
  'SysReg::kCNTHV_CTL_EL2': A64SysReg.kCNTHV_CTL_EL2,
  'SysReg::kCNTHV_CVAL_EL2': A64SysReg.kCNTHV_CVAL_EL2,
  'SysReg::kCNTHV_TVAL_EL2': A64SysReg.kCNTHV_TVAL_EL2,
  'SysReg::kCNTISCALE_EL2': A64SysReg.kCNTISCALE_EL2,
  'SysReg::kCNTKCTL_EL1': A64SysReg.kCNTKCTL_EL1,
  'SysReg::kCNTKCTL_EL12': A64SysReg.kCNTKCTL_EL12,
  'SysReg::kCNTPCTSS_EL0': A64SysReg.kCNTPCTSS_EL0,
  'SysReg::kCNTPCT_EL0': A64SysReg.kCNTPCT_EL0,
  'SysReg::kCNTPOFF_EL2': A64SysReg.kCNTPOFF_EL2,
  'SysReg::kCNTPS_CTL_EL1': A64SysReg.kCNTPS_CTL_EL1,
  'SysReg::kCNTPS_CVAL_EL1': A64SysReg.kCNTPS_CVAL_EL1,
  'SysReg::kCNTPS_TVAL_EL1': A64SysReg.kCNTPS_TVAL_EL1,
  'SysReg::kCNTP_CTL_EL0': A64SysReg.kCNTP_CTL_EL0,
  'SysReg::kCNTP_CTL_EL02': A64SysReg.kCNTP_CTL_EL02,
  'SysReg::kCNTP_CVAL_EL0': A64SysReg.kCNTP_CVAL_EL0,
  'SysReg::kCNTP_CVAL_EL02': A64SysReg.kCNTP_CVAL_EL02,
  'SysReg::kCNTP_TVAL_EL0': A64SysReg.kCNTP_TVAL_EL0,
  'SysReg::kCNTP_TVAL_EL02': A64SysReg.kCNTP_TVAL_EL02,
  'SysReg::kCNTSCALE_EL2': A64SysReg.kCNTSCALE_EL2,
  'SysReg::kCNTVCTSS_EL0': A64SysReg.kCNTVCTSS_EL0,
  'SysReg::kCNTVCT_EL0': A64SysReg.kCNTVCT_EL0,
  'SysReg::kCNTVFRQ_EL2': A64SysReg.kCNTVFRQ_EL2,
  'SysReg::kCNTVOFF_EL2': A64SysReg.kCNTVOFF_EL2,
  'SysReg::kCNTV_CTL_EL0': A64SysReg.kCNTV_CTL_EL0,
  'SysReg::kCNTV_CTL_EL02': A64SysReg.kCNTV_CTL_EL02,
  'SysReg::kCNTV_CVAL_EL0': A64SysReg.kCNTV_CVAL_EL0,
  'SysReg::kCNTV_CVAL_EL02': A64SysReg.kCNTV_CVAL_EL02,
  'SysReg::kCNTV_TVAL_EL0': A64SysReg.kCNTV_TVAL_EL0,
  'SysReg::kCNTV_TVAL_EL02': A64SysReg.kCNTV_TVAL_EL02,
  'SysReg::kCONTEXTIDR_EL1': A64SysReg.kCONTEXTIDR_EL1,
  'SysReg::kCONTEXTIDR_EL12': A64SysReg.kCONTEXTIDR_EL12,
  'SysReg::kCONTEXTIDR_EL2': A64SysReg.kCONTEXTIDR_EL2,
  'SysReg::kCPACR_EL1': A64SysReg.kCPACR_EL1,
  'SysReg::kCPACR_EL12': A64SysReg.kCPACR_EL12,
  'SysReg::kCPM_IOACC_CTL_EL3': A64SysReg.kCPM_IOACC_CTL_EL3,
  'SysReg::kCPTR_EL2': A64SysReg.kCPTR_EL2,
  'SysReg::kCPTR_EL3': A64SysReg.kCPTR_EL3,
  'SysReg::kCSSELR_EL1': A64SysReg.kCSSELR_EL1,
  'SysReg::kCTR_EL0': A64SysReg.kCTR_EL0,
  'SysReg::kCurrentEL': A64SysReg.kCurrentEL,
  'SysReg::kDACR32_EL2': A64SysReg.kDACR32_EL2,
  'SysReg::kDAIF': A64SysReg.kDAIF,
  'SysReg::kDBGAUTHSTATUS_EL1': A64SysReg.kDBGAUTHSTATUS_EL1,
  'SysReg::kDBGBCR0_EL1': A64SysReg.kDBGBCR0_EL1,
  'SysReg::kDBGBCR10_EL1': A64SysReg.kDBGBCR10_EL1,
  'SysReg::kDBGBCR11_EL1': A64SysReg.kDBGBCR11_EL1,
  'SysReg::kDBGBCR12_EL1': A64SysReg.kDBGBCR12_EL1,
  'SysReg::kDBGBCR13_EL1': A64SysReg.kDBGBCR13_EL1,
  'SysReg::kDBGBCR14_EL1': A64SysReg.kDBGBCR14_EL1,
  'SysReg::kDBGBCR15_EL1': A64SysReg.kDBGBCR15_EL1,
  'SysReg::kDBGBCR1_EL1': A64SysReg.kDBGBCR1_EL1,
  'SysReg::kDBGBCR2_EL1': A64SysReg.kDBGBCR2_EL1,
  'SysReg::kDBGBCR3_EL1': A64SysReg.kDBGBCR3_EL1,
  'SysReg::kDBGBCR4_EL1': A64SysReg.kDBGBCR4_EL1,
  'SysReg::kDBGBCR5_EL1': A64SysReg.kDBGBCR5_EL1,
  'SysReg::kDBGBCR6_EL1': A64SysReg.kDBGBCR6_EL1,
  'SysReg::kDBGBCR7_EL1': A64SysReg.kDBGBCR7_EL1,
  'SysReg::kDBGBCR8_EL1': A64SysReg.kDBGBCR8_EL1,
  'SysReg::kDBGBCR9_EL1': A64SysReg.kDBGBCR9_EL1,
  'SysReg::kDBGBVR0_EL1': A64SysReg.kDBGBVR0_EL1,
  'SysReg::kDBGBVR10_EL1': A64SysReg.kDBGBVR10_EL1,
  'SysReg::kDBGBVR11_EL1': A64SysReg.kDBGBVR11_EL1,
  'SysReg::kDBGBVR12_EL1': A64SysReg.kDBGBVR12_EL1,
  'SysReg::kDBGBVR13_EL1': A64SysReg.kDBGBVR13_EL1,
  'SysReg::kDBGBVR14_EL1': A64SysReg.kDBGBVR14_EL1,
  'SysReg::kDBGBVR15_EL1': A64SysReg.kDBGBVR15_EL1,
  'SysReg::kDBGBVR1_EL1': A64SysReg.kDBGBVR1_EL1,
  'SysReg::kDBGBVR2_EL1': A64SysReg.kDBGBVR2_EL1,
  'SysReg::kDBGBVR3_EL1': A64SysReg.kDBGBVR3_EL1,
  'SysReg::kDBGBVR4_EL1': A64SysReg.kDBGBVR4_EL1,
  'SysReg::kDBGBVR5_EL1': A64SysReg.kDBGBVR5_EL1,
  'SysReg::kDBGBVR6_EL1': A64SysReg.kDBGBVR6_EL1,
  'SysReg::kDBGBVR7_EL1': A64SysReg.kDBGBVR7_EL1,
  'SysReg::kDBGBVR8_EL1': A64SysReg.kDBGBVR8_EL1,
  'SysReg::kDBGBVR9_EL1': A64SysReg.kDBGBVR9_EL1,
  'SysReg::kDBGCLAIMCLR_EL1': A64SysReg.kDBGCLAIMCLR_EL1,
  'SysReg::kDBGCLAIMSET_EL1': A64SysReg.kDBGCLAIMSET_EL1,
  'SysReg::kDBGDTRRX_EL0': A64SysReg.kDBGDTRRX_EL0,
  'SysReg::kDBGDTRTX_EL0': A64SysReg.kDBGDTRTX_EL0,
  'SysReg::kDBGDTR_EL0': A64SysReg.kDBGDTR_EL0,
  'SysReg::kDBGPRCR_EL1': A64SysReg.kDBGPRCR_EL1,
  'SysReg::kDBGVCR32_EL2': A64SysReg.kDBGVCR32_EL2,
  'SysReg::kDBGWCR0_EL1': A64SysReg.kDBGWCR0_EL1,
  'SysReg::kDBGWCR10_EL1': A64SysReg.kDBGWCR10_EL1,
  'SysReg::kDBGWCR11_EL1': A64SysReg.kDBGWCR11_EL1,
  'SysReg::kDBGWCR12_EL1': A64SysReg.kDBGWCR12_EL1,
  'SysReg::kDBGWCR13_EL1': A64SysReg.kDBGWCR13_EL1,
  'SysReg::kDBGWCR14_EL1': A64SysReg.kDBGWCR14_EL1,
  'SysReg::kDBGWCR15_EL1': A64SysReg.kDBGWCR15_EL1,
  'SysReg::kDBGWCR1_EL1': A64SysReg.kDBGWCR1_EL1,
  'SysReg::kDBGWCR2_EL1': A64SysReg.kDBGWCR2_EL1,
  'SysReg::kDBGWCR3_EL1': A64SysReg.kDBGWCR3_EL1,
  'SysReg::kDBGWCR4_EL1': A64SysReg.kDBGWCR4_EL1,
  'SysReg::kDBGWCR5_EL1': A64SysReg.kDBGWCR5_EL1,
  'SysReg::kDBGWCR6_EL1': A64SysReg.kDBGWCR6_EL1,
  'SysReg::kDBGWCR7_EL1': A64SysReg.kDBGWCR7_EL1,
  'SysReg::kDBGWCR8_EL1': A64SysReg.kDBGWCR8_EL1,
  'SysReg::kDBGWCR9_EL1': A64SysReg.kDBGWCR9_EL1,
  'SysReg::kDBGWVR0_EL1': A64SysReg.kDBGWVR0_EL1,
  'SysReg::kDBGWVR10_EL1': A64SysReg.kDBGWVR10_EL1,
  'SysReg::kDBGWVR11_EL1': A64SysReg.kDBGWVR11_EL1,
  'SysReg::kDBGWVR12_EL1': A64SysReg.kDBGWVR12_EL1,
  'SysReg::kDBGWVR13_EL1': A64SysReg.kDBGWVR13_EL1,
  'SysReg::kDBGWVR14_EL1': A64SysReg.kDBGWVR14_EL1,
  'SysReg::kDBGWVR15_EL1': A64SysReg.kDBGWVR15_EL1,
  'SysReg::kDBGWVR1_EL1': A64SysReg.kDBGWVR1_EL1,
  'SysReg::kDBGWVR2_EL1': A64SysReg.kDBGWVR2_EL1,
  'SysReg::kDBGWVR3_EL1': A64SysReg.kDBGWVR3_EL1,
  'SysReg::kDBGWVR4_EL1': A64SysReg.kDBGWVR4_EL1,
  'SysReg::kDBGWVR5_EL1': A64SysReg.kDBGWVR5_EL1,
  'SysReg::kDBGWVR6_EL1': A64SysReg.kDBGWVR6_EL1,
  'SysReg::kDBGWVR7_EL1': A64SysReg.kDBGWVR7_EL1,
  'SysReg::kDBGWVR8_EL1': A64SysReg.kDBGWVR8_EL1,
  'SysReg::kDBGWVR9_EL1': A64SysReg.kDBGWVR9_EL1,
  'SysReg::kDCZID_EL0': A64SysReg.kDCZID_EL0,
  'SysReg::kDISR_EL1': A64SysReg.kDISR_EL1,
  'SysReg::kDIT': A64SysReg.kDIT,
  'SysReg::kDLR_EL0': A64SysReg.kDLR_EL0,
  'SysReg::kDSPSR_EL0': A64SysReg.kDSPSR_EL0,
  'SysReg::kELR_EL1': A64SysReg.kELR_EL1,
  'SysReg::kELR_EL12': A64SysReg.kELR_EL12,
  'SysReg::kELR_EL2': A64SysReg.kELR_EL2,
  'SysReg::kELR_EL3': A64SysReg.kELR_EL3,
  'SysReg::kERRIDR_EL1': A64SysReg.kERRIDR_EL1,
  'SysReg::kERRSELR_EL1': A64SysReg.kERRSELR_EL1,
  'SysReg::kERXADDR_EL1': A64SysReg.kERXADDR_EL1,
  'SysReg::kERXCTLR_EL1': A64SysReg.kERXCTLR_EL1,
  'SysReg::kERXFR_EL1': A64SysReg.kERXFR_EL1,
  'SysReg::kERXMISC0_EL1': A64SysReg.kERXMISC0_EL1,
  'SysReg::kERXMISC1_EL1': A64SysReg.kERXMISC1_EL1,
  'SysReg::kERXMISC2_EL1': A64SysReg.kERXMISC2_EL1,
  'SysReg::kERXMISC3_EL1': A64SysReg.kERXMISC3_EL1,
  'SysReg::kERXPFGCDN_EL1': A64SysReg.kERXPFGCDN_EL1,
  'SysReg::kERXPFGCTL_EL1': A64SysReg.kERXPFGCTL_EL1,
  'SysReg::kERXPFGF_EL1': A64SysReg.kERXPFGF_EL1,
  'SysReg::kERXSTATUS_EL1': A64SysReg.kERXSTATUS_EL1,
  'SysReg::kESR_EL1': A64SysReg.kESR_EL1,
  'SysReg::kESR_EL12': A64SysReg.kESR_EL12,
  'SysReg::kESR_EL2': A64SysReg.kESR_EL2,
  'SysReg::kESR_EL3': A64SysReg.kESR_EL3,
  'SysReg::kFAR_EL1': A64SysReg.kFAR_EL1,
  'SysReg::kFAR_EL12': A64SysReg.kFAR_EL12,
  'SysReg::kFAR_EL2': A64SysReg.kFAR_EL2,
  'SysReg::kFAR_EL3': A64SysReg.kFAR_EL3,
  'SysReg::kFPCR': A64SysReg.kFPCR,
  'SysReg::kFPEXC32_EL2': A64SysReg.kFPEXC32_EL2,
  'SysReg::kFPSR': A64SysReg.kFPSR,
  'SysReg::kGCR_EL1': A64SysReg.kGCR_EL1,
  'SysReg::kGMID_EL1': A64SysReg.kGMID_EL1,
  'SysReg::kHACR_EL2': A64SysReg.kHACR_EL2,
  'SysReg::kHCR_EL2': A64SysReg.kHCR_EL2,
  'SysReg::kHDFGRTR_EL2': A64SysReg.kHDFGRTR_EL2,
  'SysReg::kHDFGWTR_EL2': A64SysReg.kHDFGWTR_EL2,
  'SysReg::kHFGITR_EL2': A64SysReg.kHFGITR_EL2,
  'SysReg::kHFGRTR_EL2': A64SysReg.kHFGRTR_EL2,
  'SysReg::kHFGWTR_EL2': A64SysReg.kHFGWTR_EL2,
  'SysReg::kHPFAR_EL2': A64SysReg.kHPFAR_EL2,
  'SysReg::kHSTR_EL2': A64SysReg.kHSTR_EL2,
  'SysReg::kICC_AP0R0_EL1': A64SysReg.kICC_AP0R0_EL1,
  'SysReg::kICC_AP0R1_EL1': A64SysReg.kICC_AP0R1_EL1,
  'SysReg::kICC_AP0R2_EL1': A64SysReg.kICC_AP0R2_EL1,
  'SysReg::kICC_AP0R3_EL1': A64SysReg.kICC_AP0R3_EL1,
  'SysReg::kICC_AP1R0_EL1': A64SysReg.kICC_AP1R0_EL1,
  'SysReg::kICC_AP1R1_EL1': A64SysReg.kICC_AP1R1_EL1,
  'SysReg::kICC_AP1R2_EL1': A64SysReg.kICC_AP1R2_EL1,
  'SysReg::kICC_AP1R3_EL1': A64SysReg.kICC_AP1R3_EL1,
  'SysReg::kICC_ASGI1R_EL1': A64SysReg.kICC_ASGI1R_EL1,
  'SysReg::kICC_BPR0_EL1': A64SysReg.kICC_BPR0_EL1,
  'SysReg::kICC_BPR1_EL1': A64SysReg.kICC_BPR1_EL1,
  'SysReg::kICC_CTLR_EL1': A64SysReg.kICC_CTLR_EL1,
  'SysReg::kICC_CTLR_EL3': A64SysReg.kICC_CTLR_EL3,
  'SysReg::kICC_DIR_EL1': A64SysReg.kICC_DIR_EL1,
  'SysReg::kICC_EOIR0_EL1': A64SysReg.kICC_EOIR0_EL1,
  'SysReg::kICC_EOIR1_EL1': A64SysReg.kICC_EOIR1_EL1,
  'SysReg::kICC_HPPIR0_EL1': A64SysReg.kICC_HPPIR0_EL1,
  'SysReg::kICC_HPPIR1_EL1': A64SysReg.kICC_HPPIR1_EL1,
  'SysReg::kICC_IAR0_EL1': A64SysReg.kICC_IAR0_EL1,
  'SysReg::kICC_IAR1_EL1': A64SysReg.kICC_IAR1_EL1,
  'SysReg::kICC_IGRPEN0_EL1': A64SysReg.kICC_IGRPEN0_EL1,
  'SysReg::kICC_IGRPEN1_EL1': A64SysReg.kICC_IGRPEN1_EL1,
  'SysReg::kICC_IGRPEN1_EL3': A64SysReg.kICC_IGRPEN1_EL3,
  'SysReg::kICC_PMR_EL1': A64SysReg.kICC_PMR_EL1,
  'SysReg::kICC_RPR_EL1': A64SysReg.kICC_RPR_EL1,
  'SysReg::kICC_SGI0R_EL1': A64SysReg.kICC_SGI0R_EL1,
  'SysReg::kICC_SGI1R_EL1': A64SysReg.kICC_SGI1R_EL1,
  'SysReg::kICC_SRE_EL1': A64SysReg.kICC_SRE_EL1,
  'SysReg::kICC_SRE_EL2': A64SysReg.kICC_SRE_EL2,
  'SysReg::kICC_SRE_EL3': A64SysReg.kICC_SRE_EL3,
  'SysReg::kICH_AP0R0_EL2': A64SysReg.kICH_AP0R0_EL2,
  'SysReg::kICH_AP0R1_EL2': A64SysReg.kICH_AP0R1_EL2,
  'SysReg::kICH_AP0R2_EL2': A64SysReg.kICH_AP0R2_EL2,
  'SysReg::kICH_AP0R3_EL2': A64SysReg.kICH_AP0R3_EL2,
  'SysReg::kICH_AP1R0_EL2': A64SysReg.kICH_AP1R0_EL2,
  'SysReg::kICH_AP1R1_EL2': A64SysReg.kICH_AP1R1_EL2,
  'SysReg::kICH_AP1R2_EL2': A64SysReg.kICH_AP1R2_EL2,
  'SysReg::kICH_AP1R3_EL2': A64SysReg.kICH_AP1R3_EL2,
  'SysReg::kICH_EISR_EL2': A64SysReg.kICH_EISR_EL2,
  'SysReg::kICH_ELRSR_EL2': A64SysReg.kICH_ELRSR_EL2,
  'SysReg::kICH_HCR_EL2': A64SysReg.kICH_HCR_EL2,
  'SysReg::kICH_LR0_EL2': A64SysReg.kICH_LR0_EL2,
  'SysReg::kICH_LR10_EL2': A64SysReg.kICH_LR10_EL2,
  'SysReg::kICH_LR11_EL2': A64SysReg.kICH_LR11_EL2,
  'SysReg::kICH_LR12_EL2': A64SysReg.kICH_LR12_EL2,
  'SysReg::kICH_LR13_EL2': A64SysReg.kICH_LR13_EL2,
  'SysReg::kICH_LR14_EL2': A64SysReg.kICH_LR14_EL2,
  'SysReg::kICH_LR15_EL2': A64SysReg.kICH_LR15_EL2,
  'SysReg::kICH_LR1_EL2': A64SysReg.kICH_LR1_EL2,
  'SysReg::kICH_LR2_EL2': A64SysReg.kICH_LR2_EL2,
  'SysReg::kICH_LR3_EL2': A64SysReg.kICH_LR3_EL2,
  'SysReg::kICH_LR4_EL2': A64SysReg.kICH_LR4_EL2,
  'SysReg::kICH_LR5_EL2': A64SysReg.kICH_LR5_EL2,
  'SysReg::kICH_LR6_EL2': A64SysReg.kICH_LR6_EL2,
  'SysReg::kICH_LR7_EL2': A64SysReg.kICH_LR7_EL2,
  'SysReg::kICH_LR8_EL2': A64SysReg.kICH_LR8_EL2,
  'SysReg::kICH_LR9_EL2': A64SysReg.kICH_LR9_EL2,
  'SysReg::kICH_MISR_EL2': A64SysReg.kICH_MISR_EL2,
  'SysReg::kICH_VMCR_EL2': A64SysReg.kICH_VMCR_EL2,
  'SysReg::kICH_VTR_EL2': A64SysReg.kICH_VTR_EL2,
  'SysReg::kID_AA64AFR0_EL1': A64SysReg.kID_AA64AFR0_EL1,
  'SysReg::kID_AA64AFR1_EL1': A64SysReg.kID_AA64AFR1_EL1,
  'SysReg::kID_AA64DFR0_EL1': A64SysReg.kID_AA64DFR0_EL1,
  'SysReg::kID_AA64DFR1_EL1': A64SysReg.kID_AA64DFR1_EL1,
  'SysReg::kID_AA64ISAR0_EL1': A64SysReg.kID_AA64ISAR0_EL1,
  'SysReg::kID_AA64ISAR1_EL1': A64SysReg.kID_AA64ISAR1_EL1,
  'SysReg::kID_AA64ISAR2_EL1': A64SysReg.kID_AA64ISAR2_EL1,
  'SysReg::kID_AA64MMFR0_EL1': A64SysReg.kID_AA64MMFR0_EL1,
  'SysReg::kID_AA64MMFR1_EL1': A64SysReg.kID_AA64MMFR1_EL1,
  'SysReg::kID_AA64MMFR2_EL1': A64SysReg.kID_AA64MMFR2_EL1,
  'SysReg::kID_AA64MMFR3_EL1': A64SysReg.kID_AA64MMFR3_EL1,
  'SysReg::kID_AA64MMFR4_EL1': A64SysReg.kID_AA64MMFR4_EL1,
  'SysReg::kID_AA64PFR0_EL1': A64SysReg.kID_AA64PFR0_EL1,
  'SysReg::kID_AA64PFR1_EL1': A64SysReg.kID_AA64PFR1_EL1,
  'SysReg::kID_AA64ZFR0_EL1': A64SysReg.kID_AA64ZFR0_EL1,
  'SysReg::kID_AFR0_EL1': A64SysReg.kID_AFR0_EL1,
  'SysReg::kID_DFR0_EL1': A64SysReg.kID_DFR0_EL1,
  'SysReg::kID_ISAR0_EL1': A64SysReg.kID_ISAR0_EL1,
  'SysReg::kID_ISAR1_EL1': A64SysReg.kID_ISAR1_EL1,
  'SysReg::kID_ISAR2_EL1': A64SysReg.kID_ISAR2_EL1,
  'SysReg::kID_ISAR3_EL1': A64SysReg.kID_ISAR3_EL1,
  'SysReg::kID_ISAR4_EL1': A64SysReg.kID_ISAR4_EL1,
  'SysReg::kID_ISAR5_EL1': A64SysReg.kID_ISAR5_EL1,
  'SysReg::kID_ISAR6_EL1': A64SysReg.kID_ISAR6_EL1,
  'SysReg::kID_MMFR0_EL1': A64SysReg.kID_MMFR0_EL1,
  'SysReg::kID_MMFR1_EL1': A64SysReg.kID_MMFR1_EL1,
  'SysReg::kID_MMFR2_EL1': A64SysReg.kID_MMFR2_EL1,
  'SysReg::kID_MMFR3_EL1': A64SysReg.kID_MMFR3_EL1,
  'SysReg::kID_MMFR4_EL1': A64SysReg.kID_MMFR4_EL1,
  'SysReg::kID_MMFR5_EL1': A64SysReg.kID_MMFR5_EL1,
  'SysReg::kID_PFR0_EL1': A64SysReg.kID_PFR0_EL1,
  'SysReg::kID_PFR1_EL1': A64SysReg.kID_PFR1_EL1,
  'SysReg::kID_PFR2_EL1': A64SysReg.kID_PFR2_EL1,
  'SysReg::kIFSR32_EL2': A64SysReg.kIFSR32_EL2,
  'SysReg::kISR_EL1': A64SysReg.kISR_EL1,
  'SysReg::kLORC_EL1': A64SysReg.kLORC_EL1,
  'SysReg::kLOREA_EL1': A64SysReg.kLOREA_EL1,
  'SysReg::kLORID_EL1': A64SysReg.kLORID_EL1,
  'SysReg::kLORN_EL1': A64SysReg.kLORN_EL1,
  'SysReg::kLORSA_EL1': A64SysReg.kLORSA_EL1,
  'SysReg::kMAIR_EL1': A64SysReg.kMAIR_EL1,
  'SysReg::kMAIR_EL12': A64SysReg.kMAIR_EL12,
  'SysReg::kMAIR_EL2': A64SysReg.kMAIR_EL2,
  'SysReg::kMAIR_EL3': A64SysReg.kMAIR_EL3,
  'SysReg::kMDCCINT_EL1': A64SysReg.kMDCCINT_EL1,
  'SysReg::kMDCCSR_EL0': A64SysReg.kMDCCSR_EL0,
  'SysReg::kMDCR_EL2': A64SysReg.kMDCR_EL2,
  'SysReg::kMDCR_EL3': A64SysReg.kMDCR_EL3,
  'SysReg::kMDRAR_EL1': A64SysReg.kMDRAR_EL1,
  'SysReg::kMDSCR_EL1': A64SysReg.kMDSCR_EL1,
  'SysReg::kMIDR_EL1': A64SysReg.kMIDR_EL1,
  'SysReg::kMPAM0_EL1': A64SysReg.kMPAM0_EL1,
  'SysReg::kMPAM1_EL1': A64SysReg.kMPAM1_EL1,
  'SysReg::kMPAM1_EL12': A64SysReg.kMPAM1_EL12,
  'SysReg::kMPAM2_EL2': A64SysReg.kMPAM2_EL2,
  'SysReg::kMPAM3_EL3': A64SysReg.kMPAM3_EL3,
  'SysReg::kMPAMHCR_EL2': A64SysReg.kMPAMHCR_EL2,
  'SysReg::kMPAMIDR_EL1': A64SysReg.kMPAMIDR_EL1,
  'SysReg::kMPAMVPM0_EL2': A64SysReg.kMPAMVPM0_EL2,
  'SysReg::kMPAMVPM1_EL2': A64SysReg.kMPAMVPM1_EL2,
  'SysReg::kMPAMVPM2_EL2': A64SysReg.kMPAMVPM2_EL2,
  'SysReg::kMPAMVPM3_EL2': A64SysReg.kMPAMVPM3_EL2,
  'SysReg::kMPAMVPM4_EL2': A64SysReg.kMPAMVPM4_EL2,
  'SysReg::kMPAMVPM5_EL2': A64SysReg.kMPAMVPM5_EL2,
  'SysReg::kMPAMVPM6_EL2': A64SysReg.kMPAMVPM6_EL2,
  'SysReg::kMPAMVPM7_EL2': A64SysReg.kMPAMVPM7_EL2,
  'SysReg::kMPAMVPMV_EL2': A64SysReg.kMPAMVPMV_EL2,
  'SysReg::kMPIDR_EL1': A64SysReg.kMPIDR_EL1,
  'SysReg::kMVFR0_EL1': A64SysReg.kMVFR0_EL1,
  'SysReg::kMVFR1_EL1': A64SysReg.kMVFR1_EL1,
  'SysReg::kMVFR2_EL1': A64SysReg.kMVFR2_EL1,
  'SysReg::kNZCV': A64SysReg.kNZCV,
  'SysReg::kOSDLR_EL1': A64SysReg.kOSDLR_EL1,
  'SysReg::kOSDTRRX_EL1': A64SysReg.kOSDTRRX_EL1,
  'SysReg::kOSDTRTX_EL1': A64SysReg.kOSDTRTX_EL1,
  'SysReg::kOSECCR_EL1': A64SysReg.kOSECCR_EL1,
  'SysReg::kOSLAR_EL1': A64SysReg.kOSLAR_EL1,
  'SysReg::kOSLSR_EL1': A64SysReg.kOSLSR_EL1,
  'SysReg::kPAN': A64SysReg.kPAN,
  'SysReg::kPAR_EL1': A64SysReg.kPAR_EL1,
  'SysReg::kPMBIDR_EL1': A64SysReg.kPMBIDR_EL1,
  'SysReg::kPMBLIMITR_EL1': A64SysReg.kPMBLIMITR_EL1,
  'SysReg::kPMBPTR_EL1': A64SysReg.kPMBPTR_EL1,
  'SysReg::kPMBSR_EL1': A64SysReg.kPMBSR_EL1,
  'SysReg::kPMCCFILTR_EL0': A64SysReg.kPMCCFILTR_EL0,
  'SysReg::kPMCCNTR_EL0': A64SysReg.kPMCCNTR_EL0,
  'SysReg::kPMCEID0_EL0': A64SysReg.kPMCEID0_EL0,
  'SysReg::kPMCEID1_EL0': A64SysReg.kPMCEID1_EL0,
  'SysReg::kPMCNTENCLR_EL0': A64SysReg.kPMCNTENCLR_EL0,
  'SysReg::kPMCNTENSET_EL0': A64SysReg.kPMCNTENSET_EL0,
  'SysReg::kPMCR_EL0': A64SysReg.kPMCR_EL0,
  'SysReg::kPMEVCNTR0_EL0': A64SysReg.kPMEVCNTR0_EL0,
  'SysReg::kPMEVCNTR10_EL0': A64SysReg.kPMEVCNTR10_EL0,
  'SysReg::kPMEVCNTR11_EL0': A64SysReg.kPMEVCNTR11_EL0,
  'SysReg::kPMEVCNTR12_EL0': A64SysReg.kPMEVCNTR12_EL0,
  'SysReg::kPMEVCNTR13_EL0': A64SysReg.kPMEVCNTR13_EL0,
  'SysReg::kPMEVCNTR14_EL0': A64SysReg.kPMEVCNTR14_EL0,
  'SysReg::kPMEVCNTR15_EL0': A64SysReg.kPMEVCNTR15_EL0,
  'SysReg::kPMEVCNTR16_EL0': A64SysReg.kPMEVCNTR16_EL0,
  'SysReg::kPMEVCNTR17_EL0': A64SysReg.kPMEVCNTR17_EL0,
  'SysReg::kPMEVCNTR18_EL0': A64SysReg.kPMEVCNTR18_EL0,
  'SysReg::kPMEVCNTR19_EL0': A64SysReg.kPMEVCNTR19_EL0,
  'SysReg::kPMEVCNTR1_EL0': A64SysReg.kPMEVCNTR1_EL0,
  'SysReg::kPMEVCNTR20_EL0': A64SysReg.kPMEVCNTR20_EL0,
  'SysReg::kPMEVCNTR21_EL0': A64SysReg.kPMEVCNTR21_EL0,
  'SysReg::kPMEVCNTR22_EL0': A64SysReg.kPMEVCNTR22_EL0,
  'SysReg::kPMEVCNTR23_EL0': A64SysReg.kPMEVCNTR23_EL0,
  'SysReg::kPMEVCNTR24_EL0': A64SysReg.kPMEVCNTR24_EL0,
  'SysReg::kPMEVCNTR25_EL0': A64SysReg.kPMEVCNTR25_EL0,
  'SysReg::kPMEVCNTR26_EL0': A64SysReg.kPMEVCNTR26_EL0,
  'SysReg::kPMEVCNTR27_EL0': A64SysReg.kPMEVCNTR27_EL0,
  'SysReg::kPMEVCNTR28_EL0': A64SysReg.kPMEVCNTR28_EL0,
  'SysReg::kPMEVCNTR29_EL0': A64SysReg.kPMEVCNTR29_EL0,
  'SysReg::kPMEVCNTR2_EL0': A64SysReg.kPMEVCNTR2_EL0,
  'SysReg::kPMEVCNTR30_EL0': A64SysReg.kPMEVCNTR30_EL0,
  'SysReg::kPMEVCNTR3_EL0': A64SysReg.kPMEVCNTR3_EL0,
  'SysReg::kPMEVCNTR4_EL0': A64SysReg.kPMEVCNTR4_EL0,
  'SysReg::kPMEVCNTR5_EL0': A64SysReg.kPMEVCNTR5_EL0,
  'SysReg::kPMEVCNTR6_EL0': A64SysReg.kPMEVCNTR6_EL0,
  'SysReg::kPMEVCNTR7_EL0': A64SysReg.kPMEVCNTR7_EL0,
  'SysReg::kPMEVCNTR8_EL0': A64SysReg.kPMEVCNTR8_EL0,
  'SysReg::kPMEVCNTR9_EL0': A64SysReg.kPMEVCNTR9_EL0,
  'SysReg::kPMEVTYPER0_EL0': A64SysReg.kPMEVTYPER0_EL0,
  'SysReg::kPMEVTYPER10_EL0': A64SysReg.kPMEVTYPER10_EL0,
  'SysReg::kPMEVTYPER11_EL0': A64SysReg.kPMEVTYPER11_EL0,
  'SysReg::kPMEVTYPER12_EL0': A64SysReg.kPMEVTYPER12_EL0,
  'SysReg::kPMEVTYPER13_EL0': A64SysReg.kPMEVTYPER13_EL0,
  'SysReg::kPMEVTYPER14_EL0': A64SysReg.kPMEVTYPER14_EL0,
  'SysReg::kPMEVTYPER15_EL0': A64SysReg.kPMEVTYPER15_EL0,
  'SysReg::kPMEVTYPER16_EL0': A64SysReg.kPMEVTYPER16_EL0,
  'SysReg::kPMEVTYPER17_EL0': A64SysReg.kPMEVTYPER17_EL0,
  'SysReg::kPMEVTYPER18_EL0': A64SysReg.kPMEVTYPER18_EL0,
  'SysReg::kPMEVTYPER19_EL0': A64SysReg.kPMEVTYPER19_EL0,
  'SysReg::kPMEVTYPER1_EL0': A64SysReg.kPMEVTYPER1_EL0,
  'SysReg::kPMEVTYPER20_EL0': A64SysReg.kPMEVTYPER20_EL0,
  'SysReg::kPMEVTYPER21_EL0': A64SysReg.kPMEVTYPER21_EL0,
  'SysReg::kPMEVTYPER22_EL0': A64SysReg.kPMEVTYPER22_EL0,
  'SysReg::kPMEVTYPER23_EL0': A64SysReg.kPMEVTYPER23_EL0,
  'SysReg::kPMEVTYPER24_EL0': A64SysReg.kPMEVTYPER24_EL0,
  'SysReg::kPMEVTYPER25_EL0': A64SysReg.kPMEVTYPER25_EL0,
  'SysReg::kPMEVTYPER26_EL0': A64SysReg.kPMEVTYPER26_EL0,
  'SysReg::kPMEVTYPER27_EL0': A64SysReg.kPMEVTYPER27_EL0,
  'SysReg::kPMEVTYPER28_EL0': A64SysReg.kPMEVTYPER28_EL0,
  'SysReg::kPMEVTYPER29_EL0': A64SysReg.kPMEVTYPER29_EL0,
  'SysReg::kPMEVTYPER2_EL0': A64SysReg.kPMEVTYPER2_EL0,
  'SysReg::kPMEVTYPER30_EL0': A64SysReg.kPMEVTYPER30_EL0,
  'SysReg::kPMEVTYPER3_EL0': A64SysReg.kPMEVTYPER3_EL0,
  'SysReg::kPMEVTYPER4_EL0': A64SysReg.kPMEVTYPER4_EL0,
  'SysReg::kPMEVTYPER5_EL0': A64SysReg.kPMEVTYPER5_EL0,
  'SysReg::kPMEVTYPER6_EL0': A64SysReg.kPMEVTYPER6_EL0,
  'SysReg::kPMEVTYPER7_EL0': A64SysReg.kPMEVTYPER7_EL0,
  'SysReg::kPMEVTYPER8_EL0': A64SysReg.kPMEVTYPER8_EL0,
  'SysReg::kPMEVTYPER9_EL0': A64SysReg.kPMEVTYPER9_EL0,
  'SysReg::kPMINTENCLR_EL1': A64SysReg.kPMINTENCLR_EL1,
  'SysReg::kPMINTENSET_EL1': A64SysReg.kPMINTENSET_EL1,
  'SysReg::kPMMIR_EL1': A64SysReg.kPMMIR_EL1,
  'SysReg::kPMOVSCLR_EL0': A64SysReg.kPMOVSCLR_EL0,
  'SysReg::kPMOVSSET_EL0': A64SysReg.kPMOVSSET_EL0,
  'SysReg::kPMSCR_EL1': A64SysReg.kPMSCR_EL1,
  'SysReg::kPMSCR_EL12': A64SysReg.kPMSCR_EL12,
  'SysReg::kPMSCR_EL2': A64SysReg.kPMSCR_EL2,
  'SysReg::kPMSELR_EL0': A64SysReg.kPMSELR_EL0,
  'SysReg::kPMSEVFR_EL1': A64SysReg.kPMSEVFR_EL1,
  'SysReg::kPMSFCR_EL1': A64SysReg.kPMSFCR_EL1,
  'SysReg::kPMSICR_EL1': A64SysReg.kPMSICR_EL1,
  'SysReg::kPMSIDR_EL1': A64SysReg.kPMSIDR_EL1,
  'SysReg::kPMSIRR_EL1': A64SysReg.kPMSIRR_EL1,
  'SysReg::kPMSLATFR_EL1': A64SysReg.kPMSLATFR_EL1,
  'SysReg::kPMSWINC_EL0': A64SysReg.kPMSWINC_EL0,
  'SysReg::kPMUSERENR_EL0': A64SysReg.kPMUSERENR_EL0,
  'SysReg::kPMXEVCNTR_EL0': A64SysReg.kPMXEVCNTR_EL0,
  'SysReg::kPMXEVTYPER_EL0': A64SysReg.kPMXEVTYPER_EL0,
  'SysReg::kREVIDR_EL1': A64SysReg.kREVIDR_EL1,
  'SysReg::kRGSR_EL1': A64SysReg.kRGSR_EL1,
  'SysReg::kRMR_EL1': A64SysReg.kRMR_EL1,
  'SysReg::kRMR_EL2': A64SysReg.kRMR_EL2,
  'SysReg::kRMR_EL3': A64SysReg.kRMR_EL3,
  'SysReg::kRNDR': A64SysReg.kRNDR,
  'SysReg::kRNDRRS': A64SysReg.kRNDRRS,
  'SysReg::kRVBAR_EL1': A64SysReg.kRVBAR_EL1,
  'SysReg::kRVBAR_EL2': A64SysReg.kRVBAR_EL2,
  'SysReg::kRVBAR_EL3': A64SysReg.kRVBAR_EL3,
  'SysReg::kSCR_EL3': A64SysReg.kSCR_EL3,
  'SysReg::kSCTLR_EL1': A64SysReg.kSCTLR_EL1,
  'SysReg::kSCTLR_EL12': A64SysReg.kSCTLR_EL12,
  'SysReg::kSCTLR_EL2': A64SysReg.kSCTLR_EL2,
  'SysReg::kSCTLR_EL3': A64SysReg.kSCTLR_EL3,
  'SysReg::kSCXTNUM_EL0': A64SysReg.kSCXTNUM_EL0,
  'SysReg::kSCXTNUM_EL1': A64SysReg.kSCXTNUM_EL1,
  'SysReg::kSCXTNUM_EL12': A64SysReg.kSCXTNUM_EL12,
  'SysReg::kSCXTNUM_EL2': A64SysReg.kSCXTNUM_EL2,
  'SysReg::kSCXTNUM_EL3': A64SysReg.kSCXTNUM_EL3,
  'SysReg::kSDER32_EL2': A64SysReg.kSDER32_EL2,
  'SysReg::kSDER32_EL3': A64SysReg.kSDER32_EL3,
  'SysReg::kSPSR_EL1': A64SysReg.kSPSR_EL1,
  'SysReg::kSPSR_EL12': A64SysReg.kSPSR_EL12,
  'SysReg::kSPSR_EL2': A64SysReg.kSPSR_EL2,
  'SysReg::kSPSR_EL3': A64SysReg.kSPSR_EL3,
  'SysReg::kSPSR_abt': A64SysReg.kSPSR_abt,
  'SysReg::kSPSR_fiq': A64SysReg.kSPSR_fiq,
  'SysReg::kSPSR_irq': A64SysReg.kSPSR_irq,
  'SysReg::kSPSR_und': A64SysReg.kSPSR_und,
  'SysReg::kSPSel': A64SysReg.kSPSel,
  'SysReg::kSP_EL0': A64SysReg.kSP_EL0,
  'SysReg::kSP_EL1': A64SysReg.kSP_EL1,
  'SysReg::kSP_EL2': A64SysReg.kSP_EL2,
  'SysReg::kSSBS': A64SysReg.kSSBS,
  'SysReg::kTCO': A64SysReg.kTCO,
  'SysReg::kTCR_EL1': A64SysReg.kTCR_EL1,
  'SysReg::kTCR_EL12': A64SysReg.kTCR_EL12,
  'SysReg::kTCR_EL2': A64SysReg.kTCR_EL2,
  'SysReg::kTCR_EL3': A64SysReg.kTCR_EL3,
  'SysReg::kTEECR32_EL1': A64SysReg.kTEECR32_EL1,
  'SysReg::kTEEHBR32_EL1': A64SysReg.kTEEHBR32_EL1,
  'SysReg::kTFSRE0_EL1': A64SysReg.kTFSRE0_EL1,
  'SysReg::kTFSR_EL1': A64SysReg.kTFSR_EL1,
  'SysReg::kTFSR_EL12': A64SysReg.kTFSR_EL12,
  'SysReg::kTFSR_EL2': A64SysReg.kTFSR_EL2,
  'SysReg::kTFSR_EL3': A64SysReg.kTFSR_EL3,
  'SysReg::kTPIDRRO_EL0': A64SysReg.kTPIDRRO_EL0,
  'SysReg::kTPIDR_EL0': A64SysReg.kTPIDR_EL0,
  'SysReg::kTPIDR_EL1': A64SysReg.kTPIDR_EL1,
  'SysReg::kTPIDR_EL2': A64SysReg.kTPIDR_EL2,
  'SysReg::kTPIDR_EL3': A64SysReg.kTPIDR_EL3,
  'SysReg::kTRBBASER_EL1': A64SysReg.kTRBBASER_EL1,
  'SysReg::kTRBIDR_EL1': A64SysReg.kTRBIDR_EL1,
  'SysReg::kTRBLIMITR_EL1': A64SysReg.kTRBLIMITR_EL1,
  'SysReg::kTRBMAR_EL1': A64SysReg.kTRBMAR_EL1,
  'SysReg::kTRBPTR_EL1': A64SysReg.kTRBPTR_EL1,
  'SysReg::kTRBSR_EL1': A64SysReg.kTRBSR_EL1,
  'SysReg::kTRBTRG_EL1': A64SysReg.kTRBTRG_EL1,
  'SysReg::kTRCACATR0': A64SysReg.kTRCACATR0,
  'SysReg::kTRCACATR1': A64SysReg.kTRCACATR1,
  'SysReg::kTRCACATR10': A64SysReg.kTRCACATR10,
  'SysReg::kTRCACATR11': A64SysReg.kTRCACATR11,
  'SysReg::kTRCACATR12': A64SysReg.kTRCACATR12,
  'SysReg::kTRCACATR13': A64SysReg.kTRCACATR13,
  'SysReg::kTRCACATR14': A64SysReg.kTRCACATR14,
  'SysReg::kTRCACATR15': A64SysReg.kTRCACATR15,
  'SysReg::kTRCACATR2': A64SysReg.kTRCACATR2,
  'SysReg::kTRCACATR3': A64SysReg.kTRCACATR3,
  'SysReg::kTRCACATR4': A64SysReg.kTRCACATR4,
  'SysReg::kTRCACATR5': A64SysReg.kTRCACATR5,
  'SysReg::kTRCACATR6': A64SysReg.kTRCACATR6,
  'SysReg::kTRCACATR7': A64SysReg.kTRCACATR7,
  'SysReg::kTRCACATR8': A64SysReg.kTRCACATR8,
  'SysReg::kTRCACATR9': A64SysReg.kTRCACATR9,
  'SysReg::kTRCACVR0': A64SysReg.kTRCACVR0,
  'SysReg::kTRCACVR1': A64SysReg.kTRCACVR1,
  'SysReg::kTRCACVR10': A64SysReg.kTRCACVR10,
  'SysReg::kTRCACVR11': A64SysReg.kTRCACVR11,
  'SysReg::kTRCACVR12': A64SysReg.kTRCACVR12,
  'SysReg::kTRCACVR13': A64SysReg.kTRCACVR13,
  'SysReg::kTRCACVR14': A64SysReg.kTRCACVR14,
  'SysReg::kTRCACVR15': A64SysReg.kTRCACVR15,
  'SysReg::kTRCACVR2': A64SysReg.kTRCACVR2,
  'SysReg::kTRCACVR3': A64SysReg.kTRCACVR3,
  'SysReg::kTRCACVR4': A64SysReg.kTRCACVR4,
  'SysReg::kTRCACVR5': A64SysReg.kTRCACVR5,
  'SysReg::kTRCACVR6': A64SysReg.kTRCACVR6,
  'SysReg::kTRCACVR7': A64SysReg.kTRCACVR7,
  'SysReg::kTRCACVR8': A64SysReg.kTRCACVR8,
  'SysReg::kTRCACVR9': A64SysReg.kTRCACVR9,
  'SysReg::kTRCAUTHSTATUS': A64SysReg.kTRCAUTHSTATUS,
  'SysReg::kTRCAUXCTLR': A64SysReg.kTRCAUXCTLR,
  'SysReg::kTRCBBCTLR': A64SysReg.kTRCBBCTLR,
  'SysReg::kTRCCCCTLR': A64SysReg.kTRCCCCTLR,
  'SysReg::kTRCCIDCCTLR0': A64SysReg.kTRCCIDCCTLR0,
  'SysReg::kTRCCIDCCTLR1': A64SysReg.kTRCCIDCCTLR1,
  'SysReg::kTRCCIDCVR0': A64SysReg.kTRCCIDCVR0,
  'SysReg::kTRCCIDCVR1': A64SysReg.kTRCCIDCVR1,
  'SysReg::kTRCCIDCVR2': A64SysReg.kTRCCIDCVR2,
  'SysReg::kTRCCIDCVR3': A64SysReg.kTRCCIDCVR3,
  'SysReg::kTRCCIDCVR4': A64SysReg.kTRCCIDCVR4,
  'SysReg::kTRCCIDCVR5': A64SysReg.kTRCCIDCVR5,
  'SysReg::kTRCCIDCVR6': A64SysReg.kTRCCIDCVR6,
  'SysReg::kTRCCIDCVR7': A64SysReg.kTRCCIDCVR7,
  'SysReg::kTRCCIDR0': A64SysReg.kTRCCIDR0,
  'SysReg::kTRCCIDR1': A64SysReg.kTRCCIDR1,
  'SysReg::kTRCCIDR2': A64SysReg.kTRCCIDR2,
  'SysReg::kTRCCIDR3': A64SysReg.kTRCCIDR3,
  'SysReg::kTRCCLAIMCLR': A64SysReg.kTRCCLAIMCLR,
  'SysReg::kTRCCLAIMSET': A64SysReg.kTRCCLAIMSET,
  'SysReg::kTRCCNTCTLR0': A64SysReg.kTRCCNTCTLR0,
  'SysReg::kTRCCNTCTLR1': A64SysReg.kTRCCNTCTLR1,
  'SysReg::kTRCCNTCTLR2': A64SysReg.kTRCCNTCTLR2,
  'SysReg::kTRCCNTCTLR3': A64SysReg.kTRCCNTCTLR3,
  'SysReg::kTRCCNTRLDVR0': A64SysReg.kTRCCNTRLDVR0,
  'SysReg::kTRCCNTRLDVR1': A64SysReg.kTRCCNTRLDVR1,
  'SysReg::kTRCCNTRLDVR2': A64SysReg.kTRCCNTRLDVR2,
  'SysReg::kTRCCNTRLDVR3': A64SysReg.kTRCCNTRLDVR3,
  'SysReg::kTRCCNTVR0': A64SysReg.kTRCCNTVR0,
  'SysReg::kTRCCNTVR1': A64SysReg.kTRCCNTVR1,
  'SysReg::kTRCCNTVR2': A64SysReg.kTRCCNTVR2,
  'SysReg::kTRCCNTVR3': A64SysReg.kTRCCNTVR3,
  'SysReg::kTRCCONFIGR': A64SysReg.kTRCCONFIGR,
  'SysReg::kTRCDEVAFF0': A64SysReg.kTRCDEVAFF0,
  'SysReg::kTRCDEVAFF1': A64SysReg.kTRCDEVAFF1,
  'SysReg::kTRCDEVARCH': A64SysReg.kTRCDEVARCH,
  'SysReg::kTRCDEVID': A64SysReg.kTRCDEVID,
  'SysReg::kTRCDEVTYPE': A64SysReg.kTRCDEVTYPE,
  'SysReg::kTRCDVCMR0': A64SysReg.kTRCDVCMR0,
  'SysReg::kTRCDVCMR1': A64SysReg.kTRCDVCMR1,
  'SysReg::kTRCDVCMR2': A64SysReg.kTRCDVCMR2,
  'SysReg::kTRCDVCMR3': A64SysReg.kTRCDVCMR3,
  'SysReg::kTRCDVCMR4': A64SysReg.kTRCDVCMR4,
  'SysReg::kTRCDVCMR5': A64SysReg.kTRCDVCMR5,
  'SysReg::kTRCDVCMR6': A64SysReg.kTRCDVCMR6,
  'SysReg::kTRCDVCMR7': A64SysReg.kTRCDVCMR7,
  'SysReg::kTRCDVCVR0': A64SysReg.kTRCDVCVR0,
  'SysReg::kTRCDVCVR1': A64SysReg.kTRCDVCVR1,
  'SysReg::kTRCDVCVR2': A64SysReg.kTRCDVCVR2,
  'SysReg::kTRCDVCVR3': A64SysReg.kTRCDVCVR3,
  'SysReg::kTRCDVCVR4': A64SysReg.kTRCDVCVR4,
  'SysReg::kTRCDVCVR5': A64SysReg.kTRCDVCVR5,
  'SysReg::kTRCDVCVR6': A64SysReg.kTRCDVCVR6,
  'SysReg::kTRCDVCVR7': A64SysReg.kTRCDVCVR7,
  'SysReg::kTRCEVENTCTL0R': A64SysReg.kTRCEVENTCTL0R,
  'SysReg::kTRCEVENTCTL1R': A64SysReg.kTRCEVENTCTL1R,
  'SysReg::kTRCEXTINSELR': A64SysReg.kTRCEXTINSELR,
  'SysReg::kTRCEXTINSELR0': A64SysReg.kTRCEXTINSELR0,
  'SysReg::kTRCEXTINSELR1': A64SysReg.kTRCEXTINSELR1,
  'SysReg::kTRCEXTINSELR2': A64SysReg.kTRCEXTINSELR2,
  'SysReg::kTRCEXTINSELR3': A64SysReg.kTRCEXTINSELR3,
  'SysReg::kTRCIDR0': A64SysReg.kTRCIDR0,
  'SysReg::kTRCIDR1': A64SysReg.kTRCIDR1,
  'SysReg::kTRCIDR10': A64SysReg.kTRCIDR10,
  'SysReg::kTRCIDR11': A64SysReg.kTRCIDR11,
  'SysReg::kTRCIDR12': A64SysReg.kTRCIDR12,
  'SysReg::kTRCIDR13': A64SysReg.kTRCIDR13,
  'SysReg::kTRCIDR2': A64SysReg.kTRCIDR2,
  'SysReg::kTRCIDR3': A64SysReg.kTRCIDR3,
  'SysReg::kTRCIDR4': A64SysReg.kTRCIDR4,
  'SysReg::kTRCIDR5': A64SysReg.kTRCIDR5,
  'SysReg::kTRCIDR6': A64SysReg.kTRCIDR6,
  'SysReg::kTRCIDR7': A64SysReg.kTRCIDR7,
  'SysReg::kTRCIDR8': A64SysReg.kTRCIDR8,
  'SysReg::kTRCIDR9': A64SysReg.kTRCIDR9,
  'SysReg::kTRCIMSPEC0': A64SysReg.kTRCIMSPEC0,
  'SysReg::kTRCIMSPEC1': A64SysReg.kTRCIMSPEC1,
  'SysReg::kTRCIMSPEC2': A64SysReg.kTRCIMSPEC2,
  'SysReg::kTRCIMSPEC3': A64SysReg.kTRCIMSPEC3,
  'SysReg::kTRCIMSPEC4': A64SysReg.kTRCIMSPEC4,
  'SysReg::kTRCIMSPEC5': A64SysReg.kTRCIMSPEC5,
  'SysReg::kTRCIMSPEC6': A64SysReg.kTRCIMSPEC6,
  'SysReg::kTRCIMSPEC7': A64SysReg.kTRCIMSPEC7,
  'SysReg::kTRCITCTRL': A64SysReg.kTRCITCTRL,
  'SysReg::kTRCLAR': A64SysReg.kTRCLAR,
  'SysReg::kTRCLSR': A64SysReg.kTRCLSR,
  'SysReg::kTRCOSLAR': A64SysReg.kTRCOSLAR,
  'SysReg::kTRCOSLSR': A64SysReg.kTRCOSLSR,
  'SysReg::kTRCPDCR': A64SysReg.kTRCPDCR,
  'SysReg::kTRCPDSR': A64SysReg.kTRCPDSR,
  'SysReg::kTRCPIDR0': A64SysReg.kTRCPIDR0,
  'SysReg::kTRCPIDR1': A64SysReg.kTRCPIDR1,
  'SysReg::kTRCPIDR2': A64SysReg.kTRCPIDR2,
  'SysReg::kTRCPIDR3': A64SysReg.kTRCPIDR3,
  'SysReg::kTRCPIDR4': A64SysReg.kTRCPIDR4,
  'SysReg::kTRCPIDR5': A64SysReg.kTRCPIDR5,
  'SysReg::kTRCPIDR6': A64SysReg.kTRCPIDR6,
  'SysReg::kTRCPIDR7': A64SysReg.kTRCPIDR7,
  'SysReg::kTRCPRGCTLR': A64SysReg.kTRCPRGCTLR,
  'SysReg::kTRCPROCSELR': A64SysReg.kTRCPROCSELR,
  'SysReg::kTRCQCTLR': A64SysReg.kTRCQCTLR,
  'SysReg::kTRCRSCTLR10': A64SysReg.kTRCRSCTLR10,
  'SysReg::kTRCRSCTLR11': A64SysReg.kTRCRSCTLR11,
  'SysReg::kTRCRSCTLR12': A64SysReg.kTRCRSCTLR12,
  'SysReg::kTRCRSCTLR13': A64SysReg.kTRCRSCTLR13,
  'SysReg::kTRCRSCTLR14': A64SysReg.kTRCRSCTLR14,
  'SysReg::kTRCRSCTLR15': A64SysReg.kTRCRSCTLR15,
  'SysReg::kTRCRSCTLR16': A64SysReg.kTRCRSCTLR16,
  'SysReg::kTRCRSCTLR17': A64SysReg.kTRCRSCTLR17,
  'SysReg::kTRCRSCTLR18': A64SysReg.kTRCRSCTLR18,
  'SysReg::kTRCRSCTLR19': A64SysReg.kTRCRSCTLR19,
  'SysReg::kTRCRSCTLR2': A64SysReg.kTRCRSCTLR2,
  'SysReg::kTRCRSCTLR20': A64SysReg.kTRCRSCTLR20,
  'SysReg::kTRCRSCTLR21': A64SysReg.kTRCRSCTLR21,
  'SysReg::kTRCRSCTLR22': A64SysReg.kTRCRSCTLR22,
  'SysReg::kTRCRSCTLR23': A64SysReg.kTRCRSCTLR23,
  'SysReg::kTRCRSCTLR24': A64SysReg.kTRCRSCTLR24,
  'SysReg::kTRCRSCTLR25': A64SysReg.kTRCRSCTLR25,
  'SysReg::kTRCRSCTLR26': A64SysReg.kTRCRSCTLR26,
  'SysReg::kTRCRSCTLR27': A64SysReg.kTRCRSCTLR27,
  'SysReg::kTRCRSCTLR28': A64SysReg.kTRCRSCTLR28,
  'SysReg::kTRCRSCTLR29': A64SysReg.kTRCRSCTLR29,
  'SysReg::kTRCRSCTLR3': A64SysReg.kTRCRSCTLR3,
  'SysReg::kTRCRSCTLR30': A64SysReg.kTRCRSCTLR30,
  'SysReg::kTRCRSCTLR31': A64SysReg.kTRCRSCTLR31,
  'SysReg::kTRCRSCTLR4': A64SysReg.kTRCRSCTLR4,
  'SysReg::kTRCRSCTLR5': A64SysReg.kTRCRSCTLR5,
  'SysReg::kTRCRSCTLR6': A64SysReg.kTRCRSCTLR6,
  'SysReg::kTRCRSCTLR7': A64SysReg.kTRCRSCTLR7,
  'SysReg::kTRCRSCTLR8': A64SysReg.kTRCRSCTLR8,
  'SysReg::kTRCRSCTLR9': A64SysReg.kTRCRSCTLR9,
  'SysReg::kTRCRSR': A64SysReg.kTRCRSR,
  'SysReg::kTRCSEQEVR0': A64SysReg.kTRCSEQEVR0,
  'SysReg::kTRCSEQEVR1': A64SysReg.kTRCSEQEVR1,
  'SysReg::kTRCSEQEVR2': A64SysReg.kTRCSEQEVR2,
  'SysReg::kTRCSEQRSTEVR': A64SysReg.kTRCSEQRSTEVR,
  'SysReg::kTRCSEQSTR': A64SysReg.kTRCSEQSTR,
  'SysReg::kTRCSSCCR0': A64SysReg.kTRCSSCCR0,
  'SysReg::kTRCSSCCR1': A64SysReg.kTRCSSCCR1,
  'SysReg::kTRCSSCCR2': A64SysReg.kTRCSSCCR2,
  'SysReg::kTRCSSCCR3': A64SysReg.kTRCSSCCR3,
  'SysReg::kTRCSSCCR4': A64SysReg.kTRCSSCCR4,
  'SysReg::kTRCSSCCR5': A64SysReg.kTRCSSCCR5,
  'SysReg::kTRCSSCCR6': A64SysReg.kTRCSSCCR6,
  'SysReg::kTRCSSCCR7': A64SysReg.kTRCSSCCR7,
  'SysReg::kTRCSSCSR0': A64SysReg.kTRCSSCSR0,
  'SysReg::kTRCSSCSR1': A64SysReg.kTRCSSCSR1,
  'SysReg::kTRCSSCSR2': A64SysReg.kTRCSSCSR2,
  'SysReg::kTRCSSCSR3': A64SysReg.kTRCSSCSR3,
  'SysReg::kTRCSSCSR4': A64SysReg.kTRCSSCSR4,
  'SysReg::kTRCSSCSR5': A64SysReg.kTRCSSCSR5,
  'SysReg::kTRCSSCSR6': A64SysReg.kTRCSSCSR6,
  'SysReg::kTRCSSCSR7': A64SysReg.kTRCSSCSR7,
  'SysReg::kTRCSSPCICR0': A64SysReg.kTRCSSPCICR0,
  'SysReg::kTRCSSPCICR1': A64SysReg.kTRCSSPCICR1,
  'SysReg::kTRCSSPCICR2': A64SysReg.kTRCSSPCICR2,
  'SysReg::kTRCSSPCICR3': A64SysReg.kTRCSSPCICR3,
  'SysReg::kTRCSSPCICR4': A64SysReg.kTRCSSPCICR4,
  'SysReg::kTRCSSPCICR5': A64SysReg.kTRCSSPCICR5,
  'SysReg::kTRCSSPCICR6': A64SysReg.kTRCSSPCICR6,
  'SysReg::kTRCSSPCICR7': A64SysReg.kTRCSSPCICR7,
  'SysReg::kTRCSTALLCTLR': A64SysReg.kTRCSTALLCTLR,
  'SysReg::kTRCSTATR': A64SysReg.kTRCSTATR,
  'SysReg::kTRCSYNCPR': A64SysReg.kTRCSYNCPR,
  'SysReg::kTRCTRACEIDR': A64SysReg.kTRCTRACEIDR,
  'SysReg::kTRCTSCTLR': A64SysReg.kTRCTSCTLR,
  'SysReg::kTRCVDARCCTLR': A64SysReg.kTRCVDARCCTLR,
  'SysReg::kTRCVDCTLR': A64SysReg.kTRCVDCTLR,
  'SysReg::kTRCVDSACCTLR': A64SysReg.kTRCVDSACCTLR,
  'SysReg::kTRCVICTLR': A64SysReg.kTRCVICTLR,
  'SysReg::kTRCVIIECTLR': A64SysReg.kTRCVIIECTLR,
  'SysReg::kTRCVIPCSSCTLR': A64SysReg.kTRCVIPCSSCTLR,
  'SysReg::kTRCVISSCTLR': A64SysReg.kTRCVISSCTLR,
  'SysReg::kTRCVMIDCCTLR0': A64SysReg.kTRCVMIDCCTLR0,
  'SysReg::kTRCVMIDCCTLR1': A64SysReg.kTRCVMIDCCTLR1,
  'SysReg::kTRCVMIDCVR0': A64SysReg.kTRCVMIDCVR0,
  'SysReg::kTRCVMIDCVR1': A64SysReg.kTRCVMIDCVR1,
  'SysReg::kTRCVMIDCVR2': A64SysReg.kTRCVMIDCVR2,
  'SysReg::kTRCVMIDCVR3': A64SysReg.kTRCVMIDCVR3,
  'SysReg::kTRCVMIDCVR4': A64SysReg.kTRCVMIDCVR4,
  'SysReg::kTRCVMIDCVR5': A64SysReg.kTRCVMIDCVR5,
  'SysReg::kTRCVMIDCVR6': A64SysReg.kTRCVMIDCVR6,
  'SysReg::kTRCVMIDCVR7': A64SysReg.kTRCVMIDCVR7,
  'SysReg::kTRFCR_EL1': A64SysReg.kTRFCR_EL1,
  'SysReg::kTRFCR_EL12': A64SysReg.kTRFCR_EL12,
  'SysReg::kTRFCR_EL2': A64SysReg.kTRFCR_EL2,
  'SysReg::kTTBR0_EL1': A64SysReg.kTTBR0_EL1,
  'SysReg::kTTBR0_EL12': A64SysReg.kTTBR0_EL12,
  'SysReg::kTTBR0_EL2': A64SysReg.kTTBR0_EL2,
  'SysReg::kTTBR0_EL3': A64SysReg.kTTBR0_EL3,
  'SysReg::kTTBR1_EL1': A64SysReg.kTTBR1_EL1,
  'SysReg::kTTBR1_EL12': A64SysReg.kTTBR1_EL12,
  'SysReg::kTTBR1_EL2': A64SysReg.kTTBR1_EL2,
  'SysReg::kUAO': A64SysReg.kUAO,
  'SysReg::kVBAR_EL1': A64SysReg.kVBAR_EL1,
  'SysReg::kVBAR_EL12': A64SysReg.kVBAR_EL12,
  'SysReg::kVBAR_EL2': A64SysReg.kVBAR_EL2,
  'SysReg::kVBAR_EL3': A64SysReg.kVBAR_EL3,
  'SysReg::kVDISR_EL2': A64SysReg.kVDISR_EL2,
  'SysReg::kVMPIDR_EL2': A64SysReg.kVMPIDR_EL2,
  'SysReg::kVNCR_EL2': A64SysReg.kVNCR_EL2,
  'SysReg::kVPIDR_EL2': A64SysReg.kVPIDR_EL2,
  'SysReg::kVSESR_EL2': A64SysReg.kVSESR_EL2,
  'SysReg::kVSTCR_EL2': A64SysReg.kVSTCR_EL2,
  'SysReg::kVSTTBR_EL2': A64SysReg.kVSTTBR_EL2,
  'SysReg::kVTCR_EL2': A64SysReg.kVTCR_EL2,
  'SysReg::kVTTBR_EL2': A64SysReg.kVTTBR_EL2,
  'SysReg::kZCR_EL1': A64SysReg.kZCR_EL1,
  'SysReg::kZCR_EL12': A64SysReg.kZCR_EL12,
  'SysReg::kZCR_EL2': A64SysReg.kZCR_EL2,
  'SysReg::kZCR_EL3': A64SysReg.kZCR_EL3,
};
