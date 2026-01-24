/// Stub implementation for mobile/desktop platforms
/// This file is imported on non-web platforms
class EnvironmentServiceWeb {
  static void detectFromUrlHash(dynamic service, String hash) {
    // On mobile/desktop, don't detect from URL - always use production mode
    // User can toggle via UI if needed
  }

  static String getWindowLocationHash() {
    return '';
  }
}
