 # Roteiro de Portação: AsmJit C++ → Dart


roteiro bem prático (e incremental) para portar o AsmJit (C++) C:\MyDartProjects\asmjit\referencias\asmtk-master C:\MyDartProjects\asmjit\referencias\asmjit-master para Dart, mantendo alto desempenho e a filosofia FFI para ponteiros + libc para alocação, APIs do SO para memória executável, convenções de chamada da plataforma, e uma API “inline” de bytes ( “assembly inline via constantes para o dart”) uma API de Asembly Inline é vital para criar codigo otimizado no dart.
micro otimzações são vitais para extrair o maximo de performace 
assumir Dart Native (VM/AOT) em desktop/servidor. No iOS (e alguns ambientes “hardened”) JIT/memória executável costuma ser bloqueado por política do sistema — então trate como alvo “não suportado” ou “modo AOT/sem JIT”.

nada no codigo ou em testes podem depender de C:\MyDartProjects\asmjit\referencias
copie o que for necessario paras diretorios apropriados por exemplo C:\MyDartProjects\asmjit\assets

coloque comentarios \\ TODO onde não esta concluido ou completo

O arquivo serializer_benchmark.dart

porte os geradores e tools para dart
C:\MyDartProjects\asmjit\referencias\asmjit-master\db
C:\MyDartProjects\asmjit\referencias\asmjit-master\tools

nunca edite o codigo .g.dart gerado e sim o gerador de codigo

implementar o gerador Gerar dispatcher/serializer AArch64 a partir do DB (similar ao x86) e ligar no a64_assembler.dart.
Portar as suites pesadas do asmjit-testing (assembler_x64/x86, compiler_x86/a64, emitters, instinfo, bench) removendo os skips.
 implementar o pipeline caching (M23) e quaisquer otimizações adicionais.


porte os testes para dart
C:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit-testing

demonstrou claramente que o switch (e o if-else, que é isomórfico neste contexto) supera significativamente as buscas baseadas em List
ou Map (aceleração de aproximadamente 3x). Isso justifica a geração de uma tabela de despacho estática.

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

**Data**: 27 Dezembro 2025  
**Testes**: nao executado nesta revisao  
**Warnings**: nao verificado

Atualizações recentes:
- **Expansão Despachante SIMD X86**: Adicionadas 20+ novas instruções SSE/AVX ao dispatcher (andps/pd, orps/pd, minps/pd, maxps/pd, sqrtps/pd, rcpps, rsqrtps, vandps/pd, vorps/pd, vpor, vpand, vpaddd/q, vpmulld) com suporte para formas de registro e memória (XMM/YMM).
- **AVX Implementado**: Adicionado instruções `vsubps` e `vsubpd` (XMM/YMM) no Encoder e Assembler.
- ** Benchmarks Corrigidos**: `codegen_benchmark.dart`, `overhead_benchmark.dart` e `regalloc_benchmark.dart` atualizados e corrigidos.
- **X86Mem.ptr**: Adicionado factory `ptr` para conveniência.
- **gen_a64_db.dart expandido**: Dispatcher A64 agora tem handlers para mais instruções NEON/FP (fneg, fabs, fsqrt, fcmp, fcsel, etc - marcados como TODO).
- **emitters_test.dart criado**: Suite completa portada do asmjit_test_emitters.cpp com 14 testes para X86/A64 Assembler e Builder.
- **codegen_benchmark.dart criado**: Benchmark de geração de código X86 e A64 portado de asmjit_bench_codegen_x86.cpp.
- Serializer agora depende apenas do dispatcher gerado via switch (sem Map fallback).
- gen_x86_db.dart gera dispatcher real para o conjunto implementado e instdb.
- gen_tables.dart integra enumgen opcional.
- gen_a64_db captura categorias/extensões/raw para futuro dispatcher A64 e agora gera handlers para ldrb/ldrh/strb/strh.
- smoke tests de dispatcher/instdb adicionados (asmjit_testing_port_test.dart).
- Suite asmjit_test_instinfo parcialmente portada (checagem de nomes/IDs); skips reduzidos.
- NEON inteiro (add/sub/mul/and/orr/eor) e dispatcher A64 para vetores adicionados.
- Suite asmjit_test_compiler_x86 portada com multiplos cenarios (branch, loop, jumps, spills basicos).
- X86CodeBuilder agora cria labels via CodeHolder e faz shuffle seguro de argumentos.
- Scaffold inicial de asmjit_test_assembler_x86/x64 (sanity encoding) sem depender de referencias/.
- Suite asmjit_test_compiler_a64 portada (prologo/epilogo, branches, NEON/FP encode).
- Suite asmjit_bench_codegen_x86 portada (loop de codegen e validacao de bytes).
- JitRuntime agora tem pipeline cache (addCached/addBytesCached).
- A64CodeBuilder agora tem RA + spills (GP/NEON) com slots em stack.
- Teste de cache do JitRuntime (reuso por chave) adicionado.
- Tratamento de spills com offsets grandes (materializa endereco em registrador temporario).
- Caso de spill para vetores (NEON) adicionado no teste A64.
- Spills agora respeitam o stackSize definido pelo usuario (base de spill separada).

## Revisao do C++ original (resumo)

- Relatorio detalhado em `relatorio_portacao.md`.
- Benchmarks Dart executados (quick): `codegen_benchmark.dart`, `overhead_benchmark.dart`,
  `regalloc_benchmark.dart`, `serializer_benchmark.dart`.
