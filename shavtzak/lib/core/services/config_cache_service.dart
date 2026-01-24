import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'environment_service.dart';

/// Service for caching Firestore configuration using shared_preferences
/// Caches Google Drive and Google Calendar configs to avoid slow Firestore reads on startup
class ConfigCacheService {
  // Cache keys with environment prefix
  String get _driveConfigKey =>
      '${EnvironmentService.instance.cachePrefix}drive_config';
  String get _calendarConfigKey =>
      '${EnvironmentService.instance.cachePrefix}calendar_config';

  /// Save Google Drive config to persistent storage
  Future<void> saveDriveConfig(Map<String, String?> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(config);
      await prefs.setString(_driveConfigKey, json);
    } catch (e) {
      throw ConfigCacheException('Failed to save drive config: $e');
    }
  }

  /// Get Google Drive config from persistent storage
  /// Returns null if not cached
  Future<Map<String, String?>?> getDriveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_driveConfigKey);
      if (cached == null || cached.isEmpty) return null;
      final decoded = jsonDecode(cached) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as String?));
    } catch (e) {
      throw ConfigCacheException('Failed to get drive config: $e');
    }
  }

  /// Save Google Calendar config to persistent storage
  Future<void> saveCalendarConfig(Map<String, String?> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(config);
      await prefs.setString(_calendarConfigKey, json);
    } catch (e) {
      throw ConfigCacheException('Failed to save calendar config: $e');
    }
  }

  /// Get Google Calendar config from persistent storage
  /// Returns null if not cached
  Future<Map<String, String?>?> getCalendarConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_calendarConfigKey);
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
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_driveConfigKey);
      return cached != null && cached.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check if Calendar config is cached
  Future<bool> hasCachedCalendarConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_calendarConfigKey);
      return cached != null && cached.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Clear all cached configs (useful for testing or forced refresh)
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_driveConfigKey);
      await prefs.remove(_calendarConfigKey);
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
