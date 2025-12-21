# AsmJit Dart - Progresso

## 🎉 Milestones 0-6 e 8 CONCLUÍDOS!

Data: 20 Dezembro 2024

## 📊 Status dos Testes

```
✅ 144 testes passaram!
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
- [x] `const_pool.dart` - **Constant Pool** para literais e constantes (Milestone 6)
- [x] `formatter.dart` - **Formatter/Logger** para debug (Milestone 8)

### Runtime (`lib/src/runtime/`)
- [x] `libc.dart` - Bindings FFI para libc (malloc, free, memcpy, etc.)
- [x] `virtmem.dart` - Memória virtual executável com padrão W^X (VirtualAlloc/mmap)
- [x] `jit_runtime.dart` - JIT Runtime completo para execução de código gerado

### x86 (`lib/src/x86/`)
- [x] `x86.dart` - Registradores x86/x64 (RAX-R15, convenções SysV/Win64)
- [x] `x86_operands.dart` - Operandos de memória (`X86Mem`, `X86RipMem`)
- [x] `x86_encoder.dart` - Encoder de instruções (REX, ModR/M, SIB, opcodes) **+30 novas instruções**
- [x] `x86_assembler.dart` - API de alto nível do assembler **+25 novos métodos**

### Inline (`lib/src/inline/`)
- [x] `inline_bytes.dart` - Código pré-compilado com patches (`InlineBytes`, `InlinePatch`)
- [x] `inline_asm.dart` - Builder de funções JIT (`InlineAsm`, `X86Templates`)

## 🧪 Cobertura de Testes (144 testes)

1. **code_buffer_test.dart** (17 testes)
2. **labels_test.dart** (13 testes)
3. **x86_encoder_test.dart** (37 testes)
4. **x86_assembler_test.dart** (15 testes)
5. **jit_execution_test.dart** (13 testes)
6. **inline_test.dart** (23 testes)
7. **x86_extended_test.dart** (26 testes) - **NOVO**

## Instruções x86/x64 Implementadas

### Básicas
- `ret`, `ret imm16`, `nop`, `nopN`, `int3`, `intN`, `leave`

### MOV
- `mov r64, r64`, `mov r32, r32`
- `mov r64/r32, imm32/imm64`
- `mov r64, [mem]`, `mov [mem], r64`

### Aritméticas
- `add r64, r64/imm8/imm32`
- `sub r64, r64/imm8/imm32`
- `imul r64, r64`
- `xor`, `and`, `or`, `cmp`, `test`

### Unárias (NOVO)
- `inc r64/r32` - Incrementar
- `dec r64/r32` - Decrementar
- `neg r64` - Negação (complemento de dois)
- `not r64` - Complemento (bitwise not)

### Shifts e Rotações (NOVO)
- `shl r64, imm8/CL` - Shift left
- `shr r64, imm8/CL` - Shift right (lógico)
- `sar r64, imm8/CL` - Shift right (aritmético)
- `rol r64, imm8` - Rotate left
- `ror r64, imm8` - Rotate right

### Divisão (NOVO)
- `cqo` - Sign-extend RAX → RDX:RAX
- `cdq` - Sign-extend EAX → EDX:EAX
- `idiv r64` - Divisão com sinal
- `div r64` - Divisão sem sinal

### Conditional Move (NOVO)
- `cmovcc r64, r64` - Todas as condições
- `cmove/cmovz`, `cmovne/cmovnz`
- `cmovl`, `cmovg`, `cmovle`, `cmovge`
- `cmovb`, `cmova`

### Set Byte on Condition (NOVO)
- `setcc r8` - Todas as condições
- `sete`, `setne`, `setl`, `setg`

### Move com Extensão (NOVO)
- `movzx r64, r8` - Zero-extend byte
- `movzx r64, r16` - Zero-extend word
- `movsxd r64, r32` - Sign-extend dword

### Bit Manipulation (NOVO)
- `bsf r64, r64` - Bit scan forward
- `bsr r64, r64` - Bit scan reverse
- `popcnt r64, r64` - Population count
- `lzcnt r64, r64` - Leading zero count
- `tzcnt r64, r64` - Trailing zero count

### Exchange (NOVO)
- `xchg r64, r64` - Exchange valores

### Stack
- `push r64`, `push imm8/imm32`, `pop r64`

### Controle de Fluxo
- `jmp rel32/r64`, `call rel32/r64`
- `jcc rel32` (todas as condições: je, jne, jl, jg, jle, jge, jb, ja, etc.)
- Labels com relocação automática

### LEA
- `lea r64, [mem]`

## 📋 Próximos Passos

- [ ] Milestone 5: Jump optimization (short vs near) - **parcialmente implementado**
- [ ] Milestone 7: Instruction database generator
- [ ] Suporte AArch64 (ARM64)
- [ ] Mais instruções SIMD (SSE/AVX)

## Uso

### Exemplo: Função ABS usando CMOV

```dart
final code = CodeHolder();
final asm = X86Assembler(code);

// abs(x) = x < 0 ? -x : x
final arg0 = asm.getArgReg(0);
asm.movRR(rax, arg0);     // rax = x
asm.movRR(rcx, arg0);     // rcx = x
asm.neg(rcx);             // rcx = -x
asm.cmpRI(rax, 0);        // compare x, 0
asm.cmovl(rax, rcx);      // if x < 0, rax = -x
asm.ret();

final fn = runtime.add(code);
final abs = fn.pointer.cast<...>().asFunction<...>();
print(abs(-42)); // Output: 42
```

### Exemplo: Divisão e Módulo

```dart
// div(a, b) = a / b
asm.movRR(r8, arg1);    // salvar divisor (pode ser RDX)
asm.movRR(rax, arg0);   // dividendo em RAX
asm.cqo();              // sign-extend para RDX:RAX
asm.idiv(r8);           // dividir, quociente em RAX, resto em RDX
asm.ret();

// Para módulo, adicione: asm.movRR(rax, rdx);
```

### Exemplo: Shift e Rotação

```dart
asm.movRR(rax, arg0);
asm.shlRI(rax, 4);  // rax *= 16 (shift left 4)
asm.ret();
```

### Formatador para Debug

```dart
final logger = AsmLogger();
logger.logInstruction(0, [0xB8, 0x2A, 0x00, 0x00, 0x00], 'mov', operands: ['eax', '42']);
logger.logInstruction(5, [0xC3], 'ret');
print(logger.format());
// Output:
// 00000000  b8 2a 00 00 00        mov eax, 42
// 00000005  c3                    ret
```
