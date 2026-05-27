import 'log_event.dart';

const int _maxFieldChars = 200;

/// Render the [DebugLogger] buffer to share-friendly plain text.
///
/// Output format:
///
/// ```
/// === Shavtzak Debug Log ===
/// User: <display> [(admin)] | Env: <env> | Route: <route>
/// Captured: <ISO-Z> | Events: <n>
///
/// [HH:mm:ss.SSSZ] TYPE name {ctx} (duration ms)
/// ...
/// ```
String formatBuffer({
  required List<LogEvent> events,
  required String? userDisplay,
  required bool isAdmin,
  required String env,
  required String currentRoute,
  required DateTime capturedAt,
}) {
  final user = userDisplay ?? '-';
  final adminTag = isAdmin ? ' (admin)' : '';
  final headerIso = _iso(capturedAt);
  final lines = <String>[
    '=== Shavtzak Debug Log ===',
    'User: $user$adminTag | Env: $env | Route: $currentRoute',
    'Captured: $headerIso | Events: ${events.length}',
    '',
    for (final e in events) _formatEvent(e),
  ];
  return lines.join('\n');
}

String _formatEvent(LogEvent e) {
  final ts = '[${_timeOnly(e.timestamp)}]';
  final type = _typeLabel(e.type);
  final ctxStr = e.context.isEmpty ? '' : ' ${_renderContext(e.context)}';
  final durStr =
      e.duration == null ? '' : ' (${e.duration!.inMilliseconds} ms)';
  return '$ts $type ${e.name}$ctxStr$durStr';
}

String _typeLabel(LogEventType t) {
  switch (t) {
    case LogEventType.nav: return 'NAV';
    case LogEventType.action: return 'ACTION';
    case LogEventType.blocDispatch: return 'BLOC_DISPATCH';
    case LogEventType.blocEmit: return 'BLOC_EMIT';
    case LogEventType.blocNoEmit: return 'BLOC_NO_EMIT';
    case LogEventType.blocError: return 'BLOC_ERROR';
    case LogEventType.dbStart: return 'DB_START';
    case LogEventType.dbEnd: return 'DB_END';
    case LogEventType.dbStreamEmit: return 'DB_STREAM_EMIT';
    case LogEventType.dbError: return 'DB_ERROR';
    case LogEventType.loadStart: return 'LOAD_START';
    case LogEventType.loadEnd: return 'LOAD_END';
    case LogEventType.warning: return 'WARN';
  }
}

String _renderContext(Map<String, Object?> ctx) {
  final parts = <String>[];
  for (final entry in ctx.entries) {
    parts.add('${entry.key}: ${_renderValue(entry.value)}');
  }
  return '{${parts.join(', ')}}';
}

String _renderValue(Object? v) {
  String s;
  if (v == null) {
    s = 'null';
  } else if (v is String || v is num || v is bool) {
    s = v.toString();
  } else if (v is List) {
    s = v.map(_renderValue).join(',');
    s = '[$s]';
  } else if (v is Map) {
    s = _renderContext(v.cast<String, Object?>());
  } else {
    s = v.toString();
  }
  if (s.length > _maxFieldChars) {
    s = '${s.substring(0, _maxFieldChars)}…(truncated)';
  }
  return s;
}

String _iso(DateTime utc) {
  final d = utc.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}T'
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}.'
      '${three(d.millisecond)}Z';
}

String _timeOnly(DateTime utc) {
  final d = utc.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}.'
      '${three(d.millisecond)}Z';
}
