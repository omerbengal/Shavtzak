// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'environment_service.dart';

/// Service for caching Firestore configuration in browser localStorage
/// Caches Google Drive and Google Calendar configs to avoid slow Firestore reads on startup
class ConfigCacheService {
  // Cache keys with environment prefix
  String get _driveConfigKey =>
      '${EnvironmentService.instance.cachePrefix}drive_config';
  String get _calendarConfigKey =>
      '${EnvironmentService.instance.cachePrefix}calendar_config';

  /// Save Google Drive config to localStorage
  Future<void> saveDriveConfig(Map<String, String?> config) async {
    try {
      final json = jsonEncode(config);
      html.window.localStorage[_driveConfigKey] = json;
    } catch (e) {
      throw ConfigCacheException('Failed to save drive config: $e');
    }
  }

  /// Get Google Drive config from localStorage
  /// Returns null if not cached
  Future<Map<String, String?>?> getDriveConfig() async {
    try {
      final cached = html.window.localStorage[_driveConfigKey];
      if (cached == null || cached.isEmpty) return null;
      final decoded = jsonDecode(cached) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as String?));
    } catch (e) {
      throw ConfigCacheException('Failed to get drive config: $e');
    }
  }

  /// Save Google Calendar config to localStorage
  Future<void> saveCalendarConfig(Map<String, String?> config) async {
    try {
      final json = jsonEncode(config);
      html.window.localStorage[_calendarConfigKey] = json;
    } catch (e) {
      throw ConfigCacheException('Failed to save calendar config: $e');
    }
  }

  /// Get Google Calendar config from localStorage
  /// Returns null if not cached
  Future<Map<String, String?>?> getCalendarConfig() async {
    try {
      final cached = html.window.localStorage[_calendarConfigKey];
      if (cached == null || cached.isEmpty) return null;
      final decoded = jsonDecode(cached) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as String?));
    } catch (e) {
      throw ConfigCacheException('Failed to get calendar config: $e');
    }
  }

  /// Check if Drive config is cached
  Future<bool> hasCachedDriveConfig() async {
    try {
      final cached = html.window.localStorage[_driveConfigKey];
      return cached != null && cached.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check if Calendar config is cached
  Future<bool> hasCachedCalendarConfig() async {
    try {
      final cached = html.window.localStorage[_calendarConfigKey];
      return cached != null && cached.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Clear all cached configs (useful for testing or forced refresh)
  Future<void> clearAll() async {
    try {
      html.window.localStorage.remove(_driveConfigKey);
      html.window.localStorage.remove(_calendarConfigKey);
    } catch (e) {
      throw ConfigCacheException('Failed to clear configs: $e');
    }
  }
}

/// Custom exception for config cache errors
class ConfigCacheException implements Exception {
  final String message;
  ConfigCacheException(this.message);

  @override
  String toString() => 'ConfigCacheException: $message';
}
