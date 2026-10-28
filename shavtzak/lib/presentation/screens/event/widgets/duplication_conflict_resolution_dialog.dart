import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../core/debug/logger.dart';
import '../../../../core/utils/custom_hours.dart';
import '../../../bloc/event/duplication_custom_hours.dart';
import '../../../bloc/event/event_state.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';

/// What the admin chose in [DuplicationConflictResolutionDialog]:
/// - [excluded]: the assignments to leave out of the copy;
/// - [hoursDropped]: the assignments whose custom hours are not copied, so the
///   copy holds the member for the new event's own hours.
typedef DuplicationDialogResult = ({
  Set<String> excluded,
  Set<String> hoursDropped,
});

/// Dialog for resolving conflicts during event duplication
/// Three sections: Availability Conflicts + Quota Overages, and (when custom
/// hours are being copied) the hours to confirm.
/// Checkbox semantics: Checked (Red X) = REMOVE, Unchecked = KEEP. The hours
/// section reads the other way round: Checked (blue tick) = COPY the hours.
class DuplicationConflictResolutionDialog extends StatefulWidget {
  final DuplicationRequiresConflictResolution conflictState;

  const DuplicationConflictResolutionDialog({
    super.key,
    required this.conflictState,
  });

  /// Show the dialog and return what the admin chose (see
  /// [DuplicationDialogResult]). Returns null if user cancels
  static Future<DuplicationDialogResult?> show(
    BuildContext context,
    DuplicationRequiresConflictResolution conflictState,
  ) {
    return showDialog<DuplicationDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DuplicationConflictResolutionDialog(
        conflictState: conflictState,
      ),
    );
  }

  @override
  State<DuplicationConflictResolutionDialog> createState() =>
      _DuplicationConflictResolutionDialogState();
}

