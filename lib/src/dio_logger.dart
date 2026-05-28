import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:high_q_dio_logger/high_q_dio_logger.dart';

/// Keys used in RequestOptions.extra
const _timeStampKey = '_highq_dio_logger_timestamp';
const _requestIdKey = '_highq_dio_logger_request_id';
const _startedAtKey = '_highq_dio_logger_started_at';
const _traceIdKey = '_highq_dio_logger_trace_id';
const _spanIdKey = '_highq_dio_logger_span_id';
const _sessionIdKey = '_highq_dio_logger_session_id';

class HighQDioLogger extends Interceptor {
  final HighQDioLoggerConfig config;
  final HighQPrinter printer;
  final List<LogObserver> observers;
  final RateLimiter rateLimiter;

  // Custom callback for observer failures, falls back to FlutterError.reportError if null.
  final void Function(Object error, StackTrace? stack)? onObserverError;

  final bool enableLogPrint;

  // Legacy formatting options (kept for compatibility)
  final int maxWidth;
  final bool compact;

  late final HighQFormatter _formatter;

  HighQDioLogger({
    HighQDioLoggerConfig? config,
    HighQPrinter? printer,
    List<LogObserver>? observers,
    this.onObserverError,
    RateLimiter? rateLimiter,
    this.maxWidth = 90,
    this.compact = true,
    @Deprecated('Use HighQDioLoggerConfig.filter instead')
    bool Function(LogContext context)? filter,
    this.enableLogPrint = true,
  }) : config = config ?? const HighQDioLoggerConfig(),
       printer = printer ?? const ConsoleHighQPrinter(),
       observers = observers ?? const [],
       rateLimiter = rateLimiter ?? const NoOpRateLimiter(),
       _formatter = HighQFormatter(
         config: config ?? const HighQDioLoggerConfig(),
         printer: printer ?? const ConsoleHighQPrinter(),
       );

