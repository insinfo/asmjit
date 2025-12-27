/// AsmJit Formatter/Logger
///
/// Provides debugging utilities for code generation:
/// - Disassembly-like output
/// - Hex dump
/// - Instruction logging

import 'dart:io';
import 'dart:typed_data';

import '../x86/x86.dart';

/// Formatter for displaying generated code.
class AsmFormatter {
  /// Format a byte as two-digit hex.
  static String hex8(int value) {
    return (value & 0xFF).toRadixString(16).padLeft(2, '0');
  }

  /// Format a 16-bit value as hex.
  static String hex16(int value) {
    return (value & 0xFFFF).toRadixString(16).padLeft(4, '0');
  }

  /// Format a 32-bit value as hex.
  static String hex32(int value) {
    return (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  }

  /// Format a 64-bit value as hex.
  static String hex64(int value) {
    return value.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  /// Format an address with prefix.
  static String formatAddress(int address) {
    return '0x${address.toRadixString(16)}';
  }

  /// Format bytes as hex string.
  static String formatBytes(List<int> bytes, {String separator = ' '}) {
    return bytes.map((b) => hex8(b)).join(separator);
  }

  /// Format bytes as a hex dump with optional address.
  static String hexDump(
    Uint8List bytes, {
    int baseAddress = 0,
    int bytesPerLine = 16,
    bool showAscii = true,
  }) {
    final lines = <String>[];

    for (int i = 0; i < bytes.length; i += bytesPerLine) {
      final end = (i + bytesPerLine).clamp(0, bytes.length);
      final chunk = bytes.sublist(i, end);

      final address = hex64(baseAddress + i);

      final hexPart = chunk.map((b) => hex8(b)).join(' ');
      final padding = '   ' * (bytesPerLine - chunk.length);

      String line = '$address  $hexPart$padding';

      if (showAscii) {
        final ascii = chunk.map((b) {
          // Printable ASCII range
          return (b >= 0x20 && b <= 0x7E) ? String.fromCharCode(b) : '.';
        }).join();
        line = '$line  |$ascii|';
      }

      lines.add(line);
    }

    return lines.join('\n');
  }

  /// Format a register name.
  static String formatReg(X86Gp reg) {
    return reg.toString();
  }

  /// Format a simple instruction with operands.
  static String formatInstruction(String mnemonic, List<String> operands) {
    if (operands.isEmpty) {
      return mnemonic;
    }
    return '$mnemonic ${operands.join(', ')}';
  }
}

/// Logger for tracking code generation.
class AsmLogger {
  final List<LogEntry> _entries = [];
  bool _enabled = true;

  /// Enable or disable logging.
  bool get enabled => _enabled;
  set enabled(bool value) => _enabled = value;

  /// Number of log entries.
  int get length => _entries.length;

  /// Log an instruction.
  void logInstruction(
    int offset,
    List<int> bytes,
    String mnemonic, {
    List<String> operands = const [],
    String? comment,
  }) {
    if (!_enabled) return;

    _entries.add(LogEntry(
      kind: LogEntryKind.instruction,
      offset: offset,
      bytes: Uint8List.fromList(bytes),
      mnemonic: mnemonic,
      operands: operands,
      comment: comment,
    ));
  }

  /// Log a label binding.
  void logLabel(int offset, String name) {
    if (!_enabled) return;

    _entries.add(LogEntry(
      kind: LogEntryKind.label,
      offset: offset,
      bytes: Uint8List(0),
      mnemonic: name,
    ));
  }

  /// Log data (constant pool entry).
  void logData(int offset, List<int> bytes, String description) {
    if (!_enabled) return;

    _entries.add(LogEntry(
      kind: LogEntryKind.data,
      offset: offset,
      bytes: Uint8List.fromList(bytes),
      mnemonic: description,
    ));
  }

  /// Log a comment.
  void logComment(String comment) {
    if (!_enabled) return;

    _entries.add(LogEntry(
      kind: LogEntryKind.comment,
      offset: -1,
      bytes: Uint8List(0),
      comment: comment,
    ));
  }

  /// Clear all log entries.
  void clear() => _entries.clear();

  /// Get all entries.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Format the log as a string.
  String format({int maxBytesShown = 8}) {
    final lines = <String>[];

    for (final entry in _entries) {
      lines.add(entry.format(maxBytesShown: maxBytesShown));
    }

    return lines.join('\n');
  }

  @override
  String toString() => format();
}

/// Formatting flags for logger output.
class FormatFlags {
  static const int kNone = 0;
  static const int kMachineCode = 1 << 0;
  static const int kShowAliases = 1 << 1;
  static const int kExplainImms = 1 << 2;
  static const int kRegCasts = 1 << 3;
}

/// Base logger interface compatible with AsmJit-style logging.
abstract class BaseLogger {
  int flags = FormatFlags.kNone;

  void log(String message);
}

/// Logger that stores output in-memory.
class StringLogger extends BaseLogger {
  final StringBuffer _buffer = StringBuffer();

  @override
  void log(String message) {
    _buffer.writeln(message);
  }

  @override
  String toString() => _buffer.toString();

  /// Returns the logged data as a string.
  String data() => _buffer.toString();

  void clear() => _buffer.clear();
}

/// Logger that writes to an [IOSink].
class FileLogger extends BaseLogger {
  final IOSink _sink;

  FileLogger(this._sink);

  @override
  void log(String message) {
    _sink.writeln(message);
  }
}

/// Kind of log entry.
enum LogEntryKind {
  instruction,
  label,
  data,
  comment,
}

/// A single log entry.
class LogEntry {
  final LogEntryKind kind;
  final int offset;
  final Uint8List bytes;
  final String mnemonic;
  final List<String> operands;
  final String? comment;

  const LogEntry({
    required this.kind,
    required this.offset,
    required this.bytes,
    this.mnemonic = '',
    this.operands = const [],
    this.comment,
  });

  /// Format this entry as a string.
  String format({int maxBytesShown = 8}) {
    switch (kind) {
      case LogEntryKind.instruction:
        final offsetStr = offset >= 0 ? AsmFormatter.hex32(offset) : '        ';

        String bytesStr;
        if (bytes.length <= maxBytesShown) {
          bytesStr = AsmFormatter.formatBytes(bytes);
        } else {
          bytesStr =
              '${AsmFormatter.formatBytes(bytes.sublist(0, maxBytesShown))}...';
        }
        bytesStr = bytesStr.padRight(maxBytesShown * 3);

        final instr = AsmFormatter.formatInstruction(mnemonic, operands);

        if (comment != null) {
          return '$offsetStr  $bytesStr  $instr  ; $comment';
        }
        return '$offsetStr  $bytesStr  $instr';

      case LogEntryKind.label:
        final offsetStr = AsmFormatter.hex32(offset);
        return '$offsetStr                          $mnemonic:';

      case LogEntryKind.data:
        final offsetStr = AsmFormatter.hex32(offset);
        final bytesStr =
            AsmFormatter.formatBytes(bytes).padRight(maxBytesShown * 3);
        return '$offsetStr  $bytesStr  $mnemonic';

      case LogEntryKind.comment:
        return '                                    ; $comment';
    }
  }
}

/// Extension to add logging to a buffer size tracker.
extension LoggingExtension on AsmLogger {
  /// Creates a simple listing of instructions.
  String createListing(Uint8List code, {int baseAddress = 0}) {
    final lines = <String>[];
    lines.add('; AsmJit Generated Code');
    lines.add('; Base: ${AsmFormatter.formatAddress(baseAddress)}');
    lines.add('; Size: ${code.length} bytes');
    lines.add('');
    lines.add(format());
    return lines.join('\n');
  }
}
