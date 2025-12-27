 # Roteiro de Portação: AsmJit C++ → Dart


roteiro bem prático (e incremental) para portar o AsmJit (C++) C:\MyDartProjects\asmjit\referencias\asmtk-master C:\MyDartProjects\asmjit\referencias\asmjit-master para Dart, mantendo alto desempenho e a filosofia FFI para ponteiros + libc para alocação, APIs do SO para memória executável, convenções de chamada da plataforma, e uma API “inline” de bytes ( “assembly inline via constantes para o dart”) uma API de Asembly Inline é vital para criar codigo otimizado no dart.
micro otimzações são vitais para extrair o maximo de performace 
assumir Dart Native (VM/AOT) em desktop/servidor. No iOS (e alguns ambientes “hardened”) JIT/memória executável costuma ser bloqueado por política do sistema — então trate como alvo “não suportado” ou “modo AOT/sem JIT”.

mantenha este roteiro atualizado

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

## 🧩 Blend2D Porting Readiness (Avaliação Crítica)

**Status**: 🟠 **Parcialmente Bloqueante**

Para iniciar o porte da parte **JIT** do Blend2D (`pipecompiler.cpp`), o AsmJit Dart precisa evoluir em:

1.  🔴 **Compiler IR & CodeGen (Crítico)**:
    - O Blend2D usa intensivamente `Compiler` para construir pipelines (`PipeCompiler`).
    - `builder.dart` possui a estrutura de nós (`FuncNode`, `BlockNode`), mas `serializeNodes` ainda ignora `Func/Invoke` quando usado direto.
    - **Novo**: `X86IrCompiler` agora baixa `Func/Invoke` e emite código via `X86Serializer`, com CFG/liveness no fluxo e suporte a múltiplas funções.
    - Ainda falta evoluir o backend de compiler (RA/IR avançado + reescrita completa) para paridade com o C++.

2.  🟡 **Heavy Test Suites**:
    - Antes de confiar no JIT para renderização de pixels (onde bugs visuais são difíceis de debugar), precisamos rodar as suites pesadas: `asmjit_test_assembler_x86`, `asmjit_test_compiler_x86`.

3.  🟢 **AArch64 Completo**:
    - Necessário para targets mobile (Android/iOS), mas o desenvolvimento pode começar focando em x86_64.

**Conclusão**: O porte do **Reference Pathway** (Pure Dart) do Blend2D pode começar imediatamente. O porte do **JIT Pathway** deve aguardar a estabilização do `Compiler` (M21/M25).

## 📊 Status Atual

**Data**: 27 Dezembro 2025  
**Testes**: nao executado nesta revisao  
**Warnings**: nao verificado

