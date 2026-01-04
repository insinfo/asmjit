import 'dart:ffi';
import 'dart:typed_data';
import '../../lib/asmjit.dart';
import 'package:ffi/ffi.dart' as ffi;
import '../../lib/src/asmjit/runtime/virtmem.dart';

void main() {
  // Manually create the instruction stream
  final buffer = CodeBuffer();
  final encoder = X86Encoder(buffer);
  
  // Prologue
  // mov rax, rcx (arg0 -> rax)
  encoder.movR64R64(rax, rcx);
  
  // Load data into xmm1
  // vmovdqu xmm1, [rax]
  encoder.vmovdquXmmMem(xmm1, ptr(rax));
  
  // vpsrld xmm1, xmm1, 1
  encoder.vpsrldXmmXmmImm8(xmm1, xmm1, 1);
  
  // Store result
  // vmovdqu [rax], xmm1
  encoder.vmovdquMemXmm(ptr(rax), xmm1);
  
  // Ret
  encoder.ret();
  
  print('Bytes: ${buffer.bytes}');
  
  // Allocate executable memory
  final size = buffer.bytes.length;
  // Align to page size (4096)
  final alignedSize = (size + 4095) & ~4095;
  
  final rwBlock = VirtMem.allocRW(alignedSize);
  VirtMem.writeBytes(rwBlock, buffer.bytes);
  final rxBlock = VirtMem.protectRX(rwBlock);
  VirtMem.flushInstructionCache(rxBlock.ptr.cast<Void>(), rxBlock.size);
  
  final execPtr = rxBlock.ptr;
  
  // Execute
  final func = execPtr.cast<NativeFunction<Void Function(Pointer<Uint32>)>>().asFunction<void Function(Pointer<Uint32>)>();
  
  final data = ffi.calloc<Uint32>(4);
  data[0] = 10;
  data[1] = 20;
  data[2] = 30;
  data[3] = 40;
  
  print('In:  ${data[0]}, ${data[1]}, ${data[2]}, ${data[3]}');
  func(data);
  print('Out: ${data[0]}, ${data[1]}, ${data[2]}, ${data[3]}');
  
  // Expected: 10>>1=5, 20>>1=10, 30>>1=15, 40>>1=20
  if (data[0] == 5 && data[1] == 10 && data[2] == 15 && data[3] == 20) {
    print('SUCCESS: vpsrld works');
  } else {
    print('FAILURE');
  }
  
  ffi.calloc.free(data);
}
