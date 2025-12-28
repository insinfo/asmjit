import 'dart:typed_data';

/// A simple bit vector implementation for register allocation.
class BitVector {
  final Uint32List _data;
  final int sizeInBits;

  BitVector(this.sizeInBits) : _data = Uint32List((sizeInBits + 31) ~/ 32);

  void clearAll() {
    _data.fillRange(0, _data.length, 0);
  }

  void setAll() {
    _data.fillRange(0, _data.length, 0xFFFFFFFF);
  }

  bool testBit(int idx) {
    if (idx < 0 || idx >= sizeInBits) return false;
    return (_data[idx >> 5] & (1 << (idx & 31))) != 0;
  }

  void setBit(int idx) {
    if (idx < 0 || idx >= sizeInBits) return;
    _data[idx >> 5] |= (1 << (idx & 31));
  }

  void clearBit(int idx) {
    if (idx < 0 || idx >= sizeInBits) return;
    _data[idx >> 5] &= ~(1 << (idx & 31));
  }

  void copyFrom(BitVector other) {
    assert(sizeInBits == other.sizeInBits);
    _data.setAll(0, other._data);
  }

  /// Combined OR operation: this |= other
  /// Returns true if this bit vector changed.
  bool or(BitVector other) {
    assert(sizeInBits == other.sizeInBits);
    bool changed = false;
    for (int i = 0; i < _data.length; i++) {
      final old = _data[i];
      final newValue = old | other._data[i];
      if (old != newValue) {
        _data[i] = newValue;
        changed = true;
      }
    }
    return changed;
  }

  /// Combined AND-NOT operation: this &= ~other
  void andNot(BitVector other) {
    assert(sizeInBits == other.sizeInBits);
    for (int i = 0; i < _data.length; i++) {
      _data[i] &= ~other._data[i];
    }
  }

  /// Intersection: this &= other
  void and(BitVector other) {
    assert(sizeInBits == other.sizeInBits);
    for (int i = 0; i < _data.length; i++) {
      _data[i] &= other._data[i];
    }
  }

  bool isEqual(BitVector other) {
    if (sizeInBits != other.sizeInBits) return false;
    for (int i = 0; i < _data.length; i++) {
      if (_data[i] != other._data[i]) return false;
    }
    return true;
  }

  Iterable<int> get setBits sync* {
    for (int i = 0; i < _data.length; i++) {
      int word = _data[i];
      if (word == 0) continue;
      for (int j = 0; j < 32; j++) {
        if ((word & (1 << j)) != 0) {
          final idx = (i << 5) + j;
          if (idx >= sizeInBits) break;
          yield idx;
        }
      }
    }
  }
}
