/// AsmJit Dart - Comprehensive Codegen Benchmark
///
/// Port of asmjit-testing/bench/asmjit_bench_codegen_*.cpp
/// Benchmarks the performance of code generation across different scenarios.
// TODO: Match C++ bench parity (compiler paths, SSE/AVX mem forms, AVX512
// sequences, and full instruction mixes where encoders/dispatchers are ready).
// dart compile exe benchmark/codegen_benchmark.dart -o  benchmark/codegen_benchmark.exe
// .\referencias\asmjit-master\build\asmjit_bench_codegen.exe --quick
import 'dart:io';
import 'package:asmjit/asmjit.dart';
import 'package:asmjit/src/core/builder.dart' as ir;

const int kDefaultIterations = 100000;
const int kQuickIterations = 1000;

void main(List<String> args) {
  final quick = args.contains('--quick');
  final iterations = quick ? kQuickIterations : kDefaultIterations;

  print('AsmJit Dart Benchmark CodeGen v1.0.0 [Arch=X64] [Mode=Release]');
  print('');
  print('Iterations: $iterations ${quick ? "(quick mode)" : ""}');
  print('');

  // Run X86/X64 benchmarks
  benchmarkX86EmptyFunction(iterations);
  benchmarkX86NOpsSequence(iterations, 4);
  benchmarkX86NOpsSequence(iterations, 16);
  benchmarkX86NOpsSequence(iterations, 32);
  benchmarkX86NOpsSequence(iterations, 64);
  benchmarkX86GpSequenceReg(iterations);
  benchmarkX86GpSequenceMem(iterations);
  benchmarkX86SseSequenceReg(iterations);
  benchmarkX86SseSequenceMem(iterations);
  benchmarkX86AvxSequenceReg(iterations);
  benchmarkX86AvxSequenceMem(iterations);

  print('');

  // Run AArch64 benchmarks
  benchmarkA64EmptyFunction(iterations);
  benchmarkA64NOpsSequence(iterations, 4);
  benchmarkA64NOpsSequence(iterations, 16);
  benchmarkA64NOpsSequence(iterations, 32);
  benchmarkA64NOpsSequence(iterations, 64);
  benchmarkA64GpSequence(iterations);
  benchmarkA64NeonSequence(iterations);
}

class BenchResult {
  final String name;
  final String arch;
  final String emitter;
  final int codeSize;
  final double timeUs;

  BenchResult(this.name, this.arch, this.emitter, this.codeSize, this.timeUs);

  double get speedMibPerSec => codeSize > 0 ? (codeSize / timeUs) : 0;
  double get speedMInstPerSec => timeUs > 0 ? (1.0 / timeUs) : 0;

  void print() {
    final speedMib = codeSize > 0
        ? '${speedMibPerSec.toStringAsFixed(1).padLeft(6)} [MiB/s]'
        : '   N/A        ';
    final speedMInst =
        '${speedMInstPerSec.toStringAsFixed(1).padLeft(6)} [MInst/s]';
    stdout.write('  [$arch] $emitter'.padRight(38));
    stdout.write('| CodeSize: ${codeSize.toString().padLeft(5)} [B] ');
    stdout.write('| Time: ${timeUs.toStringAsFixed(3).padLeft(7)} [us] ');
    stdout.write('| Speed: $speedMib, $speedMInst');
    stdout.writeln();
  }
}

void printUnavailable(String arch, String emitter, String reason) {
  stdout.write('  [$arch] $emitter'.padRight(38));
  stdout.write('| CodeSize:   N/A [B] ');
  stdout.write('| Time:    N/A [us] ');
  stdout.write('| Speed:   N/A        ,   N/A');
  if (reason.isNotEmpty) {
    stdout.write(' ($reason)');
  }
  stdout.writeln();
}

void printCompilerUnavailable(String arch) {
  // TODO: Wire real compiler backend once X86Compiler is implemented.
  printUnavailable(arch, 'Compiler [no-asm]', 'TODO compiler backend');
  printUnavailable(arch, 'Compiler [finalized]', 'TODO compiler backend');
}

/// Benchmark helper that runs a code generation function many times.
BenchResult runBench(
  String name,
  String arch,
  String emitter,
  int iterations,
  int Function() generateFn,
) {
  final sw = Stopwatch()..start();
  var codeSize = 0;
  for (var i = 0; i < iterations; i++) {
    codeSize = generateFn();
  }
  sw.stop();
  final timeUs = sw.elapsedMicroseconds / iterations;
  return BenchResult(name, arch, emitter, codeSize, timeUs);
}

