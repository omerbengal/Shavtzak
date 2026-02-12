import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/constants/constraint_status.dart';
import '../../../core/constants/calendar_constants.dart';
import '../../../core/state/constraint_manager.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/vehicle_info.dart';
import '../../../domain/entities/role.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/phone_input_formatter.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../core/utils/time_range_utils.dart';
import '../../../core/utils/search_utils.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/services/utilities_service.dart';
import 'package:uuid/uuid.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart' as team;
import '../../bloc/team/team_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/role/role_bloc.dart';
import '../../bloc/role/role_state.dart';
import '../../widgets/navigation_menu.dart';
import '../../widgets/date_picker_dialog.dart';
import '../../widgets/interactive_filter_bar.dart';
import '../../widgets/swipeable_page_view.dart';
import '../../widgets/admin_passcode_dialog.dart';
import '../../widgets/vehicle_info_copy_dialog.dart';
import '../../widgets/loading_overlay.dart';
import '../../../data/repositories/user_selection_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../bloc/calendar_sync/calendar_sync_bloc.dart';
import '../../bloc/calendar_sync/calendar_sync_event.dart';
import '../../bloc/calendar_sync/calendar_sync_state.dart';
import '../../widgets/archived_members_dialog.dart';
import 'dart:async';

// Filter enum for team members (0=all non-archived, 1=permanent, 2=non-permanent)
enum TeamFilter { all, permanent, nonPermanent }

class TeamListScreen extends StatefulWidget {
  const TeamListScreen({super.key});

  @override
  State<TeamListScreen> createState() => _TeamListScreenState();
}

