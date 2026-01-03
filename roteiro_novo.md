# Roteiro de Portação: AsmJit C++ → Dart

**Última Atualização**: 2026-01-02 (18:00)
continue lendo o codigo fonte c++ C:\MyDartProjects\asmjit\referencias\asmjit-master e portando

foco em 64 bits, windows e linux e paridade com c++

responda sempre em portuges
este roteiro tem que ser matido atualizado e em portuges

continue portando ujit do c++ para o dart C:\MyDartProjects\asmjit\lib\src\asmjit\ujit e para cada coisa que estiver faltando implementar em x86 C:\MyDartProjects\asmjit\lib\src\asmjit\x86 e ARM64 C:\MyDartProjects\asmjit\lib\src\asmjit\arm e va implementando as instruções que estam faltando, e va implementando testes tambem e atualize o roteiro C:\MyDartProjects\asmjit\roteiro_novo.md.

nunca edite arquivos gerados edite o gerador
sempre que fizer uma alteração de codigo execute dart analyze para ver se esta correto

## 📊 Status Atual

| Componente | Status | Testes |
|------------|--------|--------|
| Core (CodeHolder, Buffer, Runtime) | ✅ Funcional | **730 passando** ✨ |
| x86 Assembler | ✅ ~94% | +100 instrucoes (SSE/AVX/AVX-512, Rounding) |
| x86 Encoder | ✅ ~95% | Byte-to-byte pass |
| A64 Assembler | ✅ ~62% | logic/shifts/bitmasks/adc/sbc added |
| A64 Encoder | ✅ ~58% | logic/shifts/bitmasks/adc/sbc added |
| Compiler Base | ✅ ~85% | Fixed Ret/Jump Serialization | 
| RALocal | ✅ Implementado | Funcional |
| RAGlobal | ✅ Parcial (Coalescing, Priority, Weighing) | Epilog/Ret Insertion Fixed |
| **UJIT Layer** | ✅ ~90% | X86 ~92% / A64 ~90% |
| **Benchmarks** | ✅ Operacionais | X64 & A64 GP/SSE (MInst/s metrics) |
| **Lint Status** | ✅ Clean | 0 erros, Warns Resolved |

---

## 🆕 UJIT Layer - Progresso (02/01/2026 22:00)

### Arquivos Criados/Atualizados:
| Arquivo | Status | Descrição |
|---------|--------|-----------|
| `ujit/unicompiler.dart` | ✅ ~99% | Implementação `emitM`, `emit3v` dispatch |
| `ujit/unicompiler_a64.dart` | ✅ ~99% | Suporte Float Arith, StoreZero, Cleanups |
| `test/asmjit/ujit_float_test.dart` | ✅ PASSED | Testes verificados para Add/Sub/Mul/Div Float |
| `test/asmjit/ujit_mem_test.dart` | ✅ PASSED | M/RM/MR Ops verificados (Load/Store) |

### Funcionalidades Implementadas:
1. **Float Arithmetic Ops**:
   - Adicionado suporte para `addF32/F64`, `subF32/F64`, `mulF32/F64`, `divF32/F64` em AArch64 e X86.
   - Testes de integridade (IR check) passando para operações flutuantes vetoriais.

2. **Memory Ops (M/RM/MR)**:
   - Implementado `emitM` (para StoreZero, Prefetch).
   - Implementado `_emitMA64` para AArch64 (usando WZR/XZR para storeZero).
   - Testes de Load Extensions e Stores básicos passando.

3. **Cleanup e Otimizações**:
   - Removido código duplicado (Switch Case Unreachable) em `unicompiler_a64.dart`.
   - Removidos imports desnecessários nos testes.
   - Corrigidos avisos de linter (variáveis não utilizadas).

### Próximos Passos UJIT:

1. **JIT Execution Enablement**:
   - Debugar e corrigir assert `physToWorkId` no `RAPass` para permitir execução real (`finalize()`).
   - Habilitar execução de código nos testes além da verificação de IR.

2. **Complex SIMD Ops (A64)**:
   - Terminar implementação de `_emit3viA64` (para `alignr`, `shuffles` complexos).
   - Implementar `_emit5vA64` e `_emit9vA64` se necessário.

