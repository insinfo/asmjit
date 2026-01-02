import 'package:asmjit/asmjit.dart' as asmjit;

typedef BenchmarkFunc = void Function(asmjit.BaseEmitter emitter);

class BenchmarkResult {
  final String arch;
  final String emitter;
  final String name;
  final int codeSize;
  final double durationUs;
  final int instructionCount;

  BenchmarkResult({
    required this.arch,
    required this.emitter,
    required this.name,
    required this.codeSize,
    required this.durationUs,
    this.instructionCount = 0,
  });

  @override
  String toString() {
    final sb = StringBuffer();
    sb.write(
        '  [${arch.padRight(7)}] ${emitter.padRight(9)} ${name.padRight(16)} | CodeSize:${codeSize.toString().padLeft(5)} [B] | Time:${durationUs.toStringAsFixed(3).padLeft(7)} [us]');

    if (codeSize > 0) {
      final speed = calculateMbps(durationUs, codeSize);
      sb.write(' | Speed:${speed.toStringAsFixed(1).padLeft(7)} [MiB/s]');
    } else {
      sb.write(' | Speed:    N/A        ');
    }

    if (instructionCount > 0) {
      final mips = calculateMips(durationUs, instructionCount);
      sb.write(', ${mips.toStringAsFixed(1).padLeft(8)} [MInst/s]');
    }
    return sb.toString();
  }
}

double calculateMbps(double durationUs, int outputSize) {
  if (durationUs == 0) return 0.0;
  return (outputSize * 1000000) / (durationUs * 1024 * 1024);
}

double calculateMips(double durationUs, int instructionCount) {
  if (durationUs == 0) return 0.0;
  return (instructionCount * 1000000.0) / (durationUs * 1e6);
}

void bench(
  asmjit.CodeHolder code,
  asmjit.Arch arch,
  int numIterations,
  String testName,
  int instructionCount,
  BenchmarkFunc func,
) {
  final archName = arch.name.toUpperCase();
  final asmjit.BaseEmitter emitter;
  if (arch == asmjit.Arch.x64 || arch == asmjit.Arch.x86) {
    emitter = asmjit.X86Assembler(code);
  } else {
    emitter = asmjit.A64Assembler(code);
  }

  final emitterName = "Assembler";

  double minDurationUs = double.infinity;
  int codeSize = 0;
  int actualInstructionCount = 0;

  for (var i = 0; i < numIterations; i++) {
    code.reset();
    emitter.instructionCount = 0;

    final stopwatch = Stopwatch()..start();
    func(emitter);
    stopwatch.stop();

    codeSize = code.text.size;
    actualInstructionCount = emitter.instructionCount;
    final durationUs = stopwatch.elapsedMicroseconds.toDouble();
    if (durationUs < minDurationUs) {
      minDurationUs = durationUs;
    }
  }

  final result = BenchmarkResult(
    arch: archName,
    emitter: emitterName,
    name: testName,
    codeSize: codeSize,
    durationUs: minDurationUs,
    instructionCount: actualInstructionCount,
  );

  print(result);

  code.reset();
}
