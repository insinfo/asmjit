import 'dart:ffi';
import 'dart:io';
import 'package:asmjit/asmjit.dart';
import 'package:ffi/ffi.dart' as pkgffi;

void main() {
  final runtime = JitRuntime();
  final code = CodeHolder(env: runtime.environment);
  code.logger = FileLogger(stdout);
  final cc = UniCompiler.auto(code: code);

  // void func(int* dst, int* src)
  // dst[0] = src[0] << 1;

  cc.addFunc(
    FuncSignature.build(
      [TypeId.intPtr, TypeId.intPtr],
      TypeId.void_,
      CallConvId.x64SystemV,
    ),
  );

  final dst = Platform.isWindows ? rcx : rdi;
  final src = Platform.isWindows ? rdx : rsi;

  // vmovdqu xmm1, [src]
  cc.cc.addNode(InstNode(X86InstId.kVmovdqu, [xmm1, X86Mem.ptr(src)]));

  // vpslld xmm0, xmm1, 1
  cc.cc.addNode(InstNode(X86InstId.kVpslld, [xmm0, xmm1, Imm(1)]));

  // vmovdqu [dst], xmm0
  cc.cc.addNode(InstNode(X86InstId.kVmovdqu, [X86Mem.ptr(dst), xmm0]));

  // Explicit ret
  cc.cc.addNode(InstNode(X86InstId.kRet, []));

  cc.endFunc();

  final asm = X86Assembler(code);
  cc.cc.serializeToAssembler(asm);

  print('Code size before add: ${code.text.buffer.length}');
  print('Bytes: ${code.text.buffer.bytes.sublist(0, code.text.buffer.length)}');
  final fp = runtime.add(code);
  final funcPtr = Pointer<
      NativeFunction<
          Void Function(
              Pointer<Int32>, Pointer<Int32>)>>.fromAddress(fp.address);
  final funcDart =
      funcPtr.asFunction<void Function(Pointer<Int32>, Pointer<Int32>)>();

  final dataIn = pkgffi.calloc<Int32>(4);
  final dataOut = pkgffi.calloc<Int32>(4);

  dataIn[0] = 10;
  dataIn[1] = 20;
  dataIn[2] = 30;
  dataIn[3] = 40;

  funcDart(dataOut, dataIn);

  print('In:  ${dataIn[0]}, ${dataIn[1]}, ${dataIn[2]}, ${dataIn[3]}');
  print('Out: ${dataOut[0]}, ${dataOut[1]}, ${dataOut[2]}, ${dataOut[3]}');

  if (dataOut[0] == 20) {
    print('SUCCESS: vpslld works');
  } else {
    print('FAILURE: vpslld failed. Expected 20, got ${dataOut[0]}');
  }
}
