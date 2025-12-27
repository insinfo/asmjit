finalizar o necessario em C:\MyDartProjects\asmjit\roteiro_asmjit.md
e portar o C:\MyDartProjects\asmjit\referencias\blend2d-master para dart
em C:\MyDartProjects\asmjit\lib\src\blend2d para ter uma biblioteca de graficos 2D
de alta performace em dart multiplataforma windows, linux, macOS, android e ios

a ideia e portar o blend2d para dart ultra otimizado com duas implementações uma que usa o asmjit
C:\MyDartProjects\asmjit\lib\src\asmjit e outra que não depende de asmjit
pois a versão que não depende de asmjit poderar rodar em qualquer plataforma

micro otimizações seram muito importantes para garantir alto desempenho

não misture C:\MyDartProjects\asmjit\lib\src\asmjit com o C:\MyDartProjects\asmjit\lib\src\blend2d 
C:\MyDartProjects\asmjit\lib\src\asmtk  pois no futuro seram pacotes separados

Analise src-over (reference C++):
- C++ usa CompOp_SrcOver_Op em referencias\\blend2d-master\\blend2d\\pipeline\\reference\\compopgeneric_p.h.
- Formula base: Dca' = Sca + Dca * (1 - Sa); Da' = Sa + Da * (1 - Sa).
- Implementacao Dart atual no PipelineCompiler faz s + d * (255 - Sa) usando muldiv255 (rounding + shift),
  igual ao padrao da reference.
- Otimizacoes de curto-circuito (Sa==0 e Sa==255) existem no Dart e sao consistentes com o C++.
- Diferencas atuais: nao cobre global alpha/masks, nem formatos A8/XRGB32, nem variantes vetoriais.

Proximos passos Blend2D:
- Expandir op para suportar src-over com global alpha / mask.
- Adicionar formatos A8 e XRGB32, com paths separados.
- Especializar loops por largura/stride alinhado e variacoes por pixel count (unroll curto).

Backends (Dart):
- JIT X86: pipeline_compiler.dart (copy/fill/src-over).
- JIT A64: copy/fill/src-over (PRGB32 apenas).
- Reference Dart: pipeline_reference.dart (copy/fill/src-over scalar).

Status atualizado:
- Reference Dart: suporta PRGB32/XRGB32/A8, com global alpha e mask.
- JIT X86/A64: PRGB32 sem global alpha/mask por enquanto.
- Backend JS: pipeline_reference_bytes.dart com Uint8List/ByteData (sem dart:ffi).
- Tipos condicionais: pipeline_types.dart define PipelineMask (Pointer no native, Uint8List no JS).

Pendencias imediatas:
- JS: especializacao por stride/width fixo (unroll curto) em PipelineReferenceBytes.
- JIT X86/A64: suportar global alpha/mask e formatos A8/XRGB32.
