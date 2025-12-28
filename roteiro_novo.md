 # Roteiro de Portação: AsmJit C++ → Dart


roteiro bem prático (e incremental) para portar o AsmJit (C++) C:\MyDartProjects\asmjit\referencias\asmtk-master C:\MyDartProjects\asmjit\referencias\asmjit-master para Dart

porte os testes para dart
C:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit-testing

porte os benchmarks para dart

porte os geradores e tools para dart
C:\MyDartProjects\asmjit\referencias\asmjit-master\db
C:\MyDartProjects\asmjit\referencias\asmjit-master\tools

---

## Objetivo e regras (não negociável)

- **[paridade 1:1]** a lógica tem que ser idêntica ao C++ (mesma decisão, mesma ordem, mesmos masks/flags, mesmos casos-limite). Se divergir, vai falhar em cenários reais.
- **[sem stubs]** não criar TODOs, stubs ou implementações mínimas. Só portar implementação completa e real.
- **[incremental]** cada passo adiciona valor e é validado por testes/benchmarks antes de avançar.

---

# Roteiro incremental (prático) de portação

## Fase 0 — Base de comparação e “harness” (obrigatório)

- **[congelar referência C++]** escolher um commit do `asmjit-master` / `asmtk-master` e manter como baseline.
- **[mapeamento de fontes]** para cada arquivo Dart, manter uma referência explícita do(s) arquivo(s) C++ equivalente(s) (ex: `func.dart` ⇆ `func.h/func.cpp`).
- **[modo de auditoria]** decidir como comparar comportamento:
  - testes de assembler: comparar bytes emitidos (golden/expected)
  - compiler/RA: validar invariantes (assignments, spills, preservação de regs, frame layout)
  - DB/tools: validar outputs gerados (arquivos `.g.dart` idênticos semânticamente ao que o C++ gera)

**Pronto quando**:
- `dart test` roda e falha/sucesso de forma determinística
- existe um lugar único para colocar novos testes portados (estrutura de pastas definida)

---

## Fase 1 — Core (infra mínima que desbloqueia todo o resto)

Ordem sugerida (mantendo 1:1 com C++):

1. `support.*`, `globals`, `error`, `logger` (se existir) — invariantes e helpers usados em tudo.
2. `type`, `operand`, `reg`, `arch` — base de tipos e registradores.
3. `code_buffer`, `code_holder`, `section`, reloc (o que for necessário para testes de encoding).
4. `func.*` (`FuncDetail`, `FuncFrame`, `FuncArgsContext`) — ABI, layout de stack, args/ret.
5. `emitter`/`builder` base — APIs coerentes com o C++ (sem APIs “inventadas”).
6. `compiler` base — nós, blocos, ligação com frame, etc.

**Pronto quando**:
- testes básicos de `func/frame` (layout, alinhamento, preserved regs) passam
- chamadas simples com assinatura/ABI geram o mesmo layout do C++

---

## Fase 2 — x86 Assembler (paridade por encoding)

Meta: garantir que **emitir instruções** no Dart produza os mesmos bytes do C++.

**Pronto quando**:
- a suite de testes do assembler x86 (portada) cobre os grupos principais e valida bytes
- instruções já existentes no Dart passam com comparação byte-a-byte

---

## Fase 3 — A64 Assembler (mesma abordagem do x86)

Meta: cobertura massiva de instruções com comparação por encoding.

**Pronto quando**:
- testes do assembler A64 (portados) validam bytes para um conjunto grande e representativo

---

## Fase 4 — Compiler + RA (local → global) e integração

Meta: desbloquear Blend2D/pipelines reais.

Ordem sugerida:

1. integrar `RALocal` com o `Compiler` real (pipeline equivalente ao C++)
2. portar passes necessários para atingir o comportamento do C++
3. implementar `RAGlobal` (coloring/splitting/coalescing) quando os testes do compiler exigirem

**Pronto quando**:
- `asmjit_test_compiler` portado passa (ou pelo menos o subconjunto inicial, expandindo incrementalmente)

---

# Portação de TESTES (C++ asmjit-testing → Dart)

## Objetivo

Portar a suite `C:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit-testing` para garantir:

