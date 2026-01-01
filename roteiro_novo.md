# Roteiro de Portação: AsmJit C++ → Dart

**Última Atualização**: 2026-01-01
continue lendo o codigo fonte c++ C:\MyDartProjects\asmjit\referencias\asmjit-master e portando

foco em 64 bits 
## 📊 Status Atual

| Componente | Status | Testes |
|------------|--------|--------|
| Core (CodeHolder, Buffer, Runtime) | ✅ Funcional | 635 passando |
| x86 Assembler | ✅ ~80% | +50 instrucoes (SSE FP) |
| x86 Encoder | ✅ ~90% | Byte-to-byte pass |
| A64 Assembler | ⚠️ ~20% | Básico |
| Compiler Base | ⚠️ ~50% | Básico |
| RALocal | ✅ Implementado | Funcional |
| RAGlobal | 🔴 Em progresso | Inicial | em C:\MyDartProjects\asmjit\lib\src\asmjit\core\ralocal.dart
C:\MyDartProjects\asmjit\lib\src\asmjit\core\rapass.dart
C:\MyDartProjects\asmjit\lib\src\asmjit\core\rablock.dart
C:\MyDartProjects\asmjit\lib\src\asmjit\core\radefs.dart

AsmJit Builder - Intermediate Representation
C:\MyDartProjects\asmjit\lib\src\asmjit\core\builder.dart
---

## ✅ Progresso Recente (01/01/2026)

### Instruções Implementadas Nesta Sessão:

1. **Bit Test and Set/Reset (bts, btr)**:
   - `btsRI(reg, imm8)` - Bit test and set com imediato
   - `btsRR(reg, reg)` - Bit test and set com registrador
   - `btrRI(reg, imm8)` - Bit test and reset com imediato
   - `btrRR(reg, reg)` - Bit test and reset com registrador

2. **Sign Extension**:
   - `cbw()` - Convert byte to word (AL → AX)
   - `cwde()` - Convert word to doubleword (AX → EAX)
   - `cdqe()` - Convert doubleword to quadword (EAX → RAX)
   - `cwd()` - Convert word to doubleword (AX → DX:AX)

3. **Correções de 64 bits**:
   - `btRI`, `btRR`, `btcRI`, `btcRR` agora suportam operandos de 64 bits
   - `bswapR` agora suporta 16, 32 e 64 bits

4. **Novos Testes**: 23 testes adicionados para bt/bts/bswap/cbw/cdqe/cdq/cqo/clc/cld/cmc/stc/std

5. **SSE2 Packed Integer Core**:
   - `paddb/w/d/q`, `psubb/w/d/q` (Add/Sub packed integers)
   - `pmullw/d`, `pmulhw/huw`, `pmaddwd` (Multiply packed integers)
   - `pcmpeqb/w/d/q`, `pcmpgtb/w/d/q` (Compare packed integers)
   - `pminub/uw/ud`, `pmaxub/uw/ud`, `pminsb/sw/sd`, `pmaxsb/sw/sd` (Min/Max packed integers)
   - `psllw/d/q`, `psrlw/d/q`, `psraw/d` (Shift packed integers)
   - `pslldq`, `psrldq` (Byte shifts)
   - `pand/n`, `por`, `pxor` (Logic)
   - `pack*`, `punpck*` (Pack/Unpack)
   - `pshuf*`, `palignr` (Shuffle)

---

## 🎯 Análise Profunda: Instruções Necessárias para Blend2D

Baseado na análise de `C:\MyDartProjects\asmjit\referencias\blend2d-master\blend2d\pipeline\jit\*` e `blend2d\simd\simdx86_p.h` (405KB), identificamos as seguintes categorias de instruções críticas:

### 🔴 INSTRUÇÕES SSE/SSE2 ESSENCIAIS (Prioridade Máxima)

O Blend2D usa massivamente SIMD para processamento de pixels. As instruções abaixo são **obrigatórias**:

#### 1. Packed Integer Arithmetic (SSE2)
```
paddb, paddw, paddd, paddq          - Add packed integers
psubb, psubw, psubd, psubq          - Subtract packed integers
pmullw, pmulld                       - Multiply low packed integers
pmulhw, pmulhuw                      - Multiply high packed integers
pmaddwd                              - Multiply and add
pabsb, pabsw, pabsd                  - Absolute value
psadbw                               - Sum of absolute differences
```