Atualizacoes recentes:
- **IR puro -> assembler**: `X86IrCompiler` compila `builder.dart` (Func/Invoke) com CFG/liveness e suporta multiplas funcoes por NodeList.
- **Labels IR**: `CodeHolder.ensureLabelCount()` garante IDs de labels criados no IR antes da emissao.
- **Codegen benchmark com AVX-512**: sequencias ZMM (reg/mem) adicionadas, removendo o TODO de paridade.
- **Overhead benchmark alinhado**: inclui caminhos de Compiler/Builder + RT e reinit com reset de nodes.
- **Regalloc benchmark com memoria**: tabela agora reporta estimativas de memoria (CodeHolder/nodes).
- **Retorno mask default**: `endFunc()` agora zera `k0` via `kmovw/d/q` conforme tamanho do retorno.
- **Retorno MMX default**: MMX agora usa `xmm0` (alias) zerado com `pxor`, evitando fallback em GP.
- **KMOV no dispatcher**: encoder/assembler/dispatcher suportam `kmovw/d/q` (reg <-> k).
- **Stack args com labels**: `invoke()` aceita `LabelOperand` para stack arg quando a label ja esta bound (usa offset imediato).
- **IR deduplicado**: `core/ir.dart` agora reexporta `builder.dart`/`compiler.dart` (sem definicoes duplicadas).
- **Imediatos vetoriais (nao-zero)**: `invoke()` agora materializa constantes em XMM/YMM/ZMM via scratch na pilha.
- **serializeNodes expandido**: casos `func/funcRet/invoke/section/constPool/embedLabel/jump` agora sao no-op.
- **CodeWriter inicial**: `core/code_writer.dart` criado com emissao sequencial em `CodeHolder` e troca de section.
- **InstAPI parcial**: metadata de read/write adicionada para instrucoes x86 mais comuns.
- **Opcoes de encoding/diagnostico**: `X86Compiler` agora propaga `encodingOptions` e `diagnosticOptions` para o assembler.
- **Addressing via vetores**: `Mem` com base/index em registradores vetoriais agora usa os bits baixos via `movq/movd` para GP temporario.
- **Stack args de memoria**: `_emitCallStackArg()` agora aceita `MemOperand`, carregando via `r11` antes de armazenar na pilha.
- **Imediatos vetoriais (zero)**: `invoke()` agora aceita imediato `0` para argumentos vetoriais (zera XMM/YMM via `pxor/vpxor`).
- **Stack args vetoriais**: argumentos vetoriais ZMM agora podem ser passados na pilha via `vmovups`.
- **Args vetoriais fixos**: prologo agora move argumentos XMM/YMM/ZMM a partir dos registradores ABI (xmm0..xmm7 / xmm0..xmm3).
- **Retorno spill vetorial**: `invoke()` com retorno vetorial em spill agora armazena a partir de `xmm0/ymm0/zmm0`.
- **Args em regs fisicos**: `setArg()` agora aceita registradores fisicos e faz o move do ABI para o reg fixo (GP).
- **Retorno spill em chamadas**: se o retorno da `invoke()` cair em spill (GP), o builder move via `r11` e armazena no slot de stack.
- **Retorno default vetorial**: `endFunc()` agora zera `xmm0/ymm0/zmm0` para retornos vetoriais quando nenhum retorno e definido.
- **Call moves sem temp**: quando nao ha registrador temporario livre em shuffles de argumentos, o builder usa `push`/`pop` para quebrar ciclos.
- **Invoke sem assinatura**: chamadas sem `FuncSignature` agora emitem `call` direto e movem retorno a partir de `rax/xmm0/ymm0/zmm0` quando solicitado.
- **ZMM em chamadas**: movs de argumentos/retornos ZMM agora usam `vmovups` no builder; dispatcher x86 passou a suportar ZMM em `vmovups` (reg/mem).
- **IR Serialization corrigida**: `serializeNodes` agora possui `break` em todos os `case`, evitando fallthrough e serialização inválida (impacta `Builder [finalized]`).
- **Dispatcher A64 expandido**: `ldur`/`stur` incluídos no `gen_a64_db.dart` e regenerado `a64_dispatcher.g.dart`.
- **Implementações AVX Completas**: vandps/pd, vorps/pd, vpor, vpand, vpaddq (XMM/YMM + memória) adicionadas ao Encoder e Assembler
- **Expansão Despachante SIMD X86**: Adicionadas 20+ novas instruções SSE/AVX ao dispatcher (andps/pd, orps/pd, minps/pd, maxps/pd, sqrtps/pd, rcpps, rsqrtps, vandps/pd, vor ps/pd, vpor, vpand, vpaddd/q, vpmulld) com suporte para formas de registro e memória (XMM/YMM).
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
  - `codegen_benchmark.dart`: `Builder [finalized]` sem gerar bytes (CodeSize 0) **corrigido via** `serializeNodes` com `break` (revalidar benchmark).
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

### M22: AArch64 Backend & Tools
- [ ] **Gen A64 Dispatcher**: Implementar gerador de dispatcher/serializer para AARCH64 (`gen_a64_db.dart`) similar ao x86.
- [ ] **Gen A64 Serializer**: Gerar `a64_dispatcher.g.dart` e ligar ao Assembler.

### M24: Verification & Optimization
- [ ] **Heavy Suites**: Portar `asmjit_test_assembler_x64`, `asmjit_test_compiler_x86` e `asmjit_test_emitters`.
- [ ] **Pipeline Caching**: Verificar e otimizar `JitRuntime` caching (revalidar M23).


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
dart analyze 

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

# Relatorio de Revisao (AsmJit C++ -> Dart)

Este relatorio compara o codigo original (C++) com o estado atual do port
em Dart e lista o que ainda falta portar ou alinhar.

## Escopo da revisao
- Base: `referencias/asmjit-master` e `referencias/asmtk-master`.
- Dart: `lib/`, `test/`, `tool/`, `benchmark/`.
- Saidas C++ usadas para referencia: `benchmark/cpp.md`.

