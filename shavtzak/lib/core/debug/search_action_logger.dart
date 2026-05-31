import 'dart:async';

import 'logger.dart';

/// Debounced logger for search / filter text fields.
///
/// Free-text fields are intentionally NOT logged per-keystroke — that would
/// flood the ring buffer and risk leaking content. This coalesces a burst of
/// keystrokes into a single `filter:search` action [_debounce] after the user
/// stops typing, recording only the query LENGTH (via [Logger.redact]) or a
/// `cleared` flag when the query is emptied — never the raw query, which may
/// contain a member's name.
///
/// Usage in a State:
/// ```dart
/// final _searchLog = SearchActionLogger('teamMembers');
/// // in the field's onChanged: _searchLog.onQueryChanged(query);
/// // in dispose(): _searchLog.dispose();
/// ```
class SearchActionLogger {
  SearchActionLogger(this.field);

  /// Identifies which search field this is, e.g. 'assignments', 'teamMembers'.
  final String field;

  static const Duration _debounce = Duration(milliseconds: 600);
  Timer? _timer;

  /// Call from the field's `onChanged`. Restarts the debounce timer; the
  /// `filter:search` action fires once the user pauses for [_debounce].
  void onQueryChanged(String query) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      final ctx = <String, Object?>{'field': field};
      if (query.isEmpty) {
        ctx['cleared'] = true;
      } else {
        ctx['queryLen'] = Logger.redact(query);
      }
      Logger.action('filter:search', ctx);
    });
  }

  /// Cancel any pending debounce. Call from the widget's `dispose()`.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
