import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:high_q_dio_logger/high_q_dio_logger.dart';

abstract class HighQPrinter {
  FutureOr<void> print(Object? message);
}

class ConsoleHighQPrinter implements HighQPrinter {
  const ConsoleHighQPrinter();

  @override
  FutureOr<void> print(Object? message) {
    final str = message?.toString() ?? '';
    if (str.isEmpty) {
      debugPrint('');
      return null;
    }
    // Splitting by line prevents cutting ANSI color escapes or multi-byte UTF-8 emojis in half!
    final lines = str.split('\n');
    for (final line in lines) {
      debugPrint(line);
    }
    return null;
  }
}

class MemoryHighQPrinter implements HighQPrinter {
  final List<String> logs = [];
  final int maxLogsLimit;

  MemoryHighQPrinter({this.maxLogsLimit = 500});

  @override
  FutureOr<void> print(Object? message) {
    final str = message?.toString() ?? '';
    if (logs.length >= maxLogsLimit) {
      logs.removeAt(0); // drop oldest
    }
    logs.add(str);
    return null;
  }

  void clear() => logs.clear();
}

class MultiHighQPrinter implements HighQPrinter {
  final List<HighQPrinter> printers;

  const MultiHighQPrinter(this.printers);

  @override
  Future<void> print(Object? message) async {
    for (final printer in printers) {
      try {
        await printer.print(message);
      } catch (e) {
        debugPrint('MultiHighQPrinter error printing: $e');
      }
    }
  }
}

class BatchingHighQPrinter implements HighQPrinter {
  final HighQPrinter target;
  final int batchSize;
  final Duration autoFlushDuration;
  final int maxBufferBound;
  final QueueBackpressureStrategy backpressureStrategy;

  final List<String> _buffer = [];
  Timer? _autoFlushTimer;
  bool _isFlushing = false;

  BatchingHighQPrinter({
    required this.target,
    this.batchSize = 20,
    this.autoFlushDuration = const Duration(seconds: 1),
    this.maxBufferBound = 1000,
    this.backpressureStrategy = QueueBackpressureStrategy.dropOldest,
  });

  @override
  Future<void> print(Object? message) async {
    final str = message?.toString() ?? '';

    // Enforce backpressure strategies when buffer boundaries are hit
    if (_buffer.length >= maxBufferBound) {
      if (backpressureStrategy == QueueBackpressureStrategy.dropOldest) {
        if (_buffer.isNotEmpty) _buffer.removeAt(0);
      } else {
        return; // dropNewest: discard the log
      }
    }

    _buffer.add(str);

    if (_buffer.length >= batchSize) {
      await flush();
      return;
    }

    // Initialize timer for auto-flushing on inactivity or interval
    _autoFlushTimer ??= Timer(autoFlushDuration, () {
      flush();
    });
  }

  Future<void> flush() async {
    if (_isFlushing || _buffer.isEmpty) return;
    _isFlushing = true;

    _autoFlushTimer?.cancel();
    _autoFlushTimer = null;

    final combined = _buffer.join('\n');
    _buffer.clear();
    try {
      await target.print(combined);
    } catch (e) {
      debugPrint('BatchingHighQPrinter error flushing: $e');
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> dispose() async {
    await flush();
  }
}