## Faltas principais (alto nivel)
- Core: falta portar utilitarios de suporte (`support/*`), logger avancado,
  `codewriter`, `emitter`/`emitterutils`, `osutils`, `string`, `target`,
  `inst`/`instapi` genericos e infraestrutura completa de `compiler`.
- x86: `x86compiler` e `x86rapass` incompletos, `x86emithelper` ausente,
  formatter x86 parcial, e coverage de instrucao ainda distante do C++.
- AArch64: `a64compiler`, `a64rapass`, `a64emithelper`, formatter a64 e
  instrucoes/instapi muito incompletas; dispatcher/serializer ainda subset.
- UJIT/unicompiler: nao portado (`ujit/*`).
- ASMTK: parser/tokenizer basicos, faltam features avancadas do C++.
- Tools/DB: geradores Dart cobrem x86 e parte de A64, mas ainda nao replicam
  toda a pipeline do `db/` e `tools/` originais.

## Testes (asmjit-testing)
- Port parcial: `emitters_test.dart`, partes de assembler/compiler e instinfo.
- Faltam portas completas de:
  - `asmjit_test_assembler_x86/x64/a64.cpp`
  - `asmjit_test_compiler_x86/a64.cpp`
  - `asmjit_test_unicompiler*.cpp`
  - `asmjit_test_x86_sections.cpp`
  - `asmjit_test_environment.cpp`
  - `asmjit_test_runner.cpp` (infra/harness)

## Benchmarks (paridade com C++)
- `benchmark/codegen_benchmark.dart`:
  - Cobertura expandida com sequencias AVX-512 (ZMM reg/mem).
  - Ainda sem paridade total do mix de instrucoes do C++.
  - `Builder [finalized]` gera `CodeSize: 0` **corrigido** via `serializeNodes` com `break` (revalidar benchmark).
- `benchmark/overhead_benchmark.dart`:
  - Alinhado com caminhos de `compiler`/`builder` e cobertura de RT em A64.
  - Ainda sem `code.init()`/`attach()` e error handler (nao existem no Dart).
- `benchmark/regalloc_benchmark.dart`:
  - Tabela agora mostra estimativas de memoria (CodeHolder/nodes); pipeline ainda simplificado vs C++.
  - `CodeSize` sai `0` e A64 falha com `labelAlreadyBound`.
- `benchmark/serializer_benchmark.dart`:
  - Benchmark custom (nao tem equivalente direto no C++).

## Saidas recentes (Dart)
- Executado com `--quick`:
  - `dart run benchmark/codegen_benchmark.dart --quick`
  - `dart run benchmark/overhead_benchmark.dart --quick`
  - `dart run benchmark/regalloc_benchmark.dart --quick`
  - `dart run benchmark/serializer_benchmark.dart`
- Observacoes:
  - `codegen_benchmark.dart`: `Builder [finalized]` -> `CodeSize: 0`.
  - `regalloc_benchmark.dart`: AArch64 -> `AsmJitException[labelAlreadyBound]`.

## Atualizacoes desta revisao
- Corrigido `Bad state: A64 scratch GP registers exhausted` expandindo a pool
  de registradores scratch (A64). Testado ate `--complexity 2048` sem erro.

## Recomendacoes imediatas
- Criar `finalize()` no `X86CodeBuilder` (paridade com A64) para benchmarks.
- Ajustar `regalloc_benchmark.dart` para usar pipeline real e labels corretos.
- Expandir `codegen_benchmark.dart` com cenarios do C++ e emissores faltantes.

Expand SIMD dispatcher coverage in gen_x86_db.dart so builder SSE/AVX sequences can use the full instruction mix (removes current TODO limits).

Implement the X86 compiler backend to replace the compiler placeholders with real numbers.

---

## 🔍 Análise Detalhada: Código C++ Original vs. Dart Port

### Estrutura Original (AsmJit C++)

Baseado em `referencias/asmjit-master/asmjit/`:

#### 📁 **Core** (`core/` → 79 arquivos)

