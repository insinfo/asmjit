# RESOLVIDO (2026-07-10) — Causa raiz do STATUS_HEAP_CORRUPTION (0xC0000374)

O crash intermitente NÃO era problema de ABI/registradores preservados. Era um
**store de 8 bytes onde deveriam ser 4**:

- `UniOpMR.storeU32` marcava o operando de memória com size=4, mas mantinha o
  registrador fonte de 64 bits. O assembler escolhe o operand size pelo
  registrador, então emitia `mov qword ptr [mem], r64` (REX.W → `48 89 51 04`).
- No teste `integration_abi_test.dart` ("Pointer Access (Context)"), o buffer é
  `calloc<Int32>(2)` = 8 bytes; o store em `ctx+4` escrevia 8 bytes, ou seja,
  4 bytes além do fim da alocação → corrompia metadata do heap NT → crash
  intermitente no teardown de qualquer `dart.exe` filho.

Correções aplicadas (espelhando `referencias/asmjit-master/asmjit/ujit/unicompiler_x86.cpp`):

1. `unicompiler.dart` `_emitMRX86`: stores estreitos agora encolhem o registrador
   fonte (`as8/as16/as32`), como o C++ (`src.r32()` para kStoreU32). Também
   implementados `UniOpMR.addReg/addU8/U16/U32/U64` (antes caíam no default e
   viravam MOV!) e `storeReg`.
2. `unicompiler.dart` `_emitRMX86`: loads estreitos corrigidos — `loadU32` usa
   destino de 32 bits (zero-extend implícito), `loadI32` usa `movsxd`,
   `loadU8/U16` usam `movzx` com destino r32, e `loadMergeU8/loadShiftU8/
   loadMergeU16/loadShiftU16` implementados.
3. `x86_encoder.dart`: adicionados `movMemR8/R16`, `movR8Mem/R16Mem`,
   `movzxRegMem8/16`, `movsxRegMem8/16`, `movsxdR64Mem`.
4. `x86_assembler.dart`: `movMR/movRM` agora respeitam tamanhos de 8/16 bits
   (antes 8/16 viravam store/load de 32 bits); novos `movzxRM/movsxRM/movsxdRM/
   movzxRR/movsxRR`.
5. `tool/gen_x86_db.dart` (gerador do dispatcher): `movzx/movsx/movsxd`
   despachados; `_binary` ganhou formas com memória (`add [mem], reg` etc. eram
   descartados silenciosamente!); instruções/combinações não suportadas agora
   lançam `UnsupportedError` em vez de no-op silencioso (no-op silencioso em
   assembler = código de máquina corrompido).
6. Regressão: `test/asmjit/ujit_narrow_mem_test.dart` executa código JIT contra
   buffers com sentinelas e verifica byte a byte que nada fora do alvo é tocado,
   incluindo round-trips vetoriais de 1, 2, 4 e 8 bytes.
7. `RAPass`: destinos de memória de instruções `mov*` agora mantêm base/index
   virtuais como usos. Antes, `mov [ptr], xmm` marcava `ptr` como morto cedo e
   podia recarregá-lo de um spill não inicializado, causando `0xC0000005`.
8. `movq xmm, m64` e `movq m64, xmm` foram implementados no encoder/assembler;
   o dispatcher correspondente é sempre regenerado por `tool/gen_x86_db.dart`.

Suíte completa: 809 testes verdes. Loop de repro (100x) estável.

---

# Notas originais da investigação (kit de dumps)

Você já tem exatamente o kit certo aí. Com os sintomas atuais, o “mínimo indispensável” pra separar bug do Dart/Windows de bug no asmjit é:

Dump do processo que realmente crashou (não só o runner do dart test)
WinDbg pra abrir o dump e ver exceção + stack
O seu exit -1073740940 corresponde a 0xC0000374 (STATUS_HEAP_CORRUPTION) — isso costuma acontecer no processo filho que roda o arquivo de teste (o dart test orquestra e lança outros dart.exe). Por isso o ProcDump anexado ao PID do runner pode não gerar dump: quem explode é outro dart.exe.

O melhor caminho (recomendado): WER LocalDumps (pega qualquer dart.exe que crashar)

Crie uma pasta pro dump (exemplo): C:\MyDartProjects\asmjit\tool\wer_dumps
Ative LocalDumps por usuário (não precisa admin) no PowerShell:
reg add "HKCU\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\dart.exe" /v DumpFolder /t REG_EXPAND_SZ /d "C:\MyDartProjects\asmjit\tool\wer_dumps" /f

reg add "HKCU\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\dart.exe" /v DumpType /t REG_DWORD /d 2 /f

reg add "HKCU\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\dart.exe" /v DumpCount /t REG_DWORD /d 10 /f

Rode seu loop (dart run [repro_integration_abi_crash.dart](http://_vscodecontentref_/0) 200) e, quando falhar, procure o .dmp em tool\wer_dumps.
Abrir e analisar no WinDbg
Use (de preferência) o x64:

"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\windbg.exe" -z "C:\MyDartProjects\asmjit\tool\wer_dumps\SEU_DUMP.dmp"

Dentro do WinDbg:

.symfix
.sympath+ srv*C:\symbols*https://msdl.microsoft.com/download/symbols
.reload /f
!analyze -v
.ecxr
kb
r
u @rip-40
Opcional (muito útil): gflags PageHeap pra tornar o crash determinístico
Isso ajuda quando é overwrite de heap/stack “silencioso”:

Ativar: "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\gflags.exe" /p /enable dart.exe /full
Desativar depois: "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\gflags.exe" /p /disable dart.exe
(Provavelmente vai deixar tudo bem mais lento; use só durante a caça ao bug.)

Se você me mandar o primeiro .dmp gerado (ou pelo menos o output de !analyze -v e kb), dá pra dizer com boa confiança se o RIP está em código JIT (asmjit), no Dart VM, ou se é corrupção detectada no teardown — e aí a gente direciona o fix.
