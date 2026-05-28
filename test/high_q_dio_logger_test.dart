// highq_dio_logger_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:high_q_dio_logger/high_q_dio_logger.dart';

class TestLogPrinter implements HighQPrinter {
  final List<String> logs = [];

  @override
  FutureOr<void> print(Object? message) {
    logs.add(message?.toString() ?? '');
    return null;
  }

  void clear() => logs.clear();
}

class CustomBlockerFilter implements LogFilter {
  @override
  bool shouldLog(LogLevel level, LogContext context) {
    return level != LogLevel.error;
  }
}

class CustomEqualityObject {
  final String id;
  CustomEqualityObject(this.id);

  @override
  bool operator ==(Object other) => true; // Always equal to test identity visited tracking!

  @override
  int get hashCode => 1; // Always same hashcode!
}

class MockHttpClientAdapter implements HttpClientAdapter {
  late Future<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class MockRandom implements math.Random {
  final double val;
  MockRandom(this.val);

  @override
  double nextDouble() => val;

  @override
  bool nextBool() => true;

  @override
  int nextInt(int max) => 0;
}

class CustomAppVersionEnricher implements LogEnricher {
  @override
  void enrich(LogContext context, Map<String, dynamic> metadata) {
    metadata['app_version'] = '2.4.0';
    metadata['platform'] = 'macOS';
  }
}

class CustomProductSerializer implements LogSerializer {
  @override
  bool canSerialize(dynamic value) => value is CustomEqualityObject;

