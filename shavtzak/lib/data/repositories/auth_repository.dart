import '../../core/utils/device_id.dart';
import '../../domain/entities/admin_device.dart';
import '../data_sources/database_interface.dart';

/// Repository for device-based authentication and permissions
/// Manages admin device registration and permission checking
class AuthRepository {
  final DatabaseInterface _database;
  final DeviceIdService _deviceIdService;

  AuthRepository(this._database, this._deviceIdService);

  /// Check if current device has admin access
  Future<bool> isAdmin() async {
    try {
      final deviceId = await _deviceIdService.getDeviceId();
      final adminDevice = await _database.getAdminDevice(deviceId);
      return adminDevice?.isAdmin ?? false;
    } catch (e) {
      // If error, assume no admin access for security
      return false;
    }
  }

  /// Get current admin device (if registered)
  Future<AdminDevice?> getCurrentDevice() async {
    try {
      final deviceId = await _deviceIdService.getDeviceId();
      return await _database.getAdminDevice(deviceId);
    } catch (e) {
      return null;
    }
  }

  /// Register current device
  /// Creates a new admin device entry with viewer permissions by default
  Future<void> registerDevice() async {
    final deviceId = await _deviceIdService.getDeviceId();
    final deviceName = await _deviceIdService.getDeviceName();

    final existing = await _database.getAdminDevice(deviceId);

    if (existing == null) {
      // Create new device entry
      final device = AdminDevice(
        id: deviceId,
        deviceId: deviceId,
        deviceName: deviceName,
        isAdmin: false, // Default to viewer
        addedAt: DateTime.now(),
        lastSeen: DateTime.now(),
      );
      await _database.insertAdminDevice(device);
    } else {
      // Update last seen time
      final updated = AdminDevice(
        id: existing.id,
        deviceId: existing.deviceId,
        deviceName: existing.deviceName,
        isAdmin: existing.isAdmin,
        addedAt: existing.addedAt,
        lastSeen: DateTime.now(),
      );
      await _database.updateAdminDevice(updated);
    }
  }

  /// Get all registered devices (admin only)
  Future<List<AdminDevice>> getAllDevices() async {
    return await _database.getAllAdminDevices();
  }

  /// Grant admin access to a device (admin only)
  Future<void> grantAdminAccess(String deviceId) async {
    final device = await _database.getAdminDevice(deviceId);
    if (device == null) {
      throw Exception('Device not found: $deviceId');
    }

    final updated = AdminDevice(
      id: device.id,
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      isAdmin: true,
      addedAt: device.addedAt,
      lastSeen: device.lastSeen,
    );

    await _database.updateAdminDevice(updated);
  }

  /// Revoke admin access from a device (admin only)
  Future<void> revokeAdminAccess(String deviceId) async {
    final device = await _database.getAdminDevice(deviceId);
    if (device == null) {
      throw Exception('Device not found: $deviceId');
    }

    final updated = AdminDevice(
      id: device.id,
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      isAdmin: false,
      addedAt: device.addedAt,
      lastSeen: device.lastSeen,
    );

    await _database.updateAdminDevice(updated);
  }

  /// Remove a device from the system (admin only)
  Future<void> removeDevice(String deviceId) async {
    await _database.deleteAdminDevice(deviceId);
  }

  /// Get device info for display
  Future<Map<String, String>> getDeviceInfo() async {
    return await _deviceIdService.getDeviceInfo();
  }
}
