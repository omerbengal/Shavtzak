import 'package:shared_preferences/shared_preferences.dart';
import 'environment_service.dart';

/// Service for managing user selection cache using shared_preferences
/// Handles persistence across sessions and multiple contexts (web, mobile, desktop)
class UserCacheService {
  // Cache key with environment prefix
  String get _selectedUserKey =>
      '${EnvironmentService.instance.cachePrefix}selected_user_unique_key';
  // Legacy opaque backend session cache key. Kept only for cleanup during migration.
  String get _sessionTokenKey =>
      '${EnvironmentService.instance.cachePrefix}selected_user_session_token';

  /// Save the selected user's unique key to persistent storage
  Future<void> saveSelectedUser(String uniqueKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedUserKey, uniqueKey);
    } catch (e) {
      throw UserCacheException('Failed to save selected user: $e');
    }
  }

  /// Get the selected user's unique key from persistent storage
  /// Returns null if no user is cached
  Future<String?> getSelectedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedUserKey);
    } catch (e) {
      throw UserCacheException('Failed to get selected user: $e');
    }
  }

  /// Clear the selected user from persistent storage
  Future<void> clearSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_selectedUserKey);
      await prefs.remove(_sessionTokenKey);
    } catch (e) {
      throw UserCacheException('Failed to clear user selection: $e');
    }
  }

  /// Check if there's a cached user selection
  Future<bool> hasCachedUser() async {
    try {
      final cachedUser = await getSelectedUser();
      return cachedUser != null && cachedUser.isNotEmpty;
    } catch (e) {
      // If there's an error accessing storage, assume no cached user
      return false;
    }
  }

  /// Legacy method retained for cleanup compatibility.
  Future<void> saveSessionToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionTokenKey, token);
    } catch (e) {
      throw UserCacheException('Failed to save session token: $e');
    }
  }

  Future<String?> getSessionToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_sessionTokenKey);
    } catch (e) {
      throw UserCacheException('Failed to get session token: $e');
    }
  }

  Future<void> clearSessionToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionTokenKey);
    } catch (e) {
      throw UserCacheException('Failed to clear session token: $e');
    }
  }

  /// Get the selected user's unique key synchronously from cache
  /// Note: On web this works synchronously, on mobile it may return null on first call
  /// Use getSelectedUser() for reliable async access
  String? getSelectedUserKeySync() {
    try {
      // Try to get cached value synchronously (works if SharedPreferences has been initialized)
      // This is a best-effort synchronous access
      return null; // SharedPreferences doesn't support synchronous access
    } catch (e) {
      // If there's an error accessing storage, return null
      return null;
    }
  }

  // In-memory flag to track if passcode dialog has been shown in current app session
  // This resets when the app is fully closed and reopened (not just on route navigation)
  static bool _hasShownPasscodeDialogThisSession = false;

  /// Check if the passcode requirement dialog has been shown this app session
  /// Note: This is an in-memory flag that resets when the app is closed
  bool hasPasscodeDialogBeenShownThisSession() {
    return _hasShownPasscodeDialogThisSession;
  }

  /// Mark that the passcode requirement dialog has been shown this app session
  /// Note: This is an in-memory flag that resets when the app is closed
  void markPasscodeDialogShownThisSession() {
    _hasShownPasscodeDialogThisSession = true;
  }

  /// Clear the passcode dialog shown flag (called when user logs out)
  void clearPasscodeDialogFlag() {
    _hasShownPasscodeDialogThisSession = false;
  }
}

/// Custom exception for user cache errors
class UserCacheException implements Exception {
  final String message;
  UserCacheException(this.message);

  @override
  String toString() => 'UserCacheException: $message';
}