#### 2. Packed Integer Comparison (SSE2)
```
pcmpeqb, pcmpeqw, pcmpeqd, pcmpeqq  - Compare equal
pcmpgtb, pcmpgtw, pcmpgtd, pcmpgtq  - Compare greater than
```

#### 3. Packed Integer Min/Max (SSE2/SSE4.1)
```
pminub, pminuw, pminud              - Minimum unsigned
pmaxub, pmaxuw, pmaxud              - Maximum unsigned
pminsb, pminsw, pminsd              - Minimum signed
pmaxsb, pmaxsw, pmaxsd              - Maximum signed
```

#### 4. Packed Integer Shift (SSE2)
```
psllw, pslld, psllq                 - Logical shift left
psrlw, psrld, psrlq                 - Logical shift right
psraw, psrad                         - Arithmetic shift right
pslldq, psrldq                       - Shift bytes (128-bit)
```

#### 5. Packed Integer Logic (SSE2)
```
pand, pandn, por, pxor              - Bitwise operations
```

#### 6. Shuffle/Permute (SSE2/SSSE3/SSE4.1)
```
pshufd, pshufb, pshuflw, pshufhw   - Shuffle
punpcklbw, punpckhbw                - Unpack low/high bytes
punpcklwd, punpckhwd                - Unpack low/high words
punpckldq, punpckhdq                - Unpack low/high dwords
punpcklqdq, punpckhqdq              - Unpack low/high qwords
palignr                              - Packed align right (SSSE3)
```

#### 7. Conversion (SSE2/SSE4.1)
```
cvtdq2ps, cvtps2dq                  - Int32 <-> Float32
cvttps2dq                            - Truncate Float32 to Int32
packsswb, packssdw                  - Pack with signed saturation
packuswb, packusdw                  - Pack with unsigned saturation
pmovsxbw, pmovzxbw                  - Sign/Zero extend bytes to words
pmovsxwd, pmovzxwd                  - Sign/Zero extend words to dwords
```

#### 8. Load/Store (SSE2)
```
movdqa, movdqu                       - Move aligned/unaligned 128-bit
movd, movq                           - Move 32/64-bit to/from XMM
```

#### 9. Insert/Extract (SSE4.1)
```
pinsrb, pinsrw, pinsrd, pinsrq     - Insert byte/word/dword/qword
pextrb, pextrw, pextrd, pextrq     - Extract byte/word/dword/qword
insertps, extractps                  - Insert/extract float
```

#### 10. Blend (SSE4.1)
```
pblendw, pblendvb, blendps, blendvps
```

### 🟡 INSTRUÇÕES SSE FLOATING-POINT (Prioridade Alta)

Para renderização com gradient e filtros:

```
addps, addss, addpd, addsd          - Add
subps, subss, subpd, subsd          - Subtract
mulps, mulss, mulpd, mulsd          - Multiply
divps, divss, divpd, divsd          - Divide
sqrtps, sqrtss, sqrtpd, sqrtsd      - Square root
rcpps, rcpss                         - Reciprocal estimate
rsqrtps, rsqrtss                     - Reciprocal square root estimate
minps, maxps, minss, maxss          - Min/Max
cmpps, cmpss, cmppd, cmpsd          - Compare
```

### 🟠 INSTRUÇÕES AVX/AVX2 (Prioridade Média)

Para performance 256-bit:

```
vpmaddubsw, vpmaddwd                 - Multiply-add 
vpshufb, vpermd, vpermq              - Shuffle/Permute
vpmaskmovd, vmaskmovps               - Masked load/store
vbroadcast*, vpbroadcast*            - Broadcast
vextracti128, vinserti128            - Extract/Insert 128-bit
```

### 🔵 INSTRUÇÕES AVX-512 (Prioridade Baixa)

Para uso futuro com AVX-512:

```
vpternlogd                           - Ternary logic
vpmovzxbd, vpmovsxbd                 - Zero/Sign extend
k* (mask operations)                 - Mask register operations
```

---

## 📋 Lista de Tarefas para Suportar Blend2D

### Fase 1: SSE2/SSE4.1 Core (CRÍTICO para Pipeline Mínimo)

