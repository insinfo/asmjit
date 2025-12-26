# Relatório de Benchmark ChaCha20: Dart vs C vs AsmJit

## Resumo Executivo
Este relatório compara o desempenho de seis implementações diferentes do ChaCha20 em Dart, variando de código Dart puro a C nativo via FFI e assembly gerado em tempo de execução usando `package:asmjit`.

**Principais Descobertas:**
1.  **AsmJit é viável e eficaz**: O código gerado em tempo de execução usando `package:asmjit` tem desempenho idêntico ao assembly inline estático (Shellcode), atingindo **~143 MiB/s** de vazão (throughput).
2.  **Superioridade em Baixa Latência**: Para pequenos blocos de dados (64 bytes), **AsmJit e Inline ASM** superaram a DLL em C em **~2x** (133 MiB/s vs 72 MiB/s). Isso demonstra o valor de compilar kernels especializados via JIT para evitar overheads de funções de uso geral.
3.  **Pico de Vazão**: A implementação "C Pooled" alcançou a maior vazão geral (**338 MiB/s** em blocos de 64KB), superando significativamente o assembly manual SSE2 (~143 MiB/s). Isso sugere que o compilador C (GCC/Clang com `-O3 -march=native`) aplicou otimizações mais agressivas (provavelmente instruções AVX/AVX2 ou melhor escalonamento de pipeline) do que o assembly manual SSE2 básico.
4.  **Limites de Otimização do Dart**: Dart puro com otimizações e desenrolamento de laço (*loop unrolling*) atingiu **65 MiB/s**, uma melhoria de 2x sobre o baseline (~31 MiB/s), mas ainda 2-5x mais lento que as abordagens nativas.

## Metodologia
- **Plataforma**: Windows x64 (Dart 3.6.0)
- **Tamanhos de Dados**: Pequeno (64B), Médio (1KB), Grande (64KB).
- **Iterações**: 100.000 (Pequeno), 50.000 (Médio), 5.000 (Grande).
- **Implementações**:
    1.  **C Puro (DLL)**: Compilado com `-O3 -march=native`.
    2.  **Dart Puro**: Baseline `List<int>`.
    3.  **Dart Otimizado**: `Uint32List`, `ByteData`.
    4.  **Dart Unrolled**: Loop unrolling manual em Dart.
    5.  **Dart FFI Pointer**: Acesso direto à memória via `Pointer<Uint8>`.
    6.  **Inline ASM**: Shellcode x64 SSE2 pré-compilado.
    7.  **AsmJit**: Geração dinâmica de assembly em tempo de execução usando `package:asmjit`.

## Resultados Detalhados

### Vazão (MiB/s)

| Implementação | 64 Bytes | 1 KB | 64 KB |
| :--- | :--- | :--- | :--- |
| **C DLL (Pooled)** | N/A | N/A | **338.1** |
| **C DLL (Standard)** | 72.3 | 141.8 | 152.1 |
| **AsmJit SSE2** | **133.9** | **141.8** | 143.4 |
| **Inline ASM SSE2** | 131.9 | 140.0 | 143.7 |
| **Dart Unrolled** | 49.2 | 69.1 | 65.1 |
| **Dart FFI Opt** | 51.9 | 62.7 | 62.6 |
| **Dart Baseline** | 19.5 | 30.5 | 31.2 |
| **Dart Optimized** | 19.7 | 21.4 | 21.3 |

### Latência (ns/op) - Payload Pequeno (64B)

| Implementação | Latência (ns) | Custo Relativo |
| :--- | :--- | :--- |
| **AsmJit SSE2** | **455.7** | 1.0x (Baseline) |
| **Inline ASM** | 462.7 | 1.01x |
| **C DLL** | 843.9 | 1.85x |
| **Dart Unrolled** | 1240.8 | 2.72x |
| **Dart Baseline** | 3129.2 | 6.87x |

### Análise e Overhead de FFI
- **Overhead por chamada**: Medido em **~30.4 ns**.
- **Impacto**: Para tarefas pequenas (como criptografar 64 bytes, levando ~450ns), o overhead de 30ns é negligenciável (<7%). A diferença entre AsmJit (455ns) e C DLL (843ns) para 64B sugere que a função em C tem custos internos de configuração (ex: stack frames, marshalling de argumentos ou inicialização de estado) que o kernel assembly especializado evita.
- **Nativo vs Assembly Manual**: A capacidade do compilador C de usar AVX2 (SIMD de 256 bits) provavelmente explica a diferença de 338 MiB/s vs 143 MiB/s em dados grandes. O assembly manual era SSE2 estrito (128 bits). Atualizar o gerador AsmJit para usar AVX/AVX2 provavelmente fecharia essa lacuna.

## Vantagens da Integração com AsmJit
1.  **Especialização Dinâmica**: Diferente da DLL em C pré-compilada, o AsmJit permite a compilação de kernels *especificamente* para os dados em tempo de execução (ex: embutir constantes diretamente, desenrolar loops com base no tamanho exato dos dados), potencialmente reduzindo ainda mais o overhead.
2.  **Sem Dependências Externas**: A implementação genérica em C requer a distribuição de uma `.dll`/`.so`. A implementação AsmJit está contida inteiramente no pacote Dart (gerando memória de código em tempo de execução).
3.  **Fonte Agnóstica de Instruções**: Enquanto este benchmark gerou código x86, a estrutura da biblioteca AsmJit permite construir builders genéricos que visam a CPU host (x86 ou ARM64) dinamicamente, enquanto o Inline ASM requer manter blobs binários separados para cada combinação de arquitetura/SO.

## Recomendações
1.  **Use FFI/C para Processamento em Massa**: Para grandes arquivos/streams, a implementação em C otimizada pelo compilador permanece a melhor opção para throughput.
2.  **Use AsmJit para Operações Rápidas/Pequenas de Alta Frequência**: Para cenários que exigem milhões de pequenas operações rápidas (ex: criptografia de pacotes, loops de derivação de chaves), o overhead reduzido do kernel gerado via JIT oferece um aumento de velocidade de 2x.
3.  **Otimize o Kernel AsmJit**: A implementação atual SSE2 é um baseline. Implementar AVX2 (usando registros YMM) no gerador `ChaCha20AsmJit` deve teoricamente dobrar a vazão para igualar ou superar a implementação em C.
