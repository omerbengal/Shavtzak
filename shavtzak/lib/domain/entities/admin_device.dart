import 'package:equatable/equatable.dart';

/// Admin device entity for device-based permissions
class AdminDevice extends Equatable {
  final String id;
  final String deviceId; // Unique device identifier
  final String deviceName; // Human-readable device name
  final bool isAdmin; // Whether this device has admin privileges
  final DateTime addedAt;
  final DateTime lastSeen;

  const AdminDevice({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.isAdmin,
    required this.addedAt,
    required this.lastSeen,
  });

  /// Check if this device has admin privileges
  bool get hasAdminAccess => isAdmin;

  /// Copy with method for immutability
  AdminDevice copyWith({
    String? id,
    String? deviceId,
    String? deviceName,
    bool? isAdmin,
    DateTime? addedAt,
    DateTime? lastSeen,
  }) {
    return AdminDevice(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      isAdmin: isAdmin ?? this.isAdmin,
      addedAt: addedAt ?? this.addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => [
        id,
        deviceId,
        deviceName,
        isAdmin,
        addedAt,
        lastSeen,
      ];

  @override
  String toString() => 'AdminDevice($deviceId, $deviceName, admin: $isAdmin)';
}
