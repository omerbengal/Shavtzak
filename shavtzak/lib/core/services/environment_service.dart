// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

/// Service to detect and manage the current environment (test vs production)
/// based on the URL path. Notifies listeners when environment changes.
class EnvironmentService extends ChangeNotifier {
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
    final hash = html.window.location.hash;
    // Remove '#' prefix if it exists, otherwise use empty string
    final currentPath = hash.isNotEmpty ? hash.substring(1) : '';
    final newTestMode = currentPath.startsWith('/test/') || currentPath == '/test';
    developer.log('EnvironmentService.initialize(): hash=$hash, path=$currentPath, newTestMode=$newTestMode', name: 'Environment');
    if (_isTestMode != newTestMode) {
      developer.log('EnvironmentService.initialize(): CHANGING from $_isTestMode to $newTestMode', name: 'Environment');
      _isTestMode = newTestMode;
      notifyListeners();
    }
  }

  /// Returns true if the app is running in test environment
  bool get isTestMode => _isTestMode;

  /// Returns true if the app is running in production environment
  bool get isProductionMode => !_isTestMode;

  /// Returns the environment prefix for Firestore collections
  /// Returns 'test_' for test mode, empty string for production
  String get collectionPrefix {
    final prefix = _isTestMode ? 'test_' : '';
    developer.log('EnvironmentService.collectionPrefix(): isTestMode=$_isTestMode, prefix="$prefix"', name: 'Environment');
    return prefix;
  }

  /// Returns the environment prefix for cache keys
  /// Returns 'test_' for test mode, empty string for production
  String get cachePrefix => _isTestMode ? 'test_' : '';

  /// Returns the base route prefix
  /// Returns '/test' for test mode, empty string for production
  String get routePrefix => _isTestMode ? '/test' : '';

  /// Manually set test mode (useful for testing or direct URL entry)
  void setTestMode(bool isTest) {
    developer.log('EnvironmentService.setTestMode(): called with isTest=$isTest, current _isTestMode=$_isTestMode', name: 'Environment');
    if (_isTestMode != isTest) {
      developer.log('EnvironmentService.setTestMode(): CHANGING from $_isTestMode to $isTest - calling notifyListeners()', name: 'Environment');
      _isTestMode = isTest;
      notifyListeners();
    } else {
      developer.log('EnvironmentService.setTestMode(): NO CHANGE - already $isTest', name: 'Environment');
    }
  }

  /// Update test mode based on a given path
  void updateFromPath(String path) {
    final newTestMode = path.startsWith('/test/') || path == '/test';
    developer.log('EnvironmentService.updateFromPath(): path="$path", newTestMode=$newTestMode, current _isTestMode=$_isTestMode', name: 'Environment');
    if (_isTestMode != newTestMode) {
      developer.log('EnvironmentService.updateFromPath(): CHANGING from $_isTestMode to $newTestMode - calling notifyListeners()', name: 'Environment');
      _isTestMode = newTestMode;
      notifyListeners();
    } else {
      developer.log('EnvironmentService.updateFromPath(): NO CHANGE - already $newTestMode', name: 'Environment');
    }
  }
}