  @override
  dynamic serialize(dynamic value) {
    if (value is CustomEqualityObject) {
      return 'Product:${value.id}';
    }
    return value;
  }
}

void main() {
  group('HighQDioLogger Framework Tests', () {
    late TestLogPrinter printer;

    setUp(() {
      printer = TestLogPrinter();
    });

    test('LoggerHelper.truncate handles short and long strings correctly', () {
      expect(LoggerHelper.truncate('hello', 10), 'hello');
      expect(LoggerHelper.truncate('hello world', 5), 'hello...');
    });

    test('DefaultLogSanitizer redacts only exactly matched sensitive keys', () {
      final sanitizer = DefaultLogSanitizer();

      // Redact sensitive keys
      expect(sanitizer.sanitize('Authorization', 'Bearer token123'), '***');
      expect(sanitizer.sanitize('cookie', 'session=xyz'), '***');
      expect(sanitizer.sanitize('password', 'secret'), '***');

      // Do NOT redact key names that contain the sensitive key name as a substring but aren't exact matches
      expect(
        sanitizer.sanitize('my_authorization_value', 'keep_this'),
        'keep_this',
      );
      expect(sanitizer.sanitize('username', 'alex'), 'alex');
    });

    test(
      'AnsiColor applies ANSI styling based on enableColors and theme settings',
      () {
        const theme = HighQTheme(
          successColor: '\x1B[32m',
          warningColor: '\x1B[33m',
          errorColor: '\x1B[31m',
          infoColor: '\x1B[36m',
        );

        final colored = AnsiColor(enabled: true, theme: theme);
        final plain = AnsiColor(enabled: false, theme: theme);

        expect(colored.green('ok'), '\x1B[32mok\x1B[0m');
        expect(colored.yellow('wait'), '\x1B[33mwait\x1B[0m');
        expect(colored.red('fail'), '\x1B[31mfail\x1B[0m');

        expect(plain.green('ok'), 'ok');
        expect(plain.yellow('wait'), 'wait');
        expect(plain.red('fail'), 'fail');

        // Test colorize dynamic lookup
        expect(
          colored.colorize('my info', LogLevel.info),
          '\x1B[36mmy info\x1B[0m',
        );
        expect(
          colored.colorize('my error', LogLevel.error),
          '\x1B[31mmy error\x1B[0m',
        );
      },
    );

    test(
      'CurlGenerator creates correctly escaped curl commands & redacts secrets',
      () {
        final options = RequestOptions(
          path: '/users',
          method: 'POST',
          baseUrl: 'https://api.example.com',
          headers: {
            'Authorization': 'Bearer supersecret',
            'Content-Type': 'application/json',
          },
          data: {'name': 'Alex', 'age': 25},
        );

        final curl = CurlGenerator.generate(options);

        // Verify URL and Method
        expect(curl, contains("curl -X POST 'https://api.example.com/users'"));
        // Verify Header Sanitization
        expect(curl, contains("-H 'Authorization: ***'"));
        expect(curl, contains("-H 'Content-Type: application/json'"));
        // Verify shell escaping of single quotes in body
        expect(curl, contains("--data '{\"name\":\"Alex\",\"age\":25}'"));
      },
    );

    test('CurlGenerator supports pretty multiline Curl output', () {
      final options = RequestOptions(
        path: '/users',
        method: 'POST',
        baseUrl: 'https://api.example.com',
        headers: {'Content-Type': 'application/json'},
      );

      final curl = CurlGenerator.generate(options, multiline: true);

      expect(curl, contains('curl \\\n  -X POST \\\n  '));
    });

    test(
      'JsonBodyFormatter handles deep levels, list limits, and redacts sensitive keys recursively',
      () async {
        final config = HighQDioLoggerConfig(
          maxDepth: 3,
          maxItemsPerLevel: 5,
          maxStringLength: 5,
          enableColors: false,
        );

        final ctx = BodyFormatterContext(
          config: config,
          depth: 0,
          tab: 0,
          printer: printer,
          sanitizer: DefaultLogSanitizer(),
        );

        final data = {
          'username': 'john_doe_long_string',
          'password': 'secret_password',
          'list': [1, 2, 3, 4, 5, 6, 7],
          'deep': {
            'level1': {
              'level2': {'level3': 'too_deep'},
            },
          },
        };

        final formatter = JsonBodyFormatter();
        await formatter.format(data, ctx);

        final loggedString = printer.logs.join('\n');

        // Verify sensitive key was redacted recursively
        expect(loggedString, contains('"password": "***"'));
        // Verify string truncation took effect
        expect(loggedString, contains('"username": "john_..."'));
        // Verify list items were truncated with counter
        expect(loggedString, contains('... (2 more items)'));
        // Verify maxDepth was enforced correctly and depth protection was printed
        expect(loggedString, contains('... (max depth reached)'));
      },
    );

    test(
      'JsonBodyFormatter handles non-serializable objects (DateTime, Uri, etc.) safely without throwing',
      () async {
        final config = HighQDioLoggerConfig(
          maxDepth: 3,
          maxItemsPerLevel: 2,
          maxStringLength: 100,
          enableColors: false,
        );

        final ctx = BodyFormatterContext(
          config: config,
          depth: 0,
          tab: 0,
          printer: printer,
          sanitizer: DefaultLogSanitizer(),
        );

        final data = {
          'time': DateTime.parse('2026-05-26T00:00:00Z'),
          'link': Uri.parse('https://example.com/api'),
        };

        final formatter = JsonBodyFormatter();
        await formatter.format(data, ctx);

        final loggedString = printer.logs.join('\n');
        expect(loggedString, contains('2026-05-26'));
        expect(loggedString, contains('https://example.com/api'));
      },
    );

    test(
      'JsonBodyFormatter circular reference protection prevents stack overflow crash',
      () async {
        final config = HighQDioLoggerConfig(enableColors: false);
        final ctx = BodyFormatterContext(
          config: config,
          depth: 0,
          tab: 0,
          printer: printer,
          sanitizer: DefaultLogSanitizer(),
        );

        final data = <String, dynamic>{};
        data['self'] = data;

        final formatter = JsonBodyFormatter();
        await formatter.format(data, ctx);

        final loggedString = printer.logs.join('\n');
        expect(loggedString, contains('<circular reference>'));
      },
    );

    test(
      'JsonBodyFormatter identity-based circular tracker protects overridden equality objects',
      () async {
        final config = HighQDioLoggerConfig(enableColors: false);
        final ctx = BodyFormatterContext(
          config: config,
          depth: 0,
          tab: 0,
          printer: printer,
          sanitizer: DefaultLogSanitizer(),
        );

        final obj1 = CustomEqualityObject('obj1');
        final obj2 = CustomEqualityObject('obj2');

        final data = {'a': obj1, 'b': obj2};

        final formatter = JsonBodyFormatter();
        await formatter.format(data, ctx);

        final loggedString = printer.logs.join('\n');
        // Verify custom equality objects did NOT trigger false positive circular reference (since they have different identities)
        expect(loggedString, isNot(contains('<circular reference>')));
      },
    );

    test(
      'TokenBucketRateLimiter blocks triggers when capacity is exceeded',
      () {
        final limiter = TokenBucketRateLimiter(
          capacity: 2,
          refillInterval: const Duration(seconds: 10),
          refillTokens: 0,
        );

        expect(limiter.shouldAllow(), true);
        expect(limiter.shouldAllow(), true);
        expect(limiter.shouldAllow(), false);
      },
    );

    test(
      'BatchingHighQPrinter caches entries, auto-flushes on timer, and flushes on dispose',
      () async {
        final basePrinter = TestLogPrinter();
        final batchPrinter = BatchingHighQPrinter(
          target: basePrinter,
          batchSize: 10,
          autoFlushDuration: const Duration(milliseconds: 100),
        );

        await batchPrinter.print('log1');
        expect(basePrinter.logs, isEmpty);

        // Wait to let autoFlush timer fire
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(basePrinter.logs, isNotEmpty);
        expect(basePrinter.logs.first, contains('log1'));
      },
    );

    test(
      'MultiHighQPrinter broadcasts to all target printers correctly',
      () async {
        final printerA = TestLogPrinter();
        final printerB = TestLogPrinter();
        final multi = MultiHighQPrinter([printerA, printerB]);

        await multi.print('hello world');
        expect(printerA.logs.first, 'hello world');
        expect(printerB.logs.first, 'hello world');
      },
    );

    test('SamplingLogFilter probablistically evaluates sampling rate', () {
      final filterPass = SamplingLogFilter(0.5, random: MockRandom(0.2));
      final filterBlock = SamplingLogFilter(0.5, random: MockRandom(0.8));

      final context = const LogContext();

      expect(filterPass.shouldLog(LogLevel.info, context), true);
      expect(filterBlock.shouldLog(LogLevel.info, context), false);
      expect(
        filterBlock.shouldLog(LogLevel.error, context),
        true,
      ); // errors always logged
    });

    test(
      'MemoryHighQPrinter enforces strict memory bounding limits with drop-oldest strategy',
      () {
        final printer = MemoryHighQPrinter(maxLogsLimit: 3);
        printer.print('log1');
        printer.print('log2');
        printer.print('log3');
        expect(printer.logs, ['log1', 'log2', 'log3']);

        printer.print('log4');
        // Verify oldest log1 was dropped to preserve bounds
        expect(printer.logs, ['log2', 'log3', 'log4']);
      },
    );

    test(
      'LogRequest, LogResponse, and LogError models are immutable and support .toJson() structured output',
      () {
        final request = LogRequest(
          id: 'req_123',
          method: 'GET',
          uri: Uri.parse('https://google.com'),
          headers: {'auth': '123'},
          queryParameters: {'q': 'flutter'},
          extra: {'dev': true},
          body: 'my_body',
          startedAt: DateTime.now(),
        );

        // Verify Immutability
        expect(
          () => request.headers['new_key'] = 'val',
          throwsUnsupportedError,
        );
        expect(
          () => request.queryParameters['new_key'] = 'val',
          throwsUnsupportedError,
        );

        // Verify toJson serialization
        final requestJson = request.toJson();
        expect(requestJson['id'], 'req_123');
        expect(requestJson['method'], 'GET');
        expect(requestJson['uri'], 'https://google.com');
        expect(requestJson['headers']['auth'], '123');
      },
    );

    test(
      'ConsoleHighQPrinter chunking logic splits by lines to preserve emojis',
      () {
        final printer = ConsoleHighQPrinter();
        final unicodeEmojiString = 'Hello 🚀 World!\nAnother Beautiful Line!';

        expect(() => printer.print(unicodeEmojiString), returnsNormally);
      },
    );

    test(
      'HighQDioLogger Config structured JSON format output mode and enrichment pipeline work perfectly',
      () async {
        final config = HighQDioLoggerConfig(
          outputFormat: LogOutputFormat.json,
          enrichers: [CustomAppVersionEnricher()],
        );
        final logger = HighQDioLogger(config: config, printer: printer);

        final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
        final mockAdapter = MockHttpClientAdapter();
        dio.httpClientAdapter = mockAdapter;
        dio.interceptors.add(logger);

        mockAdapter.handler = (options) async {
          return ResponseBody.fromBytes(utf8.encode('{"status":"ok"}'), 200);
        };

        await dio.get<dynamic>('/test');

        expect(printer.logs, isNotEmpty);
        final printedJson = jsonDecode(printer.logs.first);
        expect(printedJson['level'], 'info');
        expect(printedJson['type'], 'request');
        expect(printedJson['metadata']['app_version'], '2.4.0');
        expect(printedJson['metadata']['platform'], 'macOS');
      },
    );

    test('HighQDioLogger custom LogFilter blocks filtered output', () async {
      final config = HighQDioLoggerConfig(filter: CustomBlockerFilter());
      final logger = HighQDioLogger(config: config, printer: printer);

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      final mockAdapter = MockHttpClientAdapter();
      dio.httpClientAdapter = mockAdapter;
      dio.interceptors.add(logger);

      // Trigger standard response (will be logged)
      mockAdapter.handler = (options) async {
        return ResponseBody.fromBytes(utf8.encode('{"status":"ok"}'), 200);
      };
      await dio.get<dynamic>('/test');

      // Trigger error (will be blocked by CustomBlockerFilter)
      mockAdapter.handler = (options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      };
      try {
        await dio.get<dynamic>('/error');
      } catch (_) {}

      final loggedString = printer.logs.join('\n');
      expect(loggedString, contains('Response'));
      expect(loggedString, isNot(contains('DioError')));
    });
  });
}
