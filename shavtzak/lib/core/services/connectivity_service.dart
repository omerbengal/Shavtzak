import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

// Conditional import for web
import 'connectivity_service_stub.dart'
    if (dart.library.html) 'connectivity_service_web.dart' as platform;

/// Service that monitors internet connectivity status.
/// Uses browser's navigator.onLine API for web platform.
/// Only used in test mode to show blocking dialog when offline.
class ConnectivityService extends ChangeNotifier {
  static ConnectivityService? _instance;

  static ConnectivityService get instance {
    _instance ??= ConnectivityService._internal();
    return _instance!;
  }

  bool _isOnline = true;
  StreamSubscription<bool>? _subscription;

  ConnectivityService._internal();

  /// Whether the device currently has internet connectivity
  bool get isOnline => _isOnline;

  /// Whether the device is currently offline
  bool get isOffline => !_isOnline;

  /// Initialize the connectivity monitoring
  void initialize() {
    developer.log('ConnectivityService: Initializing...', name: 'Connectivity');

    // Get initial status
    _isOnline = platform.getOnlineStatus();
    developer.log('ConnectivityService: Initial status - ${_isOnline ? "online" : "offline"}',
        name: 'Connectivity');

    // Listen for changes
    _subscription?.cancel();
    _subscription = platform.onConnectivityChanged().listen((isOnline) {
      if (_isOnline != isOnline) {
        developer.log('ConnectivityService: Status changed to ${isOnline ? "online" : "offline"}',
            name: 'Connectivity');
        _isOnline = isOnline;
        notifyListeners();
      }
    });
  }

  /// Dispose of the service
  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  /// Force check the current connectivity status
  void checkConnectivity() {
    final newStatus = platform.getOnlineStatus();
    if (_isOnline != newStatus) {
      _isOnline = newStatus;
      notifyListeners();
    }
  }
}
