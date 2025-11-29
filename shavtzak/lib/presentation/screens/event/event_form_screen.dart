import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/utils/validators.dart';
import '../../../domain/entities/event.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';

class EventFormScreen extends StatefulWidget {
  final Event? event;

  const EventFormScreen({super.key, this.event});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _assemblyTimeController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _requiresArmed = false;
  Map<RoleType, int> _roleRequirements = {};

  bool get _isEditMode => widget.event != null;

  @override
  void initState() {
    super.initState();
    for (final role in RoleType.values) {
      _roleRequirements[role] = 0;
    }
    if (_isEditMode) {
      _nameController.text = widget.event!.name;
      _locationController.text = widget.event!.location;
      _notesController.text = widget.event!.notes;
      _startTimeController.text = widget.event!.startTime;
      _endTimeController.text = widget.event!.endTime;
      _assemblyTimeController.text = widget.event!.assemblyTime;
      _startDate = widget.event!.startDate;
      _endDate = widget.event!.endDate;
      _requiresArmed = widget.event!.requiresArmed;
      _roleRequirements = Map.from(widget.event!.roleRequirements);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _assemblyTimeController.dispose();
    super.dispose();
  }

  void _saveEvent() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לבחור תאריך התחלה'), backgroundColor: Colors.orange),
      );
      return;
    }

    final now = DateTime.now();
    final event = Event(
      id: _isEditMode ? widget.event!.id : const Uuid().v4(),
      name: _nameController.text.trim(),
      startDate: _startDate!,
      endDate: _endDate ?? _startDate!,
      startTime: _startTimeController.text.trim(),
      endTime: _endTimeController.text.trim(),
      assemblyTime: _assemblyTimeController.text.trim(),
      location: _locationController.text.trim(),
      requiresArmed: _requiresArmed,
      notes: _notesController.text.trim(),
      roleRequirements: _roleRequirements,
      createdAt: _isEditMode ? widget.event!.createdAt : now,
      updatedAt: now,
    );

    if (_isEditMode) {
      context.read<EventBloc>().add(UpdateEvent(event));
    } else {
      context.read<EventBloc>().add(CreateEvent(event));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EventBloc, EventState>(
      listener: (context, state) {
        if (state is EventOperationSuccess) {
          Navigator.pop(context);
        } else if (state is EventError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_isEditMode ? 'עריכת אירוע' : 'הוספת אירוע'),
            actions: [
              TextButton(
                onPressed: _saveEvent,
                child: const Text(AppStrings.save, style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          body: BlocBuilder<EventBloc, EventState>(
            builder: (context, state) {
              if (state is EventOperating) {
                return const Center(child: CircularProgressIndicator());
              }
              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'שם האירוע',
                        hintText: 'לדוגמה: חתונת כהן',
                        prefixIcon: Icon(Icons.event),
                      ),
                      validator: Validators.validateName,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'מיקום',
                        hintText: 'לדוגמה: אולמי ורסאי',
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'שדה חובה' : null,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text(_startDate == null
                          ? 'תאריך התחלה'
                          : 'תאריך התחלה: ${_formatDate(_startDate!)}'),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() => _startDate = date);
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text(_endDate == null
                          ? 'תאריך סיום (אופציונלי)'
                          : 'תאריך סיום: ${_formatDate(_endDate!)}'),
                      trailing: _endDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _endDate = null),
                            )
                          : const Icon(Icons.arrow_drop_down),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _endDate ?? _startDate ?? DateTime.now(),
                          firstDate: _startDate ?? DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() => _endDate = date);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _startTimeController,
                      decoration: const InputDecoration(
                        labelText: 'שעת התחלה',
                        hintText: 'לדוגמה: 18:00',
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'שדה חובה' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _endTimeController,
                      decoration: const InputDecoration(
                        labelText: 'שעת סיום',
                        hintText: 'לדוגמה: 23:00',
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'שדה חובה' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _assemblyTimeController,
                      decoration: const InputDecoration(
                        labelText: 'שעת התייצבות',
                        hintText: 'לדוגמה: 17:00',
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'שדה חובה' : null,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('דרוש חמוש'),
                      value: _requiresArmed,
                      onChanged: (v) => setState(() => _requiresArmed = v),
                    ),
                    const Divider(height: 32),
                    const Text('תפקידים נדרשים', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...RoleType.values.map((role) {
                      return ListTile(
                        title: Text(role.hebrewName),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                if (_roleRequirements[role]! > 0) {
                                  setState(() => _roleRequirements[role] = _roleRequirements[role]! - 1);
                                }
                              },
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                _roleRequirements[role].toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                setState(() => _roleRequirements[role] = _roleRequirements[role]! + 1);
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 32),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'הערות',
                        hintText: 'הערות נוספות על האירוע',
                        prefixIcon: Icon(Icons.notes),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
