# AsmJit Dart - Progresso

## 🎉 Milestones 0-8 CONCLUÍDOS!

Data: 20 Dezembro 2024

## 📊 Status dos Testes

```
✅ 163 testes passaram!
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

### x86 (`lib/src/x86/`)
- [x] `x86.dart` - Registradores x86/x64 (RAX-R15, convenções SysV/Win64)
- [x] `x86_operands.dart` - Operandos de memória (`X86Mem`, `X86RipMem`)
- [x] `x86_encoder.dart` - **80+ instruções codificadas**
- [x] `x86_assembler.dart` - **60+ métodos de alto nível**
- [x] `x86_func.dart` - **FuncFrame** para gerenciamento de prólogo/epílogo

### Inline (`lib/src/inline/`)
- [x] `inline_bytes.dart` - Código pré-compilado com patches (`InlineBytes`, `InlinePatch`)
- [x] `inline_asm.dart` - Builder de funções JIT (`InlineAsm`, `X86Templates`)

## 🧪 Cobertura de Testes (163 testes)

1. **code_buffer_test.dart** (17 testes)
2. **labels_test.dart** (13 testes)
3. **x86_encoder_test.dart** (37 testes)
4. **x86_assembler_test.dart** (15 testes)
5. **jit_execution_test.dart** (13 testes)
6. **inline_test.dart** (23 testes)
7. **x86_extended_test.dart** (26 testes)
8. **crypto_test.dart** (19 testes) - **NOVO**

## Instruções x86/x64 Implementadas (80+)

### Básicas
- `ret`, `ret imm16`, `nop`, `nopN`, `int3`, `intN`, `leave`

### MOV
- `mov r64, r64`, `mov r32, r32`
- `mov r64/r32, imm32/imm64`
- `mov r64, [mem]`, `mov [mem], r64`

### Aritméticas
- `add`, `sub`, `imul`, `xor`, `and`, `or`, `cmp`, `test`

### Unárias
- `inc`, `dec`, `neg`, `not`

### Shifts e Rotações
- `shl`, `shr`, `sar`, `rol`, `ror` (com imm8 ou CL)

### Divisão
- `cqo`, `cdq`, `idiv`, `div`

### Conditional Move (CMOVcc)
- `cmove/cmovz`, `cmovne/cmovnz`
- `cmovl`, `cmovg`, `cmovle`, `cmovge`
- `cmovb`, `cmova`

### Set Byte on Condition (SETcc)
- `sete`, `setne`, `setl`, `setg`

### Move com Extensão
- `movzx` (byte→qword, word→qword)
- `movsxd` (dword→qword com sinal)

### Bit Manipulation
- `bsf`, `bsr`, `popcnt`, `lzcnt`, `tzcnt`

### Exchange
- `xchg`

### Stack
- `push`, `pop`

### Controle de Fluxo
- `jmp`, `call`, `jcc` (todas as condições)
- Labels com relocação automática

### LEA
- `lea r64, [mem]`

### **Alta Precisão / Criptografia (NOVO)**
- `adc` (add with carry)
- `sbb` (subtract with borrow)
- `mul` (unsigned multiply RDX:RAX)
- `mulx` (BMI2 - multiply without flags)
- `adcx` (ADX - add with carry, CF only)
- `adox` (ADX - add with overflow, OF only)

### **Flag Manipulation (NOVO)**
- `clc` (clear carry)
- `stc` (set carry)
- `cmc` (complement carry)
- `cld` (clear direction)
- `std` (set direction)

### **String Operations (NOVO)**
- `rep movsb` (copy bytes)
- `rep movsq` (copy qwords)
- `rep stosb` (store bytes)
- `rep stosq` (store qwords)

### **Memory Fences (NOVO)**
- `mfence` (full fence)
- `sfence` (store fence)
- `lfence` (load fence)
- `pause` (spin loop hint)

## 📋 Próximos Passos

- [ ] Milestone 7: Instruction database generator
- [ ] Suporte AArch64 (ARM64)
- [ ] Mais instruções SIMD (SSE/AVX)
- [ ] Compiler/RA (Register Allocator)

## Uso

### Exemplo: FuncFrame para gerenciamento de prólogo/epílogo

```dart
final frame = FuncFrame.host(
  attr: FuncFrameAttr.nonLeaf(localStackSize: 64),
);

final code = CodeHolder();
final asm = X86Assembler(code);
final emitter = FuncFrameEmitter(frame, asm);

emitter.emitPrologue();
// ... código da função ...
emitter.emitEpilogue();
```

### Exemplo: Aritmética de Alta Precisão

```dart
// Adicionar com carry (útil para aritmética de 128-bit)
asm.clc();                // Limpar carry
asm.movRR(rax, arg0);     // rax = arg0
asm.addRR(rax, arg1);     // rax += arg1, pode setar carry
asm.movRR(rdx, arg2);     // rdx = arg2
asm.adcRR(rdx, arg3);     // rdx += arg3 + carry
```

### Exemplo: Memory Fence

```dart
// Para operações thread-safe
asm.mfence();  // Full memory barrier
asm.sfence();  // Store barrier
asm.lfence();  // Load barrier
asm.pause();   // Spin loop hint
```

### Exemplo: String copy (memcpy)

```dart
// REP MOVSB: copy RCX bytes from [RSI] to [RDI]
asm.movRR(rdi, dest);   // Destination
asm.movRR(rsi, src);    // Source
asm.movRR(rcx, count);  // Byte count
asm.cld();              // Clear direction (forward)
asm.repMovsb();         // Copy!
```
