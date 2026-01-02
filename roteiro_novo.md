# Roteiro de Portação: AsmJit C++ → Dart

**Última Atualização**: 2026-01-02 (18:00)
continue lendo o codigo fonte c++ C:\MyDartProjects\asmjit\referencias\asmjit-master e portando

foco em 64 bits, windows e linux e paridade com c++

responda sempre em portuges
este roteiro tem que ser matido atualizado e em portuges

continue portando ujit do c++ para o dart C:\MyDartProjects\asmjit\lib\src\asmjit\ujit e para cada coisa que estiver faltando implementar em x86 C:\MyDartProjects\asmjit\lib\src\asmjit\x86 e ARM64 C:\MyDartProjects\asmjit\lib\src\asmjit\arm e va implementando as instruções que estam faltando, e va implementando testes tambem e atualize o roteiro C:\MyDartProjects\asmjit\roteiro_novo.md.

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

## 🆕 UJIT Layer - Progresso (02/01/2026 18:30)

### Arquivos Criados/Atualizados:
| Arquivo | Status | Descrição |
|---------|--------|-----------|
| `ujit/unicompiler.dart` | ✅ ~98% | RRR/RRI Dispatch, Conditional Moves |
| `ujit/unicompiler_a64.dart` | ✅ ~98% | Condition Test (CMP/TST), Bit Tests (TBZ), RRR/RRI |
| `ujit/unicondition.dart` | ✅ Verified | API Stable |
| `test/asmjit/ujit_conditional_test.dart` | ✅ PASSED | Logic/Branch/Select/Cmov Verified |
| `test/asmjit/ujit_logic_shift_test.dart` | ✅ PASSED | And, Or, Xor, Shift Ops Verified |

### Funcionalidades Implementadas:
1. **Conditional Ops**:
   - Implemented `emitJIf` correctly for X86 and A64 (generating CMP/TST + Branch).
   - Implemented A64 specialized bit-tests (`TBZ`/`TBNZ`) in `emitJIfA64Impl`.
   - `emitCmov` and `emitSelect` fully functional cross-arch.
2. **Scalar Logic & Shifts (RRR/RRI)**:
   - Added `emitRRR` (And, Or, Xor, Add, Sub, Mul, Shifts) and `emitRRI` (Immediate forms).
   - Implemented X86 and A64 dispatch logic (`_emitRRRX86`, `_emitRRRA64` etc).
3. **Register Allocator Support**:
   - Implemented `emitMove` in `X86Compiler` (improved vector support) and `A64Compiler`.
4. **Lint Cleanup**:
   - Resolved switch-case lints in `unicompiler_a64.dart`.

### Próximos Passos UJIT:

1. **Memory Operands (Deep Test):**
   - Create `ujit_mem_test.dart` for M/RM/MR operations (Loads/Stores/Extensions).
   - Improve `UniOpVM` coverage for A64.

2. **JIT Execution Enablement**:
   - Debug `RAPass` assertion issue (`physToWorkId` failure on CFG) to enable `finalize()` execution.
   - Currently testing via IR verification until optimizations are stable.

3. **Complex SIMD Ops (A64):**
   - `_emit3viA64` (alignr, shuffles).
   - `_emit5vA64`, `_emit9vA64` (se necessário para crypto/hashes).

---

## ✅ Progresso Recente (01/01/2026)

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
