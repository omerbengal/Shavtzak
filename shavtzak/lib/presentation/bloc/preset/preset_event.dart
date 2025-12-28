part of 'preset_bloc.dart';

abstract class PresetEvent extends Equatable {
  const PresetEvent();

  @override
  List<Object?> get props => [];
}

/// Load all presets
class LoadPresets extends PresetEvent {}

/// Create a new preset
class CreatePreset extends PresetEvent {
  final Preset preset;

  const CreatePreset(this.preset);

  @override
  List<Object?> get props => [preset];
}

/// Update an existing preset
class UpdatePreset extends PresetEvent {
  final Preset preset;

  const UpdatePreset(this.preset);

  @override
  List<Object?> get props => [preset];
}

/// Delete a preset
class DeletePreset extends PresetEvent {
  final String presetId;

  const DeletePreset(this.presetId);

  @override
  List<Object?> get props => [presetId];
}

/// Load a preset into an event (creates checklist items from template)
class LoadPresetIntoEvent extends PresetEvent {
  final String presetId;
  final String eventId;

  const LoadPresetIntoEvent({
    required this.presetId,
    required this.eventId,
  });

  @override
  List<Object?> get props => [presetId, eventId];
}
