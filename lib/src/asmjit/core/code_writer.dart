/// AsmJit Code Writer
///
/// Minimal port of asmjit/core/codewriter.* that wraps a CodeHolder and
/// provides sequential byte emission.
// TODO concluir o port
import 'code_buffer.dart';
import 'code_holder.dart';

class CodeWriter {
  final CodeHolder code;
  Section _section;

  CodeWriter(this.code) : _section = code.text;

  /// Current section.
  Section get section => _section;

  /// Switch to a different section.
  void setSection(Section section) {
    _section = section;
  }

  /// Current offset in the active section.
  int get offset => _section.buffer.length;

  /// Access to the active buffer.
  CodeBuffer get buffer => _section.buffer;

  /// Emits raw bytes into the active section.
  void emitBytes(List<int> bytes) => buffer.emitBytes(bytes);

  /// Emits a single byte.
  void emit8(int value) => buffer.emit8(value);

  /// Emits a 16-bit value.
  void emit16(int value) => buffer.emit16(value);

  /// Emits a 32-bit value.
  void emit32(int value) => buffer.emit32(value);

  /// Emits a 64-bit value.
  void emit64(int value) => buffer.emit64(value);

  /// Clears the active section buffer.
  void reset() => buffer.clear();
}
