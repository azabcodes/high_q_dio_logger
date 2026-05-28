import 'package:high_q_dio_logger/high_q_dio_logger.dart';

class AnsiColor {
  final bool enabled;
  final HighQTheme theme;

  const AnsiColor({required this.enabled, required this.theme});

  static const String reset = '\x1B[0m';

  String red(String s) => enabled ? '${theme.errorColor}$s$reset' : s;
  String green(String s) => enabled ? '${theme.successColor}$s$reset' : s;
  String yellow(String s) => enabled ? '${theme.warningColor}$s$reset' : s;
  String info(String s) => enabled ? '${theme.infoColor}$s$reset' : s;

  /// Colors a message dynamically based on its LogLevel.
  String colorize(String msg, LogLevel level) {
    if (!enabled) return msg;
    switch (level) {
      case LogLevel.error:
        return red(msg);
      case LogLevel.warning:
        return yellow(msg);
      case LogLevel.info:
        return info(msg);
      case LogLevel.debug:
      case LogLevel.trace:
        return green(msg);
    }
  }
}
