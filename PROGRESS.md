# AsmJit Dart - Progresso

## 🎉 Port Completo do Core AsmJit + SSE + AVX/AVX2 + Register Allocator!

Data: 20 Dezembro 2024

## 📊 Status dos Testes

```
✅ 234 testes passaram!
```

## ✅ Implementado

### Core (`lib/src/core/`)
- [x] `error.dart` - Códigos de erro `AsmJitError`, `AsmJitException`, `AsmResult<T>`
- [x] `globals.dart` - Constantes globais 
- [x] `arch.dart` - Arquiteturas (`Arch`, `SubArch`, `ArchTraits`, `CallingConvention`)
- [x] `environment.dart` - Ambiente de execução (`Environment`, detecção de host)
- [x] `code_buffer.dart` - Buffer de código com emit8/16/32/64, patch, align
- [x] `labels.dart` - Sistema de labels e relocações (rel8, rel32)
- [x] `operand.dart` - Operandos base
- [x] `code_holder.dart` - Container de código, seções, labels, fixups
- [x] `const_pool.dart` - Constant Pool
- [x] `formatter.dart` - Formatter/Logger
- [x] `regalloc.dart` - **Register Allocator (linear scan) (NOVO)**

### Runtime (`lib/src/runtime/`)
- [x] `libc.dart` - Bindings FFI para libc
- [x] `virtmem.dart` - Memória virtual executável W^X
- [x] `jit_runtime.dart` - JIT Runtime completo
- [x] `cpuinfo.dart` - Detecção CPUID

### x86 (`lib/src/x86/`)
- [x] `x86.dart` - Registradores x86/x64
- [x] `x86_operands.dart` - Operandos de memória
- [x] `x86_encoder.dart` - **150+ instruções codificadas** (SSE, AVX, AVX2, FMA)
- [x] `x86_assembler.dart` - **130+ métodos de alto nível**
- [x] `x86_func.dart` - FuncFrame
- [x] `x86_simd.dart` - Registradores XMM/YMM/ZMM

### Inline (`lib/src/inline/`)
- [x] `inline_bytes.dart` - Código pré-compilado
- [x] `inline_asm.dart` - Builder de funções JIT

## 🧪 Cobertura de Testes (234 testes)

1. **code_buffer_test.dart** (17 testes)
2. **labels_test.dart** (13 testes)
3. **x86_encoder_test.dart** (37 testes)
4. **x86_assembler_test.dart** (15 testes)
5. **jit_execution_test.dart** (13 testes)
6. **inline_test.dart** (23 testes)
7. **x86_extended_test.dart** (26 testes)
8. **crypto_test.dart** (19 testes)
9. **sse_test.dart** (28 testes)
10. **cpuinfo_test.dart** (7 testes)
11. **short_jump_test.dart** (5 testes)
12. **avx_test.dart** (18 testes)
13. **regalloc_test.dart** (13 testes) - **NOVO**

## Register Allocator (NOVO)

Implementado um Register Allocator simples usando o algoritmo **Linear Scan**:

### Características
- Suporta registradores GP (14 disponíveis) e XMM (16 disponíveis)
- Considera convenção de chamada (Win64 vs SysV)
- Spilling automático quando todos os registradores estão em uso
- Cálculo automático do tamanho da área de spill
- Reuso de registradores quando intervalos não se sobrepõem

### Uso

```dart
final ra = SimpleRegAlloc(isWin64: false);

// Criar registradores virtuais
final v0 = ra.newVirtReg();
final v1 = ra.newVirtReg();
final v2 = ra.newVirtReg(regClass: RegClass.xmm);

// Registrar usos (posição = índice da instrução)
ra.recordUse(v0, 0);  // Usado na instrução 0
ra.recordUse(v0, 10); // Usado na instrução 10
ra.recordUse(v1, 5);
ra.recordUse(v1, 15);

// Alocar registradores físicos
ra.allocate();

// Verificar alocação
print('v0 -> ${v0.physReg}'); // e.g., RAX
print('v1 -> ${v1.physReg}'); // e.g., RCX
print('v2 -> ${v2.physXmm}'); // e.g., XMM0

// Verificar se houve spilling
if (v0.isSpilled) {
  print('v0 foi spilled para offset ${v0.spillOffset}');
}

// Total de espaço para spill na stack
print('Spill area: ${ra.spillAreaSize} bytes');
```

## Instruções x86/x64 Implementadas (150+)

### Básicas
- `ret`, `nop`, `int3`, `leave`

### MOV
- `mov r64/r32, r64/r32/imm`
- `mov r64, [mem]`, `mov [mem], r64`

### Aritmética
- `add`, `sub`, `imul`, `xor`, `and`, `or`, `cmp`, `test`
- `adc`, `sbb`, `mul`, `mulx`, `adcx`, `adox`
- `inc`, `dec`, `neg`, `not`

### Shifts
- `shl`, `shr`, `sar`, `rol`, `ror`

### Divisão
- `cqo`, `cdq`, `idiv`, `div`

### Controle
- `jmp` (rel8/rel32 auto), `call`, `jcc` (rel8/rel32 auto)
- `cmovcc`, `setcc`
- Labels com relocação automática

### SSE/SSE2
- Move: `movaps`, `movups`, `movsd`, `movss`, `movq`, `movd`
- Arith: `addsd/ss`, `subsd/ss`, `mulsd/ss`, `divsd/ss`, `sqrtsd/ss`
- Logic: `pxor`, `xorps`, `xorpd`
- Convert: `cvtsi2sd/ss`, `cvttsd/ss2si`, `cvtsd2ss`, `cvtss2sd`
- Compare: `comisd/ss`, `ucomisd/ss`

### AVX/AVX2 (VEX encoded)
- Move: `vmovaps`, `vmovups` (128/256-bit)
- Arith Scalar: `vaddsd`, `vsubsd`, `vmulsd`, `vdivsd`
- Arith Packed: `vaddps`, `vmulps`, `vaddpd`, `vmulpd` (256-bit)
- Logic: `vxorps`, `vpxor`
- Integer: `vpaddd`, `vpaddq`, `vpmulld`
- FMA: `vfmadd132sd`, `vfmadd231sd`
- Special: `vzeroupper`, `vzeroall`

### Criptografia/Alta Precisão
- `adc`, `sbb`, `mul`, `mulx`, `adcx`, `adox`

### Flags/String/Fence
- `clc`, `stc`, `cmc`, `cld`, `std`
- `rep movsb/q`, `rep stosb/q`
- `mfence`, `sfence`, `lfence`, `pause`

## 📋 Próximos Passos

- [ ] Instruction database generator (M7)
- [ ] Integrar Register Allocator com X86Assembler
- [ ] Suporte AArch64 (ARM64)
- [ ] Mais instruções AVX-512
- [ ] IR (Intermediate Representation)
