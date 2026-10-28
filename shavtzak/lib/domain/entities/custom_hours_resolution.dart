import 'package:equatable/equatable.dart';

/// The hours an event save gives one assignment when the event's dates or
/// times change (`event.update`'s `customHoursResolutions`).
///
/// [customStartAt] and [customEndAt] are `yyyy-MM-ddTHH:mm` Israel wall-clock
/// strings, or both null to clear the assignment's hours so the member is held
/// for the whole event again.
class CustomHoursResolution extends Equatable {
  final String assignmentId;
  final String? customStartAt;
  final String? customEndAt;

  const CustomHoursResolution({
    required this.assignmentId,
    required this.customStartAt,
    required this.customEndAt,
  });

  /// Both hours keys are always present: the backend refuses an entry that
  /// leaves one out, and an explicit null is what clears the hours.
  Map<String, dynamic> toJson() => {
        'assignmentId': assignmentId,
        'customStartAt': customStartAt,
        'customEndAt': customEndAt,
      };

  @override
  List<Object?> get props => [assignmentId, customStartAt, customEndAt];
}
