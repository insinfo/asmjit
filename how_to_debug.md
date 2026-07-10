gdb --args C:\tools\dartsdk-3.6.0\bin\dart.exe test --concurrency=8 test/integration

gdb --args C:\tools\dartsdk-3.6.0\bin\dart.exe C:\MyDartProjects\asmjit\benchmark\debug_chacha_opt.dart

gdb --args C:\tools\dartsdk-3.6.0\bin\dart.exe test --concurrency=1 test/problema

set pagination off
handle SIGSEGV stop
run
# quando parar no crash:
bt full
thread apply all bt full
info reg
x/16i $pc-16
x/64gx $sp
info sharedlibrary
gcore core.dump   # opcional, gera core