- [x] **Packed Integer Add/Sub**:
  - [x] `paddb(xmm, xmm/mem)` - Add packed bytes
  - [x] `paddw(xmm, xmm/mem)` - Add packed words
  - [x] `paddd(xmm, xmm/mem)` - Add packed dwords
  - [x] `paddq(xmm, xmm/mem)` - Add packed qwords
  - [x] `psubb(xmm, xmm/mem)` - Sub packed bytes
  - [x] `psubw(xmm, xmm/mem)` - Sub packed words
  - [x] `psubd(xmm, xmm/mem)` - Sub packed dwords
  - [x] `psubq(xmm, xmm/mem)` - Sub packed qwords

- [x] **Packed Integer Multiply**:
  - [x] `pmullw(xmm, xmm/mem)` - Multiply low words
  - [x] `pmulld(xmm, xmm/mem)` - Multiply low dwords (SSE4.1)
  - [x] `pmulhw(xmm, xmm/mem)` - Multiply high signed words
  - [x] `pmulhuw(xmm, xmm/mem)` - Multiply high unsigned words
  - [x] `pmaddwd(xmm, xmm/mem)` - Multiply and add
  - [x] `pmaddubsw(xmm, xmm/mem)` - Multiply and add unsigned/signed (SSSE3)

- [x] **Packed Integer Compare**:
  - [x] `pcmpeqb/w/d/q(xmm, xmm/mem)` - Compare equal
  - [x] `pcmpgtb/w/d/q(xmm, xmm/mem)` - Compare greater than

- [x] **Packed Integer Min/Max**:
  - [x] `pminub/uw/ud(xmm, xmm/mem)` - Minimum unsigned
  - [x] `pmaxub/uw/ud(xmm, xmm/mem)` - Maximum unsigned  
  - [x] `pminsb/sw/sd(xmm, xmm/mem)` - Minimum signed
  - [x] `pmaxsb/sw/sd(xmm, xmm/mem)` - Maximum signed

- [x] **Packed Integer Shift**:
  - [x] `psllw/d/q(xmm, xmm/imm)` - Shift left logical
  - [x] `psrlw/d/q(xmm, xmm/imm)` - Shift right logical
  - [x] `psraw/d(xmm, xmm/imm)` - Shift right arithmetic
  - [x] `pslldq(xmm, imm)` - Shift bytes left
  - [x] `psrldq(xmm, imm)` - Shift bytes right

- [x] **Packed Integer Logic**:
  - [x] `pand(xmm, xmm/mem)` - Bitwise AND
  - [x] `pandn(xmm, xmm/mem)` - Bitwise AND NOT
  - [x] `por(xmm, xmm/mem)` - Bitwise OR
  - [x] `pxor(xmm, xmm/mem)` - Bitwise XOR

- [x] **Pack/Unpack**:
  - [x] `packsswb/dw(xmm, xmm/mem)` - Pack with signed saturation
  - [x] `packuswb/dw(xmm, xmm/mem)` - Pack with unsigned saturation
  - [x] `punpcklbw/wd/dq/qdq(xmm, xmm/mem)` - Unpack low
  - [x] `punpckhbw/wd/dq/qdq(xmm, xmm/mem)` - Unpack high

- [x] **Shuffle**:
  - [x] `pshufd(xmm, xmm/mem, imm)` - Shuffle dwords
  - [x] `pshufb(xmm, xmm/mem)` - Shuffle bytes (SSSE3)
  - [x] `pshuflw/hw(xmm, xmm/mem, imm)` - Shuffle low/high words
  - [x] `palignr(xmm, xmm/mem, imm)` - Align bytes (SSSE3)

- [x] **Extend (SSE4.1)**:
  - [x] `pmovzxbw/bd/bq(xmm, xmm/mem)` - Zero extend
  - [x] `pmovzxwd/wq/dq(xmm, xmm/mem)` - Zero extend
  - [x] `pmovsxbw/bd/bq(xmm, xmm/mem)` - Sign extend
  - [x] `pmovsxwd/wq/dq(xmm, xmm/mem)` - Sign extend

- [x] **Insert/Extract (SSE4.1)**:
  - [x] `pinsrb/w/d/q(xmm, r/m, imm)` - Insert
  - [x] `pextrb/w/d/q(r/m, xmm, imm)` - Extract

