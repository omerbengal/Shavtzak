import 'package:flutter/foundation.dart';

/// Whether `/tasks` should still open straight into the nearest event.
///
/// True until a tasks screen has been shown once in this app session, so
/// coming back to the list, with the back arrow or the browser's, never
/// bounces into an event again. A sign-in that restores `/tasks` lands on
/// the session's first tasks screen, so it opens the event too.
abstract final class TasksAutoOpen {
  static bool _spent = false;

  static bool get isPending => !_spent;

  static void spend() => _spent = true;

  @visibleForTesting
  static void debugReset() => _spent = false;
}