- Divergencias notaveis com o C++:
  - `codegen_benchmark.dart`: `Builder [finalized]` sem gerar bytes (CodeSize 0).
  - `regalloc_benchmark.dart`: AArch64 falha com `labelAlreadyBound`.
  - Falta paridade de cenarios/emitters nas suites de benchmark.


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
| `compiler.h/.cpp` | - | ⚠️ Parcial (CFG + liveness básicos) |
| `rapass.h/.cpp` | `regalloc.dart` | ✅ (linear scan) |
| `jitruntime.h/.cpp` | `jit_runtime.dart` | ✅ |
| `jitallocator.h/.cpp` | `virtmem.dart` | ✅ |
| `cpuinfo.h/.cpp` | `cpuinfo.dart` | ✅ |
| `instdb.h` | `x86_inst_db.g.dart` | ✅ (1831 inst) |
| `a64 instdb` | `a64_inst_db.g.dart` | ✅ (1347 inst) |

### x86 (`asmjit/x86/` → `lib/src/x86/`)

| Arquivo C++ | Arquivo Dart | Status |
|-------------|--------------|--------|
| `x86globals.h` | `x86.dart` | ✅ |
| `x86operand.h/.cpp` | `x86_operands.dart` | ✅ |
| `x86assembler.h/.cpp` | `x86_assembler.dart` | ✅ (150+ métodos) |
| `x86emitter.h` | `x86_encoder.dart` | ✅ (200+ instruções) |
| `x86instdb.h/.cpp` | `x86_inst_db.g.dart` | ✅ |
| `x86func.h` | `x86_func.dart` | ✅ (FuncFrame) |
| `x86rapass.h/.cpp` | - | ⚠️ Parcial |
| `x86builder.h/.cpp` | `code_builder.dart` | ⚠️ Parcial (RA + frame, faltam atributos avançados) |
| - | `x86_serializer.dart` | ✅ |
| `x86compiler.h/.cpp` | - | ⚠️ Parcial |
| `arm a64 dispatcher/serializer` | `a64_dispatcher.g.dart` / `a64_serializer.dart` | ✅ (subset, precisa ampliar) |

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

**SSE/SSE2**: `movaps`, `movups`, `movsd`, `movss`, `addps`, `addpd`, `subps`, `subpd`, `mulps`, `mulpd`, `divps`, `divpd`, `sqrtsd`, `sqrtps`, `sqrtpd`, `cvtsi2sd`, `cvttsd2si`, `pxor`, `xorps`, `xorpd`, `andps`, `andpd`, `orps`, `orpd`, `minps`, `minpd`, `maxps`, `maxpd`, `rcpps`, `rsqrtps`, `comisd`

**AVX/AVX2**: `vmovaps`, `vmovups`, `vaddsd`, `vsubsd`, `vmulsd`, `vdivsd`, `vaddps`, `vaddpd`, `vsubps`, `vsubpd`, `vmulps`, `vmulpd`, `vdivps`, `vdivpd`, `vpxor`, `vxorps`, `vxorpd`, `vandps`, `vandpd`, `vorps`, `vorpd`, `vpor`, `vpand`, `vpaddd`, `vpaddq`, `vpmulld`, `vfmadd132sd`, `vfmadd231sd`, `vzeroupper`


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

### ✅ Completos (M0-M20)

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
| M15 | ✅ | FuncSignature + FuncDetail e Frame |
| M16 | ✅ | BaseBuilder + SerializerContext |
| M17 | ✅ | X86SerializerContext (Builder -> Assembler) |
| M18 | ✅ | X86Compiler (RA + Builder integration) |
| M19 | ✅ | AVX-512 Support (EVEX, ZMM, Mask) |
| M20 | ✅ | Optimization (Generated Dispatcher, Hybrid Serializer) |

### 🚧 Em Andamento (M21-M24)

| # | Status | Descrição | Prioridade |
|---|--------|-----------|------------|
| M21 | 🏗️ | Compiler IR Expansion (FuncNode, BlockNode, CFG, liveness) | Nodes criados + liveness básica |
| M22 | 🏗️ | AArch64 Backend Completion + Dispatcher | Dispatcher gerado com TODO para instruções adicionais |
| M23 | ✅ | JitRuntime Pipeline Caching (Pointer<Void> stubs) | Performance para JIT |
| M24 | 🏗️ | Portar asmjit-testing suites pesadas | emitters_test.dart completo; scaffold de assembler/compiler tests |

---

## 🧪 Cobertura de Testes (381 testes)

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
| compiler_test.dart | 1 |
| x86_avx512_test.dart | 1 |
| **emitters_test.dart** | **14** |
| asmjit_testing_port_test.dart | ~30 |
| cfg_test.dart | ~6 |

---

## 📝 TODO Detalhado

### M21: Compiler IR Expansion

```dart
// TODO: lib/src/core/builder.dart
// - Create FuncNode to hold Function Frame and Arguments
// - Create BlockNode (Basic Block) for control flow
// - Update BaseBuilder to manage generic nodes
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

test/                        # 381 testes
benchmark/
├── serializer_benchmark.dart
└── codegen_benchmark.dart
tool/
├── gen_x86_db.dart          # Gerador do instruction DB x86
├── gen_a64_db.dart          # Gerador do instruction DB AArch64
├── gen_tables.dart          # Unifica geração de tabelas
└── gen_enum.dart            # Gerador de enums
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

*Última atualização: 26 Dezembro 2024*
