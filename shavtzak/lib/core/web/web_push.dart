import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart' as impl;

/// The browser's Web Push, through `web/push.js` (`window.shavtzakPush`).
/// Everything a test needs to fake; off the web every call answers "nothing".
abstract class WebPushBridge {
  /// `default`, `granted`, `denied` or `unsupported`.
  String permission();

  /// An iPhone / iPad in the browser rather than the home-screen app, where
  /// notifications do not exist.
  bool iosNotInstalled();

  /// Asks for permission when needed (call it from a tap) and subscribes this
  /// device; the subscription's JSON, or null without permission.
  Future<String?> subscribe(String vapidPublicKey);

  /// The last [subscribe] was refused by the browser at once, without
  /// showing its window (Chrome stops asking a site whose window was closed a
  /// few times). Never on an iPhone.
  bool askedWithoutWindow();

  /// This device's subscription's JSON, or null; never asks anything.
  Future<String?> current();

  /// Drops this device's subscription; its endpoint, or null if none.
  Future<String?> unsubscribe();
}

WebPushBridge createWebPushBridge() => impl.createWebPushBridge();
