import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/assignment_label.dart';
import '../../../../data/repositories/assignment_repository.dart';
import '../../../../domain/entities/role.dart';
import '../../../../data/repositories/assignment_label_repository.dart';
import '../../../bloc/assignment/assignment_bloc.dart';
import '../../../bloc/assignment/assignment_event.dart';
import '../../../bloc/assignment/assignment_state.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';
import '../../../widgets/assignment_label_chip.dart';

/// Dialog showing all assignments for an event.
/// Default mode groups by role. Optional label mode groups by labels first,
/// then by roles inside each label section.
class EventAssignmentsDialog extends StatefulWidget {
  final String eventId;
  final String eventName;
  final List<Assignment>? assignments; // Optional: if provided, skip loading

  const EventAssignmentsDialog({
    super.key,
    required this.eventId,
    required this.eventName,
    this.assignments,
  });

  /// Constructor that accepts pre-loaded assignments (doesn't trigger BLoC event)
  const EventAssignmentsDialog.withAssignments({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.assignments,
  }) : assert(assignments != null,
            'assignments cannot be null in withAssignments constructor');

  @override
  State<EventAssignmentsDialog> createState() => _EventAssignmentsDialogState();
}

class _EventAssignmentsDialogState extends State<EventAssignmentsDialog> {
  List<Assignment>? _cachedAssignments;
  bool _useCache = false;
  bool _sortByLabel = false;

