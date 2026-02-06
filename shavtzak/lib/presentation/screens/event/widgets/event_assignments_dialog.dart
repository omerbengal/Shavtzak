import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/role.dart';
import '../../../bloc/assignment/assignment_bloc.dart';
import '../../../bloc/assignment/assignment_event.dart';
import '../../../bloc/assignment/assignment_state.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';

/// Dialog showing all assignments for an event, grouped by role
/// Roles are ordered by sortOrder (from role management screen)
/// Team members are sorted alphabetically within each role
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
  }) : assert(assignments != null, 'assignments cannot be null in withAssignments constructor');

  @override
  State<EventAssignmentsDialog> createState() => _EventAssignmentsDialogState();
}

class _EventAssignmentsDialogState extends State<EventAssignmentsDialog> {
  List<Assignment>? _cachedAssignments;
  bool _useCache = false;

  @override
  void initState() {
    super.initState();
    // Only load assignments if not provided
    if (widget.assignments != null) {
      _cachedAssignments = widget.assignments!;
      _useCache = true;
    } else {
      // Load assignments for this event
      context.read<AssignmentBloc>().add(LoadAssignmentsByEvent(widget.eventId));
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
              // Content
              Expanded(
                child: _useCache
                    ? _buildAssignmentsList(context, _cachedAssignments!)
                    : BlocBuilder<AssignmentBloc, AssignmentState>(
                        buildWhen: (previous, current) =>
                            current is AssignmentsLoaded ||
                            current is AssignmentLoading ||
                            current is AssignmentError,
                        builder: (context, state) {
                          if (state is AssignmentLoading) {
                            return const Center(child: CircularProgressIndicator());
                          } else if (state is AssignmentsLoaded) {
                            final assignments = state.assignments;
                            if (assignments.isEmpty) {
                              return Center(
                                child: Text(
                                  'אין שיבוצים לאירוע זה',
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                ),
                              );
                            }
                            return _buildAssignmentsList(context, assignments);
                          } else if (state is AssignmentError) {
                            return Center(
                              child: Text(
                                state.message,
                                style: const TextStyle(fontSize: 16, color: Colors.red),
                              ),
                            );
                          }
                          return const Center(child: CircularProgressIndicator());
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentsList(BuildContext context, List<Assignment> assignments) {
    // Wrap in BlocBuilder to properly rebuild when roles load
    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
        // Handle loading state
        if (roleState is! RolesLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final activeRoles = roleState.activeRoles;

    // Group assignments by role key
    final assignmentsByRole = <String, List<Assignment>>{};
    for (final assignment in assignments) {
      assignmentsByRole.putIfAbsent(assignment.roleType, () => []);
      assignmentsByRole[assignment.roleType]!.add(assignment);
    }

    // Sort team members alphabetically within each role
    for (final roleKey in assignmentsByRole.keys) {
      assignmentsByRole[roleKey]!.sort((a, b) {
        final aName = a.teamMember?.name ?? '';
        final bName = b.teamMember?.name ?? '';
        return aName.compareTo(bName);
      });
    }

    // Build list: only show roles that have assignments, in sortOrder
    final roleSections = <Widget>[];

    for (final role in activeRoles) {
      final roleAssignments = assignmentsByRole[role.key];
      if (roleAssignments == null || roleAssignments.isEmpty) {
        continue; // Skip roles with no assignments
      }

      roleSections.add(_buildRoleSection(role, roleAssignments));
    }

    if (roleSections.isEmpty) {
      return Center(
        child: Text(
          'אין שיבוצים לאירוע זה',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
      );
    }

    return ListView(
      children: roleSections,
    );
      },
    );
  }

  Widget _buildRoleSection(Role role, List<Assignment> assignments) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Role header with count
            Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 24,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    role.hebrewName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            const SizedBox(height: 8),
            // Team members
            ...assignments.map((assignment) {
              final member = assignment.teamMember;
              if (member == null) return const SizedBox.shrink();

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
                        // Phone icon with fallback: member phone → assignment alternative phone
                        if ((member.phoneNumber != null && member.phoneNumber!.isNotEmpty) ||
                            (assignment.alternativePhoneNumber != null && assignment.alternativePhoneNumber!.isNotEmpty)) ...[
                          InkWell(
                            onTap: () => _makePhoneCall(
                              (member.phoneNumber != null && member.phoneNumber!.isNotEmpty)
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
                        // Show status indicator if needed
                        if (assignment.status != AssignmentStatus.confirmed) ...[
                          _buildStatusIndicator(assignment.status),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    // Notes display
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
            }),
          ],
        ),
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
