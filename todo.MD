Vou analisar o estado atual do projeto — o debug_analysis.md, o repro de crash e a pasta de referências — para entender o que falta implementar e onde estão os segfaults.

Read c:\MyDartProjects\asmjit\debug_analysis.md
Read c:\MyDartProjects\asmjit\tool\repro_integration_abi_crash.dart
PowerShell List referencias folder and project directories
IN
Get-ChildItem C:\MyDartProjects\asmjit\referencias | Select-Object Name, Length; Get-ChildItem C:\MyDartProjects\asmjit -Directory | Select-Object Name

OUT
Name           Length
----           ------
asmjit-master  
asmtk-master   
blend2d-master 
.dart_tool     1
assets         1
benchmark      1
bin            1
build          1
docker         1
lib            1
referencias    1
scripts        1
test           1
tool           1
PowerShell List root files and check for CLAUDE.md
IN
Get-ChildItem C:\MyDartProjects\asmjit -File | Select-Object Name; Test-Path C:\MyDartProjects\asmjit\CLAUDE.md

OUT
Name
----
.gitignore
benchmark_report.md
codigo.bin
core.dump
dart_test.yaml
debug_analysis.md
how_to_debug.md
myeasylog.log
otimizacao.md
pubspec.lock
pubspec.yaml
relatorio_ffi_benchmark.md
roteiro_blend2d.md
roteiro_novo.md
False
PowerShell Show pending diff stats
IN
git -C C:\MyDartProjects\asmjit diff --stat; git -C C:\MyDartProjects\asmjit log --oneline -5

OUT
<persisted-output>
Output too large (113KB). Full output saved to: C:\Users\pmro\.claude\projects\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\tool-results\bmq6aico4.txt

Preview (first 2KB):
warning: in the working copy of 'assets/db/isa_aarch32.json', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'assets/db/isa_aarch64.json', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'assets/db/isa_aarch64_sme.json', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'assets/db/isa_x86.json', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'assets/db/isa_x86.md', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'benchmark/asmjit/ffi_overhead_benchmark.dart', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'benchmark/asmjit/native/build_chacha_bench.ps1', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'benchmark/asmjit/native/build_ffi_bench.ps1', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'benchmark/asmjit/native/chacha20_bench.c', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'benchmark/asmjit/native/ffi_bench.c', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'benchmark/asmjit/vpsrld_test.dart', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'docker/linux-arm64-test.Dockerfile', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'docker/linux-test.Dockerfile', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'lib/blend2d.dart', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'lib/src/asmjit/arm/a64_code_builder.dart', LF will be replaced by CRLF the next time Git touches it
...
</persisted-output>
PowerShell Show diff stat for modified files
IN
git -C C:\MyDartProjects\asmjit diff --stat -- lib/src/asmjit/core/rapass.dart debug_analysis.md 2>$null | Select-Object -Last 5

OUT
 debug_analysis.md               | 85 ++++++++++++++++++-------------------
 lib/src/asmjit/core/rapass.dart | 94 +++++++++++++++++++++++++++--------------
 2 files changed, 103 insertions(+), 76 deletions(-)
PowerShell Count test files and list test dirs
IN
Get-ChildItem C:\MyDartProjects\asmjit\test -Recurse -Filter *.dart | Measure-Object | Select-Object Count; Get-ChildItem C:\MyDartProjects\asmjit\test -Directory | Select-Object Name

OUT
Count
-----
   51
    1
    1
    1
    1
PowerShell Show pending rapass.dart changes
IN
git -C C:\MyDartProjects\asmjit diff -- lib/src/asmjit/core/rapass.dart

OUT
diff --git a/lib/src/asmjit/core/rapass.dart b/lib/src/asmjit/core/rapass.dart
index fbf6748..ddf788f 100644
--- a/lib/src/asmjit/core/rapass.dart
+++ b/lib/src/asmjit/core/rapass.dart
@@ -41,6 +41,9 @@ class _RACoalesceCandidate {
 class RAPass extends CompilerPass {
   final RALocalAllocator _allocator = RALocalAllocator();
 
+  // Cached target OS for ABI decisions (important on x64).
+  bool _isWindowsTarget = false;
+
   // Map from Virtual Register ID to RAWorkId
   final Map<int, RAWorkId> _virtIdToWorkId = {};
 
@@ -253,6 +256,7 @@ class RAPass extends CompilerPass {
         // Fallback if env check fails for some reason
         isWindows = Platform.isWindows;
       }
+      _isWindowsTarget = isWindows;
       print('RAPass: isWindows=$isWindows');
 
       final preservedGp =
@@ -1206,10 +1210,7 @@ class RAPass extends CompilerPass {
         last = last!.next;
       }
       if (last != null) {
-        newNode.prev = last;
-        newNode.next = last.next;
-        if (last.next != null) last.next!.prev = newNode;
-        last.next = newNode;
+        compiler.nodes.insertAfter(newNode, last);
       }
     }
   }