class _DuplicationConflictResolutionDialogState
    extends State<DuplicationConflictResolutionDialog> {
  // Set of assignment IDs marked for REMOVAL (checked = remove)
  late Set<String> _markedForRemoval;
  // The part of _markedForRemoval the admin chose in the quota section. Ticking
  // or unticking hours never undoes these.
  final Set<String> _removedInQuota = {};
  // Set of expanded role cards in quota section
  late Set<String> _expandedRoles;

  // The copies that carry moved custom hours, grouped by who holds them (see
  // [_hoursKey]) in the order they first appear. One group is one row of the
  // hours section.
  late Map<String, List<AssignmentDuplicationInfo>> _hoursGroups;
  // The groups whose hours the admin unticked: not copied.
  final Set<String> _hoursDroppedKeys = {};

  @override
  void initState() {
    super.initState();
    // Start with availability-conflicted assignments marked for removal. The
    // ones that cannot be kept (canKeep false) are in there and stay there.
    _markedForRemoval = Set.from(widget.conflictState.suggestedExclusions);
    // Start with all quota roles collapsed
    _expandedRoles = <String>{};
    _hoursGroups = {};
    for (final info in widget.conflictState.assignmentInfos) {
      if (!info.hasMovedCustomHours) continue;
      _hoursGroups.putIfAbsent(_hoursKey(info), () => []).add(info);
    }
  }

  /// Who the hours of [info]'s copy belong to. A member holds one set of hours
  /// across their roles, so all their copies are one group; a member flagged
  /// `allowMultipleAssignments` stands for a different person in each slot,
  /// so each copy is a group of its own.
  String _hoursKey(AssignmentDuplicationInfo info) {
    if (isHoursExempt(info.assignment.teamMember)) {
      return 'assignment:${info.assignment.id}';
    }
    return 'member:${info.assignment.teamMemberId}';
  }

  /// The availability verdict for [info] as things stand: judged with the moved
  /// hours, or with the new event's own once the admin unticked them.
  ({bool flagged, bool canKeep, String? reason}) _verdict(
      AssignmentDuplicationInfo info) {
    final withEventHours = info.availabilityWithEventHours;
    if (withEventHours != null &&
        _hoursDroppedKeys.contains(_hoursKey(info))) {
      return (
        flagged: withEventHours.flagged,
        canKeep: withEventHours.canKeep,
        reason:
            withEventHours.flagged ? withEventHours.reasons.join('\n') : null,
      );
    }
    return (
      flagged: info.hasAvailabilityConflict,
      canKeep: info.canKeep,
      reason: info.availabilityReason,
    );
  }

  /// Whether the hours group [key] shows a row: not once every one of its
  /// members' copies is marked for removal, as their hours then do not matter.
  bool _isHoursGroupVisible(String key) => _hoursGroups[key]!
      .any((info) => !_markedForRemoval.contains(info.assignment.id));

  /// Set which hours groups are unticked.
  ///
  /// Ticking or unticking never removes a copy. A copy it newly flags enters
  /// the availability list kept, for the admin to decide. A copy it frees
  /// leaves that list, where its removal could no longer be seen, so a removal
  /// made there is let go; a removal made in the quota section stays.
  void _setHoursDropped(Set<String> keys) {
    final infos = [for (final group in _hoursGroups.values) ...group];
    final wasFlagged = {
      for (final info in infos) info.assignment.id: _verdict(info).flagged,
    };
    setState(() {
      _hoursDroppedKeys
        ..clear()
        ..addAll(keys);
      for (final info in infos) {
        final id = info.assignment.id;
        final now = _verdict(info);
        if (wasFlagged[id]! &&
            !now.flagged &&
            now.canKeep &&
            !_removedInQuota.contains(id)) {
          _markedForRemoval.remove(id);
        }
      }
    });
  }

  void _toggleHours(String key) {
    final dropped = Set<String>.of(_hoursDroppedKeys);
    if (!dropped.remove(key)) dropped.add(key);
    Logger.action('toggle:duplicationHours', {
      'copied': !dropped.contains(key),
    });
    _setHoursDropped(dropped);
  }

  /// Tick every hours row on show. A group whose member is marked for removal
  /// has no row, so it keeps whatever it was.
  void _copyAllHours() {
    Logger.action('tap:copyAllDuplicationHours');
    final hidden = _hoursGroups.keys.where((key) => !_isHoursGroupVisible(key));
    _setHoursDropped(_hoursDroppedKeys.intersection(hidden.toSet()));
  }

  /// What the dialog returns: the removals and the assignments whose hours are
  /// not copied (every copy of an unticked group).
  DuplicationDialogResult _result() => (
        excluded: Set<String>.of(_markedForRemoval),
        hoursDropped: {
          for (final key in _hoursDroppedKeys)
            for (final info in _hoursGroups[key] ?? const [])
              info.assignment.id,
        },
      );

  /// Get quota info for a role
  int _getQuotaForRole(String roleKey) {
    return widget.conflictState.roleQuotas[roleKey] ?? 0;
  }

  /// Get current KEPT count for a role (not marked for removal)
  int _getKeptCountForRole(String roleKey) {
    return widget.conflictState.assignmentInfos
        .where((info) =>
            info.assignment.roleType == roleKey &&
            !_markedForRemoval.contains(info.assignment.id))
        .length;
  }

  /// Check if a role has too many kept assignments (exceeds quota)
  bool _isRoleOverQuota(String roleKey) {
    return _getKeptCountForRole(roleKey) > _getQuotaForRole(roleKey);
  }

  /// Check if all constraints are satisfied
  /// With logic fix: Always returns true - quotas will be adjusted if needed
  bool _isSelectionValid() {
    return true;
  }

  /// Get assignments with availability conflicts grouped by role
  Map<String, List<AssignmentDuplicationInfo>> _getAvailabilityConflictsByRole() {
    final result = <String, List<AssignmentDuplicationInfo>>{};
    for (final info in widget.conflictState.assignmentInfos) {
      if (_verdict(info).flagged) {
        result.putIfAbsent(info.assignment.roleType, () => []).add(info);
      }
    }
    return result;
  }

  /// Get roles with quota overages and their assignments
  Map<String, List<AssignmentDuplicationInfo>> _getQuotaOveragesByRole() {
    final result = <String, List<AssignmentDuplicationInfo>>{};

    // Group all assignments by role
    final byRole = <String, List<AssignmentDuplicationInfo>>{};
    for (final info in widget.conflictState.assignmentInfos) {
      byRole.putIfAbsent(info.assignment.roleType, () => []).add(info);
    }

    // Only include roles where assignment count > quota
    for (final entry in byRole.entries) {
      final quota = _getQuotaForRole(entry.key);
      if (entry.value.length > quota) {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  /// Flip one row between kept and marked for removal. A row that cannot be
  /// kept (the backend would refuse it even with the bypass) never changes.
  /// [fromQuota] says the tap was in the quota section: that removal is the
  /// admin's quota choice and is not undone by the hours ticks.
  void _toggleRemoval(AssignmentDuplicationInfo info,
      {required bool fromQuota}) {
    if (!_verdict(info).canKeep) return;
    final id = info.assignment.id;
    setState(() {
      if (_markedForRemoval.remove(id)) {
        _removedInQuota.remove(id);
      } else {
        _markedForRemoval.add(id);
        if (fromQuota) _removedInQuota.add(id);
      }
    });
  }

  String _formatDate(DateTime date) {
    final days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    final dayName = days[date.weekday % 7];
    return 'יום $dayName, ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final availabilityConflicts = _getAvailabilityConflictsByRole();
    final quotaOverages = _getQuotaOveragesByRole();
    final hoursKeys = _hoursGroups.keys.where(_isHoursGroupVisible).toList();

    final totalAssignments = widget.conflictState.assignmentInfos.length;
    final removedCount = _markedForRemoval.length;
    final keptCount = totalAssignments - removedCount;

    final unavailableCount = widget.conflictState.assignmentInfos
        .where((a) => _verdict(a).flagged && _markedForRemoval.contains(a.assignment.id))
        .length;
    final quotaRemovedCount = removedCount - unavailableCount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocBuilder<RoleBloc, RoleState>(
        builder: (context, roleState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(),

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),

                      // Section 1: Availability Conflicts
                      _buildAvailabilitySection(availabilityConflicts),

                      const SizedBox(height: 24),

                      // Section 2: Quota Overages
                      _buildQuotaSection(quotaOverages),

                      // Section 3: custom hours to copy, when there are any
                      if (hoursKeys.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildHoursSection(hoursKeys),
                      ],

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Summary & Actions (sticky bottom)
              _buildSummaryAndActions(
                keptCount: keptCount,
                removedCount: removedCount,
                unavailableCount: unavailableCount,
                quotaRemovedCount: quotaRemovedCount,
              ),
            ],
          ),
        ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final totalConflicts = widget.conflictState.assignmentInfos
        .where((a) => _verdict(a).flagged || a.isInOverQuotaRole)
        .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'בחירת שיבוצים לאירוע המשוכפל',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  Logger.action('tap:close:duplicationConflictDialog');
                  Navigator.of(context).pop(null);
                },
                icon: const Icon(Icons.close),
                tooltip: 'ביטול',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'תאריך חדש: ${_formatDate(widget.conflictState.proposedEvent.startDate)}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.people, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                '${widget.conflictState.assignmentInfos.length} שיבוצים',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(width: 8),
              Text('|', style: TextStyle(color: Colors.grey.shade400)),
              const SizedBox(width: 8),
              Text(
                '$totalConflicts עם קונפליקטים',
                style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilitySection(Map<String, List<AssignmentDuplicationInfo>> conflicts) {
    final hasConflicts = conflicts.isNotEmpty;
    final conflictCount = conflicts.values.fold<int>(0, (sum, list) => sum + list.length);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: hasConflicts ? Colors.red.shade400 : Colors.green.shade400,
            width: 5,
          ),
        ),
        color: hasConflicts
            ? Colors.red.shade50.withValues(alpha: 0.5)
            : Colors.green.shade50.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  hasConflicts ? Icons.event_busy : Icons.check_circle,
                  color: hasConflicts ? Colors.red.shade600 : Colors.green.shade600,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'קונפליקטי זמינות',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: hasConflicts ? Colors.red.shade800 : Colors.green.shade800,
                            ),
                          ),
                          if (hasConflicts) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$conflictCount',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasConflicts
                            ? 'חברי צוות שלא זמינים בתאריך החדש'
                            : 'כל חברי הצוות זמינים בתאריך זה',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          if (hasConflicts)
            ...conflicts.entries.map((entry) => _buildAvailabilityConflictCards(
              roleKey: entry.key,
              assignments: entry.value,
            ))
          else
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(
                    'מעולה! כל חברי הצוות זמינים',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuotaSection(Map<String, List<AssignmentDuplicationInfo>> overages) {
    final hasOverages = overages.isNotEmpty;
    final overageCount = overages.length;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: hasOverages ? Colors.amber.shade600 : Colors.green.shade400,
            width: 5,
          ),
        ),
        color: hasOverages
            ? Colors.amber.shade50.withValues(alpha: 0.5)
            : Colors.green.shade50.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  hasOverages ? Icons.warning_amber : Icons.check_circle,
                  color: hasOverages ? Colors.amber.shade700 : Colors.green.shade600,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'חריגות מכסה',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: hasOverages ? Colors.amber.shade900 : Colors.green.shade800,
                            ),
                          ),
                          if (hasOverages) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$overageCount',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasOverages
                            ? 'תפקידים עם יותר שיבוצים מהמכסה החדשה'
                            : 'כל התפקידים במסגרת המכסות',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          if (hasOverages)
            ...overages.entries.map((entry) => _buildQuotaOverageCard(
              roleKey: entry.key,
              assignments: entry.value,
            ))
          else
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('✓', style: TextStyle(fontSize: 20, color: Colors.green)),
                  const SizedBox(width: 8),
                  Text(
                    'כל התפקידים במסגרת המכסות החדשות',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The custom hours the copy would carry, one row per hours group in
  /// [keys]: ticked rows are copied, moved to the new dates.
  Widget _buildHoursSection(List<String> keys) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.blue.shade400, width: 5),
        ),
        color: Colors.blue.shade50.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⏰ שעות מותאמות (${keys.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'סמן/י את מי שהשעות שלו/ה יועתקו לאירוע החדש. '
                        'מי שלא סומן יקבל/תקבל את שעות האירוע.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _copyAllHours,
                  child: const Text('סמן הכל'),
                ),
              ],
            ),
          ),
          ...keys.map(_buildHoursRow),
        ],
      ),
    );
  }

  /// One member's hours: the old ones struck through, the moved ones under
  /// them (or the note that they are not copied), and the constraints the
  /// moved hours run into.
  Widget _buildHoursRow(String key) {
    final group = _hoursGroups[key]!;
    final first = group.first;
    final member = first.assignment.teamMember;
    final memberName = member?.name ?? 'לא ידוע';
    final copied = !_hoursDroppedKeys.contains(key);
    final oldWindow =
        firstCustomWindow(group.map((info) => info.assignment));
    final movedWindow = first.movedCustomWindow!;
    final warnings = copied && member != null
        ? customHoursWarningLines(member, movedWindow)
        : const <String>[];

    return InkWell(
      onTap: () => _toggleHours(key),
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: copied,
              onChanged: (_) => _toggleHours(key),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlocBuilder<RoleBloc, RoleState>(
                      builder: (context, roleState) {
                        final roleKey = first.assignment.roleType;
                        final roleName = roleState is RolesLoaded
                            ? roleState.getRoleHebrewName(roleKey)
                            : roleKey;
                        return Text(
                          '$memberName · $roleName',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        );
                      },
                    ),
                    if (oldWindow != null)
                      Text(
                        formatCustomHours(oldWindow),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    if (copied)
                      Text(
                        '← ${formatCustomHours(movedWindow)}',
                        style: const TextStyle(fontSize: 13),
                      )
                    else
                      Text(
                        'לא יועתק — יקבל/תקבל את שעות האירוע',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    for (final line in warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityConflictCards({
    required String roleKey,
    required List<AssignmentDuplicationInfo> assignments,
  }) {
    // In availability section, each assignment is its own card with team member name as title
    return Column(
      children: assignments.map((info) {
        final isMarkedForRemoval = _markedForRemoval.contains(info.assignment.id);
        final memberName = info.assignment.teamMember?.name ?? 'לא ידוע';
        final verdict = _verdict(info);

        return Container(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          decoration: BoxDecoration(
            color: isMarkedForRemoval ? Colors.red.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.red.shade300,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: !verdict.canKeep
                ? null
                : () {
                    Logger.action('toggle:availabilityConflictAssignment', {
                      'assignmentId': info.assignment.id,
                      'markedForRemoval': !isMarkedForRemoval,
                    });
                    _toggleRemoval(info, fromQuota: false);
                  },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Red X checkbox (disabled when the member cannot be kept)
                      _buildRemovalCheckbox(isMarkedForRemoval,
                          enabled: verdict.canKeep),
                      const SizedBox(width: 12),

                      // Member name as title
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                memberName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  decoration: isMarkedForRemoval ? TextDecoration.lineThrough : null,
                                  color: isMarkedForRemoval ? Colors.grey.shade500 : Colors.black87,
                                ),
                              ),
                            ),
                            if (info.assignment.teamMember?.isPermanent == true) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.verified_user,
                                size: 14,
                                color: Colors.blue.shade700,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Status badge
                      if (isMarkedForRemoval)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'יוסר',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Job title
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: BlocBuilder<RoleBloc, RoleState>(
                      builder: (context, roleState) {
                        final roleHebrewName = roleState is RolesLoaded
                            ? roleState.getRoleHebrewName(roleKey)
                            : roleKey;
                        return Text(
                          roleHebrewName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),

                  // Availability conflict reason: one line per reason
                  if (verdict.flagged && verdict.reason != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.event_busy, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            verdict.reason!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuotaOverageCard({
    required String roleKey,
    required List<AssignmentDuplicationInfo> assignments,
  }) {
    final newQuota = _getQuotaForRole(roleKey);
    final totalAssignments = assignments.length;
    final assignmentsToRemove = totalAssignments - newQuota;
    final currentlyMarkedForRemoval = assignments
        .where((info) => _markedForRemoval.contains(info.assignment.id))
        .length;
    final remainingToRemove = assignmentsToRemove - currentlyMarkedForRemoval;
    final isExpanded = _expandedRoles.contains(roleKey);

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.amber.shade600,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Expandable role header
          InkWell(
            onTap: () {
              Logger.action('toggle:quotaRoleExpanded', {
                'roleKey': roleKey,
                'expanded': !isExpanded,
              });
              setState(() {
                if (isExpanded) {
                  _expandedRoles.remove(roleKey);
                } else {
                  _expandedRoles.add(roleKey);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Role display name from RoleBloc
                        BlocBuilder<RoleBloc, RoleState>(
                          builder: (context, roleState) {
                            String roleHebrewName = roleKey;
                            if (roleState is RolesLoaded) {
                              final role = roleState.getRoleByKey(roleKey);
                              if (role != null) {
                                roleHebrewName = role.hebrewName;
                              }
                            } else {
                              // Fallback to RoleType enum
                              try {
                                final roleType = RoleType.values.firstWhere((rt) => rt.key == roleKey);
                                roleHebrewName = roleType.hebrewName;
                              } catch (e) {
                                // Keep roleKey as fallback
                              }
                            }
                            return Text(
                              roleHebrewName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 2),
                        Text(
                              '$totalAssignments שיבוצים • $newQuota מכסה',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content with assignments
          if (isExpanded)
            ...assignments.map((info) => _buildAssignmentRow(info, false)),
        ],
      ),
    );
  }

  Widget _buildAssignmentRow(AssignmentDuplicationInfo info, bool isAvailabilitySection) {
    final isMarkedForRemoval = _markedForRemoval.contains(info.assignment.id);
    final memberName = info.assignment.teamMember?.name ?? 'לא ידוע';
    final verdict = _verdict(info);

    return InkWell(
      onTap: !verdict.canKeep
          ? null
          : () {
              Logger.action('toggle:quotaAssignment', {
                'assignmentId': info.assignment.id,
                'markedForRemoval': !isMarkedForRemoval,
              });
              _toggleRemoval(info, fromQuota: !isAvailabilitySection);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMarkedForRemoval ? Colors.red.shade50 : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          children: [
            // Red X checkbox (disabled when the member cannot be kept)
            _buildRemovalCheckbox(isMarkedForRemoval, enabled: verdict.canKeep),
            const SizedBox(width: 12),

            // Member info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          memberName,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            decoration: isMarkedForRemoval ? TextDecoration.lineThrough : null,
                            color: isMarkedForRemoval ? Colors.grey.shade500 : null,
                          ),
                        ),
                      ),
                      if (info.assignment.teamMember?.isPermanent == true) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.verified_user,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                      ],
                    ],
                  ),
                  // Availability conflicts show in the availability section; a
                  // locked row (cannot be kept) shows its reason wherever it is
                  if ((isAvailabilitySection || !verdict.canKeep) && verdict.flagged && verdict.reason != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.event_busy, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            verdict.reason!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Status badge
            if (isMarkedForRemoval)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'יוסר',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemovalCheckbox(bool isChecked, {bool enabled = true}) {
    // A disabled box is always checked (its row is locked to removal), drawn
    // greyed so it does not look tappable.
    final fill = !enabled ? Colors.grey.shade400 : Colors.red.shade500;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isChecked ? fill : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isChecked ? fill : Colors.grey.shade400,
          width: 2,
        ),
      ),
      child: isChecked
          ? const Icon(
              Icons.close,
              size: 18,
              color: Colors.white,
            )
          : null,
    );
  }

  Widget _buildSummaryAndActions({
    required int keptCount,
    required int removedCount,
    required int unavailableCount,
    required int quotaRemovedCount,
  }) {
    final isValid = _isSelectionValid();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSummaryChip(
                  icon: Icons.check,
                  label: '$keptCount ישוכפלו',
                  color: Colors.green,
                ),
                const SizedBox(width: 16),
                _buildSummaryChip(
                  icon: Icons.close,
                  label: '$removedCount יוסרו',
                  color: Colors.red,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Logger.action('tap:cancel:duplicationConflictDialog');
                    Navigator.of(context).pop(null);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('ביטול'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isValid ? () {
                    Logger.action('tap:confirmDuplication', {
                      'keptCount': keptCount,
                      'removedCount': removedCount,
                    });
                    Navigator.of(context).pop(_result());
                  } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: const Text(
                    'צור אירוע משוכפל',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
