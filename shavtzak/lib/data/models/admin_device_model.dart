import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/admin_device.dart';

/// Data model for AdminDevice with JSON serialization
class AdminDeviceModel {
  final String id;
  final String deviceId;
  final String deviceName;
  final bool isAdmin;
  final DateTime addedAt;
  final DateTime lastSeen;

  const AdminDeviceModel({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.isAdmin,
    required this.addedAt,
    required this.lastSeen,
  });

  /// Convert from domain entity
  factory AdminDeviceModel.fromEntity(AdminDevice entity) {
    return AdminDeviceModel(
      id: entity.id,
      deviceId: entity.deviceId,
      deviceName: entity.deviceName,
      isAdmin: entity.isAdmin,
      addedAt: entity.addedAt,
      lastSeen: entity.lastSeen,
    );
  }

  /// Convert to domain entity
  AdminDevice toEntity() {
    return AdminDevice(
      id: id,
      deviceId: deviceId,
      deviceName: deviceName,
      isAdmin: isAdmin,
      addedAt: addedAt,
      lastSeen: lastSeen,
    );
  }

  /// Convert from Firestore document
  factory AdminDeviceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AdminDeviceModel(
      id: doc.id,
      deviceId: data['deviceId'] as String,
      deviceName: data['deviceName'] as String? ?? 'Unknown Device',
      isAdmin: data['isAdmin'] as bool? ?? false,
      addedAt: (data['addedAt'] as Timestamp).toDate(),
      lastSeen: (data['lastSeen'] as Timestamp).toDate(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'isAdmin': isAdmin,
      'addedAt': Timestamp.fromDate(addedAt),
      'lastSeen': Timestamp.fromDate(lastSeen),
    };
  }

  /// Convert from JSON
  factory AdminDeviceModel.fromJson(Map<String, dynamic> json) {
    return AdminDeviceModel(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String? ?? 'Unknown Device',
      isAdmin: json['isAdmin'] as bool? ?? false,
      addedAt: DateTime.parse(json['addedAt'] as String),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'isAdmin': isAdmin,
      'addedAt': addedAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
    };
  }
}