@@ -1273,10 +1274,7 @@ class RAPass extends CompilerPass {
   }
 
   void _removeNode(BaseNode node) {
-    if (node.prev != null) node.prev!.next = node.next;
-    if (node.next != null) node.next!.prev = node.prev;
-    // Note: NodeList doesn't know about this removal unless we use its methods.
-    // However, NodeList.nodes uses the links, so it works.
+    compiler.nodes.remove(node);
   }
 
   void _analyzeInstruction(InstNode node, List<RATiedReg> tiedRegs,
@@ -1808,14 +1806,47 @@ class RAPass extends CompilerPass {
     final arch = compiler.arch;
     final is64Bit = arch == Arch.x64;
 
+    // Detect VEX-prefixed (AVX) instructions by name in the instruction DB.
+    // This matters on Win64: VEX-encoded scalar ops on XMM6..XMM15 will also
+    // modify the upper 128 bits of the corresponding YMM register, which are
+    // required to be preserved when AVX is in use.
+    bool usesVex = false;
+    if (is64Bit) {
+      for (final n in compiler.nodes.nodes) {
+        if (n is InstNode) {
+          final id = n.instId;
+          if (id >= 0 && id < kX86InstDb.length) {
+            final name = kX86InstDb[id].name;
+            if (name.isNotEmpty && name.codeUnitAt(0) == 0x76 /* 'v' */) {
+              usesVex = true;
+              break;
+            }
+          }
+        }
+      }
+    }
+
     // Calculate registers to save
     final gpClobbered = _allocator.clobberedRegs[RegGroup.gp];
     final gpPreserved = _allocator.funcPreservedRegs[RegGroup.gp];
-    final gpToSave = gpClobbered & gpPreserved;
+
+    // Same rationale as vecToSave below: on Win64 it's safer to conservatively
+    // save all allocatable preserved GP registers (RBX, RSI, RDI, R12-R15...).
+    final gpToSave = (is64Bit && _isWindowsTarget)
+      ? (gpPreserved & _allocator.availableRegs[RegGroup.gp])
+      : (gpClobbered & gpPreserved);
 
     final vecClobbered = _allocator.clobberedRegs[RegGroup.vec];
     final vecPreserved = _allocator.funcPreservedRegs[RegGroup.vec];
-    final vecToSave = vecClobbered & vecPreserved;
+
+    // IMPORTANT (Win64): XMM6..XMM15 are callee-saved.
+    // If clobber tracking misses a vector reg in some corner case, we can
+    // corrupt the caller (Dart VM) and get intermittent crashes. To keep the
+    // JIT safe, conservatively save/restore all preserved vector registers on
+    // Win64.
+    final vecToSave = (is64Bit && _isWindowsTarget)
+      ? (vecPreserved & _allocator.availableRegs[RegGroup.vec])
+      : (vecClobbered & vecPreserved);
 
     final savedRegs = <X86Gp>[];
     for (int i = 0; i < 16; i++) {
@@ -1824,10 +1855,14 @@ class RAPass extends CompilerPass {
       }
     }
 
-    final savedVecRegs = <X86Xmm>[];
+    // On Win64 + AVX, preserve YMM6..YMM15 (full 256-bit) when non-volatile
+    // vector regs are saved/restored.
+    final vecSaveBytes = (is64Bit && _isWindowsTarget && usesVex) ? 32 : 16;
+
+    final savedVecIds = <int>[];
     for (int i = 0; i < 32; i++) {
       if ((vecToSave & (1 << i)) != 0) {
-        savedVecRegs.add(X86Xmm(i));
+        savedVecIds.add(i);
       }
     }
 
@@ -1838,11 +1873,11 @@ class RAPass extends CompilerPass {
 
     int currentOffset = localsSize;
 
-    if (savedVecRegs.isNotEmpty) {
+    if (savedVecIds.isNotEmpty) {
       currentOffset = _alignUp(currentOffset, 16);
-      for (final reg in savedVecRegs) {
-        currentOffset += 16;
-        vecSlots.add(MapEntry(reg, currentOffset));
+      for (final id in savedVecIds) {
+        currentOffset += vecSaveBytes;
+        vecSlots.add(MapEntry(X86Xmm(id), currentOffset));
       }
     }
 
@@ -1883,11 +1918,13 @@ class RAPass extends CompilerPass {
         lastNode = subRsp;
       }
 
-      // Spill preserved vector registers using aligned stores.
+      // Spill preserved vector registers.
       for (final slot in vecSlots) {
-        final mem = X86Mem.baseDisp(rbp, -slot.value, size: 16);
-        final save =
-            InstNode(X86InstId.kMovdqu, [mem, slot.key]); // unaligned OK
+        final mem = X86Mem.baseDisp(rbp, -slot.value, size: vecSaveBytes);
+
+        final reg = (vecSaveBytes == 32) ? X86Ymm(slot.key.id) : slot.key;
+        final instId = (vecSaveBytes == 32) ? X86InstId.kVmovdqu : X86InstId.kMovdqu;
+        final save = InstNode(instId, [mem, reg]);
         _insertNodeAfter(lastNode, save);
         lastNode = save;
       }
@@ -1922,9 +1959,10 @@ class RAPass extends CompilerPass {
         }
 
         for (final slot in vecSlots.reversed) {
-          final mem = X86Mem.baseDisp(rbp, -slot.value, size: 16);
-          final restore =
-              InstNode(X86InstId.kMovdqu, [slot.key, mem]); // unaligned OK
+          final mem = X86Mem.baseDisp(rbp, -slot.value, size: vecSaveBytes);
+          final reg = (vecSaveBytes == 32) ? X86Ymm(slot.key.id) : slot.key;
+          final instId = (vecSaveBytes == 32) ? X86InstId.kVmovdqu : X86InstId.kMovdqu;
+          final restore = InstNode(instId, [reg, mem]);
           _insertNodeBefore(node, restore);
         }
 
@@ -1952,17 +1990,11 @@ class RAPass extends CompilerPass {
   }
 
   void _insertNodeAfter(BaseNode after, BaseNode newNode) {
-    newNode.prev = after;
-    newNode.next = after.next;
-    if (after.next != null) after.next!.prev = newNode;
-    after.next = newNode;
+    compiler.nodes.insertAfter(newNode, after);
   }
 
   void _insertNodeBefore(BaseNode before, BaseNode newNode) {
-    newNode.next = before;
-    newNode.prev = before.prev;
-    if (before.prev != null) before.prev!.next = newNode;
-    before.prev = newNode;
+    compiler.nodes.insertBefore(newNode, before);
   }
 }
PowerShell List test structure
IN
Get-ChildItem C:\MyDartProjects\asmjit\test -Directory -Recurse | Select-Object FullName; (Get-ChildItem C:\MyDartProjects\asmjit\test -Recurse -Filter *.dart).Name

OUT
FullName
--------
C:\MyDartProjects\asmjit\test\asmjit
C:\MyDartProjects\asmjit\test\asmtk
C:\MyDartProjects\asmjit\test\integration
C:\MyDartProjects\asmjit\test\problema
a64_assembler_test.dart
a64_binary_test.dart
a64_compiler_test.dart
a64_generator_completion_test.dart
a64_ujit_ops_test.dart
asmjit_testing_assembler_x64_subset_test.dart
asmjit_testing_assembler_x86_test.dart
avx_test.dart
avx512_test.dart
bmi_aesni_test.dart
builder_test.dart
code_buffer_test.dart
compiler_test.dart
cpuinfo_test.dart
crypto_test.dart
inline_test.dart
jit_cache_test.dart
jit_execution_test.dart
labels_test.dart
ra_coalesce_test.dart
ra_spill_test.dart
short_jump_test.dart
sse_float_test.dart
sse_int_test.dart
sse_test.dart
sse4_1_test.dart
type_test.dart
ujit_a64_const_test.dart
ujit_a64_simd_complex_test.dart
ujit_conditional_test.dart
ujit_float_test.dart
ujit_logic_shift_test.dart
ujit_math_test.dart
ujit_mem_test.dart
ujit_simd_shuffle_test.dart
ujit_simd_test.dart
ujit_test.dart
x86_assembler_test.dart
x86_avx512_test.dart
x86_compiler_jit_test.dart
x86_encoder_test.dart
x86_extended_test.dart
asmtk_test.dart
chacha20_verify_test.dart
integration_abi_xmm_test.dart
integration_simd_test.dart
rapass_test.dart
ujit_const_test.dart
unicompiler_simd_test.dart
x86_instruction_verification_test.dart
integration_abi_test.dart
Read c:\MyDartProjects\asmjit\test\problema\integration_abi_test.dart
Update Todos

Establish baseline: run full test suite and note failures

Reproduce/diagnose Win64 heap-corruption segfault (integration_abi_test)

Fix root cause in RAPass prologue/epilogue vs asmjit C++ reference

Implement missing pieces flagged by tests/TODOs

Improve/extend tests and verify stability (repro loop)
PowerShell Run dart analyze for baseline
IN
dart analyze 2>&1 | Select-Object -Last 20

OUT
Exit code 2
Analyzing asmjit...

warning - tool\repro_integration_abi_crash.dart:52:45 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - tool\repro_integration_abi_crash.dart:53:34 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion

2 issues found.
Análise estática limpa (só 2 lints no tool de repro). Agora vou rodar o teste problemático e a suíte completa para estabelecer a baseline.

PowerShell Run the problem ABI integration test
IN
dart test test/problema/integration_abi_test.dart 2>&1 | Select-Object -Last 30

OUT
  Virt65: [6, 22]
  Virt67: [12, 22]
  Virt64: [4, 22]
  Virt66: [8, 22]
00:00 +2: Integration ABI Tests Function Arguments - Pointer Access (Context)
RAPass: isWindows=true
RAPass: LiveSpans
  Virt64: [4, 16]
  Virt65: [6, 16]
00:00 +3: Integration ABI Tests Function Arguments - Mixed Int/Float com spill de XMM
RAPass: isWindows=true
RAPass: LiveSpans
  Virt67: [2, 118]
  Virt65: [6, 118]
  Virt68: [12, 118]
  Virt64: [4, 118]
  Virt66: [8, 118]
  Virt69: [16, 118]
  Virt70: [20, 118]
  Virt71: [24, 118]
  Virt72: [28, 118]
  Virt73: [32, 118]
  Virt74: [36, 118]
  Virt75: [40, 118]
  Virt76: [44, 118]
  Virt77: [48, 118]
  Virt78: [52, 118]
  Virt79: [56, 118]
  Virt80: [60, 118]
00:00 +4: All tests passed!
PowerShell Run full test suite, summarize results
IN
dart test 2>&1 | Select-String -Pattern '(\+\d+.*?:)|(failed)|(passed)|(Some tests)' | Select-Object -Last 15

OUT
Command running in background with ID: bjo9irhgs. Output is being written to: C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\tasks\bjo9irhgs.output. You will be notified when it completes. To check interim output, use Read on that file path.
Enquanto a suíte completa roda em background, vou estudar o RAPass do port Dart e comparar com a referência C++ para achar a causa raiz do heap corruption.

Read c:\MyDartProjects\asmjit\lib\src\asmjit\core\rapass.dart
Read C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\tasks\bjo9irhgs.output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\core\rapass.dart (lines 1500-2009)
PowerShell List existing repro logs and dumps
IN
if (Test-Path C:\MyDartProjects\asmjit\tool\repro_logs) { Get-ChildItem C:\MyDartProjects\asmjit\tool\repro_logs | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name, Length, LastWriteTime }; if (Test-Path C:\MyDartProjects\asmjit\tool\wer_dumps) { Get-ChildItem C:\MyDartProjects\asmjit\tool\wer_dumps | Select-Object Name, Length, LastWriteTime }; if (Test-Path C:\MyDartProjects\asmjit\tool\repro_dumps) { Get-ChildItem C:\MyDartProjects\asmjit\tool\repro_dumps | Select-Object Name, Length }

OUT
(PowerShell completed with no output)
Grep "class JitRuntime|VirtualAlloc|malloc|calloc|allocator" (in c:\MyDartProjects\asmjit\lib\src\asmjit\core, glob: *.dart)
9 lines of output
Update Todos

Establish baseline: run full test suite and note failures

Reproduce/diagnose Win64 heap-corruption segfault (integration_abi_test)

Fix root cause in RAPass prologue/epilogue vs asmjit C++ reference

Implement missing pieces flagged by tests/TODOs

Improve/extend tests and verify stability (repro loop)
Grep "class JitRuntime|class JitAllocator|VirtualAlloc" (in c:\MyDartProjects\asmjit\lib)
7 lines of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\runtime\jit_runtime.dart
Grep "storeU32" (in c:\MyDartProjects\asmjit\lib)
3 lines of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler.dart (lines 1501-1620)
Write C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\scratchpad\dump_abi_code.dart
42 lines
import 'package:asmjit/asmjit.dart';

// Rebuilds the "Pointer Access (Context)" function from
// test/problema/integration_abi_test.dart and hexdumps the machine code.
void main() {
  final runtime = JitRuntime();
  final code = CodeHolder(env: runtime.environment);
  final archCompiler =
      X86Compiler(env: code.env, labelManager: code.labelManager);
  final cc = UniCompiler(archCompiler);

  cc.addFunc(FuncSignature.build(
      [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.x64Windows));

  final ctx = cc.newGpPtr('ctx');
  final val = cc.newGpPtr('val');
  cc.setArg(0, ctx);
  cc.setArg(1, val);

  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx as X86Gp, 0)), val);
  cc.emitRRI(UniOpRRR.add, val, val, 1);
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx, 4)), val);

  cc.ret();
  cc.endFunc();

  archCompiler.finalize();
  final assembler = X86Assembler(code);
  archCompiler.serializeToAssembler(assembler);

  final finalized = code.finalize();
  final bytes = finalized.textBytes;

  final sb = StringBuffer();
  for (int i = 0; i < bytes.length; i++) {
    sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    sb.write(' ');
    if ((i + 1) % 16 == 0) sb.writeln();
  }
  print(sb);
}
PowerShell Dump machine code of pointer-access test function
IN
dart run "C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\scratchpad\dump_abi_code.dart"

