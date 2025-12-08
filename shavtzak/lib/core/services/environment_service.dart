import 'dart:html' as html;

/// Service to detect and manage the current environment (test vs production)
/// based on the URL path.
class EnvironmentService {
  static EnvironmentService? _instance;

  /// Singleton instance
  static EnvironmentService get instance {
    _instance ??= EnvironmentService._();
    return _instance!;
  }

  EnvironmentService._();

  bool _isTestMode = false;

  /// Initialize the environment service by detecting the current URL
  void initialize() {
    final currentPath = html.window.location.pathname ?? '';
    _isTestMode = currentPath.startsWith('/test/') || currentPath == '/test';
  }

  /// Returns true if the app is running in test environment
  bool get isTestMode => _isTestMode;

  /// Returns true if the app is running in production environment
  bool get isProductionMode => !_isTestMode;

  /// Returns the environment prefix for Firestore collections
  /// Returns 'test_' for test mode, empty string for production
  String get collectionPrefix => _isTestMode ? 'test_' : '';

  /// Returns the environment prefix for cache keys
  /// Returns 'test_' for test mode, empty string for production
  String get cachePrefix => _isTestMode ? 'test_' : '';

  /// Returns the base route prefix
  /// Returns '/test' for test mode, empty string for production
  String get routePrefix => _isTestMode ? '/test' : '';

  /// Manually set test mode (useful for testing or direct URL entry)
  void setTestMode(bool isTest) {
    _isTestMode = isTest;
  }

  /// Update test mode based on a given path
  void updateFromPath(String path) {
    _isTestMode = path.startsWith('/test/') || path == '/test';
  }
}
