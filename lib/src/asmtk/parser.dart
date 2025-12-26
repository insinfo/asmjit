/// ASMTK Parser - Assembly text parser for AsmJit Dart
///
/// Parses assembly source code and emits instructions via X86Assembler.

import 'tokenizer.dart';
import '../x86/x86.dart';
import '../x86/x86_assembler.dart';
import '../x86/x86_operands.dart';
import '../x86/x86_simd.dart';
import '../core/code_holder.dart';
import '../core/labels.dart';

/// Parser error with line/column information.
class ParseError implements Exception {
  final String message;
  final int line;
  final int column;
  final String sourceText;

  ParseError(this.message, this.line, this.column, [this.sourceText = '']);

  @override
  String toString() {
    if (sourceText.isNotEmpty) {
      return 'ParseError: $message at line $line, column $column\n  $sourceText';
    }
    return 'ParseError: $message at line $line, column $column';
  }
}

/// Reference to a label for use in operands.
class LabelRef {
  final Label label;
  const LabelRef(this.label);
}

/// Assembly parser that converts text to machine code.
class AsmParser {
  final X86Assembler _asm;
  final AsmTokenizer _tokenizer;
  final Map<String, Label> _labels = {};
  final Map<String, Label> _localLabels = {};
  String? _currentGlobalLabel;

  AsmParser(this._asm) : _tokenizer = AsmTokenizer();

  /// Parse assembly source and emit instructions.
  void parse(String source) {
    _tokenizer.setInput(source);
    _labels.clear();
    _localLabels.clear();
    _currentGlobalLabel = null;

    while (true) {
      final token = _tokenizer.next();
      if (token.type == AsmTokenType.end) break;
      if (token.type == AsmTokenType.newline) continue;

      _parseCommand(token);
    }
  }

  /// Parse a single command (instruction or directive).
  void _parseCommand(AsmToken firstToken) {
    if (firstToken.type != AsmTokenType.symbol) {
      throw ParseError(
        'Expected instruction or label, got ${firstToken.type}',
        firstToken.line,
        firstToken.column,
        firstToken.text,
      );
    }

    // Check if this is a label (followed by colon)
    final next = _tokenizer.next();
    if (next.type == AsmTokenType.colon) {
      _defineLabel(firstToken.text, firstToken);
      return;
    }
    _tokenizer.putBack(next);

    // Parse instruction
    _parseInstruction(firstToken);
  }

  /// Define a label.
  void _defineLabel(String name, AsmToken token) {
    final isLocal = name.startsWith('.');

    if (isLocal) {
      if (_currentGlobalLabel == null) {
        throw ParseError(
          'Local label "$name" without preceding global label',
          token.line,
          token.column,
        );
      }
      final fullName = '$_currentGlobalLabel$name';
      final label = _getOrCreateLabel(fullName, isLocal: true);
      _asm.bind(label);
    } else {
      _currentGlobalLabel = name;
      _localLabels.clear();
      final label = _getOrCreateLabel(name, isLocal: false);
      _asm.bind(label);
    }
  }

  /// Get or create a label by name.
  Label _getOrCreateLabel(String name, {bool isLocal = false}) {
    final labels = isLocal ? _localLabels : _labels;
    return labels.putIfAbsent(name, () => _asm.newLabel());
  }

  /// Parse an instruction.
  void _parseInstruction(AsmToken mnemonicToken) {
    final mnemonic = mnemonicToken.text.toLowerCase();

    // Parse operands
    final operands = <Object>[];
    var token = _tokenizer.next();

    while (
        token.type != AsmTokenType.end && token.type != AsmTokenType.newline) {
      if (token.type == AsmTokenType.comma) {
        token = _tokenizer.next();
        continue;
      }

      final operand = _parseOperand(token);
      operands.add(operand);
      token = _tokenizer.next();
    }

    // Emit the instruction
    _emitInstruction(mnemonic, operands, mnemonicToken);
  }