OUT
Exit code 254
Error: Couldn't resolve the package 'asmjit' in 'package:asmjit/asmjit.dart'.
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:1:8: Error: Not found: 'package:asmjit/asmjit.dart'
import 'package:asmjit/asmjit.dart';
       ^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:6:19: Error: Method not found: 'JitRuntime'.
  final runtime = JitRuntime();
                  ^^^^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:7:16: Error: Method not found: 'CodeHolder'.
  final code = CodeHolder(env: runtime.environment);
               ^^^^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:9:7: Error: Method not found: 'X86Compiler'.
      X86Compiler(env: code.env, labelManager: code.labelManager);
      ^^^^^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:10:14: Error: Method not found: 'UniCompiler'.
  final cc = UniCompiler(archCompiler);
             ^^^^^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:13:8: Error: Undefined name 'TypeId'.
      [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.x64Windows));
       ^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:13:23: Error: Undefined name 'TypeId'.
      [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.x64Windows));
                      ^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:13:39: Error: Undefined name 'TypeId'.
      [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.x64Windows));
                                      ^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:13:53: Error: Undefined name 'CallConvId'.
      [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.x64Windows));
                                                    ^^^^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:12:14: Error: Undefined name 'FuncSignature'.
  cc.addFunc(FuncSignature.build(
             ^^^^^^^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:20:13: Error: Undefined name 'UniOpMR'.
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx as X86Gp, 0)), val);
            ^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:20:61: Error: 'X86Gp' isn't a type.
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx as X86Gp, 0)), val);
                                                            ^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:20:38: Error: Undefined name 'X86Mem'.
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx as X86Gp, 0)), val);
                                     ^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:20:31: Error: Method not found: 'UniMem'.
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx as X86Gp, 0)), val);
                              ^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:21:14: Error: Undefined name 'UniOpRRR'.
  cc.emitRRI(UniOpRRR.add, val, val, 1);
             ^^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:22:13: Error: Undefined name 'UniOpMR'.
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx, 4)), val);
            ^^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:22:38: Error: Undefined name 'X86Mem'.
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx, 4)), val);
                                     ^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:22:31: Error: Method not found: 'UniMem'.
  cc.emitMR(UniOpMR.storeU32, UniMem(X86Mem.baseDisp(ctx, 4)), val);
                              ^^^^^^
/C:/Users/pmro/AppData/Local/Temp/claude/c--MyDartProjects-asmjit/57edd249-1cb3-4a08-acc9-6d35e4dbcf00/scratchpad/dump_abi_code.dart:28:21: Error: Method not found: 'X86Assembler'.
  final assembler = X86Assembler(code);
                    ^^^^^^^^^^^^
PowerShell Run code dump tool inside project for package resolution
IN
Copy-Item "C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\scratchpad\dump_abi_code.dart" C:\MyDartProjects\asmjit\tool\dump_abi_code.dart; dart run C:\MyDartProjects\asmjit\tool\dump_abi_code.dart

OUT
RAPass: isWindows=true
RAPass: LiveSpans
  Virt64: [4, 16]
  Virt65: [6, 16]
55 48 89 e5 48 81 ec e0 00 00 00 f3 0f 7f 75 f0 
f3 0f 7f 7d e0 f3 44 0f 7f 45 d0 f3 44 0f 7f 4d 
c0 f3 44 0f 7f 55 b0 f3 44 0f 7f 5d a0 f3 44 0f 
7f 65 90 f3 44 0f 7f 6d 80 f3 44 0f 7f b5 70 ff 
ff ff f3 44 0f 7f bd 60 ff ff ff 48 89 9d 58 ff 
ff ff 48 89 b5 50 ff ff ff 48 89 bd 48 ff ff ff 
4c 89 a5 40 ff ff ff 4c 89 ad 38 ff ff ff 4c 89 
b5 30 ff ff ff 4c 89 bd 28 ff ff ff 48 89 11 48 
83 c2 01 48 89 51 04 4c 8b bd 28 ff ff ff 4c 8b 
b5 30 ff ff ff 4c 8b ad 38 ff ff ff 4c 8b a5 40 
ff ff ff 48 8b bd 48 ff ff ff 48 8b b5 50 ff ff 
ff 48 8b 9d 58 ff ff ff f3 44 0f 6f bd 60 ff ff 
ff f3 44 0f 6f b5 70 ff ff ff f3 44 0f 6f 6d 80 
f3 44 0f 6f 65 90 f3 44 0f 6f 5d a0 f3 44 0f 6f 
55 b0 f3 44 0f 6f 4d c0 f3 44 0f 6f 45 d0 f3 0f 
6f 7d e0 f3 0f 6f 75 f0 48 89 ec 5d c3
Grep "store_u32|store_32|r32\(\)" (in c:\MyDartProjects\asmjit\referencias\blend2d-master\src\blend2d\pipeline\jit)
1 line of output
Grep "X86Gp (r8|r16|r32|r64)\b|class X86Gp" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_operands.dart)
1 line of output
Grep "class X86Gp" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86)
1 line of output
PowerShell Explore blend2d reference layout
IN
Get-ChildItem C:\MyDartProjects\asmjit\referencias\blend2d-master -Directory | Select-Object Name; Get-ChildItem C:\MyDartProjects\asmjit\referencias\blend2d-master\src -Recurse -Directory -ErrorAction SilentlyContinue | Select-Object -First 20 FullName

