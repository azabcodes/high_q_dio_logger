import 'dart:math' as math;

enum LogLevel { trace, debug, info, warning, error }

enum LogOutputFormat { pretty, json }

enum LogCategory { network, auth, cache, analytics, general }

abstract class LogFilter {
  bool shouldLog(LogLevel level, LogContext context);
}

class DefaultLogFilter implements LogFilter {
  const DefaultLogFilter();

  @override
  bool shouldLog(LogLevel level, LogContext context) => true;
}

class SamplingLogFilter implements LogFilter {
  final double samplingRate; // e.g. 0.1 for 10%
  final math.Random _random;

  SamplingLogFilter(this.samplingRate, {math.Random? random})
    : _random = random ?? math.Random();

  @override
  bool shouldLog(LogLevel level, LogContext context) {
    if (level == LogLevel.error) return true; // always log errors
    return _random.nextDouble() < samplingRate;
  }
}

abstract class LogSerializer {
  bool canSerialize(dynamic value);
  dynamic serialize(dynamic value);
}

class DefaultLogSerializer implements LogSerializer {
  const DefaultLogSerializer();

  @override
  bool canSerialize(dynamic value) {
    return value is DateTime || value is Uri;
  }

  @override
  dynamic serialize(dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Uri) return value.toString();
    return value;
  }
}

abstract class LogEnricher {
  void enrich(LogContext context, Map<String, dynamic> metadata);
}

class LogRequest {
  final String id;
  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> extra;
  final dynamic body;
  final DateTime startedAt;

  // Correlation tracking
  final String? traceId;
  final String? spanId;
  final String? sessionId;
  final LogCategory category;

  LogRequest({
    required this.id,
    required this.method,
    required this.uri,
    required Map<String, dynamic> headers,
    required Map<String, dynamic> queryParameters,
    required Map<String, dynamic> extra,
    this.body,
    required this.startedAt,
    this.traceId,
    this.spanId,
    this.sessionId,
    this.category = LogCategory.network,
  }) : headers = Map.unmodifiable(headers),
       queryParameters = Map.unmodifiable(queryParameters),
       extra = Map.unmodifiable(extra);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'method': method,
      'uri': uri.toString(),
      'headers': headers.map((k, v) => MapEntry(k, v?.toString())),
      'queryParameters': queryParameters.map(
        (k, v) => MapEntry(k, v?.toString()),
      ),
      'extra': extra.map((k, v) => MapEntry(k, v?.toString())),
      'body': body?.toString(),
      'startedAt': startedAt.toIso8601String(),
      'traceId': traceId,
      'spanId': spanId,
      'sessionId': sessionId,
      'category': category.name,
    };
  }
}

class LogResponse {
  final String id;
  final String method;
  final Uri uri;
  final int? statusCode;
  final String? statusMessage;
  final Map<String, List<String>> headers;
  final dynamic body;
  final DateTime endedAt;

  // Correlation tracking
  final String? traceId;
  final String? spanId;
  final String? sessionId;
  final LogCategory category;

  LogResponse({
    required this.id,
    required this.method,
    required this.uri,
    this.statusCode,
    this.statusMessage,
    required Map<String, dynamic> headers,
    this.body,
    required this.endedAt,
    this.traceId,
    this.spanId,
    this.sessionId,
    this.category = LogCategory.network,
  }) : headers = Map.unmodifiable(
         headers.map((k, v) {
           final list = v is List ? v.map((e) => e.toString()).toList() : [v.toString()];
           return MapEntry(k, List<String>.unmodifiable(list));
         }),
       );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'method': method,
      'uri': uri.toString(),
      'statusCode': statusCode,
      'statusMessage': statusMessage,
      'headers': headers,
      'body': body?.toString(),
      'endedAt': endedAt.toIso8601String(),
      'traceId': traceId,
      'spanId': spanId,
      'sessionId': sessionId,
      'category': category.name,
    };
  }
}

class LogError {
  final String id;
  final String type;
  final String? message;
  final int? statusCode;
  final String? statusMessage;
  final dynamic body;
  final Uri? uri;
  final DateTime endedAt;

  // Correlation tracking
  final String? traceId;
  final String? spanId;
  final String? sessionId;
  final LogCategory category;

  const LogError({
    required this.id,
    required this.type,
    this.message,
    this.statusCode,
    this.statusMessage,
    this.body,
    this.uri,
    required this.endedAt,
    this.traceId,
    this.spanId,
    this.sessionId,
    this.category = LogCategory.network,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'message': message,
      'statusCode': statusCode,
      'statusMessage': statusMessage,
      'body': body?.toString(),
      'uri': uri?.toString(),
      'endedAt': endedAt.toIso8601String(),
      'traceId': traceId,
      'spanId': spanId,
      'sessionId': sessionId,
      'category': category.name,
    };
  }
}

class LogContext {
  final LogRequest? request;
  final LogResponse? response;
  final LogError? error;
  final Map<String, dynamic> metadata;

  const LogContext({
    this.request,
    this.response,
    this.error,
    this.metadata = const {},
  });
}