| Componente C++ | Arquivo Original | Tamanho | Status Dart | Prioridade |
|----------------|------------------|---------|-------------|------------|
| **ArchTraits** | `archtraits.h/.cpp` | 10 KB, 4 KB | ✅ `arch.dart` | ✅ |
| **Assembler** | `assembler.h/.cpp` | 4 KB, 12 KB | ✅ `x86_assembler.dart`, `a64_assembler.dart` | ✅ |
| **Builder** | `builder.h/.cpp` | 55 KB, 24 KB | ⚠️ Parcial `code_builder.dart` | 🔴 **Crítico** |
| **CodeBuffer** | `codebuffer.h` | 3 KB | ✅ `code_buffer.dart` | ✅ |
| **CodeHolder** | `codeholder.h/.cpp` | 52 KB, 45 KB | ✅ `code_holder.dart` | ✅ |
| **CodeWriter** | `codewriter.cpp`, `codewriter_p.h` | 8 KB, 5 KB | ❌ | 🟡 Média |
| **Compiler** | `compiler.h/.cpp` | 30 KB, 19 KB | ⚠️ Básico `builder.dart` (CFG) | 🔴 **Crítico** |
| **CompilerDefs** | `compilerdefs.h` | 10 KB | ❌ | 🟡 Média |
| **ConstPool** | `constpool.h/.cpp` | 7 KB, 9 KB | ✅ `const_pool.dart` | ✅ |
| **CpuInfo** | `cpuinfo.h/.cpp` | 75 KB, 92 KB | ✅ `cpuinfo.dart` | ✅ |
| **EmitHelper** | `emithelper.cpp`, `emithelper_p.h` | 11 KB, 2 KB | ❌ | 🟡 Média |
| **Emitter** | `emitter.h/.cpp` | 40 KB, 12 KB | ⚠️ Parcial (X86/A64 encoder) | 🟡 |
| **EmitterUtils** | `emitterutils.cpp`, `emitterutils_p.h` | 4 KB, 2 KB | ❌ | 🟢 Baixa |
| **Environment** | `environment.h/.cpp` | 19 KB, 1 KB | ✅ `environment.dart` | ✅ |
| **ErrorHandler** | `errorhandler.h/.cpp` | 7 KB, 0.5 KB | ⚠️ VirtMem errors apenas | 🟡 |
| **Formatter** | `formatter.h/.cpp` | 8 KB, 18 KB | ⚠️ Parcial `formatter.dart` | 🟡 |
| **Func** | `func.h/.cpp` | 77 KB, 12 KB | ✅ `x86_func.dart` (FuncSignature) | ✅ |
| **FuncArgsContext** | `funcargscontext.cpp`, `funcargscontext_p.h` | 11 KB, 7 KB | ❌ | 🟡 Média |
| **Globals** | `globals.h/.cpp` | 15 KB, 3 KB | ✅ `globals.dart` | ✅ |
| **Inst** | `inst.h/.cpp` | 34 KB, 3 KB | ⚠️ Enum em `x86_inst_db.g.dart` | 🟡 |
| **InstDB** | `instdb.cpp`, `instdb_p.h` | 4 KB, 1 KB | ✅ Gerado `x86_inst_db.g.dart`, `a64_inst_db.g.dart` | ✅ |
| **JitAllocator** | `jitallocator.h/.cpp` | 24 KB, 58 KB | ✅ `virtmem.dart` | ✅ |
| **JitRuntime** | `jitruntime.h/.cpp` | 3 KB, 2 KB | ✅ `jit_runtime.dart` + cache | ✅ |
| **Logger** | `logger.h/.cpp` | 7 KB, 1 KB | ⚠️ Básico em `formatter.dart` | 🟡 |
| **Operand** | `operand.h/.cpp` | 120 KB, 3 KB | ✅ `operand.dart`, `x86_operands.dart` | ✅ |
| **OSUtils** | `osutils.h/.cpp`, `osutils_p.h` | 1 KB, 1 KB, 2 KB | ⚠️ Parcial (libc.dart) | 🟡 |
| **RAPass (Register Allocator)** |
| - RAAssignment | `raassignment_p.h` | 17 KB | ❌ | 🔴 Alta |
| - RACFGBlock | `racfgblock_p.h` | 13 KB | ⚠️ Básico `CFGBlock` | 🟡 |
| - RACFGBuilder | `racfgbuilder_p.h` | 23 KB | ⚠️ Básico `CFGBuilder` | 🟡 |
| - RAConstraints | `raconstraints_p.h` | 1 KB | ❌ | 🟡 |
| - RADefs | `radefs_p.h` | 32 KB | ❌ | 🟡 |
| - RAInst | `rainst_p.h` | 13 KB | ❌ | 🟡 |
| - RALocal | `ralocal.cpp`, `ralocal_p.h` | 48 KB, 10 KB | ❌ | 🔴 Alta |
| - RAPass | `rapass.cpp`, `rapass_p.h` | 75 KB, 23 KB | ⚠️ Linear scan básico | 🔴 **Crítico** |
| - RAReg | `rareg_p.h` | 13 KB | ❌ | 🟡 |
| - RAStack | `rastack.cpp`, `rastack_p.h` | 5 KB, 4 KB | ✅ Spills básicos | 🟡 |
| **String** | `string.h/.cpp` | 13 KB, 15 KB | ❌ Usar Dart `String` | 🟢 |
| **Target** | `target.h/.cpp` | 1 KB, 0.4 KB | ❌ | 🟢 |
| **Type** | `type.h/.cpp` | 18 KB, 2 KB | ✅ `type.dart` | ✅ |
| **VirtMem** | `virtmem.h/.cpp` | 13 KB, 36 KB | ✅ `virtmem.dart` | ✅ |
| **Support (utilitários)** | `support/*` | ? | ❌ | 🟡 |

