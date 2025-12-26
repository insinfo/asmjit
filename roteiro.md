# Roteiro de Portação: AsmJit C++ → Dart


roteiro bem prático (e incremental) para portar o AsmJit (C++) C:\MyDartProjects\asmjit\referencias\asmtk-master C:\MyDartProjects\asmjit\referencias\asmjit-master para Dart, mantendo alto desempenho e a filosofia FFI para ponteiros + libc para alocação, APIs do SO para memória executável, convenções de chamada da plataforma, e uma API “inline” de bytes ( “assembly inline via constantes para o dart”).

assumir Dart Native (VM/AOT) em desktop/servidor. No iOS (e alguns ambientes “hardened”) JIT/memória executável costuma ser bloqueado por política do sistema — então trate como alvo “não suportado” ou “modo AOT/sem JIT”.

nada no codigo em testes podem depender de C:\MyDartProjects\asmjit\referencias
copie o que for necessario paras diretorios apropriados por exemplo C:\MyDartProjects\asmjit\assets

coloque comentarios \\ TODO onde não esta concluido ou completo

para ARM integration testes use:
docker run --privileged --rm tonistiigi/binfmt --install arm64

docker run --rm --platform linux/arm64 `
  -v ${PWD}:/work -w /work `
  -v asmjit_dart_tool_arm64:/work/.dart_tool `
  -v asmjit_pub_cache_arm64:/root/.pub-cache `
  dart:stable `
  bash -lc "dart --version && dart pub get && dart test"

docker run --rm --platform linux/arm64 dart:stable bash -lc "uname -m"

**Assumir**: Dart Native (VM/AOT) em desktop/servidor. No iOS (e alguns ambientes "hardened") JIT/memória executável costuma ser bloqueado por política do sistema — então trate como alvo "não suportado" ou "modo AOT/sem JIT".

**Regra**: Nada no código/testes pode depender de `referencias/`. Copie o que for necessário para `assets/`.

**TODO**: Colocar comentários `// TODO` onde não está concluído ou completo.

---

## 📊 Status Atual

**Data**: 25 Dezembro 2024  
**Testes**: ✅ 343 passando  
**Warnings**: 0

---

## 📁 Mapeamento de Arquivos: C++ → Dart

### Core (`asmjit/core/` → `lib/src/core/`)

| Arquivo C++ | Arquivo Dart | Status |
|-------------|--------------|--------|
| `globals.h/.cpp` | `globals.dart` | ✅ |
| `error.h` | `error.dart` | ✅ |
| `archtraits.h/.cpp` | `arch.dart` | ✅ |
| `environment.h/.cpp` | `environment.dart` | ✅ |
| `codebuffer.h` | `code_buffer.dart` | ✅ |
| `codeholder.h/.cpp` | `code_holder.dart` | ✅ |
| `operand.h/.cpp` | `operand.dart` | ✅ |
| `constpool.h/.cpp` | `const_pool.dart` | ✅ |
| `formatter.h/.cpp` | `formatter.dart` | ✅ |
| `type.h/.cpp` | `type.dart` | ✅ |
| `builder.h/.cpp` | `builder.dart` | ✅ (básico) |
| `func.h/.cpp` | `x86_func.dart` | ✅ (FuncSignature) |
| `compiler.h/.cpp` | - | ❌ TODO: Compiler |
| `rapass.h/.cpp` | `regalloc.dart` | ✅ (linear scan) |
| `jitruntime.h/.cpp` | `jit_runtime.dart` | ✅ |
| `jitallocator.h/.cpp` | `virtmem.dart` | ✅ |
| `cpuinfo.h/.cpp` | `cpuinfo.dart` | ✅ |
| `instdb.h` | `x86_inst_db.g.dart` | ✅ (1831 inst) |

### x86 (`asmjit/x86/` → `lib/src/x86/`)

| Arquivo C++ | Arquivo Dart | Status |
|-------------|--------------|--------|
| `x86globals.h` | `x86.dart` | ✅ |
| `x86operand.h/.cpp` | `x86_operands.dart` | ✅ |
| `x86assembler.h/.cpp` | `x86_assembler.dart` | ✅ (150+ métodos) |
| `x86emitter.h` | `x86_encoder.dart` | ✅ (200+ instruções) |
| `x86instdb.h/.cpp` | `x86_inst_db.g.dart` | ✅ |
| `x86func.h` | `x86_func.dart` | ✅ (FuncFrame) |
| `x86rapass.h/.cpp` | - | ❌ TODO |
| `x86builder.h/.cpp` | `code_builder.dart` | ⚠️ Parcial |
| `x86compiler.h/.cpp` | - | ❌ TODO |

