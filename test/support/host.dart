import 'package:asmjit/asmjit.dart';

/// True when the test process runs on an x86-64 host.
final bool hostIsX64 = Environment.host().arch == Arch.x64;

/// `skip:` value for tests that execute JIT-compiled x86-64 machine code.
///
/// Running x86 code on a non-x86 host (e.g. macOS/Linux arm64) crashes or
/// hangs the test isolate, so these tests must be skipped there.
final Object skipUnlessX64Host =
    hostIsX64 ? false : 'requires an x86-64 host (executes x86 JIT code)';

/// True when the test process runs on an AArch64 host.
final bool hostIsA64 = Environment.host().arch == Arch.aarch64;

/// `skip:` value for tests that execute JIT-compiled AArch64 machine code.
final Object skipUnlessA64Host =
    hostIsA64 ? false : 'requires an AArch64 host (executes A64 JIT code)';

/// x86-64 environment for IR/encoding tests that build x86 code without
/// executing it: the host environment on x86-64 hosts, otherwise an x86-64
/// environment for the host OS (so ABI-dependent expectations still match).
Environment x64TestEnv() {
  if (hostIsX64) return Environment.host();
  return Environment.host().platform == TargetPlatform.windows
      ? Environment.x64Windows()
      : Environment.x64SysV();
}

/// Environment for portable (UniCompiler) IR tests that build code without
/// executing it: the host environment on AArch64 hosts, otherwise
/// [x64TestEnv] (so the tests also run on ia32, arm32, riscv64, ... hosts,
/// which UniCompiler does not target).
Environment ujitTestEnv() => hostIsA64 ? Environment.host() : x64TestEnv();

/// `skip:` value for tests that execute JIT code through the portable
/// UniCompiler path (x86-64 or AArch64 hosts).
final Object skipUnlessJitHost =
    hostIsX64 || hostIsA64 ? false : 'requires an x86-64 or AArch64 host';
