/// Base exception class for all TorrServer-related errors.
abstract class TorrServerException implements Exception {
  final String message;
  final dynamic cause;

  const TorrServerException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return '$runtimeType: $message (Cause: $cause)';
    }
    return '$runtimeType: $message';
  }
}

/// Thrown when TorrServer fails to start (e.g. process crash, FFI error, timeout).
class TorrServerStartException extends TorrServerException {
  const TorrServerStartException(super.message, [super.cause]);
}

/// Thrown when stopping TorrServer fails or times out.
class TorrServerStopException extends TorrServerException {
  const TorrServerStopException(super.message, [super.cause]);
}

/// Thrown when a free port cannot be found or the selected port fails to bind.
class TorrServerPortException extends TorrServerException {
  final int? port;
  const TorrServerPortException(super.message, [this.port, super.cause]);
}

/// Thrown when the native TorrServer executable/framework cannot be located.
class TorrServerBinaryNotFoundException extends TorrServerException {
  final String? path;
  const TorrServerBinaryNotFoundException(
    super.message, [
    this.path,
    super.cause,
  ]);
}

/// Thrown when the TorrServer process terminates unexpectedly.
class TorrServerProcessException extends TorrServerException {
  final int? exitCode;
  const TorrServerProcessException(super.message, [this.exitCode, super.cause]);
}

/// Thrown when an error occurs during Dart FFI/MethodChannel invocation on iOS.
class TorrServerFfiException extends TorrServerException {
  const TorrServerFfiException(super.message, [super.cause]);
}

/// Thrown when an HTTP request to TorrServer fails or returns a non-2xx status.
class TorrServerHttpException extends TorrServerException {
  final int statusCode;
  final String? responseBody;

  const TorrServerHttpException(
    super.message,
    this.statusCode, [
    this.responseBody,
  ]);

  @override
  String toString() =>
      'TorrServerHttpException: $message (Status: $statusCode, Response: $responseBody)';
}

/// Thrown when invalid torrent parameters are supplied (e.g. invalid magnet or empty torrent).
class TorrServerInvalidTorrentException extends TorrServerException {
  const TorrServerInvalidTorrentException(super.message, [super.cause]);
}
