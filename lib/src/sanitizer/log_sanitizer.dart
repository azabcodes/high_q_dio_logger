/// Abstract sanitization layer for log values. Implementations can redact or transform
/// sensitive information (e.g., Authorization headers, cookies, passwords).
abstract class LogSanitizer {
  /// Returns a safe representation of a header/value pair.
  ///
  /// If the value should be redacted, return a placeholder such as '***'.
  /// Otherwise, return the original value.
  dynamic sanitize(String key, dynamic value);
}

/// Default implementation that redacts a small list of well‑known sensitive keys.
class DefaultLogSanitizer implements LogSanitizer {
  static const _sensitiveKeys = {
    'authorization',
    'cookie',
    'set-cookie',
    'token',
    'access-token',
    'refresh-token',
    'password',
  };

  @override
  dynamic sanitize(String key, dynamic value) {
    if (_sensitiveKeys.contains(key.trim().toLowerCase())) {
      return '***';
    }
    return value;
  }
}
