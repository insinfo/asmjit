/// Prints the host environment as seen by asmjit (used by CI logs).
///
/// Usage: dart run tool/print_host_info.dart
import 'dart:ffi';
import 'dart:io';

import 'package:asmjit/asmjit.dart';

void main() {
  final env = Environment.host();
  stdout
    ..writeln('Dart:        ${Platform.version}')
    ..writeln('ABI:         ${Abi.current()}')
    ..writeln('Environment: $env')
    ..writeln('Executes:    ${env.arch} JIT code');
  if (env.isX86Family) {
    final cpu = CpuInfo.host();
    stdout
      ..writeln('CPU vendor:  ${cpu.vendor}')
      ..writeln('CPU brand:   ${cpu.brand}')
      ..writeln('AVX:         ${cpu.features.avx}')
      ..writeln('AVX2:        ${cpu.features.avx2}')
      ..writeln('AVX-512F:    ${cpu.features.avx512f}');
  }
}
