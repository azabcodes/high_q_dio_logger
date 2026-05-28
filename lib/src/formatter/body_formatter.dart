import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:high_q_dio_logger/high_q_dio_logger.dart';

class BodyFormatterContext {
  final HighQDioLoggerConfig config;
  final int depth;
  final int tab;
  final HighQPrinter printer;
  final LogSanitizer sanitizer;

  const BodyFormatterContext({
    required this.config,
    required this.depth,
    required this.tab,
    required this.printer,
    required this.sanitizer,
  });

  BodyFormatterContext nextLevel() {
    return BodyFormatterContext(
      config: config,
      depth: depth + 1,
      tab: tab + 1,
      printer: printer,
      sanitizer: sanitizer,
    );
  }

  String get indent => '    ' * tab;
}

abstract class BodyFormatter {
  /// Whether this formatter can handle the given data.
  bool canHandle(dynamic data);

  /// Formats the data and writes directly to the printer in the context.
  FutureOr<void> format(dynamic data, BodyFormatterContext ctx);
}

class JsonBodyFormatter implements BodyFormatter {
  @override
  bool canHandle(dynamic data) {
    if (data is Map || data is List) return true;
    if (data is String) {
      final trimmed = data.trim();
      return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'));
    }
    return false;
  }

  @override
  FutureOr<void> format(dynamic data, BodyFormatterContext ctx) async {
    dynamic parsed = data;
    if (data is String) {
      try {
        parsed = jsonDecode(data);
      } catch (_) {
        await ctx.printer.print('║ ${data.toString()}');
        return;
      }
    }
    // LinkedHashSet.identity() guarantees identity-based tracking to avoid custom operator == and hashCode overrides
    final visited = HashSet<dynamic>.identity();
    await _printItem(parsed, ctx, visited, isLast: true);
  }

  Future<void> _printItem(
    dynamic item,
    BodyFormatterContext currentCtx,
    Set<dynamic> visited, {
    bool isLast = true,
  }) async {
    if (currentCtx.depth >= currentCtx.config.maxDepth) {
      await currentCtx.printer.print(
        '║${currentCtx.indent}... (max depth reached)${isLast ? "" : ","}',
      );
      return;
    }

    if (item is Map) {
      if (visited.contains(item)) {
        await currentCtx.printer.print(
          '║${currentCtx.indent}<circular reference>${isLast ? "" : ","}',
        );
        return;
      }
      visited.add(item);

      await currentCtx.printer.print('║${currentCtx.indent}{');
      final entries = item.entries.toList();
      final visibleCount = math.min(
        entries.length,
        currentCtx.config.maxItemsPerLevel,
      );
      for (var i = 0; i < visibleCount; i++) {
        final entry = entries[i];
        final keyStr = entry.key.toString();
        final sanitized = currentCtx.sanitizer.sanitize(keyStr, entry.value);
        final prefix = '║${currentCtx.nextLevel().indent}"$keyStr": ';
        final bool isEntryLast =
            i == visibleCount - 1 &&
            entries.length <= currentCtx.config.maxItemsPerLevel;

        if (sanitized is Map || sanitized is List) {
          await currentCtx.printer.print(prefix);
          await _printItem(
            sanitized,
            currentCtx.nextLevel(),
            visited,
            isLast: isEntryLast,
          );
        } else {
          final formattedVal = _formatValue(
            sanitized,
            currentCtx.config.maxStringLength,
          );
          await currentCtx.printer.print(
            '$prefix$formattedVal${isEntryLast ? "" : ","}',
          );
        }
      }
      if (entries.length > currentCtx.config.maxItemsPerLevel) {
        await currentCtx.printer.print(
          '║${currentCtx.nextLevel().indent}... (${entries.length - currentCtx.config.maxItemsPerLevel} more items)',
        );
      }
      await currentCtx.printer.print(
        '║${currentCtx.indent}}${isLast ? "" : ","}',
      );
      visited.remove(item);
    } else if (item is List) {
      if (visited.contains(item)) {
        await currentCtx.printer.print(
          '║${currentCtx.indent}<circular reference>${isLast ? "" : ","}',
        );
        return;
      }
      visited.add(item);

      await currentCtx.printer.print('║${currentCtx.indent}[');
      final visibleCount = math.min(
        item.length,
        currentCtx.config.maxItemsPerLevel,
      );
      for (var i = 0; i < visibleCount; i++) {
        final element = item[i];
        final bool isElementLast =
            i == visibleCount - 1 &&
            item.length <= currentCtx.config.maxItemsPerLevel;

        if (element is Map || element is List) {
          await _printItem(
            element,
            currentCtx.nextLevel(),
            visited,
            isLast: isElementLast,
          );
        } else {
          final formattedVal = _formatValue(
            element,
            currentCtx.config.maxStringLength,
          );
          await currentCtx.printer.print(
            '║${currentCtx.nextLevel().indent}$formattedVal${isElementLast ? "" : ","}',
          );
        }
      }
      if (item.length > currentCtx.config.maxItemsPerLevel) {
        await currentCtx.printer.print(
          '║${currentCtx.nextLevel().indent}... (${item.length - currentCtx.config.maxItemsPerLevel} more items)',
        );
      }
      await currentCtx.printer.print(
        '║${currentCtx.indent}]${isLast ? "" : ","}',
      );
      visited.remove(item);
    } else {
      final formattedVal = _formatValue(
        item,
        currentCtx.config.maxStringLength,
      );
      await currentCtx.printer.print(
        '║${currentCtx.indent}$formattedVal${isLast ? "" : ","}',
      );
    }
  }

  String _formatValue(dynamic val, int maxLength) {
    if (val == null) return 'null';
    if (val is String) {
      final truncated = LoggerHelper.truncate(val, maxLength);
      return '"${truncated.replaceAll('\n', ' ')}"';
    }
    return val.toString();
  }
}

class Uint8ListBodyFormatter implements BodyFormatter {
  @override
  bool canHandle(dynamic data) => data is Uint8List;

  @override
  FutureOr<void> format(dynamic data, BodyFormatterContext ctx) async {
    final Uint8List list = data as Uint8List;
    await ctx.printer.print('║${ctx.indent}[');
    for (var i = 0; i < list.length; i += 20) {
      final slice = list.sublist(i, (i + 20).clamp(0, list.length));
      await ctx.printer.print('║${ctx.indent} ${slice.join(', ')}');
    }
    await ctx.printer.print('║${ctx.indent}]');
  }
}

class PlainTextBodyFormatter implements BodyFormatter {
  @override
  bool canHandle(dynamic data) => true;

  @override
  FutureOr<void> format(dynamic data, BodyFormatterContext ctx) async {
    final str = data.toString();
    final truncated = LoggerHelper.truncate(str, ctx.config.maxStringLength);
    final maxWidth = ctx.config.lineWidth;
    final lines = (truncated.length / maxWidth).ceil();
    for (var i = 0; i < lines; ++i) {
      final part = truncated.substring(
        i * maxWidth,
        (i * maxWidth + maxWidth).clamp(0, truncated.length),
      );
      await ctx.printer.print('║ ${ctx.indent}$part');
    }
  }
}
