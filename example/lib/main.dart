import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:high_q_dio_logger/high_q_dio_logger.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HighQ Dio Logger Demo',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const DemoScreen(),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final List<String> _consoleLogs = [];
  late final Dio _dio;

  // Custom log observer that captures logs to display in the UI
  late final MemoryHighQPrinter _memoryPrinter;

  @override
  void initState() {
    super.initState();
    _memoryPrinter = MemoryHighQPrinter(maxLogsLimit: 100);
    _initDio();
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://jsonplaceholder.typicode.com',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));

    // Custom enricher to add device platform info to every log
    final customEnricher = CustomDemoEnricher();

    // Create the HighQDioLogger configuration
    final config = HighQDioLoggerConfig(
      request: true,
      requestHeaders: true,
      requestBody: true,
      responseBody: true,
      responseHeaders: false,
      errors: true,
      enableColors: true, // Colorize terminal output
      lineWidth: 90,
      maxDepth: 3,
      maxItemsPerLevel: 10,
      enrichers: [customEnricher],
    );

    // Multi-printer: log both to standard flutter debugPrint AND to our in-app memory logger
    final multiPrinter = MultiHighQPrinter([
      const ConsoleHighQPrinter(),
      _memoryPrinter,
    ]);

    // Instantiate and add the interceptor to Dio
    _dio.interceptors.add(
      HighQDioLogger(
        config: config,
        printer: multiPrinter,
      ),
    );
  }

  void _addLogToUI(String newLog) {
    setState(() {
      _consoleLogs.add(newLog);
    });
  }

  Future<void> _makeSuccessfulRequest() async {
    _memoryPrinter.clear();
    _addLogToUI('Making GET request to /posts/1...');
    try {
      await _dio.get<dynamic>('/posts/1');
      _flushMemoryLogs();
    } catch (e) {
      _addLogToUI('Error: $e');
    }
  }

  Future<void> _makePostRequest() async {
    _memoryPrinter.clear();
    _addLogToUI('Making POST request to /posts...');
    try {
      await _dio.post<dynamic>(
        '/posts',
        data: {
          'title': 'HighQ Logger',
          'body': 'This is a premium high‑fidelity logger for Dio.',
          'userId': 42,
          'nestedConfig': {
            'enablePerformanceMetrics': true,
            'logLevels': ['debug', 'info', 'error'],
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer test_token_redacted_automatically',
            'Custom-Header': 'HighQAppsRule',
          },
        ),
      );
      _flushMemoryLogs();
    } catch (e) {
      _addLogToUI('Error: $e');
    }
  }

  Future<void> _makeFailedRequest() async {
    _memoryPrinter.clear();
    _addLogToUI('Making GET request to invalid endpoint (triggers 404)...');
    try {
      await _dio.get<dynamic>('/invalid-endpoint-for-testing');
    } catch (_) {
      _flushMemoryLogs();
    }
  }

  void _flushMemoryLogs() {
    setState(() {
      _consoleLogs.addAll(_memoryPrinter.logs);
    });
  }

  void _clearUI() {
    setState(() {
      _consoleLogs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HighQ Dio Logger Demo'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Interactive Interceptor Simulator',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
            ),
            const SizedBox(height: 8),
            const Text(
              'Click any button below to fire network requests. The HighQDioLogger will intercept, enrich, sanitize, format, and output the log details below.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _makeSuccessfulRequest,
                    child: const Text('GET Request'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _makePostRequest,
                    child: const Text('POST Request'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _makeFailedRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withAlpha(51),
                      foregroundColor: Colors.redAccent,
                    ),
                    child: const Text('Trigger 404'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Formatted Output Logs:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton.icon(
                  onPressed: _clearUI,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: _consoleLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'No logs captured yet. Press a button to simulate network traffic.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _consoleLogs.length,
                        itemBuilder: (context, index) {
                          final logLine = _consoleLogs[index];
                          // Remove terminal ANSI colors to display cleanly in app UI
                          final cleanLine = logLine.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              cleanLine,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: Colors.greenAccent,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomDemoEnricher implements LogEnricher {
  @override
  void enrich(LogContext context, Map<String, dynamic> metadata) {
    metadata['environment'] = 'development';
    metadata['device_type'] = 'Flutter Simulator/Device';
  }
}
