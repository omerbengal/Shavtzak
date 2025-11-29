import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/utils/validators.dart';
import 'package:uuid/uuid.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';

class TeamListScreen extends StatefulWidget {
  const TeamListScreen({super.key});

  @override
  State<TeamListScreen> createState() => _TeamListScreenState();
}

class _TeamListScreenState extends State<TeamListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  bool _showActiveOnly = false;

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('הצג פעילים בלבד'),
                Switch(
                  value: _showActiveOnly,
                  onChanged: (value) {
                    setState(() {
                      _showActiveOnly = value;
                    });
                    if (value) {
                      context.read<TeamBloc>().add(const LoadActiveTeamMembers());
                    } else {
                      context.read<TeamBloc>().add(const LoadTeamMembers());
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        body: BlocConsumer<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            } else if (state is TeamMemberOperationSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is TeamLoading || state is TeamMemberOperating) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (state is TeamEmpty) {
              return _buildEmptyState(state.message);
            }

            if (state is TeamLoaded) {
              return _buildTeamList(state);
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
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: member.isActive ? Colors.green : Colors.grey,
          child: Text(
            member.name.isNotEmpty ? member.name[0] : '?',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          member.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: member.isActive ? Colors.black : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                _showDeleteConfirmation(member);
              },
              tooltip: 'מחק',
            ),
          ],
        ),
        onTap: () {
          _showTeamMemberFormModal(member);
        },
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
      builder: (context) => _TeamMemberFormModal(member: member),
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

  const _TeamMemberFormModal({this.member});

  @override
  State<_TeamMemberFormModal> createState() => _TeamMemberFormModalState();
}

class _TeamMemberFormModalState extends State<_TeamMemberFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _commentsController = TextEditingController();

  bool _isActive = true;
  Map<RoleType, bool> _roleCapabilities = {};
  List<DateConstraint> _constraints = [];
  bool _isDirty = false;

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

  void _saveMember() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate at least one role is selected
    if (!_roleCapabilities.values.any((selected) => selected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש לבחור לפחות תפקיד אחד'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final member = TeamMember(
      id: _isEditMode ? widget.member!.id : const Uuid().v4(),
      name: _nameController.text.trim(),
      isActive: _isActive,
      constraints: _constraints,
      roleCapabilities: _roleCapabilities,
      comments: _commentsController.text.trim(),
      createdAt: _isEditMode ? widget.member!.createdAt : now,
      updatedAt: now,
    );

    if (_isEditMode) {
      context.read<TeamBloc>().add(UpdateTeamMember(member));
    } else {
      context.read<TeamBloc>().add(CreateTeamMember(member));
    }
  }

  void _handleClose() {
    if (_isDirty) {
      showDialog(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('שינויים לא נשמרו'),
            content: const Text('האם אתה בטוח שברצונך לצאת? השינויים לא יישמרו.'),
            actions: [
              TextButton(
                child: const Text('ביטול'),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                child: const Text('צא'),
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close modal
                },
              ),
            ],
          ),
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TeamBloc, TeamState>(
      listener: (context, state) {
        if (state is TeamMemberOperationSuccess) {
          Navigator.pop(context);
        } else if (state is TeamError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Directionality(
            textDirection: TextDirection.rtl,
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
                        if (state is TeamMemberOperating) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        return Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: ListView(
                            controller: scrollController,
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: MediaQuery.of(context).viewInsets.bottom + 80,
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

                              // Comments field
                              TextFormField(
                                controller: _commentsController,
                                decoration: const InputDecoration(
                                  labelText: 'הערות',
                                  hintText: 'הערות על חבר הצוות',
                                  prefixIcon: Icon(Icons.comment),
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 3,
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

                              // Role checkboxes
                              ...RoleType.values.map((role) {
                                return CheckboxListTile(
                                  title: Text(role.hebrewName),
                                  value: _roleCapabilities[role] ?? false,
                                  onChanged: (value) {
                                    setState(() {
                                      _roleCapabilities[role] = value ?? false;
                                      _isDirty = true;
                                    });
                                  },
                                  controlAffinity: ListTileControlAffinity.leading,
                                );
                              }),

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

                              const SizedBox(height: 16),
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
  bool _isSingleDay = true;

  @override
  void initState() {
    super.initState();
    if (widget.constraint != null) {
      _startDate = widget.constraint!.startDate;
      _endDate = widget.constraint!.endDate;
      _isSingleDay = _endDate == null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.constraint == null ? 'הוספת מגבלה' : 'עריכת מגבלה'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Single day or range toggle
            SwitchListTile(
              title: const Text('יום בודד'),
              value: _isSingleDay,
              onChanged: (value) {
                setState(() {
                  _isSingleDay = value;
                  if (value) {
                    _endDate = null;
                  }
                });
              },
            ),

            const SizedBox(height: 16),

            // Start date picker
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(_startDate == null
                  ? (_isSingleDay ? 'בחר תאריך' : 'בחר תאריך התחלה')
                  : (_isSingleDay
                      ? 'תאריך: ${_formatDate(_startDate!)}'
                      : 'תאריך התחלה: ${_formatDate(_startDate!)}')),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  setState(() {
                    _startDate = date;
                  });
                }
              },
            ),

            // End date picker (if not single day)
            if (!_isSingleDay)
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(_endDate == null
                    ? 'בחר תאריך סיום'
                    : 'תאריך סיום: ${_formatDate(_endDate!)}'),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? _startDate ?? DateTime.now(),
                    firstDate: _startDate ?? DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
                    setState(() {
                      _endDate = date;
                    });
                  }
                },
              ),
          ],
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
                    if (!_isSingleDay && _endDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('יש לבחור תאריך סיום'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(
                      context,
                      DateConstraint(
                        startDate: _startDate!,
                        endDate: _isSingleDay ? null : _endDate,
                      ),
                    );
                  },
            child: const Text(AppStrings.save),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