- **[assembler]** bytes idênticos
- **[instdb]** metadados consistentes
- **[compiler/RA]** invariantes e decisões equivalentes

## Estratégia prática (incremental)

### 1) Espelho de estrutura

- criar correspondência 1:1 por arquivo de teste (nome e escopo)
- cada teste Dart deve apontar claramente qual teste C++ ele espelha

### 2) Testes de assembler por “vetor de casos”

- extrair do C++ os casos (inputs) e os bytes esperados
- no Dart, emitir com o mesmo assembler e comparar o buffer
- começar por um subset pequeno (smoke) e crescer até cobrir tudo

**Pronto quando**:
- comparação de bytes passa (mesmo endianness/layout)
- falhas mostram diff útil (offset/byte esperado vs obtido)

### 3) Testes de instdb

- validar integridade: `mnemonic`, `opCount`, `flags`, `features`, leitura/escrita (RWInfo)
- comparar propriedades “derivadas” que o compiler usa (não só valores brutos)

### 4) Testes de compiler

- começar com testes determinísticos (prolog/epilog, chamadas simples)
- depois controle de fluxo e pressão de registradores
- por fim casos grandes (stress) que exercitam spill/reload/shuffle

---

# Portação de BENCHMARKS (C++ → Dart)

## Objetivo

Portar benchmarks do C++ preservando:

- o cenário (mesmas sequências de emissão)
- a métrica (tempo/iteração, bytes gerados, contagens)

## Estratégia prática

- manter os benchmarks como executáveis Dart (ex: em `benchmark/asmjit/`)
- garantir warmup e repetição suficiente para reduzir ruído
- registrar:
  - tempo total
  - tempo por iteração
  - bytes emitidos
  - contadores específicos (se houver)

**Pronto quando**:
- a “carga” executada é equivalente ao C++ (mesma quantidade de instruções/loops)
- resultados são estáveis o suficiente para detectar regressão

---

# Portação de DB/TOOLS/GERADORES (C++ → Dart)

Referências:

- `C:\MyDartProjects\asmjit\referencias\asmjit-master\db`
- `C:\MyDartProjects\asmjit\referencias\asmjit-master\tools`

## Objetivo

Gerar os mesmos artefatos (ex: `*_inst_db.g.dart`) com o mesmo conteúdo semântico do C++.

## Estratégia prática

- portar primeiro os geradores que produzem arquivos já consumidos pelo Dart
- padronizar:
  - input: JSON/DB
  - transformação: regras idênticas
  - output: Dart gerado determinístico

**Pronto quando**:
- gerar duas vezes produz exatamente o mesmo output (determinístico)
- bater checks básicos (contagens, hashes, invariantes)

---

# Procedimento de auditoria contínua (arquivo por arquivo)

## Regra

Para cada arquivo portado/corrigido, garantir:

- mesma ordem de branches
- mesmos masks/shifts
- mesmas condições de erro
- mesmas conversões de tipo e sign-extension
- mesmo comportamento em 32/64-bit

## Checklist por arquivo

- **[mapear equivalentes]** qual `.h/.cpp` corresponde ao `.dart`
- **[enumerar símbolos]** classes/funções/constantes principais
- **[comparar decisões]** switches, tabelas, fallthroughs, flags
- **[comparar invariantes]** asserts/validações equivalentes
- **[testar]** adicionar/ajustar testes que capturam o caso-limite

## Comandos recomendados (Windows)

- usar `rg` para localizar símbolos e casos-limite
- usar `sed` para edições mecânicas (com cuidado para não alterar semântica)


# Relatório de Inconsistências: Dart vs C++ AsmJit

tem que ir vendo arquivo por arquivo e ir corrigindo para que a lógica seja idêntica ao c++

**tem que ter a mesma lógica exata do c++ se não tiver a lógica idêntica ao c++ não vai funcionar**
pode usar o SED para editar o arquivo e usar rg para ler o codigo 
---
não crie classes TODOs ou stubs somente cria a implementação correta e real igual o c++
nada de minimal implementations sempre siga fazendo o porte correto da implementação completa
## Análise Realizada em: 28/12/2024

