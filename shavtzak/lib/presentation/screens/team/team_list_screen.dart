import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/constants/constraint_status.dart';
import '../../../core/state/constraint_manager.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/assignment.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/filter_persistence.dart';
import 'package:uuid/uuid.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../widgets/navigation_menu.dart';
import '../../widgets/date_picker_dialog.dart';
import '../../widgets/interactive_filter_bar.dart';
import '../../../data/repositories/assignment_repository.dart';

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

  @override
  void initState() {
    super.initState();
    // Always load ALL team members - filtering happens in UI
    context.read<TeamBloc>().add(const LoadTeamMembers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      context.read<TeamBloc>().add(const LoadTeamMembers());
    } else {
      context.read<TeamBloc>().add(SearchTeamMembers(query));
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
          actions: [
            const NavigationMenu(),
            IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchController.clear();
                    context.read<TeamBloc>().add(const LoadTeamMembers());
                  }
                });
              },
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
                    content: Text(state.message),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 1),
                  ),
                );
            } else if (state is TeamMemberOperationSuccess) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 1),
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
        context.read<TeamBloc>().add(const RefreshTeamMembers());
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
                        bloc.add(DeactivateTeamMember(member.id));
                      } else {
                        bloc.add(ReactivateTeamMember(member.id));
                      }
                      // Reload all members after operation completes
                      Future.delayed(const Duration(milliseconds: 100), () {
                        bloc.add(const LoadTeamMembers());
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
                  Text(
                    '$activeRoles תפקידים',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (member.constraints.isNotEmpty)
                    Row(
                      children: [
                        Text(
                          '${member.constraints.where((c) => c.status != ConstraintStatus.rejected).length} מגבלות',
                          style: const TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                        if (member.constraints.any((c) => c.isPending())) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${member.constraints.where((c) => c.isPending()).length} ממתינות)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Text(
                      '0 מגבלות',
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
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
                context.read<TeamBloc>().add(DeleteTeamMember(member.id));
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
              context.read<TeamBloc>().add(const LoadTeamMembers());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
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
  final _commentsController = TextEditingController();

  bool _isActive = true;
  bool _isPermanent = false;
  Map<RoleType, bool> _roleCapabilities = {};

  late TeamBloc _teamBloc;
  List<DateConstraint> _constraints = [];
  bool _isDirty = false;
  String? _roleError; // Track role validation error

  // Hybrid constraint state manager
  LocalConstraintManager? _constraintManager;

  
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
      _commentsController.text = widget.member!.comments;
      _isActive = widget.member!.isActive;
      _isPermanent = widget.member!.isPermanent;
      _roleCapabilities = Map.from(widget.member!.roleCapabilities);
      _constraints = List.from(widget.member!.constraints);

      // Initialize constraint manager with existing constraints
      _constraintManager = LocalConstraintManager();
      _constraintManager!.initializeFromDatabase(_constraints);

      // Initialize constraint manager in BLoC
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<TeamBloc>().add(InitializeConstraintManager(
          teamMemberId: widget.member!.id,
          databaseConstraints: _constraints,
        ));
      });
    }

    // Track dirty state
    _nameController.addListener(() => _isDirty = true);
    _commentsController.addListener(() => _isDirty = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _teamBloc = context.read<TeamBloc>();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commentsController.dispose();

    // Clean up constraint manager if editing
    if (_isEditMode && _constraintManager != null) {
      _teamBloc.add(ClearLocalConstraintState(
        teamMemberId: widget.member!.id,
      ));
    }

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

    // Use effective constraints from constraint manager
    final finalConstraints = _constraintManager?.getEffectiveConstraints() ?? _constraints;

    final now = DateTime.now();
    final member = TeamMember(
      id: _isEditMode ? widget.member!.id : const Uuid().v4(),
      uniqueKey: _isEditMode ? widget.member!.uniqueKey : const Uuid().v4(),
      name: _nameController.text.trim(),
      isActive: _isActive,
      isPermanent: _isPermanent,
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
      bloc.add(UpdateTeamMember(member));
    } else {
      bloc.add(CreateTeamMember(member));
    }

    // Reload all team members after operation completes (filtering happens in UI)
    Future.delayed(const Duration(milliseconds: 100), () {
      bloc.add(const LoadTeamMembers());
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

        // Check if any constraint conflicts with the assignment's event date
        for (final constraint in member.constraints) {
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
                        final eventDate = assignment.event?.startDate;
                        final dateStr = eventDate != null
                            ? '${eventDate.day}/${eventDate.month}/${eventDate.year}'
                            : '';
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
                                          bloc.add(DeleteTeamMember(widget.member!.id));
                                          // Reload all team members after operation completes (filtering happens in UI)
                                          Future.delayed(const Duration(milliseconds: 100), () {
                                            bloc.add(const LoadTeamMembers());
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
                        // Update constraint manager BEFORE any UI rebuilds
                        // This ensures the rejected constraints dialog sees the updated state
                        if (_isEditMode && state is TeamLoaded) {
                          final updatedMember = state.members.cast<TeamMember?>().firstWhere(
                            (member) => member?.id == widget.member!.id,
                            orElse: () => null,
                          );
                          if (updatedMember != null) {
                            // Always sync with DB updates to clear local changes for updated constraints
                            // DB updates override local changes per the business logic:
                            // - If a constraint was updated in DB, clear its local modifications
                            // - If a constraint was NOT updated in DB, keep its local modifications
                            _constraints = List.from(updatedMember.constraints);

                            // Use syncWithDatabaseChanges to intelligently handle updates
                            // This clears local modifications only for constraints that changed in DB
                            _constraintManager?.syncWithDatabaseChanges(_constraints);

                            // Force rebuild to propagate changes to dialogs
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

                              // Date constraints section
                              Row(
                                children: [
                                  const Text(
                                    'מגבלות זמן',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Constraints list
                              ..._buildVisibleConstraintsList(),

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
    // Use the constraint status directly (already effective from constraint manager)
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _approveConstraint(String constraintId) {
    if (widget.member == null || _constraintManager == null) return;

    // Update local constraint manager for immediate UI feedback
    _constraintManager!.updateConstraintStatus(constraintId, ConstraintStatus.approved);
    _isDirty = true;

    // Also update BLoC for state consistency
    context.read<TeamBloc>().add(UpdateConstraintStatusLocal(
      teamMemberId: widget.member!.id,
      constraintId: constraintId,
      newStatus: ConstraintStatus.approved,
    ));

    setState(() {});
  }

  void _rejectConstraint(String constraintId) {
    if (widget.member == null || _constraintManager == null) return;

    // Update local constraint manager for immediate UI feedback
    _constraintManager!.updateConstraintStatus(constraintId, ConstraintStatus.rejected);
    _isDirty = true;

    // Also update BLoC for state consistency
    context.read<TeamBloc>().add(UpdateConstraintStatusLocal(
      teamMemberId: widget.member!.id,
      constraintId: constraintId,
      newStatus: ConstraintStatus.rejected,
    ));

    setState(() {});
  }

  void _setPendingConstraint(String constraintId) {
    if (widget.member == null || _constraintManager == null) return;

    // Update local constraint manager for immediate UI feedback
    _constraintManager!.updateConstraintStatus(constraintId, ConstraintStatus.pending);
    _isDirty = true;

    // Also update BLoC for state consistency
    context.read<TeamBloc>().add(UpdateConstraintStatusLocal(
      teamMemberId: widget.member!.id,
      constraintId: constraintId,
      newStatus: ConstraintStatus.pending,
    ));

    setState(() {});
  }

  List<Widget> _buildVisibleConstraintsList() {
    // Get effective constraints from constraint manager
    final effectiveConstraints = _constraintManager?.getEffectiveConstraints() ?? _constraints;

    final visibleConstraints = effectiveConstraints.where((constraint) {
      // Hide rejected constraints from admin view (they'll have a separate button)
      return constraint.status != ConstraintStatus.rejected;
    }).toList();

    final rejectedConstraints = effectiveConstraints.where((constraint) {
      // Only show constraints that are rejected
      return constraint.status == ConstraintStatus.rejected;
    }).toList();

    if (visibleConstraints.isEmpty && rejectedConstraints.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'אין מגבלות זמן',
            style: TextStyle(color: Colors.grey),
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
          getEffectiveConstraints: () => _constraintManager?.getEffectiveConstraints() ?? [],
          onApproveConstraint: (constraintId) => _approveConstraint(constraintId),
          onRejectConstraint: (constraintId) => _rejectConstraint(constraintId),
          onSetPendingConstraint: (constraintId) => _setPendingConstraint(constraintId),
        ),
      ),
    );
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
                                      constraint.endDate != null
                                          ? '${_formatDate(constraint.startDate)} - ${_formatDate(constraint.endDate!)}'
                                          : _formatDate(constraint.startDate),
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  _buildStatusBadge(effectiveStatus),
                                ],
                              ),
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
    }).toList();
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
