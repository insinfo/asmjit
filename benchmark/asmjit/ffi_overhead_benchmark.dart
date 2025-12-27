import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

typedef _AddU32Native = ffi.Uint32 Function(ffi.Uint32, ffi.Uint32);
typedef _AddU32 = int Function(int, int);

typedef _SumU32Native = ffi.Uint64 Function(
  ffi.Pointer<ffi.Uint32>,
  ffi.Uint64,
);
typedef _SumU32 = int Function(ffi.Pointer<ffi.Uint32>, int);

typedef _FillU32Native = ffi.Void Function(
  ffi.Pointer<ffi.Uint32>,
  ffi.Uint64,
  ffi.Uint32,
);
typedef _FillU32 = void Function(ffi.Pointer<ffi.Uint32>, int, int);

typedef _PointerChaseNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Uint32>,
  ffi.Uint32,
  ffi.Uint64,
);
typedef _PointerChase = int Function(ffi.Pointer<ffi.Uint32>, int, int);

typedef _XorU8Native = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Uint64,
  ffi.Uint8,
);
typedef _XorU8 = void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
);

typedef _VirtualAllocNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void>,
  ffi.IntPtr,
  ffi.Uint32,
  ffi.Uint32,
);
typedef _VirtualAlloc = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
);

typedef _VirtualFreeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.IntPtr,
  ffi.Uint32,
);
typedef _VirtualFree = int Function(ffi.Pointer<ffi.Void>, int, int);

typedef _RtlMoveMemoryNative = ffi.Void Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  ffi.IntPtr,
);
typedef _RtlMoveMemory = void Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Void>,
  int,
);

class BenchResult {
  final String name;
  final int iterations;
  final double nsPerOp;
  final double mibPerSec;

  BenchResult(this.name, this.iterations, this.nsPerOp, this.mibPerSec);

  void print() {
    final ns = nsPerOp.toStringAsFixed(1).padLeft(8);
    final mib =
        mibPerSec > 0 ? mibPerSec.toStringAsFixed(1).padLeft(8) : '     N/A';
    stdout.writeln('  ${name.padRight(34)} | $ns ns/op | $mib MiB/s');
  }
}

BenchResult runBench(
  String name,
  int iterations,
  int bytesPerIter,
  void Function() fn,
) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    fn();
  }
  sw.stop();
  final totalNs = sw.elapsedMicroseconds * 1000.0;
  final nsPerOp = totalNs / iterations;
  final mibPerSec = bytesPerIter > 0
      ? (bytesPerIter * iterations) / (1024 * 1024) / (totalNs / 1e9)
      : 0.0;
  return BenchResult(name, iterations, nsPerOp, mibPerSec);
}

ffi.DynamicLibrary? _tryLoadBenchDll() {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  final sep = Platform.pathSeparator;
  final dllPath = '${scriptDir.path}${sep}native${sep}ffi_bench.dll';
  final file = File(dllPath);
  if (!file.existsSync()) {
    return null;
  }
  return ffi.DynamicLibrary.open(dllPath);
}

class Kernel32 {
  Kernel32()
      : virtualAlloc = ffi.DynamicLibrary.open('kernel32.dll')
            .lookupFunction<_VirtualAllocNative, _VirtualAlloc>('VirtualAlloc'),
        virtualFree = ffi.DynamicLibrary.open('kernel32.dll')
            .lookupFunction<_VirtualFreeNative, _VirtualFree>('VirtualFree'),
        rtlMoveMemory = ffi.DynamicLibrary.open('kernel32.dll')
            .lookupFunction<_RtlMoveMemoryNative, _RtlMoveMemory>(
                'RtlMoveMemory');

  // final ffi.DynamicLibrary _lib;
  final _VirtualAlloc virtualAlloc;
  final _VirtualFree virtualFree;
  final _RtlMoveMemory rtlMoveMemory;

  ffi.Pointer<ffi.Uint8> alloc(int bytes) {
    const memCommit = 0x1000;
    const memReserve = 0x2000;
    const pageReadWrite = 0x04;
    final ptr = virtualAlloc(
      ffi.nullptr,
      bytes,
      memCommit | memReserve,
      pageReadWrite,
    );
    if (ptr == ffi.nullptr) {
      throw StateError('VirtualAlloc failed');
    }
    return ptr.cast<ffi.Uint8>();
  }

  void free(ffi.Pointer<ffi.Uint8> ptr) {
    const memRelease = 0x8000;
    final res = virtualFree(ptr.cast(), 0, memRelease);
    if (res == 0) {
      throw StateError('VirtualFree failed');
    }
  }
}