OUT
Name
----
.github
blend2d
blend2d-testing
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86.dart (lines 2-161)
Read c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler.dart (lines 1441-1502)
Grep "enum UniOpMR|enum UniOpRM" (in c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\uniop.dart)
33 lines of output
Grep "kStoreU32|StoreU32" (in c:\MyDartProjects\asmjit\referencias\blend2d-master\blend2d)
1 line of output
Grep "store_u32" (in c:\MyDartProjects\asmjit\referencias)
13 lines of output
Grep "kStoreU32" (in c:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit\ujit, glob: *.cpp)
73 lines of output
Grep "void UniCompiler::emit_rm" (in c:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit\ujit\unicompiler_x86.cpp)
61 lines of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler.dart (lines 1488-1501)
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler.dart
Added 43 lines
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler.dart
Added 53 lines
PowerShell Analyze after unicompiler edits
IN
dart analyze 2>&1 | Select-Object -Last 10

OUT
Exit code 2
Analyzing asmjit...

warning - tool\dump_abi_code.dart:20:54 - Unnecessary cast. Try removing the cast. - unnecessary_cast
warning - tool\repro_integration_abi_crash.dart:52:45 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - tool\repro_integration_abi_crash.dart:53:34 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion

3 issues found.
PowerShell Re-dump machine code after fix
IN
dart run C:\MyDartProjects\asmjit\tool\dump_abi_code.dart

OUT
RAPass: isWindows=true
RAPass: LiveSpans
  Virt64: [4, 16]
  Virt65: [6, 16]
55 48 89 e5 48 81 ec e0 00 00 00 f3 0f 7f 75 f0 
f3 0f 7f 7d e0 f3 44 0f 7f 45 d0 f3 44 0f 7f 4d 
c0 f3 44 0f 7f 55 b0 f3 44 0f 7f 5d a0 f3 44 0f 
7f 65 90 f3 44 0f 7f 6d 80 f3 44 0f 7f b5 70 ff 
ff ff f3 44 0f 7f bd 60 ff ff ff 48 89 9d 58 ff 
ff ff 48 89 b5 50 ff ff ff 48 89 bd 48 ff ff ff 
4c 89 a5 40 ff ff ff 4c 89 ad 38 ff ff ff 4c 89 
b5 30 ff ff ff 4c 89 bd 28 ff ff ff 89 11 48 83 
c2 01 89 51 04 4c 8b bd 28 ff ff ff 4c 8b b5 30 
ff ff ff 4c 8b ad 38 ff ff ff 4c 8b a5 40 ff ff 
ff 48 8b bd 48 ff ff ff 48 8b b5 50 ff ff ff 48 
8b 9d 58 ff ff ff f3 44 0f 6f bd 60 ff ff ff f3 
44 0f 6f b5 70 ff ff ff f3 44 0f 6f 6d 80 f3 44 
0f 6f 65 90 f3 44 0f 6f 5d a0 f3 44 0f 6f 55 b0 
f3 44 0f 6f 4d c0 f3 44 0f 6f 45 d0 f3 0f 6f 7d 
e0 f3 0f 6f 75 f0 48 89 ec 5d c3
Read c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_a64.dart (lines 121-250)
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_a64.dart
Added 3 lines
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_a64.dart
Added 3 lines
Grep "debugLog|kDebug|verbose|assertionsEnabled" (in c:\MyDartProjects\asmjit\lib\src\asmjit\core)
1 line of output
Read c:\MyDartProjects\asmjit\test\asmjit\ujit_mem_test.dart
Write c:\MyDartProjects\asmjit\test\asmjit\ujit_narrow_mem_test.dart
326 lines
/// Regression tests for narrow memory loads/stores emitted by UniCompiler.
///
/// Root cause of the intermittent STATUS_HEAP_CORRUPTION (0xC0000374) crash:
/// `UniOpMR.storeU32` annotated the memory operand with size 4 but kept the
/// 64-bit source register, so the assembler emitted `mov qword ptr [mem], r64`
/// (REX.W) and wrote 8 bytes — 4 bytes past the end of user heap buffers.
/// The same class of bug affected narrow loads (8-byte reads) and
/// `UniOpMR.addU*` (which fell through to MOV instead of ADD).
///
/// These tests execute JIT code against heap buffers surrounded by sentinel
/// bytes and verify that not a single byte outside the target is touched.
import 'dart:ffi';

import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:test/test.dart';

typedef _StoreNative = Void Function(Pointer<Uint8>, IntPtr);
typedef _StoreDart = void Function(Pointer<Uint8>, int);
typedef _LoadNative = IntPtr Function(Pointer<Uint8>);
typedef _LoadDart = int Function(Pointer<Uint8>);

JitFunction _compile(
    JitRuntime runtime, void Function(UniCompiler cc) generator) {
  final code = CodeHolder(env: runtime.environment);
  final archCompiler =
      X86Compiler(env: code.env, labelManager: code.labelManager);
  final cc = UniCompiler(archCompiler);

  generator(cc);

  archCompiler.finalize();
  final assembler = X86Assembler(code);
  archCompiler.serializeToAssembler(assembler);
  return runtime.add(code);
}

UniMem _mem(BaseReg base, int disp) =>
    UniMem(X86Mem.baseDisp(base as X86Gp, disp));

