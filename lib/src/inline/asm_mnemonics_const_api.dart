// C:\MyDartProjects\asmjit\lib\src\inline\asm_mnemonics_const_api.dart
// Assembly Mnemonics & Constants (API Híbrida: Legado + Completa)

// =============================================================================
//  1. REGISTRADORES (Índices para ModR/M)
// =============================================================================
const int rax = 0;
const int rcx = 1;
const int rdx = 2;
const int rbx = 3;
const int rsp = 4;
const int rbp = 5;
const int rsi = 6;
const int rdi = 7;
// R8-R15 usam os mesmos índices 0-7 combinados com prefixos REX

// =============================================================================
//  2. PREFIXOS
// =============================================================================
const int rex_w = 0x48; // 64-bit operand
const int rex_wb = 0x49; // 64-bit + Base Reg Ext
const int rex_wr = 0x4C; // 64-bit + Reg Ext
const int rex_wrb = 0x4D; // 64-bit + Reg Ext + Base Ext
const int rex_r = 0x44; // Reg extension (SSE/GPR)
const int rex_b = 0x41; // Base extension
const int rex_rb = 0x45; // Reg + Base extension
const int sse = 0x66; // Operand Size Override
const int x0f = 0x0F; // Escape 2-byte
const int lock = 0xF0; // Lock prefix

// =============================================================================
//  3. LEGADO / COMPATIBILIDADE (Não remover - Usado pelo ChaCha20 atual)
// =============================================================================
const int push_rbx = 0x53;
const int pop_rbx = 0x5B;
const int push_rsp = 0x54;
const int pop_rsp = 0x5C;
const int push_rbp = 0x55;
const int pop_rbp = 0x5D;
const int ret = 0xC3;

const int sub_rm64 = 0x81; // opcode group 81 /5
const int add_rm64 = 0x81; // opcode group 81 /0
const int mov_r_rm = 0x8B; // Load
const int mov_rm_r = 0x89; // Store
const int mov_eax = 0xB8; // mov eax, imm32
const int mov_ecx = 0xB9; // mov ecx, imm32
const int dec_ecx = 0xC9; // Requer FF antes (FF C9)
const int jnz_rel = 0x85; // Requer 0F antes (0F 85)
const int cpuid = 0xA2; // Requer 0F antes (0F A2)

// =============================================================================
//  4. STACK & MOVIMENTAÇÃO (Expandido)
// =============================================================================
const int push_r64 = 0x50; // +rd (ex: 50+0 = push rax)
const int pop_r64 = 0x58; // +rd (ex: 58+0 = pop rax)
const int push_imm32 = 0x68;
const int push_imm8 = 0x6A;
const int leave = 0xC9;
const int nop = 0x90;

const int mov_rm_imm = 0xC7; // MOV [mem], imm32
const int mov_r_imm = 0xB8; // +rd: MOV reg, imm32/64
const int mov_rm8_r8 = 0x88;
const int mov_r8_rm8 = 0x8A;
const int mov_r8_imm = 0xB0; // +rd

// =============================================================================
//  5. ARITMÉTICA E LÓGICA (ALU Expandido)
// =============================================================================
// Grupos imediatos (requerem /digit)
const int alu_rm_imm32 = 0x81;
const int alu_rm_imm8 = 0x83;

// Operações Padrão
const int add_rm_r = 0x01;
const int add_r_rm = 0x03;
const int sub_rm_r = 0x29;
const int sub_r_rm = 0x2B;
const int and_rm_r = 0x21;
const int and_r_rm = 0x23;
const int or_rm_r = 0x09;
const int or_r_rm = 0x0B;
const int xor_rm_r = 0x31;
const int xor_r_rm = 0x33;
const int cmp_rm_r = 0x39;
const int cmp_r_rm = 0x3B;
const int test_rm_r = 0x85;

// Grupos Especiais
const int grp_ff = 0xFF; // INC, DEC, CALL, JMP, PUSH
const int grp_f7 = 0xF7; // MUL, DIV, NEG, NOT, TEST

// =============================================================================
//  6. SHIFTS E ROTAÇÕES
// =============================================================================
const int shift_1 = 0xD1;
const int shift_cl = 0xD3;
const int shift_imm_ib = 0xC1; // Shift reg, imm8 (Inteiros genéricos)

// =============================================================================
//  7. CONTROLE DE FLUXO (JUMPS)
// =============================================================================
const int jmp_rel8 = 0xEB;
const int jmp_rel32 = 0xE9;

// Short Jumps (8-bit relative)
const int jo_s = 0x70;
const int jno_s = 0x71;
const int jb_s = 0x72;
const int jae_s = 0x73;
const int je_s = 0x74;
const int jne_s = 0x75;
const int jbe_s = 0x76;
const int ja_s = 0x77;
const int js_s = 0x78;
const int jns_s = 0x79;
const int jl_s = 0x7C;
const int jge_s = 0x7D;
const int jle_s = 0x7E;
const int jg_s = 0x7F;

// Near Jumps (32-bit relative - Requerem 0F antes)
const int je_near = 0x84;
const int jne_near = 0x85; // Alias para jnz_rel

// =============================================================================
//  8. SSE2 / SIMD (Completo)
// =============================================================================
// Legado (usado no ChaCha)
const int movups = 0x10;
const int movups_st = 0x11;
const int movaps = 0x28;
const int movaps_st = 0x29;
const int movdqa = 0x6F; // Load aligned int
const int pshufd = 0x70;
const int paddd = 0xFE;
const int pxor = 0xEF;
const int por = 0xEB;
const int shift_imm = 0x72; // Grupo Shift SSE Imediato (PSLLD, PSRLD, PSRAD)

// Expandido
const int movd = 0x6E; // GPR -> XMM
const int movd_st = 0x7E; // XMM -> GPR
const int movq = 0xD6; // XMM low 64 -> Mem
const int movdqu = 0x6F; // (F3 0F)
const int movdqu_st = 0x7F; // (F3 0F)

const int paddb = 0xFC;
const int paddw = 0xFD;
const int paddq = 0xD4;
const int psubb = 0xF8;
const int psubw = 0xF9;
const int psubd = 0xFA;
const int psubq = 0xFB;

const int pand = 0xDB;
const int pandn = 0xDF;

const int psllw = 0xF1;
const int pslld = 0xF2; // Shift Register
const int psllq = 0xF3;
const int psrlw = 0xD1;
const int psrld = 0xD2; // Shift Register
const int psrlq = 0xD3;
const int pshift_imm_q = 0x73; // Grupo Shift QWord

// =============================================================================
//  9. HELPERS / EXTENSION DIGITS (Para campo Reg do ModRM)
// =============================================================================
// ALU
const int digit_add = 0;
const int digit_or = 1;
const int digit_adc = 2;
const int digit_sbb = 3;
const int digit_and = 4;
const int digit_sub = 5;
const int digit_xor = 6;
const int digit_cmp = 7;

// Shifts
const int digit_rol = 0;
const int digit_ror = 1;
const int digit_shl = 4;
const int digit_shr = 5;
const int digit_sar = 7;

// Unary (Grps FF/F7)
const int digit_inc = 0;
const int digit_dec = 1;
const int digit_call = 2;
const int digit_jmp = 4;
const int digit_push = 6;
const int digit_not = 2;
const int digit_neg = 3;
const int digit_mul = 4;

// ModR/M Offsets Comuns
const int rsp_disp = 0x24; // [RSP + disp]
