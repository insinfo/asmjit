**********************************************************************
** Visual Studio 2022 Developer Command Prompt v17.11.4
** Copyright (c) 2022 Microsoft Corporation
**********************************************************************
[vcvarsall.bat] Environment initialized for: 'x64'

C:\Program Files\Microsoft Visual Studio\2022\Community>cd C:\MyDartProjects\asmjit\referencias\asmjit-master

C:\MyDartProjects\asmjit\referencias\asmjit-master>cmake -S . -B build -DASMJIT_TEST=ON -DCMAKE_BUILD_TYPE=Release
-- Building for: NMake Makefiles
-- The CXX compiler identification is MSVC 19.41.34120.0
-- Detecting CXX compiler ABI info
-- Detecting CXX compiler ABI info - done
-- Check for working CXX compiler: C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.41.34120/bin/Hostx64/x64/cl.exe - skipped
-- Detecting CXX compile features
-- Detecting CXX compile features - done
-- [asmjit] == Configuring AsmJit ('ASMJIT_TARGET_TYPE=SHARED') ==
-- [asmjit] Adding 'asmjit::asmjit' target ('ASMJIT_TARGET_TYPE=SHARED')
   ASMJIT_PRIVATE_CFLAGS=-W4;-MP;-GF;-Zc:__cplusplus;-Zc:inline;-Zc:strictStrings;-Zc:threadSafeInit-
   ASMJIT_PRIVATE_CFLAGS_DBG=-GS
   ASMJIT_PRIVATE_CFLAGS_REL=-GS-;-O2;-Oi
-- [asmjit] Enabling install support ('ASMJIT_NO_INSTALL=OFF')
-- [asmjit] Enabling AsmJit tests ('ASMJIT_TEST=ON')
-- Performing Test ASMJIT_TARGET_ARCH_X86_64
-- Performing Test ASMJIT_TARGET_ARCH_X86_64 - Success
-- Performing Test __CxxFlag__arch_AVX2
-- Performing Test __CxxFlag__arch_AVX2 - Success
-- [asmjit] == Configuring done ==
-- Configuring done (5.7s)
-- Generating done (0.6s)
-- Build files have been written to: C:/MyDartProjects/asmjit/referencias/asmjit-master/build

