// Upstream x64 assembler goldens (asmjit-testing/tests/
// asmjit_test_assembler_x64.cpp), emitted through the generic
// `X86Assembler.emit(instId, operands)` path; see
// test/support/asm_goldens.dart for the data and the ratchet of unsupported
// cases and test/support/x86_goldens.dart for the expression evaluator.
import 'package:asmjit/asmjit.dart';

import '../support/asm_goldens.dart';
import '../support/x86_goldens.dart';

void main() => assemblerGoldens(
    'x64', (expr) => assembleX86Golden(expr, Environment.x64SysV()));
