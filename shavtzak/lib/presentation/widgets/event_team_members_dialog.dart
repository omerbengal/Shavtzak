import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../domain/entities/assignment.dart';
import '../../core/constants/role_types.dart';
import '../bloc/assignment/assignment_bloc.dart';
import '../bloc/assignment/assignment_event.dart';
import '../bloc/assignment/assignment_state.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_event.dart';
import '../bloc/team/team_state.dart';
import '../bloc/role/role_bloc.dart';
import '../bloc/role/role_state.dart';
import '../../../core/services/service_locator.dart';

/// Dialog showing all team members assigned to an event
/// Excludes the current user from the list
/// Dialog showing all team members assigned to an event
/// Excludes the current user from the list
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
        // Mark that we have data to prevent showing empty state
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
            // When team members are updated, refresh the assignments
            // This will trigger the assignment data to be re-populated with updated team member info
            if (state is TeamLoaded) {
              _assignmentBloc.add(LoadAssignmentsByEvent(widget.eventId));
            }
          },
          child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 8,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 500,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(
                    children: [
                      Icon(
                        Icons.groups,
                        color: Colors.blue.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'מי איתי באירוע?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Event name
                  Text(
                    'אירוע: ${widget.eventName}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Content
                  Expanded(
                    child: BlocBuilder<AssignmentBloc, AssignmentState>(
                      builder: (context, state) {
                        // If we have cached data and are still loading, show the cached data
                        if (state is AssignmentLoading && _cachedAssignments != null) {
                          // Show cached data while waiting for real-time stream
                          final filteredAssignments = _cachedAssignments!
                              .where((a) => a.teamMemberId != widget.currentUserId)
                              .toList();

                          if (filteredAssignments.isEmpty) {
                            // If we have shown data before but now it's empty, show loading instead of empty state
                            return _hasShownData
                                ? _buildLoadingState()
                                : _buildEmptyState();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${filteredAssignments.where((a) => a.teamMember != null).length} חברי צוות נוספים באירוע',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: _buildTeamMembersList(filteredAssignments),
                                ),
                              ),
                            ],
                          );
                        }

                        // Show loading spinner if we don't have cached data
                        if (state is AssignmentLoading && _cachedAssignments == null) {
                          return _buildLoadingState();
                        }

                        if (state is AssignmentsLoaded) {
                          // Filter assignments for this event and exclude current user
                          final eventAssignments = state.assignments
                              .where((a) => a.eventId == widget.eventId)
                              .toList();

                          final filteredAssignments = eventAssignments
                              .where((a) => a.teamMemberId != widget.currentUserId)
                              .toList();

                          if (filteredAssignments.isEmpty) {
                            return _buildEmptyState();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${filteredAssignments.where((a) => a.teamMember != null).length} חברי צוות נוספים באירוע',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: _buildTeamMembersList(filteredAssignments),
                                ),
                              ),
                            ],
                          );
                        }

                        if (state is AssignmentError) {
                          return Center(
                            child: Text(
                              'שגיאה בטעינת נתונים',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.red.shade600,
                              ),
                            ),
                          );
                        }

                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          backgroundColor: Colors.blue.shade50,
                          foregroundColor: Colors.blue.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('סגור'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_off_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'אין חברי צוות נוספים באירוע',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamMembersList(List<Assignment> assignments) {
    // Group by team member to handle multiple roles
    final Map<String, List<Assignment>> memberAssignments = {};
    for (final assignment in assignments) {
      final memberId = assignment.teamMemberId;

      // Add assignment even if teamMember is null - we'll handle it in the UI
      memberAssignments.putIfAbsent(memberId, () => []);
      memberAssignments[memberId]!.add(assignment);
    }

    // Sort by team member name, handling null team members
    final members = memberAssignments.entries.toList()
      ..sort((a, b) {
        final aName = a.value.first.teamMember?.name ?? 'Unknown';
        final bName = b.value.first.teamMember?.name ?? 'Unknown';
        return aName.compareTo(bName);
      });

    return Column(
      children: members.asMap().entries.map((entry) {
        final index = entry.key;
        final memberEntry = entry.value;

        return Column(
          children: [
            _buildTeamMemberItem(memberEntry),
            if (index < members.length - 1) const Divider(height: 1),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildTeamMemberItem(MapEntry<String, List<Assignment>> memberEntry) {
    final member = memberEntry.value.first.teamMember;
    final assignments = memberEntry.value;
    final roles = assignments.map((a) => a.roleType).toList()
      ..sort((a, b) => a.compareTo(b));

    // Skip if no team member data
    if (member == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              member.name.isNotEmpty ? member.name[0] : '?',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name, roles, and phone
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name with phone button
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (member.isPermanent) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_user,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (member.phoneNumber?.isNotEmpty == true) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => _launchPhone(member.phoneNumber!),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.phone,
                                size: 16,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                member.phoneNumber!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // Role badges
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: roles.map((roleKey) => _buildRoleBadge(roleKey)).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Launch phone dialer with the phone number
  void _launchPhone(String phoneNumber) async {
    // Clean the phone number - remove non-digit characters except +
    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // Create the tel: URL
    final url = 'tel:$cleanedNumber';

    // Try to launch
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url);
    }
  }

  Widget _buildRoleBadge(String roleKey) {
    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
        final roleHebrewName = roleState is RolesLoaded
            ? roleState.getRoleHebrewName(roleKey)
            : roleKey;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _getRoleColor(),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            roleHebrewName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Color _getRoleColor() {
    // Use green color for all roles for consistency
    return Colors.green.shade600;
  }
}