import 'dart:async';
import 'dart:math' as math;

import 'package:high_q_dio_logger/high_q_dio_logger.dart';

class HighQFormatter {
  final HighQDioLoggerConfig config;
  final HighQPrinter printer;
  final LogSanitizer sanitizer;
  final List<BodyFormatter> _bodyFormatters;
  final AnsiColor ansi;

  HighQFormatter({
    required this.config,
    required this.printer,
    LogSanitizer? sanitizer,
    List<BodyFormatter>? bodyFormatters,
  }) : sanitizer = sanitizer ?? DefaultLogSanitizer(),
       ansi = AnsiColor(enabled: config.enableColors, theme: config.theme),
       _bodyFormatters =
           bodyFormatters ??
           [
             JsonBodyFormatter(),
             Uint8ListBodyFormatter(),
             PlainTextBodyFormatter(),
           ];

  Future<void> formatRequest(LogRequest request) async {
    if (config.request) {
      await _printBoxed(
        header:
            '[Request [${request.id}] ║ ${request.method}] Query parameters=> ${request.queryParameters}',
        text: request.uri.toString(),
      );
    }
    if (config.requestHeaders) {
      await _printMapAsTable(
        request.queryParameters,
        header: 'Query Parameters',
      );
      final Map<String, dynamic> requestHeaders = <String, dynamic>{}
        ..addAll(request.headers);
      final sanitizedHeaders = requestHeaders.map(
        (k, v) => MapEntry(k, sanitizer.sanitize(k, v)),
      );
      await _printMapAsTable(sanitizedHeaders, header: 'Headers');
      final sanitizedExtras = request.extra.map(
        (k, v) => MapEntry(k, sanitizer.sanitize(k, v)),
      );
      await _printMapAsTable(sanitizedExtras, header: 'Extras');
    }
    if (config.requestBody && request.method != 'GET') {
      final data = request.body;
      if (data != null) {
        await _printBody(data, depth: 0, tab: 0);
      }
    }
  }

  Future<void> formatResponse(LogResponse response, int elapsedMs) async {
    await _printResponseHeader(response, elapsedMs);
    if (config.responseHeaders) {
      final Map<String, String> responseHeaders = <String, String>{};
      response.headers.forEach(
        (k, list) => responseHeaders[k] = list.toString(),
      );
      final sanitized = responseHeaders.map(
        (k, v) => MapEntry(k, sanitizer.sanitize(k, v)),
      );
      await _printMapAsTable(sanitized, header: 'Headers');
    }
    if (config.responseBody) {
      await printer.print('╔ ResponseBody');
      await printer.print('║');
      await _printBody(response.body, depth: 0, tab: 0);
      await printer.print('║');
      await _printLine('╚');
    }
  }

  Future<void> formatError(LogError error, int elapsedMs) async {
    if (!config.errors) return;
    await _printBoxed(
      header:
          'DioError [${error.id}] ║ Status: ${error.statusCode} , ${error.statusMessage} ║ Time: $elapsedMs ms',
      text: '${error.type}: ${error.message ?? ""}',
    );
    if (error.body != null) {
      await printer.print('╔ ErrorBody');
      await _printBody(error.body, depth: 0, tab: 0);
      await _printLine('╚');
    }
  }

  Future<void> _printBoxed({String? header, String? text}) async {
    await printer.print('');
    await _printLine('╔', '╗');
    if (header != null) await printer.print('║ $header');
    if (text != null) await printer.print('║  $text');
    await _printLine('╚');
  }

  Future<void> _printResponseHeader(
    LogResponse response,
    int responseTime,
  ) async {
    final uri = response.uri;
    final method = response.method;
    final timing = _timingColor(responseTime);
    await _printBoxed(
      header:
          'Response [${response.id}] ║ $method ║ Status: ${response.statusCode} ${response.statusMessage} ║ Time: $timing',
      text: uri.toString(),
    );
  }

  String _timingColor(int ms) {
    if (!config.enableColors) return '$ms ms';
    if (ms < 300) return ansi.green('$ms ms');
    if (ms < 1000) return ansi.yellow('$ms ms');
    return ansi.red('$ms ms');
  }

  Future<void> _printLine([String pre = '', String suf = '╝']) async =>
      await printer.print('$pre${'═' * config.lineWidth}$suf');

  Future<void> _printMapAsTable(
    Map<dynamic, dynamic>? map, {
    String? header,
  }) async {
    if (map == null || map.isEmpty) return;
    await printer.print('╔ $header');
    for (var entry in map.entries) {
      await _printKV(entry.key.toString(), entry.value);
    }
    await _printLine('╚');
  }

  Future<void> _printKV(String? key, Object? value) async {
    final pre = '╟ $key: ';
    final msg = value?.toString() ?? 'null';
    final maxWidth = config.lineWidth;
    if (pre.length + msg.length > maxWidth) {
      await printer.print(pre);
      await _printBlock(msg);
    } else {
      await printer.print('$pre$msg');
    }
  }

  Future<void> _printBlock(String msg) async {
    final truncated = LoggerHelper.truncate(msg, config.maxStringLength);
    final maxWidth = config.lineWidth;
    final lines = (truncated.length / maxWidth).ceil();
    for (var i = 0; i < lines; ++i) {
      final part = truncated.substring(
        i * maxWidth,
        math.min<int>(i * maxWidth + maxWidth, truncated.length),
      );
      await printer.print('║ $part');
    }
  }

  Future<void> _printBody(
    dynamic data, {
    required int depth,
    required int tab,
  }) async {
    final ctx = BodyFormatterContext(
      config: config,
      depth: depth,
      tab: tab,
      printer: printer,
      sanitizer: sanitizer,
    );
    for (var formatter in _bodyFormatters) {
      if (formatter.canHandle(data)) {
        await formatter.format(data, ctx);
        return;
      }
    }
    await _printBlock(data.toString());
  }
}
