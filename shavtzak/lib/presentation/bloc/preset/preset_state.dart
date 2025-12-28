part of 'preset_bloc.dart';

abstract class PresetState extends Equatable {
  const PresetState();

  @override
  List<Object?> get props => [];
}

class PresetInitial extends PresetState {}

class PresetLoading extends PresetState {}

class PresetsLoaded extends PresetState {
  final List<Preset> presets;

  const PresetsLoaded(this.presets);

  @override
  List<Object?> get props => [presets];
}

class PresetError extends PresetState {
  final String message;

  const PresetError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Emitted after successfully loading a preset into an event
class PresetLoadedIntoEvent extends PresetState {
  final String presetName;
  final String eventName;
  final int itemCount;

  const PresetLoadedIntoEvent({
    required this.presetName,
    required this.eventName,
    required this.itemCount,
  });

  @override
  List<Object?> get props => [presetName, eventName, itemCount];
}
