/// Discrete categories of events captured by [DebugLogger].
enum LogEventType {
  nav,
  action,
  blocDispatch,
  blocEmit,
  blocNoEmit,
  blocError,
  dbStart,
  dbEnd,
  dbStreamEmit,
  dbError,
  loadStart,
  loadEnd,
  warning,
}

/// One captured debug event.
///
/// Held in the [DebugLogger] ring buffer and rendered by `formatBuffer`.
/// Fields are immutable; [context] is wrapped in an unmodifiable view so
/// accidental mutation outside this file is caught.
class LogEvent {
  LogEvent({
    required this.timestamp,
    required this.type,
    required this.name,
    required Map<String, Object?> context,
    this.duration,
  }) : context = Map.unmodifiable(context);

  final DateTime timestamp;
  final LogEventType type;
  final String name;
  final Map<String, Object?> context;
  final Duration? duration;
}
