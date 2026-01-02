import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  group('UJIT SIMD Tests', () {
    late CodeHolder code;
    late UniCompiler cc;

    setUp(() {
      code = CodeHolder(env: Environment.host());
      final compiler =
          X86Compiler(env: code.env, labelManager: code.labelManager);
      cc = UniCompiler(compiler);
      cc.addFunc(FuncSignature.noArgs(cc: CallConvId.x64Windows));
    });

    tearDown(() {
      // code.finalize(); // Done in tests
    });

    test('LoadDup Variants', () {
      final v16 = cc.newXmm("v16");
      final v32 = cc.newXmm("v32");
      final v64 = cc.newXmm("v64");
      final mem = X86Mem.abs(0x1000, size: 8); // Dummy address

      cc.emitVM(UniOpVM.loadDup16, v16, mem); // pinsrw+pshuflw+punpcklqdq
      cc.emitVM(UniOpVM.loadDup32, v32, mem); // movd+pshufd
      cc.emitVM(UniOpVM.loadDup64, v64, mem); // movq+punpcklqdq

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();

      expect(code.isFinalized, isTrue);
    });

    test('Broadcast Variants', () {
      final dst = cc.newXmm("dst");
      final src = cc.newXmm("src");

      // We assume src is loaded with something
      cc.emit2v(UniOpVV.broadcastU8, dst, src);
      cc.emit2v(UniOpVV.broadcastU16, dst, src);
      cc.emit2v(UniOpVV.broadcastU32, dst, src);
      cc.emit2v(UniOpVV.broadcastU64, dst, src);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();
      expect(code.isFinalized, isTrue);
    });

    test('SIMD Arithmetic & Logic', () {
      final a = cc.newXmm("a");
      final b = cc.newXmm("b");
      final dst = cc.newXmm("dst");

      // Integer
      cc.emit3v(UniOpVVV.addU32, dst, a, b);
      cc.emit3v(UniOpVVV.subU32, dst, a, b);
      cc.emit3v(UniOpVVV.mulU32, dst, a, b);

      // Floating Point
      cc.emit3v(UniOpVVV.addF32, dst, a, b);
      cc.emit3v(UniOpVVV.mulF64, dst, a, b);

      // Logic
      cc.emit3v(UniOpVVV.andU32, dst, a, b);
      cc.emit3v(UniOpVVV.xorU64, dst, a, b);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();
      expect(code.isFinalized, isTrue);
    });
    test('SIMD Min/Max', () {
      final a = cc.newXmm("a");
      final b = cc.newXmm("b");
      final dst = cc.newXmm("dst");

      cc.emit3v(UniOpVVV.minI32, dst, a, b);
      cc.emit3v(UniOpVVV.minU32, dst, a, b);
      cc.emit3v(UniOpVVV.maxI32, dst, a, b);
      cc.emit3v(UniOpVVV.maxU32, dst, a, b);

      cc.ret();
      cc.endFunc();
      cc.finalize();
      code.finalize();
      expect(code.isFinalized, isTrue);
    });
  });
}
