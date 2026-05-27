import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/debug/debug_logger.dart';
import '../../core/debug/log_formatter.dart';
import '../../core/debug/logger.dart';

/// Wraps the host screen's "+" FAB. Long-press reveals a mini-FAB; tapping
/// the mini-FAB copies the formatted [DebugLogger] buffer to the system
/// clipboard.
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
  bool _menuVisible = false;
  Timer? _autoDismiss;

  void _toggleMenu() {
    setState(() => _menuVisible = !_menuVisible);
    _autoDismiss?.cancel();
    if (_menuVisible) {
      Logger.action('debugShareMenuOpen');
      _autoDismiss = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _menuVisible = false);
      });
    }
  }

  Future<void> _copyLogs() async {
    final text = formatBuffer(
      events: DebugLogger.instance.events,
      userDisplay: widget.userDisplay,
      isAdmin: widget.isAdmin,
      env: widget.env,
      currentRoute: widget.currentRouteForShare,
      capturedAt: DateTime.now().toUtc(),
    );
    await Clipboard.setData(ClipboardData(text: text));
    Logger.action('debugShareLogsCopied', {
      'bytes': text.length,
      'eventCount': DebugLogger.instance.events.length,
    });
    if (!mounted) return;
    final count = DebugLogger.instance.events.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('הלוג הועתק ללוח ($count אירועים)')),
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
