# HighQ Dio Logger

A high-fidelity, highly configurable, and premium network logging interceptor for Dio. It provides pretty-printed, colorized console output, structured JSON export, token-bucket rate limiting, automatic PII sanitization, cURL generation, batching, and dynamic metadata enrichment.

## Features

- **Consolidated Unified Exports**: Clean library structure exporting all API components via a single entrypoint.
- **Pretty Boxed Console Formatting**: Sophisticated ASCII boxing with responsive grid widths and customizable ANSI color levels.
- **Structured JSON Logging**: Switch between human-readable pretty print and single-line structured JSON logs for production ingestion.
- **Sensitive Data Sanitizer**: Automatic detection and redaction of PII (e.g. cookies, access tokens, passwords, authorization headers) with support for custom sanitization strategies.
- **cURL Command Generator**: Generate shell-escaped, fully sanitized cURL replicas for request debugging on the fly.
- **Enrichment & Correlation Pipelines**: Automatically inject correlation identifiers (`traceId`, `spanId`, `sessionId`) and custom metadata (e.g. app version, device info).
- **Token Bucket Rate Limiting**: Mitigate heavy traffic log flooding with token-bucket-based rate limit filters.
- **Observer Broadcaster**: Listen to network events (Request, Response, Error) with custom observers to easily forward logs to tools like Firebase, Sentry, or custom analytical backends.
- **Batching & Backpressure Queue**: Buffers logs and flushes them on size or time-based triggers with customizable backpressure strategies (e.g. drop oldest, drop newest).

---

## Getting Started

Add the package dependency to your project:

```bash
flutter pub add high_q_dio_logger
```

Or add it directly to your `pubspec.yaml`:

```yaml
dependencies:
  high_q_dio_logger: ^0.0.1
```

---

## Usage

### 1. Basic Setup

Simply add the interceptor to your `Dio` instance:

```dart
import 'package:dio/dio.dart';
import 'package:high_q_dio_logger/high_q_dio_logger.dart';

void main() {
  final dio = Dio();
  dio.interceptors.add(HighQDioLogger());
}
```

### 2. Advanced Configuration

Configure limits, filters, themes, and dynamic metadata:

```dart
final dio = Dio();

final config = HighQDioLoggerConfig(
  request: true,
  requestHeaders: true,
  requestBody: true,
  responseBody: true,
  responseHeaders: false,
  errors: true,
  maxDepth: 3,                   // Protects against deep recursion
  maxItemsPerLevel: 15,          // Limits collection log flooding
  maxStringLength: 200,          // Truncates long text payloads safely
  lineWidth: 90,                 // Line width boundaries
  enableColors: true,            // ANSI colorful output
  outputFormat: LogOutputFormat.pretty, // or LogOutputFormat.json
  
  // Custom enrichers
  enrichers: [
    MyCustomEnricher(),
  ],
  
  // Custom log evaluation filters
  filter: SamplingLogFilter(0.1), // Probabilistically log 10% of standard traffic
);

dio.interceptors.add(
  HighQDioLogger(
    config: config,
    // Direct log output to multiple destinations (console + local buffer file)
    printer: MultiHighQPrinter([
      const ConsoleHighQPrinter(),
      MemoryHighQPrinter(maxLogsLimit: 500),
    ]),
  ),
);
```

### 3. Custom Metadata Enricher

Implement the `LogEnricher` interface to inject runtime context:

```dart
class MyCustomEnricher implements LogEnricher {
  @override
  void enrich(LogContext context, Map<String, dynamic> metadata) {
    metadata['environment'] = 'production';
    metadata['app_version'] = '1.2.0';
  }
}
```

---

## Running the Example

Check out the interactive Flutter simulation project located under `/example`:

1. Change directory to `/example`
2. Run `flutter pub get`
3. Launch the app using `flutter run`
