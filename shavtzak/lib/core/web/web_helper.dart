import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Defined in web/index.html: installs a newer build the service worker
/// found, then reloads. Null when the page has no such hook.
@JS('shavtzakReloadToLatest')
external JSFunction? get _reloadToLatest;

/// Web-specific implementation
/// This file is only imported on web platform
class WebHelper {
  static String getWindowLocationHash() {
    return web.window.location.hash;
  }

  /// Reload onto the latest deployed build. A plain reload would be served
  /// the build the service worker has cached, which may be the old one.
  static void reloadPage() {
    final reloadToLatest = _reloadToLatest;
    if (reloadToLatest != null) {
      reloadToLatest.callAsFunction();
    } else {
      web.window.location.reload();
    }
  }

  static void hideSplashScreen() {
    try {
      final splash = web.document.getElementById('splash-screen');
      if (splash != null) {
        splash.classList.add('splash-hidden');
        Future.delayed(const Duration(milliseconds: 300), () {
          splash.remove();
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  static void removeLocalStorageItem(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (e) {
      // Ignore errors
    }
  }
}
