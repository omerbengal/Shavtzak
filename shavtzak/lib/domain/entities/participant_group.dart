import 'package:equatable/equatable.dart';

/// One audience group ("נגלה") of an event: an optional label plus a headcount.
///
/// A null or blank [label] means the UI falls back to "נגלה N", where N is the
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

  Map<String, dynamic> toMap() => {'label': normalizedLabel, 'count': count};

  /// Parse one stored group. Returns null for anything malformed, so a bad
  /// entry is dropped rather than breaking the whole event.
  static ParticipantGroup? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final count = (raw['count'] as num?)?.toInt();
    if (count == null || count < 0) return null;
    final label = raw['label'];
    return ParticipantGroup(
      label: label is String ? label : null,
      count: count,
    );
  }

  @override
  List<Object?> get props => [normalizedLabel, count];
}
