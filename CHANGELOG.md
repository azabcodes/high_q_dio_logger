## 0.0.1

* Initial release of HighQ Dio Logger.
* Added premium colorized ASCII console pretty-printer and JSON logging support.
* Integrated token-bucket rate limiting to prevent log flooding.
* Integrated automatic PII and sensitive header sanitization.
* Added support for custom LogObservers, LogFilters, and LogEnrichers.
* Added correlation context tracking (traceId, spanId, sessionId).
* Added shell-escaped, fully sanitized cURL generator for simple request replication.
* Integrated a high-performance batching and backpressure queue for logs.
