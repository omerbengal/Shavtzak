import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';

/// Dialog for editing user's birthday
class BirthdayEditDialog extends StatefulWidget {
  const BirthdayEditDialog({super.key});

  @override
  State<BirthdayEditDialog> createState() => _BirthdayEditDialogState();
}

class _BirthdayEditDialogState extends State<BirthdayEditDialog> {
  DateTime? _selectedDate;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<UserSelectionBloc>().state;
    if (state is UserAuthenticated) {
      _selectedDate = state.user.birthday;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _selectedDate ?? DateTime(now.year - 20, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _isDirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cake, color: Colors.pink),
            const SizedBox(width: 8),
            const Text('עריכת תאריך לידה'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'בחר את תאריך הלידה שלך',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  _selectedDate != null
                      ? _formatDate(_selectedDate!)
                      : 'בחר תאריך',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              if (_selectedDate != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                      _isDirty = true;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                  label: const Text('נקה תאריך', style: TextStyle(color: Colors.red)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _isDirty ? _saveBirthday : null,
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  void _saveBirthday() async {
    final bloc = context.read<UserSelectionBloc>();
    final currentState = bloc.state;

    if (currentState is! UserAuthenticated) {
      return;
    }

    try {
      // Use the UpdateBirthday event to update the birthday
      bloc.add(UpdateBirthday(_selectedDate));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_selectedDate == null ? 'תאריך לידה הוסר' : 'תאריך לידה עודכן'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון תאריך לידה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
