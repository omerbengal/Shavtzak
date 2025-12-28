import 'package:equatable/equatable.dart';

/// A template item within a preset
class PresetItem extends Equatable {
  final String name;
  final String responsibleId;
  final List<String> ccIds;
  final String adminNote;

  const PresetItem({
    required this.name,
    required this.responsibleId,
    this.ccIds = const [],
    this.adminNote = '',
  });

  PresetItem copyWith({
    String? name,
    String? responsibleId,
    List<String>? ccIds,
    String? adminNote,
  }) {
    return PresetItem(
      name: name ?? this.name,
      responsibleId: responsibleId ?? this.responsibleId,
      ccIds: ccIds ?? this.ccIds,
      adminNote: adminNote ?? this.adminNote,
    );
  }

  @override
  List<Object?> get props => [name, responsibleId, ccIds, adminNote];

  @override
  String toString() => 'PresetItem{name: $name, responsibleId: $responsibleId}';
}

/// A checklist preset containing template items
class Preset extends Equatable {
  final String id;
  final String name;
  final List<PresetItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Preset({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  Preset copyWith({
    String? id,
    String? name,
    List<PresetItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Preset(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, items, createdAt, updatedAt];

  @override
  String toString() => 'Preset{id: $id, name: $name, items: ${items.length}}';
}
