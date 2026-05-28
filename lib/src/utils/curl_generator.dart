import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:high_q_dio_logger/high_q_dio_logger.dart';

class CurlGenerator {
  /// Generates a cURL command that reproduces the given [RequestOptions].
  /// Encapsulates values securely with shell escaping and redacts sensitive data.
  /// Supports [multiline] output format using backslash formatting.
  static String generate(
    RequestOptions options, {
    LogSanitizer? sanitizer,
    bool multiline = false,
  }) {
    final activeSanitizer = sanitizer ?? DefaultLogSanitizer();
    final buffer = StringBuffer('curl');
    final separator = multiline ? ' \\\n  ' : ' ';

    buffer.write('$separator-X ${options.method}');
    buffer.write('$separator${shellEscape(options.uri.toString())}');

    // Headers & Content-Type inference
    final headers = Map<String, dynamic>.from(options.headers);
    if (!headers.containsKey('content-type') &&
        !headers.containsKey('Content-Type')) {
      if (options.data is FormData) {
        headers['Content-Type'] = 'multipart/form-data';
      } else if (options.data is Map || options.data is List) {
        headers['Content-Type'] = 'application/json';
      }
    }

    headers.forEach((k, v) {
      final sanitizedValue = activeSanitizer.sanitize(k, v?.toString() ?? '');
      buffer.write('$separator-H ${shellEscape("$k: $sanitizedValue")}');
    });

    // Body data (FormData vs normal)
    if (options.data != null) {
      final data = options.data;
      if (data is FormData) {
        for (var field in data.fields) {
          buffer.write(
            '$separator-F ${shellEscape("${field.key}=${field.value}")}',
          );
        }
        for (var file in data.files) {
          buffer.write(
            '$separator-F ${shellEscape("${file.key}=@${file.value.filename ?? 'file'}")}',
          );
        }
      } else if (data is Map) {
        final Map<String, dynamic> sanitizedMap = data.map(
          (k, v) =>
              MapEntry(k.toString(), activeSanitizer.sanitize(k.toString(), v)),
        );
        buffer.write(
          '$separator--data ${shellEscape(jsonEncode(sanitizedMap))}',
        );
      } else {
        buffer.write('$separator--data ${shellEscape(data.toString())}');
      }
    }
    return buffer.toString();
  }

  static String shellEscape(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
