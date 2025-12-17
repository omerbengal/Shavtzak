import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/environment_service.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../bloc/event/event_bloc.dart';
import '../../../bloc/event/event_event.dart';
import '../../../bloc/event/event_state.dart';
import '../../../bloc/user_selection/user_selection_bloc.dart';
import '../../../widgets/date_picker_dialog.dart';

class EventDuplicationModal extends StatefulWidget {
  final Event event;

  const EventDuplicationModal({
    super.key,
    required this.event,
  });

  @override
  State<EventDuplicationModal> createState() => _EventDuplicationModalState();
}

class _EventDuplicationModalState extends State<EventDuplicationModal> {
  late DateTime _startDate;
  late DateTime _endDate;
  late TextEditingController _startTimeController;
  late TextEditingController _endTimeController;
  late TextEditingController _assemblyTimeController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _startDate = widget.event.startDate;
    _endDate = widget.event.endDate;
    _startTimeController = TextEditingController(text: widget.event.startTime);
    _endTimeController = TextEditingController(text: widget.event.endTime);
    _assemblyTimeController = TextEditingController(text: widget.event.assemblyTime);
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    _endTimeController.dispose();
    _assemblyTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocConsumer<EventBloc, EventState>(
        listener: (context, state) {
          if (state is EventOperationSuccess) {
            Navigator.of(context).pop();
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
          } else if (state is EventDuplicatedWithConflicts) {
            Navigator.of(context).pop();
            _showConflictDialog(state);
          } else if (state is EventError) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text(state.message),
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
          }
        },
        builder: (context, state) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            const Icon(Icons.copy, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'שכפול אירוע: ${widget.event.name}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Scrollable content
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Date selection
                                Text(
                                  'תאריכים',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: _selectStartDate,
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: 'תאריך התחלה',
                                            border: OutlineInputBorder(),
                                            suffixIcon: Icon(Icons.calendar_today),
                                          ),
                                          child: Text(
                                            _formatDate(_startDate),
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: InkWell(
                                        onTap: _selectEndDate,
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: 'תאריך סיום',
                                            border: OutlineInputBorder(),
                                            suffixIcon: Icon(Icons.calendar_today),
                                          ),
                                          child: Text(
                                            _formatDate(_endDate),
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Time fields
                                Text(
                                  'שעות',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _assemblyTimeController,
                                        decoration: const InputDecoration(
                                          labelText: 'שעת התייצבות',
                                          border: OutlineInputBorder(),
                                          hintText: 'HH:mm',
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'שדה חובה';
                                          }
                                          if (!RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
                                            return 'פורמט שגוי (HH:mm)';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _startTimeController,
                                        decoration: const InputDecoration(
                                          labelText: 'שעת התחלה',
                                          border: OutlineInputBorder(),
                                          hintText: 'HH:mm',
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'שדה חובה';
                                          }
                                          if (!RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
                                            return 'פורמט שגוי (HH:mm)';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _endTimeController,
                                        decoration: const InputDecoration(
                                          labelText: 'שעת סיום',
                                          border: OutlineInputBorder(),
                                          hintText: 'HH:mm',
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'שדה חובה';
                                          }
                                          if (!RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
                                            return 'פורמט שגוי (HH:mm)';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Info section
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'מידע על השכפול:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text('• כל שדות האירוע ישוכפלו כפי שהם'),
                                      const Text('• כל השיבוצים ישוכפלו לאירוע החדש'),
                                      const Text('• יבוצע בדיקת התנגשויות עם אילוצי זמינות'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Actions
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('ביטול'),
                            ),
                            if (state is! EventLoading)
                              ElevatedButton.icon(
                                onPressed: _duplicateEvent,
                                icon: const Icon(Icons.copy),
                                label: const Text('שכפל אירוע'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              )
                            else
                              const SizedBox(
                                width: 120,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectStartDate() async {
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (context) => DatePickerDialog(
        initialDate: _startDate,
        firstDate: DateTime.now(),
        lastDate: DateTime(2100),
      ),
    );

    if (selected != null) {
      setState(() {
        _startDate = selected;
        // Ensure end date is not before start date
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  void _selectEndDate() async {
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (context) => DatePickerDialog(
        initialDate: _endDate,
        firstDate: _startDate,
        lastDate: DateTime(2100),
      ),
    );

    if (selected != null) {
      setState(() {
        _endDate = selected;
      });
    }
  }

  void _duplicateEvent() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<EventBloc>().add(DuplicateEvent(
        eventId: widget.event.id,
        newName: widget.event.name,
        newLocation: widget.event.location,
        newComments: widget.event.comments,
        newStartDate: _startDate,
        newEndDate: _endDate,
        newStartTime: _startTimeController.text,
        newEndTime: _endTimeController.text,
        newAssemblyTime: _assemblyTimeController.text,
        newRequiresArmed: widget.event.requiresArmed,
        newRoleRequirements: widget.event.roleRequirements,
        duplicateAssignments: true,
      ));
    }
  }

  void _showConflictDialog(EventDuplicatedWithConflicts state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('האירוע שוכפל עם התנגשויות'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'האירוע "${state.duplicatedEvent.name}" שוכפל בהצלחה, אך יש התנגשויות בשיבוצים:',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: state.assignmentConflicts.length,
                    itemBuilder: (context, index) {
                      final conflict = state.assignmentConflicts[index];
                      return Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${conflict.teamMemberName} - ${conflict.roleName}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              ...conflict.conflictReasons.map(
                                (reason) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ', style: TextStyle(color: Colors.red)),
                                      Expanded(child: Text(reason)),
                                    ],
                                  ),
                                ),
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
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to the duplicated event
                final envPrefix = EnvironmentService.instance.routePrefix;
                context.go('$envPrefix/admin/events');
              },
              child: const Text('לצפייה באירועים'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}