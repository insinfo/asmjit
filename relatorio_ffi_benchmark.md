# Relatorio: Overhead de FFI (C/OS vs Dart)

## Objetivo
Comparar o custo de:
- Chamadas FFI para uma DLL C simples.
- Chamadas FFI para funcoes do SO (Windows: `RtlMoveMemory`, `VirtualAlloc`).
- Implementacao pura em Dart (sem FFI).

Os benchmarks abaixo foram criados para medir a sobrecarga por chamada e a taxa
efetiva (MiB/s) quando ha movimentacao de dados.

## Artefatos gerados
- `benchmark/native/ffi_bench.c`: funcoes C exportadas para FFI.
- `benchmark/native/build_ffi_bench.ps1`: script de build do DLL.
- `benchmark/ffi_overhead_benchmark.dart`: benchmark principal (Dart + FFI).

## Como compilar a DLL
No PowerShell, a partir da raiz do projeto:

```powershell
.\benchmark\native\build_ffi_bench.ps1 -OutDir .\benchmark\native
```

O script tenta `C:\LLVM\bin\clang.exe`, depois `C:\gcc\bin\gcc.exe`, e por fim MSVC.

## Como executar os benchmarks

```powershell
dart run benchmark/ffi_overhead_benchmark.dart
dart run benchmark/ffi_overhead_benchmark.dart --quick
```

## Observacoes de analise
- O benchmark separa:
  - `add_u32`: custo de chamada FFI pura (quase sem trabalho).
  - `sum_u32`: custo de chamada FFI + loop nativo.
  - `fill_u32`: escrita nativa para medir throughput.
  - `RtlMoveMemory`: copia de memoria via chamada do SO (FFI direto).
  - `Dart memcpy`: `Uint8List.setAll` (implementacao pura).
- O objetivo principal e capturar a sobrecarga fixa do FFI (ns/op) e a diferenca
  de throughput ao mover dados por ponteiros nativos vs buffers Dart.

## Resultados (execucao --quick)

```
FFI Overhead Microbench (Dart vs C/OS)
Iterations: 10000 (quick)

  Dart add_u32 loop                  |     63.5 ns/op |      N/A MiB/s
  FFI add_u32 loop                   |    122.2 ns/op |      N/A MiB/s

  Dart sum_u32 (Uint32List)          |   4732.4 ns/op |   3301.7 MiB/s
  FFI sum_u32 (C loop)               |   1022.4 ns/op |  15282.7 MiB/s
  FFI fill_u32 (C loop)              |    478.8 ns/op |  32633.7 MiB/s

  Dart memcpy (setAll)               |   4017.0 ns/op |  15558.9 MiB/s
  FFI memcpy (RtlMoveMemory)         |   3998.0 ns/op |  15632.8 MiB/s
```

## Como estimar a sobrecarga do FFI
Definicao pratica:

```
overhead_ns = ns_per_op(ffi_add) - ns_per_op(dart_add)
```

Para cargas com dados:
```
overhead_por_byte = (ns_per_op(ffi_memcpy) - ns_per_op(dart_memcpy)) / bytes
```

Com os numeros acima (quick):
- Overhead FFI por chamada simples: ~58.7 ns/op (122.2 - 63.5).
- `memcpy`: diferenca ~ -19 ns/op (FFI e Dart praticamente equivalentes).
- Em loops pesados (`sum_u32` e `fill_u32`), o trabalho nativo domina e a FFI
  se paga quando ha volume suficiente.

## Estrategias de otimizacao
1) **Agrupar trabalho em blocos**: evite chamadas FFI pequenas; faca loops
   nativos no lado C e exponha funcoes de lote.
2) **Evitar alocacoes por chamada**: aloque buffers uma vez e reutilize
   ponteiros (ex.: `VirtualAlloc` + `asTypedList`).
3) **Evitar conversoes de tipos**: prefira tipos nativos simples (`Uint32`,
   `Uint64`, `Pointer<Uint8>`), evitando marshaling complexo.
4) **Minimizar trocas de contexto**: passe ponteiros e tamanhos; evite
   estruturas grandes por valor.
5) **Separar hot path**: mantenha o caminho critico em Dart puro quando
   a operacao for pequena (ex.: poucas iteracoes).
6) **SSE/AVX em C quando faz sentido**: se a operacao e vetorial pesada,
   um kernel C/ASM reduz chamadas FFI e aumenta throughput.
7) **Cache de funcoes FFI**: resolva `lookupFunction` uma unica vez e reuse.
8) **Evitar bounds checks**: usar `Pointer.asTypedList` e loops simples,
   com tamanho fixo.
