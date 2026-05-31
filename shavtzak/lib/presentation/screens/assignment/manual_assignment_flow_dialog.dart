import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/debug/logger.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/role.dart';
import '../../../domain/entities/assignment.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/constants/constraint_status.dart';
import '../../../core/utils/search_utils.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/role/role_bloc.dart';
import '../../bloc/role/role_state.dart';
import '../../widgets/map_location_picker.dart';

class ManualAssignmentFlowDialog extends StatefulWidget {
  const ManualAssignmentFlowDialog({super.key});

  @override
  State<ManualAssignmentFlowDialog> createState() => _ManualAssignmentFlowDialogState();
}

class _ManualAssignmentFlowDialogState extends State<ManualAssignmentFlowDialog> {
  int _currentStep = 0;
  Event? _selectedEvent;
  TeamMember? _selectedTeamMember;
  Role? _selectedRole;
  List<Event> _futureEvents = [];
  List<TeamMember> _teamMembers = [];
  List<Assignment> _allAssignments = [];
  Map<String, List<String>> _sameDayEventsByMember = {}; // memberId -> list of event names

  // Search controllers for each step
  final TextEditingController _eventSearchController = TextEditingController();
  final TextEditingController _memberSearchController = TextEditingController();
  final TextEditingController _roleSearchController = TextEditingController();

  // Scroll controllers for each step
  final ScrollController _eventScrollController = ScrollController();
  final ScrollController _memberScrollController = ScrollController();
  final ScrollController _roleScrollController = ScrollController();

  // Search queries for each step
  String _eventSearchQuery = '';
  String _memberSearchQuery = '';
  String _roleSearchQuery = '';

