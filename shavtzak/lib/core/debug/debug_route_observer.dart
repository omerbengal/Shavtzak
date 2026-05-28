import 'package:flutter/widgets.dart';

import 'debug_logger.dart';

/// `NavigatorObserver` that resets the [DebugLogger] buffer on
/// page-level navigation (push/replace/pop of a [PageRoute]). Dialog
/// and modal-sheet pushes ([PopupRoute] subclasses) are intentionally
/// ignored, so the user's action context survives until they actually
/// navigate to a different page.
class DebugRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _reset(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is! PageRoute) return;
    _reset(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Only reset when a full PAGE is popped (genuine back-navigation to a
    // previous page). Dismissing a dialog or modal sheet pops a PopupRoute,
    // which must NOT reset — otherwise the context the user generated inside
    // that dialog (actions, DB reads, BLoC events) is wiped on close.
    if (route is! PageRoute) return;
    if (previousRoute == null) return;
    _reset(previousRoute);
  }

  void _reset(Route<dynamic> r) {
    final name = r.settings.name ?? '<unknown>';
    DebugLogger.instance.reset(newRoute: name);
  }
}
