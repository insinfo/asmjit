/// AsmJit Environment
///
/// Represents the target environment for code generation.
/// Ported from asmjit/core/environment.h

import 'dart:io' show Platform;
import 'dart:typed_data' show Endian;

import 'arch.dart';

/// Represents the execution environment for code generation.
///
/// This class encapsulates all platform-specific information needed
/// for proper code generation, including architecture, ABI, and
/// operating system details.
class Environment {
  /// Target architecture.
  final Arch arch;

  /// Sub-architecture.
  final SubArch subArch;

  /// CPU vendor.
  final Vendor vendor;

  /// Target platform.
  final TargetPlatform platform;

  /// Platform ABI.
  final PlatformABI platformABI;

  /// Object format.
  final ObjectFormat objectFormat;

  /// Float ABI.
  final FloatABI floatABI;

  /// Byte order (endianness).
  final Endian endian;

  const Environment({
    required this.arch,
    this.subArch = SubArch.unknown,
    this.vendor = Vendor.unknown,
    this.platform = TargetPlatform.unknown,
    this.platformABI = PlatformABI.unknown,
    this.objectFormat = ObjectFormat.unknown,
    this.floatABI = FloatABI.hardFloat,
    this.endian = Endian.little,
  });

  /// Creates an environment for the host system.
  factory Environment.host() {
    return Environment(
      arch: Arch.host,
      subArch: SubArch.host,
      vendor: Vendor.host,
      platform: TargetPlatform.host,
      platformABI: PlatformABI.host,
      objectFormat: ObjectFormat.jit, // We're doing JIT
      floatABI: FloatABI.host,
      endian: Endian.host,
    );
  }

  /// Creates an x64 environment with SysV ABI (Linux/macOS).
  factory Environment.x64SysV() {
    return const Environment(
      arch: Arch.x64,
      platformABI: PlatformABI.sysv,
      objectFormat: ObjectFormat.jit,
    );
  }

  /// Creates an x64 environment with Windows ABI.
  factory Environment.x64Windows() {
    return const Environment(
      arch: Arch.x64,
      platform: TargetPlatform.windows,
      platformABI: PlatformABI.msvc,
      objectFormat: ObjectFormat.jit,
    );
  }

  /// Creates an AArch64 environment.
  factory Environment.aarch64() {
    return Environment(
      arch: Arch.aarch64,
      platformABI: PlatformABI.host,
      objectFormat: ObjectFormat.jit,
    );
  }

  /// Whether the environment is empty (uninitialized).
  bool get isEmpty => arch == Arch.unknown;

  /// Whether the environment is initialized.
  bool get isInitialized => arch != Arch.unknown;

  /// Whether this is a 32-bit environment.
  bool get is32Bit => arch.is32Bit;

  /// Whether this is a 64-bit environment.
  bool get is64Bit => arch.is64Bit;

  /// Architecture family.
  ArchFamily get archFamily => arch.family;

  /// Returns whether [arch] is valid.
  static bool isValidArch(Arch arch) => arch != Arch.unknown;

  /// Whether this is an x86 family environment.
  bool get isX86Family => arch.isX86Family;

  /// Whether this is an ARM family environment.
  bool get isArmFamily => arch.isArmFamily;

  /// Whether this is a big-endian environment.
  bool get isBigEndian => endian == Endian.big;

  /// Whether this is a little-endian environment.
  bool get isLittleEndian => endian == Endian.little;

  /// Returns the register size for this environment.
  int get registerSize => arch.registerSize;

  /// Returns the stack alignment for this environment.
  int get stackAlignment => arch.stackAlignment;

  /// Returns the calling convention for this environment.
  CallingConvention get callingConvention {
    // First check if we have explicit platform info
    if (arch == Arch.x64) {
      if (platformABI == PlatformABI.msvc ||
          platform == TargetPlatform.windows) {
        return CallingConvention.win64;
      }
      if (platformABI == PlatformABI.sysv ||
          platformABI == PlatformABI.gnu ||
          platformABI == PlatformABI.darwin) {
        return CallingConvention.sysV64;
      }
      // Fall back to host detection
      return PlatformABI.callingConventionFor(arch);
    }
    return PlatformABI.callingConventionFor(arch);
  }

  /// Returns the architecture traits for this environment.
  ArchTraits get traits => ArchTraits.forArch(arch);

  /// Creates a copy with modified fields.
  Environment copyWith({
    Arch? arch,
    SubArch? subArch,
    Vendor? vendor,
    TargetPlatform? platform,
    PlatformABI? platformABI,
    ObjectFormat? objectFormat,
    FloatABI? floatABI,
    Endian? endian,
  }) {
    return Environment(
      arch: arch ?? this.arch,
      subArch: subArch ?? this.subArch,
      vendor: vendor ?? this.vendor,
      platform: platform ?? this.platform,
      platformABI: platformABI ?? this.platformABI,
      objectFormat: objectFormat ?? this.objectFormat,
      floatABI: floatABI ?? this.floatABI,
      endian: endian ?? this.endian,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Environment &&
        other.arch == arch &&
        other.subArch == subArch &&
        other.vendor == vendor &&
        other.platform == platform &&
        other.platformABI == platformABI &&
        other.objectFormat == objectFormat &&
        other.floatABI == floatABI &&
        other.endian == endian;
  }

  @override
  int get hashCode => Object.hash(
        arch,
        subArch,
        vendor,
        platform,
        platformABI,
        objectFormat,
        floatABI,
        endian,
      );

  /// Returns the register size for [arch].
  static int regSizeOfArch(Arch arch) => arch.registerSize;

  /// Returns whether [arch] is a 32-bit architecture.
  static bool is32BitArch(Arch arch) => arch.is32Bit;

  @override
  String toString() {
    return 'Environment('
        'arch: $arch, '
        'platform: $platform, '
        'abi: $platformABI, '
        'endian: ${endian == Endian.little ? "little" : "big"}'
        ')';
  }
}

/// Target platform - the operating system.
enum TargetPlatform {
  /// Unknown or uninitialized platform.
  unknown,

  /// Windows.
  windows,

  /// Linux.
  linux,

  /// macOS (OSX).
  macos,

  /// iOS.
  ios,

  /// Android.
  android,

  /// FreeBSD.
  freeBsd,

  /// NetBSD.
  netBsd,

  /// OpenBSD.
  openBsd,

  /// Fuchsia.
  fuchsia,

  /// Other POSIX-like platform.
  other;

  /// Returns the host platform.
  static TargetPlatform get host {
    if (Platform.isWindows) return TargetPlatform.windows;
    if (Platform.isLinux) return TargetPlatform.linux;
    if (Platform.isMacOS) return TargetPlatform.macos;
    if (Platform.isIOS) return TargetPlatform.ios;
    if (Platform.isAndroid) return TargetPlatform.android;
    if (Platform.isFuchsia) return TargetPlatform.fuchsia;
    return TargetPlatform.other;
  }

  /// Whether this is a Windows platform.
  bool get isWindows => this == TargetPlatform.windows;

  /// Whether this is a POSIX-like platform.
  bool get isPosix => !isWindows && this != TargetPlatform.unknown;

  /// Whether this is an Apple platform.
  bool get isApple =>
      this == TargetPlatform.macos || this == TargetPlatform.ios;
}