**⚠️ CRÍTICO**:
- **Compiler infraestrutura completa**: C++ tem ~50 KB de código para construir IR completo (nodes, edges, liveness). Dart tem apenas scaffold básico.
- **RAPass completo**: C++ tem 75 KB de register allocator avançado (graph coloring, local/global RA). Dart tem linear scan básico.

---

#### 📁 **x86** (`x86/` → 25 arquivos)

| Componente | Arquivo C++ | Tamanho | Status Dart | Ação |
|------------|-------------|---------|-------------|------|
| **x86Globals** | `x86globals.h` | 156 KB | ✅ `x86.dart` (enums) | ✅ |
| **x86Operand** | `x86operand.h/.cpp` | 53 KB, 7 KB | ✅ `x86_operands.dart` | ✅ |
| **x86Assembler** | `x86assembler.h/.cpp` | 29 KB, 159 KB | ✅ `x86_assembler.dart` (150+ métodos) | ⚠️ Faltam grupos |
| **x86Builder** | `x86builder.h/.cpp` | 14 KB, 1 KB | ⚠️ `code_builder.dart` básico | Adicionar `x86Builder` específico |
| **x86Compiler** | `x86compiler.h/.cpp` | 36 KB, 1 KB | ❌ | 🔴 **Crítico** |
| **x86Emitter** | `x86emitter.h` | 305 KB | ⚠️ `x86_encoder.dart` (200+ inst) | Faltam AVX-512 completo |
| **x86EmitHelper** | `x86emithelper.cpp`, `x86emithelper_p.h` | 21 KB, 5 KB | ❌ | Helpers de arg shuffling |
| **x86Formatter** | `x86formatter.cpp`, `x86formatter_p.h` | 31 KB, 1 KB | ⚠️ Básico | Expandir mnemonics |
| **x86Func** | `x86func.cpp`, `x86func_p.h` | 19 KB, 1 KB | ✅ `x86_func.dart` | ✅ |
| **x86InstAPI** | `x86instapi.cpp`, `x86instapi_p.h` | 74 KB, 1 KB | ❌ | Validação/query de inst |
| **x86InstDB** | `x86instdb.cpp/.h`, `x86instdb_p.h` | 512 KB, 30 KB, 17 KB | ✅ Gerado `x86_inst_db.g.dart` (1831 inst) | ✅ |
| **x86Opcode** | `x86opcode_p.h` | 20 KB | ⚠️ Inline em encoder | ✅ |
| **x86RAPass** | `x86rapass.cpp`, `x86rapass_p.h` | 59 KB, 2 KB | ❌ | X86-specific RA refinements |
| **Serializer** | - | - | ✅ `x86_serializer.dart` (custom) | ✅ |

**Instruções x86:**
- C++: Suporta 1831 instruções (todos prefixos, EVEX, etc.)
- Dart: ~220 instruções implementadas (SSE2, AVX, AVX2, BMI1/2, AES, SHA)
- **Faltam**: AVX-512 completo, FPU, MMX legacy, instruções obscuras

---

#### 📁 **ARM** (`arm/` → 28 arquivos)

