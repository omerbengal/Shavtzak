import 'package:equatable/equatable.dart';

/// A note + label attached to a single assignment SLOT (a "job"), independent
/// of whether a member is assigned. Stored on `Event.slotAnnotations`, keyed by
/// `slotAnnotationKey(roleKey, slotIndex)`. The label reuses `AssignmentLabel`
/// by id.
class SlotAnnotation extends Equatable {
  final String note;
  final String? labelId;

  const SlotAnnotation({this.note = '', this.labelId});

  /// True when there is nothing worth storing (blank note and no label).
  bool get isEmpty => note.trim().isEmpty && labelId == null;

  SlotAnnotation copyWith({String? note, String? Function()? labelId}) {
    return SlotAnnotation(
      note: note ?? this.note,
      labelId: labelId != null ? labelId() : this.labelId,
    );
  }

  Map<String, dynamic> toJson() => {'note': note, 'labelId': labelId};

  factory SlotAnnotation.fromJson(Map<String, dynamic> json) => SlotAnnotation(
        note: (json['note'] as String?) ?? '',
        labelId: json['labelId'] as String?,
      );

  @override
  List<Object?> get props => [note, labelId];
}
