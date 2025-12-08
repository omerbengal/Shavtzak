import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/constraint_status.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../widgets/date_picker_dialog.dart';

/// Screen for non-permanent users to manage their availability
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  TeamMember? _lastKnownUser;

  // Helper function to check if availability is past
  bool _isPastAvailability(DateConstraint constraint) {
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
      // For single-day availability (no endDate), check if startDate is before today
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

  @override
  void initState() {
    super.initState();
    // Trigger load of all team members for real-time updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeamBloc>().add(const LoadTeamMembers());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
            builder: (context, userState) {
              if (userState is! UserAuthenticated) {
                return const Center(
                  child: Text('אין משתמש מחובר'),
                );
              }

              return BlocConsumer<TeamBloc, TeamState>(
                listener: (context, state) {
                  // Only show error messages from TeamBloc for availability screen
                  if (state is TeamError) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(state.message),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  }
                  // Don't show TeamMemberOperationSuccess here - we'll show our own messages
                },
                builder: (context, teamState) {
                  // Show loading only if we don't have any data yet
                  if (teamState is TeamLoading && _lastKnownUser == null) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (teamState is TeamLoaded) {
                    // Find the current user in the team list
                    final currentUser = teamState.members.firstWhere(
                      (member) => member.id == userState.user.id,
                      orElse: () => userState.user,
                    );
                    _lastKnownUser = currentUser;
                    return _buildAvailabilityContent(context, currentUser);
                  }

                  // For any other state (Success, Error, etc.), keep showing last known state
                  if (_lastKnownUser != null) {
                    return _buildAvailabilityContent(context, _lastKnownUser!);
                  }

                  if (teamState is TeamError) {
                    return Center(
                      child: Text('שגיאה: ${teamState.message}'),
                    );
                  }

                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'availability_fab',
          onPressed: () => _addAvailability(context),
          backgroundColor: Colors.green,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildAvailabilityContent(BuildContext context, TeamMember user) {
    // Filter out past availability from main list (they appear in history modal)
    final availabilities = user.constraints
        .where((c) => c.isAvailability && !_isPastAvailability(c))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'הזמינות שלי',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.green[700],
                    ),
                  ),
                  // History button for past availability
                  TextButton.icon(
                    onPressed: () => _showPastAvailabilityModal(context, user),
                    icon: const Icon(
                      Icons.history,
                      size: 20,
                    ),
                    label: const Text(
                      'זמינות שעברה',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'כאן תוכל/י לסמן את התאריכים שבהם את/ה זמין/ה להתנדב. הזמינות שתסמן/י תשפיע מיד על האפשרות לשבץ אותך לאירועים.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),

        // Availability list
        Expanded(
          child: availabilities.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: availabilities.length,
                  itemBuilder: (context, index) {
                    final availability = availabilities[index];
                    return _buildAvailabilityCard(context, availability, user);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_available,
            size: 64,
            color: Colors.green[300],
          ),
          const SizedBox(height: 16),
          Text(
            'לא סימנת זמינות עדיין',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'לחץ/י על כפתור ההוספה כדי לסמן תאריכים שבהם תרצה/י להתנדב',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard(BuildContext context, DateConstraint availability, TeamMember user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    availability.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (availability.note != null && availability.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                availability.note!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editAvailability(context, availability, user),
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  label: const Text('ערוך', style: TextStyle(color: Colors.blue)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteAvailability(context, availability, user),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('מחק', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  
  void _addAvailability(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddAvailabilityDialog(
        onAdd: (startDate, endDate, note) {
          // Create the new availability constraint
          final newAvailability = DateConstraint(
            id: const Uuid().v4(),
            startDate: startDate,
            endDate: endDate,
            note: note?.isNotEmpty == true ? note : null,
            status: ConstraintStatus.approved, // Auto-approved for availability
            constraintType: ConstraintType.availability,
          );

          // Get current user state and team state
          final userState = context.read<UserSelectionBloc>().state;
          final teamState = context.read<TeamBloc>().state;

          if (userState is UserAuthenticated && teamState is TeamLoaded) {
            // Find the current user from the fresh team data
            final currentUser = teamState.members.firstWhere(
              (member) => member.id == userState.user.id,
              orElse: () => userState.user,
            );

            final updatedUser = currentUser.copyWith(
              constraints: [...currentUser.constraints, newAvailability],
            );

            context.read<TeamBloc>().add(UpdateTeamMember(updatedUser));

            // Show our own success message for availability
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                const SnackBar(
                  content: Text('הזמינות נוספה בהצלחה'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
          }
        },
      ),
    );
  }

  void _editAvailability(BuildContext context, DateConstraint availability, TeamMember user) {
    showDialog(
      context: context,
      builder: (context) => _EditAvailabilityDialog(
        availability: availability,
        user: user,
        onSave: (startDate, endDate, note) {
          final updatedAvailability = availability.copyWith(
            startDate: startDate,
            endDate: endDate,
            note: note?.isNotEmpty == true ? note : null,
          );

          final updatedConstraints = user.constraints
              .map((c) => c.id == availability.id ? updatedAvailability : c)
              .toList();

          context.read<TeamBloc>().add(
                UpdateTeamMember(
                  user.copyWith(constraints: updatedConstraints),
                ),
          );

          // Show success message
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text('הזמינות עודכנה בהצלחה'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
        },
      ),
    );
  }

  void _deleteAvailability(BuildContext context, DateConstraint availability, TeamMember user) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת זמינות'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק זמינות זו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                final updatedConstraints = user.constraints
                    .where((c) => c.id != availability.id)
                    .toList();

                context.read<TeamBloc>().add(
                      UpdateTeamMember(
                        user.copyWith(constraints: updatedConstraints),
                      ),
                    );

                // Show success message for deletion
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('הזמינות נמחקה בהצלחה'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
              },
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPastAvailabilityModal(BuildContext context, TeamMember user) {
    final pastAvailabilities = user.constraints
        .where((c) => c.isAvailability && _isPastAvailability(c))
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('זמינות שעברה'),
          content: SizedBox(
            width: double.maxFinite,
            child: pastAvailabilities.isEmpty
                ? const Text('אין זמינות שעברה')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: pastAvailabilities.length,
                    itemBuilder: (context, index) {
                      final availability = pastAvailabilities[index];
                      return ListTile(
                        leading: Icon(
                          Icons.history,
                          color: Colors.grey[600],
                        ),
                        title: Text(availability.toString()),
                        subtitle: availability.note != null ? Text(availability.note!) : null,
                      );
                    },
                  ),
          ),
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

class _AddAvailabilityDialog extends StatefulWidget {
  final Function(DateTime startDate, DateTime? endDate, String? note) onAdd;

  const _AddAvailabilityDialog({required this.onAdd});

  @override
  State<_AddAvailabilityDialog> createState() => _AddAvailabilityDialogState();
}

class _AddAvailabilityDialogState extends State<_AddAvailabilityDialog> {
  DateTime? startDate;
  DateTime? endDate;
  final noteController = TextEditingController();
  bool _canSubmit = false;

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  void initState() {
    super.initState();
    // Note is optional for availability, so we can submit without it
    _updateCanSubmit();
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  void _updateCanSubmit() {
    setState(() {
      _canSubmit = startDate != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text(
          'הוספת זמינות',
          textAlign: TextAlign.right,
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('תאריכים:'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDateRange,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 8),
                      Text(
                        startDate != null
                            ? (endDate != null && !_isSameDay(startDate!, endDate!)
                                ? '${_formatDate(startDate!)} - ${_formatDate(endDate!)}'
                                : _formatDate(startDate!))
                            : 'בחר תאריך התחלה (וסיום אם רלוונטי)',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('הערה (אופציונלי):'),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                textAlign: TextAlign.right,
                textAlignVertical: TextAlignVertical.top,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'פרטים נוספים על הזמינות שלך...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  hintTextDirection: TextDirection.rtl,
                ),
                maxLines: 3,
                minLines: 3,
                style: const TextStyle(height: 1.5),
                scrollPhysics: const BouncingScrollPhysics(),
                onChanged: (value) => _updateCanSubmit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _canSubmit
                ? () {
                    Navigator.of(context).pop();
                    widget.onAdd(
                      startDate!,
                      endDate,
                      noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                    );
                  }
                : null,
            child: const Text('הוספה'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: startDate,
        initialEndDate: endDate,
        title: 'בחר תאריכי זמינות',
        minDate: todayDate, // Prevent selecting dates before today
      ),
    );

    if (result != null) {
      setState(() {
        startDate = result['startDate']!;
        endDate = result['endDate'];

        // If only start date selected, set end date to start date (single-day availability)
        if (endDate == null) {
          endDate = startDate;
        }
      });
      _updateCanSubmit();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _EditAvailabilityDialog extends StatefulWidget {
  final DateConstraint availability;
  final TeamMember user;
  final Function(DateTime startDate, DateTime? endDate, String? note) onSave;

  const _EditAvailabilityDialog({
    required this.availability,
    required this.user,
    required this.onSave,
  });

  @override
  State<_EditAvailabilityDialog> createState() => _EditAvailabilityDialogState();
}

class _EditAvailabilityDialogState extends State<_EditAvailabilityDialog> {
  late DateTime startDate;
  DateTime? endDate;
  late TextEditingController noteController;
  bool _canSubmit = false;

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  void initState() {
    super.initState();
    startDate = widget.availability.startDate;
    endDate = widget.availability.endDate;
    noteController = TextEditingController(text: widget.availability.note ?? '');
    _updateCanSubmit();
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  void _updateCanSubmit() {
    setState(() {
      _canSubmit = true; // Always true for editing availability
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text(
          'עריכת זמינות',
          textAlign: TextAlign.right,
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('תאריכים:'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDateRange,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 8),
                      Text(
                        endDate != null && !_isSameDay(startDate, endDate!)
                            ? '${_formatDate(startDate)} - ${_formatDate(endDate!)}'
                            : _formatDate(startDate),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('הערה (אופציונלי):'),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                textAlign: TextAlign.right,
                textAlignVertical: TextAlignVertical.top,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'פרטים נוספים על הזמינות שלך...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  hintTextDirection: TextDirection.rtl,
                ),
                maxLines: 3,
                minLines: 3,
                style: const TextStyle(height: 1.5),
                scrollPhysics: const BouncingScrollPhysics(),
                onChanged: (value) => _updateCanSubmit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _canSubmit
                ? () {
                  Navigator.of(context).pop();
                  widget.onSave(
                    startDate,
                    endDate,
                    noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                  );
                }
                : null,
            child: const Text('שמור שינויים'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: startDate,
        initialEndDate: endDate,
        title: 'בחר תאריכי זמינות',
        minDate: todayDate, // Prevent selecting dates before today
      ),
    );

    if (result != null) {
      setState(() {
        startDate = result['startDate']!;
        endDate = result['endDate'];

        // If only start date selected, set end date to start date (single-day availability)
        if (endDate == null) {
          endDate = startDate;
        }
      });
      _updateCanSubmit();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}