  /// Parse a single operand.
  Object _parseOperand(AsmToken token) {
    switch (token.type) {
      case AsmTokenType.symbol:
        // Try register first
        final reg = _parseRegister(token.text);
        if (reg != null) return reg;

        // Check for memory size prefix
        final size = _parseMemorySize(token.text);
        if (size != null) {
          return _parseMemoryOperand(size);
        }

        // Must be a label reference
        return _getLabelRef(token.text);

      case AsmTokenType.u64:
        return token.intValue;

      case AsmTokenType.sub:
        final next = _tokenizer.next();
        if (next.type != AsmTokenType.u64) {
          throw ParseError(
            'Expected number after minus',
            next.line,
            next.column,
          );
        }
        return -next.intValue;

      case AsmTokenType.lBracket:
        return _parseMemoryOperand(0, bracketConsumed: true);

      default:
        throw ParseError(
          'Unexpected token type ${token.type}',
          token.line,
          token.column,
          token.text,
        );
    }
  }

  int? _parseMemorySize(String text) {
    switch (text.toLowerCase()) {
      case 'byte':
        return 1;
      case 'word':
        return 2;
      case 'dword':
        return 4;
      case 'qword':
        return 8;
      case 'xmmword':
      case 'oword':
        return 16;
      case 'ymmword':
        return 32;
      case 'zmmword':
        return 64;
      default:
        return null;
    }
  }

  X86Mem _parseMemoryOperand(int size, {bool bracketConsumed = false}) {
    var token = _tokenizer.next();

    if (!bracketConsumed) {
      // Skip 'ptr' if present
      if (token.type == AsmTokenType.symbol &&
          token.text.toLowerCase() == 'ptr') {
        token = _tokenizer.next();
      }

      // Expect '['
      if (token.type != AsmTokenType.lBracket) {
        throw ParseError(
          'Expected "[" in memory operand',
          token.line,
          token.column,
        );
      }
      token = _tokenizer.next();
    }

    X86Gp? base;
    X86Gp? index;
    int scale = 1;
    int disp = 0;
    bool isNegative = false;

    while (true) {
      if (token.type == AsmTokenType.rBracket) break;

      if (token.type == AsmTokenType.add) {
        isNegative = false;
        token = _tokenizer.next();
        continue;
      }

      if (token.type == AsmTokenType.sub) {
        isNegative = true;
        token = _tokenizer.next();
        continue;
      }

      if (token.type == AsmTokenType.mul) {
        token = _tokenizer.next();
        if (token.type != AsmTokenType.u64) {
          throw ParseError('Expected scale factor', token.line, token.column);
        }
        scale = token.intValue;
        token = _tokenizer.next();
        continue;
      }

      if (token.type == AsmTokenType.symbol) {
        final reg = _parseRegister(token.text);
        if (reg == null || reg is! X86Gp) {
          throw ParseError(
            'Unknown register: ${token.text}',
            token.line,
            token.column,
          );
        }

        final peek = _tokenizer.next();
        if (peek.type == AsmTokenType.mul) {
          index = reg;
          token = _tokenizer.next();
        } else {
          _tokenizer.putBack(peek);
          if (base == null) {
            base = reg;
          } else if (index == null) {
            index = reg;
          } else {
            throw ParseError(
              'Too many registers in memory operand',
              token.line,
              token.column,
            );
          }
          token = _tokenizer.next();
        }
        continue;
      }

      if (token.type == AsmTokenType.u64) {
        final value = isNegative ? -token.intValue : token.intValue;
        disp += value;
        isNegative = false;
        token = _tokenizer.next();
        continue;
      }

      throw ParseError(
        'Unexpected token in memory operand',
        token.line,
        token.column,
      );
    }

    if (base != null && index != null) {
      return X86Mem.baseIndexScale(base, index, scale, disp: disp, size: size);
    } else if (base != null) {
      return X86Mem.baseDisp(base, disp, size: size);
    } else if (index != null) {
      return X86Mem(index: index, scale: scale, displacement: disp, size: size);
    } else {
      return X86Mem.abs(disp, size: size);
    }
  }

