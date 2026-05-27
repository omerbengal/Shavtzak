import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'log_event.dart';

/// In-memory ring buffer of recent [LogEvent]s. Singleton.
///
/// Always-on in both `test` and `prod` environments. Capacity is fixed at
/// [capacity]; new entries drop the oldest. Never throws (recording is
/// wrapped in `try/catch`).
class DebugLogger {
  DebugLogger._();
  static final DebugLogger instance = DebugLogger._();

  /// Maximum number of events held in memory at once.
  static const int capacity = 200;

  final Queue<LogEvent> _events = Queue<LogEvent>();

  /// Append an event to the buffer. If capacity is exceeded, the oldest
  /// event is dropped. This method must never throw.
  void record(LogEvent event) {
    try {
      if (_events.length >= capacity) {
        _events.removeFirst();
      }
      _events.add(event);
    } catch (_) {
      // Logging must never break the app.
    }
  }

  /// Clear the buffer and record a synthetic NAV event for [newRoute].
  /// Called by [DebugRouteObserver] on every route change.
  void reset({required String newRoute}) {
    try {
      _events.clear();
      _events.add(LogEvent(
        timestamp: DateTime.now().toUtc(),
        type: LogEventType.nav,
        name: newRoute,
        context: const {'reset': true},
      ));
    } catch (_) {}
  }

  /// Read-only view of the current buffer contents (oldest first).
  List<LogEvent> get events => List.unmodifiable(_events);

  @visibleForTesting
  void debugClearForTests() {
    _events.clear();
  }
}
