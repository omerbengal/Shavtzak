import 'package:equatable/equatable.dart';

/// One audience group ("סבב") of an event: an optional label plus a headcount.
///
/// A null or blank [label] means the UI falls back to "סבב N", where N is the
/// group's 1-based position in Event.participantGroups.
class ParticipantGroup extends Equatable {
  final String? label;
  final int count;

  const ParticipantGroup({this.label, required this.count});

  /// The label with surrounding whitespace removed, or null when absent/blank.
  /// Blank and absent are the same thing everywhere, so this is what both
  /// serialization and equality use.
  String? get normalizedLabel {
    final trimmed = label?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  List<Object?> get props => [normalizedLabel, count];
}
