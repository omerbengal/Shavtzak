import 'package:flutter/foundation.dart';

// Conditional imports for web-specific functionality
import 'environment_service_stub.dart'
    if (dart.library.js) 'environment_service_web.dart';

/// Service to detect and manage the current environment (test vs production)
/// On web: detects from URL path
/// On mobile/desktop: defaults to production, can be manually set
class EnvironmentService extends ChangeNotifier {
  static EnvironmentService? _instance;

  /// Singleton instance
  static EnvironmentService get instance {
    _instance ??= EnvironmentService._();
    return _instance!;
  }

  EnvironmentService._();

  bool _isTestMode = false;

  /// Initialize the environment service by detecting the current environment
  /// On web: detects from URL hash
  /// On mobile/desktop: defaults to production mode
  void initialize() {
    if (kIsWeb) {
      final hash = EnvironmentServiceWeb.getWindowLocationHash();
      EnvironmentServiceWeb.detectFromUrlHash(this, hash);
    } else {
      // On mobile/desktop, default to production mode
      // User can toggle via UI if needed
      _isTestMode = false;
    }
  }

  /// Returns true if the app is running in test environment
  bool get isTestMode => _isTestMode;

  /// Returns true if the app is running in production environment
  bool get isProductionMode => !_isTestMode;

  /// Returns the environment prefix for Firestore collections
  /// Returns 'test_' for test mode, empty string for production
  String get collectionPrefix {
    return _isTestMode ? 'test_' : '';
  }

  /// Returns the environment prefix for cache keys
  /// Returns 'test_' for test mode, empty string for production
  String get cachePrefix => _isTestMode ? 'test_' : '';

  /// Returns the base route prefix
  /// Returns '/test' for test mode, empty string for production
  String get routePrefix => _isTestMode ? '/test' : '';

  /// Manually set test mode (useful for testing or direct URL entry)
  void setTestMode(bool isTest) {
    if (_isTestMode != isTest) {
      _isTestMode = isTest;
      notifyListeners();
    }
  }

  /// Update test mode based on a given path
  void updateFromPath(String path) {
    final newTestMode = path.startsWith('/test/') || path == '/test';
    if (_isTestMode != newTestMode) {
      _isTestMode = newTestMode;
      notifyListeners();
    }
  }
}
