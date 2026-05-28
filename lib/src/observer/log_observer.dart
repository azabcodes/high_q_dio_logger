import 'dart:async';
import 'package:high_q_dio_logger/high_q_dio_logger.dart';

abstract class LogObserver {
  FutureOr<void> onRequest(LogRequest request);
  FutureOr<void> onResponse(LogResponse response, int elapsedMs);
  FutureOr<void> onError(LogError error, int elapsedMs);
}
