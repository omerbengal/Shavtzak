import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/role.dart';
import '../bloc/assignment/assignment_bloc.dart';
import '../bloc/assignment/assignment_event.dart';
import '../bloc/assignment/assignment_state.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_event.dart';
import '../bloc/team/team_state.dart';
import '../bloc/role/role_bloc.dart';
import '../bloc/role/role_state.dart';
import '../../../core/services/service_locator.dart';

/// Dialog showing all team members assigned to an event, grouped by role
/// Excludes the current user from the list
/// Uses the same UI layout as EventAssignmentsDialog
class EventTeamMembersDialog extends StatefulWidget {
  final String eventId;
  final String currentUserId;
  final String eventName;

  const EventTeamMembersDialog({
    super.key,
    required this.eventId,
    required this.currentUserId,
    required this.eventName,
  });

  @override
  State<EventTeamMembersDialog> createState() => _EventTeamMembersDialogState();
}


class _EventTeamMembersDialogState extends State<EventTeamMembersDialog> {
  late final AssignmentBloc _assignmentBloc;
  late final TeamBloc _teamBloc;
  List<Assignment>? _cachedAssignments;
  bool _hasShownData = false;

  @override
  void initState() {
    super.initState();
    // Create dedicated BLoCs for this dialog
    _assignmentBloc = serviceLocator.createAssignmentBloc();
    _teamBloc = serviceLocator.createTeamBloc();

    _loadAssignments();
  }

  @override
  void dispose() {
    _assignmentBloc.close();
    _teamBloc.close();
    super.dispose();
  }

  void _loadAssignments() async {
    // If we don't have cached data, prefetch it first
    if (_cachedAssignments == null) {
      try {
        final assignmentRepository = serviceLocator.createAssignmentRepository();
        final assignments = await assignmentRepository.getAssignmentsByEvent(widget.eventId);
        _cachedAssignments = assignments;
        _hasShownData = assignments.isNotEmpty;
      } catch (e) {
        // If prefetch fails, continue with BLoC loading
      }
    }

    // Use the AssignmentBloc's real-time stream
    _assignmentBloc.add(LoadAssignmentsByEvent(widget.eventId));
    // Also load team members to keep them updated
    _teamBloc.add(const LoadTeamMembers());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AssignmentBloc>.value(value: _assignmentBloc),
          BlocProvider<TeamBloc>.value(value: _teamBloc),
        ],
        child: BlocListener<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamLoaded) {
              _assignmentBloc.add(LoadAssignmentsByEvent(widget.eventId));
            }
          },
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
                          'מי איתי ב${widget.eventName}?',
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
                    child: BlocBuilder<AssignmentBloc, AssignmentState>(
                      builder: (context, state) {
                        // If we have cached data and are still loading, show the cached data
                        if (state is AssignmentLoading && _cachedAssignments != null) {
                          final filtered = _cachedAssignments!
                              .where((a) => a.teamMemberId != widget.currentUserId)
                              .toList();
                          if (filtered.isEmpty) {
                            return _hasShownData
                                ? const Center(child: CircularProgressIndicator())
                                : _buildEmptyState();
                          }
                          return _buildAssignmentsList(context, filtered);
                        }

                        if (state is AssignmentLoading && _cachedAssignments == null) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (state is AssignmentsLoaded) {
                          final filtered = state.assignments
                              .where((a) => a.eventId == widget.eventId)
                              .where((a) => a.teamMemberId != widget.currentUserId)
                              .toList();
                          if (filtered.isEmpty) {
                            return _buildEmptyState();
                          }
                          return _buildAssignmentsList(context, filtered);
                        }

                        if (state is AssignmentError) {
                          return Center(
                            child: Text(
                              'שגיאה בטעינת נתונים',
                              style: TextStyle(fontSize: 16, color: Colors.red.shade600),
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
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'אין חברי צוות נוספים באירוע',
        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
      ),
    );
  }

  Widget _buildAssignmentsList(BuildContext context, List<Assignment> assignments) {
    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
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
          if (roleAssignments == null || roleAssignments.isEmpty) continue;
          roleSections.add(_buildRoleSection(role, roleAssignments));
        }

        if (roleSections.isEmpty) {
          return _buildEmptyState();
        }

        return ListView(children: roleSections);
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
}