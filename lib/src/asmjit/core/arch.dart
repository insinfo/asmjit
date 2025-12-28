/// AsmJit Architecture Definitions
///
/// Ported from asmjit/core/archtraits.h and environment.h

import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'operand.dart';
import 'reg_type.dart';
import 'support.dart';

const Set<RegType> _archGpRegTypes = {
  RegType.gp8Lo,
  RegType.gp8Hi,
  RegType.gp16,
  RegType.gp32,
  RegType.gp64,
};

const Set<RegType> _archVecRegTypes = {
  RegType.vec128,
  RegType.vec256,
  RegType.vec512,
};

const Set<RegType> _archMaskRegTypes = {RegType.mask};

/// Architecture family.
enum ArchFamily {
  unknown(0),
  x86(1),
  arm(2),
  aarch64(3),
  riscv(4),
  mips(5),
  loongarch(6);

  final int value;
  const ArchFamily(this.value);
}

/// Machine architecture.
///
/// Corresponds to the Arch enum in environment.h
enum Arch {
  /// Unknown or uninitialized architecture.
  unknown(ArchFamily.unknown),

  /// 32-bit x86 architecture.
  x86(ArchFamily.x86),

  /// 64-bit x86 architecture (AMD64 / Intel64 / x86_64).
  x64(ArchFamily.x86),

  /// AArch64 architecture (64-bit ARM).
  aarch64(ArchFamily.aarch64),

  /// 32-bit ARM architecture (ARM32/ARMv7).
  arm(ArchFamily.arm),

  /// 32-bit RISC-V architecture.
  riscv32(ArchFamily.riscv),

  /// 64-bit RISC-V architecture.
  riscv64(ArchFamily.riscv),

  /// 32-bit MIPS architecture.
  mips32(ArchFamily.mips),

  /// 64-bit MIPS architecture.
  mips64(ArchFamily.mips),

  /// 32-bit LoongArch architecture.
  loongarch32(ArchFamily.loongarch),

  /// 64-bit LoongArch architecture.
  loongarch64(ArchFamily.loongarch);

  final ArchFamily family;
  const Arch(this.family);

  /// Whether this architecture is 32-bit.
  bool get is32Bit {
    switch (this) {
      case Arch.x86:
      case Arch.arm:
      case Arch.mips32:
      case Arch.riscv32:
      case Arch.loongarch32:
        return true;
      default:
        return false;
    }
  }

  /// Whether this architecture is 64-bit.
  bool get is64Bit => !is32Bit && this != Arch.unknown;

  /// Whether this is an x86 family architecture.
  bool get isX86Family => family == ArchFamily.x86;

  /// Whether this is an ARM family architecture.
  bool get isArmFamily =>
      family == ArchFamily.arm || family == ArchFamily.aarch64;

  /// Whether this is a RISC-V family architecture.
  bool get isRiscvFamily => family == ArchFamily.riscv;

  /// Whether this is a MIPS family architecture.
  bool get isMipsFamily => family == ArchFamily.mips;

  /// Returns the register size in bytes.
  int get registerSize => is64Bit ? 8 : 4;

  /// Returns the stack alignment.
  int get stackAlignment {
    switch (this) {
      case Arch.x64:
        return 16;
      case Arch.aarch64:
        return 16;
      default:
        return is64Bit ? 16 : (isX86Family ? 4 : 8);
    }
  }

  /// Returns the host architecture.
  static Arch get host {
    final abi = Abi.current();
    switch (abi) {
      case Abi.windowsX64:
      case Abi.linuxX64:
      case Abi.macosX64:
      case Abi.fuchsiaX64:
        return Arch.x64;
      case Abi.windowsArm64:
      case Abi.linuxArm64:
      case Abi.macosArm64:
      case Abi.fuchsiaArm64:
      case Abi.androidArm64:
      case Abi.iosArm64:
        return Arch.aarch64;
      case Abi.windowsIA32:
      case Abi.linuxIA32:
        return Arch.x86;
      case Abi.linuxArm:
      case Abi.androidArm:
        return Arch.arm;
      case Abi.linuxRiscv64:
      case Abi.fuchsiaRiscv64:
        return Arch.riscv64;
      case Abi.linuxRiscv32:
        return Arch.riscv32;
      default:
        return Arch.unknown;
    }
  }
}