class _TeamListScreenState extends State<TeamListScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';
  TeamLoaded? _lastLoadedState;
  bool _hasTriggeredInitialSync = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = createRtlCursorFixedFocusNode(_searchController);
    // Always load ALL team members - filtering happens in UI
    context.read<TeamBloc>().add(const team.LoadTeamMembers());
    // Ensure events are loaded (needed to count future available events for non-permanent members)
    context.read<EventBloc>().add(const LoadEvents());
    // Trigger calendar validation sync to check for deleted events on initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CalendarSyncBloc>().add(const ValidateSyncedEvents());
      _hasTriggeredInitialSync = true;
    });
    // Register callback for when this page becomes visible
    onTeamPageVisible = () {
      if (mounted && _hasTriggeredInitialSync) {
        context.read<CalendarSyncBloc>().add(const ValidateSyncedEvents());
      }
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    // Unregister callback
    onTeamPageVisible = null;
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  /// Handle phone number click with device-specific behavior
  Future<void> onPhoneClicked(String phoneNumber) async {
    // Remove any formatting characters (dashes, spaces)
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[-\s]'), '');
    final phoneUri = Uri(scheme: 'tel', path: cleanPhone);

    // Try to launch the phone URI
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      // Cannot launch tel:// URI - likely on desktop
      showDialog(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('שיחת טלפון'),
            content: Text('לא ניתן להתקשר מהמחשב\nמספר הטלפון: $phoneNumber'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('סגור'),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Handle filter change
  void _onFilterChanged(int newIndex) {
    setState(() {
      FilterPersistence.teamFilterIndex = newIndex;
    });
  }

  /// Build a compact icon button for the leading AppBar section
  Widget _buildCompactIcon({required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              // Leading: Sync button
              BlocListener<CalendarSyncBloc, CalendarSyncState>(
                listener: (context, state) {
                  if (state is CalendarSyncBidirectionalComplete) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Text(state.message),
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                  } else if (state is CalendarSyncFailure && state.constraintId == 'bidirectional') {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Text(state.errorMessage),
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 3),
                          action: SnackBarAction(
                            label: 'נסה שוב',
                            textColor: Colors.white,
                            onPressed: () {
                              context.read<CalendarSyncBloc>().add(const PerformBidirectionalSync());
                            },
                          ),
                        ),
                      );
                  }
                },
                child: BlocBuilder<CalendarSyncBloc, CalendarSyncState>(
                  builder: (context, state) {
                    final isInProgress = state is CalendarSyncInProgress && state.constraintId == 'bidirectional';
                    if (isInProgress) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }
                    return _buildCompactIcon(
                      icon: Icons.sync,
                      onPressed: () {
                        context.read<CalendarSyncBloc>().add(const PerformBidirectionalSync());
                      },
                    );
                  },
                ),
              ),
              // Leading: Vehicle info copy button
              _buildCompactIcon(
                icon: Icons.directions_car,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const Directionality(
                      textDirection: TextDirection.rtl,
                      child: VehicleInfoCopyDialog(),
                    ),
                  );
                },
              ),
              // Centered title
              const Expanded(
                child: Center(child: Text(AppStrings.team, style: TextStyle(fontSize: 20))),
              ),
              // Trailing: Archive button
              IconButton(
                icon: const Icon(Icons.inventory_2),
                tooltip: 'ארכיון',
                onPressed: () => ArchivedMembersDialog.show(context),
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              // Trailing: Home button
              IconButton(
                icon: const Icon(Icons.home),
                tooltip: 'בית',
                onPressed: () {
                  final envPrefix = EnvironmentService.instance.routePrefix;
                  context.go('$envPrefix/admin');
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              // Trailing: Logout button
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'התנתק',
                onPressed: () => _logout(context),
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
            ],
          ),
        ),
      body: BlocConsumer<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamError) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(state.message),
                    ),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                );
            } else if (state is TeamMemberOperationSuccess) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(state.message),
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
            }
          },
          builder: (context, state) {
            // Always show last known state if available, unless explicitly loading
            if (state is TeamLoading && _lastLoadedState == null) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (state is TeamEmpty) {
              return _buildEmptyState(state);
            }

            if (state is TeamLoaded) {
              _lastLoadedState = state;
              return _buildTeamList(state);
            }

            // For any other state (Success, Error), keep showing last state if available
            if (_lastLoadedState != null) {
              return _buildTeamList(_lastLoadedState!);
            }

            if (state is TeamError) {
              return _buildErrorState(state.message);
            }

            return _buildEmptyState(const TeamEmpty('טוען...'));
          },
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'team_fab',
          onPressed: () {
            _showTeamMemberFormModal(null);
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildTeamList(TeamLoaded state) {
    // Filter members based on selected filter
    final filteredMembers = _filterMembers(state.members, FilterPersistence.teamFilterIndex);

    // Split into members with pending constraints and without
    final membersWithPending = filteredMembers
        .where((m) => m.constraints.any((c) => c.status == ConstraintStatus.pending))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final membersWithoutPending = filteredMembers
        .where((m) => !m.constraints.any((c) => c.status == ConstraintStatus.pending))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return RefreshIndicator(
      onRefresh: () async {
        context.read<TeamBloc>().add(const team.RefreshTeamMembers());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          // Interactive filter bar
          InteractiveFilterBar(
            options: [
              FilterOption(label: 'סה״כ', count: state.totalCount.toString()),
              FilterOption(label: 'קבועים', count: state.permanentCount.toString()),
              FilterOption(label: 'לא קבועים', count: state.nonPermanentCount.toString()),
            ],
            selectedIndex: FilterPersistence.teamFilterIndex,
            onFilterChanged: _onFilterChanged,
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'חיפוש חבר צוות...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          // Team list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: membersWithPending.length +
                  (membersWithPending.isNotEmpty && membersWithoutPending.isNotEmpty ? 1 : 0) +
                  membersWithoutPending.length,
              itemBuilder: (context, index) {
                // Pending constraints section
                if (index < membersWithPending.length) {
                  return _buildTeamMemberCard(membersWithPending[index]);
                }
                // Divider between sections
                if (membersWithPending.isNotEmpty &&
                    membersWithoutPending.isNotEmpty &&
                    index == membersWithPending.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(thickness: 2, color: Colors.grey[700]),
                  );
                }
                // Remaining members section
                final remainingIndex = index -
                    membersWithPending.length -
                    (membersWithPending.isNotEmpty && membersWithoutPending.isNotEmpty ? 1 : 0);
                return _buildTeamMemberCard(membersWithoutPending[remainingIndex]);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Filter members based on selected filter index (always excludes archived)
  List<TeamMember> _filterMembers(List<TeamMember> members, int filterIndex) {
    // First, exclude archived members
    final nonArchivedMembers = members.where((m) => !m.isArchived).toList();

    List<TeamMember> result;
    switch (filterIndex) {
      case 0: // All non-archived
        result = nonArchivedMembers;
        break;
      case 1: // Permanent (non-archived)
        result = nonArchivedMembers.where((m) => m.isPermanent).toList();
        break;
      case 2: // Non-permanent (non-archived)
        result = nonArchivedMembers.where((m) => !m.isPermanent).toList();
        break;
      default:
        result = nonArchivedMembers;
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final normalizedQuery = normalizeForSearch(_searchQuery);
      result = result.where((member) {
        final normalizedName = normalizeForSearch(member.name);
        return normalizedName.contains(normalizedQuery);
      }).toList();
    }

    return result;
  }

  Widget _buildTeamMemberCard(TeamMember member) {
    // Count active roles
    final activeRoles =
        member.roleCapabilities.values.where((v) => v == true).length;

    return Card(
      child: InkWell(
        onTap: () {
          _showTeamMemberFormModal(member);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with avatar, name, and archive button
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: member.isActive ? Colors.green : Colors.grey,
                    child: Text(
                      member.name.isNotEmpty ? member.name[0] : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: member.isActive ? Colors.black : Colors.grey,
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
                  // Archive button
                  IconButton(
                    icon: Icon(
                      Icons.archive_outlined,
                      size: 20,
                      color: Colors.grey[600],
                    ),
                    tooltip: 'העבר לארכיון',
                    onPressed: () => _showArchiveConfirmation(member),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Info row
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Phone number if available
                  if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty)
                    InkWell(
                      onTap: () => onPhoneClicked(member.phoneNumber!),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone, size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              Validators.formatPhoneNumber(member.phoneNumber),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Birthday if available
                  if (member.birthday != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cake, size: 14, color: Colors.pink),
                          const SizedBox(width: 4),
                          Text(
                            '${member.birthday!.day.toString().padLeft(2, '0')}/${member.birthday!.month.toString().padLeft(2, '0')}/${member.birthday!.year}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.pink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Vehicle info if available
                  if (member.vehicleInfo != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_car, size: 14, color: Colors.brown),
                          const SizedBox(width: 4),
                          Text(
                            member.vehicleInfo!.displayString,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.brown,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '$activeRoles תפקידים',
                    style: const TextStyle(fontSize: 12),
                  ),
                  // Check if member has any relevant constraints (unavailability for permanent, availability for non-permanent)
                  // Uses BlocBuilder<EventBloc> so the count updates in real time when event dates change
                  BlocBuilder<EventBloc, EventState>(
                    builder: (context, eventState) {
                      // Helper function to check if constraint is past (same logic as admin modal)
                      bool isPastConstraint(DateConstraint constraint) {
                        if (constraint.endDate != null) {
                          final today = DateTime.now();
                          final constraintEndDate = DateTime(
                            constraint.endDate!.year,
                            constraint.endDate!.month,
                            constraint.endDate!.day,
                          );
                          final todayDate = DateTime(
                            today.year,
                            today.month,
                            today.day,
                          );
                          return constraintEndDate.isBefore(todayDate);
                        } else {
                          // For single-day constraints (no endDate), check if startDate is before today
                          final today = DateTime.now();
                          final constraintStartDate = DateTime(
                            constraint.startDate.year,
                            constraint.startDate.month,
                            constraint.startDate.day,
                          );
                          final todayDate = DateTime(
                            today.year,
                            today.month,
                            today.day,
                          );
                          return constraintStartDate.isBefore(todayDate);
                        }
                      }

                      // Non-permanent members: event-based availability (future events only)
                      if (!member.isPermanent) {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);

                        int availableCount;
                        if (eventState is EventsLoaded) {
                          availableCount = member.availableEventIds.where((id) =>
                            eventState.events.any((e) =>
                              e.id == id &&
                              !DateTime(e.endDate.year, e.endDate.month, e.endDate.day).isBefore(today),
                            ),
                          ).length;
                        } else {
                          availableCount = member.availableEventIds.length;
                        }

                        if (availableCount == 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          'זמין/ה ל-$availableCount אירועים',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }

                      // Permanent members: constraint-based logic (exclude rejected)
                      final activeConstraints = member.constraints
                          .where((c) => !isPastConstraint(c))
                          .where((c) => c.isUnavailability)
                          .where((c) => !c.isRejected())
                          .toList();
                      final approvedCount = activeConstraints.where((c) => c.isApproved()).length;
                      final pendingCount = activeConstraints.where((c) => c.isPending()).length;

                      if (activeConstraints.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      final totalCount = activeConstraints.length;

                      if (approvedCount > 0) {
                        return Row(
                          children: [
                            Text(
                              '$totalCount מגבלות',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (pendingCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '($pendingCount ממתינות לבחינה)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        );
                      } else if (pendingCount > 0) {
                        return Text(
                          '$pendingCount מגבלות ממתינות לבחינה',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
                  if (member.comments.isNotEmpty)
                    Text(
                      member.comments,
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTeamMemberFormModal(TeamMember? member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => _TeamMemberFormModal(
        member: member,
        filterIndex: FilterPersistence.teamFilterIndex,
        onSuccess: () {
          Navigator.of(modalContext).pop();
        },
      ),
    );
  }

  void _showArchiveConfirmation(TeamMember member) {
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('העברה לארכיון'),
          content: Text(
            'האם להעביר את ${member.name} לארכיון?\n\nחבר/ת צוות בארכיון לא יופיע/תופיע ברשימה הראשית ולא ניתן לשבצו/ה.',
          ),
          actions: [
            TextButton(
              child: const Text('ביטול'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('העבר לארכיון'),
              onPressed: () {
                Navigator.pop(dialogContext);
                final updatedMember = member.copyWith(
                  isArchived: true,
                  updatedAt: DateTime.now(),
                );
                context.read<TeamBloc>().add(team.UpdateTeamMember(updatedMember));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text('${member.name} הועבר/ה לארכיון'),
                    ),
                    backgroundColor: Colors.orange,
                    action: SnackBarAction(
                      label: 'ביטול',
                      textColor: Colors.white,
                      onPressed: () {
                        // Restore the member
                        final restoredMember = member.copyWith(
                          isArchived: false,
                          updatedAt: DateTime.now(),
                        );
                        context.read<TeamBloc>().add(team.UpdateTeamMember(restoredMember));
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(TeamMember member) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת חבר צוות'),
          content: Text(
            'האם אתה בטוח שברצונך למחוק את ${member.name}?\nפעולה זו תמחק גם את כל השיבוצים שלו.',
          ),
          actions: [
            TextButton(
              child: const Text('ביטול'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
              onPressed: () {
                context.read<TeamBloc>().add(team.DeleteTeamMember(member.id));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(TeamEmpty state) {
    return Column(
      children: [
        // Show interactive filter bar if this is a filtered empty state
        if (state.isFiltered)
          InteractiveFilterBar(
            options: const [
              FilterOption(label: 'סה״כ', count: '0'),
              FilterOption(label: 'פעילים', count: '0'),
              FilterOption(label: 'לא פעילים', count: '0'),
            ],
            selectedIndex: FilterPersistence.teamFilterIndex,
            onFilterChanged: _onFilterChanged,
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  state.message,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                // Only show "add first" button if database is truly empty (not filtered)
                if (!state.isFiltered)
                  ElevatedButton.icon(
                    onPressed: () {
                      _showTeamMemberFormModal(null);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('הוסף חבר צוות ראשון'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              context.read<TeamBloc>().add(const team.LoadTeamMembers());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    // Sign out first
    context.read<UserSelectionBloc>().add(const SignOut());

    // Listen for the state change and then navigate once
    bool handled = false;
    StreamSubscription? subscription;
    subscription = context.read<UserSelectionBloc>().stream.listen((state) {
      if (!handled && state is UserSignedOut && context.mounted) {
        handled = true;
        subscription?.cancel();
        final envPrefix = EnvironmentService.instance.routePrefix;
        context.go('$envPrefix/whoami');
      }
    });
  }
}

// Team Member Form Modal Widget
class _TeamMemberFormModal extends StatefulWidget {
  final TeamMember? member; // null for create, non-null for edit
  final int filterIndex;
  final VoidCallback onSuccess;

  const _TeamMemberFormModal({
    this.member,
    required this.filterIndex,
    required this.onSuccess,
  });

  @override
  State<_TeamMemberFormModal> createState() => _TeamMemberFormModalState();
}

class _TeamMemberFormModalState extends State<_TeamMemberFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _commentsController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _vehicleInfoController = TextEditingController();

  // Birthday fields
  int? _birthdayDay;
  int? _birthdayMonth;
  int? _birthdayYear;

  // Vehicle info fields
  VehicleInfo? _vehicleInfo;

  // Hebrew month names
  static const List<String> _hebrewMonths = [
    'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
    'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
  ];

  int get _maxBirthdayYear => DateTime.now().year - 20;
  int get _minBirthdayYear => DateTime.now().year - 100;

  bool _isActive = true;
  bool _isPermanent = false;
  bool _allowMultipleAssignments = false;
  bool _canAccessSummaryScreen = false;
  Map<String, bool> _roleCapabilities = {};

  late TeamBloc _teamBloc;
  List<DateConstraint> _constraints = [];
  List<String> _availableEventIds = []; // Event-based availability for non-permanent members
  bool _isDirty = false;
  String? _roleError; // Track role validation error
  bool _isSaving = false;
  bool _isDeleting = false;
  late final FocusNode _nameFocusNode;
  late final FocusNode _commentsFocusNode;

    bool get _isEditMode => widget.member != null;

  @override
  void initState() {
    super.initState();
    _nameFocusNode = createRtlCursorFixedFocusNode(_nameController);
    _commentsFocusNode = createRtlCursorFixedFocusNode(_commentsController);

    // Initialize role capabilities with all roles set to false
    // Will be populated from RoleBloc when state is loaded

    // Load existing member data if editing
    if (_isEditMode) {
      _nameController.text = widget.member!.name;
      _phoneController.text = widget.member!.phoneNumber ?? '';
      _commentsController.text = widget.member!.comments;
      _isActive = widget.member!.isActive;
      _isPermanent = widget.member!.isPermanent;
      _allowMultipleAssignments = widget.member!.allowMultipleAssignments;
      _canAccessSummaryScreen = widget.member!.canAccessSummaryScreen;
      _roleCapabilities = Map.from(widget.member!.roleCapabilities);
      _constraints = List.from(widget.member!.constraints);
      _availableEventIds = List.from(widget.member!.availableEventIds);
      if (widget.member!.birthday != null) {
        _birthdayDay = widget.member!.birthday!.day;
        _birthdayMonth = widget.member!.birthday!.month;
        _birthdayYear = widget.member!.birthday!.year;
        _updateBirthdayController();
      }
      _vehicleInfo = widget.member!.vehicleInfo;
      _updateVehicleInfoController();
    }

    // Track dirty state
    _nameController.addListener(() => _isDirty = true);
    _phoneController.addListener(() => _isDirty = true);
    _commentsController.addListener(() => _isDirty = true);
  }

  void _updateBirthdayController() {
    if (_birthdayDay != null && _birthdayMonth != null && _birthdayYear != null) {
      _birthdayController.text = '${_birthdayDay.toString().padLeft(2, '0')}/${_birthdayMonth.toString().padLeft(2, '0')}/$_birthdayYear';
    } else {
      _birthdayController.clear();
    }
  }

  void _updateVehicleInfoController() {
    if (_vehicleInfo != null && _vehicleInfo!.isComplete) {
      _vehicleInfoController.text = _vehicleInfo!.displayString;
    } else {
      _vehicleInfoController.clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _teamBloc = context.read<TeamBloc>();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _commentsController.dispose();
    _birthdayController.dispose();
    _vehicleInfoController.dispose();
    _nameFocusNode.dispose();
    _commentsFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveMember() async {
    if (_isSaving) return; // Prevent double-submit

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate at least one role is selected
    if (!_roleCapabilities.values.any((selected) => selected)) {
      setState(() {
        _roleError = 'יש לבחור לפחות תפקיד אחד';
      });
      return;
    }

    setState(() => _isSaving = true);

    // Use the constraints list directly
    final finalConstraints = _constraints;

    final now = DateTime.now();
    final birthday = (_birthdayDay != null && _birthdayMonth != null && _birthdayYear != null)
        ? DateTime(_birthdayYear!, _birthdayMonth!, _birthdayDay!)
        : null;
    final member = TeamMember(
      id: _isEditMode ? widget.member!.id : const Uuid().v4(),
      uniqueKey: _isEditMode ? widget.member!.uniqueKey : const Uuid().v4(),
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim().isEmpty
        ? null
        : _phoneController.text.trim(),
      birthday: birthday,
      vehicleInfo: _vehicleInfo,
      isActive: _isActive,
      isPermanent: _isPermanent,
      allowMultipleAssignments: _allowMultipleAssignments,
      canAccessSummaryScreen: _canAccessSummaryScreen,
      constraints: finalConstraints,
      roleCapabilities: _roleCapabilities,
      comments: _commentsController.text.trim(),
      createdAt: _isEditMode ? widget.member!.createdAt : now,
      updatedAt: now,
      isAdmin: _isEditMode ? widget.member!.isAdmin : false,
      availableEventIds: _availableEventIds,
    );

    // Check for conflicting assignments if editing and constraints changed
    if (_isEditMode && _constraintsChanged()) {
      final conflictingAssignments = await _getConflictingAssignments(member);

      if (conflictingAssignments.isNotEmpty) {
        // Show warning dialog
        final action = await _showConflictWarningDialog(conflictingAssignments);

        if (action == null) {
          // User cancelled, don't save
          if (mounted) setState(() => _isSaving = false);
          return;
        }

        if (action == true) {
          // User chose "שמור ומחק שיבוצים" (Save + Delete assignments)
          final assignmentBloc = context.read<AssignmentBloc>();
          for (final assignment in conflictingAssignments) {
            assignmentBloc.add(DeleteAssignment(assignment.id));
          }

          // Wait a moment for deletions to process
          await Future.delayed(const Duration(milliseconds: 300));
        }
        // If action == false, user chose "שמור והשאר שיבוצים" (Save + Keep assignments)
        // So we proceed with saving without deleting assignments
      }
    }

    final bloc = context.read<TeamBloc>();
    if (_isEditMode) {
      bloc.add(team.UpdateTeamMember(member));
    } else {
      bloc.add(team.CreateTeamMember(member));
    }

    // Reload all team members after operation completes (filtering happens in UI)
    Future.delayed(const Duration(milliseconds: 100), () {
      bloc.add(const team.LoadTeamMembers());
    });

    // Close modal after save operation
    widget.onSuccess();
  }

  /// Check if constraints have changed since loading
  bool _constraintsChanged() {
    if (!_isEditMode) return false;

    final originalConstraints = widget.member!.constraints;

    // Check if length changed
    if (originalConstraints.length != _constraints.length) {
      return true;
    }

    // Check if any constraint is different
    for (int i = 0; i < originalConstraints.length; i++) {
      if (originalConstraints[i] != _constraints[i]) {
        return true;
      }
    }

    return false;
  }

  /// Get assignments that conflict with the new constraints
  Future<List<Assignment>> _getConflictingAssignments(TeamMember member) async {
    try {
      final assignmentRepository = RepositoryProvider.of<AssignmentRepository>(context);
      final allAssignments = await assignmentRepository.getAssignmentsByPerson(member.id);

      final conflicting = <Assignment>[];

      for (final assignment in allAssignments) {
        if (assignment.event == null) continue;

        // Check if any ACTIVE constraint conflicts with the assignment's event date
        // Rejected constraints should not cause conflicts
        for (final constraint in member.constraints) {
          // Skip rejected constraints - they should not affect assignments
          if (constraint.status == ConstraintStatus.rejected) continue;

          if (constraint.conflictsWith(assignment.event!.startDate)) {
            conflicting.add(assignment);
            break; // No need to check other constraints for this assignment
          }
        }
      }

      return conflicting;
    } catch (e) {
      return [];
    }
  }

  /// Show warning dialog about conflicting assignments
  Future<bool?> _showConflictWarningDialog(List<Assignment> conflictingAssignments) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => BlocBuilder<RoleBloc, RoleState>(
        builder: (context, roleState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('אזהרה - שיבוצים קיימים'),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'נמצאו שיבוצים קיימים שמתנגשים עם המגבלות החדשות:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: conflictingAssignments.map((assignment) {
                            final eventName = assignment.event?.name ?? 'אירוע לא ידוע';
                            final startDate = assignment.event?.startDate;
                            final endDate = assignment.event?.endDate;
                            String dateStr = '';
                            if (startDate != null) {
                              dateStr = '${startDate.day}/${startDate.month}/${startDate.year}';
                              // Add end date if it exists and is different from start date
                              if (endDate != null &&
                                  (endDate.day != startDate.day ||
                                   endDate.month != startDate.month ||
                                   endDate.year != startDate.year)) {
                                dateStr += ' - ${endDate.day}/${endDate.month}/${endDate.year}';
                              }
                            }
                            final roleName = roleState is RolesLoaded
                                ? roleState.getRoleHebrewName(assignment.roleType)
                                : assignment.roleType;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.warning, color: Colors.orange, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$eventName ($dateStr) - $roleName',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'בחר את הפעולה הרצויה:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('שמור ומחק שיבוצים'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('שמור והשאר שיבוצים'),
            ),
          ],
        ),
          );
        },
      ),
    );
  }

  
  void _handleClose() {
    if (_isDirty) {
      showDialog(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('שינויים לא נשמרו'),
            content: const Text('האם אתה בטוח שברצונך לצאת? השינויים לא יישמרו.'),
            actions: [
              TextButton(
                child: const Text('ביטול'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('צא'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Close dialog
                  widget.onSuccess(); // Close modal
                },
              ),
            ],
          ),
        ),
      );
    } else {
      widget.onSuccess();
    }
  }

  void _showAdminPasscodeDialog() async {
    if (!_isEditMode || widget.member == null) return;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AdminPasscodeDialog(
        teamMemberName: widget.member!.name,
        currentPasscode: widget.member!.passcode,
        currentLength: widget.member!.passcodeLength,
      ),
    );

    if (result != null && result['action'] == 'set' && context.mounted) {
      // Set or change passcode
      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();
        await userSelectionRepo.setTeamMemberPasscode(
          widget.member!.uniqueKey,
          result['passcode'] as String,
          result['length'] as int,
        );

        // Refresh team member data
        _teamBloc.add(const team.LoadTeamMembers());

        // Close modal to refresh the UI and show updated passcode status
        widget.onSuccess();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('קוד הגישה עודכן בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון קוד גישה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (result != null && result['action'] == 'remove' && context.mounted) {
      // Remove passcode
      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();
        await userSelectionRepo.clearTeamMemberPasscode(widget.member!.uniqueKey);

        // Refresh team member data
        _teamBloc.add(const team.LoadTeamMembers());

        // Close modal to refresh the UI and show updated passcode status
        widget.onSuccess();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('קוד הגישה הוסר בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהסרת קוד גישה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final horizontalPadding = maxWidth > 1000
                  ? (maxWidth - 1000) / 2
                  : 0.0;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: Column(
                children: [
                  // Modal Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isEditMode ? 'עריכת חבר צוות' : 'הוספת חבר צוות',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_isEditMode)
                          BlocBuilder<UserSelectionBloc, UserSelectionState>(
                            builder: (context, userState) {
                              final bool isOwnProfile = userState is UserAuthenticated &&
                                  widget.member!.id == userState.user.id;

                              return IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  color: isOwnProfile ? Colors.grey.shade400 : Colors.red,
                                ),
                                onPressed: isOwnProfile ? null : () {
                                  showDialog(
                                    context: context,
                                    builder: (dialogContext) => Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: AlertDialog(
                                        title: const Text('מחיקת חבר צוות'),
                                        content: Text(
                                          'האם אתה בטוח שברצונך למחוק את ${widget.member!.name}?\nפעולה זו תמחק גם את כל השיבוצים שלו.',
                                        ),
                                        actions: [
                                          TextButton(
                                            child: const Text('ביטול'),
                                            onPressed: () => Navigator.of(dialogContext).pop(),
                                          ),
                                          TextButton(
                                            child: const Text('מחק', style: TextStyle(color: Colors.red)),
                                            onPressed: () {
                                              Navigator.of(dialogContext).pop(); // Close dialog first
                                              setState(() => _isDeleting = true);
                                              final bloc = context.read<TeamBloc>();
                                              bloc.add(team.DeleteTeamMember(widget.member!.id));
                                              // Reload all team members after operation completes (filtering happens in UI)
                                              Future.delayed(const Duration(milliseconds: 300), () {
                                                bloc.add(const team.LoadTeamMembers());
                                              });
                                              // Close modal after showing delete overlay briefly
                                              Future.delayed(const Duration(milliseconds: 500), () {
                                                widget.onSuccess();
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                tooltip: isOwnProfile ? 'לא ניתן למחוק את עצמך' : 'מחק',
                              );
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _handleClose,
                        ),
                      ],
                    ),
                  ),

                  // Modal Body (Scrollable)
                  Expanded(
                    child: BlocConsumer<TeamBloc, TeamState>(
                      listener: (context, state) {
                        // Update constraints when database changes
                        if (_isEditMode && state is TeamLoaded) {
                          final updatedMember = state.members.cast<TeamMember?>().firstWhere(
                            (member) => member?.id == widget.member!.id,
                            orElse: () => null,
                          );
                          if (updatedMember != null) {
                            // Update constraints with the latest database state
                            _constraints = List.from(updatedMember.constraints);
                            setState(() {});
                          }
                        }
                      },
                      builder: (context, state) {
                        return Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 16,
                            ),
                            children: [
                              const SizedBox(height: 16),

                              // Name field
                              TextFormField(
                                controller: _nameController,
                                focusNode: _nameFocusNode,
                                decoration: const InputDecoration(
                                  labelText: 'שם חבר הצוות',
                                  hintText: 'הזן שם מלא',
                                  prefixIcon: Icon(Icons.person),
                                  border: OutlineInputBorder(),
                                ),
                                validator: Validators.validateName,
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Phone number field
                              TextFormField(
                                controller: _phoneController,
                                decoration: const InputDecoration(
                                  labelText: 'מספר טלפון',
                                  hintText: '05X-XXXXXXX',
                                  prefixIcon: Icon(Icons.phone),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                                validator: Validators.validatePhoneNumber,
                                keyboardType: TextInputType.phone,
                                textDirection: TextDirection.ltr,
                                smartQuotesType: SmartQuotesType.disabled,
                                smartDashesType: SmartDashesType.disabled,
                                textAlign: TextAlign.end, // Right-aligned while keeping LTR
                                inputFormatters: [
                                  PhoneNumberTextInputFormatter(),
                                ],
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Birthday field - read-only text field with floating label
                              TextFormField(
                                readOnly: true,
                                onTap: () => _showBirthdayPickerDialog(),
                                decoration: InputDecoration(
                                  labelText: 'תאריך לידה',
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.cake,
                                      color: (_birthdayDay != null && _birthdayMonth != null && _birthdayYear != null)
                                          ? Colors.black87
                                          : Colors.grey,
                                    ),
                                  ),
                                  border: const OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.grey, width: 0.5),
                                  ),
                                  enabledBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.grey, width: 0.5),
                                  ),
                                ),
                                controller: _birthdayController,
                                style: TextStyle(
                                  color: (_birthdayDay != null && _birthdayMonth != null && _birthdayYear != null)
                                      ? Colors.black87
                                      : Colors.grey,
                                  ),
                                textAlign: TextAlign.right,
                              ),

                              const SizedBox(height: 16),

                              // Vehicle info field - read-only text field with floating label
                              TextFormField(
                                readOnly: true,
                                onTap: () => _showVehicleInfoDialog(),
                                decoration: InputDecoration(
                                  labelText: 'פרטי רכב',
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      _vehicleInfo != null && _vehicleInfo!.isComplete
                                          ? Icons.directions_car
                                          : Icons.directions_car_outlined,
                                      color: _vehicleInfo != null && _vehicleInfo!.isComplete
                                          ? Colors.black87
                                          : Colors.grey,
                                    ),
                                  ),
                                  border: const OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.grey, width: 0.5),
                                  ),
                                  enabledBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.grey, width: 0.5),
                                  ),
                                  suffixIcon: _vehicleInfo != null && _vehicleInfo!.isComplete
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 20),
                                          onPressed: () {
                                            setState(() {
                                              _vehicleInfo = null;
                                              _updateVehicleInfoController();
                                              _isDirty = true;
                                            });
                                          },
                                        )
                                      : null,
                                ),
                                controller: _vehicleInfoController,
                                style: TextStyle(
                                  color: _vehicleInfo != null && _vehicleInfo!.isComplete
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                                textAlign: TextAlign.right,
                              ),

                              const SizedBox(height: 16),

                              // Active status switch
                              SwitchListTile(
                                title: const Text('חבר צוות פעיל'),
                                subtitle: Text(
                                  _isActive
                                      ? 'ניתן לשבץ לאירועים'
                                      : 'לא ניתן לשבץ לאירועים',
                                ),
                                value: _isActive,
                                onChanged: (value) {
                                  setState(() {
                                    _isActive = value;
                                    _isDirty = true;
                                  });
                                },
                              ),

                              // Permanent status switch
                              SwitchListTile(
                                title: const Text('חבר צוות קבוע'),
                                value: _isPermanent,
                                onChanged: (value) {
                                  setState(() {
                                    _isPermanent = value;
                                    _isDirty = true;
                                  });
                                },
                              ),

                              // Multiple assignment switch
                              SwitchListTile(
                                title: const Text('שיבוץ מרובה'),
                                subtitle: const Text(
                                  'מאפשר שיבוץ לאותו אירוע מספר פעמים',
                                ),
                                value: _allowMultipleAssignments,
                                onChanged: (value) {
                                  setState(() {
                                    _allowMultipleAssignments = value;
                                    _isDirty = true;
                                  });
                                },
                              ),

                              // Summary screen access switch
                              SwitchListTile(
                                title: const Text('גישה למסך מנהלים'),
                                subtitle: const Text(
                                  'מאפשר לחבר צוות שאינו מנהל לצפות במסך מנהלים',
                                ),
                                value: _canAccessSummaryScreen,
                                onChanged: (value) {
                                  setState(() {
                                    _canAccessSummaryScreen = value;
                                    _isDirty = true;
                                  });
                                },
                              ),

                              const Divider(height: 32),

                              // Role capabilities section - wrapped with BlocBuilder
                              BlocBuilder<RoleBloc, RoleState>(
                                builder: (context, roleState) {
                                  return Column(
                                    children: [
                                      // Role capabilities header with buttons
                                      Row(
                                        children: [
                                          const Text(
                                            'תפקידים',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton(
                                            onPressed: () {
                                              setState(() {
                                                // Select all roles from RoleBloc
                                                if (roleState is RolesLoaded) {
                                                  for (final role in roleState.allNonArchivedRoles) {
                                                    _roleCapabilities[role.key] = true;
                                                  }
                                                }
                                                _roleError = null; // Clear error
                                                _isDirty = true;
                                              });
                                            },
                                            child: const Text('בחר הכל'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              setState(() {
                                                // Deselect all roles from RoleBloc
                                                if (roleState is RolesLoaded) {
                                                  for (final role in roleState.allNonArchivedRoles) {
                                                    _roleCapabilities[role.key] = false;
                                                  }
                                                }
                                                _isDirty = true;
                                              });
                                            },
                                            child: const Text('נקה הכל'),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 8),

                                      // Role validation error
                                      if (_roleError != null)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 16, bottom: 8),
                                          child: Text(
                                            _roleError!,
                                            style: TextStyle(
                                              color: Colors.red.shade700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),

                                      // Role checkboxes
                                      Builder(
                                        builder: (context) {
                                          // Get all non-archived roles
                                          List<Role> roles;
                                          if (roleState is RolesLoaded) {
                                            roles = roleState.allNonArchivedRoles;
                                          } else {
                                            // Fallback to RoleType.values during initial load
                                            roles = RoleType.values.map((rt) => Role(
                                              id: rt.key,
                                              key: rt.key,
                                              hebrewName: rt.hebrewName,
                                              isVisible: true,
                                              isArchived: false,
                                              sortOrder: RoleType.values.indexOf(rt),
                                              createdAt: DateTime.now(),
                                              updatedAt: DateTime.now(),
                                            )).toList();
                                          }

                                          return Container(
                                    decoration: _roleError != null
                                        ? BoxDecoration(
                                            border: Border.all(color: Colors.red.shade700),
                                            borderRadius: BorderRadius.circular(4),
                                            color: Colors.red.shade50,
                                          )
                                        : null,
                                    child: Column(
                                      children: roles.map((roleObj) {
                                        return CheckboxListTile(
                                          title: Text(roleObj.hebrewName),
                                          value: _roleCapabilities[roleObj.key] ?? false,
                                          onChanged: (value) {
                                            setState(() {
                                              _roleCapabilities[roleObj.key] = value ?? false;
                                              _roleError = null; // Clear error when user interacts
                                              _isDirty = true;
                                            });
                                          },
                                          controlAffinity: ListTileControlAffinity.leading,
                                        );
                                      }).toList(),
                                    ),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),

                              const Divider(height: 32),

                              // Date constraints/availability section
                              Row(
                                children: [
                                  Text(
                                    _isPermanent ? 'מגבלות זמן' : 'זמינות לאירועים',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _isPermanent ? null : Colors.green[700],
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_isPermanent) ...[
                                    // Add constraint button for permanent members
                                    IconButton(
                                      onPressed: () => _addConstraintOrAvailability(),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Colors.orange,
                                      ),
                                      tooltip: 'הוסף מגבלה',
                                    ),
                                    // Show rejected constraints button
                                    if (_constraints.any((c) => c.isUnavailability && c.status == ConstraintStatus.rejected))
                                      TextButton.icon(
                                        onPressed: () => _showRejectedConstraints(_constraints.where((c) => c.isUnavailability && c.status == ConstraintStatus.rejected).toList()),
                                        icon: const Icon(
                                          Icons.visibility,
                                          size: 20,
                                        ),
                                        label: Text(
                                          'הצג מגבלות שנדחו (${_constraints.where((c) => c.isUnavailability && c.status == ConstraintStatus.rejected).length})',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.grey[600],
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                  ] else ...[
                                    // Edit availability button for non-permanent members (blue pencil)
                                    IconButton(
                                      onPressed: () => _editAvailabilityEvents(),
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.blue,
                                      ),
                                      tooltip: 'ערוך זמינות',
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Helper text
                              Text(
                                _isPermanent
                                    ? 'כאן תוכל לאשר או לדחות בקשות מגבלות מחברי צוות קבועים. מגבלות מאושרות ימנעו שיבוץ לאירועים.'
                                    : 'אירועים שחבר הצוות הזה סימן את עצמו/ה זמין/ה להתנדב. לחץ על העיגול כדי לערוך.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),

                              const SizedBox(height: 8),

                              // Constraints list (permanent) / Availability events list (non-permanent)
                              if (_isPermanent)
                                ..._buildVisibleConstraintsList()
                              else
                                BlocBuilder<EventBloc, EventState>(
                                  builder: (context, eventState) {
                                    if (eventState is! EventsLoaded) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }

                                    final now = DateTime.now();
                                    final today = DateTime(now.year, now.month, now.day);

                                    // Get future events that this member is available for
                                    final availableEvents = eventState.events.where((event) {
                                      final eventEndDate = DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
                                      return !eventEndDate.isBefore(today) && _availableEventIds.contains(event.id);
                                    }).toList()
                                      ..sort((a, b) => a.startDate.compareTo(b.startDate));

                                    if (availableEvents.isEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          'אין אירועים נבחרים',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 16,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }

                                    return Column(
                                      children: availableEvents.map((event) {
                                        final formattedLocation = event.location.isNotEmpty
                                            ? _formatLocationForDisplay(event.location)
                                            : '';

                                        return Card(
                                          color: Colors.green[50],
                                          margin: const EdgeInsets.only(bottom: 8),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.event_available,
                                                      color: Colors.green[600],
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        event.name,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 16,
                                                          color: Colors.green[700],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 28),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        _formatEventDates(event),
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          color: Colors.black,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      Text(
                                                        _formatEventTimes(event),
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.black,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      if (formattedLocation.isNotEmpty)
                                                        Text(
                                                          'מיקום: $formattedLocation',
                                                          style: const TextStyle(
                                                            fontSize: 13,
                                                            color: Colors.black,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),

                              const Divider(height: 32),

                              // Passcode management section (admin only, edit mode only)
                              if (_isEditMode) ...[
                                Row(
                                  children: [
                                    const Text(
                                      'ניהול קוד גישה',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () => _showAdminPasscodeDialog(),
                                      icon: const Icon(Icons.admin_panel_settings, size: 20),
                                      label: const Text('נהל קוד'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Theme.of(context).primaryColor,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        widget.member?.passcode != null ? Icons.lock : Icons.lock_open,
                                        color: widget.member?.passcode != null
                                            ? Theme.of(context).primaryColor
                                            : Colors.grey[400],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          widget.member?.passcode != null
                                              ? 'קוד גישה מוגדר (${widget.member?.passcodeLength} ספרות)'
                                              : 'לא הוגדר קוד גישה',
                                          style: TextStyle(
                                            color: widget.member?.passcode != null
                                                ? null
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              const Divider(height: 32),

                              // Comments field
                              TextFormField(
                                controller: _commentsController,
                                focusNode: _commentsFocusNode,
                                decoration: const InputDecoration(
                                  labelText: 'הערות',
                                  hintText: 'הערות על חבר הצוות',
                                  prefixIcon: Icon(Icons.comment),
                                  border: OutlineInputBorder(),
                                ),
                                minLines: 1,
                                maxLines: 3,
                                scrollPadding: const EdgeInsets.only(bottom: 300),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              // Dynamic bottom spacing for keyboard
                              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 80),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Modal Footer (Fixed at bottom)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _handleClose,
                            child: const Text('ביטול'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveMember,
                            child: const Text('שמור'),
                          ),
                        ),
                      ],
                    ),
                  ),
                      ],
                    ),
                  ),
                      // Loading overlay
                      LoadingOverlay(
                        isLoading: _isSaving || _isDeleting,
                        message: _isDeleting ? 'מוחק איש צוות...' : (_isEditMode ? 'שומר איש צוות...' : 'יוצר איש צוות...'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
  }

  Widget _buildConstraintCard(DateConstraint constraint) {
    // Handle availability constraints differently
    if (constraint.isAvailability) {
      return _buildAvailabilityCard(constraint);
    }

    // For unavailability constraints (permanent members), use existing logic
    final effectiveStatus = constraint.status;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              effectiveStatus == ConstraintStatus.pending ? Icons.hourglass_empty :
              effectiveStatus == ConstraintStatus.approved ? Icons.check_circle : Icons.cancel,
              color: effectiveStatus == ConstraintStatus.pending ? Colors.amber :
                     effectiveStatus == ConstraintStatus.approved ? Colors.green : Colors.red,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    constraint.endDate != null && !_isSameDay(constraint.startDate, constraint.endDate!)
                        ? '${_formatDate(constraint.startDate)} - ${_formatDate(constraint.endDate!)}'
                        : _formatDate(constraint.startDate),
                  ),
                ),
                _buildStatusBadge(effectiveStatus),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (constraint.startTime != null || constraint.endTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'שעות: ${constraint.startTime ?? '---'} - ${constraint.endTime ?? '---'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                if (constraint.note != null && constraint.note!.isNotEmpty)
                  Text(
                    constraint.note!,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                  onPressed: () => _editConstraintOrAvailability(constraint),
                  tooltip: 'ערוך',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  onPressed: () => _deleteConstraintOrAvailability(constraint),
                  tooltip: 'מחק',
                ),
              ],
            ),
            onTap: null,
          ),
          // Status change controls for all constraints
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: effectiveStatus == ConstraintStatus.pending
                  ? Colors.amber[50]
                  : effectiveStatus == ConstraintStatus.approved
                      ? Colors.green[50]
                      : Colors.grey[50],
              border: Border(
                top: BorderSide(
                  color: effectiveStatus == ConstraintStatus.pending
                      ? Colors.amber[200]!
                      : effectiveStatus == ConstraintStatus.approved
                          ? Colors.green[200]!
                          : Colors.grey[200]!,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Right button (first in RTL)
                if (effectiveStatus == ConstraintStatus.pending)
                  // Pending: Right = Accept
                  TextButton.icon(
                    onPressed: () => _approveConstraint(constraint.id),
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    label: const Text('אשר', style: TextStyle(color: Colors.green)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green[50],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  )
                else if (effectiveStatus == ConstraintStatus.approved)
                  // Approved: Right = Pending
                  TextButton.icon(
                    onPressed: () => _setPendingConstraint(constraint.id),
                    icon: const Icon(Icons.hourglass_empty, color: Colors.amber, size: 20),
                    label: const Text('החזר לממתין', style: TextStyle(color: Colors.amber)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.amber[50],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  )
                else // Rejected: Right = Pending
                  TextButton.icon(
                    onPressed: () => _setPendingConstraint(constraint.id),
                    icon: const Icon(Icons.hourglass_empty, color: Colors.amber, size: 20),
                    label: const Text('החזר לממתין', style: TextStyle(color: Colors.amber)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.amber[50],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),

                const SizedBox(width: 8), // Consistent spacing

                // Left button (last in RTL)
                if (effectiveStatus == ConstraintStatus.pending)
                  // Pending: Left = Reject
                  TextButton.icon(
                    onPressed: () => _rejectConstraint(constraint.id),
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                    label: const Text('דחה', style: TextStyle(color: Colors.red)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  )
                else if (effectiveStatus == ConstraintStatus.approved)
                  // Approved: Left = Reject
                  TextButton.icon(
                    onPressed: () => _rejectConstraint(constraint.id),
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                    label: const Text('דחה', style: TextStyle(color: Colors.red)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  )
                else // Rejected: Left = Accept
                  TextButton.icon(
                    onPressed: () => _approveConstraint(constraint.id),
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    label: const Text('אשר', style: TextStyle(color: Colors.green)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green[50],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ConstraintStatus status) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case ConstraintStatus.pending:
        backgroundColor = Colors.orange;
        textColor = Colors.white;
        text = 'ממתין';
        break;
      case ConstraintStatus.approved:
        backgroundColor = Colors.green;
        textColor = Colors.white;
        text = 'אושר';
        break;
      case ConstraintStatus.rejected:
        backgroundColor = Colors.red;
        textColor = Colors.white;
        text = 'נדחה';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAvailabilityCard(DateConstraint availability) {
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_available,
                  color: Colors.green[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    availability.endDate != null && !_isSameDay(availability.startDate, availability.endDate!)
                        ? '${_formatDate(availability.startDate)} - ${_formatDate(availability.endDate!)}'
                        : _formatDate(availability.startDate),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                // Edit and delete buttons for availability
                IconButton(
                  icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                  onPressed: () => _editConstraintOrAvailability(availability),
                  tooltip: 'ערוך',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  onPressed: () => _deleteConstraintOrAvailability(availability),
                  tooltip: 'מחק',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            if (availability.startTime != null || availability.endTime != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.green[600]),
                  const SizedBox(width: 4),
                  Text(
                    'שעות: ${availability.startTime ?? '---'} - ${availability.endTime ?? '---'}',
                    style: TextStyle(fontSize: 12, color: Colors.green[600]),
                  ),
                ],
              ),
            ],
            if (availability.note != null && availability.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.note,
                      size: 16,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        availability.note!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _approveConstraint(String constraintId) {
    if (widget.member == null) return;

    // Find and update the constraint directly in the constraints list
    final constraintIndex = _constraints.indexWhere((c) => c.id == constraintId);
    if (constraintIndex != -1) {
      _constraints[constraintIndex] = _constraints[constraintIndex].copyWith(
        status: ConstraintStatus.approved,
        wasAutoRejectedFromCalendar: false, // Reset auto-rejection flag when approved
      );
      _isDirty = true;
      setState(() {});
    }
  }

  void _rejectConstraint(String constraintId) {
    if (widget.member == null) return;

    // Find and update the constraint directly in the constraints list
    final constraintIndex = _constraints.indexWhere((c) => c.id == constraintId);
    if (constraintIndex != -1) {
      _constraints[constraintIndex] = _constraints[constraintIndex].copyWith(
        status: ConstraintStatus.rejected,
        // Note: Don't reset wasAutoRejectedFromCalendar here - manual rejection is different
      );
      _isDirty = true;
      setState(() {});
    }
  }

  void _setPendingConstraint(String constraintId) {
    if (widget.member == null) return;

    // Find and update the constraint directly in the constraints list
    final constraintIndex = _constraints.indexWhere((c) => c.id == constraintId);
    if (constraintIndex != -1) {
      _constraints[constraintIndex] = _constraints[constraintIndex].copyWith(
        status: ConstraintStatus.pending,
        wasAutoRejectedFromCalendar: false, // Reset auto-rejection flag when set to pending
      );
      _isDirty = true;
      setState(() {});
    }
  }

  List<Widget> _buildVisibleConstraintsList() {
    final visibleConstraints = _constraints.where((constraint) {
      // Filter by constraint type based on permanent status
      if (_isPermanent && constraint.isAvailability) return false; // Permanent members only see unavailability
      if (!_isPermanent && constraint.isUnavailability) return false; // Non-permanent members only see availability

      // Hide rejected constraints from admin view (they'll have a separate button)
      if (constraint.status == ConstraintStatus.rejected) return false;

      // Filter out past constraints (endDate < today) from admin view
      // These constraints don't need admin inspection
      if (constraint.endDate != null) {
        final today = DateTime.now();
        final constraintEndDate = DateTime(
          constraint.endDate!.year,
          constraint.endDate!.month,
          constraint.endDate!.day,
        );
        final todayDate = DateTime(
          today.year,
          today.month,
          today.day,
        );
        if (constraintEndDate.isBefore(todayDate)) {
          return false;
        }
      } else {
        // For single-day constraints (no endDate), check if startDate is before today
        final today = DateTime.now();
        final constraintStartDate = DateTime(
          constraint.startDate.year,
          constraint.startDate.month,
          constraint.startDate.day,
        );
        final todayDate = DateTime(
          today.year,
          today.month,
          today.day,
        );
        if (constraintStartDate.isBefore(todayDate)) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final widgets = <Widget>[];

    // Show "no constraints" message if there are no visible (approved/pending) constraints
    // Even if there are rejected constraints, we show this message
    if (visibleConstraints.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _isPermanent ? 'אין מגבלות זמן' : 'אין זמינות',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      // Add visible constraints
      widgets.addAll(visibleConstraints.map((constraint) {
        return _buildConstraintCard(constraint);
      }).toList());
    }

    return widgets;
  }

  /// Open the availability events editor modal
  void _editAvailabilityEvents() async {
    final eventState = context.read<EventBloc>().state;
    if (eventState is! EventsLoaded) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final futureEvents = eventState.events.where((event) {
      final eventEndDate = DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
      return !eventEndDate.isBefore(today);
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _AdminAvailabilityDialog(
        events: futureEvents,
        initialSelectedEventIds: _availableEventIds,
      ),
    );

    if (result != null) {
      setState(() {
        _availableEventIds = result;
        _isDirty = true;
      });
    }
  }

  /// Format event date range in Hebrew
  String _formatEventDates(Event event) {
    final isSameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    if (isSameDay) {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)}';
    } else {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)} - יום ${_getFullHebrewDayName(event.endDate.weekday)} ${event.endDate.day} ב${_getHebrewMonthName(event.endDate.month)}';
    }
  }

  String _formatEventTimes(Event event) {
    final parts = <String>[];
    if (event.assemblyTime.isNotEmpty) {
      parts.add('התייצבות - ${event.assemblyTime}');
    }
    if (event.startTime.isNotEmpty) {
      parts.add('התכנסות - ${event.startTime}');
    }
    if (event.actualShowStartTime.isNotEmpty) {
      parts.add('תחילת מופע - ${event.actualShowStartTime}');
    }
    if (event.endTime.isNotEmpty) {
      parts.add('סיום - ${event.endTime}');
    }
    return parts.join(' | ');
  }

  String _getFullHebrewDayName(int weekday) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    return days[weekday];
  }

  String _getHebrewMonthName(int month) {
    const months = [
      '', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return months[month];
  }

  /// Format location for display - remove coordinates
  String _formatLocationForDisplay(String location) {
    if (location.contains('||')) {
      final parts = location.split('||');
      final strippedLocation = parts[0].trim();
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }

  void _showRejectedConstraints(List<DateConstraint> rejectedConstraints) {
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: _RejectedConstraintsDialog(
          teamMemberId: widget.member!.id,
          getEffectiveConstraints: () => _constraints,
          onApproveConstraint: (constraintId) => _approveConstraint(constraintId),
          onRejectConstraint: (constraintId) => _rejectConstraint(constraintId),
          onSetPendingConstraint: (constraintId) => _setPendingConstraint(constraintId),
          onDeleteConstraint: (constraintId) {
            setState(() {
              _constraints.removeWhere((c) => c.id == constraintId);
              _isDirty = true;
            });
          },
          onEditConstraint: (constraintId, updatedConstraint) {
            final index = _constraints.indexWhere((c) => c.id == constraintId);
            if (index != -1) {
              setState(() {
                _constraints[index] = updatedConstraint;
                _isDirty = true;
              });
            }
          },
        ),
      ),
    );
  }

  void _showBirthdayPickerDialog() async {
    final result = await showDialog<Map<String, int?>>(
      context: context,
      builder: (dialogContext) => _BirthdayPickerDialog(
        initialDay: _birthdayDay,
        initialMonth: _birthdayMonth,
        initialYear: _birthdayYear,
        maxYear: _maxBirthdayYear,
        minYear: _minBirthdayYear,
        hebrewMonths: _hebrewMonths,
      ),
    );

    if (result != null) {
      setState(() {
        _birthdayDay = result['day'];
        _birthdayMonth = result['month'];
        _birthdayYear = result['year'];
        _isDirty = true;
        _updateBirthdayController();
      });
    }
  }

  void _showVehicleInfoDialog() async {
    final result = await showDialog<VehicleInfo?>(
      context: context,
      builder: (dialogContext) => _VehicleInfoDialog(
        initialVehicleInfo: _vehicleInfo,
      ),
    );

    if (result != null || (result == null && _vehicleInfo != null)) {
      setState(() {
        _vehicleInfo = result;
        _isDirty = true;
        _updateVehicleInfoController();
      });
    }
  }

  /// Add a new constraint or availability for admin
  void _addConstraintOrAvailability() async {
    final result = await showDialog<DateConstraint>(
      context: context,
      builder: (context) => _AdminConstraintDialog(
        isPermanent: _isPermanent,
      ),
    );

    if (result != null) {
      setState(() {
        _constraints.add(result);
        _isDirty = true;
      });
    }
  }

  /// Edit an existing constraint or availability for admin
  void _editConstraintOrAvailability(DateConstraint constraint) async {
    final result = await showDialog<DateConstraint>(
      context: context,
      builder: (context) => _AdminConstraintDialog(
        constraint: constraint,
        isPermanent: _isPermanent,
      ),
    );

    if (result != null) {
      final index = _constraints.indexWhere((c) => c.id == constraint.id);
      if (index != -1) {
        setState(() {
          _constraints[index] = result;
          _isDirty = true;
        });
      }
    }
  }

  /// Delete a constraint or availability for admin
  void _deleteConstraintOrAvailability(DateConstraint constraint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(_isPermanent ? 'מחיקת מגבלה' : 'מחיקת זמינות'),
          content: Text(_isPermanent
              ? 'האם את/ה בטוח/ה שברצונך למחוק את המגבלה הזו?'
              : 'האם את/ה בטוח/ה שברצונך למחוק זמינות זו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        _constraints.removeWhere((c) => c.id == constraint.id);
        _isDirty = true;
      });
    }
  }
}

// Constraint Dialog Widget
class _ConstraintDialog extends StatefulWidget {
  final DateConstraint? constraint;

  const _ConstraintDialog({this.constraint});

  @override
  State<_ConstraintDialog> createState() => _ConstraintDialogState();
}

class _ConstraintDialogState extends State<_ConstraintDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _noteController = TextEditingController();
  late final FocusNode _noteFocusNode;

  @override
  void initState() {
    super.initState();
    _noteFocusNode = createRtlCursorFixedFocusNode(_noteController);
    if (widget.constraint != null) {
      _startDate = widget.constraint!.startDate;
      _endDate = widget.constraint!.endDate;
      _noteController.text = widget.constraint!.note ?? '';
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: _startDate,
        initialEndDate: _endDate,
        title: 'בחר תאריכי מגבלה',
      ),
    );

    if (result != null) {
      final selectedStartDate = result['startDate'];
      final selectedEndDate = result['endDate'];

      // Check if only start date was selected
      if (selectedStartDate != null && selectedEndDate == null) {
        // Show confirmation dialog for single-day constraint
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('אישור מגבלה ליום בודד'),
              content: Text(
                'האם זו מגבלה ליום בודד (${_formatDate(selectedStartDate!)})?',
              ),
              actions: [
                TextButton(
                  child: const Text('ביטול'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                ElevatedButton(
                  child: const Text('כן, מגבלה ליום בודד'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ),
        );

        if (confirmed == true) {
          setState(() {
            _startDate = selectedStartDate;
            _endDate = null; // Single day constraint
          });
        }
      } else if (selectedStartDate != null && selectedEndDate != null) {
        // Check if start and end dates are the same
        final isSameDate = selectedStartDate.year == selectedEndDate.year &&
            selectedStartDate.month == selectedEndDate.month &&
            selectedStartDate.day == selectedEndDate.day;

        setState(() {
          _startDate = selectedStartDate;
          // Automatically convert to single day if same date selected
          _endDate = isSameDate ? null : selectedEndDate;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.constraint == null ? 'הוספת מגבלה' : 'עריכת מגבלה'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Date selection button
            OutlinedButton.icon(
              onPressed: _pickDates,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _startDate == null
                    ? 'בחר תאריכים'
                    : _endDate != null
                        ? '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}'
                        : _formatDate(_startDate!),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerRight,
              ),
            ),

            if (_startDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _startDate = null;
                    _endDate = null;
                  }),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('נקה'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ),

            // Note text field
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              focusNode: _noteFocusNode,
              decoration: const InputDecoration(
                labelText: 'הערה',
                hintText: 'הוסף הערה למגבלה',
                prefixIcon: Icon(Icons.note),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              minLines: 1,
              textDirection: TextDirection.rtl,
              textAlignVertical: TextAlignVertical.center,
            ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: _startDate == null
                ? null
                : () {
                    final noteText = _noteController.text.trim();
                    Navigator.pop(
                      context,
                      DateConstraint(
                        id: widget.constraint?.id ?? const Uuid().v4(), // Use existing ID or generate new one
                        startDate: _startDate!,
                        endDate: _endDate,
                        note: noteText.isEmpty ? null : noteText,
                        status: widget.constraint?.status ?? ConstraintStatus.approved, // Use existing status or default to approved
                        constraintType: widget.constraint?.constraintType ?? ConstraintType.unavailability, // Use existing type or default to unavailability
                      ),
                    );
                  },
            child: Text(widget.constraint == null ? 'הוספה' : 'שמור'),
          ),
        ],
      ),
    );
  }
}

// Admin Constraint/Availability Dialog Widget
class _AdminConstraintDialog extends StatefulWidget {
  final DateConstraint? constraint;
  final bool isPermanent; // true = constraint (permanent member), false = availability (non-permanent)

  const _AdminConstraintDialog({
    this.constraint,
    required this.isPermanent,
  });

  @override
  State<_AdminConstraintDialog> createState() => _AdminConstraintDialogState();
}

class _AdminConstraintDialogState extends State<_AdminConstraintDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();
  late final FocusNode _noteFocusNode;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _noteFocusNode = createRtlCursorFixedFocusNode(_noteController);
    if (widget.constraint != null) {
      _startDate = widget.constraint!.startDate;
      _endDate = widget.constraint!.endDate;
      _noteController.text = widget.constraint!.note ?? '';
      _startTimeController.text = widget.constraint!.startTime ?? '';
      _endTimeController.text = widget.constraint!.endTime ?? '';
    }
    _noteController.addListener(_updateCanSubmit);
    _startTimeController.addListener(_updateCanSubmit);
    _endTimeController.addListener(_updateCanSubmit);
  }

  @override
  void dispose() {
    _noteController.removeListener(_updateCanSubmit);
    _noteController.dispose();
    _noteFocusNode.dispose();
    _startTimeController.removeListener(_updateCanSubmit);
    _startTimeController.dispose();
    _endTimeController.removeListener(_updateCanSubmit);
    _endTimeController.dispose();
    super.dispose();
  }

  void _updateCanSubmit() {
    setState(() {
      // For permanent members (constraints), note is required
      // For non-permanent members (availability), note is optional
      bool dateValid;
      if (widget.isPermanent) {
        dateValid = _startDate != null && _noteController.text.trim().isNotEmpty;
      } else {
        dateValid = _startDate != null;
      }

      // Validate time range:
      // - If one time is set, the other must be set too
      // - If both are set, start must be before end
      bool timeValid = true;
      final hasStart = _startTimeController.text.isNotEmpty;
      final hasEnd = _endTimeController.text.isNotEmpty;
      if (hasStart != hasEnd) {
        timeValid = false; // One set but not the other
      } else if (hasStart && hasEnd) {
        timeValid = TimeRangeUtils.isValidTimeRange(
          _startTimeController.text,
          _endTimeController.text,
        );
      }

      _canSubmit = dateValid && timeValid;
    });
  }

  /// Show time picker (Cupertino style)
  Future<void> _showTimePickerFor(TextEditingController controller) async {
    final now = DateTime.now();
    DateTime initialTime = now;
    if (controller.text.isNotEmpty) {
      final parts = controller.text.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          initialTime = DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
    }

    DateTime selectedTime = initialTime;

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 280,
          height: 220,
          child: Column(
            children: [
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initialTime,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime newTime) {
                    selectedTime = newTime;
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      child: const Text('ביטול'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      child: const Text('אישור'),
                      onPressed: () => Navigator.of(context).pop(selectedTime),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      setState(() {
        controller.text = '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _pickDates() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: _startDate,
        initialEndDate: _endDate,
        title: widget.isPermanent ? 'בחר תאריכי מגבלה' : 'בחר תאריכי זמינות',
        minDate: todayDate, // Prevent selecting dates before today
      ),
    );

    if (result != null) {
      final selectedStartDate = result['startDate'];
      final selectedEndDate = result['endDate'];

      setState(() {
        _startDate = selectedStartDate;
        // If only start date selected, set end date to start date (single day)
        _endDate = selectedEndDate ?? selectedStartDate;
      });
      _updateCanSubmit();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          widget.constraint == null
              ? (widget.isPermanent ? 'הוספת מגבלה' : 'הוספת זמינות')
              : (widget.isPermanent ? 'עריכת מגבלה' : 'עריכת זמינות'),
          textAlign: TextAlign.right,
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('תאריכים:'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDates,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 8),
                      Text(
                        _startDate != null
                            ? (_endDate != null && !_isSameDay(_startDate!, _endDate!)
                                ? '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}'
                                : _formatDate(_startDate!))
                            : 'בחר תאריכים',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('טווח שעות (אופציונלי):'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startTimeController,
                      readOnly: true,
                      onTap: () => _showTimePickerFor(_startTimeController),
                      decoration: InputDecoration(
                        labelText: 'שעת התחלה',
                        hintText: 'לדוגמה: 09:00',
                        prefixIcon: const Icon(Icons.access_time),
                        border: const OutlineInputBorder(),
                        suffixIcon: _startTimeController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    _startTimeController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _endTimeController,
                      readOnly: true,
                      onTap: () => _showTimePickerFor(_endTimeController),
                      decoration: InputDecoration(
                        labelText: 'שעת סיום',
                        hintText: 'לדוגמה: 17:00',
                        prefixIcon: const Icon(Icons.access_time),
                        border: const OutlineInputBorder(),
                        suffixIcon: _endTimeController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    _endTimeController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              // Validation warnings
              if (_startTimeController.text.isNotEmpty != _endTimeController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'יש להזין גם שעת התחלה וגם שעת סיום',
                    style: TextStyle(color: Colors.red[700], fontSize: 12),
                  ),
                ),
              if (_startTimeController.text.isNotEmpty &&
                  _endTimeController.text.isNotEmpty &&
                  !TimeRangeUtils.isValidTimeRange(
                    _startTimeController.text,
                    _endTimeController.text,
                  ))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'שעת סיום חייבת להיות אחרי שעת התחלה',
                    style: TextStyle(color: Colors.red[700], fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                widget.isPermanent ? 'סיבה (חובה):' : 'הערה (אופציונלי):',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                focusNode: _noteFocusNode,
                textAlign: TextAlign.right,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: widget.isPermanent
                      ? 'יש להזין סיבה למגבלה...'
                      : 'פרטים נוספים על הזמינות...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  hintTextDirection: TextDirection.rtl,
                ),
                maxLines: 3,
                minLines: 3,
                style: const TextStyle(height: 1.5),
                scrollPhysics: const BouncingScrollPhysics(),
              ),
            ],
          ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _canSubmit
                ? () {
                    final noteText = _noteController.text.trim();
                    final startTime = _startTimeController.text.isNotEmpty
                        ? _startTimeController.text
                        : null;
                    final endTime = _endTimeController.text.isNotEmpty
                        ? _endTimeController.text
                        : null;
                    Navigator.of(context).pop(
                      DateConstraint(
                        id: widget.constraint?.id ?? const Uuid().v4(),
                        startDate: _startDate!,
                        endDate: _endDate != null && !_isSameDay(_startDate!, _endDate!) ? _endDate : null,
                        note: noteText.isEmpty ? null : noteText,
                        status: ConstraintStatus.approved, // Admin creates are always auto-approved
                        constraintType: widget.isPermanent
                            ? ConstraintType.unavailability
                            : ConstraintType.availability,
                        wasAutoRejectedFromCalendar: false,
                        startTime: startTime,
                        endTime: endTime,
                      ),
                    );
                  }
                : null,
            child: Text(widget.constraint == null ? 'הוספה' : 'שמור שינויים'),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

// Admin dialog for editing event-based availability of a non-permanent member
class _AdminAvailabilityDialog extends StatefulWidget {
  final List<Event> events;
  final List<String> initialSelectedEventIds;

  const _AdminAvailabilityDialog({
    super.key,
    required this.events,
    required this.initialSelectedEventIds,
  });

  @override
  State<_AdminAvailabilityDialog> createState() => _AdminAvailabilityDialogState();
}

class _AdminAvailabilityDialogState extends State<_AdminAvailabilityDialog> {
  late Set<String> _selectedEventIds;

  @override
  void initState() {
    super.initState();
    _selectedEventIds = Set.from(widget.initialSelectedEventIds);
  }

  void _toggleEvent(String eventId) {
    setState(() {
      if (_selectedEventIds.contains(eventId)) {
        _selectedEventIds.remove(eventId);
      } else {
        _selectedEventIds.add(eventId);
      }
    });
  }

  /// Group events by month
  Map<String, List<Event>> _groupEventsByMonth(List<Event> events) {
    final grouped = <String, List<Event>>{};
    for (final event in events) {
      final monthKey = _getHebrewMonthYear(event.startDate);
      grouped.putIfAbsent(monthKey, () => []).add(event);
    }
    return grouped;
  }

  String _getHebrewMonthYear(DateTime date) {
    const months = [
      '', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return '${months[date.month]} ${date.year}';
  }

  String _formatEventDates(Event event) {
    final isSameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    if (isSameDay) {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)}';
    } else {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)} - יום ${_getFullHebrewDayName(event.endDate.weekday)} ${event.endDate.day} ב${_getHebrewMonthName(event.endDate.month)}';
    }
  }

  String _formatEventTimes(Event event) {
    final parts = <String>[];
    if (event.assemblyTime.isNotEmpty) {
      parts.add('התייצבות - ${event.assemblyTime}');
    }
    if (event.startTime.isNotEmpty) {
      parts.add('התכנסות - ${event.startTime}');
    }
    if (event.actualShowStartTime.isNotEmpty) {
      parts.add('תחילת מופע - ${event.actualShowStartTime}');
    }
    if (event.endTime.isNotEmpty) {
      parts.add('סיום - ${event.endTime}');
    }
    return parts.join(' | ');
  }

  String _getFullHebrewDayName(int weekday) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    return days[weekday];
  }

  String _getHebrewMonthName(int month) {
    const months = [
      '', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return months[month];
  }

  String _formatLocationForDisplay(String location) {
    if (location.contains('||')) {
      final parts = location.split('||');
      final strippedLocation = parts[0].trim();
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }

  @override
  Widget build(BuildContext context) {
    final groupedEvents = _groupEventsByMonth(widget.events);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 500,
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ערוך זמינות לאירועים',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'סמן/ה את האירועים שחבר הצוות זמין/ה להתנדב אליהם',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Events list
            Expanded(
              child: widget.events.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'אין אירועים עתידיים',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: groupedEvents.length,
                      itemBuilder: (context, index) {
                        final monthYear = groupedEvents.keys.elementAt(index);
                        final events = groupedEvents[monthYear]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Month header
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                monthYear,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Event checkboxes
                            ...events.map((event) {
                              final isSelected = _selectedEventIds.contains(event.id);
                              final formattedLocation = event.location.isNotEmpty
                                  ? _formatLocationForDisplay(event.location)
                                  : '';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: isSelected ? Colors.green[50] : Colors.white,
                                child: CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (_) => _toggleEvent(event.id),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: Text(
                                    event.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isSelected ? Colors.green[700] : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatEventDates(event),
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Text(
                                        _formatEventTimes(event),
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: Colors.black,
                                        ),
                                      ),
                                      if (formattedLocation.isNotEmpty)
                                        Text(
                                          'מיקום: $formattedLocation',
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: Colors.black,
                                          ),
                                        ),
                                    ],
                                  ),
                                  activeColor: Colors.green,
                                  checkColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                              );
                            }).toList(),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // Footer buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ביטול'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_selectedEventIds.toList()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('שמור'),
                  ),
                ],
              ),
            ),
          ],
        ),
        ), // SizedBox
      ),
    );
  }
}

// Separate widget for rejected constraints dialog to avoid infinite loop
class _RejectedConstraintsDialog extends StatefulWidget {
  final String teamMemberId;
  final List<DateConstraint> Function() getEffectiveConstraints;
  final Function(String) onApproveConstraint;
  final Function(String) onRejectConstraint;
  final Function(String) onSetPendingConstraint;
  final Function(String) onDeleteConstraint;
  final Function(String, DateConstraint) onEditConstraint;

  const _RejectedConstraintsDialog({
    required this.teamMemberId,
    required this.getEffectiveConstraints,
    required this.onApproveConstraint,
    required this.onRejectConstraint,
    required this.onSetPendingConstraint,
    required this.onDeleteConstraint,
    required this.onEditConstraint,
  });

  @override
  State<_RejectedConstraintsDialog> createState() => _RejectedConstraintsDialogState();
}

class _RejectedConstraintsDialogState extends State<_RejectedConstraintsDialog> {
  bool _isLoading = false;


  @override
  Widget build(BuildContext context) {
    return BlocListener<TeamBloc, TeamState>(
      listener: (context, state) {
        // Trigger rebuild when BLoC state changes to refresh dialog content
        setState(() {});
      },
      child: AlertDialog(
        title: Text(
          'מגבלות שנדחו (${_getRejectedConstraints().length})',
          textAlign: TextAlign.right,
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            children: [
              Text(
                'כאן תוכל לשנות את הסטטוס של מגבלות שנדחו בעבר:',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              if (_getRejectedConstraints().isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('אין מגבלות שנדחו'),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _getRejectedConstraints().length,
                    itemBuilder: (context, index) {
                      final constraint = _getRejectedConstraints()[index];

                      // The constraint already has the effective status from LocalConstraintManager
                      final effectiveStatus = constraint.status;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    effectiveStatus == ConstraintStatus.pending ? Icons.hourglass_empty :
                                    effectiveStatus == ConstraintStatus.approved ? Icons.check_circle : Icons.cancel,
                                    color: effectiveStatus == ConstraintStatus.pending ? Colors.amber :
                                           effectiveStatus == ConstraintStatus.approved ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      constraint.toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  _buildStatusBadge(effectiveStatus),
                                ],
                              ),
                              // Note
                              if (constraint.note != null && constraint.note!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  constraint.note!,
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              // Auto-rejection message in red if applicable
                              if (constraint.wasAutoRejectedFromCalendar) ...[
                                const SizedBox(height: 4),
                                Text(
                                  CalendarAutoRejection.message,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Right button (first in RTL)
                                  if (effectiveStatus == ConstraintStatus.pending)
                                    // Pending: Right = Accept
                                    TextButton.icon(
                                      onPressed: () => _approveConstraint(constraint.id),
                                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                      label: const Text('אשר', style: TextStyle(color: Colors.green)),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.green[50],
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                    )
                                  else if (effectiveStatus == ConstraintStatus.approved)
                                    // Approved: Right = Pending
                                    TextButton.icon(
                                      onPressed: () => _setPendingConstraint(constraint.id),
                                      icon: const Icon(Icons.hourglass_empty, color: Colors.amber, size: 18),
                                      label: const Text('החזר לממתין', style: TextStyle(color: Colors.amber)),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.amber[50],
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                    )
                                  else // Rejected: Right = Pending
                                    TextButton.icon(
                                      onPressed: () => _setPendingConstraint(constraint.id),
                                      icon: const Icon(Icons.hourglass_empty, color: Colors.amber, size: 18),
                                      label: const Text('החזר לממתין', style: TextStyle(color: Colors.amber)),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.amber[50],
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                    ),

                                  const SizedBox(width: 8), // Consistent spacing

                                  // Left button (last in RTL)
                                  if (effectiveStatus == ConstraintStatus.pending)
                                    // Pending: Left = Reject
                                    TextButton.icon(
                                      onPressed: () => _rejectConstraint(constraint.id),
                                      icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                      label: const Text('דחה', style: TextStyle(color: Colors.red)),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.red[50],
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                    )
                                  else if (effectiveStatus == ConstraintStatus.approved)
                                    // Approved: Left = Reject
                                    TextButton.icon(
                                      onPressed: () => _rejectConstraint(constraint.id),
                                      icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                                      label: const Text('דחה', style: TextStyle(color: Colors.red)),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.red[50],
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                    )
                                  else // Rejected: Left = Accept
                                    TextButton.icon(
                                      onPressed: () => _approveConstraint(constraint.id),
                                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                      label: const Text('אשר', style: TextStyle(color: Colors.green)),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.green[50],
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                    ),

                                  const Spacer(),

                                  // Edit button
                                  IconButton(
                                    onPressed: () => _editConstraint(constraint),
                                    icon: const Icon(Icons.edit, size: 18),
                                    color: Colors.blue,
                                    tooltip: 'ערוך',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                  ),

                                  const SizedBox(width: 4),

                                  // Delete button
                                  IconButton(
                                    onPressed: () => _deleteConstraint(constraint),
                                    icon: const Icon(Icons.delete, size: 18),
                                    color: Colors.red,
                                    tooltip: 'מחק',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
    );
  }

  List<DateConstraint> _getRejectedConstraints() {
    // Use the parent's LocalConstraintManager to get effective constraints
    final effectiveConstraints = widget.getEffectiveConstraints();

    // Filter for rejected constraints
    return effectiveConstraints.where((constraint) {
      return constraint.status == ConstraintStatus.rejected;
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  void _approveConstraint(String constraintId) {
    // Call parent callback to update LocalConstraintManager
    widget.onApproveConstraint(constraintId);
    setState(() {}); // Refresh dialog
  }

  void _rejectConstraint(String constraintId) {
    // Call parent callback to update LocalConstraintManager
    widget.onRejectConstraint(constraintId);
    setState(() {}); // Refresh dialog
  }

  void _setPendingConstraint(String constraintId) {
    // Call parent callback to update LocalConstraintManager
    widget.onSetPendingConstraint(constraintId);
    setState(() {}); // Refresh dialog
  }

  void _deleteConstraint(DateConstraint constraint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת מגבלה'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק את המגבלה הזו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      widget.onDeleteConstraint(constraint.id);
      setState(() {}); // Refresh dialog
    }
  }

  void _editConstraint(DateConstraint constraint) async {
    final result = await showDialog<DateConstraint>(
      context: context,
      builder: (context) => _AdminConstraintDialog(
        constraint: constraint,
        isPermanent: true, // Rejected constraints dialog is for permanent members only
      ),
    );

    if (result != null) {
      // Preserve the original rejected status - do NOT auto-move to pending/approved
      final updatedConstraint = result.copyWith(
        status: constraint.status,
      );
      widget.onEditConstraint(constraint.id, updatedConstraint);
      setState(() {}); // Refresh dialog
    }
  }

  Widget _buildStatusBadge(ConstraintStatus status) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case ConstraintStatus.pending:
        backgroundColor = Colors.orange;
        textColor = Colors.white;
        text = 'ממתין';
        break;
      case ConstraintStatus.approved:
        backgroundColor = Colors.green;
        textColor = Colors.white;
        text = 'אושר';
        break;
      case ConstraintStatus.rejected:
        backgroundColor = Colors.red;
        textColor = Colors.white;
        text = 'נדחה';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

// Birthday Picker Dialog Widget
class _BirthdayPickerDialog extends StatefulWidget {
  final int? initialDay;
  final int? initialMonth;
  final int? initialYear;
  final int maxYear;
  final int minYear;
  final List<String> hebrewMonths;

  const _BirthdayPickerDialog({
    required this.initialDay,
    required this.initialMonth,
    required this.initialYear,
    required this.maxYear,
    required this.minYear,
    required this.hebrewMonths,
  });

  @override
  State<_BirthdayPickerDialog> createState() => _BirthdayPickerDialogState();
}

class _BirthdayPickerDialogState extends State<_BirthdayPickerDialog> {
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;
  bool _isDirty = false;
  bool _showValidationErrors = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay;
    _selectedMonth = widget.initialMonth;
    _selectedYear = widget.initialYear;
  }

  int _getDaysInMonth(int? month, int? year) {
    if (month == null) return 31;
    final y = year ?? 2000; // Use leap year if year not selected
    return DateTime(y, month + 1, 0).day;
  }

  /// Returns true if there's a partial selection (some fields filled, some not)
  bool get _hasPartialSelection {
    final filledCount = [_selectedDay, _selectedMonth, _selectedYear]
        .where((v) => v != null)
        .length;
    return filledCount > 0 && filledCount < 3;
  }

  /// Returns true if this specific field should show an error
  bool _fieldHasError(int? fieldValue) {
    return _showValidationErrors && _hasPartialSelection && fieldValue == null;
  }

  /// Builds InputDecoration with proper error styling
  InputDecoration _buildFieldDecoration(String label, int? fieldValue) {
    final hasError = _fieldHasError(fieldValue);
    return InputDecoration(
      labelText: label,
      labelStyle: hasError ? const TextStyle(color: Colors.red) : null,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: hasError ? Colors.red : Colors.grey,
          width: hasError ? 2 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: hasError ? Colors.red : Colors.blue,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = _getDaysInMonth(_selectedMonth, _selectedYear);

    // Adjust day if it exceeds days in selected month
    if (_selectedDay != null && _selectedDay! > daysInMonth) {
      _selectedDay = daysInMonth;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cake, color: Colors.pink),
            const SizedBox(width: 8),
            const Text('בחירת תאריך לידה'),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Day dropdown
              DropdownButtonFormField<int>(
                value: _selectedDay,
                decoration: _buildFieldDecoration('יום', _selectedDay),
                items: List.generate(daysInMonth, (index) {
                  final day = index + 1;
                  return DropdownMenuItem(
                    value: day,
                    child: Text(day.toString()),
                  );
                }),
                onChanged: (value) {
                  setState(() {
                    _selectedDay = value;
                    _isDirty = true;
                  });
                },
              ),
              const SizedBox(height: 12),
              // Month dropdown
              DropdownButtonFormField<int>(
                value: _selectedMonth,
                decoration: _buildFieldDecoration('חודש', _selectedMonth),
                items: List.generate(12, (index) {
                  final month = index + 1;
                  return DropdownMenuItem(
                    value: month,
                    child: Text(widget.hebrewMonths[index]),
                  );
                }),
                onChanged: (value) {
                  setState(() {
                    _selectedMonth = value;
                    _isDirty = true;
                  });
                },
              ),
              const SizedBox(height: 12),
              // Year dropdown
              DropdownButtonFormField<int>(
                value: _selectedYear,
                decoration: _buildFieldDecoration('שנה', _selectedYear),
                items: List.generate(widget.maxYear - widget.minYear + 1, (index) {
                  final year = widget.maxYear - index;
                  return DropdownMenuItem(
                    value: year,
                    child: Text(year.toString()),
                  );
                }),
                onChanged: (value) {
                  setState(() {
                    _selectedYear = value;
                    _isDirty = true;
                  });
                },
              ),
              if (_showValidationErrors && _hasPartialSelection) ...[
                const SizedBox(height: 8),
                const Text(
                  'יש למלא את כל השדות',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              if (_selectedDay != null || _selectedMonth != null || _selectedYear != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedDay = null;
                      _selectedMonth = null;
                      _selectedYear = null;
                      _isDirty = true;
                      _showValidationErrors = false;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                  label: const Text('נקה תאריך', style: TextStyle(color: Colors.red)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _isDirty ? () {
              // Validate: either all fields filled or all empty
              if (_hasPartialSelection) {
                setState(() {
                  _showValidationErrors = true;
                });
                return;
              }
              Navigator.of(context).pop({
                'day': _selectedDay,
                'month': _selectedMonth,
                'year': _selectedYear,
              });
            } : null,
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }
}

/// Dialog for editing vehicle information in team member form
class _VehicleInfoDialog extends StatefulWidget {
  final VehicleInfo? initialVehicleInfo;

  const _VehicleInfoDialog({
    required this.initialVehicleInfo,
  });

  @override
  State<_VehicleInfoDialog> createState() => _VehicleInfoDialogState();
}

class _VehicleInfoDialogState extends State<_VehicleInfoDialog> {
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  late final FocusNode _modelFocusNode;
  late final FocusNode _colorFocusNode;
  String? _selectedManufacturer;
  bool _isDirty = false;

  // Error states
  bool _showValidationErrors = false;
  String? _vehicleNumberError;

  @override
  void initState() {
    super.initState();
    _modelFocusNode = createRtlCursorFixedFocusNode(_modelController);
    _colorFocusNode = createRtlCursorFixedFocusNode(_colorController);
    // Initialize real-time updates
    UtilitiesService.instance.initialize();
    _initializeFields();
  }

  void _initializeFields() {
    if (widget.initialVehicleInfo != null && widget.initialVehicleInfo!.isComplete) {
      _vehicleNumberController.text = widget.initialVehicleInfo!.vehicleNumber;
      _selectedManufacturer = widget.initialVehicleInfo!.manufacturer;
      _modelController.text = widget.initialVehicleInfo!.model;
      _colorController.text = widget.initialVehicleInfo!.color;
    }
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    _colorController.dispose();
    _modelController.dispose();
    _modelFocusNode.dispose();
    _colorFocusNode.dispose();
    super.dispose();
  }

  bool get _hasPartialSelection {
    final filledCount = [
      _vehicleNumberController.text.isNotEmpty,
      _selectedManufacturer != null && _selectedManufacturer!.isNotEmpty,
      _modelController.text.isNotEmpty,
      _colorController.text.isNotEmpty,
    ].where((v) => v).length;
    return filledCount > 0 && filledCount < 4;
  }

  bool get _isVehicleNumberValid {
    final number = _vehicleNumberController.text.trim();
    return VehicleInfo.isValidVehicleNumber(number);
  }

  VehicleInfo? _getVehicleInfo() {
    final number = _vehicleNumberController.text.trim();
    final manufacturer = _selectedManufacturer;
    final model = _modelController.text.trim();
    final color = _colorController.text.trim();

    // If all empty, return null (clear vehicle info)
    if (number.isEmpty && (manufacturer == null || manufacturer.isEmpty) &&
        model.isEmpty && color.isEmpty) {
      return null;
    }

    // All fields must be filled
    if (number.isEmpty || manufacturer == null || manufacturer.isEmpty ||
        model.isEmpty || color.isEmpty) {
      return null;
    }

    // Validate vehicle number
    if (!_isVehicleNumberValid) {
      return null;
    }

    return VehicleInfo(
      vehicleNumber: number,
      manufacturer: manufacturer,
      model: model,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.directions_car, color: Colors.blue),
            SizedBox(width: 8),
            Text('פרטי רכב'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'מלא את פרטי הרכב',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              // Vehicle number field
              TextField(
                controller: _vehicleNumberController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  labelText: 'מספר רכב',
                  hintText: '7-8 ספרות',
                  prefixIcon: const Icon(Icons.numbers),
                  errorText: _showValidationErrors && _vehicleNumberError != null
                      ? _vehicleNumberError
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _isDirty = true;
                    if (_showValidationErrors) {
                      _validateVehicleNumber(value);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              // Manufacturer dropdown - StreamBuilder for real-time updates
              StreamBuilder<List<String>>(
                stream: UtilitiesService.instance.watchCarManufacturers(),
                builder: (context, snapshot) {
                  final manufacturers = snapshot.data ?? [];

                  return DropdownButtonFormField<String>(
                    value: _selectedManufacturer,
                    decoration: const InputDecoration(
                      labelText: 'יצרן',
                      prefixIcon: Icon(Icons.factory),
                      border: OutlineInputBorder(),
                    ),
                    items: manufacturers.map((manufacturer) {
                      return DropdownMenuItem(
                        value: manufacturer,
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Center(
                            child: Text(manufacturer),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedManufacturer = value;
                        _modelController.clear();
                        _isDirty = true;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              // Model field - free text input
              TextField(
                controller: _modelController,
                focusNode: _modelFocusNode,
                decoration: const InputDecoration(
                  labelText: 'דגם',
                  hintText: 'למשל: יונדאי אקונט X, סונטה סדאן',
                  prefixIcon: Icon(Icons.directions_car),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _isDirty = true;
                  });
                },
              ),
              const SizedBox(height: 12),
              // Color field
              TextField(
                controller: _colorController,
                focusNode: _colorFocusNode,
                decoration: const InputDecoration(
                  labelText: 'צבע',
                  hintText: 'למשל: לבן, שחור, כסף',
                  prefixIcon: Icon(Icons.palette),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _isDirty = true;
                  });
                },
              ),
              if (_showValidationErrors && _hasPartialSelection) ...[
                const SizedBox(height: 8),
                const Text(
                  'יש למלא את כל השדות או להשאיר ריק',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        actions: [
          // Center all buttons horizontally
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Clear details button
              if (_vehicleNumberController.text.isNotEmpty ||
                  _selectedManufacturer != null ||
                  _modelController.text.isNotEmpty ||
                  _colorController.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _vehicleNumberController.clear();
                      _selectedManufacturer = null;
                      _modelController.clear();
                      _colorController.clear();
                      _vehicleNumberError = null;
                      _isDirty = true;
                      _showValidationErrors = false;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                  label: const Text('נקה פרטים', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: _isDirty ? _saveVehicleInfo : null,
                child: const Text('שמור'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _validateVehicleNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _vehicleNumberError = null;
    } else if (!VehicleInfo.isValidVehicleNumber(trimmed)) {
      _vehicleNumberError = 'מספר רכב חייב להכיל 7-8 ספרות';
    } else {
      _vehicleNumberError = null;
    }
  }

  void _saveVehicleInfo() {
    // Check if selection is valid before saving
    final vehicleInfo = _getVehicleInfo();

    // Validate partial selection
    if (_hasPartialSelection) {
      setState(() {
        _showValidationErrors = true;
        _validateVehicleNumber(_vehicleNumberController.text);
      });
      return;
    }

    // Validate vehicle number format if provided
    if (_vehicleNumberController.text.isNotEmpty && !_isVehicleNumberValid) {
      setState(() {
        _showValidationErrors = true;
        _validateVehicleNumber(_vehicleNumberController.text);
      });
      return;
    }

    Navigator.of(context).pop(vehicleInfo);
  }
}
