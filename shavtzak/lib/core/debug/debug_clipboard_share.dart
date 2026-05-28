import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debug_logger.dart';
import 'log_formatter.dart';
import 'logger.dart';

/// Snapshots the current [DebugLogger] buffer, formats it via [formatBuffer],
/// writes the result to the system clipboard, and shows a success or
/// failure snackbar on [context]. Also records a
/// `Logger.action('debugShareLogsCopied', ...)` telemetry event on success
/// or `Logger.warning('clipboardFailed', ...)` on failure.
///
/// The caller is responsible for dismissing any UI that revealed the
/// trigger (e.g. a mini-FAB) before or after awaiting this call — this
/// function does not own that UI state.
Future<void> copyDebugLogsToClipboard(
  BuildContext context, {
  required String currentRouteForShare,
  required String? userDisplay,
  required bool isAdmin,
  required String env,
}) async {
  final events = DebugLogger.instance.events;
  final text = formatBuffer(
    events: events,
    userDisplay: userDisplay,
    isAdmin: isAdmin,
    env: env,
    currentRoute: currentRouteForShare,
    capturedAt: DateTime.now().toUtc(),
  );
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (e) {
    Logger.warning('clipboardFailed', {'error': e.runtimeType.toString()});
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('שגיאה בהעתקה ללוח')),
    );
    return;
  }
  Logger.action('debugShareLogsCopied', {
    'bytes': text.length,
    'eventCount': events.length,
  });
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('הלוג הועתק ללוח (${events.length} אירועים)')),
  );
}
