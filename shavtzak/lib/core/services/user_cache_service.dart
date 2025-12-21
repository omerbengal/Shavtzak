// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'environment_service.dart';

/// Service for managing user selection cache in browser localStorage
/// Handles persistence across browser sessions and multiple contexts (desktop, mobile, PWA)
class UserCacheService {
  // Cache key with environment prefix
  String get _selectedUserKey =>
      '${EnvironmentService.instance.cachePrefix}selected_user_unique_key';

  /// Save the selected user's unique key to localStorage
  Future<void> saveSelectedUser(String uniqueKey) async {
    try {
      html.window.localStorage[_selectedUserKey] = uniqueKey;
    } catch (e) {
      throw UserCacheException('Failed to save selected user: $e');
    }
  }

  /// Get the selected user's unique key from localStorage
  /// Returns null if no user is cached
  Future<String?> getSelectedUser() async {
    try {
      return html.window.localStorage[_selectedUserKey];
    } catch (e) {
      throw UserCacheException('Failed to get selected user: $e');
    }
  }

  /// Clear the selected user from localStorage
  Future<void> clearSelection() async {
    try {
      html.window.localStorage.remove(_selectedUserKey);
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
      // If there's an error accessing localStorage, assume no cached user
      return false;
    }
  }
}

/// Custom exception for user cache errors
class UserCacheException implements Exception {
  final String message;
  UserCacheException(this.message);

  @override
  String toString() => 'UserCacheException: $message';
}