| Componente | Arquivo C++ | Tamanho | Status Dart | Ação |
|------------|-------------|---------|-------------|------|
| **a64Globals** | `a64globals.h` | 128 KB | ⚠️ `a64.dart` Parcial | Expandir enums |
| **a64Operand** | `a64operand.h/.cpp` | 47 KB, 2 KB | ✅ `a64_operands.dart` | ✅ |
| **a64Assembler** | `a64assembler.h/.cpp` | 1 KB, 171 KB | ✅ `a64_assembler.dart` Básico | 🔴 Faltam MUITOS métodos |
| **a64Builder** | `a64builder.h/.cpp` | 1 KB, 1 KB | ✅ `a64_code_builder.dart` | ✅ |
| **a64Compiler** | `a64compiler.h/.cpp` | 12 KB, 1 KB | ❌ | 🔴 Crítico |
| **a64Emitter** | `a64emitter.h` | 48 KB | ⚠️ `a64_encoder.dart` subset | Adicionar NEON completo |
| **a64EmitHelper** | `a64emithelper.cpp`, `a64emithelper_p.h` | 14 KB, 1 KB | ❌ | Helpers de prologue/epilogue |
| **a64Formatter** | `a64formatter.cpp`, `a64formatter_p.h` | 1 KB, 1 KB | ❌ | Mnemonics ARM |
| **a64Func** | `a64func.cpp`, `a64func_p.h` | 7 KB, 1 KB | ⚠️ Básico | Calling conventions |
| **a64InstAPI** | `a64instapi.cpp`, `a64instapi_p.h` | 7 KB, 1 KB | ❌ | Query/validation |
| **a64InstDB** | `a64instdb.cpp/.h`, `a64instdb_p.h` | 230 KB, 2 KB, 21 KB | ✅ Gerado `a64_inst_db.g.dart` (1347 inst) | ✅ |
| **a64RAPass** | `a64rapass.cpp`, `a64rapass_p.h` | 32 KB, 2 KB | ❌ | A64-specific RA |
| **Dispatcher** | - | - | ⚠️ `a64_dispatcher.g.dart` TODO stubs | Implementar handlers |
| **Serializer** | - | - | ⚠️ `a64_serializer.dart` subset | Expandir encoding |

**⚠️ Gap Crítico**:
- C++ `a64assembler.cpp`: 171 KB de métodos (centenas de instruções NEON, FP, LD/ST variants)
- Dart `a64_assembler.dart`: Apenas ~30 métodos básicos
- **Faltam**: 90%+ das instruções ARM64

---

#### 📁 **UJIT** (`ujit/` → ?)

Universal JIT compiler (não portado):

- Cross-architecture IR
- `ujit/*.h/*.cpp`
- **Status**: ❌ Não iniciado
- **Prioridade**: 🟢 Baixa (não essencial para Blend2D)

---

#### 📁 **Support** (`support/` → ?)

Utilitários (strings, math, memory):

- Provavelmente 10-20 arquivos
- **Status**: ❌ Substituir por `dart:core`, `dart:math`, etc.
- **Prioridade**: 🟢 Baixa

---

### 📁 **DB (Database)** (`db/` → arquivos de dados)

Definições de instruções em formato estruturado:

```
db/
├── a64.json (ou similar)
├── x86.json
└── ...
```

**C++ Tools** (`tools/`):
- Geradores de código C++ a partir de `db/`
- Scripts 

**Dart Tools** (`tool/`):
- ✅ `gen_x86_db.dart`: Gera `x86_inst_db.g.dart` e dispatcher
- ✅ `gen_a64_db.dart`: Gera `a64_inst_db.g.dart` e dispatcher (com TODOs)
- ✅ `gen_tables.dart`: Unifica geração
- ✅ `gen_enum.dart`: Gera enums

**Gap**: Geradores Dart não replicam 100% da pipeline C++ (algumas metadata ausentes).

---

### 📋 **Checklist: Componentes Faltantes (Priorizado)**

#### 🔴 **Crítico (Core do Compiler)**

- [ ] **Compiler IR completo** (`compiler.h/.cpp`):
  - [ ] `FuncNode` (representa função com args, locals)
  - [ ] `BlockNode` (basic blocks)
  - [ ] `InstNode` (instruções no IR)
  - [ ] `LabelNode`, `JumpNode`
  - [ ] `VarNode` (variáveis virtuais)
  - [ ] Liveness analysis avançada
  - [ ] Dominance tree
  - [ ] Loop detection

- [ ] **RAPass avançado** (`rapass.cpp`):
  - [ ] Graph coloring register allocation
  - [ ] Live range splitting
  - [ ] Spill cost calculation
  - [ ] Rematerialization
  - [ ] COPY coalescing

