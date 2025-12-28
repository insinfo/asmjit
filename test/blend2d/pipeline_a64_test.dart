import 'package:asmjit/asmjit.dart';
import 'package:asmjit/blend2d.dart';
import 'package:test/test.dart';

void main() {
  group('PipelineCompiler A64', () {
    test('Compiles SrcOver for A64', () {
      final runtime = JitRuntime(
        enableExecutableMemory: true,
        environment: Environment.aarch64(),
      );
      final compiler = PipelineCompiler();

      final program = compiler.compileProgram(
        runtime,
        const [
          PipelineOp.compSrcOver(
            width: 100,
            height: 100,
            dstStride: 400,
            srcStride: 400,
            dstFormat: PixelFormat.prgb32,
            srcFormat: PixelFormat.prgb32,
          ),
        ],
        backend: PipelineBackend.jitA64,
      );

      program.dispose();
      runtime.dispose();
    });

    test('Compiles SrcOver A64 builder directly', () {
      final env = Environment.aarch64();
      final builder = A64CodeBuilder.create(env: env);

      final v0 = builder.newVecReg(sizeBits: 128);
      final v1 = builder.newVecReg(sizeBits: 128);
      builder.faddVec(v0, v1, v1);

      final finalized = builder.finalize();
      expect(finalized.textBytes.length, greaterThan(0));
    });
  });
}
