import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/debug/debug_clipboard_share.dart';
import '../../core/debug/logger.dart';

/// Long-pressing [child] shows the small bug button under it, which copies
/// the debug log to the clipboard. The same trigger as a long press on the
/// active bottom tab ([BottomNavWithDebugTrigger]), for screens without one.
class DebugLogLongPress extends StatefulWidget {
  const DebugLogLongPress({
    super.key,
    required this.child,
    required this.route,
    required this.userDisplay,
    required this.isAdmin,
    required this.env,
    required this.heroTag,
  });

  final Widget child;

  /// The screen the log is copied from, written at its top.
  final String route;
  final String? userDisplay;
  final bool isAdmin;
  final String env;
  final String heroTag;

  @override
  State<DebugLogLongPress> createState() => _DebugLogLongPressState();
}

class _DebugLogLongPressState extends State<DebugLogLongPress> {
  static const Duration _autoDismissAfter = Duration(seconds: 4);
  static const double _miniFabRadius = 20.0;

  OverlayEntry? _entry;
  Timer? _autoDismiss;

  void _toggle() {
    if (_entry != null) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final origin = box.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final center = origin.dx + box.size.width / 2;
    final top = origin.dy + box.size.height + 8;
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: center - _miniFabRadius,
        top: top,
        child: FloatingActionButton.small(
          key: const Key('debug-log-mini-fab'),
          heroTag: widget.heroTag,
          tooltip: 'העתק לוג תקלה',
          onPressed: _copyAndDismiss,
          child: const Icon(Icons.bug_report),
        ),
      ),
    );
    overlay.insert(_entry!);
    Logger.action('debugShareMenuOpen');
    _autoDismiss?.cancel();
    _autoDismiss = Timer(_autoDismissAfter, () {
      if (mounted) _hide();
    });
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
    _autoDismiss?.cancel();
    _autoDismiss = null;
  }

  Future<void> _copyAndDismiss() async {
    final route = widget.route;
    await copyDebugLogsToClipboard(
      context,
      currentRouteForShare: route,
      userDisplay: widget.userDisplay,
      isAdmin: widget.isAdmin,
      env: widget.env,
    );
    if (mounted) _hide();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onLongPress: _toggle, child: widget.child);
  }
}
