import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/preset.dart';

/// Model for converting between PresetItem and Firestore data
class PresetItemModel {
  /// Creates a PresetItem from Firestore map data
  static PresetItem fromFirestore(Map<String, dynamic> data) {
    // Handle ccIds field - could be List<dynamic> or List<String>
    List<String> ccIds = [];
    if (data['ccIds'] != null) {
      ccIds = (data['ccIds'] as List).map((e) => e.toString()).toList();
    }

    return PresetItem(
      name: data['name'] as String,
      responsibleId: data['responsibleId'] as String,
      ccIds: ccIds,
      adminNote: data['adminNote'] as String? ?? '',
    );
  }

  /// Converts a PresetItem to Firestore map data
  static Map<String, dynamic> toFirestore(PresetItem item) {
    return {
      'name': item.name,
      'responsibleId': item.responsibleId,
      'ccIds': item.ccIds,
      'adminNote': item.adminNote,
    };
  }
}

/// Model for converting between Preset entities and Firestore documents
class PresetModel {
  /// Creates a Preset from a Firestore document
  static Preset fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Handle items field
    List<PresetItem> items = [];
    if (data['items'] != null) {
      final itemsList = data['items'] as List;
      items = itemsList
          .map((item) => PresetItemModel.fromFirestore(item as Map<String, dynamic>))
          .toList();
    }

    return Preset(
      id: doc.id,
      name: data['name'] as String,
      items: items,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Converts a Preset entity to a Firestore document
  static Map<String, dynamic> toFirestore(Preset preset) {
    return {
      'name': preset.name,
      'items': preset.items.map((item) => PresetItemModel.toFirestore(item)).toList(),
      'createdAt': Timestamp.fromDate(preset.createdAt),
      'updatedAt': Timestamp.fromDate(preset.updatedAt),
    };
  }
}