### ASMTK (`asmtk/` → `lib/src/asmtk/`)

| Arquivo C++ | Arquivo Dart | Status |
|-------------|--------------|--------|
| `asmtokenizer.h/.cpp` | `tokenizer.dart` | ✅ |
| `asmparser.h/.cpp` | `parser.dart` | ✅ (básico) |

### Runtime & Inline

| Arquivo Dart | Status | Descrição |
|--------------|--------|-----------|
| `libc.dart` | ✅ | FFI bindings libc |
| `virtmem.dart` | ✅ | Memória executável W^X |
| `jit_runtime.dart` | ✅ | Runtime JIT completo |
| `cpuinfo.dart` | ✅ | Detecção CPUID |
| `inline_bytes.dart` | ✅ | Código pré-compilado |
| `inline_asm.dart` | ✅ | Builder de funções JIT |

---

## 📋 Instruções x86 Implementadas (200+)

### ✅ Completo

**Básicas**: `ret`, `nop`, `int3`, `leave`, `push`, `pop`

**MOV**: `mov r,r`, `mov r,imm`, `mov r,[m]`, `mov [m],r`, `mov [m],imm`

**Aritmética**: `add`, `sub`, `imul` (2 e 3 operandos), `xor`, `and`, `or`, `cmp`, `test`, `inc`, `dec`, `neg`, `not`

**Carry/Multi**: `adc`, `sbb`, `mul`, `mulx`, `adcx`, `adox`

**Shifts**: `shl`, `shr`, `sar`, `rol`, `ror`

**Divisão**: `cqo`, `cdq`, `idiv`, `div`

**Controle**: `jmp`, `call`, `jcc` (todas), `cmovcc`, `setcc`

**Extensão**: `movzx`, `movsx`, `movsxd`

**Bits**: `bsf`, `bsr`, `popcnt`, `lzcnt`, `tzcnt`

**LEA**: `lea r,[m]`

**XCHG**: `xchg r,r`

**SSE/SSE2**: `movaps`, `movups`, `movsd`, `movss`, `addsd`, `subsd`, `mulsd`, `divsd`, `sqrtsd`, `cvtsi2sd`, `cvttsd2si`, `pxor`, `xorps`, `xorpd`, `comisd`

**AVX/AVX2**: `vmovaps`, `vmovups`, `vaddsd`, `vsubsd`, `vmulsd`, `vdivsd`, `vaddps`, `vmulps`, `vpxor`, `vpaddd`, `vpaddq`, `vpmulld`, `vfmadd132sd`, `vfmadd231sd`, `vzeroupper`

**BMI1**: `andn`, `bextr`, `blsi`, `blsmsk`, `blsr` ✅

**BMI2**: `bzhi`, `pdep`, `pext`, `rorx`, `sarx`, `shlx`, `shrx` ✅

**AES-NI**: `aesenc`, `aesenclast`, `aesdec`, `aesdeclast`, `aeskeygenassist`, `aesimc` ✅

**Memory-Imm**: `mov [m],imm`, `add [m],r`, `add [m],imm`, `sub [m],r`, `cmp [m],imm` ✅

**Flags/Fence**: `clc`, `stc`, `cmc`, `cld`, `std`, `mfence`, `sfence`, `lfence`, `pause`

**SHA**: `sha1rnds4`, `sha1nexte`, `sha1msg1`, `sha1msg2`, `sha256rnds2`, `sha256msg1`, `sha256msg2` ✅

### ⚠️ TODO: Instruções Pendentes

```dart
// TODO: AVX-512
// - Instruções básicas AVX-512 (EVEX encoding)
```

---

## 🎯 Milestones

### ✅ Completos (M0-M16)

| # | Status | Descrição |
|---|--------|-----------|
| M0 | ✅ | Projeto compila + FFI libc ok |
| M1 | ✅ | VirtMem aloca RW/RX (W^X) |
| M2 | ✅ | CodeBuffer + Label/Fixup rel8/rel32 |
| M3 | ✅ | x86_64 encoder (220+ instruções) |
| M4 | ✅ | ABI SysV/Win64 + prólogo/epílogo |
| M5 | ✅ | Jumps auto-sizing (rel8/rel32) |
| M6 | ✅ | ConstPool implementado |
| M7 | ✅ | Instruction DB Generator (1831 inst) |
| M8 | ✅ | Formatter/Logger |
| M9 | ✅ | Register Allocator (linear scan) |
| M10 | ✅ | ASMTK Parser + Builder IR + TypeId |
| M11 | ✅ | BMI1/BMI2 implementados |
| M12 | ✅ | AES-NI implementado |
| M13 | ✅ | Memory-Immediate instruções |
| M14 | ✅ | SHA Extensions |
| M15 | ✅ | FuncSignature + FuncDetail |
| M16 | ✅ | BaseBuilder + SerializerContext |

