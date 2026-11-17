import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../web/web_push.dart';
import 'backend_api_service.dart';

/// Where this device stands with the task notifications.
enum PushStatus {
  /// The browser has no Web Push.
  unsupported,

  /// An iPhone / iPad in the browser: only the home-screen app gets them.
  iosInstallNeeded,

  /// The browser never asked on this device.
  notAsked,

  /// Subscribed and on.
  enabled,

  /// Turned off in the settings (or allowed but not subscribed).
  off,

  /// Refused in the browser's own window; only the phone's or the site's
  /// settings can undo it.
  blocked,

  /// "הפעל התראות" only: the browser refused at once without showing its
  /// window (Chrome's site settings then say "no permission"; Android,
  /// 17/11/2026). Only the site's settings in Chrome can allow it.
  noWindow,
}

/// The server half: the API's `/push/subscribe` and `/push/unsubscribe`.
abstract class PushBackend {
  Future<void> subscribe(Map<String, dynamic> subscription);
  Future<void> unsubscribe(String endpoint);
}

/// What this device remembers about the notifications.
abstract class PushDeviceFlags {
  /// "כיבוי" in the settings: the quiet re-subscribe must not undo it.
  Future<bool> turnedOff();
  Future<void> setTurnedOff(bool value);

  /// The app version "לא עכשיו" was pressed on; the popup returns with the
  /// next version.
  Future<String?> snoozedVersion();
  Future<void> setSnoozedVersion(String? version);
}

/// "שובצת למשימה" notifications on this device (Web Push, design approved by
/// Omer 16/11/2026): the popup's and the settings row's actions, the quiet
/// re-subscribe on every sign-in (the in-app refresh removes the worker and
/// with it the subscription) and the sign-out cleanup.
class PushNotificationService {
  PushNotificationService(this._bridge, this._backend, this._flags);

  static PushNotificationService? _instance;

  static PushNotificationService get instance => _instance ??= PushNotificationService(
        createWebPushBridge(),
        _ApiPushBackend(BackendApiService()),
        _PrefsPushFlags(),
      );

  @visibleForTesting
  static set instance(PushNotificationService value) => _instance = value;

  /// The VAPID public key; the private half is the Functions secret
  /// `WEB_PUSH_VAPID_PRIVATE_KEY` (functions/src/push.ts has the same key).
  static const String vapidPublicKey =
      'BFG-lA4XBV-QImmU-vJNKvD-TssSHXTAvMqFct1B5h9lH_fO0G1kDUoJXng1Sjy6n_3vsoW9XgH_pDls0-XIg80';

  final WebPushBridge _bridge;
  final PushBackend _backend;
  final PushDeviceFlags _flags;

  Future<PushStatus> status() async {
    switch (_bridge.permission()) {
      case 'unsupported':
        return _bridge.iosNotInstalled() ? PushStatus.iosInstallNeeded : PushStatus.unsupported;
      case 'denied':
        return PushStatus.blocked;
      case 'granted':
        if (await _flags.turnedOff()) return PushStatus.off;
        return await _bridge.current() != null ? PushStatus.enabled : PushStatus.off;
      default:
        return await _flags.turnedOff() ? PushStatus.off : PushStatus.notAsked;
    }
  }

  /// Whether the popup opens: this device was never asked (or is an iPhone in
  /// the browser) and "לא עכשיו" was not pressed on [appVersion].
  Future<bool> shouldPrompt(PushStatus status, String? appVersion) async {
    if (status != PushStatus.notAsked && status != PushStatus.iosInstallNeeded) return false;
    return await _flags.snoozedVersion() != (appVersion ?? '');
  }

  Future<void> snooze(String? appVersion) => _flags.setSnoozedVersion(appVersion ?? '');

  /// "הפעל התראות" (call it straight from the tap: iPhone asks only then).
  Future<PushStatus> enable() async {
    final json = await _bridge.subscribe(vapidPublicKey);
    if (json == null) {
      final now = await status();
      if (now == PushStatus.notAsked && _bridge.askedWithoutWindow()) {
        debugPrint('push: the browser refused without showing its window');
        return PushStatus.noWindow;
      }
      return now;
    }
    await _backend.subscribe(jsonDecode(json) as Map<String, dynamic>);
    await _flags.setTurnedOff(false);
    return PushStatus.enabled;
  }

  /// "כיבוי" in the settings.
  Future<PushStatus> disable() async {
    await _flags.setTurnedOff(true);
    final endpoint = await _bridge.unsubscribe();
    if (endpoint != null) await _backend.unsubscribe(endpoint);
    return PushStatus.off;
  }

  /// On every sign-in: when this browser already allows notifications and
  /// they were not turned off here, (re)subscribe without asking and tell
  /// the server, which also moves the device to the member now signed in.
  Future<void> syncSilently({required bool canReceive}) async {
    try {
      if (!canReceive) return;
      if (_bridge.permission() != 'granted' || await _flags.turnedOff()) return;
      final json = await _bridge.current() ?? await _bridge.subscribe(vapidPublicKey);
      if (json == null) return;
      await _backend.subscribe(jsonDecode(json) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('push: quiet re-subscribe failed: $error');
    }
  }

  /// Before a sign-out: the server stops sending to this device. The browser
  /// keeps its subscription, for whoever signs in next ([syncSilently]).
  Future<void> forgetDevice() async {
    try {
      final json = await _bridge.current();
      if (json == null) return;
      final endpoint = (jsonDecode(json) as Map<String, dynamic>)['endpoint'];
      if (endpoint is String) await _backend.unsubscribe(endpoint);
    } catch (error) {
      debugPrint('push: forgetting the device failed: $error');
    }
  }
}

class _ApiPushBackend implements PushBackend {
  _ApiPushBackend(this._api);

  final BackendApiService _api;

  /// A returning member's app opens on a saved snapshot before Firebase has
  /// restored its credential; wait for it (briefly) rather than fail.
  Future<void> _signedIn() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance
        .authStateChanges()
        .firstWhere((user) => user != null)
        .timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> subscribe(Map<String, dynamic> subscription) async {
    await _signedIn();
    await _api.post(
      'push/subscribe',
      requireAuth: true,
      body: {
        'subscription': subscription,
        'origin': Uri.base.replace(query: '', fragment: '').toString(),
      },
    );
  }

  @override
  Future<void> unsubscribe(String endpoint) async {
    await _api.post('push/unsubscribe', requireAuth: true, body: {'endpoint': endpoint});
  }
}

class _PrefsPushFlags implements PushDeviceFlags {
  static const _offKey = 'push_turned_off';
  static const _snoozeKey = 'push_snoozed_version';

  @override
  Future<bool> turnedOff() async => (await SharedPreferences.getInstance()).getBool(_offKey) ?? false;

  @override
  Future<void> setTurnedOff(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_offKey, value);

  @override
  Future<String?> snoozedVersion() async => (await SharedPreferences.getInstance()).getString(_snoozeKey);

  @override
  Future<void> setSnoozedVersion(String? version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version == null) {
      await prefs.remove(_snoozeKey);
    } else {
      await prefs.setString(_snoozeKey, version);
    }
  }
}
