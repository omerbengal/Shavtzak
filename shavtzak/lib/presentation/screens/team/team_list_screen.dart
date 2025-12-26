import 'package:flutter/material.dart';
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
import '../../../domain/entities/assignment.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/phone_input_formatter.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../core/services/environment_service.dart';
import 'package:uuid/uuid.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart' as team;
import '../../bloc/team/team_state.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/navigation_menu.dart';
import '../../widgets/date_picker_dialog.dart';
import '../../widgets/interactive_filter_bar.dart';
import '../../widgets/swipeable_page_view.dart';
import '../../widgets/admin_passcode_dialog.dart';
import '../../../data/repositories/user_selection_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../bloc/calendar_sync/calendar_sync_bloc.dart';
import '../../bloc/calendar_sync/calendar_sync_event.dart';
import '../../bloc/calendar_sync/calendar_sync_state.dart';
import 'dart:async';

// Filter enum for team members (0=all, 1=active, 2=inactive)
enum TeamFilter { all, active, inactive }

class TeamListScreen extends StatefulWidget {
  const TeamListScreen({super.key});

  @override
  State<TeamListScreen> createState() => _TeamListScreenState();
}

class _TeamListScreenState extends State<TeamListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  TeamLoaded? _lastLoadedState;
  bool _hasTriggeredInitialSync = false;

  @override
  void initState() {
    super.initState();
    // Always load ALL team members - filtering happens in UI
    context.read<TeamBloc>().add(const team.LoadTeamMembers());
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
    // Unregister callback
    onTeamPageVisible = null;
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      context.read<TeamBloc>().add(const team.LoadTeamMembers());
    } else {
      context.read<TeamBloc>().add(team.SearchTeamMembers(query));
    }
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: _showSearch
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'חיפוש חבר צוות...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black54),
                  ),
                  style: const TextStyle(color: Colors.black),
                  onChanged: _onSearchChanged,
                )
              : const Text(AppStrings.team),
          leading: IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search),
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                context.read<TeamBloc>().add(const team.LoadTeamMembers());
              }
            });
          },
        ),
        actions: [
          // Sync button (appears closest to title in RTL)
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
                return IconButton(
                  icon: isInProgress
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync),
                  onPressed: isInProgress
                      ? null
                      : () {
                          context.read<CalendarSyncBloc>().add(const PerformBidirectionalSync());
                        },
                  tooltip: 'סנכרון עם יומן גוגל',
                  iconSize: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
                );
              },
            ),
          ),
          // Home button (appears middle from left in RTL)
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'בית',
            onPressed: () {
              final envPrefix = EnvironmentService.instance.routePrefix;
              context.go('$envPrefix/admin');
            },
            iconSize: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
          ),
          // Logout button (appears farthest left in RTL)
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'התנתק',
            onPressed: () => _logout(context),
            iconSize: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
          ),
        ],
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
              FilterOption(label: 'פעילים', count: state.activeCount.toString()),
              FilterOption(label: 'לא פעילים', count: state.inactiveCount.toString()),
            ],
            selectedIndex: FilterPersistence.teamFilterIndex,
            onFilterChanged: _onFilterChanged,
          ),
          // Team list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: filteredMembers.length,
              itemBuilder: (context, index) {
                final member = filteredMembers[index];
                return _buildTeamMemberCard(member);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Filter members based on selected filter index
  List<TeamMember> _filterMembers(List<TeamMember> members, int filterIndex) {
    switch (filterIndex) {
      case 0: // All
        return members;
      case 1: // Active
        return members.where((m) => m.isActive).toList();
      case 2: // Inactive
        return members.where((m) => !m.isActive).toList();
      default:
        return members;
    }
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
              // Header row with avatar, name, and activate/deactivate button
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
                    child: Text(
                      member.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: member.isActive ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                  // Activate/Deactivate button
                  IconButton(
                    icon: Icon(
                      member.isActive ? Icons.check_circle : Icons.cancel,
                      color: member.isActive ? Colors.green : Colors.grey,
                    ),
                    onPressed: () {
                      final bloc = context.read<TeamBloc>();
                      if (member.isActive) {
                        bloc.add(team.DeactivateTeamMember(member.id));
                      } else {
                        bloc.add(team.ReactivateTeamMember(member.id));
                      }
                      // Reload all members after operation completes
                      Future.delayed(const Duration(milliseconds: 100), () {
                        bloc.add(const team.LoadTeamMembers());
                      });
                    },
                    tooltip: member.isActive ? 'השבת' : 'הפעל',
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
                  const SizedBox(height: 2),
                  Text(
                    '$activeRoles תפקידים',
                    style: const TextStyle(fontSize: 12),
                  ),
                  // Check if member has any relevant constraints (unavailability for permanent, availability for non-permanent)
                  Builder(
                    builder: (context) {
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

                      // Filter out past constraints and by constraint type before counting
                      final activeConstraints = member.constraints
                          .where((c) => !isPastConstraint(c))
                          .where((c) => member.isPermanent ? c.isUnavailability : c.isAvailability)
                          .toList();
                      final approvedCount = activeConstraints.where((c) => c.isApproved()).length;
                      final pendingCount = activeConstraints.where((c) => c.isPending()).length;

                      if (activeConstraints.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      // If has approved constraints, show both counters as before
                      if (approvedCount > 0) {
                        return Row(
                          children: [
                            Text(
                              member.isPermanent
                                  ? '$approvedCount מגבלות'
                                  : '$approvedCount תאריכי זמינות',
                              style: TextStyle(
                                fontSize: 12,
                                color: member.isPermanent ? Colors.orange : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (pendingCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '($pendingCount ממתינות)',
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
                        // If no approved constraints but has pending, show only pending counter in red
                        return Text(
                          member.isPermanent
                              ? '$pendingCount מגבלות ממתינות'
                              : '$pendingCount ממתינות',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      } else {
                        // No approved or pending constraints (shouldn't happen with activeConstraints.isEmpty check)
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

  // Birthday fields
  int? _birthdayDay;
  int? _birthdayMonth;
  int? _birthdayYear;

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
  Map<RoleType, bool> _roleCapabilities = {};

  late TeamBloc _teamBloc;
  List<DateConstraint> _constraints = [];
  bool _isDirty = false;
  String? _roleError; // Track role validation error

    bool get _isEditMode => widget.member != null;

  @override
  void initState() {
    super.initState();

    // Initialize role capabilities with all roles set to false
    for (final role in RoleType.values) {
      _roleCapabilities[role] = false;
    }

    // Load existing member data if editing
    if (_isEditMode) {
      _nameController.text = widget.member!.name;
      _phoneController.text = widget.member!.phoneNumber ?? '';
      _commentsController.text = widget.member!.comments;
      _isActive = widget.member!.isActive;
      _isPermanent = widget.member!.isPermanent;
      _allowMultipleAssignments = widget.member!.allowMultipleAssignments;
      _roleCapabilities = Map.from(widget.member!.roleCapabilities);
      _constraints = List.from(widget.member!.constraints);
      if (widget.member!.birthday != null) {
        _birthdayDay = widget.member!.birthday!.day;
        _birthdayMonth = widget.member!.birthday!.month;
        _birthdayYear = widget.member!.birthday!.year;
        _updateBirthdayController();
      }
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
    super.dispose();
  }

  Future<void> _saveMember() async {
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
      isActive: _isActive,
      isPermanent: _isPermanent,
      allowMultipleAssignments: _allowMultipleAssignments,
      constraints: finalConstraints,
      roleCapabilities: _roleCapabilities,
      comments: _commentsController.text.trim(),
      createdAt: _isEditMode ? widget.member!.createdAt : now,
      updatedAt: now,
      isAdmin: _isEditMode ? widget.member!.isAdmin : false,
    );

    // Check for conflicting assignments if editing and constraints changed
    if (_isEditMode && _constraintsChanged()) {
      final conflictingAssignments = await _getConflictingAssignments(member);

      if (conflictingAssignments.isNotEmpty) {
        // Show warning dialog
        final action = await _showConflictWarningDialog(conflictingAssignments);

        if (action == null) {
          // User cancelled, don't save
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
      builder: (dialogContext) => Directionality(
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
                        final roleName = assignment.roleType.hebrewName;

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
                  child: Container(
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
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
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
                                          final bloc = context.read<TeamBloc>();
                                          bloc.add(team.DeleteTeamMember(widget.member!.id));
                                          // Reload all team members after operation completes (filtering happens in UI)
                                          Future.delayed(const Duration(milliseconds: 100), () {
                                            bloc.add(const team.LoadTeamMembers());
                                          });
                                          Navigator.of(dialogContext).pop(); // Close dialog
                                          widget.onSuccess(); // Close modal
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            tooltip: 'מחק',
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
                                decoration: const InputDecoration(
                                  labelText: 'שם חבר הצוות',
                                  hintText: 'הזן שם מלא',
                                  prefixIcon: Icon(Icons.person),
                                  border: OutlineInputBorder(),
                                ),
                                validator: Validators.validateName,
                                textDirection: TextDirection.rtl,
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

                              const Divider(height: 32),

                              // Role capabilities section
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
                                        for (final role in RoleType.values) {
                                          _roleCapabilities[role] = true;
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
                                        for (final role in RoleType.values) {
                                          _roleCapabilities[role] = false;
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
                              Container(
                                decoration: _roleError != null
                                    ? BoxDecoration(
                                        border: Border.all(color: Colors.red.shade700),
                                        borderRadius: BorderRadius.circular(4),
                                        color: Colors.red.shade50,
                                      )
                                    : null,
                                child: Column(
                                  children: RoleType.values.map((role) {
                                    return CheckboxListTile(
                                      title: Text(role.hebrewName),
                                      value: _roleCapabilities[role] ?? false,
                                      onChanged: (value) {
                                        setState(() {
                                          _roleCapabilities[role] = value ?? false;
                                          _roleError = null; // Clear error when user interacts
                                          _isDirty = true;
                                        });
                                      },
                                      controlAffinity: ListTileControlAffinity.leading,
                                    );
                                  }).toList(),
                                ),
                              ),

                              const Divider(height: 32),

                              // Date constraints/availability section
                              Row(
                                children: [
                                  Text(
                                    _isPermanent ? 'מגבלות זמן' : 'זמינות',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _isPermanent ? null : Colors.green[700],
                                    ),
                                  ),
                                  const Spacer(),
                                  // Show rejected constraints button only for permanent members with unavailability constraints
                                  if (_isPermanent && _constraints.any((c) => c.isUnavailability && c.status == ConstraintStatus.rejected))
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
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Helper text
                              Text(
                                _isPermanent
                                    ? 'כאן תוכל לאשר או לדחות בקשות מגבלות מחברי צוות קבועים. מגבלות מאושרות ימנעו שיבוץ לאירועים.'
                                    : 'זמינות שסימן/ה חבר הצוות הזה. זמינות פעילה מאפשרת שיבוץ לאירועים.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),

                              const SizedBox(height: 8),

                              // Constraints/Availability list
                              ..._buildVisibleConstraintsList(),

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
                                textDirection: TextDirection.rtl,
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
                            onPressed: _saveMember,
                            child: const Text('שמור'),
                          ),
                        ),
                      ],
                    ),
                  ),
                      ],
                    ),
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
            subtitle: constraint.note != null && constraint.note!.isNotEmpty
                ? Text(
                    constraint.note!,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  )
                : null,
            trailing: null, // Admins cannot delete constraints
            onTap: null, // Admins cannot edit constraints
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
                Text(
                  availability.endDate != null && !_isSameDay(availability.startDate, availability.endDate!)
                      ? '${_formatDate(availability.startDate)} - ${_formatDate(availability.endDate!)}'
                      : _formatDate(availability.startDate),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
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

    final rejectedConstraints = _constraints.where((constraint) {
      // Only show constraints that are rejected AND match the constraint type for this member
      if (_isPermanent && constraint.isAvailability) return false; // Permanent members only see unavailability
      if (!_isPermanent && constraint.isUnavailability) return false; // Non-permanent members only see availability

      return constraint.status == ConstraintStatus.rejected;
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    if (visibleConstraints.isEmpty && rejectedConstraints.isEmpty) {
      return [
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
        )
      ];
    }

    final widgets = <Widget>[];

    // Add visible constraints
    if (visibleConstraints.isNotEmpty) {
      widgets.addAll(visibleConstraints.map((constraint) {
        return _buildConstraintCard(constraint);
      }).toList());
    }

    // Add rejected constraints button if any exist
    if (rejectedConstraints.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => _showRejectedConstraints(rejectedConstraints),
            icon: const Icon(Icons.visibility_off, size: 18),
            label: Text(
              'הצג מגבלות שנדחו (${rejectedConstraints.length})',
              style: const TextStyle(fontSize: 14),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[600],
              side: BorderSide(color: Colors.grey[300]!),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ),
      );
    }

    return widgets;
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

  // Admins cannot add or edit constraints - only approve/reject
  // void _addConstraint() async {
  //   final result = await showDialog<DateConstraint>(
  //     context: context,
  //     builder: (context) => const _ConstraintDialog(),
  //   );

  //   if (result != null) {
  //     setState(() {
  //       _constraints.add(result);
  //       _isDirty = true;
  //     });
  //   }
  // }

  // void _editConstraint(DateConstraint constraint, int index) async {
  //   final result = await showDialog<DateConstraint>(
  //     context: context,
  //     builder: (context) => _ConstraintDialog(constraint: constraint),
  //   );

  //   if (result != null) {
  //     setState(() {
  //       _constraints[index] = result;
  //       _isDirty = true;
  //     });
  //   }
  // }
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

  @override
  void initState() {
    super.initState();
    if (widget.constraint != null) {
      _startDate = widget.constraint!.startDate;
      _endDate = widget.constraint!.endDate;
      _noteController.text = widget.constraint!.note ?? '';
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
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

// Separate widget for rejected constraints dialog to avoid infinite loop
class _RejectedConstraintsDialog extends StatefulWidget {
  final String teamMemberId;
  final List<DateConstraint> Function() getEffectiveConstraints;
  final Function(String) onApproveConstraint;
  final Function(String) onRejectConstraint;
  final Function(String) onSetPendingConstraint;

  const _RejectedConstraintsDialog({
    required this.teamMemberId,
    required this.getEffectiveConstraints,
    required this.onApproveConstraint,
    required this.onRejectConstraint,
    required this.onSetPendingConstraint,
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