void main() {
  final hostIsX64 = Environment.host().arch == Arch.x64;

  group('UJIT narrow store safety', () {
    late JitRuntime runtime;

    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    /// Builds `void fn(uint8_t* p, intptr_t val)` performing a single
    /// narrow store at [p + disp], then verifies sentinel bytes around the
    /// written range stay intact.
    void checkStore({
      required UniOpMR op,
      required int width,
      required int disp,
      required int value,
      required List<int> expectedBytes,
    }) {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        final v = cc.newGpPtr('v');
        cc.setArg(0, p);
        cc.setArg(1, v);
        cc.emitMR(op, _mem(p, disp), v);
        cc.ret();
        cc.endFunc();
      });

      const bufSize = 32;
      final buf = pkgffi.calloc<Uint8>(bufSize);
      try {
        for (int i = 0; i < bufSize; i++) {
          buf[i] = 0xA5; // sentinel
        }

        final call = fn.pointer
            .cast<NativeFunction<_StoreNative>>()
            .asFunction<_StoreDart>();
        call(buf, value);

        for (int i = 0; i < bufSize; i++) {
          final inTarget = i >= disp && i < disp + width;
          if (inTarget) {
            expect(buf[i], equals(expectedBytes[i - disp]),
                reason: 'byte $i (inside store target) has wrong value');
          } else {
            expect(buf[i], equals(0xA5),
                reason: 'byte $i outside the $width-byte store target at '
                    '+$disp was clobbered — store wrote too many bytes');
          }
        }
      } finally {
        pkgffi.calloc.free(buf);
      }
    }

    test('storeU32 writes exactly 4 bytes', () {
      checkStore(
        op: UniOpMR.storeU32,
        width: 4,
        disp: 8,
        value: 0x11223344,
        expectedBytes: [0x44, 0x33, 0x22, 0x11],
      );
    });

    test('storeU32 ignores high 32 bits of the source register', () {
      // High garbage bits in the 64-bit register must not reach memory.
      checkStore(
        op: UniOpMR.storeU32,
        width: 4,
        disp: 4,
        value: 0x7FFFFFFF11223344,
        expectedBytes: [0x44, 0x33, 0x22, 0x11],
      );
    });

    test('storeU16 writes exactly 2 bytes', () {
      checkStore(
        op: UniOpMR.storeU16,
        width: 2,
        disp: 6,
        value: 0x1122EEFF,
        expectedBytes: [0xFF, 0xEE],
      );
    });

    test('storeU8 writes exactly 1 byte', () {
      checkStore(
        op: UniOpMR.storeU8,
        width: 1,
        disp: 3,
        value: 0x11223377,
        expectedBytes: [0x77],
      );
    });

    test('storeU64 writes exactly 8 bytes', () {
      checkStore(
        op: UniOpMR.storeU64,
        width: 8,
        disp: 8,
        value: 0x1122334455667788,
        expectedBytes: [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11],
      );
    });

    test('crash repro shape: two u32 stores fill an 8-byte heap buffer', () {
      // Exact pattern from integration_abi_test 'Pointer Access (Context)':
      // ctx[0] = val; ctx[1] = val + 1 on a calloc'd 2 x int32 buffer.
      // The old 8-byte store at +4 corrupted the heap allocator's metadata.
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final ctx = cc.newGpPtr('ctx');
        final val = cc.newGpPtr('val');
        cc.setArg(0, ctx);
        cc.setArg(1, val);
        cc.emitMR(UniOpMR.storeU32, _mem(ctx, 0), val);
        cc.emitRRI(UniOpRRR.add, val, val, 1);
        cc.emitMR(UniOpMR.storeU32, _mem(ctx, 4), val);
        cc.ret();
        cc.endFunc();
      });

      final call = fn.pointer
          .cast<NativeFunction<Void Function(Pointer<Int32>, IntPtr)>>()
          .asFunction<void Function(Pointer<Int32>, int)>();

      // Loop to give the heap plenty of chances to detect an overflow.
      for (int i = 0; i < 1000; i++) {
        final mem = pkgffi.calloc<Int32>(2);
        try {
          call(mem, i);
          expect(mem[0], equals(i));
          expect(mem[1], equals(i + 1));
        } finally {
          pkgffi.calloc.free(mem);
        }
      }
    });
  }, skip: hostIsX64 ? false : 'x64-only test');

  group('UJIT memory add (UniOpMR.add*)', () {
    late JitRuntime runtime;

    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    test('addU32 performs ADD (not MOV) and writes exactly 4 bytes', () {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        final v = cc.newGpPtr('v');
        cc.setArg(0, p);
        cc.setArg(1, v);
        cc.emitMR(UniOpMR.addU32, _mem(p, 0), v);
        cc.ret();
        cc.endFunc();
      });

      final buf = pkgffi.calloc<Uint32>(2);
      try {
        buf[0] = 100;
        buf[1] = 0xCAFEBABE; // sentinel

        final call = fn.pointer
            .cast<NativeFunction<_StoreNative>>()
            .asFunction<_StoreDart>();
        call(buf.cast<Uint8>(), 23);

        expect(buf[0], equals(123),
            reason: 'addU32 must ADD to memory, not overwrite it');
        expect(buf[1], equals(0xCAFEBABE),
            reason: 'addU32 must not touch bytes past the 4-byte target');
      } finally {
        pkgffi.calloc.free(buf);
      }
    });

    test('addU64 adds 8 bytes in place', () {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr, TypeId.intPtr], TypeId.void_, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        final v = cc.newGpPtr('v');
        cc.setArg(0, p);
        cc.setArg(1, v);
        cc.emitMR(UniOpMR.addU64, _mem(p, 0), v);
        cc.ret();
        cc.endFunc();
      });

      final buf = pkgffi.calloc<Int64>(1);
      try {
        buf.value = 0x100000000; // forces a carry into the high dword
        final call = fn.pointer
            .cast<NativeFunction<_StoreNative>>()
            .asFunction<_StoreDart>();
        call(buf.cast<Uint8>(), 7);
        expect(buf.value, equals(0x100000007));
      } finally {
        pkgffi.calloc.free(buf);
      }
    });
  }, skip: hostIsX64 ? false : 'x64-only test');

  group('UJIT narrow load correctness', () {
    late JitRuntime runtime;

    setUp(() => runtime = JitRuntime());
    tearDown(() => runtime.dispose());

    /// Builds `intptr_t fn(uint8_t* p)` performing a single narrow load at
    /// [p + disp] and returning it. The buffer is filled with 0xFF beyond the
    /// loaded range, so an over-wide load produces a detectably wrong value.
    int runLoad({required UniOpRM op, required int disp}) {
      final fn = _compile(runtime, (cc) {
        cc.addFunc(FuncSignature.build(
            [TypeId.intPtr], TypeId.intPtr, CallConvId.cdecl));
        final p = cc.newGpPtr('p');
        cc.setArg(0, p);
        final out = cc.newGpPtr('out');
        cc.emitRM(op, out, _mem(p, disp));
        cc.ret([out]);
        cc.endFunc();
      });

      const bufSize = 32;
      final buf = pkgffi.calloc<Uint8>(bufSize);
      try {
        // Little-endian payload 0x8899AABBCCDDEEFF at +8; 0xFF elsewhere so
        // an 8-byte read where 4 was intended is guaranteed to differ.
        for (int i = 0; i < bufSize; i++) {
          buf[i] = 0xFF;
        }
        final payload = [0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88];
        for (int i = 0; i < payload.length; i++) {
          buf[8 + i] = payload[i];
        }

        final call = fn.pointer
            .cast<NativeFunction<_LoadNative>>()
            .asFunction<_LoadDart>();
        return call(buf);
      } finally {
        pkgffi.calloc.free(buf);
      }
    }

    test('loadU32 reads 4 bytes and zero-extends', () {
      expect(runLoad(op: UniOpRM.loadU32, disp: 8), equals(0xCCDDEEFF));
    });

    test('loadI32 reads 4 bytes and sign-extends', () {
      expect(runLoad(op: UniOpRM.loadI32, disp: 8),
          equals(0xCCDDEEFF - 0x100000000)); // 0xCCDDEEFF has the sign bit set
    });

    test('loadU16 reads 2 bytes and zero-extends', () {
      expect(runLoad(op: UniOpRM.loadU16, disp: 8), equals(0xEEFF));
    });

    test('loadI16 reads 2 bytes and sign-extends', () {
      expect(runLoad(op: UniOpRM.loadI16, disp: 8), equals(0xEEFF - 0x10000));
    });

    test('loadU8 reads 1 byte and zero-extends', () {
      expect(runLoad(op: UniOpRM.loadU8, disp: 8), equals(0xFF));
    });

    test('loadI8 reads 1 byte and sign-extends', () {
      expect(runLoad(op: UniOpRM.loadI8, disp: 8), equals(-1));
    });

    test('loadU64 reads 8 bytes', () {
      expect(runLoad(op: UniOpRM.loadU64, disp: 8),
          equals(0x8899AABBCCDDEEFF - 0x10000000000000000)); // as signed int64
    });
  }, skip: hostIsX64 ? false : 'x64-only test');
}
Edit c:\MyDartProjects\asmjit\test\asmjit\ujit_narrow_mem_test.dart
Added 1 line
PowerShell Run new narrow-memory regression tests
IN
dart test test/asmjit/ujit_narrow_mem_test.dart 2>&1 | Select-String -Pattern '\+\d+|failed|passed|Error|CRASH' | Select-Object -Last 15

OUT
Exit code 1
00:00 +4 -3: UJIT memory add (UniOpMR.add*) addU64 adds 8 bytes in place
00:00 +4 -4: UJIT memory add (UniOpMR.add*) addU64 adds 8 bytes in place [E]
00:00 +4 -4: UJIT narrow load correctness loadU32 reads 4 bytes and zero-extends
00:00 +5 -4: UJIT narrow load correctness loadI32 reads 4 bytes and sign-extends
00:00 +5 -5: UJIT narrow load correctness loadI32 reads 4 bytes and sign-extends [E]
00:00 +5 -5: UJIT narrow load correctness loadU16 reads 2 bytes and zero-extends
00:00 +5 -6: UJIT narrow load correctness loadU16 reads 2 bytes and zero-extends [E]
00:00 +5 -6: UJIT narrow load correctness loadI16 reads 2 bytes and sign-extends
00:00 +5 -7: UJIT narrow load correctness loadI16 reads 2 bytes and sign-extends [E]
00:00 +5 -7: UJIT narrow load correctness loadU8 reads 1 byte and zero-extends
00:00 +5 -8: UJIT narrow load correctness loadU8 reads 1 byte and zero-extends [E]
00:00 +5 -8: UJIT narrow load correctness loadI8 reads 1 byte and sign-extends
00:00 +5 -9: UJIT narrow load correctness loadI8 reads 1 byte and sign-extends [E]
00:00 +5 -9: UJIT narrow load correctness loadU64 reads 8 bytes
00:00 +6 -9: Some tests failed.
Os novos testes acharam mais problemas (9 falhas). Vou ver os detalhes:

