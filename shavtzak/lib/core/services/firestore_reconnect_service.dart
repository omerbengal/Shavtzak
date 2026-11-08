import 'dart:async';

import 'package:flutter/widgets.dart';

import '../debug/logger.dart';

/// Reopens Firestore's live connection once it is known to be stuck.
///
/// The connection the app's listeners share can stop delivering without an
/// error (seen on a phone, 2026-11-08: a stage save landed, the screen kept
/// the old contacts until a refresh). Taking the network down and up again
/// makes the SDK open a fresh connection; every listener stays subscribed and
/// receives whatever it missed, so no bloc has to resubscribe.
///
/// Reconnects only on proof that the connection is stuck, never just in case:
/// - a save the backend accepted that has not come back through the stream
///   (see `TaskBloc`'s `onStaleStream`), or
/// - a [check] that did not answer: when the app comes back into view, or the
///   device back online, one tiny document is read from the server through the
///   same connection the listeners use. An answer (one read) means it is
///   alive and nothing else happens; no answer within [checkTimeout] means it
///   is stuck. An error is not a stuck connection (a lost session, say) and
///   does not reconnect.
///
/// Writes go through the backend, not the SDK, so nothing is queued or lost
/// while the network is down for that moment.
class FirestoreReconnectService {
  FirestoreReconnectService({
    required Future<void> Function() disableNetwork,
    required Future<void> Function() enableNetwork,
    required Future<void> Function() probe,
    this.minInterval = const Duration(seconds: 3),
    this.minHidden = const Duration(seconds: 2),
    this.checkTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _disableNetwork = disableNetwork,
        _enableNetwork = enableNetwork,
        _probe = probe,
        _clock = clock ?? DateTime.now;

  final Future<void> Function() _disableNetwork;
  final Future<void> Function() _enableNetwork;
  final Future<void> Function() _probe;
  final DateTime Function() _clock;

  /// How long the app must have been out of view for its return to check.
  final Duration minHidden;

  /// How long the check waits for the server before calling it stuck.
  final Duration checkTimeout;

  Future<void>? _checking;
  DateTime? _hiddenAt;
  AppLifecycleListener? _lifecycle;

  /// Checks the connection whenever the app comes back into view.
  void watchVisibility() {
    _lifecycle ??= AppLifecycleListener(onHide: onHidden, onShow: onShown);
  }

  /// The app went out of view.
  void onHidden() => _hiddenAt ??= _clock();

  /// The app came back into view.
  void onShown() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null) return;
    final hidden = _clock().difference(hiddenAt);
    if (hidden < minHidden) return;
    unawaited(check('shown:${hidden.inSeconds}s'));
  }

  /// Asks the server for one tiny document through the live connection, and
  /// reconnects only when no answer comes. A call while a check runs joins it.
  Future<void> check(String reason) {
    return _checking ??= _check(reason).whenComplete(() => _checking = null);
  }

  Future<void> _check(String reason) async {
    final started = _clock();
    try {
      await _probe().timeout(checkTimeout);
    } on TimeoutException {
      Logger.warning('firestore:checkTimedOut', {'reason': reason});
      await reconnect('check:$reason');
      return;
    } catch (error) {
      Logger.warning('firestore:checkFailed', {
        'reason': reason,
        'error': '$error',
      });
      return;
    }
    Logger.action('firestore:checkOk', {
      'reason': reason,
      'ms': _clock().difference(started).inMilliseconds,
    });
  }

  /// The shortest gap between two reconnects; requests inside it are dropped.
  final Duration minInterval;

  Future<void>? _running;
  DateTime? _lastDone;

  /// Closes and reopens the connection. A call while one is running joins
  /// it; a call just after one finished is dropped.
  Future<void> reconnect(String reason) {
    final running = _running;
    if (running != null) return running;
    final lastDone = _lastDone;
    if (lastDone != null && _clock().difference(lastDone) < minInterval) {
      return Future<void>.value();
    }
    Logger.warning('firestore:reconnect', {'reason': reason});
    final run = _run();
    _running = run;
    return run;
  }

  Future<void> _run() async {
    try {
      await _disableNetwork();
    } catch (error) {
      Logger.warning('firestore:reconnectFailed', {'step': 'disable', 'error': '$error'});
    }
    try {
      await _enableNetwork();
    } catch (error) {
      Logger.warning('firestore:reconnectFailed', {'step': 'enable', 'error': '$error'});
    } finally {
      _lastDone = _clock();
      _running = null;
    }
  }

  void dispose() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
