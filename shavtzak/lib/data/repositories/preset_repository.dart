import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/preset.dart';
import '../../core/services/environment_service.dart';
import '../data_sources/database_interface.dart';
import '../models/preset_model.dart';

/// Repository for managing checklist presets with real-time updates
class PresetRepository {
  final DatabaseInterface _database;

  PresetRepository(this._database);

  String _getEnvironmentPrefix() {
    return EnvironmentService.instance.collectionPrefix;
  }

  /// Get all presets (one-time)
  Future<List<Preset>> getPresets() async {
    return await _database.getPresets();
  }

  /// Watch all presets for real-time updates
  Stream<List<Preset>> watchPresets() {
    return FirebaseFirestore.instance
        .collection('${_getEnvironmentPrefix()}checklist_presets')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      developer.log('PresetRepository: Processing ${snapshot.docs.length} presets', name: 'Preset');
      return snapshot.docs
          .map((doc) => PresetModel.fromFirestore(doc))
          .toList();
    }).handleError((error, stackTrace) {
      developer.log('Error watching presets: $error', name: 'Preset', error: error, stackTrace: stackTrace);
      return <Preset>[];
    });
  }

  /// Get a preset by ID
  Future<Preset?> getPresetById(String id) async {
    return await _database.getPresetById(id);
  }

  /// Create a new preset
  Future<void> createPreset(Preset preset) async {
    await _database.insertPreset(preset);
    developer.log('PresetRepository: Created preset ${preset.id} (${preset.name})', name: 'Preset');
  }

  /// Update an existing preset
  Future<void> updatePreset(Preset preset) async {
    await _database.updatePreset(preset);
    developer.log('PresetRepository: Updated preset ${preset.id} (${preset.name})', name: 'Preset');
  }

  /// Delete a preset
  Future<void> deletePreset(String id) async {
    await _database.deletePreset(id);
    developer.log('PresetRepository: Deleted preset $id', name: 'Preset');
  }

  /// Load a preset into an event (creates checklist items from template)
  Future<void> loadPresetIntoEvent(String presetId, String eventId, String creatorAdminId) async {
    await _database.loadPresetIntoEvent(presetId, eventId, creatorAdminId);
    developer.log('PresetRepository: Loaded preset $presetId into event $eventId', name: 'Preset');
  }

  void dispose() {
    // No cleanup needed
  }
}
