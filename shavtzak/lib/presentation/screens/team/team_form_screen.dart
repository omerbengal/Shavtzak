import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/utils/validators.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';

class TeamFormScreen extends StatefulWidget {
  final TeamMember? member; // null for create, non-null for edit

  const TeamFormScreen({super.key, this.member});

  @override
  State<TeamFormScreen> createState() => _TeamFormScreenState();
}

class _TeamFormScreenState extends State<TeamFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isActive = true;
  Map<RoleType, bool> _roleCapabilities = {};
  List<DateConstraint> _constraints = [];

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
      _isActive = widget.member!.isActive;
      _roleCapabilities = Map.from(widget.member!.roleCapabilities);
      _constraints = List.from(widget.member!.constraints);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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
      createdAt: _isEditMode ? widget.member!.createdAt : now,
      updatedAt: now,
    );

    if (_isEditMode) {
      context.read<TeamBloc>().add(UpdateTeamMember(member));
    } else {
      context.read<TeamBloc>().add(CreateTeamMember(member));
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
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_isEditMode ? 'עריכת חבר צוות' : 'הוספת חבר צוות'),
            actions: [
              TextButton(
                onPressed: _saveMember,
                child: const Text(
                  AppStrings.save,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          body: BlocBuilder<TeamBloc, TeamState>(
            builder: (context, state) {
              if (state is TeamMemberOperating) {
                return const Center(child: CircularProgressIndicator());
              }

              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Name field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'שם חבר הצוות',
                        hintText: 'הזן שם מלא',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: Validators.validateName,
                      textDirection: TextDirection.rtl,
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

                    const SizedBox(height: 80), // Space for FAB
                  ],
                ),
              );
            },
          ),
        ),
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
      });
    }
  }
}

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