- [x] **Blend (SSE4.1)**:
  - [x] `pblendw(xmm, xmm/mem, imm)` - Blend words
  - [x] `blendps/pd(xmm, xmm/mem, imm)` - Blend float/double
  - [x] `pblendvb(xmm, xmm/mem, xmm0)` - Variable blend bytes

- [x] **SSE Floating Point (Completo)**:
  - [x] **Scalar Arithmetic**: `addss/sd`, `subss/sd`, `mulss/sd`, `divss/sd`, `sqrtss/sd`
  - [x] **Packed Arithmetic**: `addps/pd`, `subps/pd`, `mulps/pd`, `divps/pd`, `minps/pd`, `maxps/pd`
  - [x] **Comparison**: `cmpps/pd/ss/sd`, `comiss/sd`, `ucomiss/sd`
  - [x] **Conversion**: `cvtsi2ss/sd`, `cvtss/sd2si`, `cvtss2sd`, `cvtsd2ss`, `cvtdq2ps`, `cvtps2dq`, `cvttps2dq`
  - [x] **Math**: `rcpps/ss`, `rsqrtps/ss`, `sqrtps/pd`




### Fase 3: AVX/AVX2

- [x] Versões VEX de todas as instruções SSE (3 operandos) (Math, Logic, Shuffle)
- [x] `vbroadcastss/sd` - Broadcast float/double
- [x] `vpbroadcastb/w/d/q` - Broadcast integer
- [x] `vpermd/q` - Permute
- [x] `vpmaskmovd/q` - Masked move
- [x] `vextracti128/vinserti128` - Extract/Insert 128-bit
- [x] `vgatherdps/dpd/qps/qpd` - Gather
- [x] `vperm2i128` - Permute 128-bit lanes

### Fase 4: AVX-512 (Opcional)

- [ ] Masking support (k0-k7)
- [ ] `vpternlogd/q` - Ternary logic
- [ ] Broadcast em qualquer operando
- [ ] EVEX encoding

---

## 🛠️ Arquitetura do Compiler para Blend2D

O pipeline JIT do Blend2D precisa de:

### 1. PipeCompiler
```dart
class PipeCompiler {
  // Vector operations helper
  void v_mov(VecArray dst, Vec src);
  void v_broadcast_u8z(Vec dst, Mem src);
  void v_broadcast_u16z(Vec dst, Mem src);
  void v_cvt_u8_lo_to_u16(Vec dst, Vec src);
  void s_extract_u16(Gp dst, Vec src, int idx);
  void shift_or_rotate_right(Vec dst, Vec src, int n);
  
  // Memory operations
  void load_u8(Gp dst, Mem src);
  
  // Labels
  Label new_label();
  void bind(Label label);
  void j(Label label, Condition cond);
}
```

### 2. FetchUtils
```dart
class FetchUtils {
  static void satisfy_solid_pixels(PipeCompiler pc, Pixel s, PixelFlags flags);
  static void satisfy_pixels(PipeCompiler pc, Pixel p, PixelFlags flags);
}
```

### 3. Pixel Types
```dart
class Pixel {
  PixelType type;
  VecArray pc;  // packed RGBA32
  VecArray uc;  // unpacked RGBA32 (16-bit per component)
  VecArray ua;  // unpacked alpha
  VecArray ui;  // unpacked inverse alpha
}
```

---

## 📁 Referências

### C++ AsmJit
- `C:\MyDartProjects\asmjit\referencias\asmjit-master`
- `C:\MyDartProjects\asmjit\referencias\asmtk-master`
- Testes: `C:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit-testing`

### C++ Blend2D
- `C:\MyDartProjects\asmjit\referencias\blend2d-master`
- Pipeline JIT: `blend2d\pipeline\jit\*`
- SIMD x86: `blend2d\simd\simdx86_p.h` (5700 linhas, 405KB)
- SIMD ARM: `blend2d\simd\simdarm_p.h` (222KB)

### Dart Implementation
- `C:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart`
- `C:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart`
- Testes: `C:\MyDartProjects\asmjit\test\asmjit\*`

---

## � Status das Instruções SIMD (Análise Detalhada)

### ✅ Instruções SSE Floating-Point JÁ IMPLEMENTADAS