  @override
  void dispose() {
    _eventSearchController.dispose();
    _memberSearchController.dispose();
    _roleSearchController.dispose();
    _eventScrollController.dispose();
    _memberScrollController.dispose();
    _roleScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    // Load events and team members
    context.read<EventBloc>().add(const LoadEvents());
    context.read<TeamBloc>().add(const LoadActiveTeamMembers());

    // Load all assignments for same-day conflict detection
    final assignmentRepo = context.read<AssignmentRepository>();
    _allAssignments = await assignmentRepo.getAllAssignments();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<EventBloc, EventState>(
          listener: (context, state) {
            if (state is EventsLoaded) {
              setState(() {
                _futureEvents = state.events
                    .where((event) => !event.isPast && !event.isDeactivated)
                    .toList()
                  ..sort((a, b) => a.startDate.compareTo(b.startDate));
              });
            }
          },
        ),
        BlocListener<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamLoaded) {
              setState(() {
                _teamMembers = state.members
                    .where((member) => member.isActive && !member.isArchived)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
              });
            }
          },
        ),
      ],
      child: AlertDialog(
        actionsAlignment: _currentStep == 0
            ? MainAxisAlignment.end
            : MainAxisAlignment.spaceBetween,
        title: Text(
          'שיבוץ ידני חדש',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        content: SizedBox(
          width: 400,
          height: 500,
          child: Column(
            children: [
              // Progress indicator
              _buildProgressIndicator(),

              const SizedBox(height: 24),

              // Step content
              Expanded(
                child: _buildStepContent(),
              ),
            ],
          ),
        ),
        actions: [
          // Back button (only show on steps 2 and 3)
          if (_currentStep == 1 || _currentStep == 2)
            TextButton(
              onPressed: () {
                Logger.action('tap:back:manualAssignmentFlow', {'step': _currentStep});
                setState(() {
                  _currentStep--;
                  // Clear search query when going back
                  if (_currentStep == 1) {
                    _memberSearchController.clear();
                    _memberSearchQuery = '';
                  } else if (_currentStep == 0) {
                    _eventSearchController.clear();
                    _eventSearchQuery = '';
                  }
                });
                // Scroll to top when going back (after widget rebuild)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_currentStep == 1 && _memberScrollController.hasClients) {
                    _memberScrollController.jumpTo(0);
                  } else if (_currentStep == 0 && _eventScrollController.hasClients) {
                    _eventScrollController.jumpTo(0);
                  }
                });
              },
              child: const Text('אחורה'),
            ),
          // Cancel button - role selection auto-completes the assignment
          TextButton(
            onPressed: () {
              Logger.action('tap:cancel:manualAssignmentFlow', {'step': _currentStep});
              Navigator.of(context).pop();
            },
            child: const Text('ביטול', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Container(
          width: 60,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: index <= _currentStep ? Colors.blue : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildEventSelectionStep();
      case 1:
        return _buildTeamMemberSelectionStep();
      case 2:
        return _buildRoleSelectionStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEventSelectionStep() {
    // Filter events based on normalized search query
    final normalizedQuery = normalizeForSearch(_eventSearchController.text.trim());
    var filteredEvents = normalizedQuery.isEmpty
        ? _futureEvents
        : _futureEvents.where((event) {
            final normalizedName = normalizeForSearch(event.name);
            final normalizedLocation = normalizeForSearch(event.location);
            return normalizedName.contains(normalizedQuery) ||
                   normalizedLocation.contains(normalizedQuery);
          }).toList();

    // Sort so selected event appears at the top
    if (_selectedEvent != null && filteredEvents.any((e) => e.id == _selectedEvent!.id)) {
      filteredEvents = [
        filteredEvents.firstWhere((e) => e.id == _selectedEvent!.id),
        ...filteredEvents.where((e) => e.id != _selectedEvent!.id),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 1 מתוך 3: בחירת אירוע',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'בחר אירוע עתידי שברצונך לשבץ לו איש צוות:',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        // Search bar
        Directionality(
          textDirection: TextDirection.rtl,
          child: TextField(
            controller: _eventSearchController,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'חיפוש אירוע לפי שם או מיקום...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _eventSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        Logger.action('tap:clearSearch:event');
                        setState(() {
                          _eventSearchController.clear();
                          _eventSearchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (value) {
              setState(() {
                _eventSearchQuery = value;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filteredEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        normalizedQuery.isEmpty
                            ? 'לא נמצאו אירועים עתידיים'
                            : 'לא נמצאו אירועים התואמים לחיפוש',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _eventScrollController,
                  itemCount: filteredEvents.length,
                  itemBuilder: (context, index) {
                    final event = filteredEvents[index];
                    final isSelected = _selectedEvent?.id == event.id;

                    return Card(
                      elevation: isSelected ? 4 : 1,
                      color: isSelected ? Colors.blue.shade50 : Colors.white,
                      child: ListTile(
                        title: Text(
                          event.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.blue.shade700 : Colors.black,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Dates formatted in Hebrew
                            Text(_formatEventDates(event)),
                            // Time fields with labels
                            if (event.assemblyTime.isNotEmpty)
                              Text('שעת התייצבות: ${event.assemblyTime}'),
                            if (event.startTime.isNotEmpty)
                              Text('שעת התכנסות קהל: ${event.startTime}'),
                            if (event.actualShowStartTime.isNotEmpty)
                              Text('שעת תחילת המופע בפועל: ${event.actualShowStartTime}'),
                            if (event.endTime.isNotEmpty)
                              Text('שעת סיום: ${event.endTime}'),
                            // Location (without coordinates)
                            if (event.location.isNotEmpty)
                              Text('מיקום: ${_formatLocationForDisplay(event.location)}'),
                          ],
                        ),
                        onTap: () {
                          Logger.action('select:event', {'eventId': event.id});
                          // Update selection if different event
                          if (!isSelected) {
                            setState(() {
                              _selectedEvent = event;
                            });
                          }
                          // Always advance to next step (even if same event)
                          _computeSameDayAssignments();
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) {
                              setState(() {
                                _currentStep = 1;
                                // Clear member search when entering step 2
                                _memberSearchController.clear();
                                _memberSearchQuery = '';
                              });
                              // Scroll member list to top after widget rebuild
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && _memberScrollController.hasClients) {
                                  _memberScrollController.jumpTo(0);
                                }
                              });
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTeamMemberSelectionStep() {
    // Filter team members based on normalized search query
    final normalizedQuery = normalizeForSearch(_memberSearchController.text.trim());
    var filteredMembers = normalizedQuery.isEmpty
        ? _teamMembers
        : _teamMembers.where((member) {
            final normalizedName = normalizeForSearch(member.name);
            return normalizedName.contains(normalizedQuery);
          }).toList();

    // Sort so selected team member appears at the top
    if (_selectedTeamMember != null && filteredMembers.any((m) => m.id == _selectedTeamMember!.id)) {
      filteredMembers = [
        filteredMembers.firstWhere((m) => m.id == _selectedTeamMember!.id),
        ...filteredMembers.where((m) => m.id != _selectedTeamMember!.id),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 2 מתוך 3: בחירת איש צוות',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'בחר איש צוות לשיבוץ באירוע "${_selectedEvent?.name}":',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        // Search bar
        Directionality(
          textDirection: TextDirection.rtl,
          child: TextField(
            controller: _memberSearchController,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'חיפוש איש צוות לפי שם...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _memberSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        Logger.action('tap:clearSearch:member');
                        setState(() {
                          _memberSearchController.clear();
                          _memberSearchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (value) {
              setState(() {
                _memberSearchQuery = value;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filteredMembers.isEmpty
              ? Center(
                  child: Text(
                    normalizedQuery.isEmpty
                        ? 'לא נמצאו אנשי צוות פעילים'
                        : 'לא נמצאו אנשי צוות התואמים לחיפוש',
                  ),
                )
              : ListView.builder(
                  controller: _memberScrollController,
                  itemCount: filteredMembers.length,
                  itemBuilder: (context, index) {
                    final teamMember = filteredMembers[index];
                    final isSelected = _selectedTeamMember?.id == teamMember.id;
                    final hasConflict = _hasDateConstraintConflict(teamMember);
                    final hasAvailability = _hasAvailabilityForEvent(teamMember);
                    final hasSameDay = _hasSameDayAssignment(teamMember);

                    // Track availability issue but don't disable
                    final hasAvailabilityIssue = !teamMember.isPermanent && !hasAvailability;

                    return Card(
                      elevation: isSelected ? 4 : 1,
                      color: isSelected
                          ? Colors.blue.shade50
                          : Colors.white,
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(
                              teamMember.name,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.black,
                              ),
                            ),
                            if (teamMember.isPermanent) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.verified_user,
                                size: 16,
                                color: Colors.blue.shade700,
                              ),
                            ],
                          ],
                        ),
                        trailing: hasConflict || hasAvailabilityIssue || hasSameDay
                            ? Icon(Icons.warning, color: Colors.orange.shade700)
                            : null,
                        onTap: () {
                          Logger.action('select:teamMember', {
                            'memberId': teamMember.id,
                            'hasConflict': hasConflict,
                            'hasAvailabilityIssue': hasAvailabilityIssue,
                            'hasSameDay': hasSameDay,
                          });
                          if (hasConflict || hasAvailabilityIssue || hasSameDay) {
                            _showConstraintWarning(teamMember, hasAvailabilityIssue, hasSameDay: hasSameDay);
                          } else {
                            // Update selection if different member
                            if (!isSelected) {
                              setState(() {
                                _selectedTeamMember = teamMember;
                              });
                            }
                            // Always advance to next step (even if same member)
                            Future.delayed(const Duration(milliseconds: 300), () {
                              if (mounted) {
                                setState(() {
                                  _currentStep = 2;
                                  // Clear role search when entering step 3
                                  _roleSearchController.clear();
                                  _roleSearchQuery = '';
                                });
                                // Scroll role list to top after widget rebuild
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted && _roleScrollController.hasClients) {
                                    _roleScrollController.jumpTo(0);
                                  }
                                });
                              }
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRoleSelectionStep() {
    if (_selectedTeamMember == null) return const SizedBox.shrink();

    final availableRoleKeys = _selectedTeamMember!.roleCapabilities.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();

    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
        // Get role display names from RoleBloc
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

        // Filter roles to only those that match available role keys
        var filteredRoles = roles.where((roleObj) {
          return availableRoleKeys.contains(roleObj.key);
        }).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        // Apply search filter
        final normalizedQuery = normalizeForSearch(_roleSearchController.text.trim());
        if (normalizedQuery.isNotEmpty) {
          filteredRoles = filteredRoles.where((role) {
            final normalizedRoleName = normalizeForSearch(role.hebrewName);
            return normalizedRoleName.contains(normalizedQuery);
          }).toList();
        }

        // Sort so selected role appears at the top
        if (_selectedRole != null && filteredRoles.any((r) => r.key == _selectedRole!.key)) {
          filteredRoles = [
            filteredRoles.firstWhere((r) => r.key == _selectedRole!.key),
            ...filteredRoles.where((r) => r.key != _selectedRole!.key),
          ];
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'שלב 3 מתוך 3: בחירת תפקיד',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'בחר תפקיד עבור ${_selectedTeamMember!.name} באירוע "${_selectedEvent?.name}":',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            // Search bar
            Directionality(
              textDirection: TextDirection.rtl,
              child: TextField(
                controller: _roleSearchController,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'חיפוש תפקיד לפי שם...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _roleSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            Logger.action('tap:clearSearch:role');
                            setState(() {
                              _roleSearchController.clear();
                              _roleSearchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
                onChanged: (value) {
                  setState(() {
                    _roleSearchQuery = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredRoles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.work_off, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            normalizedQuery.isEmpty
                                ? 'לאיש צוות זה אין תפקידים זמינים'
                                : 'לא נמצאו תפקידים התואמים לחיפוש',
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _roleScrollController,
                      itemCount: filteredRoles.length,
                      itemBuilder: (context, index) {
                        final role = filteredRoles[index];
                        final isSelected = _selectedRole?.key == role.key;

                        return Card(
                          elevation: isSelected ? 4 : 1,
                          color: isSelected ? Colors.blue.shade50 : Colors.white,
                          child: InkWell(
                            onTap: () {
                              Logger.action('select:role', {'roleKey': role.key});
                              // Update selection if different role
                              if (!isSelected) {
                                setState(() {
                                  _selectedRole = role;
                                });
                              }
                              // Always finish (even if same role)
                              _finish();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text(
                                role.hebrewName,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.blue.shade700 : Colors.black,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _hasDateConstraintConflict(TeamMember teamMember) {
    if (_selectedEvent == null) return false;

    // Members with allowMultipleAssignments bypass constraint checks
    if (teamMember.allowMultipleAssignments) return false;

    return teamMember.constraints.any((constraint) {
      // Only consider APPROVED constraints for conflicts
      if (constraint.status != ConstraintStatus.approved) return false;

      // For permanent members, check for unavailability constraints
      // For non-permanent members, check if they DON'T have availability
      if (teamMember.isPermanent) {
        // Permanent members: unavailability constraints cause conflicts
        if (constraint.constraintType != ConstraintType.unavailability) return false;
      } else {
        // Non-permanent members: lack of availability causes conflicts
        // But we don't show this as a constraint warning - they just can't be selected
        return false;
      }

      // Check if constraint overlaps with event dates
      final constraintStart = constraint.startDate;
      final constraintEnd = constraint.endDate ?? constraint.startDate;
      final dateOverlap = !(constraintEnd.isBefore(_selectedEvent!.startDate) ||
               constraintStart.isAfter(_selectedEvent!.endDate));

      if (!dateOverlap) return false;

      // If dates overlap, check if constraint blocks the event
      // If constraint has no time specified, it blocks (applies to entire day)
      // If constraint has time, check if it blocks event time
      return constraint.blocksEventAssignment(_selectedEvent!);
    });
  }

  /// Check if member has availability for the selected event
  bool _hasAvailabilityForEvent(TeamMember teamMember) {
    // Members with allowMultipleAssignments bypass availability checks
    if (teamMember.allowMultipleAssignments) return true;

    // Permanent members are always considered available unless they have unavailability constraints
    if (teamMember.isPermanent) return true;

    if (_selectedEvent == null) return false;

    // For non-permanent members, use the new event-based availability system
    return teamMember.isAvailableForEvent(_selectedEvent!.id);
  }

  /// Check if member is assigned to another event on the same day(s)
  bool _hasSameDayAssignment(TeamMember teamMember) {
    if (_selectedEvent == null) return false;

    // Members with allowMultipleAssignments bypass same-day checks
    if (teamMember.allowMultipleAssignments) return false;

    return _sameDayEventsByMember.containsKey(teamMember.id);
  }

  /// Compute same-day assignments for the selected event
  void _computeSameDayAssignments() {
    if (_selectedEvent == null) {
      _sameDayEventsByMember = {};
      return;
    }

    final sameDayMap = <String, List<String>>{};

    for (final assignment in _allAssignments) {
      // Skip assignments to the selected event
      if (assignment.eventId == _selectedEvent!.id) continue;

      // Find the other event
      final otherEvent = _futureEvents.firstWhere(
        (e) => e.id == assignment.eventId,
        orElse: () => Event(
          id: '',
          name: '',
          startDate: DateTime.now(),
          endDate: DateTime.now(),
          startTime: '',
          endTime: '',
          assemblyTime: '',
          location: '',
          requiresArmed: false,
          roleRequirements: {},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Skip if event not found
      if (otherEvent.id.isEmpty) continue;

      // Check if events share dates
      if (_eventsShareDate(_selectedEvent!, otherEvent)) {
        final memberId = assignment.teamMemberId;
        sameDayMap.putIfAbsent(memberId, () => []);
        if (!sameDayMap[memberId]!.contains(otherEvent.name)) {
          sameDayMap[memberId]!.add(otherEvent.name);
        }
      }
    }

    setState(() {
      _sameDayEventsByMember = sameDayMap;
    });
  }

  /// Helper function to check if two events share at least one day
  bool _eventsShareDate(Event a, Event b) {
    // Normalize dates to day precision (ignore time)
    final aStart = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final aEnd = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    final bStart = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
    final bEnd = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);

    // Check for overlap: events overlap if one starts before the other ends
    return aStart.isBefore(bEnd.add(const Duration(days: 1))) &&
           bStart.isBefore(aEnd.add(const Duration(days: 1)));
  }

  void _showConstraintWarning(TeamMember teamMember, bool isAvailabilityIssue, {bool hasSameDay = false}) {
    String warningMessage;
    List<Widget> constraintDetails = [];

    if (hasSameDay) {
      // Same-day assignment conflict
      final otherEvents = _sameDayEventsByMember[teamMember.id] ?? [];
      warningMessage = 'חבר/ת צוות זה/זו משובצ/ת לאירוע אחר באותם תאריכים:\n\n${otherEvents.join(", ")}';
    } else if (isAvailabilityIssue) {
      // Non-permanent member without availability
      warningMessage = 'ל${teamMember.name} אין זמינות לאירוע "${_selectedEvent!.name}".\n\nחברי צוות לא-קבועים צריכים לציין זמינות מראש.';
    } else {
      // Date constraint conflict for permanent member
      final conflictingConstraints = teamMember.constraints.where((constraint) {
        // Only show approved unavailability constraints for permanent members
        if (constraint.status != ConstraintStatus.approved) return false;
        if (teamMember.isPermanent && constraint.constraintType != ConstraintType.unavailability) return false;
        if (!teamMember.isPermanent) return false; // Don't show for non-permanent members

        final constraintStart = constraint.startDate;
        final constraintEnd = constraint.endDate ?? constraint.startDate;
        final dateOverlap = !(constraintEnd.isBefore(_selectedEvent!.startDate) ||
                 constraintStart.isAfter(_selectedEvent!.endDate));

        if (!dateOverlap) return false;

        // Check if this constraint blocks the event
        return constraint.blocksEventAssignment(_selectedEvent!);
      }).toList();

      warningMessage = 'ל${teamMember.name} יש הגבלות אישורות החופפות לאירוע "${_selectedEvent!.name}":';
      constraintDetails = conflictingConstraints.map((constraint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.block, size: 16, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    constraint.endDate != null && !_isSameDay(constraint.startDate, constraint.endDate!)
                        ? '${_formatDate(constraint.startDate)} - ${_formatDate(constraint.endDate!)}'
                        : _formatDate(constraint.startDate),
                    style: const TextStyle(fontSize: 14),
                  ),
                  // Show time range if specified
                  if (constraint.startTime != null && constraint.endTime != null)
                    Text(
                      'שעות: ${constraint.startTime}-${constraint.endTime}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  // Show event time for context
                  if (_selectedEvent!.assemblyTime.isNotEmpty)
                    Text(
                      'שעת התייצבות לאירוע: ${_selectedEvent!.assemblyTime}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      )).toList();
    }

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('אזהרת סתירה'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(warningMessage),
              if (constraintDetails.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...constraintDetails,
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:cancel:constraintWarning', {'memberId': teamMember.id});
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                Logger.action('tap:confirmAssignDespiteWarning', {'memberId': teamMember.id});
                Navigator.of(dialogContext).pop();
                setState(() {
                  _selectedTeamMember = teamMember;
                });
                // Auto-advance to next step
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      _currentStep = 2;
                      // Clear role search when entering step 3
                      _roleSearchController.clear();
                      _roleSearchQuery = '';
                    });
                  }
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('שבץ בכל זאת'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _selectedEvent != null;
      case 1:
        return _selectedTeamMember != null;
      case 2:
        return _selectedRole != null;
      default:
        return false;
    }
  }

  void _nextStep() {
    setState(() {
      _currentStep++;
    });
  }

  void _previousStep() {
    setState(() {
      _currentStep--;
    });
  }

  void _finish() {
    if (_selectedEvent != null && _selectedTeamMember != null && _selectedRole != null) {
      Navigator.of(context).pop({
        'event': _selectedEvent!,
        'teamMember': _selectedTeamMember!,
        'roleType': _selectedRole!.key,
      });
    }
  }

  /// Format event dates in Hebrew (like user/assignments screen)
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

  /// Get full Hebrew day name (e.g., "ראשון", "שני")
  String _getFullHebrewDayName(int weekday) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    return days[weekday];
  }

  /// Get Hebrew month name (e.g., "פברואר")
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
      final strippedLocation = MapLocationResult.stripCoordinates(location);
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }
}