/// Register type matching asmjit::RegType.
enum RegType {
  none(0),
  labelTag(1),
  gp8Lo(2),
  gp8Hi(3),
  gp16(4),
  gp32(5),
  gp64(6),
  vec8(7),
  vec16(8),
  vec32(9),
  vec64(10),
  vec128(11),
  vec256(12),
  vec512(13),
  vec1024(14),
  vecNLen(15),
  mask(16),
  tile(17),
  segment(25),
  control(26),
  debug(27),
  x86Mm(28),
  x86St(29),
  x86Bnd(30),
  pc(31);

  final int value;
  const RegType(this.value);

  static RegType fromValue(int value) {
    return values.firstWhere((e) => e.value == value,
        orElse: () => RegType.none);
  }
}
