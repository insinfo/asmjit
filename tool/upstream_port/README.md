# Scripts do port mecânico dos encoders do upstream

Usados para gerar `lib/src/asmjit/x86/x86_emit.dart` (de `x86::Assembler::_emit()`)
e `lib/src/asmjit/arm/a64_emit.dart` (de `a64::Assembler::_emit()`), além de
`a64_instdb.dart` (structs do `a64instdb_p.h`, `a64/structs.py`) e
`a64_predicate.dart` (namespace `Predicate` do `a64globals.h`, `a64/predicate.py`).

- `translate.py`: traduz o corpo do `_emit()` C++ (o `switch` com `goto`) para
  uma máquina de estados Dart (`case`/labels viram estados de `_S`, `goto X`
  vira `state = _S.X; continue loop;`).
- `head.dart.txt`: cabeçalho escrito à mão (adaptador de operandos, writer,
  tabelas e helpers).
- `patch_*.py`: correções manuais aplicadas sobre o corpo traduzido
  (relocações/labels e casos que o tradutor não cobre).
- `assemble.py`: junta cabeçalho + corpo + rodapé (estados de erro, enum
  `_S`, mapa encoding -> estado).
- `build.sh`: roda tudo e grava os erros do `dart analyze`.

Os scripts usam caminhos do scratchpad da sessão em que foram escritos
(variável `S`) e esperam o corpo do `_emit()` extraído do upstream em
`$S/emit.cpp` (x86: `x86assembler.cpp` a partir de `Assembler::_emit`;
A64: `$S/a64emit.cpp`, `a64assembler.cpp` linhas 780-fim). Os arquivos `.dart`
gerados são a fonte de verdade e já estão formatados; ao atualizar o upstream,
ajuste `S`, rode `build.sh`, `dart format` e compare com a versão commitada.
