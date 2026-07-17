import 'package:equatable/equatable.dart';

/// One staged (not-yet-saved) edit to a single assignment slot, keyed by
/// [slotKey]. Holds the DESIRED state (what the admin wants) and the BASELINE
/// snapshot (the DB state when the slot was first touched). Baseline is used
/// ONLY for conflict detection at Save; the actual write converges the current
/// DB to [desired…]. Persisted to localStorage for crash recovery.
class StagedAssignmentChange extends Equatable {
  final String slotKey;
  final String eventId;
  final String roleType;
  final int slotIndex;

  // Desired state (null desiredMemberId => staged clear).
  final String? desiredMemberId;
  final String desiredNotes;
  final String? desiredSemanticLabelId;
  final String? desiredAltPhone;

  // Baseline snapshot (DB state at first touch). Null member => slot was empty.
  final String? baselineAssignmentId;
  final String? baselineMemberId;
  final String baselineNotes;
  final String? baselineSemanticLabelId;
  final String? baselineAltPhone;

  /// Stable id to use if this staged change creates a new assignment doc.
  final String desiredAssignmentId;
  final int stagedAtMillis;

  const StagedAssignmentChange({
    required this.slotKey,
    required this.eventId,
    required this.roleType,
    required this.slotIndex,
    required this.desiredMemberId,
    required this.desiredNotes,
    required this.desiredSemanticLabelId,
    required this.desiredAltPhone,
    required this.baselineAssignmentId,
    required this.baselineMemberId,
    required this.baselineNotes,
    required this.baselineSemanticLabelId,
    required this.baselineAltPhone,
    required this.desiredAssignmentId,
    required this.stagedAtMillis,
  });

  static String slotKeyFor(String eventId, String roleType, int slotIndex) =>
      '${eventId}_${roleType}_$slotIndex';

  bool get isClear => desiredMemberId == null;

  /// True when the desired state equals the baseline (a full revert) — the
  /// change is then dropped so the slot is no longer dirty.
  bool get matchesBaseline =>
      desiredMemberId == baselineMemberId &&
      desiredNotes == baselineNotes &&
      desiredSemanticLabelId == baselineSemanticLabelId &&
      desiredAltPhone == baselineAltPhone;

  StagedAssignmentChange copyWith({
    String? Function()? desiredMemberId,
    String? desiredNotes,
    String? Function()? desiredSemanticLabelId,
    String? Function()? desiredAltPhone,
    String? Function()? baselineAssignmentId,
    String? Function()? baselineMemberId,
    int? stagedAtMillis,
  }) {
    return StagedAssignmentChange(
      slotKey: slotKey,
      eventId: eventId,
      roleType: roleType,
      slotIndex: slotIndex,
      desiredMemberId:
          desiredMemberId != null ? desiredMemberId() : this.desiredMemberId,
      desiredNotes: desiredNotes ?? this.desiredNotes,
      desiredSemanticLabelId: desiredSemanticLabelId != null
          ? desiredSemanticLabelId()
          : this.desiredSemanticLabelId,
      desiredAltPhone:
          desiredAltPhone != null ? desiredAltPhone() : this.desiredAltPhone,
      baselineAssignmentId: baselineAssignmentId != null
          ? baselineAssignmentId()
          : this.baselineAssignmentId,
      baselineMemberId:
          baselineMemberId != null ? baselineMemberId() : this.baselineMemberId,
      baselineNotes: baselineNotes,
      baselineSemanticLabelId: baselineSemanticLabelId,
      baselineAltPhone: baselineAltPhone,
      desiredAssignmentId: desiredAssignmentId,
      stagedAtMillis: stagedAtMillis ?? this.stagedAtMillis,
    );
  }

  Map<String, dynamic> toJson() => {
        'slotKey': slotKey,
        'eventId': eventId,
        'roleType': roleType,
        'slotIndex': slotIndex,
        'desiredMemberId': desiredMemberId,
        'desiredNotes': desiredNotes,
        'desiredSemanticLabelId': desiredSemanticLabelId,
        'desiredAltPhone': desiredAltPhone,
        'baselineAssignmentId': baselineAssignmentId,
        'baselineMemberId': baselineMemberId,
        'baselineNotes': baselineNotes,
        'baselineSemanticLabelId': baselineSemanticLabelId,
        'baselineAltPhone': baselineAltPhone,
        'desiredAssignmentId': desiredAssignmentId,
        'stagedAtMillis': stagedAtMillis,
      };

  factory StagedAssignmentChange.fromJson(Map<String, dynamic> json) =>
      StagedAssignmentChange(
        slotKey: json['slotKey'] as String,
        eventId: json['eventId'] as String,
        roleType: json['roleType'] as String,
        slotIndex: json['slotIndex'] as int,
        desiredMemberId: json['desiredMemberId'] as String?,
        desiredNotes: (json['desiredNotes'] as String?) ?? '',
        desiredSemanticLabelId: json['desiredSemanticLabelId'] as String?,
        desiredAltPhone: json['desiredAltPhone'] as String?,
        baselineAssignmentId: json['baselineAssignmentId'] as String?,
        baselineMemberId: json['baselineMemberId'] as String?,
        baselineNotes: (json['baselineNotes'] as String?) ?? '',
        baselineSemanticLabelId: json['baselineSemanticLabelId'] as String?,
        baselineAltPhone: json['baselineAltPhone'] as String?,
        desiredAssignmentId: json['desiredAssignmentId'] as String,
        stagedAtMillis: json['stagedAtMillis'] as int,
      );

  @override
  List<Object?> get props => [
        slotKey,
        eventId,
        roleType,
        slotIndex,
        desiredMemberId,
        desiredNotes,
        desiredSemanticLabelId,
        desiredAltPhone,
        baselineAssignmentId,
        baselineMemberId,
        baselineNotes,
        baselineSemanticLabelId,
        baselineAltPhone,
        desiredAssignmentId,
        stagedAtMillis,
      ];
}
