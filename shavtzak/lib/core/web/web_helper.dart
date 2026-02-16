import 'package:web/web.dart' as web;

/// Web-specific implementation
/// This file is only imported on web platform
class WebHelper {
  static String getWindowLocationHash() {
    return web.window.location.hash;
  }

  static void reloadPage() {
    web.window.location.reload();
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
}
