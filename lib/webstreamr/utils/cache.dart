/// In-memory LRU cache with TTL — replacement for `cacheable` + Keyv used by webstreamr.
library;

class _Entry<V> {
  V value;
  int expiresAtMs;
  _Entry(this.value, this.expiresAtMs);
}

class Cacheable<V> {
  final int lruSize;
  final _store = <String, _Entry<V>>{};
  // Linked-hash semantics: dart's Map preserves insertion order, so we move
  // re-accessed keys to the end for LRU.

  Cacheable({this.lruSize = 1024});

  V? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.expiresAtMs > 0 && entry.expiresAtMs < DateTime.now().millisecondsSinceEpoch) {
      _store.remove(key);
      return null;
    }
    // touch
    _store.remove(key);
    _store[key] = entry;
    return entry.value;
  }

  /// Returns the raw entry including expiration timestamp (ms since epoch),
  /// or null. Useful for callers that want to know remaining TTL without an
  /// extra clock call.
  ({V value, int expiresAtMs})? getRaw(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.expiresAtMs > 0 && entry.expiresAtMs < DateTime.now().millisecondsSinceEpoch) {
      _store.remove(key);
      return null;
    }
    _store.remove(key);
    _store[key] = entry;
    return (value: entry.value, expiresAtMs: entry.expiresAtMs);
  }

  void set(String key, V value, [Duration? ttl]) {
    final expires = ttl == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
    _store.remove(key);
    _store[key] = _Entry(value, expires);
    while (_store.length > lruSize) {
      _store.remove(_store.keys.first);
    }
  }

  void delete(String key) => _store.remove(key);

  void clear() => _store.clear();

  int get size => _store.length;
}
