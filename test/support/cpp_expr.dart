// Parser of the C++ call expressions used by the upstream assembler tests
// (`add(rcx, qword_ptr(rdx, rbx, 0, 128))`, `lock().add(...)`,
// `ldr(x0, ptr(x1, 8))`, `cset(x1, CondCode::kEQ)`).

/// Node of a parsed expression.
sealed class CppExpr {}

/// Identifier, possibly qualified (`CondCode::kEQ`).
final class CppIdent extends CppExpr {
  final String name;
  CppIdent(this.name);
  @override
  String toString() => name;
}

/// Integer literal (64-bit two's complement).
final class CppNum extends CppExpr {
  final int value;
  CppNum(this.value);
  @override
  String toString() => '$value';
}

/// Floating point literal.
final class CppDouble extends CppExpr {
  final double value;
  CppDouble(this.value);
  @override
  String toString() => '$value';
}

/// Call `name(args)`, or method call `receiver.name(args)`.
final class CppCall extends CppExpr {
  final CppExpr? receiver;
  final String name;
  final List<CppExpr> args;
  CppCall(this.receiver, this.name, this.args);
  @override
  String toString() =>
      '${receiver == null ? '' : '$receiver.'}$name(${args.join(', ')})';
}

class CppParseError implements Exception {
  final String message;
  CppParseError(this.message);
  @override
  String toString() => 'CppParseError: $message';
}

CppExpr parseCppExpr(String source) {
  final p = _Parser(source);
  final e = p.expr();
  p.skipSpaces();
  if (!p.atEnd) throw CppParseError('trailing input in "$source"');
  return e;
}

class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);

  bool get atEnd => i >= s.length;

  void skipSpaces() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  bool accept(String t) {
    skipSpaces();
    if (s.startsWith(t, i)) {
      i += t.length;
      return true;
    }
    return false;
  }

  void expect(String t) {
    if (!accept(t)) throw CppParseError('expected "$t" at $i in "$s"');
  }

  CppExpr expr() {
    var e = primary();
    while (accept('.')) {
      final name = ident();
      e = CppCall(e, name, args());
    }
    // Integer sums (`128 + 128`) are folded.
    while (accept('+')) {
      final r = primary();
      if (e is! CppNum || r is! CppNum) {
        throw CppParseError('"+" of non-numbers in "$s"');
      }
      e = CppNum(e.value + r.value);
    }
    return e;
  }

  List<CppExpr> args() {
    expect('(');
    final out = <CppExpr>[];
    if (accept(')')) return out;
    do {
      out.add(expr());
    } while (accept(','));
    expect(')');
    return out;
  }

  String ident() {
    skipSpaces();
    final start = i;
    while (i < s.length && RegExp(r'[A-Za-z0-9_]').hasMatch(s[i])) {
      i++;
    }
    if (start == i) throw CppParseError('expected identifier at $i in "$s"');
    return s.substring(start, i);
  }

  CppExpr primary() {
    skipSpaces();
    if (accept('(')) {
      final e = expr();
      expect(')');
      return e;
    }
    if (accept('-')) {
      final e = primary();
      if (e is CppDouble) return CppDouble(-e.value);
      if (e is! CppNum) throw CppParseError('"-" before a non-number in "$s"');
      return CppNum(-e.value);
    }
    if (i < s.length && RegExp(r'[0-9]').hasMatch(s[i])) return number();
    var name = ident();
    while (accept('::')) {
      name = '$name::${ident()}';
    }
    skipSpaces();
    if (i < s.length && s[i] == '(') return CppCall(null, name, args());
    return CppIdent(name);
  }

  CppExpr number() {
    final f = RegExp(r'[0-9]+\.[0-9]+').matchAsPrefix(s, i);
    if (f != null) {
      i = f.end;
      return CppDouble(double.parse(f.group(0)!));
    }
    final m = RegExp(r'(0[xX][0-9A-Fa-f]+|[0-9]+)([uU]?[lL]{0,2})')
        .matchAsPrefix(s, i)!;
    i = m.end;
    final text = m.group(1)!;
    final big = text.startsWith(RegExp('0[xX]'))
        ? BigInt.parse(text.substring(2), radix: 16)
        : BigInt.parse(text);
    return CppNum(big.toSigned(64).toInt());
  }
}