PowerShell Show failure details of narrow-mem tests
IN
dart test test/asmjit/ujit_narrow_mem_test.dart --reporter expanded 2>&1 | Select-String -Pattern '\[E\]|Expected|Actual|Unimplemented|Unsupported|Exception|Error:' -Context 0,2 | Select-Object -First 60

OUT
Exit code 1
> 00:00 +2 -1: UJIT narrow store safety storeU16 writes exactly 2 bytes [E]
>   Expected: <165>
>     Actual: <34>
    byte 8 outside the 2-byte store target at +6 was clobbered — store wrote too many bytes
    
> 00:00 +2 -2: UJIT narrow store safety storeU8 writes exactly 1 byte [E]
>   Expected: <165>
>     Actual: <51>
    byte 4 outside the 1-byte store target at +3 was clobbered — store wrote too many bytes
    
> 00:00 +4 -3: UJIT memory add (UniOpMR.add*) addU32 performs ADD (not MOV) and writes exactly 4 bytes [E]
>   Expected: <123>
>     Actual: <100>
    addU32 must ADD to memory, not overwrite it
    
> 00:00 +4 -4: UJIT memory add (UniOpMR.add*) addU64 adds 8 bytes in place [E]
>   Expected: <4294967303>
>     Actual: <4294967296>
    
    package:matcher                              expect
> 00:00 +5 -5: UJIT narrow load correctness loadI32 reads 4 bytes and sign-extends [E]
>   Expected: <-857870593>
>     Actual: <1942285451264>
    
    package:matcher                              expect
> 00:00 +5 -6: UJIT narrow load correctness loadU16 reads 2 bytes and zero-extends [E]
>   Expected: <61183>
>     Actual: <1942183477248>
    
    package:matcher                              expect
> 00:00 +5 -7: UJIT narrow load correctness loadI16 reads 2 bytes and sign-extends [E]
>   Expected: <-4353>
>     Actual: <1942392668160>
    
    package:matcher                              expect
> 00:00 +5 -8: UJIT narrow load correctness loadU8 reads 1 byte and zero-extends [E]
>   Expected: <255>
>     Actual: <1942182756352>
    
    package:matcher                              expect
> 00:00 +5 -9: UJIT narrow load correctness loadI8 reads 1 byte and sign-extends [E]
>   Expected: <-1>
>     Actual: <1942182756352>
    
    package:matcher                              expect
> Consider enabling the flag chain-stack-traces to receive more detailed exceptions.
  For example, 'dart test --chain-stack-traces'.
Globpattern: "lib/src/asmjit/x86/*.dart"
Found 11 files
Grep "kMovzx|kMovsxd|kMovsx" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_serializer.dart)
1 line of output
Grep "kMovzx|kMovsxd" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart)
1 line of output
Grep "Movzx|movzx" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86)
31 lines of output
Grep "case X86InstId.kMovzx|case X86InstId.kMovsx|case X86InstId.kMovsxd|case X86InstId.kMov\b|case X86InstId.kAdd\b" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_serializer.dart)
1 line of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_serializer.dart
Grep "kMovzx|kMovsxd|kMovsx\b" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart)
1 line of output
Grep "case 62|case 61|case 63" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart)
1 line of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart
Grep "kMovzx:|kMovsx:|kMovsxd:|kMov:|_binary\(|void _binary|void _mov" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart)
12 lines of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart (lines 667-866)
Grep "movRM|movMR|movzx|movsx" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart)
31 lines of output
Grep "_mov\(asm|kMov:|default:|Unsupported IDs" (in c:\MyDartProjects\asmjit\tool\gen_x86_db.dart)
5 lines of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart (lines 161-280)
lembrece arquivos gerados não podem ser mechidos x86_dispatcher.g.dart tem que corrigir o gerador  C:\MyDartProjects\asmjit\tool
Read c:\MyDartProjects\asmjit\tool\gen_x86_db.dart (lines 541-670)
Grep "void (movMemR|movR32Mem|movR64Mem|movsx|movzx|movsxd|addMR|addRM|addMI)" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart)
12 lines of output
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart (lines 471-710)
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart (lines 1091-1160)
Grep "void emitRexForRegMem|void emitRexForRegRm|void emitRexForReg\b|void _emitOpSizeAndRexForRegRm|void _emitOpSizeAndRexForReg\b" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart)
79 lines of output
Update Todos

Establish baseline: run full test suite and note failures

Diagnose segfault: storeU32 emitted 8-byte store (root cause found)

Fix UniCompiler narrow load/store + add-to-mem (x86 & A64)

Add encoder support: 8/16-bit mov mem, movzx/movsx/movsxd from mem

Fix generator gen_x86_db.dart: dispatch movzx/movsx/movsxd, mem forms in _binary/_mov; regenerate

Run new regression tests + full suite + repro loop
Agora vou adicionar os métodos que faltam no encoder (formas de 8/16 bits e movzx/movsx/movsxd com memória):

Edit c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart
Added 30 lines
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart
Added 39 lines
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart
Added 25 lines
Read c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart (lines 381-430)
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart
Added 63 lines
Agora o gerador. Vou ver o conjunto supported e a função _helpers():

Grep "final supported = |'mov',|'add'," (in c:\MyDartProjects\asmjit\tool\gen_x86_db.dart)
21 lines of output
Grep "String _helpers\(\)" (in c:\MyDartProjects\asmjit\tool\gen_x86_db.dart)
121 lines of output
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 3 lines
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 6 lines
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 24 lines
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 16 lines
Agora o default do switch — trocar o no-op silencioso por erro explícito com o nome da instrução:

Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 2 lines
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 6 lines
Grep "void main" (in c:\MyDartProjects\asmjit\tool\gen_x86_db.dart)
1 line of output
Grep "main\(" (in c:\MyDartProjects\asmjit\tool, glob: gen_x86*.dart)
21 lines of output
PowerShell Regenerate x86 DB and dispatcher
IN
git -C C:\MyDartProjects\asmjit status --short lib/src/asmjit/x86/x86_inst_db.g.dart; dart run tool/gen_x86_db.dart 2>&1 | Select-Object -Last 5; git -C C:\MyDartProjects\asmjit diff --stat -- lib/src/asmjit/x86/x86_inst_db.g.dart lib/src/asmjit/x86/x86_dispatcher.g.dart 2>$null | Select-Object -Last 4

OUT
Total forms: 3632
Generated 1831 instructions
Generated Dispatcher at lib/src/asmjit/x86/x86_dispatcher.g.dart

Done! Generated lib/src/asmjit/x86/x86_inst_db.g.dart
 lib/src/asmjit/x86/x86_dispatcher.g.dart | 93 +++++++++++++++++++++++---------
 1 file changed, 69 insertions(+), 24 deletions(-)
PowerShell Analyze and run narrow-mem regression tests
IN
dart analyze 2>&1 | Select-Object -Last 6; dart test test/asmjit/ujit_narrow_mem_test.dart 2>&1 | Select-Object -Last 4

OUT
Exit code 1
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:628:111 - The method 'vpsrldYmmYmm' isn't defined for the type 'X86Assembler'. Try correcting the name to the name of an existing method, or defining a method named 'vpsrldYmmYmm'. - undefined_method
warning - tool\dump_abi_code.dart:20:54 - Unnecessary cast. Try removing the cast. - unnecessary_cast
warning - tool\repro_integration_abi_crash.dart:52:45 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - tool\repro_integration_abi_crash.dart:53:34 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion

