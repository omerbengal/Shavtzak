import 'log_event.dart';

const int _maxFieldChars = 200;

/// Render the [DebugLogger] buffer to share-friendly plain text.
///
/// Output format:
///
/// ```
/// === Shavtzak Debug Log ===
/// User: <display> [(admin)] | Env: <env> | Route: <route>
/// Captured: <ISO local, e.g. 2026-05-28T20:09:25.024+03:00> | Events: <n>
///
/// [HH:mm:ss.SSS+OF:FS] TYPE name {ctx} (duration ms)
/// ...
/// ```
///
/// Timestamps render in the device-local timezone with an explicit offset
/// (DST-aware), so a log shared from Israel shows `+03:00` in summer and
/// `+02:00` in winter without ambiguity.
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

String _two(int n) => n.toString().padLeft(2, '0');
String _three(int n) => n.toString().padLeft(3, '0');

/// Renders the device-local UTC offset as `+HH:mm` / `-HH:mm`.
///
/// Uses [DateTime.timeZoneOffset], which is DST-aware on the host (e.g. on
/// the browser for Flutter Web). So in Israel this yields `+03:00` during
/// daylight saving and `+02:00` in winter, automatically.
String _offset(DateTime local) {
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final mins = off.inMinutes.abs();
  return '$sign${_two(mins ~/ 60)}:${_two(mins % 60)}';
}

/// Full ISO-8601 local timestamp with offset, e.g.
/// `2026-05-28T20:09:25.024+03:00`. Input may be UTC or local; it is
/// converted to device-local for display.
String _iso(DateTime ts) {
  final d = ts.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)}T'
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}.'
      '${_three(d.millisecond)}${_offset(d)}';
}

/// Time-of-day local timestamp with offset, e.g. `20:09:25.024+03:00`.
String _timeOnly(DateTime ts) {
  final d = ts.toLocal();
  return '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}.'
      '${_three(d.millisecond)}${_offset(d)}';
}