void main(List<String> args) {
  final quick = args.contains('--quick');
  final iterations = quick ? 10000 : 200000;
  final copyIterations = quick ? 2000 : 20000;
  final xorIterations = quick ? 5000 : 50000;
  // Keep pointer-chase total steps bounded to avoid multi-minute runs.
  final chaseIterations = quick ? 100 : 300;
  final chaseSteps = quick ? 1 << 14 : 1 << 18;
  final len = 1 << 16; // 64 KiB
  final sumLen = 1 << 12; // 4096 u32
  final chaseLen = 1 << 16; // 65536 nodes
  final xorLen = 1024; // 1 KiB

  stdout.writeln('FFI Overhead Microbench (Dart vs C/OS)');
  stdout.writeln('Iterations: $iterations ${quick ? "(quick)" : ""}');
  stdout.writeln('');

  final kernel32 = Kernel32();

  // Dart buffers.
  final dartBytes = Uint8List(len);
  final dartBytesDst = Uint8List(len);
  for (var i = 0; i < dartBytes.length; i++) {
    dartBytes[i] = i & 0xFF;
  }

  // Native buffers for OS memcpy.
  final nativeSrc = kernel32.alloc(len);
  final nativeDst = kernel32.alloc(len);
  nativeSrc.asTypedList(len).setAll(0, dartBytes);

  // Native buffers for sum.
  final nativeU32 = kernel32.alloc(sumLen * 4).cast<ffi.Uint32>();
  final nativeU32List = nativeU32.asTypedList(sumLen);
  for (var i = 0; i < nativeU32List.length; i++) {
    nativeU32List[i] = i;
  }

  // Pointer chase data.
  final dartNext = Uint32List(chaseLen);
  for (var i = 0; i < chaseLen; i++) {
    dartNext[i] = (i * 65521 + 1) % chaseLen;
  }
  final nativeNext = kernel32.alloc(chaseLen * 4).cast<ffi.Uint32>();
  nativeNext.asTypedList(chaseLen).setAll(0, dartNext);

  // XOR buffers.
  final dartXorSrc = Uint8List(xorLen);
  final dartXorDst = Uint8List(xorLen);
  for (var i = 0; i < xorLen; i++) {
    dartXorSrc[i] = (i * 31) & 0xFF;
  }
  final nativeXorSrc = kernel32.alloc(xorLen);
  final nativeXorDst = kernel32.alloc(xorLen);
  nativeXorSrc.asTypedList(xorLen).setAll(0, dartXorSrc);

  // Load C helpers if available.
  final benchLib = _tryLoadBenchDll();
  _AddU32? addU32;
  _SumU32? sumU32;
  _FillU32? fillU32;
  _PointerChase? pointerChase;
  _XorU8? xorU8;
  if (benchLib != null) {
    addU32 = benchLib.lookupFunction<_AddU32Native, _AddU32>('add_u32');
    sumU32 = benchLib.lookupFunction<_SumU32Native, _SumU32>('sum_u32');
    fillU32 = benchLib.lookupFunction<_FillU32Native, _FillU32>('fill_u32');
    pointerChase = benchLib.lookupFunction<_PointerChaseNative, _PointerChase>(
        'pointer_chase_u32');
    xorU8 = benchLib.lookupFunction<_XorU8Native, _XorU8>('xor_u8');
  }

  // Dart add.
  var acc = 0;
  runBench('Dart add_u32 loop', iterations, 0, () {
    acc = (acc + 3) & 0xFFFFFFFF;
  }).print();

  if (addU32 != null) {
    runBench('FFI add_u32 loop', iterations, 0, () {
      acc = addU32!(acc, 3);
    }).print();
  } else {
    stdout.writeln(
        '  FFI add_u32 loop               | N/A (ffi_bench.dll missing)');
  }

  stdout.writeln('');

  // Dart sum.
  runBench('Dart sum_u32 (Uint32List)', iterations, sumLen * 4, () {
    var s = 0;
    for (var i = 0; i < sumLen; i++) {
      s += i;
    }
    acc = s;
  }).print();

  if (sumU32 != null) {
    runBench('FFI sum_u32 (C loop)', iterations, sumLen * 4, () {
      acc = sumU32!(nativeU32, sumLen);
    }).print();
  } else {
    stdout.writeln(
        '  FFI sum_u32 (C loop)            | N/A (ffi_bench.dll missing)');
  }

  if (fillU32 != null) {
    runBench('FFI fill_u32 (C loop)', iterations, sumLen * 4, () {
      fillU32!(nativeU32, sumLen, 0xA5A5A5A5);
    }).print();
  } else {
    stdout.writeln(
        '  FFI fill_u32 (C loop)           | N/A (ffi_bench.dll missing)');
  }

  stdout.writeln('');

  // Pointer chasing.
  runBench('Dart pointer chase (Uint32List)', chaseIterations, 0, () {
    var idx = 0;
    for (var i = 0; i < chaseSteps; i++) {
      idx = dartNext[idx];
    }
    acc = idx;
  }).print();

  if (pointerChase != null) {
    runBench('FFI pointer chase (C loop)', chaseIterations, 0, () {
      acc = pointerChase!(nativeNext, 0, chaseSteps);
    }).print();
  } else {
    stdout.writeln(
        '  FFI pointer chase (C loop)      | N/A (ffi_bench.dll missing)');
  }

  stdout.writeln('');

  // XOR block (AES-like simple kernel).
  runBench('Dart xor_u8 (1 KiB)', xorIterations, xorLen, () {
    for (var i = 0; i < xorLen; i++) {
      dartXorDst[i] = dartXorSrc[i] ^ 0x5A;
    }
  }).print();

  if (xorU8 != null) {
    runBench('FFI xor_u8 (1 KiB)', xorIterations, xorLen, () {
      xorU8!(nativeXorSrc, nativeXorDst, xorLen, 0x5A);
    }).print();
  } else {
    stdout.writeln(
        '  FFI xor_u8 (1 KiB)               | N/A (ffi_bench.dll missing)');
  }

  stdout.writeln('');

  // Dart copy.
  runBench('Dart memcpy (setAll)', copyIterations, len, () {
    dartBytesDst.setAll(0, dartBytes);
  }).print();

  // OS memcpy via FFI.
  runBench('FFI memcpy (RtlMoveMemory)', copyIterations, len, () {
    kernel32.rtlMoveMemory(
      nativeDst.cast(),
      nativeSrc.cast(),
      len,
    );
  }).print();

  kernel32.free(nativeSrc);
  kernel32.free(nativeDst);
  kernel32.free(nativeU32.cast());
  kernel32.free(nativeNext.cast());
  kernel32.free(nativeXorSrc);
  kernel32.free(nativeXorDst);

  // Use acc to avoid dead code elimination.
  if (acc == 0xFFFFFFFF) {
    stdout.writeln('');
  }
}