| Instrução | reg,reg | reg,mem | Status |
|-----------|---------|---------|--------|
| addss/sd | ✅ | ❌ | Parcial |
| addps/pd | ✅ | ✅ | OK |
| subss/sd | ✅ | ❌ | Parcial |
| subps/pd | ✅ | ✅ | OK |
| mulss/sd | ✅ | ❌ | Parcial |
| mulps/pd | ✅ | ✅ | OK |
| divss/sd | ✅ | ❌ | Parcial |
| divps/pd | ✅ | ✅ | OK |
| sqrtss/sd | ✅ | ❌ | Parcial |
| sqrtps/pd | ✅ | ✅ | OK |
| minps/pd | ✅ | ✅ | OK |
| maxps/pd | ✅ | ✅ | OK |

### ✅ Instruções SSE Load/Store/Move JÁ IMPLEMENTADAS

| Instrução | Status | Notas |
|-----------|--------|-------|
| movaps | ✅ | xmm,xmm / xmm,mem / mem,xmm |
| movups | ✅ | xmm,xmm / xmm,mem / mem,xmm |
| movss | ✅ | xmm,xmm / xmm,mem / mem,xmm |
| movsd | ✅ | xmm,xmm / xmm,mem / mem,xmm |
| movd | ✅ | xmm,r32 / r32,xmm / xmm,mem / mem,xmm |
| movq | ✅ | xmm,r64 / r64,xmm |

### ⚠️ Instruções SSE Integer PARCIALMENTE IMPLEMENTADAS

| Instrução | Status | Notas |
|-----------|--------|-------|
| Todos os grupos | ✅ | SSE2/SSE3/SSSE3/SSE4.1 Core Completos |

### 🔴 Instruções SSE Integer FALTANDO (Críticas para Blend2D)

| Instrução | Prioridade | Uso no Blend2D |
|-----------|------------|----------------|
| **COMPLETO** | ✅ | Fase 1 Finalizada! |

### 🟡 Instruções AVX FALTANDO

| Instrução | Prioridade | Notas |
|-----------|------------|-------|
| Versões VEX (3 operandos) | ALTA | Todas as SSE acima |
| vbroadcastss/sd | ALTA | Broadcast scalar |
| vpbroadcastb/w/d/q | ALTA | Broadcast integer |
| vperm2i128 | MÉDIA | Permute 128-bit lanes |
| vpermd/q | MÉDIA | Permute elements |
| vinserti128/vextracti128 | MÉDIA | Insert/Extract 128-bit |
| vpmaskmovd/q | BAIXA | Masked load/store |
| vgatherdps/qps | BAIXA | Gather operations |

---

## �📌 Regras Importantes

1. **Paridade 1:1 com C++**: A lógica deve ser idêntica - mesmas decisões, mesma ordem, mesmos masks/flags
2. **Sem stubs**: Não criar TODOs ou implementações mínimas
3. **Incremental**: Cada passo adiciona valor e é validado por testes
4. **Byte-to-byte**: Testes de encoding devem comparar bytes exatos com C++

---

## � Métricas

| Métrica | Valor |
|---------|-------|
| **Total de testes passando** | 635 |
| **Instruções GP x86 implementadas** | ~200+ |
| **Instruções FP SSE implementadas** | ~40 |
| **Instruções Int SSE implementadas** | ~5 (parcial) |
| **Instruções Int SSE faltando** | ~50+ |
| **Cobertura do encoder** | ~80% GP, ~20% SIMD Int |
| **Cobertura do assembler** | ~70% GP, ~15% SIMD Int |

---

## 📁 Referências

### C++ AsmJit
- `C:\MyDartProjects\asmjit\referencias\asmjit-master`
- `C:\MyDartProjects\asmjit\referencias\asmtk-master`
- Testes: `C:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit-testing`

### C++ Blend2D
- `C:\MyDartProjects\asmjit\referencias\blend2d-master`
- Pipeline JIT: `blend2d\pipeline\jit\*`
- SIMD x86: `blend2d\simd\simdx86_p.h` (5700 linhas, 405KB)
- SIMD ARM: `blend2d\simd\simdarm_p.h` (222KB)

### Dart Implementation
- `C:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart`
- `C:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart`
- Testes: `C:\MyDartProjects\asmjit\test\asmjit\*`
