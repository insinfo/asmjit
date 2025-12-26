/// ASMTK - Assembler Toolkit for AsmJit Dart
///
/// Port of the ASMTK library from C++ to Dart.
/// Provides assembly text parsing capabilities.

/// Token types for assembly parsing.
enum AsmTokenType {
  /// End of input.
  end,

  /// Newline.
  newline,

  /// Symbol/identifier (e.g., register name, instruction mnemonic).
  symbol,

  /// Numeric symbol (symbol starting with digit).
  numericSymbol,

  /// Unsigned 64-bit integer.
  u64,

  /// 64-bit floating point.
  f64,

  /// Left curly brace `{`.
  lCurl,

  /// Right curly brace `}`.
  rCurl,

  /// Left bracket `[`.
  lBracket,

  /// Right bracket `]`.
  rBracket,

  /// Left parenthesis `(`.
  lParen,

  /// Right parenthesis `)`.
  rParen,

  /// Plus sign `+`.
  add,

  /// Minus sign `-`.
  sub,

  /// Asterisk `*`.
  mul,

  /// Forward slash `/`.
  div,

  /// Comma `,`.
  comma,

  /// Colon `:`.
  colon,

  /// Other punctuation.
  other,

  /// Invalid token.
  invalid,
}

/// Represents a parsed token.
class AsmToken {
  AsmTokenType type;
  String text;
  int line;
  int column;

  /// Value for numeric tokens.
  int intValue;
  double floatValue;

  AsmToken({
    this.type = AsmTokenType.end,
    this.text = '',
    this.line = 1,
    this.column = 1,
    this.intValue = 0,
    this.floatValue = 0.0,
  });

  void reset() {
    type = AsmTokenType.end;
    text = '';
    intValue = 0;
    floatValue = 0.0;
  }

  /// Check if token text equals the given string (case-insensitive).
  bool isText(String s) => text.toLowerCase() == s.toLowerCase();

  /// Check if this is an end-of-input or newline token.
  bool get isEndOrNewline =>
      type == AsmTokenType.end || type == AsmTokenType.newline;

  @override
  String toString() => 'AsmToken($type, "$text", line:$line, col:$column)';
}

/// Parse flags for the tokenizer.
class ParseFlags {
  /// No special flags.
  static const int none = 0;

  /// Don't parse numbers, always parse as symbols.
  static const int parseSymbol = 1 << 0;

  /// Include dashes in symbol names.
  static const int includeDashes = 1 << 1;
}

/// Character classification for tokenization.
enum _CharKind {
  digit0,
  digit1,
  digit2,
  digit3,
  digit4,
  digit5,
  digit6,
  digit7,
  digit8,
  digit9,
  hexA,
  hexB,
  hexC,
  hexD,
  hexE,
  hexF,
  alphaG,
  alphaH,
  alphaI,
  alphaJ,
  alphaK,
  alphaL,
  alphaM,
  alphaN,
  alphaO,
  alphaP,
  alphaQ,
  alphaR,
  alphaS,
  alphaT,
  alphaU,
  alphaV,
  alphaW,
  alphaX,
  alphaY,
  alphaZ,
  underscore,
  dot,
  symbol,
  dollar,
  dash,
  punctuation,
  space,
  extended,
  invalid,
}

/// Assembly tokenizer - parses assembly source into tokens.
class AsmTokenizer {
  String _source;
  int _pos = 0;
  int _line = 1;
  int _column = 1;
  AsmToken? _putBack;

  /// Character map for quick classification.
  static final List<_CharKind> _charMap = _buildCharMap();

  static List<_CharKind> _buildCharMap() {
    final map = List<_CharKind>.filled(256, _CharKind.invalid);

    // Whitespace
    map[0x09] = _CharKind.space; // tab
    map[0x0A] = _CharKind.space; // newline
    map[0x0B] = _CharKind.space; // vtab
    map[0x0C] = _CharKind.space; // form feed
    map[0x0D] = _CharKind.space; // carriage return
    map[0x20] = _CharKind.space; // space

    // Punctuation
    for (var c in '!"#%&\'()*+,-./:;<=>?[\\]^`{|}~'.codeUnits) {
      map[c] = _CharKind.punctuation;
    }

    // Special punctuation
    map[0x24] = _CharKind.dollar; // $
    map[0x2D] = _CharKind.dash; // -
    map[0x2E] = _CharKind.dot; // .
    map[0x40] = _CharKind.symbol; // @
    map[0x5F] = _CharKind.underscore; // _

    // Digits 0-9
    for (var i = 0; i <= 9; i++) {
      map[0x30 + i] = _CharKind.values[i]; // digit0..digit9
    }

    // Uppercase A-F (hex)
    for (var i = 0; i < 6; i++) {
      map[0x41 + i] = _CharKind.values[10 + i]; // hexA..hexF
    }
    // Uppercase G-Z
    for (var i = 6; i < 26; i++) {
      map[0x41 + i] = _CharKind.values[10 + i]; // alphaG..alphaZ
    }

    // Lowercase a-f (hex)
    for (var i = 0; i < 6; i++) {
      map[0x61 + i] = _CharKind.values[10 + i]; // hexA..hexF
    }
    // Lowercase g-z
    for (var i = 6; i < 26; i++) {
      map[0x61 + i] = _CharKind.values[10 + i]; // alphaG..alphaZ
    }

    // Extended ASCII
    for (var i = 128; i < 256; i++) {
      map[i] = _CharKind.extended;
    }

    return map;
  }