  @override
  void initState() {
    super.initState();
    // Only load assignments if not provided
    if (widget.assignments != null) {
      _cachedAssignments = widget.assignments!;
      _useCache = true;
    } else {
      // Load assignments for this event
      context
          .read<AssignmentBloc>()
          .add(LoadAssignmentsByEvent(widget.eventId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'שיבוצים ל${widget.eventName}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                value: _sortByLabel,
                onChanged: (value) {
                  setState(() {
                    _sortByLabel = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'קיבוץ לפי לייבלים',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'יציג קודם קבוצות לייבלים, ובתוכן חלוקה לתפקידים',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              // Content
              Expanded(
                child: StreamBuilder<List<AssignmentLabel>>(
                  stream: context
                      .read<AssignmentLabelRepository>()
                      .watchAssignmentLabels(),
                  builder: (context, labelSnapshot) {
                    final labels =
                        labelSnapshot.data ?? const <AssignmentLabel>[];

                    return _useCache
                        ? StreamBuilder<List<Assignment>>(
                            stream: context
                                .read<AssignmentRepository>()
                                .watchAssignmentsByEvent(widget.eventId),
                            initialData: _cachedAssignments,
                            builder: (context, assignmentSnapshot) {
                              final assignments = _applyAssignmentLabels(
                                assignmentSnapshot.data ??
                                    (_cachedAssignments ??
                                        const <Assignment>[]),
                                labels,
                              );
                              if (assignments.isEmpty) {
                                return Center(
                                  child: Text(
                                    'אין שיבוצים לאירוע זה',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                );
                              }
                              return _buildAssignmentsList(
                                context,
                                assignments,
                              );
                            },
                          )
                        : BlocBuilder<AssignmentBloc, AssignmentState>(
                            buildWhen: (previous, current) =>
                                current is AssignmentsLoaded ||
                                current is AssignmentLoading ||
                                current is AssignmentError,
                            builder: (context, state) {
                              if (state is AssignmentLoading) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              } else if (state is AssignmentsLoaded) {
                                final assignments = _applyAssignmentLabels(
                                  state.assignments,
                                  labels,
                                );
                                if (assignments.isEmpty) {
                                  return Center(
                                    child: Text(
                                      'אין שיבוצים לאירוע זה',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey.shade600),
                                    ),
                                  );
                                }
                                return _buildAssignmentsList(
                                  context,
                                  assignments,
                                );
                              } else if (state is AssignmentError) {
                                return Center(
                                  child: Text(
                                    state.message,
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.red),
                                  ),
                                );
                              }
                              return const Center(
                                  child: CircularProgressIndicator());
                            },
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Assignment> _applyAssignmentLabels(
    List<Assignment> assignments,
    List<AssignmentLabel> labels,
  ) {
    if (assignments.isEmpty || labels.isEmpty) {
      return assignments;
    }

    final labelsById = {
      for (final label in labels) label.id: label,
    };

    return assignments.map((assignment) {
      return assignment.copyWith(
        semanticLabel: () => assignment.semanticLabelId == null
            ? null
            : labelsById[assignment.semanticLabelId!],
      );
    }).toList();
  }

  Widget _buildAssignmentsList(
      BuildContext context, List<Assignment> assignments) {
    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
        if (roleState is! RolesLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final activeRoles = roleState.activeRoles;
        final sections = _sortByLabel
            ? _buildLabelSections(activeRoles, assignments)
            : _buildRoleSections(activeRoles, assignments);

        if (sections.isEmpty) {
          return Center(
            child: Text(
              'אין שיבוצים לאירוע זה',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          );
        }

        return ListView(
          children: sections,
        );
      },
    );
  }

  List<Widget> _buildRoleSections(
    List<Role> activeRoles,
    List<Assignment> assignments,
  ) {
    final assignmentsByRole = <String, List<Assignment>>{};
    for (final assignment in assignments) {
      assignmentsByRole.putIfAbsent(assignment.roleType, () => []);
      assignmentsByRole[assignment.roleType]!.add(assignment);
    }

    final sections = <Widget>[];
    for (final role in activeRoles) {
      final roleAssignments = assignmentsByRole[role.key];
      if (roleAssignments == null || roleAssignments.isEmpty) {
        continue;
      }

      sections.add(
        _buildRoleSection(
          role,
          _sortAssignmentsWithinRoleGroup(roleAssignments),
        ),
      );
    }

    return sections;
  }

  List<Widget> _buildLabelSections(
    List<Role> activeRoles,
    List<Assignment> assignments,
  ) {
    final labeledAssignments = <AssignmentLabel, List<Assignment>>{};
    final unlabeledAssignments = <Assignment>[];

    for (final assignment in assignments) {
      final label = assignment.semanticLabel;
      if (label == null) {
        unlabeledAssignments.add(assignment);
        continue;
      }

      labeledAssignments.putIfAbsent(label, () => []);
      labeledAssignments[label]!.add(assignment);
    }

    final orderedLabels = labeledAssignments.keys.toList()
      ..sort((a, b) {
        final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
        if (bySortOrder != 0) return bySortOrder;
        return a.hebrewName.compareTo(b.hebrewName);
      });

    final sections = <Widget>[
      for (final label in orderedLabels)
        _buildLabelSection(
          label: label,
          assignments: labeledAssignments[label]!,
          activeRoles: activeRoles,
        ),
    ];

    if (unlabeledAssignments.isNotEmpty) {
      sections.add(
        _buildLabelSection(
          label: null,
          assignments: unlabeledAssignments,
          activeRoles: activeRoles,
        ),
      );
    }

    return sections;
  }

  Widget _buildLabelSection({
    required AssignmentLabel? label,
    required List<Assignment> assignments,
    required List<Role> activeRoles,
  }) {
    final roleSections = <Widget>[];

    for (final role in activeRoles) {
      final roleAssignments = assignments
          .where((assignment) => assignment.roleType == role.key)
          .toList();
      if (roleAssignments.isEmpty) {
        continue;
      }

      roleSections.add(
        _buildNestedRoleSection(
          role,
          _sortAssignmentsAlphabetically(roleAssignments),
          showTopDivider: roleSections.isNotEmpty,
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (label != null)
                  AssignmentLabelChip(
                    label: label,
                    fontSize: 11,
                    maxLines: 3,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'ללא לייבל',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${assignments.length}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...roleSections,
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSection(Role role, List<Assignment> assignments) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildRoleContent(
          role,
          assignments,
          titleFontSize: 18,
          titleIconSize: 24,
          countFontSize: 14,
          countPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
    );
  }

  Widget _buildNestedRoleSection(
    Role role,
    List<Assignment> assignments, {
    required bool showTopDivider,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTopDivider) const Divider(height: 20),
        _buildRoleContent(
          role,
          assignments,
          titleFontSize: 16,
          titleIconSize: 20,
          countFontSize: 12,
          countPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        ),
      ],
    );
  }

  Widget _buildRoleContent(
    Role role,
    List<Assignment> assignments, {
    required double titleFontSize,
    required double titleIconSize,
    required double countFontSize,
    required EdgeInsetsGeometry countPadding,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.badge_outlined,
              size: titleIconSize,
              color: Colors.blue.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                role.hebrewName,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: countPadding,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${assignments.length}',
                style: TextStyle(
                  fontSize: countFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...assignments.map(
          (assignment) => _buildAssignmentRow(
            assignment,
            showAssignmentLabel: !_sortByLabel,
          ),
        ),
      ],
    );
  }

  List<Assignment> _sortAssignmentsWithinRoleGroup(
    List<Assignment> assignments,
  ) {
    final sortedAssignments = List<Assignment>.from(assignments);
    sortedAssignments.sort((a, b) {
      final aLabel = a.semanticLabel;
      final bLabel = b.semanticLabel;

      if (aLabel == null && bLabel != null) return 1;
      if (aLabel != null && bLabel == null) return -1;
      if (aLabel != null && bLabel != null) {
        final bySortOrder = aLabel.sortOrder.compareTo(bLabel.sortOrder);
        if (bySortOrder != 0) return bySortOrder;

        final byLabelName = aLabel.hebrewName.compareTo(bLabel.hebrewName);
        if (byLabelName != 0) return byLabelName;
      }

      final aName = a.teamMember?.name ?? '';
      final bName = b.teamMember?.name ?? '';
      final byName = aName.compareTo(bName);
      if (byName != 0) return byName;

      final bySlotIndex = a.slotIndex.compareTo(b.slotIndex);
      if (bySlotIndex != 0) return bySlotIndex;

      return a.id.compareTo(b.id);
    });
    return sortedAssignments;
  }

  List<Assignment> _sortAssignmentsAlphabetically(List<Assignment> assignments) {
    final sortedAssignments = List<Assignment>.from(assignments);
    sortedAssignments.sort((a, b) {
      final aName = a.teamMember?.name ?? '';
      final bName = b.teamMember?.name ?? '';
      final byName = aName.compareTo(bName);
      if (byName != 0) return byName;

      final byRole = a.roleType.compareTo(b.roleType);
      if (byRole != 0) return byRole;

      final bySlotIndex = a.slotIndex.compareTo(b.slotIndex);
      if (bySlotIndex != 0) return bySlotIndex;

      return a.id.compareTo(b.id);
    });
    return sortedAssignments;
  }

  Widget _buildAssignmentRow(
    Assignment assignment, {
    required bool showAssignmentLabel,
  }) {
    final member = assignment.teamMember;
    if (member == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 28, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 18,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  member.name,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if ((member.phoneNumber != null &&
                      member.phoneNumber!.isNotEmpty) ||
                  (assignment.alternativePhoneNumber != null &&
                      assignment.alternativePhoneNumber!.isNotEmpty)) ...[
                InkWell(
                  onTap: () => _makePhoneCall(
                    (member.phoneNumber != null &&
                            member.phoneNumber!.isNotEmpty)
                        ? member.phoneNumber!
                        : assignment.alternativePhoneNumber!,
                  ),
                  child: Icon(
                    Icons.phone,
                    size: 22,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (assignment.status != AssignmentStatus.confirmed) ...[
                _buildStatusIndicator(assignment.status),
                const SizedBox(width: 8),
              ],
            ],
          ),
          if (showAssignmentLabel && assignment.semanticLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 26, top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: AssignmentLabelChip(
                  label: assignment.semanticLabel!,
                  fontSize: 10,
                  maxLines: 3,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          if (assignment.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 26, top: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.note_alt_outlined,
                      size: 14,
                      color: Colors.purple.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'הערות לשיבוץ: ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.purple.shade800,
                              ),
                            ),
                            TextSpan(
                              text: assignment.notes,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.purple.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Widget _buildStatusIndicator(AssignmentStatus status) {
    switch (status) {
      case AssignmentStatus.pending:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'ממתין',
            style: TextStyle(
              fontSize: 10,
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case AssignmentStatus.declined:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'נדחה',
            style: TextStyle(
              fontSize: 10,
              color: Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case AssignmentStatus.confirmed:
        return const SizedBox.shrink();
    }
  }
}
