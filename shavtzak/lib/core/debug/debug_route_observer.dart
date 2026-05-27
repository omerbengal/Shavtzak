import 'package:flutter/widgets.dart';

import 'debug_logger.dart';

/// `NavigatorObserver` that resets the [DebugLogger] buffer on every
/// route push/replace/pop. The new route's name is recorded as the
/// first event of the new buffer.
class DebugRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _reset(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _reset(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _reset(previousRoute);
  }

  void _reset(Route<dynamic> r) {
    final name = r.settings.name ?? '<unknown>';
    DebugLogger.instance.reset(newRoute: name);
  }
}
