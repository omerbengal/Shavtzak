import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/role_types.dart';
import '../../../bloc/event/event_state.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';

/// Dialog for resolving conflicts during event duplication
/// Two sections: Availability Conflicts + Quota Overages
/// Checkbox semantics: Checked (Red X) = REMOVE, Unchecked = KEEP
class DuplicationConflictResolutionDialog extends StatefulWidget {
  final DuplicationRequiresConflictResolution conflictState;

  const DuplicationConflictResolutionDialog({
    super.key,
    required this.conflictState,
  });

  /// Show the dialog and return the set of assignment IDs to EXCLUDE
  /// Returns null if user cancels
  static Future<Set<String>?> show(
    BuildContext context,
    DuplicationRequiresConflictResolution conflictState,
  ) {
    return showDialog<Set<String>>(
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
  // Set of expanded role cards in quota section
  late Set<String> _expandedRoles;

  @override
  void initState() {
    super.initState();
    // Start with availability-conflicted assignments marked for removal
    _markedForRemoval = Set.from(widget.conflictState.suggestedExclusions);
    // Start with all quota roles collapsed
    _expandedRoles = <String>{};
  }

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
      if (info.hasAvailabilityConflict) {
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

  String _formatDate(DateTime date) {
    final days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    final dayName = days[date.weekday % 7];
    return 'יום $dayName, ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final availabilityConflicts = _getAvailabilityConflictsByRole();
    final quotaOverages = _getQuotaOveragesByRole();

    final totalAssignments = widget.conflictState.assignmentInfos.length;
    final removedCount = _markedForRemoval.length;
    final keptCount = totalAssignments - removedCount;

    final unavailableCount = widget.conflictState.assignmentInfos
        .where((a) => a.hasAvailabilityConflict && _markedForRemoval.contains(a.assignment.id))
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
        .where((a) => a.hasAnyConflict)
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
                onPressed: () => Navigator.of(context).pop(null),
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

  Widget _buildAvailabilityConflictCards({
    required String roleKey,
    required List<AssignmentDuplicationInfo> assignments,
  }) {
    // In availability section, each assignment is its own card with team member name as title
    return Column(
      children: assignments.map((info) {
        final isMarkedForRemoval = _markedForRemoval.contains(info.assignment.id);
        final memberName = info.assignment.teamMember?.name ?? 'לא ידוע';

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
            onTap: () {
              setState(() {
                if (isMarkedForRemoval) {
                  _markedForRemoval.remove(info.assignment.id);
                } else {
                  _markedForRemoval.add(info.assignment.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Red X checkbox
                      _buildRemovalCheckbox(isMarkedForRemoval),
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

                  // Availability conflict reason
                  if (info.hasAvailabilityConflict && info.availabilityReason != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.event_busy, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            info.availabilityReason!,
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

    return InkWell(
      onTap: () {
        setState(() {
          if (isMarkedForRemoval) {
            _markedForRemoval.remove(info.assignment.id);
          } else {
            _markedForRemoval.add(info.assignment.id);
          }
        });
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
            // Red X checkbox
            _buildRemovalCheckbox(isMarkedForRemoval),
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
                  // Only show availability conflicts in the availability section
                  if (isAvailabilitySection && info.hasAvailabilityConflict && info.availabilityReason != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.event_busy, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            info.availabilityReason!,
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

  Widget _buildRemovalCheckbox(bool isChecked) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isChecked ? Colors.red.shade500 : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isChecked ? Colors.red.shade500 : Colors.grey.shade400,
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
                  onPressed: () => Navigator.of(context).pop(null),
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
                  onPressed: isValid ? () => Navigator.of(context).pop(_markedForRemoval) : null,
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
