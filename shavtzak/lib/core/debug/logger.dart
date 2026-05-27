import 'debug_logger.dart';
import 'log_event.dart';

/// Static facade for explicit instrumentation at UI sites that don't
/// naturally route through BLoC.
///
/// All recording goes through [DebugLogger.instance]. Methods never throw.
class Logger {
  Logger._();

  /// Record a semantic UI action.
  static void action(String name,
      [Map<String, Object?> context = const {}]) {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.action,
      name: name,
      context: context,
    ));
  }

  /// Record the start of a screen-level loading operation.
  ///
  /// Pair with [loadingEnd] using the same [operation] string.
  static void loadingStart(String operation,
      [Map<String, Object?> context = const {}]) {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.loadStart,
      name: operation,
      context: context,
    ));
  }

  /// Record the completion of a screen-level loading operation.
  ///
  /// If a prior [loadingStart] for the same [operation] exists in the
  /// buffer, the resulting event's `duration` is filled in. If not, the
  /// event is still recorded with `context: {unmatched: true}`.
  static void loadingEnd(
    String operation, {
    bool ok = true,
    Object? error,
    Map<String, Object?> context = const {},
  }) {
    final now = DateTime.now().toUtc();
    final events = DebugLogger.instance.events;
    LogEvent? start;
    for (final e in events.reversed) {
      if (e.type == LogEventType.loadStart && e.name == operation) {
        start = e;
        break;
      }
    }
    final merged = <String, Object?>{
      ...context,
      'ok': ok,
      if (error != null) 'error': error.toString(),
      if (start == null) 'unmatched': true,
    };
    DebugLogger.instance.record(LogEvent(
      timestamp: now,
      type: LogEventType.loadEnd,
      name: operation,
      context: merged,
      duration: start == null ? null : now.difference(start.timestamp),
    ));
  }

  /// Record a freeform diagnostic warning.
  static void warning(String name,
      [Map<String, Object?> context = const {}]) {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.warning,
      name: name,
      context: context,
    ));
  }

  /// Convert a possibly-sensitive string into a privacy-safe length stamp.
  ///
  /// Returns `<null>` for null, `<N chars>` otherwise. Never returns
  /// any portion of [raw].
  static String redact(String? raw) {
    if (raw == null) return '<null>';
    return '<${raw.length} chars>';
  }
}
