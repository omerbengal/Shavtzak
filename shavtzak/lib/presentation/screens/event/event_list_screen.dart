import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/utils/validators.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/event.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    context.read<EventBloc>().add(const LoadEvents());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      context.read<EventBloc>().add(const LoadEvents());
    } else {
      context.read<EventBloc>().add(SearchEvents(query));
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
                    hintText: 'חיפוש אירוע...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black54),
                  ),
                  style: const TextStyle(color: Colors.black),
                  onChanged: _onSearchChanged,
                )
              : const Text('אירועים'),
          actions: [
            IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchController.clear();
                    context.read<EventBloc>().add(const LoadEvents());
                  }
                });
              },
            ),
          ],
        ),
        body: BlocConsumer<EventBloc, EventState>(
          listener: (context, state) {
            if (state is EventError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: Colors.red),
              );
            } else if (state is EventOperationSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: Colors.green),
              );
            }
          },
          builder: (context, state) {
            if (state is EventLoading || state is EventOperating) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is EventsEmpty) {
              return _buildEmptyState(state.message);
            }
            if (state is EventsLoaded) {
              return _buildEventList(state);
            }
            if (state is EventError) {
              return _buildErrorState(state.message);
            }
            return _buildEmptyState('טוען...');
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _showEventFormModal(null);
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEventList(EventsLoaded state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<EventBloc>().add(const RefreshEvents());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('סך הכל', state.totalCount.toString()),
                _buildStatItem('קרובים', state.upcomingCount.toString()),
                _buildStatItem('פעילים', state.activeCount.toString()),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: state.events.length,
              itemBuilder: (context, index) {
                return _buildEventCard(state.events[index]);
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
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  Widget _buildEventCard(Event event) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: Text(event.name.isNotEmpty ? event.name[0] : '?', style: const TextStyle(color: Colors.white)),
        ),
        title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(_formatDate(event.startDate), style: const TextStyle(fontSize: 12)),
            Text(event.location, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (event.comments.isNotEmpty)
              Text(
                event.comments,
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () {
            _showDeleteConfirmation(event);
          },
          tooltip: 'מחק',
        ),
        onTap: () => _showEventFormModal(event),
      ),
    );
  }

  void _showEventFormModal(Event? event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _EventFormModal(event: event),
    );
  }

  void _showDeleteConfirmation(Event event) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת אירוע'),
          content: Text(
            'האם אתה בטוח שברצונך למחוק את ${event.name}?\nפעולה זו תמחק גם את כל השיבוצים.',
          ),
          actions: [
            TextButton(
              child: const Text('ביטול'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
              onPressed: () {
                context.read<EventBloc>().add(DeleteEvent(event.id));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              _showEventFormModal(null);
            },
            icon: const Icon(Icons.add),
            label: const Text('הוסף אירוע ראשון'),
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
          const Icon(Icons.error_outline, size: 80, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 18, color: Colors.red), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.read<EventBloc>().add(const LoadEvents()),
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }
}

// Event Form Modal Widget
class _EventFormModal extends StatefulWidget {
  final Event? event; // null for create, non-null for edit

  const _EventFormModal({this.event});

  @override
  State<_EventFormModal> createState() => _EventFormModalState();
}

class _EventFormModalState extends State<_EventFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _commentsController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _assemblyTimeController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _requiresArmed = false;
  Map<RoleType, int> _roleRequirements = {};
  bool _isDirty = false;

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
      _commentsController.text = widget.event!.comments;
      _startTimeController.text = widget.event!.startTime;
      _endTimeController.text = widget.event!.endTime;
      _assemblyTimeController.text = widget.event!.assemblyTime;
      _startDate = widget.event!.startDate;
      _endDate = widget.event!.endDate;
      _requiresArmed = widget.event!.requiresArmed;
      _roleRequirements = Map.from(widget.event!.roleRequirements);
    }

    _nameController.addListener(() => _isDirty = true);
    _locationController.addListener(() => _isDirty = true);
    _commentsController.addListener(() => _isDirty = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _commentsController.dispose();
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
      comments: _commentsController.text.trim(),
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
                            _isEditMode ? 'עריכת אירוע' : 'הוספת אירוע',
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
                    child: BlocBuilder<EventBloc, EventState>(
                      builder: (context, state) {
                        if (state is EventOperating) {
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
                                  labelText: 'שם האירוע',
                                  hintText: 'לדוגמה: חתונת כהן',
                                  prefixIcon: Icon(Icons.event),
                                  border: OutlineInputBorder(),
                                ),
                                validator: Validators.validateName,
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Location field
                              TextFormField(
                                controller: _locationController,
                                decoration: const InputDecoration(
                                  labelText: 'מיקום',
                                  hintText: 'לדוגמה: אולמי ורסאי',
                                  prefixIcon: Icon(Icons.location_on),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'שדה חובה' : null,
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Start Date
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
                                    setState(() {
                                      _startDate = date;
                                      _isDirty = true;
                                    });
                                  }
                                },
                              ),

                              // End Date
                              ListTile(
                                leading: const Icon(Icons.calendar_today),
                                title: Text(_endDate == null
                                    ? 'תאריך סיום (אופציונלי)'
                                    : 'תאריך סיום: ${_formatDate(_endDate!)}'),
                                trailing: _endDate != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () => setState(() {
                                          _endDate = null;
                                          _isDirty = true;
                                        }),
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
                                    setState(() {
                                      _endDate = date;
                                      _isDirty = true;
                                    });
                                  }
                                },
                              ),

                              const SizedBox(height: 16),

                              // Start Time
                              TextFormField(
                                controller: _startTimeController,
                                decoration: const InputDecoration(
                                  labelText: 'שעת התחלה (אופציונלי)',
                                  hintText: 'לדוגמה: 18:00',
                                  prefixIcon: Icon(Icons.access_time),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // End Time
                              TextFormField(
                                controller: _endTimeController,
                                decoration: const InputDecoration(
                                  labelText: 'שעת סיום (אופציונלי)',
                                  hintText: 'לדוגמה: 23:00',
                                  prefixIcon: Icon(Icons.access_time),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Assembly Time
                              TextFormField(
                                controller: _assemblyTimeController,
                                decoration: const InputDecoration(
                                  labelText: 'שעת התייצבות (אופציונלי)',
                                  hintText: 'לדוגמה: 17:00',
                                  prefixIcon: Icon(Icons.access_time),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Requires Armed
                              SwitchListTile(
                                title: const Text('דרוש חמוש'),
                                value: _requiresArmed,
                                onChanged: (v) => setState(() {
                                  _requiresArmed = v;
                                  _isDirty = true;
                                }),
                              ),

                              const Divider(height: 32),

                              // Role Requirements
                              const Text(
                                'תפקידים נדרשים',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
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
                                            setState(() {
                                              _roleRequirements[role] = _roleRequirements[role]! - 1;
                                              _isDirty = true;
                                            });
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
                                          setState(() {
                                            _roleRequirements[role] = _roleRequirements[role]! + 1;
                                            _isDirty = true;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }),

                              const Divider(height: 32),

                              // Comments
                              TextFormField(
                                controller: _commentsController,
                                decoration: const InputDecoration(
                                  labelText: 'הערות',
                                  hintText: 'הערות על האירוע',
                                  prefixIcon: Icon(Icons.comment),
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 3,
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

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
                            onPressed: _saveEvent,
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
