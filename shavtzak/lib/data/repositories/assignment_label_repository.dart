import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/assignment_label_palette.dart';
import '../../domain/entities/assignment_label.dart';
import '../data_sources/database_interface.dart';

class AssignmentLabelRepository {
  final DatabaseInterface _database;

  AssignmentLabelRepository(this._database);

  // Single shared stream: one underlying Firestore listener feeds all
  // StreamBuilders, and shareValue() replays the latest list to late
  // subscribers so rebuilds/navigation don't re-read the collection.
  Stream<List<AssignmentLabel>>? _sharedLabels;

  Stream<List<AssignmentLabel>> watchAssignmentLabels() {
    return _sharedLabels ??=
        _database.watchAssignmentLabels().map(_sortLabels).shareValue();
  }

  Stream<List<AssignmentLabel>> watchActiveAssignmentLabels() {
    return watchAssignmentLabels().map(
      (labels) => labels.where((label) => label.isActive).toList(),
    );
  }

  Future<List<AssignmentLabel>> getAssignmentLabels() async {
    return _sortLabels(await _database.getAssignmentLabels());
  }

  Future<AssignmentLabel> createAssignmentLabel({
    required String hebrewName,
    String? color,
  }) async {
    final trimmedName = _normalizeLabelName(hebrewName);
    final existingLabels = await getAssignmentLabels();
    _ensureNameIsUnique(trimmedName, existingLabels);

    final now = DateTime.now();
    final maxSortOrder = existingLabels.isEmpty
        ? -1
        : existingLabels
            .map((label) => label.sortOrder)
            .reduce((a, b) => a > b ? a : b);
    final id = const Uuid().v4();
    final label = AssignmentLabel(
      id: id,
      key: id,
      hebrewName: trimmedName,
      color: color ?? AssignmentLabelPalette.defaultColor,
      sortOrder: maxSortOrder + 1,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    await _database.insertAssignmentLabel(label);
    return label;
  }

  Future<AssignmentLabel> updateAssignmentLabel({
    required AssignmentLabel label,
    required String hebrewName,
    required String color,
  }) async {
    final trimmedName = _normalizeLabelName(hebrewName);
    final existingLabels = await getAssignmentLabels();
    _ensureNameIsUnique(trimmedName, existingLabels, excludeId: label.id);

    final updatedLabel = label.copyWith(
      hebrewName: trimmedName,
      color: color,
      updatedAt: DateTime.now(),
    );

    await _database.updateAssignmentLabel(updatedLabel);
    return updatedLabel;
  }

  Future<void> archiveAssignmentLabel(String labelId) async {
    await _database.archiveAssignmentLabel(labelId);
  }

  Future<void> restoreAssignmentLabel(String labelId) async {
    await _database.restoreAssignmentLabel(labelId);
  }

  Future<void> deleteAssignmentLabel(String labelId) async {
    await _database.deleteAssignmentLabel(labelId);
  }

  Future<void> reorderAssignmentLabels(
    List<AssignmentLabel> reorderedLabels,
  ) async {
    final labelIdToSortOrder = <String, int>{};
    for (int index = 0; index < reorderedLabels.length; index++) {
      labelIdToSortOrder[reorderedLabels[index].id] = index;
    }
    await _database.updateAssignmentLabelsSortOrder(labelIdToSortOrder);
  }

  String _normalizeLabelName(String hebrewName) {
    final trimmedName = hebrewName.trim();
    if (trimmedName.isEmpty) {
      throw Exception('יש להזין שם ללייבל');
    }
    return trimmedName;
  }

  void _ensureNameIsUnique(
    String normalizedName,
    List<AssignmentLabel> existingLabels, {
    String? excludeId,
  }) {
    AssignmentLabel? duplicateLabel;
    for (final label in existingLabels) {
      final isDuplicate = label.id != excludeId &&
          label.hebrewName.trim().toLowerCase() == normalizedName.toLowerCase();
      if (isDuplicate) {
        duplicateLabel = label;
        break;
      }
    }
    if (duplicateLabel != null) {
      throw Exception(
        duplicateLabel.isActive
            ? 'קיים כבר לייבל בשם הזה'
            : 'קיים כבר לייבל בשם הזה (בארכיון)',
      );
    }
  }

  List<AssignmentLabel> _sortLabels(List<AssignmentLabel> labels) {
    final sorted = List<AssignmentLabel>.from(labels);
    sorted.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.hebrewName.compareTo(b.hebrewName);
    });
    return sorted;
  }
}