/// Sub-architecture type.
enum SubArch {
  /// Unknown or undefined sub-arch.
  unknown,

  /// ARMv6 sub-architecture.
  armV6,

  /// ARMv7 sub-architecture.
  armV7,

  /// ARMv8 sub-architecture.
  armV8,

  /// RISC-V I extension.
  riscvI,

  /// Host sub-architecture.
  ;

  static SubArch get host => SubArch.unknown;
}

/// CPU vendor.
enum Vendor {
  /// Unknown or uninitialized vendor.
  unknown,

  /// Intel vendor.
  intel,

  /// AMD vendor.
  amd,

  /// Apple vendor.
  apple,

  /// ARM vendor.
  arm,

  /// Host vendor.
  ;

  static Vendor get host => Vendor.unknown;
}

/// Platform ABI (calling convention).
enum PlatformABI {
  /// Unknown ABI.
  unknown,

  /// Microsoft ABI (Windows).
  msvc,

  /// GNU ABI (Linux/GNU).
  gnu,

  /// Android ABI.
  android,

  /// Cygwin ABI.
  cygwin,

  /// Darwin ABI (macOS/iOS).
  darwin,

  /// System V ABI (standard UNIX).
  sysv;

  /// Returns the host platform ABI.
  static PlatformABI get host {
    if (Platform.isWindows) return PlatformABI.msvc;
    if (Platform.isMacOS || Platform.isIOS) return PlatformABI.darwin;
    if (Platform.isAndroid) return PlatformABI.android;
    if (Platform.isLinux || Platform.isFuchsia) return PlatformABI.gnu;
    return PlatformABI.unknown;
  }

  /// Gets the calling convention ABI for the architecture.
  ///
  /// - x64 on Windows → win64
  /// - x64 on other platforms → sysv
  /// - aarch64 → aapcs64
  /// - x86 → cdecl
  static CallingConvention callingConventionFor(Arch arch) {
    if (arch == Arch.x64) {
      return Platform.isWindows
          ? CallingConvention.win64
          : CallingConvention.sysV64;
    }
    if (arch == Arch.aarch64) {
      return CallingConvention.aapcs64;
    }
    if (arch == Arch.x86) {
      return CallingConvention.cdecl;
    }
    return CallingConvention.unknown;
  }
}

/// Object format.
enum ObjectFormat {
  /// Unknown or uninitialized format.
  unknown,

  /// JIT code generation.
  jit,

  /// ELF object format (Linux).
  elf,

  /// Mach-O object format (macOS/iOS).
  machO,

  /// PE/COFF object format (Windows).
  coff,

  /// Host object format.
  ;

  static ObjectFormat get host {
    if (Platform.isWindows) return ObjectFormat.coff;
    if (Platform.isMacOS || Platform.isIOS) return ObjectFormat.machO;
    if (Platform.isLinux || Platform.isAndroid) return ObjectFormat.elf;
    return ObjectFormat.unknown;
  }
}

/// Floating point ABI.
enum FloatABI {
  /// Soft float ABI (no FPU).
  softFloat,

  /// Hard float ABI (hardware FPU).
  hardFloat;

  static FloatABI get host => FloatABI.hardFloat;
}

/// Calling convention.
enum CallingConvention {
  /// Unknown calling convention.
  unknown,

  /// C declaration (x86).
  cdecl,

  /// Standard call (x86 Windows).
  stdcall,

  /// Fast call (x86 Windows).
  fastcall,

  /// This call (x86 Windows).
  thiscall,

  /// Microsoft x64 ABI (Windows x64).
  win64,

  /// System V AMD64 ABI (Unix x64).
  sysV64,

  /// ARM AAPCS (32-bit ARM).
  aapcs,

  /// ARM AAPCS64 (64-bit ARM).
  aapcs64,

  /// RISC-V calling convention.
  riscv,
}

/// Architecture traits - useful constants for a specific architecture.
class ArchTraits {
  /// The architecture these traits belong to.
  final Arch arch;

  /// Register size in bytes.
  final int registerSize;

