import 'package:web/web.dart' as web;

/// Web-specific implementation for environment detection
/// This file is only imported on web platform
class EnvironmentServiceWeb {
  static void detectFromUrlHash(dynamic service, String hash) {
    // Remove '#' prefix if it exists, otherwise use empty string
    final currentPath = hash.isNotEmpty ? hash.substring(1) : '';
    final newTestMode = currentPath.startsWith('/test/') || currentPath == '/test';
    if (service.isTestMode != newTestMode) {
      service.setTestMode(newTestMode);
    }
  }

  static String getWindowLocationHash() {
    return web.window.location.hash;
  }
}
