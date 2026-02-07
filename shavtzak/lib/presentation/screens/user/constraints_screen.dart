import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/constraint_status.dart';
import '../../../core/constants/calendar_constants.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/calendar_sync/calendar_sync_bloc.dart';
import '../../bloc/calendar_sync/calendar_sync_event.dart';
import '../../widgets/date_picker_dialog.dart';
import '../../widgets/loading_overlay.dart';
import 'availability_screen.dart';
import 'user_navigation_shell.dart'; // Import for onConstraintsPageVisible callback

/// Screen for non-admin users to manage their constraint requests
/// Redirects non-permanent users to availability screen
class ConstraintsScreen extends StatefulWidget {
  const ConstraintsScreen({super.key});

  @override
  State<ConstraintsScreen> createState() => _ConstraintsScreenState();
}

class _ConstraintsScreenState extends State<ConstraintsScreen> {
  TeamMember? _lastKnownUser;
  bool _hasTriggeredInitialSync = false;

  // Helper function to check if constraint is past (same logic as modal)
  bool _isPastConstraint(DateConstraint constraint) {
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

  @override
  void initState() {
    super.initState();
    // Trigger load of all team members for real-time updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeamBloc>().add(const LoadTeamMembers());
      // Trigger calendar validation sync to check for deleted events on initial load
      context.read<CalendarSyncBloc>().add(const ValidateSyncedEvents());
      _hasTriggeredInitialSync = true;
    });
    // Register callback for when this page becomes visible (e.g., when navigating back from assignments)
    onConstraintsPageVisible = () {
      if (mounted && _hasTriggeredInitialSync) {
        context.read<CalendarSyncBloc>().add(const ValidateSyncedEvents());
      }
    };
  }

  @override
  void dispose() {
    // Unregister callback
    onConstraintsPageVisible = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        builder: (context, userState) {
          if (userState is! UserAuthenticated) {
            return Scaffold(
              body: SafeArea(
                child: const Center(
                  child: Text('אין משתמש מחובר'),
                ),
              ),
            );
          }

          // Redirect non-permanent users to availability screen
          if (!userState.user.isPermanent) {
            // Return the availability screen directly
            return const AvailabilityScreen();
          }

          // For permanent users, show the constraints screen with FAB
          return Scaffold(
            body: SafeArea(
              child: BlocConsumer<TeamBloc, TeamState>(
                listener: (context, state) {
                  // Show snackbar for success/error messages
                  if (state is TeamMemberOperationSuccess) {
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
                  } else if (state is TeamError) {
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
                  }
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
                    return _buildConstraintsContent(context, currentUser);
                  }

                  // For any other state (Success, Error, etc.), keep showing last known state
                  if (_lastKnownUser != null) {
                    return _buildConstraintsContent(context, _lastKnownUser!);
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
              ),
            ),
            floatingActionButton: FloatingActionButton(
              heroTag: 'constraints_fab',
              onPressed: () => _addConstraintRequest(context),
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConstraintsContent(BuildContext context, TeamMember user) {
    // Filter out past constraints from main list (they appear in expired constraints modal)
    // Only show unavailability constraints for permanent members
    final constraints = user.constraints
        .where((c) => c.isUnavailability && !_isPastConstraint(c))
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
                    'המגבלות שלי',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  // History button for expired constraints
                  TextButton.icon(
                    onPressed: () => _showExpiredConstraintsModal(context, user),
                    icon: const Icon(
                      Icons.history,
                      size: 20,
                    ),
                    label: const Text(
                      'מגבלות לא בתוקף',
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
                'כאן תוכל/י להוסיף בקשות למגבלות זמן. הבקשות יופיעו כאן עם סטטוס ממתין לאישור עד שמנהל המערכת יאשר אותן.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),

        // Constraints list
        Expanded(
          child: constraints.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: constraints.length,
                  itemBuilder: (context, index) {
                    final constraint = constraints[index];
                    return _buildConstraintCard(context, user, constraint, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'אין לך מגבלות זמן',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'לחץ/י על כפתור ההוספה כדי להוסיף הגבלת זמן חדשה',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConstraintCard(BuildContext context, TeamMember user, DateConstraint constraint, int index) {
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
                    constraint.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _buildStatusBadge(constraint.status),
              ],
            ),
            if (constraint.note != null && constraint.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                constraint.note!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
            // Show auto-rejection message in red if applicable
            if (constraint.wasAutoRejectedFromCalendar) ...[
              const SizedBox(height: 8),
              Text(
                CalendarAutoRejection.message,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editConstraint(context, user, constraint, index),
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  label: const Text('ערוך', style: TextStyle(color: Colors.blue)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteConstraint(context, user, constraint.id),
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

  Widget _buildStatusBadge(ConstraintStatus status) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case ConstraintStatus.pending:
        backgroundColor = Colors.orange;
        textColor = Colors.white;
        text = status.hebrewShortName;
        break;
      case ConstraintStatus.approved:
        backgroundColor = Colors.green;
        textColor = Colors.white;
        text = status.hebrewShortName;
        break;
      case ConstraintStatus.rejected:
        backgroundColor = Colors.red;
        textColor = Colors.white;
        text = status.hebrewShortName;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _addConstraintRequest(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _ConstraintRequestDialog(
        onAdd: (startDate, endDate, note) {
          final userState = context.read<UserSelectionBloc>().state;
          if (userState is UserAuthenticated) {
            // Send to database - UI will update automatically via stream
            context.read<TeamBloc>().add(AddConstraintRequest(
              teamMemberId: userState.user.id,
              startDate: startDate,
              endDate: endDate,
              note: note,
            ));
          }
        },
      ),
    );
  }

  void _deleteConstraint(BuildContext context, TeamMember user, String constraintId) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת מגבלה'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק את המגבלה הזו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();

                // Find the constraint index
                final constraintIndex = user.constraints.indexWhere((c) => c.id == constraintId);
                if (constraintIndex != -1) {
                  // Send to database - UI will update automatically via stream
                  context.read<TeamBloc>().add(RemoveConstraintRequest(
                    teamMemberId: user.id,
                    constraintIndex: constraintIndex,
                  ));
                }
              },
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  void _editConstraint(BuildContext context, TeamMember user, DateConstraint constraint, int index) {
    showDialog(
      context: context,
      builder: (context) => _EditConstraintDialog(
        constraint: constraint,
        onSave: (startDate, endDate, note) {
          // Create updated constraint with pending status
          final updatedConstraint = constraint.copyWith(
            startDate: startDate,
            endDate: endDate,
            note: note,
            status: ConstraintStatus.pending, // Always change to pending when edited
            wasAutoRejectedFromCalendar: false, // Reset auto-rejection flag when edited
          );

          final userState = context.read<UserSelectionBloc>().state;
          if (userState is UserAuthenticated) {
            // Update constraint by removing and re-adding with new data
            final updatedConstraints = List<DateConstraint>.from(user.constraints);
            updatedConstraints[index] = updatedConstraint;

            final updatedUser = user.copyWith(constraints: updatedConstraints);
            context.read<TeamBloc>().add(UpdateTeamMember(updatedUser));
          }
        },
      ),
    );
  }

  void _showExpiredConstraintsModal(BuildContext context, TeamMember user) {
    
    for (int i = 0; i < user.constraints.length; i++) {
      // Process constraints if needed
    }

    showDialog(
      context: context,
      builder: (context) => _ExpiredConstraintsModal(user: user),
    );
  }

}

/// Dialog for adding constraint requests
class _ConstraintRequestDialog extends StatefulWidget {
  final Function(DateTime startDate, DateTime? endDate, String? note) onAdd;

  const _ConstraintRequestDialog({required this.onAdd});

  @override
  State<_ConstraintRequestDialog> createState() => _ConstraintRequestDialogState();
}

class _ConstraintRequestDialogState extends State<_ConstraintRequestDialog> {
  DateTime? startDate;
  DateTime? endDate;
  final noteController = TextEditingController();
  late final FocusNode _noteFocusNode;
  bool _canSubmit = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _noteFocusNode = createRtlCursorFixedFocusNode(noteController);
    noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    noteController.removeListener(_onNoteChanged);
    noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    setState(() {
      _canSubmit = noteController.text.isNotEmpty && startDate != null;
    });
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          AlertDialog(
            title: const Text(
              'הוספת בקשת מגבלה',
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
                          : 'בחר תאריכים',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('סיבה (חובה):'),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              focusNode: _noteFocusNode,
              textAlign: TextAlign.right,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'יש להזין סיבה לבקשה...',
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
            ),
          ],
        ),
      ),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: (_canSubmit && !_isSaving)
                  ? () {
                      if (_isSaving) return;
                      setState(() => _isSaving = true);
                      widget.onAdd(startDate!, endDate, noteController.text);
                      Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('הוסף בקשה'),
            ),
          ],
          ),
          LoadingOverlay(isLoading: _isSaving, message: 'שולח בקשה...'),
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
        title: 'בחר תאריכי מגבלה',
        minDate: todayDate, // Prevent selecting dates before today
      ),
    );

    if (result != null) {
      setState(() {
        startDate = result['startDate'];
        endDate = result['endDate'];

        // If only start date selected, set end date to start date (single-day constraint)
        endDate ??= startDate;
      });
      _onNoteChanged();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

/// Dialog for editing constraints
class _EditConstraintDialog extends StatefulWidget {
  final DateConstraint constraint;
  final Function(DateTime startDate, DateTime? endDate, String note) onSave;

  const _EditConstraintDialog({
    required this.constraint,
    required this.onSave,
  });

  @override
  State<_EditConstraintDialog> createState() => _EditConstraintDialogState();
}

class _EditConstraintDialogState extends State<_EditConstraintDialog> {
  late DateTime startDate;
  DateTime? endDate;
  late TextEditingController noteController;
  late final FocusNode _noteFocusNode;
  bool _canSubmit = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    startDate = widget.constraint.startDate;
    endDate = widget.constraint.endDate;
    noteController = TextEditingController(text: widget.constraint.note ?? '');
    _noteFocusNode = createRtlCursorFixedFocusNode(noteController);
    noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    noteController.removeListener(_onNoteChanged);
    noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    setState(() {
      _canSubmit = _hasChanges();
    });
  }

  bool _hasChanges() {
    final noteChanged = noteController.text.trim() != (widget.constraint.note ?? '');
    final startDateChanged = !_isSameDay(startDate, widget.constraint.startDate);
    final endDateChanged = (endDate == null) != (widget.constraint.endDate == null) ||
        (endDate != null && widget.constraint.endDate != null && !_isSameDay(endDate!, widget.constraint.endDate!));

    return noteChanged || startDateChanged || endDateChanged;
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          AlertDialog(
            title: const Text(
              'עריכת מגבלה',
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
            const Text('סיבה (חובה):'),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              focusNode: _noteFocusNode,
              textAlign: TextAlign.right,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'יש להזין סיבה לבקשה...',
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
            ),
          ],
        ),
      ),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: (_canSubmit && !_isSaving)
                  ? () {
                      if (_isSaving) return;
                      setState(() => _isSaving = true);
                      widget.onSave(startDate, endDate, noteController.text);
                      Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('שמור שינויים'),
            ),
          ],
          ),
          LoadingOverlay(isLoading: _isSaving, message: 'שומר שינויים...'),
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
        title: 'בחר תאריכי מגבלה',
        minDate: todayDate, // Prevent selecting dates before today
      ),
    );

    if (result != null) {
      setState(() {
        startDate = result['startDate']!;
        endDate = result['endDate'];

        // If only start date selected, set end date to start date (single-day constraint)
        endDate ??= startDate;
      });
      _onNoteChanged();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
/// Modal dialog for displaying and editing expired constraints
class _ExpiredConstraintsModal extends StatefulWidget {
  final TeamMember user;

  const _ExpiredConstraintsModal({required this.user});

  @override
  State<_ExpiredConstraintsModal> createState() => _ExpiredConstraintsModalState();
}

class _ExpiredConstraintsModalState extends State<_ExpiredConstraintsModal> {
  TeamMember? _lastKnownUser;

  // Helper function to check if constraint is past
  bool isPastConstraint(DateConstraint constraint) {
    final today = DateTime.now();

    if (constraint.endDate != null) {
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
      final isPast = constraintEndDate.isBefore(todayDate);

  
      return isPast;
    } else {
      // For single-day constraints (no endDate), check if startDate is before today
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
      final isPast = constraintStartDate.isBefore(todayDate);

    
      return isPast;
    }
  }

  TeamMember? _getCurrentUserFromState(TeamState state, String userId) {
    if (state is TeamLoaded) {
      try {
        return state.members.firstWhere((member) => member.id == userId);
      } catch (e) {
        // Fallback to userSelectionBloc to get current user
        return null;
      }
    } else if (state is TeamLoading) {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'המגבלות לא בתוקף',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                'כאן מוצגות כל המגבלות שתאריך הסיום שלהן חלף. ניתן לערוך מגבלות אלו אם נדרש.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),

              // Constraints list with real-time updates
              Expanded(
                child: BlocConsumer<TeamBloc, TeamState>(
                  listener: (context, state) {
                    // Show snackbar for success/error messages
                    if (state is TeamMemberOperationSuccess) {
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
                    } else if (state is TeamError) {
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
                    }
                  },
                  builder: (context, state) {
                    // Get current user data using same pattern as main screen
                    final userState = context.read<UserSelectionBloc>().state;

                    if (userState is! UserAuthenticated) {
                      return const Center(
                        child: Text('אין משתמש מחובר'),
                      );
                    }

                    
                    // Show loading only if we don't have any data yet (same as main screen)
                    if (state is TeamLoading && _lastKnownUser == null) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    TeamMember currentUser;

                    if (state is TeamLoaded) {

                      // Check if current user is in the team list
                      final userInTeamList = state.members.any((m) => m.id == userState.user.id);

                      if (userInTeamList) {
                        final teamUser = state.members.firstWhere((m) => m.id == userState.user.id);

                        currentUser = teamUser;
                      } else {
                        return const Center(
                          child: Text('שגיאה: המשתמש לא נמצא ברשימת צוות'),
                        );
                      }

                      _lastKnownUser = currentUser;
                    } else {

                      // For success states, expect quick transition to TeamLoaded after stream restart
                      if (state is TeamMemberOperationSuccess) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('מעדכן נתונים מעודכנים...', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      } else if (_lastKnownUser != null) {
                        // For other states, keep showing last known state (same as main screen)
                        currentUser = _lastKnownUser!;
                      } else {
                        // Only show error if we have no data at all
                        return const Center(
                          child: Text('לא ניתן לטעון את נתוני המשתמש'),
                        );
                      }
                    }

                    
                    // Always filter constraints data
                    final allConstraints = currentUser.constraints;

                    final expiredConstraints = allConstraints
                        .where((c) => c.isUnavailability && isPastConstraint(c))
                        .toList()
                      ..sort((a, b) => a.startDate.compareTo(b.startDate));
                    
                    if (expiredConstraints.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'אין מגבלות לא בתוקף',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: expiredConstraints.length,
                      itemBuilder: (context, index) {
                        final constraint = expiredConstraints[index];
                        final originalIndex = currentUser.constraints.indexOf(constraint);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Date range with status
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        constraint.endDate != null
                                            ? '${_formatDate(constraint.startDate)} - ${_formatDate(constraint.endDate!)}'
                                            : _formatDate(constraint.startDate),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(constraint.status).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _getStatusColor(constraint.status),
                                        ),
                                      ),
                                      child: Text(
                                        _getStatusText(constraint.status),
                                        style: TextStyle(
                                          color: _getStatusColor(constraint.status),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Note
                                if (constraint.note != null && constraint.note!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    constraint.note!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],

                                // Auto-rejection message in red if applicable
                                if (constraint.wasAutoRejectedFromCalendar) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    CalendarAutoRejection.message,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],

                                // Actions
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _editExpiredConstraint(constraint, originalIndex, currentUser),
                                      icon: const Icon(Icons.edit, size: 16),
                                      label: const Text('ערוך'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _deleteConstraint(context, currentUser, constraint.id),
                                      icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                      label: const Text('מחק', style: TextStyle(color: Colors.red)),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Color _getStatusColor(ConstraintStatus status) {
    switch (status) {
      case ConstraintStatus.pending:
        return Colors.orange;
      case ConstraintStatus.approved:
        return Colors.green;
      case ConstraintStatus.rejected:
        return Colors.red;
    }
  }

  String _getStatusText(ConstraintStatus status) {
    switch (status) {
      case ConstraintStatus.pending:
        return 'ממתין לאישור';
      case ConstraintStatus.approved:
        return 'אושר';
      case ConstraintStatus.rejected:
        return 'נדחה';
    }
  }

  void _editExpiredConstraint(DateConstraint constraint, int originalIndex, TeamMember currentUser) {
    showDialog(
      context: context,
      builder: (context) => _EditExpiredConstraintDialog(
        user: currentUser,
        constraint: constraint,
        originalIndex: originalIndex,
      ),
    );
  }

  void _deleteConstraint(BuildContext context, TeamMember user, String constraintId) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת מגבלה'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק את המגבלה הזו?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();

                // Find the constraint index
                final constraintIndex = user.constraints.indexWhere((c) => c.id == constraintId);
                if (constraintIndex != -1) {
                  // Send to database - UI will update automatically via stream
                  context.read<TeamBloc>().add(RemoveConstraintRequest(
                    teamMemberId: user.id,
                    constraintIndex: constraintIndex,
                  ));
                }
              },
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for editing expired constraints
class _EditExpiredConstraintDialog extends StatefulWidget {
  final TeamMember user;
  final DateConstraint constraint;
  final int originalIndex;

  const _EditExpiredConstraintDialog({
    required this.user,
    required this.constraint,
    required this.originalIndex,
  });

  @override
  State<_EditExpiredConstraintDialog> createState() => _EditExpiredConstraintDialogState();
}

class _EditExpiredConstraintDialogState extends State<_EditExpiredConstraintDialog> {
  late DateTime startDate;
  DateTime? endDate;
  late TextEditingController noteController;
  late final FocusNode _noteFocusNode;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    startDate = widget.constraint.startDate;
    endDate = widget.constraint.endDate;
    noteController = TextEditingController(text: widget.constraint.note ?? '');
    _noteFocusNode = createRtlCursorFixedFocusNode(noteController);
    _onNoteChanged();
  }

  @override
  void dispose() {
    noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    setState(() {
      _canSubmit = noteController.text.trim().isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('עריכת מגבלה לא בתוקפה'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date range display
              const Text(
                'תאריכי מגבלה:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDateRange,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 8),
                      Text(
                        endDate != null
                            ? '${_formatDate(startDate)} - ${_formatDate(endDate!)}'
                            : _formatDate(startDate),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Note field
              const Text(
                'הערה (לאישור מנהל):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                focusNode: _noteFocusNode,
                decoration: const InputDecoration(
                  hintText: 'הסבר קצר לגבי המגבלה...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onChanged: (value) => _onNoteChanged(),
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
                    // Create updated constraint with pending status
                    final updatedConstraint = DateConstraint(
                      id: widget.constraint.id,
                      startDate: startDate,
                      endDate: endDate,
                      note: noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim(),
                      status: ConstraintStatus.pending, // Reset to pending when edited
                      constraintType: widget.constraint.constraintType, // Preserve original constraint type
                    );

                    // Update constraint via BLoC (same pattern as existing edit constraint)
                    final updatedConstraints = List<DateConstraint>.from(widget.user.constraints);
                    updatedConstraints[widget.originalIndex] = updatedConstraint;

                    final updatedUser = widget.user.copyWith(constraints: updatedConstraints);
                    context.read<TeamBloc>().add(UpdateTeamMember(updatedUser));

                    Navigator.of(context).pop();
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
        title: 'בחר תאריכי מגבלה',
        minDate: todayDate, // Prevent selecting dates before today
      ),
    );

    if (result != null) {
      setState(() {
        startDate = result['startDate']!;
        endDate = result['endDate'];

        // If only start date selected, set end date to start date (single-day constraint)
        endDate ??= startDate;
      });
      _onNoteChanged();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
