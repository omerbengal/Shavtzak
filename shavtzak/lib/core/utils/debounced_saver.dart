import 'dart:async';

import 'package:flutter/foundation.dart';

import 'crud_action_result.dart';

/// Saves one field of a record as it changes, with no save button (Omer,
/// 16/11/2026: "שינוי של צ'קבוקס - ישר שומר").
///
/// Every change is shown at once through [onDraft], but sent only after
/// [delay] without another change, so rapid ticks become ONE call carrying
/// the whole current selection (the last state wins). One call per field is
/// in flight at a time: a change made while it is out is sent when it
/// returns, so the backend never receives an older value after a newer one.
///
/// A value [validate] refuses is not sent and not shown: [error] holds the
/// message for the picker, and the record keeps its last saved value. A
/// refused call takes the change back ([onDraft] null, [revision] bumped so
/// an open picker re-reads the saved value) and reports [onFailure].
/// [flush] sends a waiting change at once (the picker closed).
class DebouncedSaver<T> extends ChangeNotifier {
  DebouncedSaver({
    required this.send,
    required this.onDraft,
    this.validate,
    this.onFailure,
    this.delay = defaultDelay,
  });

  /// How long a change waits for the next one.
  static const Duration defaultDelay = Duration(milliseconds: 600);

  /// Sends a value; called with one value at a time.
  final Future<CrudActionResult> Function(T value) send;

  /// Shows [value] over the record until it is sent; null = show the record
  /// as it is. Called with the value itself right before [send], so the
  /// caller can hand it over to its optimistic overlay in one step.
  final void Function(T? value) onDraft;
  final String? Function(T value)? validate;
  final void Function(String message)? onFailure;
  final Duration delay;

  Timer? _timer;
  bool _waiting = false;
  late T _latest;
  bool _inFlight = false;
  bool _disposed = false;
  String? _error;
  int _revision = 0;

  /// Why the picker's selection is not being saved; null when it is.
  String? get error => _error;

  /// Bumped when a refused call took a change back.
  int get revision => _revision;

  /// Whether a change waits or is on its way.
  bool get isBusy => _waiting || _inFlight;

  /// A change: shown at once, sent after [delay] unless another comes first.
  void change(T value) {
    if (_disposed) return;
    final error = validate?.call(value);
    _error = error;
    if (error != null) {
      // Keep the last saved value: nothing waits, nothing is shown.
      _timer?.cancel();
      _timer = null;
      if (_waiting) {
        _waiting = false;
        onDraft(null);
      }
      notifyListeners();
      return;
    }
    _latest = value;
    _waiting = true;
    onDraft(value);
    _timer?.cancel();
    _timer = Timer(delay, _dispatch);
    notifyListeners();
  }

  /// Sends a waiting change now (the picker closed).
  void flush() {
    _timer?.cancel();
    _timer = null;
    _error = null;
    if (_waiting) _dispatch();
  }

  /// Drops a waiting change: something newer replaces the whole field.
  void discard() {
    _timer?.cancel();
    _timer = null;
    _error = null;
    if (_waiting) {
      _waiting = false;
      onDraft(null);
    }
  }

  Future<void> _dispatch() async {
    _timer?.cancel();
    _timer = null;
    // The call out now sends this one when it returns.
    if (_inFlight || !_waiting) return;
    final value = _latest;
    _waiting = false;
    _inFlight = true;
    final result = await send(value);
    _inFlight = false;
    if (result.isFailure) {
      // Take everything back, a change made meanwhile too: it was built on
      // the refused one.
      _timer?.cancel();
      _timer = null;
      if (_waiting) {
        _waiting = false;
        onDraft(null);
      }
      _revision++;
      onFailure?.call(result.message ?? 'השמירה נכשלה');
      if (!_disposed) notifyListeners();
      return;
    }
    // A change that waited for this call goes now if its time has come
    // (or the picker is gone); otherwise its own timer sends it.
    if (_waiting && (_timer == null || _disposed)) _dispatch();
  }

  /// Sends a waiting change before going: closing the task does not lose it.
  @override
  void dispose() {
    flush();
    _disposed = true;
    super.dispose();
  }
}