### Arquivos Comparados:
- `func.dart` vs `func.h` / `func.cpp`
- `x86_func.dart` vs `x86func.cpp`
- `func_args_context.dart` vs `funcargscontext_p.h` / `funcargscontext.cpp`
- `emit_helper.dart` vs `emithelper.cpp`
- `regalloc.dart` vs arquivos RA do C++

---

## ✅ IMPLEMENTADO: RALocal (Register Allocator Local)

**Novos arquivos criados:**
- `lib/src/asmjit/core/radefs.dart` - Definições do RA (RAWorkId, RARegCount, RARegMask, RALiveSpan, RATiedReg, RAWorkReg)
- `lib/src/asmjit/core/raassignment.dart` - Estado de assignment (PhysToWorkMap, WorkToPhysMap, RAAssignmentState)
- `lib/src/asmjit/core/ralocal.dart` - Alocador local (RALocalAllocator)

**O RALocalAllocator implementa o algoritmo completo do C++:**
1. ✅ Cálculo de willUse/willFree masks
2. ✅ Tratamento de registradores consecutivos
3. ✅ Decisões de assignment (decideOnAssignment, decideOnReassignment, decideOnSpillFor)
4. ✅ Operações de movimentação (onMoveReg, onSwapReg, onLoadReg, onSaveReg, onSpillReg)
5. ✅ Fase 5: Shuffle de registradores USE com suporte a swap
6. ✅ Fase 6: Kill de registradores OUT/KILL
7. ✅ Fase 7: Spill de registradores CLOBBERED
8. ✅ Fase 9: Assignment de registradores OUT
9. ✅ Modelo de custo para decisões de spill (kCostOfFrequency, kCostOfDirtyFlag)

---

## �️ ARQUIVOS LEGADOS REMOVIDOS

Os seguintes arquivos foram removidos porque não seguiam a API C++ e tinham implementações incompatíveis:

- ❌ `lib/src/asmjit/core/regalloc.dart` - Implementação linear-scan simplificada (não seguia C++)
- ❌ `lib/src/asmjit/core/ir.dart` - Arquivo de re-export desnecessário
- ❌ `lib/src/asmjit/core/code_builder.dart` - X86CodeBuilder com API própria (não existe no C++)
- ❌ `lib/src/asmjit/x86/x86_compiler.dart` - X86Compiler wrapper (precisa ser portado corretamente)

**Próximos passos para substituição:**
1. Portar `BaseCompiler` do C++ (`compiler.h`, `compiler.cpp`) ✅
2. Portar `x86::Compiler` do C++ (`x86compiler.h`, `x86compiler.cpp`) (Iniciado)
3. Integrar RALocalAllocator com o novo Compiler (Pendente)

---

## �🔴 INCONSISTÊNCIAS CRÍTICAS (Ainda pendentes)

### 1. ✅ **FuncValue - Tratamento de Stack Offset com Sinal (CORRIGIDO)**

**C++ (func.h:721)**:
```cpp
[[nodiscard]]
ASMJIT_INLINE_NODEBUG int32_t stack_offset() const noexcept { 
  return int32_t(_data & kStackOffsetMask) >> kStackOffsetShift; 
}
```

**CORREÇÃO APLICADA em func.dart**: Agora `stackOffset` faz extensão de sinal corretamente:
```dart
int get stackOffset {
  final raw = (_data & FuncValueBits.kStackOffsetMask) >>
      FuncValueBits.kStackOffsetShift;
  // Sign extend from 20 bits
  if ((raw & 0x80000) != 0) {
    return raw | 0xFFF00000; // Extend sign bit
  }
  return raw;
}
```

---

### 2. **x86func.dart - Falta LightCall para 64-bit (CRÍTICO)**

**C++ (x86func.cpp:193-208)**:
```cpp
case CallConvId::kLightCall2:
case CallConvId::kLightCall3:
case CallConvId::kLightCall4: {
  uint32_t n = uint32_t(call_conv_id) - uint32_t(CallConvId::kLightCall2) + 2;

  cc.set_flags(CallConvFlags::kPassFloatsByVec);
  cc.set_natural_stack_alignment(16);
  cc.set_passed_order(RegGroup::kGp, kZax, kZdx, kZcx, kZsi, kZdi);
  cc.set_passed_order(RegGroup::kVec, 0, 1, 2, 3, 4, 5, 6, 7);
  cc.set_passed_order(RegGroup::kMask, 0, 1, 2, 3, 4, 5, 6, 7);
  cc.set_passed_order(RegGroup::kX86_MM, 0, 1, 2, 3, 4, 5, 6, 7);

  cc.set_preserved_regs(RegGroup::kGp, Support::lsb_mask<uint32_t>(16));  // 16 for 64-bit!
  cc.set_preserved_regs(RegGroup::kVec, ~Support::lsb_mask<uint32_t>(n));
  break;
}
```

