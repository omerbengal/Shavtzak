import 'package:equatable/equatable.dart';
import '../../../../domain/entities/slot_annotation.dart';

/// A pending gap-annotation edit for one slot, staged until Save — the
/// annotation-world parallel of `StagedAssignmentChange`. Keyed in the bloc by
/// the grid slotKey `"<eventId>_<roleType>_<slotIndex>"`.
class StagedSlotAnnotation extends Equatable {
  final String eventId;
  final String roleType;
  final int slotIndex;

  /// Desired final annotation for this slot; null = the slot should have NO
  /// annotation (a delete on Save).
  final SlotAnnotation? desired;

  /// The reconciled annotation this slot showed when first staged (revert
  /// target — a revert to it drops the entry).
  final SlotAnnotation? baseline;

  /// For a re-key MOVE: the old `"<roleType>#<idx>"` annotation key to delete in
  /// the same Save write. Null for a plain edit/delete.
  final String? staleKey;

  const StagedSlotAnnotation({
    required this.eventId,
    required this.roleType,
    required this.slotIndex,
    required this.desired,
    required this.baseline,
    this.staleKey,
  });

  /// Reverts to baseline and carries no move → nothing to save, drop it.
  bool get isNoop => desired == baseline && staleKey == null;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'roleType': roleType,
        'slotIndex': slotIndex,
        'desired': desired?.toJson(),
        'baseline': baseline?.toJson(),
        'staleKey': staleKey,
      };

  factory StagedSlotAnnotation.fromJson(Map<String, dynamic> json) =>
      StagedSlotAnnotation(
        eventId: json['eventId'] as String,
        roleType: json['roleType'] as String,
        slotIndex: json['slotIndex'] as int,
        desired: json['desired'] == null
            ? null
            : SlotAnnotation.fromJson(
                Map<String, dynamic>.from(json['desired'] as Map)),
        baseline: json['baseline'] == null
            ? null
            : SlotAnnotation.fromJson(
                Map<String, dynamic>.from(json['baseline'] as Map)),
        staleKey: json['staleKey'] as String?,
      );

  @override
  List<Object?> get props =>
      [eventId, roleType, slotIndex, desired, baseline, staleKey];
}
