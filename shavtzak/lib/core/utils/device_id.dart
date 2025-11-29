import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Service for managing device identification
/// This is used for the device-based permission system (admin vs viewer)
class DeviceIdService {
  static const String _deviceIdKey = 'device_id';
  static const String _deviceNameKey = 'device_name';

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Get the unique device ID
  /// If no ID exists, generates and stores a new UUID
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null) {
      // Generate new UUID for this device
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }

  /// Get a human-readable device name
  Future<String> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    String? cachedName = prefs.getString(_deviceNameKey);

    if (cachedName != null) {
      return cachedName;
    }

    // Generate device name based on platform
    String deviceName;

    if (kIsWeb) {
      final webInfo = await _deviceInfo.webBrowserInfo;
      deviceName =
          '${webInfo.browserName.name} על ${webInfo.platform ?? 'לא ידוע'}';
    } else {
      // For future mobile/desktop support
      deviceName = 'מכשיר לא ידוע';
    }

    // Cache the device name
    await prefs.setString(_deviceNameKey, deviceName);
    return deviceName;
  }

  /// Clear device ID (for testing purposes)
  Future<void> clearDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_deviceNameKey);
  }

  /// Get device info for display
  Future<Map<String, String>> getDeviceInfo() async {
    final id = await getDeviceId();
    final name = await getDeviceName();

    return {
      'id': id,
      'name': name,
    };
  }
}
