import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/debug/debug_logger.dart';
import '../../core/debug/log_formatter.dart';
import '../../core/debug/logger.dart';

/// Wraps the host screen's "+" FAB. Long-press reveals a mini-FAB; tapping
/// the mini-FAB copies the formatted [DebugLogger] buffer to the system
/// clipboard.
///
/// The [child] FAB must have an explicit [FloatingActionButton.heroTag] set.
/// Leaving it at the default shared tag will cause a Hero conflict at
/// runtime when the mini-FAB is simultaneously visible.
class DebugLogShareFab extends StatefulWidget {
  const DebugLogShareFab({
    super.key,
    required this.child,
    required this.currentRouteForShare,
    required this.userDisplay,
    required this.isAdmin,
    required this.env,
  });

  final Widget child;
  final String currentRouteForShare;
  final String? userDisplay;
  final bool isAdmin;
  final String env;

  @override
  State<DebugLogShareFab> createState() => _DebugLogShareFabState();
}

class _DebugLogShareFabState extends State<DebugLogShareFab> {
  static const Duration _autoDismissAfter = Duration(seconds: 4);

  bool _menuVisible = false;
  Timer? _autoDismiss;

  void _toggleMenu() {
    setState(() => _menuVisible = !_menuVisible);
    _autoDismiss?.cancel();
    if (_menuVisible) {
      Logger.action('debugShareMenuOpen');
      _autoDismiss = Timer(_autoDismissAfter, () {
        if (mounted) setState(() => _menuVisible = false);
      });
    }
  }

  Future<void> _copyLogs() async {
    final events = DebugLogger.instance.events;
    final text = formatBuffer(
      events: events,
      userDisplay: widget.userDisplay,
      isAdmin: widget.isAdmin,
      env: widget.env,
      currentRoute: widget.currentRouteForShare,
      capturedAt: DateTime.now().toUtc(),
    );
    await Clipboard.setData(ClipboardData(text: text));
    Logger.action('debugShareLogsCopied', {
      'bytes': text.length,
      'eventCount': events.length,
    });
    if (!mounted) return;
    // All remaining code is synchronous; mounted cannot change again.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('הלוג הועתק ללוח (${events.length} אירועים)')),
    );
    setState(() => _menuVisible = false);
    _autoDismiss?.cancel();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_menuVisible)
          FloatingActionButton(
            mini: true,
            heroTag: 'debug-share-mini-fab',
            tooltip: 'העתק לוג תקלה',
            onPressed: _copyLogs,
            child: const Icon(Icons.bug_report),
          ),
        if (_menuVisible) const SizedBox(height: 8),
        GestureDetector(
          onLongPress: _toggleMenu,
          child: widget.child,
        ),
      ],
    );
  }
}