  LabelRef _getLabelRef(String name) {
    final isLocal = name.startsWith('.');
    final fullName = isLocal && _currentGlobalLabel != null
        ? '$_currentGlobalLabel$name'
        : name;
    final label = _getOrCreateLabel(fullName, isLocal: isLocal);
    return LabelRef(label);
  }

  Object? _parseRegister(String name) {
    final lower = name.toLowerCase();

    // 64-bit GP registers
    switch (lower) {
      case 'rax':
        return rax;
      case 'rcx':
        return rcx;
      case 'rdx':
        return rdx;
      case 'rbx':
        return rbx;
      case 'rsp':
        return rsp;
      case 'rbp':
        return rbp;
      case 'rsi':
        return rsi;
      case 'rdi':
        return rdi;
      case 'r8':
        return r8;
      case 'r9':
        return r9;
      case 'r10':
        return r10;
      case 'r11':
        return r11;
      case 'r12':
        return r12;
      case 'r13':
        return r13;
      case 'r14':
        return r14;
      case 'r15':
        return r15;

      // 32-bit GP registers
      case 'eax':
        return eax;
      case 'ecx':
        return ecx;
      case 'edx':
        return edx;
      case 'ebx':
        return ebx;
      case 'esp':
        return esp;
      case 'ebp':
        return ebp;
      case 'esi':
        return esi;
      case 'edi':
        return edi;
      case 'r8d':
        return r8d;
      case 'r9d':
        return r9d;
      case 'r10d':
        return r10d;
      case 'r11d':
        return r11d;
      case 'r12d':
        return r12d;
      case 'r13d':
        return r13d;
      case 'r14d':
        return r14d;
      case 'r15d':
        return r15d;

      // 16-bit GP registers
      case 'ax':
        return ax;
      case 'cx':
        return cx;
      case 'dx':
        return dx;
      case 'bx':
        return bx;
      case 'sp':
        return sp;
      case 'bp':
        return bp;
      case 'si':
        return si;
      case 'di':
        return di;

      // 8-bit GP registers
      case 'al':
        return al;
      case 'cl':
        return cl;
      case 'dl':
        return dl;
      case 'bl':
        return bl;
      case 'ah':
        return ah;
      case 'ch':
        return ch;
      case 'dh':
        return dh;
      case 'bh':
        return bh;
      case 'spl':
        return spl;
      case 'bpl':
        return bpl;
      case 'sil':
        return sil;
      case 'dil':
        return dil;
      case 'r8b':
        return r8b;
      case 'r9b':
        return r9b;
      case 'r10b':
        return r10b;
      case 'r11b':
        return r11b;
      case 'r12b':
        return r12b;
      case 'r13b':
        return r13b;
      case 'r14b':
        return r14b;
      case 'r15b':
        return r15b;
    }

    // XMM registers
    if (lower.startsWith('xmm')) {
      final idx = int.tryParse(lower.substring(3));
      if (idx != null && idx >= 0 && idx <= 31) {
        return X86Xmm(idx);
      }
    }

    // YMM registers
    if (lower.startsWith('ymm')) {
      final idx = int.tryParse(lower.substring(3));
      if (idx != null && idx >= 0 && idx <= 31) {
        return X86Ymm(idx);
      }
    }

    return null;
  }

  X86Gp _asGp(Object op, AsmToken token) {
    if (op is X86Gp) return op;
    throw ParseError('Expected GP register', token.line, token.column);
  }

  int _asImm(Object op, AsmToken token) {
    if (op is int) return op;
    throw ParseError('Expected immediate value', token.line, token.column);
  }

  Label _asLabel(Object op, AsmToken token) {
    if (op is LabelRef) return op.label;
    throw ParseError('Expected label', token.line, token.column);
  }

  X86Mem _asMem(Object op, AsmToken token) {
    if (op is X86Mem) return op;
    throw ParseError('Expected memory operand', token.line, token.column);
  }

