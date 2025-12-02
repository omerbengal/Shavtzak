import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/assignment.dart';
import '../../../core/utils/validators.dart';
import 'package:uuid/uuid.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../widgets/navigation_menu.dart';
import '../../widgets/date_picker_dialog.dart';
import '../../../data/repositories/assignment_repository.dart';

class TeamListScreen extends StatefulWidget {
  const TeamListScreen({super.key});

  @override
  State<TeamListScreen> createState() => _TeamListScreenState();
}

class _TeamListScreenState extends State<TeamListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  bool _showActiveOnly = false;
  TeamLoaded? _lastLoadedState;

  @override
  void initState() {
    super.initState();
    // Load team members on init
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          leading: const NavigationMenu(),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _showActiveOnly = !_showActiveOnly;
                  });
                  if (_showActiveOnly) {
                    context.read<TeamBloc>().add(const LoadActiveTeamMembers());
                  } else {
                    context.read<TeamBloc>().add(const LoadTeamMembers());
                  }
                },
                style: OutlinedButton.styleFrom(
                  backgroundColor: _showActiveOnly ? Colors.green : Colors.white,
                  foregroundColor: _showActiveOnly ? Colors.white : Colors.black,
                  side: BorderSide(
                    color: _showActiveOnly ? Colors.green : Colors.grey,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('הצג פעילים בלבד'),
              ),
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
                  ),
                );
            } else if (state is TeamMemberOperationSuccess) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.green,
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
              return _buildEmptyState(state.message);
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

            return _buildEmptyState('טוען...');
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
    return RefreshIndicator(
      onRefresh: () async {
        context.read<TeamBloc>().add(const RefreshTeamMembers());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          // Statistics header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('סך הכל', state.totalCount.toString()),
                _buildStatItem('פעילים', state.activeCount.toString()),
                _buildStatItem('לא פעילים', state.inactiveCount.toString()),
              ],
            ),
          ),
          // Team list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: state.members.length,
              itemBuilder: (context, index) {
                final member = state.members[index];
                return _buildTeamMemberCard(member);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
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
                      if (member.isActive) {
                        context.read<TeamBloc>().add(DeactivateTeamMember(member.id));
                      } else {
                        context.read<TeamBloc>().add(ReactivateTeamMember(member.id));
                      }
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
                    Text(
                      '${member.constraints.length} מגבלות',
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

  Widget _buildEmptyState(String message) {
    return Center(
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
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              _showTeamMemberFormModal(null);
            },
            icon: const Icon(Icons.add),
            label: const Text('הוסף חבר צוות ראשון'),
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
  final VoidCallback onSuccess;

  const _TeamMemberFormModal({
    this.member,
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
      _commentsController.text = widget.member!.comments;
      _isActive = widget.member!.isActive;
      _isPermanent = widget.member!.isPermanent;
      _roleCapabilities = Map.from(widget.member!.roleCapabilities);
      _constraints = List.from(widget.member!.constraints);
    }

    // Track dirty state
    _nameController.addListener(() => _isDirty = true);
    _commentsController.addListener(() => _isDirty = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commentsController.dispose();
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

    final now = DateTime.now();
    final member = TeamMember(
      id: _isEditMode ? widget.member!.id : const Uuid().v4(),
      name: _nameController.text.trim(),
      isActive: _isActive,
      isPermanent: _isPermanent,
      constraints: _constraints,
      roleCapabilities: _roleCapabilities,
      comments: _commentsController.text.trim(),
      createdAt: _isEditMode ? widget.member!.createdAt : now,
      updatedAt: now,
    );

    // Check for conflicting assignments if editing and constraints changed
    if (_isEditMode && _constraintsChanged()) {
      final conflictingAssignments = await _getConflictingAssignments(member);

      if (conflictingAssignments.isNotEmpty) {
        // Show warning dialog
        final confirmed = await _showConflictWarningDialog(conflictingAssignments);

        if (confirmed != true) {
          // User cancelled, don't save
          return;
        }

        // User confirmed, delete conflicting assignments
        final assignmentBloc = context.read<AssignmentBloc>();
        for (final assignment in conflictingAssignments) {
          assignmentBloc.add(DeleteAssignment(assignment.id));
        }

        // Wait a moment for deletions to process
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    if (_isEditMode) {
      context.read<TeamBloc>().add(UpdateTeamMember(member));
    } else {
      context.read<TeamBloc>().add(CreateTeamMember(member));
    }

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
      debugPrint('Error getting conflicting assignments: $e');
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
                  'האם ברצונך למחוק את השיבוצים הללו ולשמור את המגבלות?',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('מחק שיבוצים ושמור'),
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
                                          context.read<TeamBloc>().add(DeleteTeamMember(widget.member!.id));
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
                    child: BlocBuilder<TeamBloc, TeamState>(
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
                                  IconButton(
                                    onPressed: _addConstraint,
                                    icon: const Icon(Icons.add_circle),
                                    tooltip: 'הוסף מגבלה',
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Constraints list
                              if (_constraints.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'אין מגבלות זמן',
                                    style: TextStyle(color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              else
                                ..._constraints.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final constraint = entry.value;
                                  return _buildConstraintCard(constraint, index);
                                }),

                              const Divider(height: 32),

                              // Comments field
                              TextFormField(
                                controller: _commentsController,
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

  Widget _buildConstraintCard(DateConstraint constraint, int index) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_busy, color: Colors.orange),
        title: Text(
          constraint.endDate != null
              ? '${_formatDate(constraint.startDate)} - ${_formatDate(constraint.endDate!)}'
              : _formatDate(constraint.startDate),
        ),
        subtitle: constraint.note != null && constraint.note!.isNotEmpty
            ? Text(
                constraint.note!,
                style: const TextStyle(fontStyle: FontStyle.italic),
              )
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () {
            setState(() {
              _constraints.removeAt(index);
              _isDirty = true;
            });
          },
        ),
        onTap: () => _editConstraint(constraint, index),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _addConstraint() async {
    final result = await showDialog<DateConstraint>(
      context: context,
      builder: (context) => const _ConstraintDialog(),
    );

    if (result != null) {
      setState(() {
        _constraints.add(result);
        _isDirty = true;
      });
    }
  }

  void _editConstraint(DateConstraint constraint, int index) async {
    final result = await showDialog<DateConstraint>(
      context: context,
      builder: (context) => _ConstraintDialog(constraint: constraint),
    );

    if (result != null) {
      setState(() {
        _constraints[index] = result;
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
                        startDate: _startDate!,
                        endDate: _endDate,
                        note: noteText.isEmpty ? null : noteText,
                      ),
                    );
                  },
            child: const Text(AppStrings.save),
          ),
        ],
      ),
    );
  }
}