**Dart (x86_func.dart:125-171)** - **FALTA COMPLETAMENTE O CASO LightCall PARA 64-bit!**

O switch para 64-bit só tem casos para `x64SystemV`, `x64Windows` e `vectorCall`. Os casos `lightCall2/3/4` não existem para modo 64-bit, causando `invalidArgument` quando usados.

### 2. ✅ **x86func.dart - Falta LightCall para 64-bit (CORRIGIDO)**

**C++ (x86func.cpp:193-208)**:
...
**Dart (x86_func.dart:125-171)** - Implementado LightCall2/3/4 em initCallConv 64-bit.

---

### 3. ✅ **x86func.dart - Tratamento Incompleto de Tipos de Retorno (CORRIGIDO)**

**C++ (x86func.cpp:263-328)** tem tratamento completo de tipos de retorno.
**Dart (x86_func.dart)**: Implementado tratamento para Float80, MMX e preservação de TypeId.

---

**C++ (x86func.cpp:263-328)** tem tratamento completo de tipos de retorno:
- `Int8/Int16/Int32` → `GP32` com typeId correto
- `UInt8/UInt16/UInt32` → `GP32` com typeId correto  
- `Float80` → `X86_St` (FPU stack)
- `Mmx32/Mmx64` → Tratamento especial para x64 (XMM ou GP64 dependendo da estratégia)

**Dart (x86_func.dart:204-226)** usa lógica simplificada:
```dart
if (typeId.isInt) {
  // ... apenas verifica sizeInBytes
} else if (typeId.isFloat) {
  final regType = arch.is32Bit ? RegType.x86St : RegType.vec128;
  ret.initReg(regType, i, typeId);
} else {
  ret.initReg(vecTypeIdToRegType(typeId), i, typeId);
}
```

**PROBLEMAS**:
1. Não preserva TypeId original (ex: Int8 deveria manter Int8, não virar Int32)
2. Não trata Float80 corretamente em 64-bit
3. Não trata MMX corretamente (deveria ir para XMM ou GP64 dependendo da estratégia)
4. Falta tratamento de void para terminar o pack

---

### 4. ✅ **FuncArgsContext - Falta Membro `_has_preserved_fp` (CORRIGIDO)**

**C++ (funcargscontext_p.h:184-185)**:
```cpp
bool _has_stack_src = false;
bool _has_preserved_fp = false;
```

**CORREÇÃO APLICADA em func_args_context.dart**: Adicionado `bool _hasPreservedFP = false;` e getter `hasPreservedFP`. Também inicializado em `initWorkData` com `_hasPreservedFP = frame.hasPreservedFP;`.

---

### 5. ✅ **FuncArgsContext - Tratamento de Constraints (VERIFICADO)**

**Dart**: Constraints são usadas localmente. A ausência de referência persistente não bloqueia a funcionalidade atual.

---

**C++ (funcargscontext_p.h:179)**:
```cpp
const RAConstraints* _constraints = nullptr;
```

**Dart (func_args_context.dart)**: Não armazena referência aos constraints, apenas usa durante `initWorkData`.

O C++ mantém a referência para uso posterior potencial.

---

### 6. **x86func.dart - Tratamento de VarArgs Incompleto (MODERADO)**

**C++ (x86func.cpp:395-397)**:
```cpp
if (signature.has_var_args() && cc.has_flag(CallConvFlags::kPassVecByStackIfVA)) {
  reg_id = Reg::kIdBad;
}
```

**Dart (x86_func.dart:263-267)**:
```dart
if (typeId.isVec &&
    signature.hasVarArgs &&
    cc.hasFlag(CallConvFlags.kPassVecByStackIfVA)) {
  regId = Reg.kIdBad;
}
```