  AsmTokenizer([String source = '']) : _source = source;

  /// Set the input source.
  void setInput(String source) {
    _source = source;
    _pos = 0;
    _line = 1;
    _column = 1;
    _putBack = null;
  }

  /// Put a token back so it will be returned on next call to next().
  void putBack(AsmToken token) {
    _putBack = token;
  }

  /// Check if we've reached end of input.
  bool get isEnd => _pos >= _source.length;

  /// Current character code or -1 if at end.
  int get _cur => _pos < _source.length ? _source.codeUnitAt(_pos) : -1;

  /// Peek ahead n characters.
  int _peek(int offset) {
    final pos = _pos + offset;
    return pos < _source.length ? _source.codeUnitAt(pos) : -1;
  }

  /// Advance position and update line/column.
  void _advance([int count = 1]) {
    for (var i = 0; i < count && _pos < _source.length; i++) {
      if (_source.codeUnitAt(_pos) == 0x0A) {
        _line++;
        _column = 1;
      } else {
        _column++;
      }
      _pos++;
    }
  }

  /// Get character kind for a code unit.
  _CharKind _kindOf(int c) {
    if (c < 0 || c >= 256) return _CharKind.invalid;
    return _charMap[c];
  }

  /// Check if character kind represents a digit.
  bool _isDigit(_CharKind k) => k.index <= _CharKind.digit9.index;

  /// Check if character kind represents a hex digit.
  bool _isHexDigit(_CharKind k) => k.index <= _CharKind.hexF.index;

  /// Check if character kind can be part of a symbol.
  bool _isSymbolChar(_CharKind k, {bool includeDash = false}) {
    if (k.index <= _CharKind.alphaZ.index) return true;
    if (k == _CharKind.underscore || k == _CharKind.dollar) return true;
    if (k == _CharKind.dot) return true;
    if (includeDash && k == _CharKind.dash) return true;
    return false;
  }

  /// Parse the next token.
  AsmToken next({int flags = ParseFlags.none}) {
    // Return put-back token if available
    if (_putBack != null) {
      final token = _putBack!;
      _putBack = null;
      return token;
    }

    // Skip whitespace (except newlines)
    while (!isEnd) {
      final c = _cur;
      if (c == 0x0A) {
        // Newline - return it as a token
        final token = AsmToken(
          type: AsmTokenType.newline,
          text: '\n',
          line: _line,
          column: _column,
        );
        _advance();
        return token;
      }
      if (c == 0x20 || c == 0x09 || c == 0x0D) {
        _advance();
        continue;
      }
      break;
    }

    if (isEnd) {
      return AsmToken(type: AsmTokenType.end, line: _line, column: _column);
    }

    final startLine = _line;
    final startColumn = _column;
    final startPos = _pos;

    final c = _cur;
    final kind = _kindOf(c);

    // Skip comments
    if (c == 0x3B) {
      // ; comment
      while (!isEnd && _cur != 0x0A) {
        _advance();
      }
      return next(flags: flags);
    }
    if (c == 0x2F && _peek(1) == 0x2F) {
      // // comment
      while (!isEnd && _cur != 0x0A) {
        _advance();
      }
      return next(flags: flags);
    }
    if (c == 0x23) {
      // # comment
      while (!isEnd && _cur != 0x0A) {
        _advance();
      }
      return next(flags: flags);
    }

    // Parse $ prefix (hex number or symbol)
    if (c == 0x24) {
      _advance();
      if (!isEnd && _isHexDigit(_kindOf(_cur))) {
        // $hexnumber
        return _parseHexNumber(startPos, startLine, startColumn);
      }
      // $ followed by symbol
      return _parseSymbol(startPos, startLine, startColumn, flags);
    }

    // Parse . prefix (directive or local label)
    if (c == 0x2E) {
      _advance();
      return _parseSymbol(startPos, startLine, startColumn, flags);
    }

    // Parse number
    if ((flags & ParseFlags.parseSymbol) == 0 && _isDigit(kind)) {
      return _parseNumber(startPos, startLine, startColumn);
    }

    // Parse symbol
    if (_isSymbolChar(kind)) {
      return _parseSymbol(startPos, startLine, startColumn, flags);
    }

    // Parse punctuation
    _advance();
    final text = _source.substring(startPos, _pos);

    AsmTokenType type;
    switch (c) {
      case 0x7B:
        type = AsmTokenType.lCurl;
      case 0x7D:
        type = AsmTokenType.rCurl;
      case 0x5B:
        type = AsmTokenType.lBracket;
      case 0x5D:
        type = AsmTokenType.rBracket;
      case 0x28:
        type = AsmTokenType.lParen;
      case 0x29:
        type = AsmTokenType.rParen;
      case 0x2B:
        type = AsmTokenType.add;
      case 0x2D:
        type = AsmTokenType.sub;
      case 0x2A:
        type = AsmTokenType.mul;
      case 0x2F:
        type = AsmTokenType.div;
      case 0x2C:
        type = AsmTokenType.comma;
      case 0x3A:
        type = AsmTokenType.colon;
      default:
        type = AsmTokenType.other;
    }

    return AsmToken(
      type: type,
      text: text,
      line: startLine,
      column: startColumn,
    );
  }

