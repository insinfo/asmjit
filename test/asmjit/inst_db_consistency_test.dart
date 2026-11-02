// Instruction databases are indexed by instruction id; the generator once
// emitted the x86 table in alphabetical order, so kX86InstDb[id] returned a
// different instruction (kMov -> 'bound'), breaking name-based checks such as
// the VEX detection in the register allocator.
import 'package:asmjit/asmjit.dart';
import 'package:test/test.dart';

void main() {
  test('kX86InstDb is indexed by X86InstId', () {
    for (int i = 0; i < kX86InstDb.length; i++) {
      expect(kX86InstDb[i].id, i, reason: 'entry $i (${kX86InstDb[i].name})');
    }
    expect(kX86InstDb[X86InstId.kMov].name, 'mov');
    expect(kX86InstDb[X86InstId.kPaddsb].name, 'paddsb');
    expect(kX86InstDb[X86InstId.kVpxor].name, 'vpxor');
  });

  test('kA64InstDb is indexed by A64InstId', () {
    expect(kA64InstDb[A64InstId.kMov].name, 'mov');
    expect(kA64InstDb[A64InstId.kLdr].name, 'ldr');
    expect(kA64InstDb[A64InstId.kFadd].name, 'fadd');
  });

  test('ArchTraits move/xchg ids match the generated databases', () {
    expect(ArchTraits.forArch(Arch.x64).movId, X86InstId.kMov);
    expect(ArchTraits.forArch(Arch.x64).xchgId, X86InstId.kXchg);
    expect(ArchTraits.forArch(Arch.aarch64).movId, A64InstId.kMov);
  });
}