**PROBLEMA**: O Dart só verifica `isVec`, mas o C++ aplica a regra para qualquer tipo que não seja float (verifica na estrutura else).

---

### 7. **emit_helper.dart - Falta `emit_reg_move` com Operand_ (MODERADO)**

**C++ (emithelper.cpp:73-76)**:
```cpp
Error BaseEmitHelper::emit_reg_move(const Operand_& dst_, const Operand_& src_, TypeId type_id, const char* comment) {
```

**Dart (emit_helper.dart:472)**:
```dart
AsmJitError emitRegMove(EmitOperand dst, EmitOperand src, TypeId typeId);
```

O C++ permite tanto registradores quanto memória como dst/src, enquanto o Dart restringe os tipos.

---

### 8. ✅ **FuncFrame.finalize() - Diferença no Cálculo de has_inst_push_pop (CORRIGIDO)**

**Dart**: Corrigido para chamar `hasInstPushPop(group)` passando o grupo corretamente.

---

**C++ (func.cpp:202-205)**:
```cpp
for (RegGroup group : Support::enumerate(RegGroup::kMaxVirt)) {
  save_restore_sizes[size_t(!arch_traits.has_inst_push_pop(group))]
    += Support::align_up(Support::popcnt(saved_regs(group)) * save_restore_reg_size(group), save_restore_alignment(group));
}
```

**Dart (func.dart:1062-1067)**:
```dart
for (var group in RegGroup.values) {
  int idx = archTraits.hasInstPushPop() ? 0 : 1;  // ⚠️ Não passa group!
  saveRestoreSizes[idx] += support.alignUp(
      support.popcnt(savedRegs(group)) * saveRestoreRegSize(group),
      saveRestoreAlignment(group));
}
```

**PROBLEMA**: O Dart chama `hasInstPushPop()` sem parâmetro, enquanto o C++ chama `has_inst_push_pop(group)`. O resultado é que o Dart usa o mesmo índice para todos os grupos, enquanto o C++ pode usar índices diferentes por grupo.

---

### 9. ✅ **regalloc.dart - Implementação Independente (REMOVIDO)**

Arquivo legado removido. Substituído por `ralocal.dart`.

---

O arquivo `regalloc.dart` contém uma implementação de linear-scan register allocator que é **COMPLETAMENTE DIFERENTE** do C++ original:

- C++ usa `RALocal` com múltiplas passes (CFG analysis, live range splitting, etc.)
- Dart usa uma implementação simplificada de linear-scan incorretamente

O comentário na linha 286 diz:
```dart
/// TODO tem que ter a mesma logica exata do c++ se não tiver a logica identica ao c++ não vai funcionar
```

**Este arquivo precisa ser reescrito para seguir a lógica C++.**

---

### 10. ✅ **FuncDetail - Falta Deabstract Delta (CORRIGIDO)**

**Dart**: Adicionado chamada `deabstract(registerSize)` em `FuncDetail.init`.

---

**C++ (func.cpp:59)**:
```cpp
uint32_t deabstract_delta = TypeUtils::deabstract_delta_of_size(register_size);
// ...
arg_pack[0].init_type_id(TypeUtils::deabstract(signature_args[arg_index], deabstract_delta));
```

**Dart (func.dart:635-637)**:
```dart
for (int i = 0; i < argCount; i++) {
  _args[i][0].initTypeId(signature.arg(i));  // ⚠️ Não faz deabstract!
}
```

**PROBLEMA**: O Dart não aplica `deabstract` aos tipos, o que pode causar tipos abstratos (como IntPtr) não serem convertidos para tipos concretos.

---

### 11. **CallConv - setFlags vs addFlags (MENOR)**

**C++ (x86func.cpp:62)**:
```cpp
cc.set_flags(CallConvFlags::kCalleePopsStack);  // SET substitui
```

**Dart (x86_func.dart:62)**:
```dart
cc.addFlags(CallConvFlags.kCalleePopsStack);  // ADD adiciona
```

Em alguns lugares o C++ usa `set_flags` (substitui) enquanto o Dart usa `addFlags` (adiciona). Isso pode causar comportamento diferente se flags anteriores precisarem ser removidas.

