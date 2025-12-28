import 'arch.dart';
import 'error.dart';
import 'globals.dart';
import 'operand.dart' show RegGroup;
import 'reg_utils.dart';
import 'support.dart';

/// Architecture-specific constraints used by the register allocator.
class RAConstraints {
  final List<RegMask> _availableRegs =
      List.filled(Globals.numVirtGroups, 0);

  /// Returns the available registers for [group].
  RegMask availableRegs(RegGroup group) => _availableRegs[group.index];

  /// Initializes constraints for the given [arch].
  AsmJitError init(Arch arch) {
    switch (arch) {
      case Arch.x86:
      case Arch.x64:
        final registerCount = arch == Arch.x86 ? 8 : 16;
        _availableRegs[RegGroup.gp.index] =
            lsbMask(registerCount) & ~bitMask(4);
        _availableRegs[RegGroup.vec.index] = lsbMask(registerCount);
        _availableRegs[RegGroup.mask.index] = lsbMask(8);
        _availableRegs[RegGroup.extra.index] = 0;
        return AsmJitError.ok;

      case Arch.aarch64:
        _availableRegs[RegGroup.gp.index] =
            0xFFFFFFFF & ~bitMaskRange(18, 14);
        _availableRegs[RegGroup.vec.index] = 0xFFFFFFFF;
        _availableRegs[RegGroup.mask.index] = 0;
        _availableRegs[RegGroup.extra.index] = 0;
        return AsmJitError.ok;

      default:
        return AsmJitError.invalidArch;
    }
  }
}
