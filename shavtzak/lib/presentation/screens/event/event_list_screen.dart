import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/event_assignment_status.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/event.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../widgets/navigation_menu.dart';
import '../../widgets/date_picker_dialog.dart';
import 'quota_reduction_analyzer.dart';
import 'widgets/quota_reduction_dialog.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  EventsLoaded? _lastLoadedState;

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
          leading: const NavigationMenu(),
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
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(content: Text(state.message), backgroundColor: Colors.red),
                );
            } else if (state is EventOperationSuccess) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(content: Text(state.message), backgroundColor: Colors.green),
                );
            }
          },
          builder: (context, state) {
            // Always show last known state if available, unless explicitly loading
            if (state is EventLoading && _lastLoadedState == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is EventsEmpty) {
              return _buildEmptyState(state.message);
            }
            if (state is EventsLoaded) {
              _lastLoadedState = state;
              return _buildEventList(state);
            }
            // For any other state (Success, Error), keep showing last state if available
            if (_lastLoadedState != null) {
              return _buildEventList(_lastLoadedState!);
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
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: state.events.length,
              itemBuilder: (context, index) {
                return _buildEventCard(state.events[index], state.assignmentCounts);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Get background color for event card based on assignment status
  Color? _getEventCardColor(Event event, Map<String, int> assignmentCounts) {
    final assignmentCount = assignmentCounts[event.id] ?? 0;
    final totalRequired = event.totalPeopleRequired;

    // Determine status based on counts
    final EventAssignmentStatus status;
    if (totalRequired == 0) {
      status = EventAssignmentStatus.noQuotas;
    } else if (assignmentCount == 0) {
      status = EventAssignmentStatus.none;
    } else if (assignmentCount < totalRequired) {
      status = EventAssignmentStatus.partial;
    } else {
      status = EventAssignmentStatus.complete;
    }

    switch (status) {
      case EventAssignmentStatus.none:
        return Colors.red.shade50;
      case EventAssignmentStatus.partial:
        return Colors.orange.shade50;
      case EventAssignmentStatus.complete:
        return Colors.green.shade50;
      case EventAssignmentStatus.noQuotas:
        return null; // Default color
    }
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

  Widget _buildEventCard(Event event, Map<String, int> assignmentCounts) {
    // Check if start and end dates are the same
    final isSameDate = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    final cardColor = _getEventCardColor(event, assignmentCounts);

    return Card(
      color: cardColor,
      child: InkWell(
        onTap: () => _showEventFormModal(event),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with avatar and name
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(event.name.isNotEmpty ? event.name[0] : '?', style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(event.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // All fields in a single Wrap for horizontal flow
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  // Date field(s) - smart logic
                  if (isSameDate)
                    _buildFieldItem('תאריך', _formatDate(event.startDate))
                  else ...[
                    _buildFieldItem('תאריך התחלה', _formatDate(event.startDate)),
                    _buildFieldItem('תאריך סיום', _formatDate(event.endDate)),
                  ],
                  _buildFieldItem('מיקום', event.location.isEmpty ? '-' : event.location),
                  // Time fields
                  _buildFieldItem('שעת התייצבות', event.assemblyTime.isEmpty ? '-' : event.assemblyTime),
                  _buildFieldItem('שעת התחלה', event.startTime.isEmpty ? '-' : event.startTime),
                  _buildFieldItem('שעת סיום', event.endTime.isEmpty ? '-' : event.endTime),
                ],
              ),
              // Comments (if not empty)
              if (event.comments.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildFieldItem('הערות', event.comments),
              ],
            ],
          ),
        ),
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
      builder: (modalContext) => _EventFormModal(
        event: event,
        onSuccess: () {
          Navigator.of(modalContext).pop();
        },
      ),
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

  Widget _buildFieldItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
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
  final VoidCallback onSuccess;

  const _EventFormModal({
    this.event,
    required this.onSuccess,
  });

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
  bool _validateName = false; // Enable name validation after blur or submit
  String? _dateError; // Track date validation error
  final _nameFocusNode = FocusNode(); // For name field blur detection

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

    // Enable validation when name field loses focus
    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus && _nameController.text.isNotEmpty) {
        setState(() {
          _validateName = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _commentsController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _assemblyTimeController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveEvent() async {
    // Enable validation for all fields after first submit attempt
    setState(() {
      _validateName = true;
      // Validate date field
      _dateError = _startDate == null ? 'יש לבחור תאריך התחלה' : null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_startDate == null) {
      return;
    }

    // NEW: Quota reduction analysis (edit mode only)
    if (_isEditMode) {
      try {
        final conflicts = await QuotaReductionAnalyzer.analyzeQuotaReductions(
          originalEvent: widget.event!,
          newRoleRequirements: _roleRequirements,
          assignmentRepo: context.read<AssignmentRepository>(),
        );

        // If there are assignments that need to be removed, show dialog
        if (conflicts.isNotEmpty) {
          if (!mounted) return;
          final selectedIds = await QuotaReductionDialog.show(
            context,
            conflicts,
          );

          if (selectedIds == null) {
            // User cancelled - revert quotas to original values
            setState(() {
              _roleRequirements = Map.from(widget.event!.roleRequirements);
            });
            return;
          }

          // Delete selected assignments
          if (selectedIds.isNotEmpty && mounted) {
            final assignmentRepo = context.read<AssignmentRepository>();
            await assignmentRepo.deleteAssignmentsBatch(selectedIds);

            // Reorder remaining assignments to fill slots sequentially
            // This ensures slots 0, 1, 2, ... are filled without gaps
            for (final conflict in conflicts) {
              // Get all remaining assignments for this role
              final allAssignments = await assignmentRepo.getAssignmentsByEvent(
                widget.event!.id,
              );
              final remainingAssignments = allAssignments
                  .where((a) =>
                      a.roleType == conflict.roleType &&
                      !selectedIds.contains(a.id))
                  .toList();

              // Sort by current slotIndex to maintain relative order
              remainingAssignments.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

              // Reassign sequential slot indices starting from 0
              for (int i = 0; i < remainingAssignments.length; i++) {
                if (remainingAssignments[i].slotIndex != i) {
                  // Update this assignment with new slotIndex
                  final updated = remainingAssignments[i].copyWith(
                    slotIndex: i,
                    updatedAt: DateTime.now(),
                  );
                  await assignmentRepo.updateAssignmentUnchecked(updated);
                }
              }
            }
            // Note: No need to manually reload - assignment screen uses real-time streams
          }
        }

        // IMPORTANT: Always reorder assignments after quota reduction,
        // even if there were no conflicts requiring deletion.
        // This handles cases where assignments are beyond the new quota range
        // (e.g., Person at slot 5 when quota reduced to 4)
        if (mounted) {
          final assignmentRepo = context.read<AssignmentRepository>();
          final allAssignments = await assignmentRepo.getAssignmentsByEvent(
            widget.event!.id,
          );

          // Check each role where quota was reduced
          for (final roleType in RoleType.values) {
            final oldQuota = widget.event!.roleRequirements[roleType] ?? 0;
            final newQuota = _roleRequirements[roleType] ?? 0;

            // Only process roles where quota was reduced
            if (newQuota >= oldQuota) continue;

            // Get all assignments for this role
            final roleAssignments = allAssignments
                .where((a) => a.roleType == roleType)
                .toList();

            // Sort by current slotIndex to maintain relative order
            roleAssignments.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

            // Reassign sequential slot indices starting from 0
            // This moves any assignments beyond the quota range into the valid range
            for (int i = 0; i < roleAssignments.length; i++) {
              if (roleAssignments[i].slotIndex != i) {
                final updated = roleAssignments[i].copyWith(
                  slotIndex: i,
                  updatedAt: DateTime.now(),
                );
                await assignmentRepo.updateAssignmentUnchecked(updated);
              }
            }
          }
        }
      } catch (e) {
        // Show error and don't proceed with save
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text('שגיאה בניתוח שיבוצים: $e'),
                backgroundColor: Colors.red,
              ),
            );
        }
        return;
      }
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

    if (!mounted) return;
    if (_isEditMode) {
      context.read<EventBloc>().add(UpdateEvent(event));
    } else {
      context.read<EventBloc>().add(CreateEvent(event));
    }

    // Close modal after save operation
    widget.onSuccess();
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
                            _isEditMode ? 'עריכת אירוע' : 'הוספת אירוע',
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
                                    title: const Text('מחיקת אירוע'),
                                    content: Text(
                                      'האם אתה בטוח שברצונך למחוק את ${widget.event!.name}?\nפעולה זו תמחק גם את כל השיבוצים.',
                                    ),
                                    actions: [
                                      TextButton(
                                        child: const Text('ביטול'),
                                        onPressed: () => Navigator.of(dialogContext).pop(),
                                      ),
                                      TextButton(
                                        child: const Text('מחק', style: TextStyle(color: Colors.red)),
                                        onPressed: () {
                                          context.read<EventBloc>().add(DeleteEvent(widget.event!.id));
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
                    child: BlocBuilder<EventBloc, EventState>(
                      builder: (context, state) {
                        return Form(
                          key: _formKey,
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
                                focusNode: _nameFocusNode,
                                decoration: const InputDecoration(
                                  labelText: 'שם האירוע',
                                  hintText: 'לדוגמה: חתונת כהן',
                                  prefixIcon: Icon(Icons.event),
                                  border: OutlineInputBorder(),
                                ),
                                autovalidateMode: _validateName
                                    ? AutovalidateMode.onUserInteraction
                                    : AutovalidateMode.disabled,
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
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'נא למלא מיקום';
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Date Selection (Dual Calendar)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final result = await showDialog<Map<String, DateTime?>>(
                                        context: context,
                                        builder: (context) => DualCalendarDatePicker(
                                          isSingleDate: false,
                                          initialStartDate: _startDate,
                                          initialEndDate: _endDate,
                                          title: 'בחר תאריכי אירוע',
                                        ),
                                      );

                                      if (result != null) {
                                        final selectedStartDate = result['startDate'];
                                        final selectedEndDate = result['endDate'];

                                        // Check if only start date was selected
                                        if (selectedStartDate != null && selectedEndDate == null) {
                                          // Show confirmation dialog for single-day event
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (dialogContext) => Directionality(
                                              textDirection: TextDirection.rtl,
                                              child: AlertDialog(
                                                title: const Text('אישור אירוע ליום בודד'),
                                                content: Text(
                                                  'האם זה אירוע ליום בודד (${_formatDate(selectedStartDate!)})?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text('ביטול'),
                                                    onPressed: () => Navigator.of(dialogContext).pop(false),
                                                  ),
                                                  ElevatedButton(
                                                    child: const Text('כן, אירוע ליום בודד'),
                                                    onPressed: () => Navigator.of(dialogContext).pop(true),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );

                                          if (confirmed == true) {
                                            setState(() {
                                              _startDate = selectedStartDate;
                                              _endDate = null; // Single day event
                                              _dateError = null;
                                              _isDirty = true;
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
                                            _dateError = null;
                                            _isDirty = true;
                                          });
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_month),
                                    label: Text(
                                      _startDate == null
                                          ? 'בחר תאריכי אירוע'
                                          : _endDate == null
                                              ? 'מ-${_formatDate(_startDate!)}'
                                              : '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.all(16),
                                      alignment: Alignment.centerRight,
                                      side: BorderSide(
                                        color: _dateError != null ? Colors.red.shade700 : Colors.grey,
                                        width: _dateError != null ? 2 : 1,
                                      ),
                                      backgroundColor: _dateError != null ? Colors.red.shade50 : null,
                                    ),
                                  ),
                                  if (_dateError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 16, top: 4, bottom: 8),
                                      child: Text(
                                        _dateError!,
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (_startDate != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          onPressed: () => setState(() {
                                            _startDate = null;
                                            _endDate = null;
                                            _isDirty = true;
                                          }),
                                          icon: const Icon(Icons.clear, size: 16),
                                          label: const Text('נקה'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
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
        },
      );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
