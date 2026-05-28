import 'package:high_q_dio_logger/high_q_dio_logger.dart';

enum QueueBackpressureStrategy { dropOldest, dropNewest }

class HighQDioLoggerConfig {
  /// Whether to log request line.
  final bool request;

  /// Whether to log request headers.
  final bool requestHeaders;

  /// Whether to log request body.
  final bool requestBody;

  /// Whether to log response headers.
  final bool responseHeaders;

  /// Whether to log response body.
  final bool responseBody;

  /// Whether to log errors.
  final bool errors;

  /// Maximum recursion depth for JSON printing.
  final int maxDepth;

  /// Maximum items per level when printing collections.
  final int maxItemsPerLevel;

  /// Maximum string length before truncation.
  final int maxStringLength;

  /// Enables ANSI color output (if supported).
  final bool enableColors;

  /// Line width for printing (wraps lines).
  final int lineWidth;

  /// Customizable colors for request/response logs.
  final HighQTheme theme;

  /// Format of the log output: pretty or structured JSON
  final LogOutputFormat outputFormat;

  /// Customizable filter strategy to evaluate if a log should be printed
  final LogFilter filter;

  /// Custom serializers for payloads (binary, custom objects, etc.)
  final List<LogSerializer> serializers;

  /// Log enrichers to dynamically append context metrics
  final List<LogEnricher> enrichers;

  /// Backpressure strategy to enforce on Batching Printer when boundaries are hit
  final QueueBackpressureStrategy backpressureStrategy;

  const HighQDioLoggerConfig({
    this.request = true,
    this.requestHeaders = false,
    this.requestBody = false,
    this.responseHeaders = false,
    this.responseBody = true,
    this.errors = true,
    this.maxDepth = 5,
    this.maxItemsPerLevel = 20,
    this.maxStringLength = 200,
    this.enableColors = true,
    this.lineWidth = 90,
    this.theme = const HighQTheme(),
    this.outputFormat = LogOutputFormat.pretty,
    this.filter = const DefaultLogFilter(),
    this.serializers = const [DefaultLogSerializer()],
    this.enrichers = const [],
    this.backpressureStrategy = QueueBackpressureStrategy.dropOldest,
  });
}
