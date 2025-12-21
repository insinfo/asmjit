# AsmJit Dart - Progresso

## 🎉 Port Completo do Core AsmJit!

Data: 20 Dezembro 2024

## 📊 Status dos Testes

```
✅ 198 testes passaram!
```

## ✅ Implementado

### Core (`lib/src/core/`)
- [x] `error.dart` - Códigos de erro `AsmJitError`, `AsmJitException`, `AsmResult<T>`
- [x] `globals.dart` - Constantes globais (`kAllocOverhead`, `kAllocAlignment`, etc.)
- [x] `arch.dart` - Arquiteturas (`Arch`, `SubArch`, `ArchTraits`, `CallingConvention`)
- [x] `environment.dart` - Ambiente de execução (`Environment`, detecção de host)
- [x] `code_buffer.dart` - Buffer de código com emit8/16/32/64, patch, align
- [x] `labels.dart` - Sistema de labels e relocações (`Label`, `Reloc`, `LabelManager`)
- [x] `operand.dart` - Operandos base (`Operand`, `Imm`, `BaseReg`, `BaseMem`)
- [x] `code_holder.dart` - Container de código, seções, labels, fixups
- [x] `const_pool.dart` - Constant Pool para literais e constantes
- [x] `formatter.dart` - Formatter/Logger para debug

### Runtime (`lib/src/runtime/`)
- [x] `libc.dart` - Bindings FFI para libc (malloc, free, memcpy, etc.)
- [x] `virtmem.dart` - Memória virtual executável com padrão W^X (VirtualAlloc/mmap)
- [x] `jit_runtime.dart` - JIT Runtime completo para execução de código gerado
- [x] `cpuinfo.dart` - **Detecção de features da CPU via CPUID (NOVO)**

### x86 (`lib/src/x86/`)
- [x] `x86.dart` - Registradores x86/x64 (RAX-R15, convenções SysV/Win64)
- [x] `x86_operands.dart` - Operandos de memória (`X86Mem`, `X86RipMem`)
- [x] `x86_encoder.dart` - **120+ instruções codificadas**
- [x] `x86_assembler.dart` - **90+ métodos de alto nível**
- [x] `x86_func.dart` - FuncFrame para gerenciamento de prólogo/epílogo
- [x] `x86_simd.dart` - Registradores XMM/YMM/ZMM

### Inline (`lib/src/inline/`)
- [x] `inline_bytes.dart` - Código pré-compilado com patches (`InlineBytes`, `InlinePatch`)
- [x] `inline_asm.dart` - Builder de funções JIT (`InlineAsm`, `X86Templates`)

## 🧪 Cobertura de Testes (198 testes)

1. **code_buffer_test.dart** (17 testes)
2. **labels_test.dart** (13 testes)
3. **x86_encoder_test.dart** (37 testes)
4. **x86_assembler_test.dart** (15 testes)
5. **jit_execution_test.dart** (13 testes)
6. **inline_test.dart** (23 testes)
7. **x86_extended_test.dart** (26 testes)
8. **crypto_test.dart** (19 testes)
9. **sse_test.dart** (28 testes)
10. **cpuinfo_test.dart** (7 testes) - **NOVO**

## CPU Feature Detection (NOVO)

O AsmJit Dart agora detecta automaticamente as features da CPU usando a instrução CPUID:

```dart
final cpu = CpuInfo.host();
print(cpu);
// CpuInfo(
//   vendor: GenuineIntel,
//   brand: Intel(R) Core(TM) i7-3632QM CPU @ 2.20GHz,
//   processors: 8,
//   features: CpuFeatures(x64, FPU, CMOV, MMX, SSE, SSE2, SSE3, SSSE3, 
//                          SSE4.1, SSE4.2, POPCNT, AVX, AES-NI, PCLMULQDQ)
// )

// Check for specific features
if (cpu.features.avx2) {
  // Use AVX2 instructions
}

if (cpu.features.bmi2) {
  // Use MULX instruction
}

if (cpu.features.adx) {
  // Use ADCX/ADOX instructions
}
```

## Instruções x86/x64 Implementadas (120+)

### Básicas
- `ret`, `nop`, `int3`, `leave`

### MOV
- `mov r64/r32, r64/r32/imm`
- `mov r64, [mem]`, `mov [mem], r64`

### Aritméticas
- `add`, `sub`, `imul`, `xor`, `and`, `or`, `cmp`, `test`
- `adc`, `sbb` (com carry/borrow)
- `mul`, `mulx` (multiplicação sem flags)

### Unárias
- `inc`, `dec`, `neg`, `not`

### Shifts e Rotações
- `shl`, `shr`, `sar`, `rol`, `ror`

### Divisão
- `cqo`, `cdq`, `idiv`, `div`

### Conditional Move/Set
- `cmovcc`, `setcc` (todas as condições)

### Move com Extensão
- `movzx`, `movsxd`

### Bit Manipulation
- `bsf`, `bsr`, `popcnt`, `lzcnt`, `tzcnt`

### Controle de Fluxo
- `jmp`, `call`, `jcc` (todas as condições)
- Labels com relocação automática

### Stack
- `push`, `pop`

### Alta Precisão / Criptografia
- `adc`, `sbb`, `mul`, `mulx`, `adcx`, `adox`

### Flag/String/Fence
- `clc`, `stc`, `cmc`, `cld`, `std`
- `rep movsb/q`, `rep stosb/q`
- `mfence`, `sfence`, `lfence`, `pause`

### SSE/SSE2
- Move: `movaps`, `movups`, `movsd`, `movss`, `movq`, `movd`
- Arithmetic: `addsd/ss`, `subsd/ss`, `mulsd/ss`, `divsd/ss`, `sqrtsd/ss`
- Logic: `pxor`, `xorps`, `xorpd`
- Conversion: `cvtsi2sd/ss`, `cvttsd/ss2si`, `cvtsd2ss`, `cvtss2sd`
- Comparison: `comisd/ss`, `ucomisd/ss`

## 📋 Próximos Passos

- [ ] Milestone 7: Instruction database generator
- [ ] Short jump optimization (rel8/rel32 auto-select)
- [ ] Suporte AArch64 (ARM64)
- [ ] Mais instruções AVX/AVX2/AVX-512
- [ ] Compiler/RA (Register Allocator)

## Exemplo Completo

```dart
import 'package:asmjit/asmjit.dart';
import 'dart:ffi';

void main() {
  // Check CPU features
  final cpu = CpuInfo.host();
  print('Running on: ${cpu.brand}');
  print('Features: ${cpu.features}');

  // Create JIT runtime
  final runtime = JitRuntime();

  // Build a function that adds two numbers
  final code = CodeHolder();
  final asm = X86Assembler(code);

  final arg0 = asm.getArgReg(0);
  final arg1 = asm.getArgReg(1);

  asm.movRR(rax, arg0);
  asm.addRR(rax, arg1);
  asm.ret();

  // Compile and execute
  final fn = runtime.add(code);
  
  typedef NativeAdd = Int64 Function(Int64, Int64);
  typedef DartAdd = int Function(int, int);
  
  final add = fn.pointer
      .cast<NativeFunction<NativeAdd>>()
      .asFunction<DartAdd>();

  print('10 + 20 = ${add(10, 20)}');

  // Cleanup
  fn.dispose();
  runtime.dispose();
}
```