  void _emitInstruction(String mnemonic, List<Object> ops, AsmToken token) {
    try {
      switch (mnemonic) {
        // No operands
        case 'ret':
          _asm.ret();
        case 'nop':
          _asm.nop();
        case 'cdq':
          _asm.cdq();
        case 'cqo':
          _asm.cqo();
        case 'leave':
          _asm.leave();
        case 'int3':
          _asm.int3();
        case 'clc':
          _asm.clc();
        case 'stc':
          _asm.stc();
        case 'cmc':
          _asm.cmc();
        case 'cld':
          _asm.cld();
        case 'mfence':
          _asm.mfence();
        case 'sfence':
          _asm.sfence();
        case 'lfence':
          _asm.lfence();
        case 'pause':
          _asm.pause();

        // One GP operand
        case 'push':
          _asm.push(_asGp(ops[0], token));
        case 'pop':
          _asm.pop(_asGp(ops[0], token));
        case 'inc':
          _asm.inc(_asGp(ops[0], token));
        case 'dec':
          _asm.dec(_asGp(ops[0], token));
        case 'neg':
          _asm.neg(_asGp(ops[0], token));
        case 'not':
          _asm.not(_asGp(ops[0], token));
        case 'mul':
          _asm.mul(_asGp(ops[0], token));
        case 'div':
          _asm.div(_asGp(ops[0], token));
        case 'idiv':
          _asm.idiv(_asGp(ops[0], token));

        // Jump to label
        case 'jmp':
          if (ops[0] is LabelRef) {
            _asm.jmp(_asLabel(ops[0], token));
          } else if (ops[0] is X86Gp) {
            _asm.jmpR(_asGp(ops[0], token));
          }
        case 'call':
          if (ops[0] is LabelRef) {
            _asm.call(_asLabel(ops[0], token));
          } else if (ops[0] is X86Gp) {
            _asm.callR(_asGp(ops[0], token));
          }

        // Conditional jumps
        case 'je':
        case 'jz':
          _asm.je(_asLabel(ops[0], token));
        case 'jne':
        case 'jnz':
          _asm.jne(_asLabel(ops[0], token));
        case 'jl':
        case 'jnge':
          _asm.jl(_asLabel(ops[0], token));
        case 'jle':
        case 'jng':
          _asm.jle(_asLabel(ops[0], token));
        case 'jg':
        case 'jnle':
          _asm.jg(_asLabel(ops[0], token));
        case 'jge':
        case 'jnl':
          _asm.jge(_asLabel(ops[0], token));
        case 'jb':
        case 'jnae':
        case 'jc':
          _asm.jb(_asLabel(ops[0], token));
        case 'jbe':
        case 'jna':
          _asm.jbe(_asLabel(ops[0], token));
        case 'ja':
        case 'jnbe':
          _asm.ja(_asLabel(ops[0], token));
        case 'jae':
        case 'jnb':
        case 'jnc':
          _asm.jae(_asLabel(ops[0], token));

        // SETcc
        case 'sete':
        case 'setz':
          _asm.sete(_asGp(ops[0], token));
        case 'setne':
        case 'setnz':
          _asm.setne(_asGp(ops[0], token));
        case 'setl':
          _asm.setl(_asGp(ops[0], token));
        case 'setg':
          _asm.setg(_asGp(ops[0], token));

        // Two operand - MOV
        case 'mov':
          final dst = ops[0];
          final src = ops[1];
          if (dst is X86Gp && src is X86Gp) {
            _asm.movRR(dst, src);
          } else if (dst is X86Gp && src is int) {
            if (dst.bits == 64) {
              _asm.movRI64(dst, src);
            } else {
              _asm.movRI32(dst, src);
            }
          } else if (dst is X86Gp && src is X86Mem) {
            _asm.movRM(dst, src);
          } else if (dst is X86Mem && src is X86Gp) {
            _asm.movMR(dst, src);
          } else {
            throw ParseError('Invalid MOV operands', token.line, token.column);
          }

        // LEA
        case 'lea':
          _asm.lea(_asGp(ops[0], token), _asMem(ops[1], token));

        // Two operand - ALU register,register or register,imm
        case 'add':
          if (ops[1] is int) {
            _asm.addRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else {
            _asm.addRR(_asGp(ops[0], token), _asGp(ops[1], token));
          }
        case 'sub':
          if (ops[1] is int) {
            _asm.subRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else {
            _asm.subRR(_asGp(ops[0], token), _asGp(ops[1], token));
          }
        case 'and':
          _asm.andRR(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'or':
          _asm.orRR(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'xor':
          _asm.xorRR(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmp':
          if (ops[1] is int) {
            _asm.cmpRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else {
            _asm.cmpRR(_asGp(ops[0], token), _asGp(ops[1], token));
          }
        case 'test':
          _asm.testRR(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'imul':
          if (ops.length == 1) {
            _asm.mul(_asGp(ops[0], token));
          } else {
            _asm.imulRR(_asGp(ops[0], token), _asGp(ops[1], token));
          }
        case 'xchg':
          _asm.xchg(_asGp(ops[0], token), _asGp(ops[1], token));

        // Shift instructions
        case 'shl':
          if (ops[1] is int) {
            _asm.shlRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else if (ops[1] is X86Gp && (ops[1] as X86Gp).id == cl.id) {
            _asm.shlRCl(_asGp(ops[0], token));
          }
        case 'shr':
          if (ops[1] is int) {
            _asm.shrRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else if (ops[1] is X86Gp && (ops[1] as X86Gp).id == cl.id) {
            _asm.shrRCl(_asGp(ops[0], token));
          }
        case 'sar':
          if (ops[1] is int) {
            _asm.sarRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else if (ops[1] is X86Gp && (ops[1] as X86Gp).id == cl.id) {
            _asm.sarRCl(_asGp(ops[0], token));
          }
        case 'rol':
          _asm.rolRI(_asGp(ops[0], token), _asImm(ops[1], token));
        case 'ror':
          _asm.rorRI(_asGp(ops[0], token), _asImm(ops[1], token));

        // CMOVcc
        case 'cmove':
        case 'cmovz':
          _asm.cmove(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmovne':
        case 'cmovnz':
          _asm.cmovne(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmovl':
          _asm.cmovl(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmovle':
          _asm.cmovle(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmovg':
          _asm.cmovg(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmovge':
          _asm.cmovge(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmovb':
          _asm.cmovb(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'cmova':
          _asm.cmova(_asGp(ops[0], token), _asGp(ops[1], token));

        // Bit manipulation
        case 'bsf':
          _asm.bsf(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'bsr':
          _asm.bsr(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'popcnt':
          _asm.popcnt(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'lzcnt':
          _asm.lzcnt(_asGp(ops[0], token), _asGp(ops[1], token));
        case 'tzcnt':
          _asm.tzcnt(_asGp(ops[0], token), _asGp(ops[1], token));

        // Carry operations
        case 'adc':
          if (ops[1] is int) {
            _asm.adcRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else {
            _asm.adcRR(_asGp(ops[0], token), _asGp(ops[1], token));
          }
        case 'sbb':
          if (ops[1] is int) {
            _asm.sbbRI(_asGp(ops[0], token), _asImm(ops[1], token));
          } else {
            _asm.sbbRR(_asGp(ops[0], token), _asGp(ops[1], token));
          }

        default:
          throw ParseError(
            'Unknown instruction: $mnemonic',
            token.line,
            token.column,
          );
      }
    } catch (e) {
      if (e is ParseError) rethrow;
      throw ParseError(
        'Error emitting $mnemonic: $e',
        token.line,
        token.column,
      );
    }
  }
}

/// Convenience function to assemble a string.
CodeHolder assembleString(String source) {
  final code = CodeHolder();
  final asm = X86Assembler(code);
  final parser = AsmParser(asm);
  parser.parse(source);
  return code;
}
