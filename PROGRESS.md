# AsmJit Dart - Progresso

## 🎉 Port Completo do Core AsmJit + Short Jumps!

Data: 20 Dezembro 2024

## 📊 Status dos Testes

```
✅ 203 testes passaram!
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
- [x] `code_holder.dart` - Container de código, seções, labels, fixups + rel8 relocations
- [x] `const_pool.dart` - Constant Pool para literais e constantes
- [x] `formatter.dart` - Formatter/Logger para debug

### Runtime (`lib/src/runtime/`)
- [x] `libc.dart` - Bindings FFI para libc (malloc, free, memcpy, etc.)
- [x] `virtmem.dart` - Memória virtual executável com padrão W^X (VirtualAlloc/mmap)
- [x] `jit_runtime.dart` - JIT Runtime completo para execução de código gerado
- [x] `cpuinfo.dart` - Detecção de features da CPU via CPUID

### x86 (`lib/src/x86/`)
- [x] `x86.dart` - Registradores x86/x64 (RAX-R15, convenções SysV/Win64)
- [x] `x86_operands.dart` - Operandos de memória (`X86Mem`, `X86RipMem`)
- [x] `x86_encoder.dart` - **120+ instruções codificadas**
- [x] `x86_assembler.dart` - **90+ métodos de alto nível** + **Short jumps automáticos (NOVO)**
- [x] `x86_func.dart` - FuncFrame para gerenciamento de prólogo/epílogo
- [x] `x86_simd.dart` - Registradores XMM/YMM/ZMM

### Inline (`lib/src/inline/`)
- [x] `inline_bytes.dart` - Código pré-compilado com patches (`InlineBytes`, `InlinePatch`)
- [x] `inline_asm.dart` - Builder de funções JIT (`InlineAsm`, `X86Templates`)

## 🧪 Cobertura de Testes (203 testes)

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
11. **short_jump_test.dart** (5 testes) - **NOVO**

## Short Jump Optimization (NOVO)

O assembler agora **automaticamente otimiza backward jumps** para usar short jumps (rel8) quando possível:

### Backward Jumps (para labels já bound)
```dart
final loopStart = code.newLabel();

code.bind(loopStart);
asm.nop();
asm.jmp(loopStart);  // Automaticamente usa EB xx (2 bytes) ao invés de E9 xx xx xx xx (5 bytes)
```

### Forward Jumps com forceShort
```dart
final target = code.newLabel();

// Force short jump para forward jump (use com cuidado!)
asm.jmp(target, forceShort: true);
asm.nop();
asm.nop();
code.bind(target);
```

### Benefícios
- **Código menor**: Short jumps usam 2 bytes vs 5-6 bytes
- **Loops mais eficientes**: Backward jumps em loops tight são automaticamente otimizados
- **Cache-friendly**: Código menor = melhor uso do instruction cache

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
- `jmp` (rel8/rel32 automático), `call`, `jcc` (rel8/rel32 automático)
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
- [ ] Suporte AArch64 (ARM64)
- [ ] Mais instruções AVX/AVX2/AVX-512
- [ ] Compiler/RA (Register Allocator)

## Exemplo: Loop com Short Jumps

```dart
import 'package:asmjit/asmjit.dart';
import 'dart:ffi';

void main() {
  final runtime = JitRuntime();
  final code = CodeHolder();
  final asm = X86Assembler(code);

  final arg0 = asm.getArgReg(0);
  
  // Sum from 1 to n
  asm.xorRR(rax, rax);   // result = 0
  asm.movRR(r8, arg0);   // n = arg0
  
  final loopStart = code.newLabel();
  final done = code.newLabel();
  
  code.bind(loopStart);
  asm.testRR(r8, r8);
  asm.jz(done);           // Forward jump (rel32)
  asm.addRR(rax, r8);     // result += n
  asm.dec(r8);            // n--
  asm.jmp(loopStart);     // Backward jump - AUTOMATICALLY uses rel8!
  
  code.bind(done);
  asm.ret();

  // Execute!
  final fn = runtime.add(code);
  typedef NativeSum = Int64 Function(Int64);
  typedef DartSum = int Function(int);
  
  final sum = fn.pointer.cast<NativeFunction<NativeSum>>().asFunction<DartSum>();
  
  print('Sum(10) = ${sum(10)}');   // 55
  print('Sum(100) = ${sum(100)}'); // 5050
  
  fn.dispose();
  runtime.dispose();
}
```