  void _handleObserverError(Object e, StackTrace s) {
    if (onObserverError != null) {
      onObserverError!(e, s);
    } else {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'highq_dio_logger',
          context: ErrorDescription(
            'HighQDioLogger observer notification failed',
          ),
        ),
      );
    }
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final stopwatch = Stopwatch()..start();
    options.extra[_timeStampKey] = stopwatch;

    final id = UuidProvider.next();
    options.extra[_requestIdKey] = id;

    final startedAt = DateTime.now();
    options.extra[_startedAtKey] = startedAt;

    final traceId =
        options.headers['x-trace-id']?.toString() ?? UuidProvider.next();
    options.extra[_traceIdKey] = traceId;

    final spanId =
        options.headers['x-span-id']?.toString() ?? UuidProvider.next();
    options.extra[_spanIdKey] = spanId;

    final sessionId = options.headers['x-session-id']?.toString();
    options.extra[_sessionIdKey] = sessionId;

    // Build the request model
    final logRequest = LogRequest(
      id: id,
      method: options.method,
      uri: options.uri,
      headers: options.headers,
      queryParameters: options.queryParameters,
      extra: options.extra,
      body: options.data,
      startedAt: startedAt,
      traceId: traceId,
      spanId: spanId,
      sessionId: sessionId,
      category: LogCategory.network,
    );

    // Dynamic metadata enrichment
    final metadataMap = <String, dynamic>{};
    final logContext = LogContext(request: logRequest, metadata: metadataMap);
    for (final enricher in config.enrichers) {
      try {
        enricher.enrich(logContext, metadataMap);
      } catch (e) {
        debugPrint('HighQDioLogger enricher error: $e');
      }
    }

    // Notify observers
    for (final observer in observers) {
      try {
        await observer.onRequest(logRequest);
      } catch (e, s) {
        _handleObserverError(e, s);
      }
    }

    // Rate Limiter, Production guard & LogFilter evaluation
    if (!kDebugMode ||
        !enableLogPrint ||
        !rateLimiter.shouldAllow() ||
        !config.filter.shouldLog(LogLevel.info, logContext)) {
      handler.next(options);
      return;
    }

    if (config.outputFormat == LogOutputFormat.json) {
      await printer.print(
        jsonEncode({
          'level': 'info',
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'request',
          'metadata': metadataMap,
          'data': logRequest.toJson(),
        }),
      );
    } else {
      await _formatter.formatRequest(logRequest);
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final stopwatch =
        response.requestOptions.extra[_timeStampKey] as Stopwatch?;
    final int elapsed = stopwatch?.elapsedMilliseconds ?? 0;
    final id = response.requestOptions.extra[_requestIdKey] as String? ?? '';
    final endedAt = DateTime.now();

    final traceId = response.requestOptions.extra[_traceIdKey] as String?;
    final spanId = response.requestOptions.extra[_spanIdKey] as String?;
    final sessionId = response.requestOptions.extra[_sessionIdKey] as String?;

    // Build response model
    final logResponse = LogResponse(
      id: id,
      method: response.requestOptions.method,
      uri: response.requestOptions.uri,
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: response.headers.map,
      body: response.data,
      endedAt: endedAt,
      traceId: traceId,
      spanId: spanId,
      sessionId: sessionId,
      category: LogCategory.network,
    );

    // Dynamic metadata enrichment
    final metadataMap = <String, dynamic>{};
    final logContext = LogContext(response: logResponse, metadata: metadataMap);
    for (final enricher in config.enrichers) {
      try {
        enricher.enrich(logContext, metadataMap);
      } catch (e) {
        debugPrint('HighQDioLogger enricher error: $e');
      }
    }

    // Notify observers
    for (final observer in observers) {
      try {
        await observer.onResponse(logResponse, elapsed);
      } catch (e, s) {
        _handleObserverError(e, s);
      }
    }

    // Rate Limiter, Production guard & LogFilter evaluation
    if (!kDebugMode ||
        !enableLogPrint ||
        !rateLimiter.shouldAllow() ||
        !config.filter.shouldLog(LogLevel.info, logContext)) {
      handler.next(response);
      return;
    }

    if (config.outputFormat == LogOutputFormat.json) {
      await printer.print(
        jsonEncode({
          'level': 'info',
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'response',
          'elapsedMs': elapsed,
          'metadata': metadataMap,
          'data': logResponse.toJson(),
        }),
      );
    } else {
      await _formatter.formatResponse(logResponse, elapsed);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final stopwatch = err.requestOptions.extra[_timeStampKey] as Stopwatch?;
    final int elapsed = stopwatch?.elapsedMilliseconds ?? 0;
    final id = err.requestOptions.extra[_requestIdKey] as String? ?? '';
    final endedAt = DateTime.now();

    final traceId = err.requestOptions.extra[_traceIdKey] as String?;
    final spanId = err.requestOptions.extra[_spanIdKey] as String?;
    final sessionId = err.requestOptions.extra[_sessionIdKey] as String?;

    // Build error model
    final logError = LogError(
      id: id,
      type: err.type.toString(),
      message: err.message,
      statusCode: err.response?.statusCode,
      statusMessage: err.response?.statusMessage,
      body: err.response?.data,
      uri: err.requestOptions.uri,
      endedAt: endedAt,
      traceId: traceId,
      spanId: spanId,
      sessionId: sessionId,
      category: LogCategory.network,
    );

    // Dynamic metadata enrichment
    final metadataMap = <String, dynamic>{};
    final logContext = LogContext(error: logError, metadata: metadataMap);
    for (final enricher in config.enrichers) {
      try {
        enricher.enrich(logContext, metadataMap);
      } catch (e) {
        debugPrint('HighQDioLogger enricher error: $e');
      }
    }

    // Notify observers
    for (final observer in observers) {
      try {
        await observer.onError(logError, elapsed);
      } catch (e, s) {
        _handleObserverError(e, s);
      }
    }

    // Rate Limiter, Production guard & LogFilter evaluation
    if (!kDebugMode ||
        !enableLogPrint ||
        !rateLimiter.shouldAllow() ||
        !config.filter.shouldLog(LogLevel.error, logContext)) {
      handler.next(err);
      return;
    }

    if (config.outputFormat == LogOutputFormat.json) {
      await printer.print(
        jsonEncode({
          'level': 'error',
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'error',
          'elapsedMs': elapsed,
          'metadata': metadataMap,
          'data': logError.toJson(),
        }),
      );
    } else {
      await _formatter.formatError(logError, elapsed);
    }
    handler.next(err);
  }
}