13 issues found.
  lib/src/asmjit/x86/x86_dispatcher.g.dart:829:6: Context: Found this candidate, but the arguments don't match.
  void _shift(X86Assembler asm, List<Object> ops,
       ^^^^^^
00:00 +0 -1: Some tests failed.
PowerShell List all analyzer errors
IN
dart analyze 2>&1 | Select-String 'error' | Select-Object -First 15

OUT
Exit code 3
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:625:24 - The argument type 'Null' can't be assigned to the 
parameter type 'void Function(X86Gp, int)'.  - argument_type_not_assignable
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:625:36 - The named parameter 'xmmI' isn't defined. Try correcting 
the name to an existing named parameter's name, or defining a named parameter with the name 'xmmI'. - 
undefined_named_parameter
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:625:61 - The method 'vpslldXmmXmm' isn't defined for the type 
'X86Assembler'. Try correcting the name to the name of an existing method, or defining a method named 'vpslldXmmXmm'. 
- undefined_method
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:625:86 - The named parameter 'ymmI' isn't defined. Try correcting 
the name to an existing named parameter's name, or defining a named parameter with the name 'ymmI'. - 
undefined_named_parameter
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:625:111 - The method 'vpslldYmmYmm' isn't defined for the type 
'X86Assembler'. Try correcting the name to the name of an existing method, or defining a method named 'vpslldYmmYmm'. 
- undefined_method
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:628:24 - The argument type 'Null' can't be assigned to the 
parameter type 'void Function(X86Gp, int)'.  - argument_type_not_assignable
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:628:36 - The named parameter 'xmmI' isn't defined. Try correcting 
the name to an existing named parameter's name, or defining a named parameter with the name 'xmmI'. - 
undefined_named_parameter
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:628:61 - The method 'vpsrldXmmXmm' isn't defined for the type 
'X86Assembler'. Try correcting the name to the name of an existing method, or defining a method named 'vpsrldXmmXmm'. 
- undefined_method
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:628:86 - The named parameter 'ymmI' isn't defined. Try correcting 
the name to an existing named parameter's name, or defining a named parameter with the name 'ymmI'. - 
undefined_named_parameter
  error - lib\src\asmjit\x86\x86_dispatcher.g.dart:628:111 - The method 'vpsrldYmmYmm' isn't defined for the type 
'X86Assembler'. Try correcting the name to the name of an existing method, or defining a method named 'vpsrldYmmYmm'. 
- undefined_method
PowerShell Show committed dispatcher handling of vpslld/vpsrld
IN
git -C C:\MyDartProjects\asmjit\ show HEAD:lib/src/asmjit/x86/x86_dispatcher.g.dart | Select-String -Pattern 'kVpslld|kVpsrld|_simdShift' -Context 0,3 | Select-Object -First 12

OUT
>     case X86InstId.kVpslld:
        _simd3(asm, ops, xmm: (d, s1, s2) {
    final imm = s2 is Imm ? s2.value : s2 as int;
    asm.vpslld(d, s1, imm);
>     case X86InstId.kVpsrld:
        _simd3(asm, ops, xmm: (d, s1, s2) {
    final imm = s2 is Imm ? s2.value : s2 as int;
    asm.vpsrld(d, s1, imm);
PowerShell Full committed vpslld case
IN
git -C C:\MyDartProjects\asmjit show HEAD:lib/src/asmjit/x86/x86_dispatcher.g.dart | Select-String -Pattern 'kVpslld' -Context 0,12

OUT
>     case X86InstId.kVpslld:
        _simd3(asm, ops, xmm: (d, s1, s2) {
    final imm = s2 is Imm ? s2.value : s2 as int;
    asm.vpslld(d, s1, imm);
  });
        break;
      case X86InstId.kVpsrld:
        _simd3(asm, ops, xmm: (d, s1, s2) {
    final imm = s2 is Imm ? s2.value : s2 as int;
    asm.vpsrld(d, s1, imm);
  });
        break;
      case X86InstId.kVpxor:
Grep "vpslld|vpsrld" (in c:\MyDartProjects\asmjit\tool\gen_x86_db.dart)
28 lines of output
Grep "void vpslld|void vpsrld" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart)
2 lines of output
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 6 lines
PowerShell Regenerate dispatcher and analyze
IN
dart run tool/gen_x86_db.dart 2>&1 | Select-Object -Last 2; dart analyze 2>&1 | Select-Object -Last 6

OUT
Exit code 2
Done! Generated lib/src/asmjit/x86/x86_inst_db.g.dart

warning - tool\dump_abi_code.dart:20:54 - Unnecessary cast. Try removing the cast. - unnecessary_cast
warning - tool\repro_integration_abi_crash.dart:52:45 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - tool\repro_integration_abi_crash.dart:53:34 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion

3 issues found.
PowerShell Run narrow-mem regression tests
IN
dart test test/asmjit/ujit_narrow_mem_test.dart 2>&1 | Select-Object -Last 4

OUT
RAPass: LiveSpans
  Virt65: [6, 10]
  Virt64: [4, 10]
00:00 +15: All tests passed!
PowerShell Run full test suite
IN
dart test 2>&1 | Select-String -Pattern 'Some tests|All tests|failed' | Select-Object -Last 5

OUT
00:04 +805: All tests passed!
PowerShell Run ABI crash repro loop 100 iterations
IN
dart run tool/repro_integration_abi_crash.dart 100 --no-dump 2>&1 | Select-Object -Last 5

OUT
Command running in background with ID: blpttlodu. Output is being written to: C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\tasks\blpttlodu.output. You will be notified when it completes. To check interim output, use Read on that file path.
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\core\rapass.dart
Added 4 lines
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\core\rapass.dart
Modified
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\core\rapass.dart
Added 2 lines
Read c:\MyDartProjects\asmjit\tool\repro_integration_abi_crash.dart (lines 50-57)
Update Todos

Establish baseline: run full test suite and note failures

Diagnose segfault: storeU32 emitted 8-byte store (root cause found)

Fix UniCompiler narrow load/store + add-to-mem (x86 & A64)

Add encoder support: 8/16-bit mov mem, movzx/movsx/movsxd from mem

Fix generator gen_x86_db.dart + regenerate dispatcher (fail-loud default)

Cleanup: debug prints gated, lints, dump tool; update debug_analysis.md

Verify: full suite green + ABI repro loop 100x stable
Edit c:\MyDartProjects\asmjit\tool\repro_integration_abi_crash.dart
Added 1 line
Edit C:\MyDartProjects\asmjit\tool\dump_abi_code.dart
Edit failed
Read C:\MyDartProjects\asmjit\tool\dump_abi_code.dart
Edit C:\MyDartProjects\asmjit\tool\dump_abi_code.dart
Modified
Edit c:\MyDartProjects\asmjit\debug_analysis.md
Added 42 lines
PowerShell Final analyze check
IN
dart analyze 2>&1 | Select-Object -Last 3

OUT
Analyzing asmjit...
No issues found!
Read C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\tasks\blpttlodu.output
Write C:\Users\pmro\.claude\projects\c--MyDartProjects-asmjit\memory\generated-files-fix-generator.md
13 lines
---
name: generated-files-fix-generator
description: Never hand-edit *.g.dart in the asmjit port — fix tool/gen_x86_db.dart and regenerate
metadata:
  type: feedback
---

The user requires that generated files (`lib/src/asmjit/x86/x86_dispatcher.g.dart`, `x86_inst_db.g.dart`) are never edited directly; the generator `tool/gen_x86_db.dart` must be fixed and re-run (`dart run tool/gen_x86_db.dart`).

**Why:** Hand edits are silently lost on the next regeneration. This already happened once: the committed dispatcher had hand-patched `vpslld/vpsrld` cases while the generator still emitted calls to nonexistent assembler methods, so regenerating broke the build until the generator was fixed.

**How to apply:** For any change to dispatch logic, edit the `supported` set, `_dispatchCall`, or `_helpers()` inside `tool/gen_x86_db.dart`, regenerate, then run `dart analyze` — a drifted generator shows up immediately as undefined-method errors. See [[asmjit-port-segfault-rootcause]].
Write C:\Users\pmro\.claude\projects\c--MyDartProjects-asmjit\memory\asmjit-port-segfault-rootcause.md
17 lines
---
name: asmjit-port-segfault-rootcause
description: Root cause of the intermittent 0xC0000374 heap-corruption crash in the Dart asmjit port and the invariants that prevent it
metadata:
  type: project
---

The intermittent `STATUS_HEAP_CORRUPTION` (exit -1073740940 / 0xC0000374) crashes in `dart test` (fixed 2026-07-10) were caused by narrow stores emitting full-width writes: `UniOpMR.storeU32` kept a 64-bit source register, so the x86 assembler emitted `mov qword ptr [mem], r64` and wrote 4 bytes past user heap buffers.

**Why:** In this x86 encoder the *register* operand decides operand size (REX.W), not the memory-operand size annotation. Any emit path that narrows only the `X86Mem.size` still writes/reads the full register width. The C++ reference (`referencias/asmjit-master/asmjit/ujit/unicompiler_x86.cpp`) always resizes the register (`src.r32()` etc.).

**How to apply:**
- When emitting narrow loads/stores, shrink the register (`X86Gp.as8/as16/as32`) — virtual regs keep their id, so RA handles it.
- The generated dispatcher must fail loud: unsupported instructions/operand combos throw `UnsupportedError`. Silent no-op dispatch was hiding dropped instructions (`add [mem], reg`, `movzx` from memory) for months.
- Regression coverage lives in `test/asmjit/ujit_narrow_mem_test.dart` (sentinel-guarded heap buffers, byte-exact checks); the crash repro loop is `tool/repro_integration_abi_crash.dart`.
- RAPass still conservatively saves ALL preserved GP+XMM regs on Win64 (user's mitigation, kept for safety); reverting to precise `clobbered & preserved` is a possible perf follow-up. RA debug prints are gated behind `ASMJIT_RA_DEBUG=1`. See [[generated-files-fix-generator]].
PowerShell Check MEMORY.md index
IN
if (Test-Path C:\Users\pmro\.claude\projects\c--MyDartProjects-asmjit\memory\MEMORY.md) { Get-Content C:\Users\pmro\.claude\projects\c--MyDartProjects-asmjit\memory\MEMORY.md } else { 'ABSENT' }

OUT
ABSENT
Write C:\Users\pmro\.claude\projects\c--MyDartProjects-asmjit\memory\MEMORY.md
5 lines
# Memory Index

- [Generated files: fix the generator](generated-files-fix-generator.md) — never hand-edit *.g.dart; fix tool/gen_x86_db.dart and regenerate
- [Segfault root cause & invariants](asmjit-port-segfault-rootcause.md) — narrow stores must shrink the register; dispatcher fails loud; regression tests in ujit_narrow_mem_test.dart
Enquanto o repro roda, vou varrer o unicompiler.dart por outros fallbacks silenciosos parecidos:

Grep "default:\s*\n\s*break;" (in c:\MyDartProjects\asmjit\lib\src\asmjit\ujit)
17 lines of output
Read C:\Users\pmro\AppData\Local\Temp\claude\c--MyDartProjects-asmjit\57edd249-1cb3-4a08-acc9-6d35e4dbcf00\tasks\blpttlodu.output
Loop de repro: 100/100 sem falhas. Vou checar os dois default: break do unicompiler_x86.dart para ver se são fallbacks perigosos:

Read c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_x86.dart (lines 561-690)
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_x86.dart
Added 4 lines
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_x86.dart
Added 4 lines
PowerShell Analyze and full test suite after fail-loud MV/VM
IN
dart analyze 2>&1 | Select-Object -Last 2; dart test 2>&1 | Select-String -Pattern 'Some tests|All tests|failed' | Select-Object -Last 3

OUT
Analyzing asmjit...
No issues found!

00:04 +805: All tests passed!
Grep "enum UniOpMV" (in c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\uniop.dart)
26 lines of output
Grep "kStore8" (in c:\MyDartProjects\asmjit\referencias\asmjit-master\asmjit\ujit\unicompiler_x86.cpp)
59 lines of output
O C++ implementa store8 via pextrb e store16U16 via pextrw. Vou ver se o assembler Dart os suporta:

Grep "pextrb|pextrw" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86)
21 lines of output
Grep "kPextrb|kPextrw" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart)
1 line of output
Grep "kPinsrb|kPinsrw|kPextrd|kPinsrd" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart)
1 line of output
Grep "void pinsrb|void pinsrw" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart)
4 lines of output
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 4 lines
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 8 lines
Edit c:\MyDartProjects\asmjit\tool\gen_x86_db.dart
Added 46 lines
Agora o _emitMVX86 com store8/store16U16, e preciso ver como o branch AVX do _emitVMX86 trata load8/load16U16:

Read c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_x86.dart (lines 501-570)
Grep "kVpinsrb|kVpinsrw|kPinsrb\b" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_dispatcher.g.dart)
1 line of output
Grep "void vpinsrb|void vpinsrw" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_assembler.dart)
1 line of output
Grep "vpinsr|vpextr" (in c:\MyDartProjects\asmjit\lib\src\asmjit\x86\x86_encoder.dart)
1 line of output
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_x86.dart
Added 3 lines
Edit c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler_x86.dart
Added 10 lines
PowerShell Regenerate dispatcher and analyze
IN
dart run tool/gen_x86_db.dart 2>&1 | Select-Object -Last 2; dart analyze 2>&1 | Select-Object -Last 2

