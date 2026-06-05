/// Async semaphore + per-host helpers (port of `async-mutex` Semaphore + Mutex usage).
library;

import 'dart:async';
import '../errors.dart';

class _SemWaiter {
  final Completer<void> completer;
  Timer? timeoutTimer;
  _SemWaiter(this.completer);
}

class Semaphore {
  final int capacity;
  int _inUse = 0;
  final _waiters = <_SemWaiter>[];

  Semaphore(this.capacity);

  /// Acquires a slot. If full, waits up to [timeout]. On timeout, throws
  /// [QueueIsFullError] for [url].
  Future<void> acquire({Duration? timeout, Uri? url}) {
    if (_inUse < capacity) {
      _inUse++;
      return Future.value();
    }
    final c = Completer<void>();
    final waiter = _SemWaiter(c);
    if (timeout != null) {
      waiter.timeoutTimer = Timer(timeout, () {
        if (!c.isCompleted) {
          _waiters.remove(waiter);
          c.completeError(QueueIsFullError(url ?? Uri.parse('about:blank')));
        }
      });
    }
    _waiters.add(waiter);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final w = _waiters.removeAt(0);
      w.timeoutTimer?.cancel();
      // _inUse stays the same, the completer signals to the waiter that they
      // hold a slot.
      w.completer.complete();
      return;
    }
    if (_inUse > 0) _inUse--;
  }
}

/// Simple async mutex (capacity = 1).
class Mutex {
  final _sem = Semaphore(1);
  Future<T> runExclusive<T>(Future<T> Function() body) async {
    await _sem.acquire();
    try {
      return await body();
    } finally {
      _sem.release();
    }
  }
}
