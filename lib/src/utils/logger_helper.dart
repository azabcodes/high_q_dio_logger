class LoggerHelper {
  /// Truncates a string to [maxLength] characters, appending '...' if it exceeds the limit.
  static String truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }
}