// =============================================================================
// X86/X64 Benchmarks
// =============================================================================

void benchmarkX86EmptyFunction(int iterations) {
  print('Empty function (mov + return from function):');

  // Assembler [raw]
  runBench('Empty', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.movRI(eax, 0);
    asm.ret();
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('Empty', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.movRI(eax, 0);
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('Empty', 'X64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.push(rbp);
    asm.movRR(rbp, rsp);
    asm.movRI(eax, 0);
    asm.movRR(rsp, rbp);
    asm.pop(rbp);
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  // Builder [no-asm]
  runBench('Empty', 'X64', 'Builder [no-asm]', iterations, () {
    final builder = X86CodeBuilder.create();
    builder.mov(eax, 0);
    builder.ret();
    return builder.code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('Empty', 'X64', 'Builder [finalized]', iterations, () {
    final builder = X86CodeBuilder.create();
    builder.mov(eax, 0);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('Empty', 'X64', 'Builder [prolog/epilog]', iterations, () {
    final builder = X86CodeBuilder.create();
    builder.configureFrameAttr(FuncFrameAttr.nonLeaf());
    builder.mov(eax, 0);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

void benchmarkX86NOpsSequence(int iterations, int nOps) {
  print('${nOps}-Ops sequence ($nOps ops + return from function):');

  // Assembler [raw]
  runBench('${nOps}Ops', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    for (var i = 0; i < nOps; i += 4) {
      asm.addRR(eax, ebx);
      asm.imulRR(eax, ecx);
      asm.subRR(eax, edx);
      asm.imulRR(eax, ecx);
    }
    asm.ret();
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('${nOps}Ops', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    for (var i = 0; i < nOps; i += 4) {
      asm.addRR(eax, ebx);
      asm.imulRR(eax, ecx);
      asm.subRR(eax, edx);
      asm.imulRR(eax, ecx);
    }
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('${nOps}Ops', 'X64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.push(rbp);
    asm.movRR(rbp, rsp);
    for (var i = 0; i < nOps; i += 4) {
      asm.addRR(eax, ebx);
      asm.imulRR(eax, ecx);
      asm.subRR(eax, edx);
      asm.imulRR(eax, ecx);
    }
    asm.movRR(rsp, rbp);
    asm.pop(rbp);
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  // Builder [no-asm]
  runBench('${nOps}Ops', 'X64', 'Builder [no-asm]', iterations, () {
    final builder = X86CodeBuilder.create();
    for (var i = 0; i < nOps; i += 4) {
      builder.add(eax, ebx);
      builder.imul(eax, ecx);
      builder.sub(eax, edx);
      builder.imul(eax, ecx);
    }
    builder.ret();
    return builder.code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('${nOps}Ops', 'X64', 'Builder [finalized]', iterations, () {
    final builder = X86CodeBuilder.create();
    for (var i = 0; i < nOps; i += 4) {
      builder.add(eax, ebx);
      builder.imul(eax, ecx);
      builder.sub(eax, edx);
      builder.imul(eax, ecx);
    }
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('${nOps}Ops', 'X64', 'Builder [prolog/epilog]', iterations, () {
    final builder = X86CodeBuilder.create();
    builder.configureFrameAttr(FuncFrameAttr.nonLeaf());
    for (var i = 0; i < nOps; i += 4) {
      builder.add(eax, ebx);
      builder.imul(eax, ecx);
      builder.sub(eax, edx);
      builder.imul(eax, ecx);
    }
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

void benchmarkX86GpSequenceReg(int iterations) {
  print('GpSequence<Reg> (Sequence of GP instructions - reg-only):');

  // Assembler [raw]
  runBench('GpSeq', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateGpSequenceReg(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('GpSeq', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateGpSequenceReg(asm);
    return code.finalize().textBytes.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('GpSeq', 'X64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.push(rbp);
    asm.movRR(rbp, rsp);
    _generateGpSequenceReg(asm);
    asm.movRR(rsp, rbp);
    asm.pop(rbp);
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  // Builder [no-asm]
  runBench('GpSeq', 'X64', 'Builder [no-asm]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateGpSequenceBuilder(builder);
    builder.ret();
    return builder.code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('GpSeq', 'X64', 'Builder [finalized]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateGpSequenceBuilder(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('GpSeq', 'X64', 'Builder [prolog/epilog]', iterations, () {
    final builder = X86CodeBuilder.create();
    builder.configureFrameAttr(FuncFrameAttr.nonLeaf());
    _generateGpSequenceBuilder(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

void benchmarkX86GpSequenceMem(int iterations) {
  print('GpSequence<Mem> (Sequence of GP instructions - reg/mem):');

  // Assembler [raw]
  runBench('GpSeqMem', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateGpSequenceMem(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('GpSeqMem', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateGpSequenceMem(asm);
    return code.finalize().textBytes.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('GpSeqMem', 'X64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.push(rbp);
    asm.movRR(rbp, rsp);
    _generateGpSequenceMem(asm);
    asm.movRR(rsp, rbp);
    asm.pop(rbp);
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

void benchmarkX86SseSequenceReg(int iterations) {
  print('SseSequence<Reg> (sequence of SSE+ instructions - reg-only):');

  // Assembler [raw] - SSE ops
  runBench('SseSeq', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateSseSequenceReg(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('SseSeq', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateSseSequenceReg(asm);
    return code.finalize().textBytes.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('SseSeq', 'X64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.push(rbp);
    asm.movRR(rbp, rsp);
    _generateSseSequenceReg(asm);
    asm.movRR(rsp, rbp);
    asm.pop(rbp);
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  // Builder [no-asm]
  runBench('SseSeq', 'X64', 'Builder [no-asm]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateSseSequenceBuilderReg(builder);
    builder.ret();
    return builder.code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('SseSeq', 'X64', 'Builder [finalized]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateSseSequenceBuilderReg(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('SseSeq', 'X64', 'Builder [prolog/epilog]', iterations, () {
    final builder = X86CodeBuilder.create();
    builder.configureFrameAttr(FuncFrameAttr.nonLeaf());
    _generateSseSequenceBuilderReg(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

void benchmarkX86SseSequenceMem(int iterations) {
  print('SseSequence<Mem> (sequence of SSE+ instructions - reg/mem):');

  // Assembler [raw]
  runBench('SseSeqMem', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateSseSequenceMem(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('SseSeqMem', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateSseSequenceMem(asm);
    return code.finalize().textBytes.length;
  }).print();

  // Builder [finalized]
  runBench('SseSeqMem', 'X64', 'Builder [finalized]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateSseSequenceBuilderMem(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

void benchmarkX86AvxSequenceReg(int iterations) {
  print('AvxSequence<Reg> (sequence of AVX+ instructions - reg-only):');

  // Assembler [raw] - AVX ops
  runBench('AvxSeq', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateAvxSequenceReg(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('AvxSeq', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateAvxSequenceReg(asm);
    return code.finalize().textBytes.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('AvxSeq', 'X64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    asm.push(rbp);
    asm.movRR(rbp, rsp);
    _generateAvxSequenceReg(asm);
    asm.movRR(rsp, rbp);
    asm.pop(rbp);
    asm.ret();
    return code.finalize().textBytes.length;
  }).print();

  // Builder [no-asm]
  runBench('AvxSeq', 'X64', 'Builder [no-asm]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateAvxSequenceBuilderReg(builder);
    builder.ret();
    return builder.code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('AvxSeq', 'X64', 'Builder [finalized]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateAvxSequenceBuilderReg(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('AvxSeq', 'X64', 'Builder [prolog/epilog]', iterations, () {
    final builder = X86CodeBuilder.create();
    builder.configureFrameAttr(FuncFrameAttr.nonLeaf());
    _generateAvxSequenceBuilderReg(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

void benchmarkX86AvxSequenceMem(int iterations) {
  print('AvxSequence<Mem> (sequence of AVX+ instructions - reg/mem):');

  // Assembler [raw]
  runBench('AvxSeqMem', 'X64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateAvxSequenceMem(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler [validated]
  runBench('AvxSeqMem', 'X64', 'Assembler [validated]', iterations, () {
    final code = CodeHolder(env: Environment.host());
    final asm = X86Assembler(code);
    _generateAvxSequenceMem(asm);
    return code.finalize().textBytes.length;
  }).print();

  // Builder [finalized]
  runBench('AvxSeqMem', 'X64', 'Builder [finalized]', iterations, () {
    final builder = X86CodeBuilder.create();
    _generateAvxSequenceBuilderMem(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  printCompilerUnavailable('X64');

  print('');
}

// GP Sequence generator - reg only
void _generateGpSequenceReg(X86Assembler asm) {
  asm.movRI(rax, 0xAAAAAAAA);
  asm.movRI(rbx, 0xBBBBBBBB);
  asm.movRI(rcx, 0xCCCCCCCC);
  asm.movRI(rdx, 0xFFFFFFFF);

  for (var i = 0; i < 8; i++) {
    asm.adcRR(rax, rbx);
    asm.addRR(rbx, rcx);
    asm.addRR(rcx, rdx);
    asm.andRR(rax, rbx);
    asm.orRR(rbx, rcx);
    asm.xorRR(rcx, rdx);
    asm.bsf(rax, rbx);
    asm.bsr(rbx, rcx);
    asm.popcnt(rcx, rdx);
    asm.lzcnt(rax, rbx);
    asm.tzcnt(rbx, rcx);
    asm.cmpRR(rax, rbx);
    asm.cmovb(rax, rbx);
    asm.cmpRR(rbx, rcx);
    asm.cmovg(rbx, rcx);
    asm.dec(rax);
    asm.inc(rbx);
    asm.imulRR(rcx, rdx);
    asm.movsxB(rax, al);
    asm.movsxW(rbx, bx);
    asm.movzxB(rcx, cl);
    asm.movzxW(rdx, dx);
    asm.movsxd(rax, eax);
    asm.neg(rax);
    asm.not(rbx);
    asm.sbbRR(rcx, rdx);
    asm.subRR(rax, rbx);
    asm.testRR(rax, rbx);
    asm.xchg(rax, rbx);
    asm.shlRCl(rax);
    asm.shrRCl(rbx);
    asm.sarRCl(rcx);
    asm.rolRI(rdx, 1);
    asm.rorRI(rdx, 1);
    asm.adcx(rax, rbx);
    asm.adox(rbx, rcx);
  }

  asm.ret();
}

// GP Sequence generator - builder
void _generateGpSequenceBuilder(X86CodeBuilder builder) {
  builder.mov(rax, 0xAAAAAAAA);
  builder.mov(rbx, 0xBBBBBBBB);
  builder.mov(rcx, 0xCCCCCCCC);
  builder.mov(rdx, 0xFFFFFFFF);

  for (var i = 0; i < 8; i++) {
    builder.add(rax, rbx);
    builder.add(rbx, rcx);
    builder.sub(rax, rbx);
    builder.and(rax, rbx);
    builder.or(rbx, rcx);
    builder.xor(rcx, rdx);
    builder.imul(rax, rcx);
    builder.cmp(rax, rbx);
    builder.test(rbx, rcx);
  }
}

// GP Sequence generator - with memory ops
void _generateGpSequenceMem(X86Assembler asm) {
  asm.movRI(rax, 0xAAAAAAAA);
  asm.movRI(rbx, 0xBBBBBBBB);
  asm.movRI(rcx, 0xCCCCCCCC);

  final mem = X86Mem.ptr(rcx);
  for (var i = 0; i < 10; i++) {
    asm.addRM(rax, mem);
    asm.addRM(rbx, mem);
    asm.subRM(rax, mem);
    asm.subRM(rbx, mem);
    asm.andRM(rax, mem);
    asm.orRM(rax, mem);
    asm.xorRM(rax, mem);
    asm.cmpRM(rax, mem);
    asm.testRM(rax, mem);
    asm.movRM(rax, mem);
    asm.movMR(mem, rbx);
  }

  asm.ret();
}

// SSE Sequence generator
void _generateSseSequenceReg(X86Assembler asm) {
  asm.xorRR(eax, eax);
  asm.xorps(xmm0, xmm0);
  asm.xorps(xmm1, xmm1);
  asm.xorps(xmm2, xmm2);
  asm.xorps(xmm3, xmm3);

  for (var i = 0; i < 10; i++) {
    asm.addps(xmm0, xmm1);
    asm.addssXX(xmm0, xmm1);
    asm.subps(xmm0, xmm1);
    asm.subssXX(xmm0, xmm1);
    asm.mulps(xmm0, xmm1);
    asm.mulssXX(xmm0, xmm1);
    asm.divps(xmm0, xmm1);
    asm.divssXX(xmm0, xmm1);
    asm.minps(xmm0, xmm1);
    asm.maxps(xmm0, xmm1);
    asm.movapsXX(xmm0, xmm1);
    asm.movupsXX(xmm1, xmm2);
    asm.movsdXX(xmm2, xmm3);
    asm.movssXX(xmm3, xmm0);
    asm.addsdXX(xmm0, xmm1);
    asm.subsdXX(xmm1, xmm2);
    asm.mulsdXX(xmm2, xmm3);
    asm.divsdXX(xmm3, xmm0);
    asm.sqrtsdXX(xmm0, xmm1);
    asm.sqrtssXX(xmm1, xmm2);
    asm.xorpsXX(xmm0, xmm1);
    asm.pxorXX(xmm1, xmm2);
    asm.xorpdXX(xmm2, xmm3);
    asm.cvtsi2sdXR(xmm0, rax);
    asm.cvttsd2siRX(rax, xmm0);
    asm.cvtsi2ssXR(xmm1, rbx);
    asm.cvttss2siRX(rbx, xmm1);
    asm.cvtsd2ssXX(xmm2, xmm3);
    asm.cvtss2sdXX(xmm3, xmm2);
    asm.comisdXX(xmm0, xmm1);
    asm.comissXX(xmm2, xmm3);
    asm.ucomisdXX(xmm1, xmm2);
    asm.ucomissXX(xmm3, xmm0);
    asm.movdXR(xmm0, eax);
    asm.movdRX(eax, xmm1);
    asm.movqXR(xmm2, rax);
    asm.movqRX(rax, xmm3);
  }

  asm.ret();
}

void _generateSseSequenceBuilderReg(X86CodeBuilder builder) {
  // TODO: Expand SIMD dispatcher to support more SSE ops in Builder.
  for (var i = 0; i < 20; i++) {
    builder.inst(X86InstId.kAddps, [
      ir.RegOperand(xmm0),
      ir.RegOperand(xmm1),
      ir.RegOperand(xmm2),
    ]);
    builder.inst(X86InstId.kAddpd, [
      ir.RegOperand(xmm1),
      ir.RegOperand(xmm2),
      ir.RegOperand(xmm3),
    ]);
    builder.inst(X86InstId.kVxorps, [
      ir.RegOperand(xmm0),
      ir.RegOperand(xmm1),
      ir.RegOperand(xmm2),
    ]);
  }
}

// AVX Sequence generator
void _generateAvxSequenceReg(X86Assembler asm) {
  asm.xorRR(eax, eax);
  asm.vxorpsXXX(xmm0, xmm0, xmm0);
  asm.vxorpsXXX(xmm1, xmm1, xmm1);
  asm.vxorpsXXX(xmm2, xmm2, xmm2);
  asm.vxorpsYYY(ymm0, ymm0, ymm0);
  asm.vxorpsYYY(ymm1, ymm1, ymm1);
  asm.vxorpsYYY(ymm2, ymm2, ymm2);

  for (var i = 0; i < 10; i++) {
    asm.vaddpsXXX(xmm0, xmm1, xmm2);
    asm.vaddpsYYY(ymm0, ymm1, ymm2);
    asm.vaddpdXXX(xmm0, xmm1, xmm2);
    asm.vaddpdYYY(ymm0, ymm1, ymm2);
    asm.vsubpsXXX(xmm0, xmm1, xmm2);
    asm.vsubpdXXX(xmm0, xmm1, xmm2);
    asm.vsubpsYYY(ymm0, ymm1, ymm2);
    asm.vsubpdYYY(ymm0, ymm1, ymm2);
    asm.vmulpsYYY(ymm0, ymm1, ymm2);
    asm.vmulpdYYY(ymm0, ymm1, ymm2);
    asm.vaddsdXXX(xmm0, xmm1, xmm2);
    asm.vsubsdXXX(xmm1, xmm2, xmm3);
    asm.vmulsdXXX(xmm2, xmm3, xmm0);
    asm.vdivsdXXX(xmm3, xmm0, xmm1);
    asm.vxorpsXXX(xmm0, xmm1, xmm2);
    asm.vxorpsYYY(ymm0, ymm1, ymm2);
    asm.vpxorXXX(xmm0, xmm1, xmm2);
    asm.vpadddXXX(xmm0, xmm1, xmm2);
    asm.vpadddYYY(ymm0, ymm1, ymm2);
    asm.vpaddqXXX(xmm1, xmm2, xmm3);
    asm.vpmulldXXX(xmm2, xmm3, xmm0);
    asm.vfmadd132sdXXX(xmm0, xmm1, xmm2);
    asm.vfmadd231sdXXX(xmm1, xmm2, xmm3);
    asm.vmovapsXX(xmm0, xmm1);
    asm.vmovapsYY(ymm0, ymm1);
    asm.vmovupsXX(xmm1, xmm2);
    asm.vmovupsYY(ymm1, ymm2);
  }
  asm.vzeroupper();

  asm.ret();
}

void _generateAvxSequenceBuilderReg(X86CodeBuilder builder) {
  // TODO: Expand SIMD dispatcher to support more AVX ops in Builder.
  for (var i = 0; i < 20; i++) {
    builder.inst(X86InstId.kAddps, [
      ir.RegOperand(xmm0),
      ir.RegOperand(xmm1),
      ir.RegOperand(xmm2),
    ]);
    builder.inst(X86InstId.kAddpd, [
      ir.RegOperand(xmm1),
      ir.RegOperand(xmm2),
      ir.RegOperand(xmm3),
    ]);
    builder.inst(X86InstId.kVxorps, [
      ir.RegOperand(xmm0),
      ir.RegOperand(xmm1),
      ir.RegOperand(xmm2),
    ]);
  }
}

void _generateAvxSequenceMem(X86Assembler asm) {
  asm.xorRR(eax, eax);
  final mem = X86Mem.ptr(rcx);

  for (var i = 0; i < 10; i++) {
    asm.vaddpsXXM(xmm0, xmm1, mem);
    asm.vaddpsYYM(ymm0, ymm1, mem);
    asm.vaddpdXXM(xmm1, xmm2, mem);
    asm.vaddpdYYM(ymm1, ymm2, mem);
    asm.vsubpsXXM(xmm2, xmm3, mem);
    asm.vsubpsYYM(ymm2, ymm3, mem);
    asm.vsubpdXXM(xmm0, xmm1, mem);
    asm.vsubpdYYM(ymm0, ymm1, mem);
    asm.vmulpsXXM(xmm1, xmm2, mem);
    asm.vmulpsYYM(ymm1, ymm2, mem);
    asm.vxorpsXXM(xmm2, xmm3, mem);
    asm.vxorpsYYM(ymm2, ymm3, mem);
    asm.vpxorXXM(xmm0, xmm1, mem);
    asm.vpxorYYM(ymm0, ymm1, mem);
  }

  asm.ret();
}

void _generateAvxSequenceBuilderMem(X86CodeBuilder builder) {
  final mem = X86Mem.ptr(rcx);
  for (var i = 0; i < 10; i++) {
    builder.vaddps(xmm0, xmm1, mem);
    builder.vaddps(ymm0, ymm1, mem);
    builder.vaddpd(xmm1, xmm2, mem);
    builder.vaddpd(ymm1, ymm2, mem);
    builder.vsubps(xmm2, xmm3, mem);
    builder.vsubps(ymm2, ymm3, mem);
    builder.vsubpd(xmm0, xmm1, mem);
    builder.vsubpd(ymm0, ymm1, mem);
    builder.vmulps(xmm1, xmm2, mem);
    builder.vmulps(ymm1, ymm2, mem);
    builder.vxorps(xmm2, xmm3, mem);
    builder.vxorps(ymm2, ymm3, mem);
    builder.vpxor(xmm0, xmm1, mem);
    builder.vpxor(ymm0, ymm1, mem);
  }
}

// =============================================================================
// AArch64 Benchmarks
// =============================================================================

void benchmarkA64EmptyFunction(int iterations) {
  print('Empty function (mov + return from function) [AArch64]:');

  // Assembler [raw]
  runBench('Empty', 'A64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    asm.movz(w0, 0);
    asm.ret();
    return code.text.buffer.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('Empty', 'A64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    asm.emitPrologue();
    asm.movz(w0, 0);
    asm.emitEpilogue();
    return code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('Empty', 'A64', 'Builder [finalized]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    builder.mov(w0, xzr);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('Empty', 'A64', 'Builder [prolog/epilog]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    builder.setStackSize(16);
    builder.mov(w0, xzr);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  print('');
}

void benchmarkA64NOpsSequence(int iterations, int nOps) {
  print('${nOps}-Ops sequence ($nOps ops + return from function) [AArch64]:');

  // Assembler [raw]
  runBench('${nOps}Ops', 'A64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    for (var i = 0; i < nOps; i += 4) {
      asm.add(x0, x0, x1);
      asm.mul(x0, x0, x2);
      asm.sub(x0, x0, x3);
      asm.mul(x0, x0, x2);
    }
    asm.ret();
    return code.text.buffer.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('${nOps}Ops', 'A64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    asm.emitPrologue();
    for (var i = 0; i < nOps; i += 4) {
      asm.add(x0, x0, x1);
      asm.mul(x0, x0, x2);
      asm.sub(x0, x0, x3);
      asm.mul(x0, x0, x2);
    }
    asm.emitEpilogue();
    return code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('${nOps}Ops', 'A64', 'Builder [finalized]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    for (var i = 0; i < nOps; i += 4) {
      builder.add(x0, x0, x1);
      builder.mul(x0, x0, x2);
      builder.sub(x0, x0, x3);
      builder.mul(x0, x0, x2);
    }
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('${nOps}Ops', 'A64', 'Builder [prolog/epilog]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    builder.setStackSize(16);
    for (var i = 0; i < nOps; i += 4) {
      builder.add(x0, x0, x1);
      builder.mul(x0, x0, x2);
      builder.sub(x0, x0, x3);
      builder.mul(x0, x0, x2);
    }
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  print('');
}

void benchmarkA64GpSequence(int iterations) {
  print('GpSequence (Sequence of GP instructions) [AArch64]:');

  // Assembler [raw]
  runBench('GpSeq', 'A64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    _generateA64GpSequence(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('GpSeq', 'A64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    asm.emitPrologue();
    _generateA64GpSequence(asm);
    asm.emitEpilogue();
    return code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('GpSeq', 'A64', 'Builder [finalized]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    _generateA64GpSequenceBuilder(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('GpSeq', 'A64', 'Builder [prolog/epilog]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    builder.setStackSize(16);
    _generateA64GpSequenceBuilder(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  print('');
}

void benchmarkA64NeonSequence(int iterations) {
  print('NeonSequence (Sequence of NEON instructions) [AArch64]:');

  // Assembler [raw]
  runBench('NeonSeq', 'A64', 'Assembler [raw]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    _generateA64NeonSequence(asm);
    return code.text.buffer.length;
  }).print();

  // Assembler with prolog/epilog
  runBench('NeonSeq', 'A64', 'Assembler [prolog/epilog]', iterations, () {
    final code = CodeHolder(env: Environment.aarch64());
    final asm = A64Assembler(code);
    asm.emitPrologue();
    _generateA64NeonSequence(asm);
    asm.emitEpilogue();
    return code.text.buffer.length;
  }).print();

  // Builder [finalized]
  runBench('NeonSeq', 'A64', 'Builder [finalized]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    _generateA64NeonSequenceBuilder(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  // Builder [prolog/epilog]
  runBench('NeonSeq', 'A64', 'Builder [prolog/epilog]', iterations, () {
    final builder = A64CodeBuilder.create(env: Environment.aarch64());
    builder.setStackSize(16);
    _generateA64NeonSequenceBuilder(builder);
    builder.ret();
    return builder.finalize().textBytes.length;
  }).print();

  print('');
}

// A64 GP Sequence generator
void _generateA64GpSequence(A64Assembler asm) {
  asm.movz(x0, 0xAAAA);
  asm.movz(x1, 0xBBBB);
  asm.movz(x2, 0xCCCC);
  asm.movz(x3, 0xFFFF);

  for (var i = 0; i < 10; i++) {
    asm.add(x0, x0, x1);
    asm.add(x1, x1, x2);
    asm.add(x2, x2, x3);
    asm.sub(x0, x0, x1);
    asm.sub(x1, x1, x2);
    asm.and(x0, x0, x1);
    asm.and(x1, x1, x2);
    asm.orr(x0, x0, x1);
    asm.orr(x1, x1, x2);
    asm.eor(x0, x0, x1);
    asm.eor(x1, x1, x2);
    asm.cmp(x0, x1);
    asm.cmp(x1, x2);
    asm.mul(x0, x1, x2);
    asm.mul(x1, x2, x3);
  }

  asm.ret();
}

void _generateA64GpSequenceBuilder(A64CodeBuilder builder) {
  builder.add(x0, xzr, 0xAAAA);
  builder.add(x1, xzr, 0xBBBB);
  builder.add(x2, xzr, 0xCCCC);
  builder.add(x3, xzr, 0xFFFF);

  for (var i = 0; i < 10; i++) {
    builder.add(x0, x0, x1);
    builder.add(x1, x1, x2);
    builder.add(x2, x2, x3);
    builder.sub(x0, x0, x1);
    builder.sub(x1, x1, x2);
    builder.and(x0, x0, x1);
    builder.and(x1, x1, x2);
    builder.orr(x0, x0, x1);
    builder.orr(x1, x1, x2);
    builder.eor(x0, x0, x1);
    builder.eor(x1, x1, x2);
    builder.cmp(x0, x1);
    builder.cmp(x1, x2);
    builder.mul(x0, x1, x2);
    builder.mul(x1, x2, x3);
  }
}

// A64 NEON Sequence generator
void _generateA64NeonSequence(A64Assembler asm) {
  for (var i = 0; i < 20; i++) {
    asm.addVec(v0.s, v1.s, v2.s);
    asm.addVec(v1.s, v2.s, v3.s);
    asm.subVec(v0.s, v1.s, v2.s);
    asm.subVec(v1.s, v2.s, v3.s);
    asm.mulVec(v0.s, v1.s, v2.s);
    asm.mulVec(v1.s, v2.s, v3.s);
    asm.andVec(v0.s, v1.s, v2.s);
    asm.orrVec(v0.s, v1.s, v2.s);
    asm.eorVec(v0.s, v1.s, v2.s);
    asm.fadd(d0, d1, d2);
    asm.fsub(d0, d1, d2);
    asm.fmul(d0, d1, d2);
    asm.fdiv(d0, d1, d2);
  }

  asm.ret();
}

void _generateA64NeonSequenceBuilder(A64CodeBuilder builder) {
  for (var i = 0; i < 20; i++) {
    builder.addVec(v0.s, v1.s, v2.s);
    builder.addVec(v1.s, v2.s, v3.s);
    builder.subVec(v0.s, v1.s, v2.s);
    builder.subVec(v1.s, v2.s, v3.s);
    builder.mulVec(v0.s, v1.s, v2.s);
    builder.mulVec(v1.s, v2.s, v3.s);
    builder.andVec(v0.s, v1.s, v2.s);
    builder.eorVec(v0.s, v1.s, v2.s);
    builder.fadd(d0, d1, d2);
    builder.fsub(d0, d1, d2);
    builder.fmul(d0, d1, d2);
    builder.fdiv(d0, d1, d2);
  }
}

// X86 SSE Sequence generator - memory
void _generateSseSequenceMem(X86Assembler asm) {
  asm.xorRR(eax, eax);
  final mem = X86Mem.ptr(rcx);

  for (var i = 0; i < 10; i++) {
    asm.addpsXM(xmm0, mem);
    asm.subpsXM(xmm1, mem);
    asm.mulpsXM(xmm2, mem);
    asm.divpsXM(xmm3, mem);
    asm.xorpsXM(xmm0, mem);
    asm.pxorXM(xmm1, mem);
    asm.movapsXM(xmm2, mem);
    asm.movupsXM(xmm3, mem);
    asm.movssXM(xmm0, mem);
    asm.movsdXM(xmm1, mem);
  }

  asm.ret();
}

void _generateSseSequenceBuilderMem(X86CodeBuilder builder) {
  final mem = X86Mem.ptr(rcx);
  for (var i = 0; i < 10; i++) {
    builder.vaddps(xmm0, mem);
    builder.vsubps(xmm1, mem);
    builder.vmulps(xmm2, mem);
    builder.vdivps(xmm3, mem);
    builder.vxorps(xmm0, mem);
    builder.vpxor(xmm1, mem);
    builder.vmovaps(xmm2, mem);
    builder.vmovups(xmm3, mem);
    builder.movss(xmm0, mem);
    builder.movsd(xmm1, mem);
  }
}