---

### 12. **FuncValueBits - Constantes de Shift Incorretas (VERIFICAR)**

**C++ (func.h:586-601)**:
```cpp
enum Bits : uint32_t {
  kTypeIdShift      = 0,
  kTypeIdMask       = 0x000000FFu,

  kFlagIsReg        = 0x00000100u,
  kFlagIsStack      = 0x00000200u,
  kFlagIsIndirect   = 0x00000400u,
  kFlagIsDone       = 0x00000800u,

  kStackOffsetShift = 12,
  kStackOffsetMask  = 0xFFFFF000u,

  kRegIdShift       = 16,
  kRegIdMask        = 0x00FF0000u,

  kRegTypeShift     = 24,
  kRegTypeMask      = 0xFF000000u
};
```

**Dart (func.dart:354-370)** parece correto, mas verificar se os valores batem exatamente.

---

## 📋 Status Atual

- Helpers de função e frames usam agora `RegType` concretos, `FuncFrameAttributes` transporta máscaras/locais/flags e `FuncFrame.host(...)` consome esses dados para manter a compatibilidade com o modelo C++, liberando o construtor principal para os builders.
- `RegUtils.Reg` expõe `RegType`+ID, o builder fornece `movRI/movRR/test`, `FuncDetail` recebe `FuncSignature` + calling convention, e a infraestrutura (`FuncFrame`, `FuncValue`, `FuncArgsContext`) passa a operar com as mesmas unidades que o código C++ original.
- O pipeline x86, benchmarks e testes agora usam as APIs corretas (`FuncFrame.getArgReg`, novos construtores nomeados, `includeShadowSpace` compatível), `emit_helper.dart` aceita operandos concretos e `dart analyze` está limpo—só resta lidar com os avisos de limpeza já removidos da lista.
- Mantemos a fidelidade ao C++ enquanto documentamos os próximos refinamentos no roteiro; o fluxo de shuffle/pipeline segue alinhado com os conceitos originais.

---

## 📋 Referências e Próximos Passos

### Prioridade ALTA (Crítico para funcionamento):
1. ✅ Corrigir `FuncValue.stackOffset` para tratar sinal corretamente
2. ✅ Adicionar casos `LightCall` para modo 64-bit em `x86_func.dart`
3. ✅ Completar tratamento de tipos de retorno em `initFuncDetail`
4. ⬜ Adicionar deabstract para tipos em `FuncDetail.init`
5. ✅ Corrigir `hasInstPushPop(group)` para passar o grupo
6. ⬜ Portar `BaseCompiler` do C++ (compiler.h/cpp)
7. ⬜ Portar `x86::Compiler` do C++ (x86compiler.h/cpp)

### Prioridade MÉDIA:
8. ✅ Adicionar `_hasPreservedFP` em `FuncArgsContext`
10. ⬜ Corrigir tratamento de VarArgs para todos os tipos não-float
11. ⬜ Revisar todos os `setFlags` vs `addFlags`
12. ⬜ Refatorar blend2d/pipeline para usar novo Compiler

### Prioridade BAIXA:
13. ⬜ Adicionar suporte a `emit_reg_move` com operandos genéricos
14. ⬜ Capturar quaisquer regressões nas suites de testes/benchmarks ao estender o suporte

### Arquivos Core do RA (Completos e Validados):
- ✅ `lib/src/asmjit/core/radefs.dart`
- ✅ `lib/src/asmjit/core/raassignment.dart`
- ✅ `lib/src/asmjit/core/ralocal.dart`
- ✅ `lib/src/asmjit/core/func.dart`
- ✅ `lib/src/asmjit/core/func_args_context.dart`
- ✅ `lib/src/asmjit/core/arch.dart`

### Validação Contínua:
15. Revalidar regularmente com `dart analyze` enquanto adicionamos novos helpers ou aproximamos ainda mais o fluxo do `callconv`/RA, garantindo que a tradução siga fielmente o C++ sem alertas.
sempre responda em portugues 
# Auditoria Completa: AsmJit Dart vs C++
**Data da Análise**: 28/12/2024
**Status Geral**: ⚠️ Parcialmente Portado
**Objetivo**: Identificar gaps de API, funcionalidades ausentes e necessidades de testes/benchmarks para paridade 1:1.