### 🚧 Em Andamento (M17-M19)

| # | Status | Descrição | Prioridade |
|---|--------|-----------|------------|
| M17 | 🚧 | X86SerializerContext (IR -> assembler) | Alta |
| M18 | ⏳ | X86Compiler (RA + Builder) | Média |
| M19 | ⏳ | AVX-512 (EVEX encoding) | Baixa |

---

## 🧪 Cobertura de Testes (311 testes)

| Arquivo | Testes |
|---------|--------|
| code_buffer_test.dart | 17 |
| labels_test.dart | 13 |
| x86_encoder_test.dart | 37 |
| x86_assembler_test.dart | 15 |
| jit_execution_test.dart | 13 |
| inline_test.dart | 23 |
| x86_extended_test.dart | 26 |
| crypto_test.dart | 19 |
| sse_test.dart | 28 |
| cpuinfo_test.dart | 7 |
| short_jump_test.dart | 5 |
| avx_test.dart | 18 |
| regalloc_test.dart | 13 |
| asmtk_test.dart | 20 |
| builder_test.dart | 18 |
| type_test.dart | 14 |
| bmi_aesni_test.dart | 25 |

---

## 📝 TODO Detalhado

### M14: Serialização IR → Assembler

```dart
// TODO: lib/src/core/builder.dart
// - Adicionar método serialize(X86Assembler asm)
// - Iterar sobre NodeList e emitir cada InstNode
// - Resolver LabelNode com bind()
// - Tratar EmbedDataNode com embedBytes()
```

### M15: FuncSignature Completo

```dart
// TODO: lib/src/x86/x86_func.dart
// - Portar FuncSignature do AsmJit
// - Suporte a múltiplos tipos de retorno
// - Suporte a parâmetros em stack
// - Cálculo automático de stack frame
// - Integração com RegAlloc
```

### M16: Compiler Pass

```dart
// TODO: lib/src/core/compiler.dart
// - Criar classe X86Compiler extends BaseBuilder
// - Integrar SimpleRegAlloc
// - Adicionar passes de otimização:
//   - Peephole optimization
//   - Dead code elimination
//   - Constant folding
```

---

## 📂 Estrutura do Projeto

```
lib/
├── asmjit.dart              # Exports públicos
└── src/
    ├── asmtk/               # Assembly Toolkit (Parser)
    │   ├── asmtk.dart
    │   ├── parser.dart
    │   └── tokenizer.dart
    ├── core/                # Core (arquitetura-independente)
    │   ├── arch.dart
    │   ├── builder.dart
    │   ├── code_buffer.dart
    │   ├── code_builder.dart
    │   ├── code_holder.dart
    │   ├── const_pool.dart
    │   ├── environment.dart
    │   ├── error.dart
    │   ├── formatter.dart
    │   ├── globals.dart
    │   ├── labels.dart
    │   ├── operand.dart
    │   ├── regalloc.dart
    │   └── type.dart
    ├── inline/              # Inline assembly helpers
    │   ├── inline_asm.dart
    │   └── inline_bytes.dart
    ├── runtime/             # JIT Runtime
    │   ├── cpuinfo.dart
    │   ├── jit_runtime.dart
    │   ├── libc.dart
    │   └── virtmem.dart
    └── x86/                 # x86/x64 específico
        ├── x86.dart
        ├── x86_assembler.dart
        ├── x86_encoder.dart
        ├── x86_func.dart
        ├── x86_inst_db.g.dart
        ├── x86_operands.dart
        └── x86_simd.dart

test/                        # 311 testes
tool/
└── gen_x86_db.dart          # Gerador do instruction DB
```

---

## 🔧 Comandos Úteis

```bash
# Analisar código
dart analyze lib

# Rodar todos os testes
dart test

# Gerar instruction database
dart run tool/gen_x86_db.dart

# Rodar teste específico
dart test test/x86_encoder_test.dart
```

---

## 📚 Referências

Os arquivos originais do AsmJit estão em `referencias/` (não usar em código/testes):

- `referencias/asmjit-master/` - AsmJit C++ original
- `referencias/asmtk-master/` - ASMTK C++ original

---

*Última atualização: 25 Dezembro 2024*