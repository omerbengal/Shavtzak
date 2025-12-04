import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/constraint_status.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../widgets/date_picker_dialog.dart';

/// Screen for non-admin users to manage their constraint requests
class ConstraintsScreen extends StatefulWidget {
  const ConstraintsScreen({super.key});

  @override
  State<ConstraintsScreen> createState() => _ConstraintsScreenState();
}

class _ConstraintsScreenState extends State<ConstraintsScreen> {
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

              return BlocBuilder<TeamBloc, TeamState>(
                builder: (context, teamState) {
                  // Load all team members to get real-time updates
                  if (teamState is TeamLoaded) {
                    // Find the current user in the team list
                    final currentUser = teamState.members.firstWhere(
                      (member) => member.id == userState.user.id,
                      orElse: () => userState.user,
                    );
                    return _buildConstraintsContent(context, currentUser);
                  } else if (teamState is TeamLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  } else if (teamState is TeamError) {
                    return Center(
                      child: Text('שגיאה: ${teamState.message}'),
                    );
                  } else {
                    // Trigger the load of all team members for real-time updates
                    context.read<TeamBloc>().add(const LoadTeamMembers());
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                },
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _addConstraintRequest(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildConstraintsContent(BuildContext context, TeamMember user) {
    final constraints = user.constraints;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'הגבלות שלי',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'כאן תוכל/י להוסיף בקשות להגבלות זמן. הבקשות יופיעו כאן עם סטטוס ממתין לאישור עד שמנהל המערכת יאשר אותן.',
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
            'אין לך הגבלות זמן',
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
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (constraint.isPending()) ...[
                  TextButton.icon(
                    onPressed: () => _deletePendingRequest(context, user, index),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('מחק בקשה', style: TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _editConstraint(context, user, constraint, index),
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    label: const Text('ערוך', style: TextStyle(color: Colors.blue)),
                  ),
                ] else ...[
                  // For approved or rejected constraints, allow editing and deletion
                  TextButton.icon(
                    onPressed: () => _editConstraint(context, user, constraint, index),
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    label: const Text('ערוך', style: TextStyle(color: Colors.blue)),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deleteConstraint(context, user, index),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('מחק', style: TextStyle(color: Colors.red)),
                  ),
                ],
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

  void _deletePendingRequest(BuildContext context, TeamMember user, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת בקשה'),
        content: const Text('האם את/ה בטוח/ה שברצונך למחוק את בקשת ההגבלה הזו?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<TeamBloc>().add(RemoveConstraintRequest(
                teamMemberId: user.id,
                constraintIndex: index,
              ));
            },
            child: const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
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

  void _deleteConstraint(BuildContext context, TeamMember user, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת הגבלה'),
        content: const Text('האם את/ה בטוח/ה שברצונך למחוק את ההגבלה הזו?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Remove constraint by updating team member with new constraints list
              final updatedConstraints = List<DateConstraint>.from(user.constraints);
              updatedConstraints.removeAt(index);

              final updatedUser = user.copyWith(constraints: updatedConstraints);
              context.read<TeamBloc>().add(UpdateTeamMember(updatedUser));
            },
            child: const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    noteController.removeListener(_onNoteChanged);
    noteController.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    setState(() {
      _canSubmit = noteController.text.isNotEmpty && startDate != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('הוספת בקשת הגבלה'),
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
                          ? (endDate != null
                              ? '${_formatDate(startDate!)} - ${_formatDate(endDate!)}'
                              : _formatDate(startDate!))
                          : 'בחר תאריך התחלה (וסיום אם רלוונטי)',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('הערה (חובה):'),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'יש להזין הערה לבקשה...',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                hintStyle: TextStyle(
                  color: Colors.grey[600],
                  height: 1.5,
                ),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: _canSubmit
              ? () {
                  widget.onAdd(startDate!, endDate, noteController.text);
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('הוסף בקשה'),
        ),
      ],
    );
  }

  Future<void> _selectDateRange() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: startDate,
        initialEndDate: endDate,
        title: 'בחר תאריכי הגבלה',
      ),
    );

    if (result != null) {
      setState(() {
        startDate = result['startDate'];
        endDate = result['endDate'];
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
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    startDate = widget.constraint.startDate;
    endDate = widget.constraint.endDate;
    noteController = TextEditingController(text: widget.constraint.note ?? '');
    noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    noteController.removeListener(_onNoteChanged);
    noteController.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    setState(() {
      _canSubmit = noteController.text.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('עריכת הגבלה'),
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
                      endDate != null
                          ? '${_formatDate(startDate)} - ${_formatDate(endDate!)}'
                          : _formatDate(startDate),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('הערה (חובה):'),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'יש להזין הערה לבקשה...',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                hintStyle: TextStyle(
                  color: Colors.grey[600],
                  height: 1.5,
                ),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        ElevatedButton(
          onPressed: _canSubmit
              ? () {
                  widget.onSave(startDate, endDate, noteController.text);
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('שמור שינויים'),
        ),
      ],
    );
  }

  Future<void> _selectDateRange() async {
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (context) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: startDate,
        initialEndDate: endDate,
        title: 'בחר תאריכי הגבלה',
      ),
    );

    if (result != null) {
      setState(() {
        startDate = result['startDate']!;
        endDate = result['endDate'];
      });
      _onNoteChanged();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}