C:\MyDartProjects\asmjit\referencias\asmjit-master>cmake --build build --config Release
[  0%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/archtraits.cpp.obj
archtraits.cpp
[  1%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/assembler.cpp.obj
assembler.cpp
[  1%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/builder.cpp.obj
builder.cpp
[  2%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/codeholder.cpp.obj
codeholder.cpp
[  3%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/codewriter.cpp.obj
codewriter.cpp
[  3%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/compiler.cpp.obj
compiler.cpp
[  4%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/constpool.cpp.obj
constpool.cpp
[  5%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/cpuinfo.cpp.obj
cpuinfo.cpp
[  5%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/emithelper.cpp.obj
emithelper.cpp
[  6%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/emitter.cpp.obj
emitter.cpp
[  6%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/emitterutils.cpp.obj
emitterutils.cpp
[  7%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/environment.cpp.obj
environment.cpp
[  8%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/errorhandler.cpp.obj
errorhandler.cpp
[  8%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/formatter.cpp.obj
formatter.cpp
[  9%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/func.cpp.obj
func.cpp
[ 10%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/funcargscontext.cpp.obj
funcargscontext.cpp
[ 10%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/globals.cpp.obj
globals.cpp
[ 11%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/inst.cpp.obj
inst.cpp
[ 12%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/instdb.cpp.obj
instdb.cpp
[ 12%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/jitallocator.cpp.obj
jitallocator.cpp
[ 13%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/jitruntime.cpp.obj
jitruntime.cpp
[ 13%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/logger.cpp.obj
logger.cpp
[ 14%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/operand.cpp.obj
operand.cpp
[ 15%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/osutils.cpp.obj
osutils.cpp
[ 15%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/ralocal.cpp.obj
ralocal.cpp
[ 16%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/rapass.cpp.obj
rapass.cpp
[ 17%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/rastack.cpp.obj
rastack.cpp
[ 17%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/string.cpp.obj
string.cpp
[ 18%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/target.cpp.obj
target.cpp
[ 18%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/type.cpp.obj
type.cpp
[ 19%] Building CXX object CMakeFiles/asmjit.dir/asmjit/core/virtmem.cpp.obj
virtmem.cpp
[ 20%] Building CXX object CMakeFiles/asmjit.dir/asmjit/support/arena.cpp.obj
arena.cpp
[ 20%] Building CXX object CMakeFiles/asmjit.dir/asmjit/support/arenabitset.cpp.obj
arenabitset.cpp
[ 21%] Building CXX object CMakeFiles/asmjit.dir/asmjit/support/arenahash.cpp.obj
arenahash.cpp
[ 22%] Building CXX object CMakeFiles/asmjit.dir/asmjit/support/arenalist.cpp.obj
arenalist.cpp
[ 22%] Building CXX object CMakeFiles/asmjit.dir/asmjit/support/arenatree.cpp.obj
arenatree.cpp
[ 23%] Building CXX object CMakeFiles/asmjit.dir/asmjit/support/arenavector.cpp.obj
arenavector.cpp
[ 24%] Building CXX object CMakeFiles/asmjit.dir/asmjit/support/support.cpp.obj
support.cpp
[ 24%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/armformatter.cpp.obj
armformatter.cpp
[ 25%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64assembler.cpp.obj
a64assembler.cpp
[ 25%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64builder.cpp.obj
a64builder.cpp
[ 26%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64compiler.cpp.obj
a64compiler.cpp
[ 27%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64emithelper.cpp.obj
a64emithelper.cpp
[ 27%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64formatter.cpp.obj
a64formatter.cpp
[ 28%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64func.cpp.obj
a64func.cpp
[ 29%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64instapi.cpp.obj
a64instapi.cpp
[ 29%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64instdb.cpp.obj
a64instdb.cpp
[ 30%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64operand.cpp.obj
a64operand.cpp
[ 31%] Building CXX object CMakeFiles/asmjit.dir/asmjit/arm/a64rapass.cpp.obj
a64rapass.cpp
[ 31%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86assembler.cpp.obj
x86assembler.cpp
[ 32%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86builder.cpp.obj
x86builder.cpp
[ 32%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86compiler.cpp.obj
x86compiler.cpp
[ 33%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86emithelper.cpp.obj
x86emithelper.cpp
[ 34%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86formatter.cpp.obj
x86formatter.cpp
[ 34%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86func.cpp.obj
x86func.cpp
[ 35%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86instdb.cpp.obj
x86instdb.cpp
[ 36%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86instapi.cpp.obj
x86instapi.cpp
[ 36%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86operand.cpp.obj
x86operand.cpp
[ 37%] Building CXX object CMakeFiles/asmjit.dir/asmjit/x86/x86rapass.cpp.obj
x86rapass.cpp
[ 37%] Building CXX object CMakeFiles/asmjit.dir/asmjit/ujit/unicompiler_a64.cpp.obj
unicompiler_a64.cpp
[ 38%] Building CXX object CMakeFiles/asmjit.dir/asmjit/ujit/unicompiler_x86.cpp.obj
unicompiler_x86.cpp
[ 39%] Building CXX object CMakeFiles/asmjit.dir/asmjit/ujit/vecconsttable.cpp.obj
vecconsttable.cpp
[ 39%] Linking CXX shared library asmjit.dll
[ 39%] Built target asmjit
[ 40%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/archtraits.cpp.obj
archtraits.cpp
[ 40%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/assembler.cpp.obj
assembler.cpp
[ 41%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/builder.cpp.obj
builder.cpp
[ 41%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/codeholder.cpp.obj
codeholder.cpp
[ 42%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/codewriter.cpp.obj
codewriter.cpp
[ 43%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/compiler.cpp.obj
compiler.cpp
[ 43%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/constpool.cpp.obj
constpool.cpp
[ 44%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/cpuinfo.cpp.obj
cpuinfo.cpp
[ 45%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/emithelper.cpp.obj
emithelper.cpp
[ 45%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/emitter.cpp.obj
emitter.cpp
[ 46%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/emitterutils.cpp.obj
emitterutils.cpp
[ 47%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/environment.cpp.obj
environment.cpp
[ 47%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/errorhandler.cpp.obj
errorhandler.cpp
[ 48%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/formatter.cpp.obj
formatter.cpp
[ 48%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/func.cpp.obj
func.cpp
[ 49%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/funcargscontext.cpp.obj
funcargscontext.cpp
[ 50%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/globals.cpp.obj
globals.cpp
[ 50%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/inst.cpp.obj
inst.cpp
[ 51%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/instdb.cpp.obj
instdb.cpp
[ 52%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/jitallocator.cpp.obj
jitallocator.cpp
[ 52%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/jitruntime.cpp.obj
jitruntime.cpp
[ 53%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/logger.cpp.obj
logger.cpp
[ 53%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/operand.cpp.obj
operand.cpp
[ 54%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/osutils.cpp.obj
osutils.cpp
[ 55%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/ralocal.cpp.obj
ralocal.cpp
[ 55%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/rapass.cpp.obj
rapass.cpp
[ 56%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/rastack.cpp.obj
rastack.cpp
[ 57%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/string.cpp.obj
string.cpp
[ 57%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/target.cpp.obj
target.cpp
[ 58%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/type.cpp.obj
type.cpp
[ 59%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/core/virtmem.cpp.obj
virtmem.cpp
[ 59%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/support/arena.cpp.obj
arena.cpp
[ 60%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/support/arenabitset.cpp.obj
arenabitset.cpp
[ 60%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/support/arenahash.cpp.obj
arenahash.cpp
[ 61%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/support/arenalist.cpp.obj
arenalist.cpp
[ 62%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/support/arenatree.cpp.obj
arenatree.cpp
[ 62%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/support/arenavector.cpp.obj
arenavector.cpp
[ 63%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/support/support.cpp.obj
support.cpp
[ 64%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/armformatter.cpp.obj
armformatter.cpp
[ 64%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64assembler.cpp.obj
a64assembler.cpp
[ 65%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64builder.cpp.obj
a64builder.cpp
[ 66%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64compiler.cpp.obj
a64compiler.cpp
[ 66%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64emithelper.cpp.obj
a64emithelper.cpp
[ 67%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64formatter.cpp.obj
a64formatter.cpp
[ 67%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64func.cpp.obj
a64func.cpp
[ 68%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64instapi.cpp.obj
a64instapi.cpp
[ 69%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64instdb.cpp.obj
a64instdb.cpp
[ 69%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64operand.cpp.obj
a64operand.cpp
[ 70%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/arm/a64rapass.cpp.obj
a64rapass.cpp
[ 71%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86assembler.cpp.obj
x86assembler.cpp
[ 71%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86builder.cpp.obj
x86builder.cpp
[ 72%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86compiler.cpp.obj
x86compiler.cpp
[ 72%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86emithelper.cpp.obj
x86emithelper.cpp
[ 73%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86formatter.cpp.obj
x86formatter.cpp
[ 74%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86func.cpp.obj
x86func.cpp
[ 74%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86instdb.cpp.obj
x86instdb.cpp
[ 75%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86instapi.cpp.obj
x86instapi.cpp
[ 76%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86operand.cpp.obj
x86operand.cpp
[ 76%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/x86/x86rapass.cpp.obj
x86rapass.cpp
[ 77%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/ujit/unicompiler_a64.cpp.obj
unicompiler_a64.cpp
[ 78%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/ujit/unicompiler_x86.cpp.obj
unicompiler_x86.cpp
[ 78%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit/ujit/vecconsttable.cpp.obj
vecconsttable.cpp
[ 79%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit-testing/tests/asmjit_test_runner.cpp.obj
asmjit_test_runner.cpp
[ 79%] Building CXX object CMakeFiles/asmjit_test_runner.dir/asmjit-testing/tests/broken.cpp.obj
broken.cpp
[ 80%] Linking CXX executable asmjit_test_runner.exe
[ 80%] Built target asmjit_test_runner
[ 81%] Building CXX object CMakeFiles/asmjit_test_assembler.dir/asmjit-testing/tests/asmjit_test_assembler.cpp.obj
asmjit_test_assembler.cpp
[ 82%] Building CXX object CMakeFiles/asmjit_test_assembler.dir/asmjit-testing/tests/asmjit_test_assembler_a64.cpp.obj
asmjit_test_assembler_a64.cpp
[ 82%] Building CXX object CMakeFiles/asmjit_test_assembler.dir/asmjit-testing/tests/asmjit_test_assembler_x64.cpp.obj
asmjit_test_assembler_x64.cpp
[ 83%] Building CXX object CMakeFiles/asmjit_test_assembler.dir/asmjit-testing/tests/asmjit_test_assembler_x86.cpp.obj
asmjit_test_assembler_x86.cpp
[ 84%] Linking CXX executable asmjit_test_assembler.exe
[ 84%] Built target asmjit_test_assembler
[ 85%] Building CXX object CMakeFiles/asmjit_test_environment.dir/asmjit-testing/tests/asmjit_test_environment.cpp.obj
asmjit_test_environment.cpp
[ 86%] Linking CXX executable asmjit_test_environment.exe
[ 86%] Built target asmjit_test_environment
[ 87%] Building CXX object CMakeFiles/asmjit_test_emitters.dir/asmjit-testing/tests/asmjit_test_emitters.cpp.obj
asmjit_test_emitters.cpp
[ 87%] Linking CXX executable asmjit_test_emitters.exe
[ 87%] Built target asmjit_test_emitters
[ 88%] Building CXX object CMakeFiles/asmjit_test_x86_sections.dir/asmjit-testing/tests/asmjit_test_x86_sections.cpp.objasmjit_test_x86_sections.cpp
[ 89%] Linking CXX executable asmjit_test_x86_sections.exe
[ 89%] Built target asmjit_test_x86_sections
[ 89%] Building CXX object CMakeFiles/asmjit_test_instinfo.dir/asmjit-testing/tests/asmjit_test_instinfo.cpp.obj
asmjit_test_instinfo.cpp
[ 90%] Linking CXX executable asmjit_test_instinfo.exe
[ 90%] Built target asmjit_test_instinfo
[ 90%] Building CXX object CMakeFiles/asmjit_test_compiler.dir/asmjit-testing/tests/asmjit_test_compiler.cpp.obj
asmjit_test_compiler.cpp
[ 91%] Building CXX object CMakeFiles/asmjit_test_compiler.dir/asmjit-testing/tests/asmjit_test_compiler_a64.cpp.obj
asmjit_test_compiler_a64.cpp
[ 92%] Building CXX object CMakeFiles/asmjit_test_compiler.dir/asmjit-testing/tests/asmjit_test_compiler_x86.cpp.obj
asmjit_test_compiler_x86.cpp
[ 92%] Linking CXX executable asmjit_test_compiler.exe
[ 92%] Built target asmjit_test_compiler
[ 93%] Building CXX object CMakeFiles/asmjit_test_unicompiler.dir/asmjit-testing/tests/asmjit_test_unicompiler.cpp.obj
asmjit_test_unicompiler.cpp
[ 93%] Building CXX object CMakeFiles/asmjit_test_unicompiler.dir/asmjit-testing/tests/asmjit_test_unicompiler_sse2.cpp.obj
asmjit_test_unicompiler_sse2.cpp
[ 94%] Building CXX object CMakeFiles/asmjit_test_unicompiler.dir/asmjit-testing/tests/asmjit_test_unicompiler_avx2fma.cpp.obj
asmjit_test_unicompiler_avx2fma.cpp
[ 95%] Building CXX object CMakeFiles/asmjit_test_unicompiler.dir/asmjit-testing/tests/broken.cpp.obj
broken.cpp
[ 95%] Linking CXX executable asmjit_test_unicompiler.exe
[ 95%] Built target asmjit_test_unicompiler
[ 96%] Building CXX object CMakeFiles/asmjit_bench_codegen.dir/asmjit-testing/bench/asmjit_bench_codegen.cpp.obj
asmjit_bench_codegen.cpp
[ 97%] Building CXX object CMakeFiles/asmjit_bench_codegen.dir/asmjit-testing/bench/asmjit_bench_codegen_a64.cpp.obj
asmjit_bench_codegen_a64.cpp
[ 97%] Building CXX object CMakeFiles/asmjit_bench_codegen.dir/asmjit-testing/bench/asmjit_bench_codegen_x86.cpp.obj
asmjit_bench_codegen_x86.cpp
[ 98%] Linking CXX executable asmjit_bench_codegen.exe
[ 98%] Built target asmjit_bench_codegen
[ 99%] Building CXX object CMakeFiles/asmjit_bench_overhead.dir/asmjit-testing/bench/asmjit_bench_overhead.cpp.obj
asmjit_bench_overhead.cpp
[ 99%] Linking CXX executable asmjit_bench_overhead.exe
[ 99%] Built target asmjit_bench_overhead
[100%] Building CXX object CMakeFiles/asmjit_bench_regalloc.dir/asmjit-testing/bench/asmjit_bench_regalloc.cpp.obj
asmjit_bench_regalloc.cpp
[100%] Linking CXX executable asmjit_bench_regalloc.exe
[100%] Built target asmjit_bench_regalloc

C:\MyDartProjects\asmjit\referencias\asmjit-master>ls
CMakeLists.txt     CONTRIBUTING.md  README.md  asmjit-testing  configure.sh             configure_vs2022_x64.bat  db
CMakePresets.json  LICENSE.md       asmjit     build           configure_sanitizers.sh  configure_vs2022_x86.bat  tools

C:\MyDartProjects\asmjit\referencias\asmjit-master>cd build

C:\MyDartProjects\asmjit\referencias\asmjit-master\build>ls
CMakeCache.txt       asmjit.exp                 asmjit_test_assembler.exe    asmjit_test_runner.exe
CMakeFiles           asmjit.lib                 asmjit_test_compiler.exe     asmjit_test_unicompiler.exe
CTestTestfile.cmake  asmjit_bench_codegen.exe   asmjit_test_emitters.exe     asmjit_test_x86_sections.exe
Makefile             asmjit_bench_overhead.exe  asmjit_test_environment.exe  cmake_install.cmake
asmjit.dll           asmjit_bench_regalloc.exe  asmjit_test_instinfo.exe

C:\MyDartProjects\asmjit\referencias\asmjit-master\build>.\asmjit_bench_codegen.exe
AsmJit Benchmark CodeGen v1.21.0 [Arch=X64] [Mode=Release]

Usage:
  --help         Show usage only
  --quick        Decrease the number of iterations to make tests quicker
  --arch=<ARCH>  Select architecture(s) to run ('all' by default)

Architectures:
  --arch=x86     32-bit X86 architecture (X86)
  --arch=x64     64-bit X86 architecture (X86_64)
  --arch=aarch64 64-bit ARM architecture (AArch64)

Empty function (mov + return from function):
  [X86    ] Assembler [raw]            | CodeSize:    6 [B] | Time:  0.100 [us] | Speed:   57.2 [MiB/s],     20.0 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize:    6 [B] | Time:  0.200 [us] | Speed:   28.6 [MiB/s],     10.0 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize:    6 [B] | Time:  0.200 [us] | Speed:   28.6 [MiB/s],     10.0 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.100 [us] | Speed:    N/A        ,     20.0 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize:    6 [B] | Time:  0.200 [us] | Speed:   28.6 [MiB/s],     10.0 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize:    6 [B] | Time:  0.400 [us] | Speed:   14.3 [MiB/s],      5.0 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  0.400 [us] | Speed:    N/A        ,      5.0 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize:    6 [B] | Time:  2.900 [us] | Speed:    2.0 [MiB/s],      0.7 [MInst/s]

Empty function (mov + return from function):
  [X64    ] Assembler [raw]            | CodeSize:    6 [B] | Time:  0.100 [us] | Speed:   57.2 [MiB/s],     20.0 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize:    6 [B] | Time:  0.200 [us] | Speed:   28.6 [MiB/s],     10.0 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize:    6 [B] | Time:  0.200 [us] | Speed:   28.6 [MiB/s],     10.0 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.100 [us] | Speed:    N/A        ,     20.0 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize:    6 [B] | Time:  0.200 [us] | Speed:   28.6 [MiB/s],     10.0 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize:    6 [B] | Time:  0.400 [us] | Speed:   14.3 [MiB/s],      5.0 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  0.400 [us] | Speed:    N/A        ,      5.0 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize:    6 [B] | Time:  3.000 [us] | Speed:    1.9 [MiB/s],      0.7 [MInst/s]

4-Ops sequence (4 ops + return from function):
  [X86    ] Assembler [raw]            | CodeSize:   11 [B] | Time:  0.200 [us] | Speed:   52.5 [MiB/s],     25.0 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize:   11 [B] | Time:  0.400 [us] | Speed:   26.2 [MiB/s],     12.5 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize:   13 [B] | Time:  0.400 [us] | Speed:   31.0 [MiB/s],     12.5 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.200 [us] | Speed:    N/A        ,     25.0 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize:   11 [B] | Time:  0.400 [us] | Speed:   26.2 [MiB/s],     12.5 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize:   13 [B] | Time:  0.700 [us] | Speed:   17.7 [MiB/s],      7.1 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  0.600 [us] | Speed:    N/A        ,      8.3 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize:   29 [B] | Time:  5.300 [us] | Speed:    5.2 [MiB/s],      0.9 [MInst/s]

4-Ops sequence (4 ops + return from function):
  [X64    ] Assembler [raw]            | CodeSize:   11 [B] | Time:  0.200 [us] | Speed:   52.5 [MiB/s],     25.0 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize:   11 [B] | Time:  0.500 [us] | Speed:   21.0 [MiB/s],     10.0 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize:   13 [B] | Time:  0.400 [us] | Speed:   31.0 [MiB/s],     12.5 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.200 [us] | Speed:    N/A        ,     25.0 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize:   11 [B] | Time:  0.400 [us] | Speed:   26.2 [MiB/s],     12.5 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize:   13 [B] | Time:  0.700 [us] | Speed:   17.7 [MiB/s],      7.1 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  0.600 [us] | Speed:    N/A        ,      8.3 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize:   13 [B] | Time:  4.900 [us] | Speed:    2.5 [MiB/s],      1.0 [MInst/s]

16-Ops sequence (16 ops + return from function):
  [X86    ] Assembler [raw]            | CodeSize:   41 [B] | Time:  0.500 [us] | Speed:   78.2 [MiB/s],     34.0 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize:   41 [B] | Time:  1.500 [us] | Speed:   26.1 [MiB/s],     11.3 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize:   43 [B] | Time:  0.700 [us] | Speed:   58.6 [MiB/s],     24.3 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.500 [us] | Speed:    N/A        ,     34.0 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize:   41 [B] | Time:  1.100 [us] | Speed:   35.5 [MiB/s],     15.5 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize:   43 [B] | Time:  1.400 [us] | Speed:   29.3 [MiB/s],     12.1 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  0.900 [us] | Speed:    N/A        ,     18.9 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize:   59 [B] | Time:  8.300 [us] | Speed:    6.8 [MiB/s],      2.0 [MInst/s]

16-Ops sequence (16 ops + return from function):
  [X64    ] Assembler [raw]            | CodeSize:   41 [B] | Time:  0.500 [us] | Speed:   78.2 [MiB/s],     34.0 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize:   41 [B] | Time:  1.500 [us] | Speed:   26.1 [MiB/s],     11.3 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize:   43 [B] | Time:  0.700 [us] | Speed:   58.6 [MiB/s],     24.3 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.500 [us] | Speed:    N/A        ,     34.0 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize:   41 [B] | Time:  1.100 [us] | Speed:   35.5 [MiB/s],     15.5 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize:   43 [B] | Time:  1.400 [us] | Speed:   29.3 [MiB/s],     12.1 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  0.900 [us] | Speed:    N/A        ,     18.9 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize:   43 [B] | Time:  8.100 [us] | Speed:    5.1 [MiB/s],      2.1 [MInst/s]

32-Ops sequence (32 ops + return from function):
  [X86    ] Assembler [raw]            | CodeSize:   81 [B] | Time:  0.900 [us] | Speed:   85.8 [MiB/s],     36.7 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize:   81 [B] | Time:  2.800 [us] | Speed:   27.6 [MiB/s],     11.8 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize:   83 [B] | Time:  1.100 [us] | Speed:   72.0 [MiB/s],     30.0 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.800 [us] | Speed:    N/A        ,     41.3 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize:   81 [B] | Time:  1.900 [us] | Speed:   40.7 [MiB/s],     17.4 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize:   83 [B] | Time:  2.300 [us] | Speed:   34.4 [MiB/s],     14.3 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  1.300 [us] | Speed:    N/A        ,     25.4 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize:   99 [B] | Time: 12.500 [us] | Speed:    7.6 [MiB/s],      2.6 [MInst/s]

32-Ops sequence (32 ops + return from function):
  [X64    ] Assembler [raw]            | CodeSize:   81 [B] | Time:  0.900 [us] | Speed:   85.8 [MiB/s],     36.7 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize:   81 [B] | Time:  2.800 [us] | Speed:   27.6 [MiB/s],     11.8 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize:   83 [B] | Time:  1.100 [us] | Speed:   72.0 [MiB/s],     30.0 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  0.800 [us] | Speed:    N/A        ,     41.3 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize:   81 [B] | Time:  1.900 [us] | Speed:   40.7 [MiB/s],     17.4 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize:   83 [B] | Time:  2.300 [us] | Speed:   34.4 [MiB/s],     14.3 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  1.300 [us] | Speed:    N/A        ,     25.4 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize:   83 [B] | Time: 12.300 [us] | Speed:    6.4 [MiB/s],      2.7 [MInst/s]

64-Ops sequence (64 ops + return from function):
  [X86    ] Assembler [raw]            | CodeSize:  161 [B] | Time:  1.700 [us] | Speed:   90.3 [MiB/s],     38.2 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize:  161 [B] | Time:  5.500 [us] | Speed:   27.9 [MiB/s],     11.8 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize:  163 [B] | Time:  1.900 [us] | Speed:   81.8 [MiB/s],     34.2 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  1.600 [us] | Speed:    N/A        ,     40.6 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize:  161 [B] | Time:  3.700 [us] | Speed:   41.5 [MiB/s],     17.6 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize:  163 [B] | Time:  4.000 [us] | Speed:   38.9 [MiB/s],     16.2 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  2.000 [us] | Speed:    N/A        ,     32.5 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize:  179 [B] | Time: 20.500 [us] | Speed:    8.3 [MiB/s],      3.2 [MInst/s]

64-Ops sequence (64 ops + return from function):
  [X64    ] Assembler [raw]            | CodeSize:  161 [B] | Time:  1.600 [us] | Speed:   96.0 [MiB/s],     40.6 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize:  161 [B] | Time:  5.600 [us] | Speed:   27.4 [MiB/s],     11.6 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize:  163 [B] | Time:  1.900 [us] | Speed:   81.8 [MiB/s],     34.2 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  1.600 [us] | Speed:    N/A        ,     40.6 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize:  161 [B] | Time:  3.700 [us] | Speed:   41.5 [MiB/s],     17.6 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize:  163 [B] | Time:  4.000 [us] | Speed:   38.9 [MiB/s],     16.2 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  2.000 [us] | Speed:    N/A        ,     32.5 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize:  163 [B] | Time: 20.300 [us] | Speed:    7.7 [MiB/s],      3.2 [MInst/s]

GpSequence<Reg> (Sequence of GP instructions - reg-only):
  [X86    ] Assembler [raw]            | CodeSize:  499 [B] | Time:  4.600 [us] | Speed:  103.5 [MiB/s],     33.5 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize:  499 [B] | Time: 11.300 [us] | Speed:   42.1 [MiB/s],     13.6 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize:  502 [B] | Time:  4.800 [us] | Speed:   99.7 [MiB/s],     32.1 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  3.900 [us] | Speed:    N/A        ,     39.5 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize:  499 [B] | Time:  7.700 [us] | Speed:   61.8 [MiB/s],     20.0 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize:  502 [B] | Time:  8.000 [us] | Speed:   59.8 [MiB/s],     19.2 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  4.300 [us] | Speed:    N/A        ,     35.8 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize:  501 [B] | Time: 45.500 [us] | Speed:   10.5 [MiB/s],      3.4 [MInst/s]

GpSequence<Reg> (Sequence of GP instructions - reg-only):
  [X64    ] Assembler [raw]            | CodeSize:  636 [B] | Time:  4.700 [us] | Speed:  129.1 [MiB/s],     32.8 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize:  636 [B] | Time: 11.900 [us] | Speed:   51.0 [MiB/s],     12.9 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize:  639 [B] | Time:  4.900 [us] | Speed:  124.4 [MiB/s],     31.4 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  3.900 [us] | Speed:    N/A        ,     39.5 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize:  636 [B] | Time:  7.700 [us] | Speed:   78.8 [MiB/s],     20.0 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize:  639 [B] | Time:  8.100 [us] | Speed:   75.2 [MiB/s],     19.0 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  4.300 [us] | Speed:    N/A        ,     35.8 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize:  636 [B] | Time: 45.200 [us] | Speed:   13.4 [MiB/s],      3.4 [MInst/s]

GpSequence<Mem> (Sequence of GP instructions - reg/mem):
  [X86    ] Assembler [raw]            | CodeSize:  448 [B] | Time:  4.400 [us] | Speed:   97.1 [MiB/s],     29.1 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize:  448 [B] | Time: 12.000 [us] | Speed:   35.6 [MiB/s],     10.7 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize:  451 [B] | Time:  4.700 [us] | Speed:   91.5 [MiB/s],     27.2 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  3.200 [us] | Speed:    N/A        ,     40.0 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize:  448 [B] | Time:  7.000 [us] | Speed:   61.0 [MiB/s],     18.3 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize:  451 [B] | Time:  7.400 [us] | Speed:   58.1 [MiB/s],     17.3 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  3.600 [us] | Speed:    N/A        ,     35.6 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize:  451 [B] | Time: 39.000 [us] | Speed:   11.0 [MiB/s],      3.3 [MInst/s]

GpSequence<Mem> (Sequence of GP instructions - reg/mem):
  [X64    ] Assembler [raw]            | CodeSize:  556 [B] | Time:  4.400 [us] | Speed:  120.5 [MiB/s],     29.1 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize:  556 [B] | Time: 12.700 [us] | Speed:   41.8 [MiB/s],     10.1 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize:  559 [B] | Time:  4.800 [us] | Speed:  111.1 [MiB/s],     26.7 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  3.200 [us] | Speed:    N/A        ,     40.0 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize:  556 [B] | Time:  7.000 [us] | Speed:   75.7 [MiB/s],     18.3 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize:  559 [B] | Time:  7.400 [us] | Speed:   72.0 [MiB/s],     17.3 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  3.700 [us] | Speed:    N/A        ,     34.6 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize:  557 [B] | Time: 38.800 [us] | Speed:   13.7 [MiB/s],      3.3 [MInst/s]

SseSequence<Reg> (sequence of SSE+ instructions - reg-only):
  [X86    ] Assembler [raw]            | CodeSize: 1017 [B] | Time:  6.800 [us] | Speed:  142.6 [MiB/s],     35.0 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize: 1017 [B] | Time: 16.900 [us] | Speed:   57.4 [MiB/s],     14.1 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize: 1018 [B] | Time:  7.000 [us] | Speed:  138.7 [MiB/s],     34.0 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  6.300 [us] | Speed:    N/A        ,     37.8 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize: 1017 [B] | Time: 12.000 [us] | Speed:   80.8 [MiB/s],     19.8 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize: 1018 [B] | Time: 12.300 [us] | Speed:   78.9 [MiB/s],     19.3 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  7.000 [us] | Speed:    N/A        ,     34.0 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize: 1018 [B] | Time: 67.200 [us] | Speed:   14.4 [MiB/s],      3.5 [MInst/s]

SseSequence<Reg> (sequence of SSE+ instructions - reg-only):
  [X64    ] Assembler [raw]            | CodeSize: 1031 [B] | Time:  6.800 [us] | Speed:  144.6 [MiB/s],     35.1 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize: 1031 [B] | Time: 17.100 [us] | Speed:   57.5 [MiB/s],     14.0 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize: 1032 [B] | Time:  7.000 [us] | Speed:  140.6 [MiB/s],     34.1 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  6.300 [us] | Speed:    N/A        ,     37.9 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize: 1031 [B] | Time: 12.000 [us] | Speed:   81.9 [MiB/s],     19.9 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize: 1032 [B] | Time: 12.300 [us] | Speed:   80.0 [MiB/s],     19.4 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  7.000 [us] | Speed:    N/A        ,     34.1 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize: 1032 [B] | Time: 67.500 [us] | Speed:   14.6 [MiB/s],      3.5 [MInst/s]

SseSequence<Mem> (sequence of SSE+ instructions - reg/mem):
  [X86    ] Assembler [raw]            | CodeSize: 1049 [B] | Time:  8.100 [us] | Speed:  123.5 [MiB/s],     30.7 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize: 1049 [B] | Time: 20.700 [us] | Speed:   48.3 [MiB/s],     12.0 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize: 1050 [B] | Time:  8.300 [us] | Speed:  120.6 [MiB/s],     30.0 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  6.600 [us] | Speed:    N/A        ,     37.7 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize: 1049 [B] | Time: 13.500 [us] | Speed:   74.1 [MiB/s],     18.4 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize: 1050 [B] | Time: 13.800 [us] | Speed:   72.6 [MiB/s],     18.0 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  7.400 [us] | Speed:    N/A        ,     33.6 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize: 1050 [B] | Time: 71.700 [us] | Speed:   14.0 [MiB/s],      3.5 [MInst/s]

SseSequence<Mem> (sequence of SSE+ instructions - reg/mem):
  [X64    ] Assembler [raw]            | CodeSize: 1061 [B] | Time:  8.100 [us] | Speed:  124.9 [MiB/s],     30.9 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize: 1061 [B] | Time: 21.000 [us] | Speed:   48.2 [MiB/s],     11.9 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize: 1062 [B] | Time:  8.300 [us] | Speed:  122.0 [MiB/s],     30.1 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time:  6.600 [us] | Speed:    N/A        ,     37.9 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize: 1061 [B] | Time: 13.600 [us] | Speed:   74.4 [MiB/s],     18.4 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize: 1062 [B] | Time: 13.900 [us] | Speed:   72.9 [MiB/s],     18.0 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time:  7.400 [us] | Speed:    N/A        ,     33.8 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize: 1062 [B] | Time: 72.000 [us] | Speed:   14.1 [MiB/s],      3.5 [MInst/s]

AvxSequence<Reg> (sequence of AVX+ instructions - reg-only):
  [X86    ] Assembler [raw]            | CodeSize: 2589 [B] | Time: 17.700 [us] | Speed:  139.5 [MiB/s],     31.8 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize: 2589 [B] | Time: 45.200 [us] | Speed:   54.6 [MiB/s],     12.4 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize: 2590 [B] | Time: 18.200 [us] | Speed:  135.7 [MiB/s],     30.9 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time: 14.500 [us] | Speed:    N/A        ,     38.8 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize: 2589 [B] | Time: 28.800 [us] | Speed:   85.7 [MiB/s],     19.5 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize: 2590 [B] | Time: 29.500 [us] | Speed:   83.7 [MiB/s],     19.1 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time: 15.200 [us] | Speed:    N/A        ,     37.0 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize: 2590 [B] | Time:183.200 [us] | Speed:   13.5 [MiB/s],      3.1 [MInst/s]

AvxSequence<Reg> (sequence of AVX+ instructions - reg-only):
  [X64    ] Assembler [raw]            | CodeSize: 2599 [B] | Time: 17.800 [us] | Speed:  139.2 [MiB/s],     31.6 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize: 2599 [B] | Time: 45.700 [us] | Speed:   54.2 [MiB/s],     12.3 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize: 2600 [B] | Time: 18.200 [us] | Speed:  136.2 [MiB/s],     30.9 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time: 14.500 [us] | Speed:    N/A        ,     38.8 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize: 2599 [B] | Time: 28.800 [us] | Speed:   86.1 [MiB/s],     19.5 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize: 2600 [B] | Time: 29.500 [us] | Speed:   84.1 [MiB/s],     19.1 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time: 15.200 [us] | Speed:    N/A        ,     37.0 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize: 2600 [B] | Time:183.700 [us] | Speed:   13.5 [MiB/s],      3.1 [MInst/s]

AvxSequence<Mem> (sequence of AVX+ instructions - reg/mem):
  [X86    ] Assembler [raw]            | CodeSize: 2278 [B] | Time: 18.700 [us] | Speed:  116.2 [MiB/s],     26.7 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize: 2278 [B] | Time: 47.100 [us] | Speed:   46.1 [MiB/s],     10.6 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize: 2279 [B] | Time: 19.300 [us] | Speed:  112.6 [MiB/s],     25.9 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time: 12.700 [us] | Speed:    N/A        ,     39.4 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize: 2278 [B] | Time: 28.800 [us] | Speed:   75.4 [MiB/s],     17.4 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize: 2279 [B] | Time: 29.400 [us] | Speed:   73.9 [MiB/s],     17.0 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time: 13.700 [us] | Speed:    N/A        ,     36.5 [MInst/s]
  [X86    ] Compiler  [finalized]      | CodeSize: 2279 [B] | Time:166.200 [us] | Speed:   13.1 [MiB/s],      3.0 [MInst/s]

AvxSequence<Mem> (sequence of AVX+ instructions - reg/mem):
  [X64    ] Assembler [raw]            | CodeSize: 2284 [B] | Time: 18.700 [us] | Speed:  116.5 [MiB/s],     26.8 [MInst/s]
  [X64    ] Assembler [validated]      | CodeSize: 2284 [B] | Time: 47.400 [us] | Speed:   46.0 [MiB/s],     10.6 [MInst/s]
  [X64    ] Assembler [prolog/epilog]  | CodeSize: 2285 [B] | Time: 19.300 [us] | Speed:  112.9 [MiB/s],     26.0 [MInst/s]
  [X64    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time: 12.800 [us] | Speed:    N/A        ,     39.1 [MInst/s]
  [X64    ] Builder   [finalized]      | CodeSize: 2284 [B] | Time: 28.900 [us] | Speed:   75.4 [MiB/s],     17.3 [MInst/s]
  [X64    ] Builder   [prolog/epilog]  | CodeSize: 2285 [B] | Time: 29.500 [us] | Speed:   73.9 [MiB/s],     17.0 [MInst/s]
  [X64    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time: 13.700 [us] | Speed:    N/A        ,     36.6 [MInst/s]
  [X64    ] Compiler  [finalized]      | CodeSize: 2285 [B] | Time:166.300 [us] | Speed:   13.1 [MiB/s],      3.0 [MInst/s]

Avx512Sequence<Reg> (sequence of AVX512+ instructions - reg-only):
  [X86    ] Assembler [raw]            | CodeSize: 7933 [B] | Time: 51.600 [us] | Speed:  146.6 [MiB/s],     25.3 [MInst/s]
  [X86    ] Assembler [validated]      | CodeSize: 7933 [B] | Time:118.900 [us] | Speed:   63.6 [MiB/s],     11.0 [MInst/s]
  [X86    ] Assembler [prolog/epilog]  | CodeSize: 7934 [B] | Time: 52.000 [us] | Speed:  145.5 [MiB/s],     25.1 [MInst/s]
  [X86    ] Builder   [no-asm]         | CodeSize:    0 [B] | Time: 46.100 [us] | Speed:    N/A        ,     28.3 [MInst/s]
  [X86    ] Builder   [finalized]      | CodeSize: 7933 [B] | Time: 76.200 [us] | Speed:   99.3 [MiB/s],     17.1 [MInst/s]
  [X86    ] Builder   [prolog/epilog]  | CodeSize: 7934 [B] | Time: 77.100 [us] | Speed:   98.1 [MiB/s],     16.9 [MInst/s]
  [X86    ] Compiler  [no-asm]         | CodeSize:    0 [B] | Time: 47.800 [us] | Speed:    N/A        ,     27.3 [MInst/s]
^C
C:\MyDartProjects\asmjit\referencias\asmjit-master\build>.\asmjit_bench_overhead.exe
AsmJit Benchmark Overhead v1.21.0 [Arch=X64] [Mode=Release]

This benchmark was designed to benchmark the cost of initialization and
reset (or reinitialization) of CodeHolder and Emitters; and the cost of
moving a minimal assembled function to executable memory. Each output line
uses "<Test> [Func] [Finalize] [RT]" format, with the following meaning:

  - <Test>     - test case name - either 'CodeHolder' only or an emitter
  - [Func]     - function was assembled
  - [Finalize] - function was finalized (Builder/Compiler)
  - [RT]       - function was added to JitRuntime and then removed from it

Essentially the output provides an insight into the cost of reusing
CodeHolder and other emitters, and the cost of assembling, finalizing,
and moving the assembled code into executable memory by separating each
phase.

The number of iterations benchmarked: 1000000 (override by --count=n)

CodeHolder (Only)               [init/reset]:   53.587 [ms]
Assembler                       [init/reset]:   97.383 [ms]
Assembler + Func                [init/reset]:  140.434 [ms]
Assembler + Func + RT           [init/reset]:  283.919 [ms]
Builder                         [init/reset]:  137.166 [ms]
Builder + Func                  [init/reset]:  185.350 [ms]
Builder + Func + Finalize       [init/reset]:  310.220 [ms]
Builder + Func + Finalize + RT  [init/reset]:  472.503 [ms]
Compiler                        [init/reset]:  209.754 [ms]
Compiler + Func                 [init/reset]:  471.303 [ms]
Compiler + Func + Finalize      [init/reset]: 3485.844 [ms]
Compiler + Func + Finalize + RT [init/reset]: 3975.991 [ms]

CodeHolder (Only)               [reinit    ]:   44.334 [ms]
Assembler                       [reinit    ]:   47.383 [ms]
Assembler + Func                [reinit    ]:   97.404 [ms]
Assembler + Func + RT           [reinit    ]:  244.204 [ms]
Builder                         [reinit    ]:   99.221 [ms]
Builder + Func                  [reinit    ]:  142.715 [ms]
Builder + Func + Finalize       [reinit    ]:  281.077 [ms]
Builder + Func + Finalize + RT  [reinit    ]:  429.784 [ms]
Compiler                        [reinit    ]:  179.487 [ms]
Compiler + Func                 [reinit    ]:  453.921 [ms]
Compiler + Func + Finalize      [reinit    ]: 3421.473 [ms]
Compiler + Func + Finalize + RT [reinit    ]: 3869.109 [ms]

C:\MyDartProjects\asmjit\referencias\asmjit-master\build>.\asmjit_bench_regalloc.exe
AsmJit Benchmark RegAlloc v1.21.0 [Arch=X64] [Mode=Release]

Usage:
  asmjit_bench_regalloc [arguments]

Arguments:
  --help           Show usage only
  --arch=<NAME>    Select architecture to run ('all' by default)
  --verbose        Verbose output
  --complexity=<n> Maximum complexity to test (65536)

Architectures:
  --arch=x86       32-bit X86 architecture (X86)
  --arch=x64       64-bit X86 architecture (X86_64)
  --arch=aarch64   64-bit ARM architecture (AArch64)

+-----------------------------------------+-----------+-----------------------------------+--------------+--------------+
|           Input Configuration           |   Output  |        Reserved Memory [KiB]      |      Time Elapsed [ms]      |
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+
| Arch   | Complexity | Labels | RegCount |  CodeSize | Code Hold.| Compiler  | Pass Temp.|   Emit Time  |  Reg. Alloc  |
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+
| X64    |          1 |      4 |       43 |      1123 |        32 |       128 |       128 |        0.038 |        0.106 |
| X64    |          2 |      5 |       46 |      1261 |        32 |       128 |       128 |        0.024 |        0.087 |
| X64    |          4 |      7 |       52 |      1688 |        32 |       128 |       128 |        0.028 |        0.116 |
| X64    |          8 |     11 |       64 |      2669 |        32 |       128 |       128 |        0.053 |        0.168 |
| X64    |         16 |     19 |       88 |      4862 |        32 |       128 |       128 |        0.045 |        0.256 |
| X64    |         32 |     35 |      136 |      9090 |        32 |       384 |       384 |        0.066 |        0.459 |
| X64    |         64 |     67 |      232 |     17409 |        32 |       384 |       384 |        0.120 |        0.821 |
| X64    |        128 |    131 |      424 |     34294 |        32 |       896 |       896 |        0.202 |        1.728 |
| X64    |        256 |    259 |      808 |     67830 |        32 |      1920 |      1920 |        0.571 |        4.283 |
| X64    |        512 |    515 |     1576 |    135745 |        32 |      3968 |      3968 |        0.750 |        6.750 |
| X64    |       1024 |   1027 |     3112 |    271740 |        32 |      8064 |      3968 |        1.603 |       16.985 |
| X64    |       2048 |   2051 |     6184 |    544468 |        32 |     16256 |      8064 |        3.138 |       37.865 |
| X64    |       4096 |   4099 |    12328 |   1091495 |        96 |     32640 |     16256 |        5.868 |       93.972 |
| X64    |       8192 |   8195 |    24616 |   2182753 |        96 |     32640 |     32640 |       18.472 |      243.897 |
| X64    |      16384 |  16387 |    49192 |   4371826 |       224 |     65408 |     65408 |       29.791 |      745.181 |
| X64    |      32768 |  32771 |    98344 |   8766075 |       480 |    130944 |    130944 |       69.190 |     2550.438 |
| X64    |      65536 |  65539 |   196648 |  17526400 |       992 |    262016 |    262016 |      181.681 |     9695.457 |
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+

+-----------------------------------------+-----------+-----------------------------------+--------------+--------------+
|           Input Configuration           |   Output  |        Reserved Memory [KiB]      |      Time Elapsed [ms]      |
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+
| Arch   | Complexity | Labels | RegCount |  CodeSize | Code Hold.| Compiler  | Pass Temp.|   Emit Time  |  Reg. Alloc  |
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+
| AArch64|          1 |      4 |       43 |       508 |        32 |       128 |       128 |        0.051 |        0.128 |
| AArch64|          2 |      5 |       46 |       604 |        32 |       128 |       128 |        0.026 |        0.074 |
| AArch64|          4 |      7 |       52 |       780 |        32 |       128 |       128 |        0.028 |        0.095 |
| AArch64|          8 |     11 |       64 |      1140 |        32 |       128 |       128 |        0.040 |        0.144 |
| AArch64|         16 |     19 |       88 |      1964 |        32 |       128 |       128 |        0.057 |        0.241 |
| AArch64|         32 |     35 |      136 |      3568 |        32 |       128 |       384 |        0.097 |        0.387 |
| AArch64|         64 |     67 |      232 |      6764 |        32 |       384 |       384 |        0.148 |        0.707 |
| AArch64|        128 |    131 |      424 |     13080 |        32 |       896 |       896 |        0.299 |        1.396 |
| AArch64|        256 |    259 |      808 |     25604 |        32 |       896 |      1920 |        0.543 |        3.273 |
| AArch64|        512 |    515 |     1576 |     51468 |        32 |      1920 |      3968 |        0.916 |        6.384 |
| AArch64|       1024 |   1027 |     3112 |    103556 |        32 |      3968 |      3968 |        2.272 |       14.512 |
| AArch64|       2048 |   2051 |     6184 |    207840 |        32 |      8064 |      8064 |        3.426 |       35.040 |
| AArch64|       4096 |   4099 |    12328 |        60 |        32 |     16256 |     16256 |        7.023 |       80.734 | (err: InvalidDisplacement)
| AArch64|       8192 |   8195 |    24616 |        28 |        32 |     32640 |     32640 |       13.864 |      221.689 | (err: InvalidDisplacement)
| AArch64|      16384 |  16387 |    49192 |        52 |        32 |     65408 |     65408 |       32.672 |      703.776 | (err: InvalidDisplacement)
| AArch64|      32768 |  32771 |    98344 |        40 |        32 |    130944 |    130944 |       74.842 |     2443.575 | (err: InvalidDisplacement)
| AArch64|      65536 |  65539 |   196648 |        36 |        32 |    196480 |    262016 |      188.100 |     9425.666 | (err: InvalidDisplacement)
+--------+------------+--------+----------+-----------+-----------+-----------+-----------+--------------+--------------+


C:\MyDartProjects\asmjit\referencias\asmjit-master\build>

