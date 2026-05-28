abstract class RateLimiter {
  /// Attempts to acquire a permit. Returns true if allowed, false if rate-limited.
  bool shouldAllow();
}

class TokenBucketRateLimiter implements RateLimiter {
  final int capacity;
  final Duration refillInterval;
  final int refillTokens;

  double _tokens;
  DateTime _lastRefill;

  TokenBucketRateLimiter({
    this.capacity = 100,
    this.refillInterval = const Duration(seconds: 1),
    this.refillTokens = 10,
  }) : _tokens = capacity.toDouble(),
       _lastRefill = DateTime.now();

  @override
  bool shouldAllow() {
    _refill();
    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      return true;
    }
    return false;
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill);
    if (elapsed >= refillInterval) {
      final cycles = elapsed.inMicroseconds / refillInterval.inMicroseconds;
      final added = cycles * refillTokens;
      _tokens = (_tokens + added).clamp(0.0, capacity.toDouble());
      _lastRefill = now;
    }
  }
}

class NoOpRateLimiter implements RateLimiter {
  const NoOpRateLimiter();

  @override
  bool shouldAllow() => true;
}