  /// Stack pointer alignment.
  final int spAlignment;

  /// Minimum addressable unit (usually 1 byte).
  final int minAddressableUnit;

  /// Maximum instruction size.
  final int maxInstSize;

  /// Whether the architecture supports unaligned access.
  final bool supportsUnalignedAccess;

  /// Frame pointer register ID.
  final int fpRegId;

  /// Stack pointer register ID.
  final int spRegId;

  /// Register types supported by this architecture.
  final Set<RegType> supportedRegTypes;

  /// Register groups that support register swap instructions.
  final int regSwapMask;

  /// Frame pointer register ID.
  final int linkRegId;

  const ArchTraits({
    required this.arch,
    required this.registerSize,
    required this.spAlignment,
    this.minAddressableUnit = 1,
    required this.maxInstSize,
    this.supportsUnalignedAccess = true,
    this.fpRegId = -1,
    this.spRegId = -1,
    this.linkRegId = -1,
    this.supportedRegTypes = const {},
    this.regSwapMask = 0,
  });

  /// Tests whether the architecture provides the given register type.
  bool hasRegType(RegType type) => supportedRegTypes.contains(type);

  /// Tests whether the architecture exposes a register-swap instruction for [group].
  bool hasRegSwap(RegGroup group) => bitTest(regSwapMask, group.index);

  /// Returns whether the architecture has a link register.
  bool get hasLinkReg => linkRegId != -1;

  /// Returns whether the architecture has push/pop instructions for the given group.
  /// Only GP registers support push/pop on x86/x64.
  bool hasInstPushPop([RegGroup? group]) {
    if (arch != Arch.x86 && arch != Arch.x64) return false;
    // Only GP registers support push/pop
    if (group != null && group != RegGroup.gp) return false;
    return true;
  }

  /// Traits for x86 architecture.
  static const x86 = ArchTraits(
    arch: Arch.x86,
    registerSize: 4,
    spAlignment: 4,
    maxInstSize: 15, // x86 max instruction length
    supportsUnalignedAccess: true,
    fpRegId: 5,
    spRegId: 4,
    supportedRegTypes: {
      ..._archGpRegTypes,
      RegType.vec128,
      RegType.mask,
    },
    regSwapMask: 1,
  );

  /// Traits for x64 architecture.
  static const x64 = ArchTraits(
    arch: Arch.x64,
    registerSize: 8,
    spAlignment: 16,
    maxInstSize: 15, // x64 max instruction length
    supportsUnalignedAccess: true,
    fpRegId: 5,
    spRegId: 4,
    supportedRegTypes: {
      ..._archGpRegTypes,
      ..._archVecRegTypes,
      ..._archMaskRegTypes,
    },
    regSwapMask: 1,
  );

  /// Traits for AArch64 architecture.
  static const aarch64 = ArchTraits(
    arch: Arch.aarch64,
    registerSize: 8,
    spAlignment: 16,
    maxInstSize: 4,
    supportsUnalignedAccess: true,
    fpRegId: 29,
    spRegId: 31,
    linkRegId: 30,
    supportedRegTypes: {
      ..._archGpRegTypes,
      RegType.vec128,
    },
  );

  /// Traits for ARM32 architecture.
  static const arm = ArchTraits(
    arch: Arch.arm,
    registerSize: 4,
    spAlignment: 8,
    maxInstSize: 4, // ARM32 fixed instruction size
    supportsUnalignedAccess: false, // Depends on version
    supportedRegTypes: {
      ..._archGpRegTypes,
      RegType.vec128,
    },
  );

  /// Returns traits for the given architecture.
  static ArchTraits forArch(Arch arch) {
    switch (arch) {
      case Arch.x86:
        return x86;
      case Arch.x64:
        return x64;
      case Arch.aarch64:
        return aarch64;
      case Arch.arm:
        return arm;
      default:
        return ArchTraits(
          arch: arch,
          registerSize: arch.registerSize,
          spAlignment: arch.stackAlignment,
          maxInstSize: 4,
          supportedRegTypes: {..._archGpRegTypes},
        );
    }
  }

  /// Returns traits for the host architecture.
  static ArchTraits get host => forArch(Arch.host);
}