---

## 🛠️ Correções e Refatoração (02/01/2026 22:30)

### Correções de Compilação e Runtime:
1.  **UniCompiler Mixin Visibility**:
    - Movidos métodos `newVec`, `newVecWithWidth`, `_newVecConst` para `UniCompilerBase` (abstratos) para permitir acesso seguro via mixins (`UniCompilerA64`).
    - Removidos casts inseguros `(cc as dynamic)` e `(this as dynamic)` em `unicompiler_a64.dart`.
    - Corrigido uso de `newVec` em `UniCompilerA64` para usar `newVecWithWidth` corretamente.

2.  **Testes**:
    - Corrigido import não utilizado em `ujit_simd_shuffle_test.dart`.
    - `ujit_simd_shuffle_test.dart` passando com sucesso.

### ⚠️ Bloqueios Identificados para Blend2d (RESOLVIDOS):
1.  **Suporte a Labels em Operandos de Memória (X86Mem)**:
    - ✅ **Resolvido**: Adicionado suporte a `Label` em `X86Mem` e implementado encoding RIP-relative em `X86Encoder`.
    - ✅ **Implementado**: `UniCompiler` agora usa `LEA reg, [label]` para tabelas de constantes locais em X86.
    - ✅ **Verificado**: `ujit_const_test.dart` passando.

2.  **Execução JIT Real (RAPass)**:
    - ✅ **Resolvido**: Corrigido bug no `RALocalAllocator` onde registradores marcados para liberação (`willFree`) eram considerados disponíveis para movimento antes de serem efetivamente liberados, causando falha de asserção `physToWorkId`.
    - ✅ **Verificado**: `x86_compiler_jit_test.dart` passando com alocação de registradores complexa.

---

## ✅ Progresso Recente (02/01/2026)

### Instruções Implementadas Nesta Sessão:

1. **AVX/AVX2 Foundation (Completo)**:
   - `vbroadcastss/sd` - Broadcast float/double
   - `vpbroadcastb/w/d/q` - Broadcast integer
   - `vpermd/q`, `vperm2i128` - Permute
   - `vpmaskmovd/q` - Masked move
   - `vextracti128/vinserti128` - Extract/Insert 128-bit
   - `vgatherdps/dpd/qps/qpd` - Gather
   - Versões VEX de instruções SSE (3 operandos)

2. **SSE4.1 Avançado (Completo)**:
   - `blend*` (ps, pd, vps, vpd, w, vb) - Blend vector elements
   - `insertps`, `extractps` - Insert/Extract floating point
   - `pinsr*`, `pextr*` (b, w, d, q) - Insert/Extract integer
   - `pmovzx*`, `pmovsx*` - Zero/Sign Extension

3. **SSE2 Packed Integer Core**:
   - `padd*`, `psub*`, `pmul*`
   - `pcmpeq/gt*`
   - `pmin/max*`
   - `psll/srl/sra*`
   - `pand/n`, `por`, `pxor`
   - `pack*`, `punpck*`
   - `pshuf*`, `palignr`

## 🛠️ Correções e Expansão de Testes (02/01/2026 23:00)

### Correções de Compilação:
1.  **X86Assembler Duplicates**:
    - Removidas definições duplicadas de `padddXX`, `padddXM`, `paddwXX` em `x86_assembler.dart`.
2.  **X86Encoder Missing Methods**:
    - Implementados `movdquXmmXmm`, `movdquXmmMem`, `movdquMemXmm` em `x86_encoder.dart` (SSE2).
3.  **Generator Cleanup**:
    - Removidos elementos duplicados (`movd`, `movq`) em `tool/gen_x86_db.dart`.
4.  **Lint Fixes**:
    - Removidos imports não utilizados em `integration_simd_test.dart` e `unicompiler.dart`.

### Testes de Integração:
1.  **SIMD Integration Test**:
    - `test/asmjit/integration_simd_test.dart` agora compila e passa com sucesso.
    - Verifica execução real de código JIT com instruções SSE2 (`paddd`, `movdqu`).

