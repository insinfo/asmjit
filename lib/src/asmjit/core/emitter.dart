/// AsmJit Emitter Infrastructure
///
/// Minimal stubs required by Blend2D pipeline integration.

import 'code_holder.dart';
import 'error.dart';
import 'formatter.dart';

/// Diagnostic options used by compiler/RA passes.
class DiagnosticOptions {
  static const int kNone = 0;
  static const int kValidateIntermediate = 1 << 0;
  static const int kRAAnnotate = 1 << 1;
}

/// Encoding options used by assemblers/compilers.
class EncodingOptions {
  static const int kNone = 0;
  static const int kOptimizeForSize = 1 << 0;
  static const int kOptimizedAlign = 1 << 1;
}

/// Error handler interface.
abstract class ErrorHandler {
  void handleError(AsmJitError err, String message, BaseEmitter? origin);
}

/// Base emitter class (assembler or compiler).
class BaseEmitter {
  final CodeHolder code;
  BaseLogger? logger;
  ErrorHandler? errorHandler;

  int encodingOptions = EncodingOptions.kNone;
  int diagnosticOptions = DiagnosticOptions.kNone;

  BaseEmitter(this.code);

  /// Sets a logger for formatted output.
  void setLogger(BaseLogger logger) {
    this.logger = logger;
  }

  /// Sets an error handler.
  void setErrorHandler(ErrorHandler handler) {
    errorHandler = handler;
  }

  /// Emits a log line if a logger is attached.
  void log(String message) {
    logger?.log(message);
  }

  /// Reports an error to the handler (if any).
  void reportError(AsmJitError err, String message) {
    errorHandler?.handleError(err, message, this);
  }
}
