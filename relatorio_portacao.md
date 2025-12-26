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
  - Falta `validated`, `builder [no-asm]`, `builder [prolog/epilog]` e `compiler`.
  - Cobertura de sequencias GP/SSE/AVX e A64 e muito menor que o C++.
  - `Builder [finalized]` gera `CodeSize: 0` (nao serializa/gera codigo).
- `benchmark/overhead_benchmark.dart`:
  - Nao replica `code.reset()/init()` e `attach()` como no C++.
  - Falta caminho de `compiler` e cobertura de RT para A64.
- `benchmark/regalloc_benchmark.dart`:
  - Nao usa pipeline de compiler/RA do C++; nao mede memoria.
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