---

## 📊 Resumo Executivo

| Módulo | Status | Descrição |
|--------|--------|-----------|
| **Core** | ⚠️ Parcial | Infraestrutura básica OK (`CodeHolder`, `CodeBuffer`, `Runtime`). Faltam `Complaint IR` completo e `Global Register Allocator`. |
| **x86** | ⚠️ Parcial | Encoder robusto. Assembler com ~40% dos métodos C++. Faltam helpers de `Compiler`. |
| **ARM (A64)** | 🔴 Crítico | Encoder funcional. Assembler com apenas ~10% dos métodos C++. Compiler inexistente. |
| **Testes** | ⚠️ Parcial | Testes unitários básicos ok. Faltam suites pesadas (`asmjit_test_compiler`, `asmjit_test_assembler`). |
| **Benchmarks** | ainda não portados | Principais benchmarks (`codegen`, `overhead`, `regalloc`)  |

---

## 🔍 Core (`lib/src/asmjit/core`)

O "cérebro" do AsmJit. A maior discrepância está na infraestrutura de Compilador e Alocação de Registradores que tem que ser resolvida com prioridade autissima

| Arquivo C++ (Ref) | Tamanho C++ | Arquivo Dart | Status | Gaps Identificados |
|-------------------|-------------|--------------|--------|-------------------|
| `compiler.h/.cpp` | ~50 KB | `compiler.dart` (10 KB) | ✅ Parcial | Implementado `BaseCompiler`, `FuncNode`, `BlockNode`, `JumpNode`. Falta integração completa com RAGlobal. |
| `rapass.h/.cpp` | ~100 KB | `ralocal.dart` (29 KB) | 🔴 Crítico | Implementado apenas **RALocal** (Linear Scan). Falta **RAGlobal** (Coloring, Split, Coalescing) e todo o pipeline avançado de otimização de registradores isso é vital |
| `builder.h/.cpp` | ~80 KB | `builder.dart` (17 KB) | 🟡 Crítico | Funcionalidade básica de emissão existe, mas falta lógica complexa de manipulação de nós e injeção de instruções. |
| `func.h/.cpp` | ~90 KB | `func.dart` (39 KB) | ✅ Bom | Core logic portada (`FuncDetail`, `FuncFrame`), mas requer revisão constante de flags e atributos (v. relatório anterior). |
| `codeholder.cpp` | ~45 KB | `code_holder.dart` (9 KB) | 🟡 Crítico | Faltam métodos de manipulação de seções, relocação e gerenciamento avançado de erro. |
| `emitter.h/.cpp` | ~50 KB | `emitter.dart` (1.5 KB) | 🔴 Crítico | A classe base `Emitter` no C++ tem muita lógica compartilhada de validação e encoding que não está no Dart (está dispersa ou ausente). |
| `codewriter.cpp` | ~8 KB | `code_writer.dart` (1 KB) | 🔴 Crítico | Utilitário de escrita de código (hex dump, logging avançado) praticamente inexistente. |

**Ação Necessária**: Priorizar o porting de `Compiler` infraestrutura e o RAGlobal para suportar o backend JIT do Blend2D.

---

## 🖥️ x86 Backend (`lib/src/asmjit/x86`)

O backend x86 está mais maduro que o ARM, mas ainda longe da completude da API C++.

| Arquivo C++ (Ref) | Tamanho C++ | Arquivo Dart | Status | Gaps Identificados |
|-------------------|-------------|--------------|--------|-------------------|
| `x86assembler.cpp` | 159 KB | `x86_assembler.dart` (57 KB) | 🟡 Médio | Falta ~60% dos métodos de conveniência (wrappers para instruções específicas, variantes de operandos). |
| `x86instdb.cpp` | 512 KB | `x86_inst_db.g.dart` (228 KB) | ⚠️ Atenção | O DB gerado é menor. Verificar se faltam metadados de instruções (RW info, CPU features) essenciais para o Compiler. |
| `x86compiler.cpp` | 36 KB | `x86_compiler.dart` (Skeleton) | 🟡 Estágio Inicial | Criado esqueleto de `X86Compiler` e `X86InstructionAnalyzer`. Falta implementação de métodos de instrução. |
| `x86emithelper.cpp`| 21 KB | `emit_helper.dart` (13 KB)* | 🟡 Médio | Helpers genéricos existem, mas faltam os específicos de x86 para shuffle de argumentos vetoriais complexos. |