OUT
Done! Generated lib/src/asmjit/x86/x86_inst_db.g.dart
Analyzing asmjit...
No issues found!
Vou verificar as assinaturas públicas de emitVM/emitMV para escrever testes e2e desses caminhos:

Grep "void emitVM|void emitMV" (in c:\MyDartProjects\asmjit\lib\src\asmjit\ujit\unicompiler.dart)
27 lines of output
Edit c:\MyDartProjects\asmjit\test\asmjit\ujit_narrow_mem_test.dart
Added 73 lines
PowerShell Run extended narrow-mem tests
IN
dart test test/asmjit/ujit_narrow_mem_test.dart 2>&1 | Select-Object -Last 6

OUT
Exit code 5
  test\asmjit\ujit_narrow_mem_test.dart 347:12               main.<fn>.roundTrip.<fn>
  test\asmjit\ujit_narrow_mem_test.dart 30:12                _compile
  test\asmjit\ujit_narrow_mem_test.dart 341:18               main.<fn>.roundTrip
  test\asmjit\ujit_narrow_mem_test.dart 385:7                main.<fn>.<fn>
  
00:00 +16 -1: UJIT vector narrow load/store (UniOpVM/UniOpMV) load32U32/store32U32 copies exactly 4 bytes
PowerShell Show load8 test error detail
IN
dart test test/asmjit/ujit_narrow_mem_test.dart --plain-name 'load8' 2>&1 | Select-String -Pattern 'Error|error|Unimplemented|Unsupported' | Select-Object -First 6

OUT
(PowerShell completed with no output)
PowerShell Show failing vector test details
IN
dart test test/asmjit/ujit_narrow_mem_test.dart --reporter expanded 2>&1 | Select-String -Pattern '\[E\]' -Context 0,8 | Select-Object -First 4

OUT
Exit code 5
> 00:00 +16 -1: UJIT vector narrow load/store (UniOpVM/UniOpMV) load16U16/store16U16 copies exactly 2 bytes [E]
    UnimplementedError: UniOpVM UniOpVM.load16U16 not implemented for X86
    package:asmjit/src/asmjit/ujit/unicompiler_x86.dart 514:7  UniCompilerX86._emitVMX86
    package:asmjit/src/asmjit/ujit/unicompiler.dart 1085:7     UniCompiler.emitVM
    test\asmjit\ujit_narrow_mem_test.dart 347:12               main.<fn>.roundTrip.<fn>
    test\asmjit\ujit_narrow_mem_test.dart 30:12                _compile
    test\asmjit\ujit_narrow_mem_test.dart 341:18               main.<fn>.roundTrip
    test\asmjit\ujit_narrow_mem_test.dart 385:7                main.<fn>.<fn>
    
Só load16U16 falta na tabela _getUniOpVMInfo. Vou ver a tabela: