/// AsmJit Error Handling
///
/// Provides error codes and exception classes for AsmJit.
/// Ported from asmjit/core/globals.h

/// AsmJit error codes.
///
/// Matches the Error enum from globals.h
enum AsmJitError {
  /// No error (success).
  ok,

  /// Out of memory.
  outOfMemory,

  /// Invalid argument.
  invalidArgument,

  /// Invalid state.
  invalidState,

  /// Invalid architecture.
  invalidArch,

  /// The object is not initialized.
  notInitialized,

  /// Object already initialized.
  alreadyInitialized,

  /// Feature not enabled.
  featureNotEnabled,

  /// Too many handles (open or created) - cannot create more.
  tooManyHandles,

  /// Too large (code, move, etc).
  tooLarge,

  /// No code was generated.
  noCodeGenerated,

  /// Invalid directive.
  invalidDirective,

  /// Attempt to use uninitialized label.
  invalidLabel,

  /// Label index overflow.
  tooManyLabels,

  /// Label is already bound.
  labelAlreadyBound,

  /// Label is already defined (named labels).
  labelAlreadyDefined,

  /// Label name is too long.
  labelNameTooLong,

  /// Invalid label name.
  invalidLabelName,

  /// Invalid parent label.
  invalidParentLabel,

  /// Invalid section.
  invalidSection,

  /// Too many sections.
  tooManySections,

  /// Invalid section name.
  invalidSectionName,

  /// Too many relocations.
  tooManyRelocations,

  /// Invalid relocation entry.
  invalidRelocEntry,

  /// Relocation offset out of range.
  relocOffsetOutOfRange,

  /// Invalid assignment.
  invalidAssignment,

  /// Invalid instruction.
  invalidInstruction,

  /// Invalid register type.
  invalidRegType,

  /// Invalid register group.
  invalidRegGroup,

  /// Incompatible physical register.
  invalidPhysId,

  /// Overlapping virtual register.
  overlappedRegs,

  /// Overlapping operands.
  overlappingOperands,

  /// Invalid address format.
  invalidAddress,

  /// Invalid address index.
  invalidAddressIndex,

  /// Invalid address scale.
  invalidAddressScale,

  /// Invalid use of 64-bit address.
  invalidAddress64Bit,

  /// Invalid use of 64-bit address that require 32-bit zero-extension.
  invalidAddress64BitZeroExtension,

  /// Invalid displacement.
  invalidDisplacement,

  /// Invalid segment.
  invalidSegment,

  /// Invalid element index.
  invalidElementIndex,

  /// Invalid prefix combination.
  invalidPrefixCombination,

  /// Invalid LOCK prefix.
  invalidLockPrefix,

  /// Invalid XACQUIRE prefix.
  invalidXAcquirePrefix,

  /// Invalid XRELEASE prefix.
  invalidXReleasePrefix,

  /// Invalid REP prefix.
  invalidRepPrefix,

  /// Invalid REX prefix.
  invalidRexPrefix,

  /// Invalid extra register.
  invalidExtraReg,

  /// Invalid K register.
  invalidKMaskReg,

  /// Invalid K register use.
  invalidKZeroUse,

  /// Invalid broadcast.
  invalidBroadcast,

  /// Invalid embedded rounding.
  invalidEROrSAE,

  /// Invalid 8-bit immediate.
  invalid8BitImm,

  /// Invalid immediate.
  invalidImmediate,

  /// Invalid operand size.
  invalidOperandSize,

  /// Ambiguous operand size.
  ambiguousOperandSize,

  /// Mismatching operand size.
  operandSizeMismatch,

  /// Invalid option.
  invalidOption,

  /// Option already defined.
  optionAlreadyDefined,

  /// Invalid TypeId.
  invalidTypeId,

  /// Invalid use of GP pointer or base pointer.
  invalidUseOfGpbHi,

  /// Invalid use of GP 64-bit register in 32-bit mode.
  invalidUseOfGpq,

  /// Invalid use of F80 register.
  invalidUseOfF80,

  /// Not consecutive registers.
  notConsecutiveRegs,

  /// Illegal virtual register usage.
  illegalVirtReg,

  /// ABI changed during function translation.
  abiChanged,

  /// Unbound label cannot be evaluated by expression.
  expressionLabelNotBound,

  /// Arithmetic overflow during expression evaluation.
  expressionOverflow,

  /// Failed to open anonymous memory handle or file descriptor.
  failedToOpenAnonymousMemory,

  /// Failed to map virtual memory.
  failedToMapVirtMem,

  /// Unknown/generic error.
  unknown,
}

/// Exception thrown by AsmJit operations.
class AsmJitException implements Exception {
  /// The error code.
  final AsmJitError code;

  /// Human-readable error message.
  final String message;

  /// Optional cause exception.
  final Object? cause;

  const AsmJitException(this.code, this.message, [this.cause]);

  /// Creates a generic exception with just a message (code defaults to unknown).
  factory AsmJitException.generic(String message, [Object? cause]) =>
      AsmJitException(AsmJitError.unknown, message, cause);

  /// Creates an out-of-memory exception.
  factory AsmJitException.outOfMemory([String? details]) => AsmJitException(
        AsmJitError.outOfMemory,
        details ?? 'Out of memory',
      );

  /// Creates an invalid argument exception.
  factory AsmJitException.invalidArgument(String message) => AsmJitException(
        AsmJitError.invalidArgument,
        message,
      );

  /// Creates a feature not enabled exception.
  factory AsmJitException.featureNotEnabled(String feature) => AsmJitException(
        AsmJitError.featureNotEnabled,
        'Feature not enabled: $feature',
      );

  @override
  String toString() {
    final buffer = StringBuffer('AsmJitException[${code.name}]: $message');
    if (cause != null) {
      buffer.write(' (cause: $cause)');
    }
    return buffer.toString();
  }
}

/// Result type for operations that can fail.
///
/// Provides a Rust-like Result pattern for error handling.
class AsmResult<T> {
  final T? _value;
  final AsmJitException? _error;

  const AsmResult._(this._value, this._error);

  /// Creates a successful result.
  const AsmResult.ok(T value) : this._(value, null);

  /// Creates a failed result.
  const AsmResult.err(AsmJitException error) : this._(null, error);

  /// Whether this result is successful.
  bool get isOk => _error == null;

  /// Whether this result is an error.
  bool get isErr => _error != null;

  /// Gets the value if successful, or null otherwise.
  T? get value => _value;

  /// Gets the error if failed, or null otherwise.
  AsmJitException? get error => _error;

  /// Unwraps the value, throwing if this result is an error.
  T unwrap() {
    if (_error != null) throw _error;
    return _value as T;
  }

  /// Unwraps the value, returning a default if this result is an error.
  T unwrapOr(T defaultValue) {
    if (_error != null) return defaultValue;
    return _value as T;
  }

  /// Maps the value if successful, preserving errors.
  AsmResult<U> map<U>(U Function(T) transform) {
    if (_error != null) return AsmResult.err(_error);
    return AsmResult.ok(transform(_value as T));
  }

  /// Chains another operation that can fail.
  AsmResult<U> andThen<U>(AsmResult<U> Function(T) operation) {
    if (_error != null) return AsmResult.err(_error);
    return operation(_value as T);
  }
}