- [ ] **x86Compiler** (`x86compiler.h/.cpp`):
  - [ ] Integration com IR
  - [ ] X86-specific prologue/epilogue
  - [ ] Emit helpers

- [ ] **a64Compiler** (`a64compiler.h/.cpp`):
  - [ ] ARM64-specific prologue/epilogue
  - [ ] AAPCS calling conv completa

#### 🟡 **Alta (Cobertura de Instruções)**

- [ ] **x86 AVX-512** (EVEX encoding):
  - [ ] Máscaras (`k0-k7`)
  - [ ] ZMM registers (`zmm0-zmm31`)
  - [ ] Embedded broadcast
  - [ ] Rounding control

- [ ] **a64 NEON completo**:
  - [ ] Vector load/store (LD1/ST1 com post-index, etc.)
  - [ ] Advanced SIMD arithmetic (100+ instruções)
  - [ ] FP16, BF16 variants
  - [ ] SVE (Scalable Vector Extension) ?

- [ ] **x86 FPU legacy** (x87):
  - [ ] FLD, FST, FADD, FMUL, etc.

#### 🟡 **Média (Utilitários)**

- [ ] **EmitHelper** (`emithelper.cpp`, x86/a64):
  - [ ] Argument shuffling (reg → stack, stack → reg)
  - [ ] Calling convention helpers

- [ ] **FuncArgsContext** (`funcargscontext.cpp`):
  - [ ] Argument assignment (GP, XMM, stack)
  - [ ] Variadic functions

- [ ] **InstAPI** (x86/a64):
  - [ ] Query instruction properties
  - [ ] Validate operand combinations

- [ ] **Formatter avançado**:
  - [ ] Mnemonics completos
  - [ ] AT&T syntax (além de Intel)
  - [ ] Comments/annotations

- [ ] **CodeWriter** (`codewriter.cpp`):
  - [ ] High-level code serialization

#### 🟢 **Baixa (Nice-to-have)**

- [ ] **UJIT**: Cross-arch IR
- [ ] **Support libs**: Usar Dart equivalents
- [ ] **String class**: Usar `dart:core` `String`
- [ ] **Target abstraction**: Minimal

---

## 🎯 **Recomendações para Próximas Iterações**


1. **Expandir a64Assembler**:
   - Portar 50+ métodos de `a64assembler.cpp` (focus: NEON integer ops)
   - Testar cada grupo (add/sub/mul NEON)

2. **Implementar FuncNode/BlockNode** (IR):
   - Criar `lib/src/core/ir.dart`
   - `class FuncNode`, `class BlockNode`, `class InstNode`
   - Integrar com `Builder`

3. **Adicionar x86EmitHelper básico**:
   - Argument shuffling simples
   - Preparar para x86Compiler


4. **x86Compiler skeleton**:
   - Criar `lib/src/x86/x86_compiler.dart`
   - Prólogo/epílogo com RA
   - Emit de função completa

5. **a64Compiler skeleton**:
   - Criar `lib/src/arm/a64_compiler.dart`
   - AAPCS calling convention

6. **RAPass com graph coloring**:
   - Implementar algoritmo Chaitin-Briggs (simplificado)
   - Comparar performance com linear scan


7. **AVX-512 completo**:
   - EVEX encoder
   - ZMM, masks, embedded ops

8. **a64 NEON completo**:
   - Port de todos os grupos de `a64emitter.h`

9. **InstAPI e validação**:
   - Runtime validation de operandos
   - Mensagens de erro melhores

10. **Formatter AT&T**:
    - Syntax alternativa para x86

---

## 📚 **Arquivos C++ Críticos para Estudar**

**Core Compiler**:
- `compiler.cpp` (19 KB) - IR construction
- `rapass.cpp` (75 KB) - Register allocator master
- `builder.cpp` (24 KB) - Builder integration

**x86**:
- `x86assembler.cpp` (159 KB) - Todos os métodos de instrução
- `x86compiler.cpp` (1 KB wrapper + includes) - Integration
- `x86rapass.cpp` (59 KB) - X86-specific RA

**ARM64**:
- `a64assembler.cpp` (171 KB) - **CRÍTICO** - centenas de instruções
- `a64rapass.cpp` (32 KB) - ARM64 RA nuances

**Geração de Código**:
- `tools/` (Python scripts) - Geradores originais
- `db/` (JSON/estruturado) - Database de instruções

---


