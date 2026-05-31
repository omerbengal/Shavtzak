import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/debug/logger.dart';
import '../../../core/utils/web_url_launcher.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/event_sorting.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';
import '../../../core/constants/role_types.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/role/role_bloc.dart';
import '../../bloc/role/role_state.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/parking_location_picker_dialog.dart';
import '../../widgets/event_team_members_dialog.dart';
import '../event/widgets/event_drive_files_section.dart';

/// Screen for non-admin users to view their event assignments
class UserAssignmentsScreen extends StatefulWidget {
  const UserAssignmentsScreen({super.key});

  @override
  State<UserAssignmentsScreen> createState() => _UserAssignmentsScreenState();
}

class _UserAssignmentsScreenState extends State<UserAssignmentsScreen> {
  // State persistence to prevent transient bloc states from blanking the screen.
  AssignmentState? _lastLoadedState;
  bool _isMutationInFlight = false;
  String _mutationMessage = '';
  bool _isPastSectionExpanded = false;

  @override
  void initState() {
    super.initState();
    // Load assignments for the current user
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserAssignments();
    });
  }

  /// Calculate responsive font size based on screen width
  /// Returns a value between minSize and maxSize, scaled proportionally
  double _getResponsiveFontSize(BuildContext context,
      {double minSize = 14.0, double maxSize = 20.0}) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Map screen width range [320, 768] to font size range [minSize, maxSize]
    final clampedWidth = screenWidth.clamp(320.0, 768.0);
    final scaleFactor = (clampedWidth - 320.0) / (768.0 - 320.0);
    return minSize + (maxSize - minSize) * scaleFactor;
  }

  /// Calculate responsive icon size based on screen width
  /// Returns a value between minSize and maxSize, scaled proportionally
  double _getResponsiveIconSize(BuildContext context,
      {double minSize = 16.0, double maxSize = 24.0}) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Map screen width range [320, 768] to icon size range [minSize, maxSize]
    final clampedWidth = screenWidth.clamp(320.0, 768.0);
    final scaleFactor = (clampedWidth - 320.0) / (768.0 - 320.0);
    return minSize + (maxSize - minSize) * scaleFactor;
  }

  void _loadUserAssignments() {
    final userState = context.read<UserSelectionBloc>().state;
    if (userState is UserAuthenticated) {
      // Use LoadUserAssignments which watches both assignments AND events
      // This ensures real-time updates when event details change or events are deleted
      context.read<AssignmentBloc>().add(
            LoadUserAssignments(userState.user.id),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child:
                  BlocSelector<UserSelectionBloc, UserSelectionState, String?>(
                selector: (state) =>
                    state is UserAuthenticated ? state.user.id : null,
                builder: (context, userId) {
                  if (userId == null) {
                    return const Center(
                      child: Text('אין משתמש מחובר'),
                    );
                  }

                  return BlocConsumer<AssignmentBloc, AssignmentState>(
                    listener: (context, state) {
                      if (state is AssignmentsLoaded ||
                          state is AssignmentsEmpty) {
                        _lastLoadedState = state;
                      }

                      if (state is AssignmentError) {
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
                      }
                    },
                    builder: (context, state) {
                      final displayState = _resolveDisplayState(state);

                      if (state is AssignmentLoading &&
                          _lastLoadedState == null) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (displayState is AssignmentsEmpty) {
                        return _buildEmptyState();
                      }

                      if (displayState is AssignmentsLoaded) {
                        return BlocBuilder<RoleBloc, RoleState>(
                          builder: (context, roleState) {
                            return _buildAssignmentsContent(
                              context,
                              displayState.assignments,
                            );
                          },
                        );
                      }

                      if (displayState is AssignmentError) {
                        return _buildErrorState(displayState.message);
                      }

                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                  );
                },
              ),
            ),
            _buildMutationDialogOverlay(),
          ],
        ),
      ),
    );
  }

  AssignmentState _resolveDisplayState(AssignmentState state) {
    if (_lastLoadedState == null) {
      return state;
    }

    if (state is AssignmentsLoaded || state is AssignmentsEmpty) {
      return state;
    }

    if (state is AssignmentError && _lastLoadedState is AssignmentError) {
      return state;
    }

    if (state is! AssignmentsLoaded && state is! AssignmentsEmpty) {
      return _lastLoadedState!;
    }

    return state;
  }

  Widget _buildAssignmentsContent(
      BuildContext context, List<Assignment> assignments) {
    // Group assignments by event ID to consolidate multiple roles per event
    final Map<String, List<Assignment>> assignmentsByEvent = {};
    for (final assignment in assignments) {
      if (assignment.event == null) continue;
      final eventId = assignment.eventId;
      assignmentsByEvent.putIfAbsent(eventId, () => []);
      assignmentsByEvent[eventId]!.add(assignment);
    }

    // Get role order from RoleBloc
    final roleState = context.read<RoleBloc>().state;
    final roleKeyToSortOrder = <String, int>{};

    if (roleState is RolesLoaded) {
      // Build a map of role key to sortOrder from RoleBloc
      for (final role in roleState.activeRoles) {
        roleKeyToSortOrder[role.key] = role.sortOrder;
      }
    } else {
      // Fallback: use RoleType enum index as sortOrder
      for (final roleType in RoleType.values) {
        roleKeyToSortOrder[roleType.key] = RoleType.values.indexOf(roleType);
      }
    }

    // Convert to list of grouped assignments (using first assignment as representative)
    final groupedAssignments = assignmentsByEvent.entries.map((entry) {
      final eventAssignments = entry.value;
      // Sort roles by sortOrder (from RoleBloc) for consistent display
      eventAssignments.sort((a, b) {
        final aSortOrder = roleKeyToSortOrder[a.roleType] ?? 0;
        final bSortOrder = roleKeyToSortOrder[b.roleType] ?? 0;
        return aSortOrder.compareTo(bSortOrder);
      });
      return eventAssignments;
    }).toList();

    // Separate upcoming and past
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final upcomingGroups = groupedAssignments.where((group) {
      final event = group.first.event!;
      final eventEndDate = DateTime(
        event.endDate.year,
        event.endDate.month,
        event.endDate.day,
      );
      return !eventEndDate.isBefore(today);
    }).toList();

    final pastGroups = groupedAssignments.where((group) {
      final event = group.first.event!;
      final eventEndDate = DateTime(
        event.endDate.year,
        event.endDate.month,
        event.endDate.day,
      );
      return eventEndDate.isBefore(today);
    }).toList();

    // Sort upcoming by start date (soonest first)
    upcomingGroups.sort((a, b) {
      return compareEventsChronologically(a.first.event!, b.first.event!);
    });

    // Sort past by start date (most recent first)
    pastGroups.sort((a, b) {
      return compareEventsChronologicallyDescending(
        a.first.event!,
        b.first.event!,
      );
    });

    return RefreshIndicator(
      onRefresh: () async {
        Logger.action('tap:refreshAssignments');
        _loadUserAssignments();
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'האירועים שלי',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'כאן מופיעים כל האירועים שאליהם שובצת',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),

          // Upcoming assignments section
          _buildSectionHeader(
            context,
            'אירועים קרובים',
            upcomingGroups.length,
            Colors.blue.shade700,
          ),

          if (upcomingGroups.isEmpty)
            _buildEmptySectionMessage('אין אירועים קרובים כרגע')
          else
            ...upcomingGroups.map(
              (assignmentGroup) => _buildAssignmentCard(
                  context, assignmentGroup,
                  isUpcoming: true),
            ),

          const SizedBox(height: 16),

          // Past assignments section (collapsible, closed by default)
          _buildCollapsibleSectionHeader(
            context,
            'אירועים שעברו',
            pastGroups.length,
            Colors.grey.shade600,
            isExpanded: _isPastSectionExpanded,
            onToggle: () {
              Logger.action('toggle:pastSection',
                  {'on': !_isPastSectionExpanded});
              setState(() {
                _isPastSectionExpanded = !_isPastSectionExpanded;
              });
            },
          ),

          if (_isPastSectionExpanded && pastGroups.isEmpty)
            _buildEmptySectionMessage('אין אירועים קודמים'),
          if (_isPastSectionExpanded && pastGroups.isNotEmpty)
            ...pastGroups.map(
              (assignmentGroup) => _buildAssignmentCard(
                  context, assignmentGroup,
                  isUpcoming: false),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha((255 * 0.15).round()),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleSectionHeader(
    BuildContext context,
    String title,
    int count,
    Color color, {
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return Material(
      color: Colors.grey.shade100,
      child: InkWell(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha((255 * 0.15).round()),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySectionMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[500],
          ),
        ),
      ),
    );
  }

  /// Builds a card for an event with all assigned roles
  /// [assignmentGroup] contains all assignments for the same event (multiple roles)
  Widget _buildAssignmentCard(
      BuildContext context, List<Assignment> assignmentGroup,
      {required bool isUpcoming}) {
    if (assignmentGroup.isEmpty) return const SizedBox.shrink();

    // Use the first assignment to get event details (all share the same event)
    final event = assignmentGroup.first.event;
    if (event == null) {
      return const SizedBox.shrink();
    }

    // Get all role types for this event (as String keys)
    final roles = assignmentGroup.map((a) => a.roleType).toList();

    // Collect assignment notes (filter out empty ones)
    final assignmentNotes = assignmentGroup
        .where((a) => a.notes.isNotEmpty)
        .map((a) => MapEntry(a.roleType, a.notes))
        .toList();

    final backgroundColor =
        isUpcoming ? Colors.blue.shade50 : Colors.grey.shade100;
    final borderColor =
        isUpcoming ? Colors.blue.shade200 : Colors.grey.shade300;
    final iconColor = isUpcoming ? Colors.blue.shade700 : Colors.grey.shade500;
    final textColor = isUpcoming ? Colors.grey.shade900 : Colors.grey.shade600;
    final secondaryTextColor =
        isUpcoming ? Colors.grey.shade700 : Colors.grey.shade500;

    // Check if event is today or tomorrow for special highlighting
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final eventStart = DateTime(
        event.startDate.year, event.startDate.month, event.startDate.day);
    final isToday = eventStart.isAtSameMomentAs(today);
    final isTomorrow = eventStart.isAtSameMomentAs(tomorrow);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: isUpcoming ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isToday ? Colors.orange.shade400 : borderColor,
          width: isToday ? 2 : 1,
        ),
      ),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event title row with drive folder button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    event.name,
                    style: TextStyle(
                      fontSize: _getResponsiveFontSize(context,
                          minSize: 16.0, maxSize: 18.0),
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'קבצים בגוגל דרייב',
                  onPressed: () {
                    Logger.action('open:driveFilesDialog',
                        {'eventId': event.id});
                    _showDriveFilesDialog(context, event);
                  },
                  icon: Icon(
                    Icons.folder_open,
                    color: isUpcoming
                        ? Colors.blue.shade700
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),

            // Event comments (moved to just below title)
            if (event.comments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: _getResponsiveIconSize(context,
                          minSize: 16.0, maxSize: 18.0),
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.comments,
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context,
                              minSize: 12.0, maxSize: 13.0),
                          fontStyle: FontStyle.italic,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Role badges row (can have multiple roles)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: roles
                  .map((roleKey) => _buildRoleBadge(roleKey, isUpcoming))
                  .toList(),
            ),

            const SizedBox(height: 12),

            // Assembly time & Location (most important info!)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUpcoming
                    ? Colors.blue.shade100.withAlpha((255 * 0.5).round())
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isUpcoming ? Colors.blue.shade300 : Colors.grey.shade400,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date section
                  if (_isSameDay(event.startDate, event.endDate))
                    // Single day event - one row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: _getResponsiveIconSize(context,
                              minSize: 18.0, maxSize: 22.0),
                          color: isUpcoming
                              ? Colors.blue.shade800
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'תאריך:',
                          style: TextStyle(
                            fontSize: _getResponsiveFontSize(context,
                                minSize: 14.0, maxSize: 16.0),
                            fontWeight: FontWeight.w500,
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text.rich(
                            _formatDateWithHighlight(
                              _formatSingleDayDisplay(
                                  event.startDate, isToday, isTomorrow),
                              isUpcoming,
                              context,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    // Multi-day event - two separate rows
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: _getResponsiveIconSize(context,
                                  minSize: 18.0, maxSize: 22.0),
                              color: isUpcoming
                                  ? Colors.blue.shade800
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'תאריך התחלה:',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context,
                                    minSize: 14.0, maxSize: 16.0),
                                fontWeight: FontWeight.w500,
                                color: secondaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text.rich(
                                _formatDateWithHighlight(
                                  _formatSingleDayDisplay(
                                      event.startDate, isToday, isTomorrow),
                                  isUpcoming,
                                  context,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: _getResponsiveIconSize(context,
                                  minSize: 18.0, maxSize: 22.0),
                              color: isUpcoming
                                  ? Colors.blue.shade800
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'תאריך סיום:',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context,
                                    minSize: 14.0, maxSize: 16.0),
                                fontWeight: FontWeight.w500,
                                color: secondaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text.rich(
                                _formatDateWithHighlight(
                                  _formatSingleDayDisplay(
                                      event.endDate, false, false),
                                  isUpcoming,
                                  context,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  // Location section (if exists)
                  if (event.location.isNotEmpty) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final locationText =
                            MapLocationResult.stripCoordinates(event.location);
                        final hasMapIcons =
                            _isLocationPickedFromMap(event.location);

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: _getResponsiveIconSize(context,
                                  minSize: 18.0, maxSize: 22.0),
                              color: isUpcoming
                                  ? Colors.blue.shade800
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'מיקום:',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context,
                                    minSize: 14.0, maxSize: 16.0),
                                fontWeight: FontWeight.w500,
                                color: secondaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    locationText,
                                    style: TextStyle(
                                      fontSize: _getResponsiveFontSize(context,
                                          minSize: 14.0, maxSize: 16.0),
                                      fontWeight: FontWeight.w600,
                                      color: isUpcoming
                                          ? Colors.blue.shade900
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  if (hasMapIcons) ...[
                                    _buildGoogleMapsButton(
                                        onTap: () {
                                          Logger.action('tap:openGoogleMaps',
                                              {'eventId': event.id});
                                          _openGoogleMaps(event.location);
                                        }),
                                    _buildWazeButton(
                                        onTap: () {
                                          Logger.action('tap:openWaze',
                                              {'eventId': event.id});
                                          _openWaze(event.location);
                                        }),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Parking location section
                  // Show if: (1) parking location exists, OR (2) user can edit parking (show "לא מוגדרת")
                  Builder(
                    builder: (context) {
                      final currentUserId =
                          context.select<UserSelectionBloc, String?>((bloc) {
                        final state = bloc.state;
                        return state is UserAuthenticated
                            ? state.user.id
                            : null;
                      });
                      final canEditParking = currentUserId != null &&
                          event.parkingEditorIds.contains(currentUserId);

                      final hasParkingLocation =
                          event.parkingLocation != null &&
                              event.parkingLocation!.isNotEmpty;

                      // Only show if there's a parking location OR user can edit
                      if (!hasParkingLocation && !canEditParking) {
                        return const SizedBox.shrink();
                      }

                      final parkingText = hasParkingLocation
                          ? MapLocationResult.stripCoordinates(
                              event.parkingLocation!)
                          : 'לא מוגדרת';
                      final hasMapIcons = hasParkingLocation &&
                          _isLocationPickedFromMap(event.parkingLocation!);

                      return Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.local_parking,
                                    size: _getResponsiveIconSize(context,
                                        minSize: 18.0, maxSize: 22.0),
                                    color: iconColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'חנייה:',
                                    style: TextStyle(
                                      fontSize: _getResponsiveFontSize(context,
                                          minSize: 14.0, maxSize: 16.0),
                                      fontWeight: FontWeight.w500,
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        GestureDetector(
                                          onTap: canEditParking
                                              ? () {
                                                  Logger.action(
                                                      'tap:editParkingLocation',
                                                      {'eventId': event.id});
                                                  _editParkingLocation(
                                                      context, event);
                                                }
                                              : null,
                                          child: Text(
                                            parkingText,
                                            style: TextStyle(
                                              fontSize: _getResponsiveFontSize(
                                                  context),
                                              fontWeight: FontWeight.bold,
                                              color: hasParkingLocation
                                                  ? (isUpcoming
                                                      ? Colors.blue.shade900
                                                      : Colors.grey.shade700)
                                                  : (isUpcoming
                                                      ? Colors.grey.shade600
                                                      : Colors.grey.shade400),
                                              fontStyle: hasParkingLocation
                                                  ? FontStyle.normal
                                                  : FontStyle.italic,
                                              decoration: canEditParking
                                                  ? TextDecoration.underline
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (hasMapIcons) ...[
                                          _buildGoogleMapsButton(
                                              onTap: () {
                                                Logger.action(
                                                    'tap:openGoogleMapsParking',
                                                    {'eventId': event.id});
                                                _openGoogleMaps(
                                                    event.parkingLocation!);
                                              }),
                                          _buildWazeButton(
                                              onTap: () {
                                                Logger.action(
                                                    'tap:openWazeParking',
                                                    {'eventId': event.id});
                                                _openWaze(
                                                    event.parkingLocation!);
                                              }),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    },
                  ),
                  // Assembly time row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time_filled,
                        size: _getResponsiveIconSize(context,
                            minSize: 18.0, maxSize: 22.0),
                        color: isUpcoming
                            ? Colors.blue.shade800
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'שעת התייצבות:',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context,
                              minSize: 14.0, maxSize: 16.0),
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        event.assemblyTime.isNotEmpty
                            ? event.assemblyTime
                            : 'טרם נקבעה',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context,
                              minSize: 14.0, maxSize: 16.0),
                          fontWeight: FontWeight.w600,
                          color: isUpcoming
                              ? Colors.blue.shade900
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Event times - vertical list in chronological order
            // 1. Audience gathering time (התכנסות קהל)
            if (event.startTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: _getResponsiveIconSize(context,
                          minSize: 16.0, maxSize: 18.0),
                      color: iconColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'התכנסות קהל:',
                      style: TextStyle(
                        fontSize: _getResponsiveFontSize(context,
                            minSize: 13.0, maxSize: 14.0),
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      event.startTime,
                      style: TextStyle(
                        fontSize: _getResponsiveFontSize(context,
                            minSize: 13.0, maxSize: 14.0),
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),

            // 2. Actual show start time (תחילת המופע)
            if (event.actualShowStartTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      size: _getResponsiveIconSize(context,
                          minSize: 16.0, maxSize: 18.0),
                      color: iconColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'תחילת המופע:',
                      style: TextStyle(
                        fontSize: _getResponsiveFontSize(context,
                            minSize: 13.0, maxSize: 14.0),
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      event.actualShowStartTime,
                      style: TextStyle(
                        fontSize: _getResponsiveFontSize(context,
                            minSize: 13.0, maxSize: 14.0),
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),

            // 3. End time (סיום)
            if (event.endTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: _getResponsiveIconSize(context,
                          minSize: 16.0, maxSize: 18.0),
                      color: iconColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'סיום:',
                      style: TextStyle(
                        fontSize: _getResponsiveFontSize(context,
                            minSize: 13.0, maxSize: 14.0),
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      event.endTime,
                      style: TextStyle(
                        fontSize: _getResponsiveFontSize(context,
                            minSize: 13.0, maxSize: 14.0),
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),

            // "Who's with me?" button
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _showEventTeamMembers(context, event.id, event.name),
                icon: Icon(
                  Icons.groups,
                  size: _getResponsiveIconSize(context,
                      minSize: 16.0, maxSize: 18.0),
                ),
                label: Text(
                  'מי איתי באירוע?',
                  style: TextStyle(
                    fontSize: _getResponsiveFontSize(context,
                        minSize: 13.0, maxSize: 14.0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade100,
                  foregroundColor: Colors.blue.shade700,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.blue.shade200),
                  ),
                ),
              ),
            ),

            // Assignment notes (at the bottom)
            ...assignmentNotes.map((entry) {
              final noteText = assignmentNotes.length > 1
                  ? null // will use BlocBuilder for role prefix
                  : entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
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
                        size: _getResponsiveIconSize(context,
                            minSize: 16.0, maxSize: 18.0),
                        color: Colors.purple.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: assignmentNotes.length > 1
                            ? BlocBuilder<RoleBloc, RoleState>(
                                builder: (context, roleState) {
                                  final roleHebrewName = roleState
                                          is RolesLoaded
                                      ? roleState.getRoleHebrewName(entry.key)
                                      : entry.key;
                                  return Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text:
                                              'הערות לשיבוץ ($roleHebrewName): ',
                                          style: TextStyle(
                                            fontSize: _getResponsiveFontSize(
                                                context,
                                                minSize: 12.0,
                                                maxSize: 13.0),
                                            fontWeight: FontWeight.w600,
                                            color: Colors.purple.shade800,
                                          ),
                                        ),
                                        TextSpan(
                                          text: entry.value,
                                          style: TextStyle(
                                            fontSize: _getResponsiveFontSize(
                                                context,
                                                minSize: 12.0,
                                                maxSize: 13.0),
                                            color: Colors.purple.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'הערות לשיבוץ: ',
                                      style: TextStyle(
                                        fontSize: _getResponsiveFontSize(
                                            context,
                                            minSize: 12.0,
                                            maxSize: 13.0),
                                        fontWeight: FontWeight.w600,
                                        color: Colors.purple.shade800,
                                      ),
                                    ),
                                    TextSpan(
                                      text: noteText,
                                      style: TextStyle(
                                        fontSize: _getResponsiveFontSize(
                                            context,
                                            minSize: 12.0,
                                            maxSize: 13.0),
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
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String roleKey, bool isUpcoming) {
    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
        final roleHebrewName = roleState is RolesLoaded
            ? roleState.getRoleHebrewName(roleKey)
            : roleKey;
        final backgroundColor =
            isUpcoming ? _getRoleColor() : Colors.grey.shade400;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            roleHebrewName,
            style: TextStyle(
              fontSize:
                  _getResponsiveFontSize(context, minSize: 12.0, maxSize: 13.0),
              fontWeight: FontWeight.w600,
              color: isUpcoming ? Colors.white : Colors.grey.shade800,
            ),
          ),
        );
      },
    );
  }

  Color _getRoleColor() {
    // All roles use green color for consistency
    return Colors.green.shade700;
  }

  String _formatDateDisplay(Event event, bool isToday, bool isTomorrow) {
    final startDate = event.startDate;
    final endDate = event.endDate;

    // Check if same day
    if (_isSameDay(startDate, endDate)) {
      final dateStr =
          'יום ${_getFullHebrewDayName(startDate.weekday)} ${startDate.day} ב${_getHebrewMonthName(startDate.month)}';

      if (isToday) {
        return '$dateStr (היום)';
      }
      if (isTomorrow) {
        return '$dateStr (מחר)';
      }
      return dateStr;
    }

    // Multi-day event
    final startDateStr =
        'יום ${_getFullHebrewDayName(startDate.weekday)} ${startDate.day} ב${_getHebrewMonthName(startDate.month)}';
    final endDateStr =
        'יום ${_getFullHebrewDayName(endDate.weekday)} ${endDate.day} ב${_getHebrewMonthName(endDate.month)}';

    if (isToday) {
      return '$startDateStr (היום) --> $endDateStr';
    }
    if (isTomorrow) {
      return '$startDateStr (מחר) --> $endDateStr';
    }
    return '$startDateStr --> $endDateStr';
  }

  String _formatSingleDayDisplay(DateTime date, bool isToday, bool isTomorrow) {
    final dateStr =
        'יום ${_getFullHebrewDayName(date.weekday)} ${date.day} ב${_getHebrewMonthName(date.month)}';

    if (isToday) {
      return '$dateStr (היום)';
    }
    if (isTomorrow) {
      return '$dateStr (מחר)';
    }
    return dateStr;
  }

  String _formatDayMonth(DateTime date) {
    final day = date.day;
    final month = _getHebrewMonthName(date.month);
    return '$day $month';
  }

  String _getHebrewDayName(int weekday) {
    const days = [
      '',
      'יום ב\'',
      'יום ג\'',
      'יום ד\'',
      'יום ה\'',
      'יום ו\'',
      'שבת',
      'יום א\''
    ];
    return days[weekday];
  }

  String _getFullHebrewDayName(int weekday) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    return days[weekday];
  }

  TextSpan _formatDateWithHighlight(
      String dateText, bool isUpcoming, BuildContext context) {
    final color = isUpcoming ? Colors.blue.shade900 : Colors.grey.shade700;
    final responsiveFontSize =
        _getResponsiveFontSize(context, minSize: 14.0, maxSize: 16.0);

    if (dateText.contains('(היום)')) {
      final parts = dateText.split('(היום)');
      return TextSpan(
        children: [
          TextSpan(
            text: parts[0],
            style: TextStyle(
              fontSize: responsiveFontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          TextSpan(
            text: '(היום)',
            style: TextStyle(
              fontSize: responsiveFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
          if (parts.length > 1)
            TextSpan(
              text: parts[1],
              style: TextStyle(
                fontSize: responsiveFontSize,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
        ],
      );
    }

    if (dateText.contains('(מחר)')) {
      final parts = dateText.split('(מחר)');
      return TextSpan(
        children: [
          TextSpan(
            text: parts[0],
            style: TextStyle(
              fontSize: responsiveFontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          TextSpan(
            text: '(מחר)',
            style: TextStyle(
              fontSize: responsiveFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
          if (parts.length > 1)
            TextSpan(
              text: parts[1],
              style: TextStyle(
                fontSize: responsiveFontSize,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
        ],
      );
    }

    // No special indicators
    return TextSpan(
      text: dateText,
      style: TextStyle(
        fontSize: responsiveFontSize,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  String _getHebrewMonthName(int month) {
    const months = [
      '',
      'ינואר',
      'פברואר',
      'מרץ',
      'אפריל',
      'מאי',
      'יוני',
      'יולי',
      'אוגוסט',
      'ספטמבר',
      'אוקטובר',
      'נובמבר',
      'דצמבר'
    ];
    return months[month];
  }

  String _formatEventTimes(String startTime, String endTime) {
    // Check if both times are empty
    if (startTime.isEmpty && endTime.isEmpty) {
      return 'טרם נקבעו';
    }

    // Check if only start time is empty
    if (startTime.isEmpty && endTime.isNotEmpty) {
      return 'טרם נקבעה --> $endTime';
    }

    // Check if only end time is empty
    if (startTime.isNotEmpty && endTime.isEmpty) {
      return '$startTime --> טרם נקבעה';
    }

    // Both times are available
    return '$startTime --> $endTime';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildGoogleMapsButton({required VoidCallback onTap}) {
    return Tooltip(
      message: 'Google Maps',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
          height: _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Image.asset(
            'assets/images/google_maps.png',
            width:
                _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
            height:
                _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.map_outlined,
                size: _getResponsiveIconSize(context,
                    minSize: 22.0, maxSize: 28.0),
                color: Colors.red.shade600,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWazeButton({required VoidCallback onTap}) {
    return Tooltip(
      message: 'Waze',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
          height: _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Image.asset(
            'assets/images/waze.png',
            width:
                _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
            height:
                _getResponsiveIconSize(context, minSize: 22.0, maxSize: 28.0),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.navigation_outlined,
                size: _getResponsiveIconSize(context,
                    minSize: 22.0, maxSize: 28.0),
                color: Colors.blue.shade600,
              );
            },
          ),
        ),
      ),
    );
  }

  /// Open Google Maps with directions to the location
  void _openGoogleMaps(String location) {
    final (lat, lng) = MapLocationResult.parseCoordinates(location);

    String url;
    if (lat != null && lng != null) {
      // Use coordinates for precise navigation
      url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    } else {
      // Fall back to search by location name
      final query = MapLocationResult.stripCoordinates(location);
      url =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
    }

    launchUrlWithAutoClose(url);
  }

  /// Open Waze with directions to the location
  void _openWaze(String location) {
    final (lat, lng) = MapLocationResult.parseCoordinates(location);

    String url;
    if (lat != null && lng != null) {
      // Use coordinates for precise navigation
      url = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
    } else {
      // Fall back to search by location name
      final query = MapLocationResult.stripCoordinates(location);
      url = 'https://waze.com/ul?q=${Uri.encodeComponent(query)}&navigate=yes';
    }

    launchUrlWithAutoClose(url);
  }

  /// Check if the location was picked using the map picker
  /// Map picker locations have coordinates (either with "||" separator or as raw "lat, lng")
  bool _isLocationPickedFromMap(String location) {
    // Check for the "||" separator format
    if (location.contains('||')) {
      return true;
    }

    // Try to parse coordinates directly (format: "lat, lng")
    final coords = MapLocationResult.parseCoordinates(location);
    return coords.$1 != null && coords.$2 != null;
  }

  /// Update parking location for an event
  Future<CrudActionResult> _updateParkingLocation(
    BuildContext context,
    Event event,
    String? newParkingLocation,
    List<String> newEditorIds,
  ) async {
    final updatedEvent = event.copyWith(
      parkingLocation: newParkingLocation,
      parkingEditorIds: newEditorIds,
      updatedAt: DateTime.now(),
      clearParkingLocation:
          newParkingLocation == null, // Explicitly clear when null
    );

    return await _runBlockingMutation(
      message: 'שומר מיקום חנייה...',
      dispatch: (completion) {
        context.read<EventBloc>().add(
              UpdateEvent(updatedEvent, completion: completion),
            );
      },
    );
  }

  /// Edit parking location for an event
  void _editParkingLocation(BuildContext context, Event event) async {
    // Use simplified dialog in user/assignments screen
    // Team member editor selection only available in admin/event modal
    final result = await ParkingLocationPickerDialog.show(
      context,
      eventLocation: event.location,
      initialParkingLocation: event.parkingLocation,
    );

    if (result != null && mounted) {
      // Handle empty parking location (user clicked "Clear")
      final newLocation =
          result.parkingLocation.isEmpty ? null : result.parkingLocation;

      final updateResult = await _updateParkingLocation(
        context,
        event,
        newLocation,
        event
            .parkingEditorIds, // Keep original editor IDs (users can't change them)
      );

      if (!mounted) {
        return;
      }

      if (updateResult.isFailure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updateResult.message ?? 'שגיאה בשמירת מיקום החנייה'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newLocation == null
                ? 'מיקום החנייה נמחק בהצלחה'
                : 'מיקום החנייה עודכן בהצלחה'),
            backgroundColor: newLocation == null ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _startMutation(String message) {
    setState(() {
      _isMutationInFlight = true;
      _mutationMessage = message;
    });
  }

  void _finishMutation() {
    if (!mounted) return;
    setState(() {
      _isMutationInFlight = false;
      _mutationMessage = '';
    });
  }

  Future<CrudActionResult> _dispatchMutation(
    void Function(CrudActionCompleter completion) dispatch,
  ) async {
    final completion = Completer<CrudActionResult>();
    dispatch(completion);
    return await completion.future;
  }

  Future<CrudActionResult> _runBlockingMutation({
    required String message,
    required void Function(CrudActionCompleter completion) dispatch,
  }) async {
    if (_isMutationInFlight) {
      return const CrudActionResult.failure('פעולה אחרת עדיין מתבצעת');
    }

    _startMutation(message);
    final result = await _dispatchMutation(dispatch);
    _finishMutation();
    return result;
  }

  Widget _buildMutationDialogOverlay() {
    if (!_isMutationInFlight) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  _mutationMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'אין לך שיבוצים כרגע',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'כשתשובץ/י לאירוע, הוא יופיע כאן',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            'שגיאה בטעינת שיבוצים',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Logger.action('tap:retryLoadAssignments');
              _loadUserAssignments();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }

  /// Show dialog with all team members assigned to the event
  void _showEventTeamMembers(
      BuildContext context, String eventId, String eventName) {
    Logger.action('open:whoIsWithMe', {'eventId': eventId});
    final userState = context.read<UserSelectionBloc>().state;
    if (userState is! UserAuthenticated) return;

    showDialog(
      context: context,
      builder: (context) => EventTeamMembersDialog(
        eventId: eventId,
        currentUserId: userState.user.id,
        eventName: eventName,
      ),
    );
  }

  void _showDriveFilesDialog(BuildContext context, Event event) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogHeight = (screenHeight * 0.72).clamp(420.0, 760.0);
    final filesListHeight = (dialogHeight - 170).clamp(200.0, 580.0);

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SizedBox(
            width: 560,
            height: dialogHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_open, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('קבצים בגוגל דרייב')),
                      IconButton(
                        tooltip: 'סגור',
                        onPressed: () {
                          Logger.action('tap:close:driveFilesDialog',
                              {'eventId': event.id});
                          Navigator.of(dialogContext).pop();
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  EventDriveFilesSection(
                    eventId: event.id,
                    driveFolderId: event.driveFolderId,
                    driveFolderLink: event.driveFolderLink,
                    eventName: event.name,
                    showHeader: false,
                    scrollableFilesOnly: true,
                    filesListHeight: filesListHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