  /// Parse a symbol/identifier.
  AsmToken _parseSymbol(
      int startPos, int startLine, int startColumn, int flags) {
    final includeDash = (flags & ParseFlags.includeDashes) != 0;

    while (!isEnd) {
      final kind = _kindOf(_cur);
      if (!_isSymbolChar(kind, includeDash: includeDash)) break;
      _advance();
    }

    return AsmToken(
      type: AsmTokenType.symbol,
      text: _source.substring(startPos, _pos),
      line: startLine,
      column: startColumn,
    );
  }

  /// Parse a number (decimal, hex, octal, binary).
  AsmToken _parseNumber(int startPos, int startLine, int startColumn) {
    var value = 0;
    var base = 10;
    final firstChar = _cur;

    _advance();

    // Check for 0x, 0b, 0o prefix
    if (firstChar == 0x30 && !isEnd) {
      final second = _cur;
      if (second == 0x78 || second == 0x58) {
        // 0x - hex
        _advance();
        base = 16;
      } else if (second == 0x62 || second == 0x42) {
        // 0b - binary
        _advance();
        base = 2;
      } else if (second == 0x6F || second == 0x4F) {
        // 0o - octal
        _advance();
        base = 8;
      } else if (_isDigit(_kindOf(second))) {
        // Octal (legacy)
        base = 8;
        value = firstChar - 0x30;
      } else {
        value = 0;
      }
    } else {
      value = firstChar - 0x30;
    }

    // Parse digits
    while (!isEnd) {
      final c = _cur;
      final kind = _kindOf(c);

      int digit;
      if (_isDigit(kind)) {
        digit = c - 0x30;
      } else if (_isHexDigit(kind)) {
        digit = kind.index; // hexA=10, hexB=11, etc.
      } else if (kind == _CharKind.underscore) {
        // Allow _ as separator
        _advance();
        continue;
      } else {
        break;
      }

      if (digit >= base) break;

      value = value * base + digit;
      _advance();
    }

    // Check for h/o/q/b suffix (MASM style)
    if (!isEnd) {
      final c = _cur;
      if (c == 0x68 || c == 0x48) {
        // h - hex suffix
        _advance();
        // Reparse as hex
        final text = _source.substring(startPos, _pos - 1);
        value = int.tryParse(text, radix: 16) ?? 0;
      } else if (c == 0x6F || c == 0x4F || c == 0x71 || c == 0x51) {
        // o/q - octal suffix
        _advance();
        final text = _source.substring(startPos, _pos - 1);
        value = int.tryParse(text, radix: 8) ?? 0;
      } else if (c == 0x62 || c == 0x42) {
        // b - binary suffix (only if not followed by more alnum)
        final next = _peek(1);
        if (next == -1 || !_isSymbolChar(_kindOf(next))) {
          _advance();
          final text = _source.substring(startPos, _pos - 1);
          value = int.tryParse(text, radix: 2) ?? 0;
        }
      }
    }

    return AsmToken(
      type: AsmTokenType.u64,
      text: _source.substring(startPos, _pos),
      line: startLine,
      column: startColumn,
      intValue: value,
    );
  }

  /// Parse a hexadecimal number (after $ prefix).
  AsmToken _parseHexNumber(int startPos, int startLine, int startColumn) {
    var value = 0;

    while (!isEnd) {
      final kind = _kindOf(_cur);
      if (!_isHexDigit(kind)) break;

      value = value * 16 + kind.index;
      _advance();
    }

    return AsmToken(
      type: AsmTokenType.u64,
      text: _source.substring(startPos, _pos),
      line: startLine,
      column: startColumn,
      intValue: value,
    );
  }

  /// Tokenize entire input and return list of tokens.
  List<AsmToken> tokenizeAll() {
    final tokens = <AsmToken>[];
    while (true) {
      final token = next();
      tokens.add(token);
      if (token.type == AsmTokenType.end) break;
    }
    return tokens;
  }
}