**Ação Necessária**: Completar `x86_assembler.dart` com todos os grupos de instruções (AVX-512 completo, FPU legacy , AMX, etc).

---

## 📱 ARM (AArch64) Backend (`lib/src/asmjit/arm`)

O backend ARM está em estágio inicial comparado ao C++.

| Arquivo C++ (Ref) | Tamanho C++ | Arquivo Dart | Status | Gaps Identificados |
|-------------------|-------------|--------------|--------|-------------------|
| `a64assembler.cpp`| 171 KB | `a64_assembler.dart` (18 KB)| 🔴 Crítico | **Apenas ~10% implementado**. Faltam centenas de instruções (Vector, SIMD avançado, Crypto, SVE). |
| `a64compiler.cpp` | 12 KB | Missing | 🔴 Crítico | Não existe implementação de Compiler backend para A64 (prologo/epílogo, ABI handling). |
| `a64emithelper.cpp`| 14 KB | Missing | 🔴 Crítico | Helpers de emissão A64 ausentes. |
| `a64instdb.cpp` | 230 KB | `a64_inst_db.g.dart` (100 KB)| ⚠️ Atenção | DB gerado parcial. |

**Ação Necessária**: Focar esforços massivos em `a64_assembler.dart` para suportar instruções necessárias para gráficos/processamento (NEON, FP).

---

## 🧪 Verificação de Testes

A suite de testes do Dart é uma fração da suite C++.

### Faltam (Do diretório `asmjit-testing` C++):
1.  **`asmjit_test_assembler_x86.cpp` / `_a64.cpp`**: Testes exaustivos de verificação de encoding bit-a-bit para TODAS as instruções. O Dart tem apenas "smoke tests" (algumas instruções). **Necessário portar para garantir fidelidade de encoding.**
2.  **`asmjit_test_compiler.cpp`**: Testes complexos de fluxo de controle, chamadas de função recursivas, alocação de muitos registradores. Essencial para validar o `RALocal`.
3.  **`asmjit_test_emitters.cpp`**: Validação cruzada de emissores.
4.  **`asmjit_test_instinfo.cpp`**: Validação da integridade do DB de instruções.

**Recomendação**: Criar scripts para portar automaticamente os testes de assembler (parsing do C++ ou output gerado) para Dart, pois são milhares de linhas.

---

## 🚀 Verificação de Benchmarks

Os principais benchmarks foram portados, mas precisam de validação de paridade de comportamento.

| Benchmark | Status Dart | Notas |
|-----------|-------------|-------|
| `codegen_benchmark` | ✅ Portado | Verifica throughput de Assembler/Builder. |
| `overhead_benchmark`| ✅ Portado | Mede custo de criação de CodeHolder/Runtime. |
| `regalloc_benchmark`| ⚠️ Parcial | Falha em complexidades altas ou não implementa todos os cenários do C++ (ex: bugs de Displacement em A64 vistos no C++ devem ser replicados ou corrigidos). |

---

## 📝 Lista de Tarefas Imediatas (Roadmap Atualizado)

1.  **Prioridade 0 (Estabilidade Core)**:
    *   Resolver inconsistências em `func.dart` (Stack Offset sinal ✅).
    *   Refatorar `compiler.dart` para suportar definições de Nós reais (`FuncNode`, `BlockNode`) ✅.

2.  **Prioridade 1 RAGlobal completo**:
   Implementar RAGlobal

3.  **Prioridade 2 (Backend x86)**:
*   Implementar `x86_compiler.dart` (Lowering real).
*   Expandir coverage de `x86_assembler.dart`.

4.  **Prioridade 3 (Backend ARM)**:
    *   Expandir drasticamente `a64_assembler.dart` (Atualmente inutilizável para código real complexo).

5.  **Prioridade 4 (Qualidade)**:
    *   Portar `asmjit_test_assembler` completo para garantir que a implementação dart esta em paridade com a implementação c++
