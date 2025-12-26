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
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;
  bool _isDirty = false;

  // Hebrew month names
  static const List<String> _hebrewMonths = [
    'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
    'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
  ];

  int get _maxYear => DateTime.now().year - 20;
  int get _minYear => 1900;

  @override
  void initState() {
    super.initState();
    final state = context.read<UserSelectionBloc>().state;
    if (state is UserAuthenticated && state.user.birthday != null) {
      final birthday = state.user.birthday!;
      _selectedDay = birthday.day;
      _selectedMonth = birthday.month;
      _selectedYear = birthday.year;
    }
  }

  int _getDaysInMonth(int? month, int? year) {
    if (month == null) return 31;
    final y = year ?? 2000; // Use leap year if year not selected
    return DateTime(y, month + 1, 0).day;
  }

  DateTime? _getSelectedDate() {
    if (_selectedDay != null && _selectedMonth != null && _selectedYear != null) {
      return DateTime(_selectedYear!, _selectedMonth!, _selectedDay!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = _getDaysInMonth(_selectedMonth, _selectedYear);

    // Adjust day if it exceeds days in selected month
    if (_selectedDay != null && _selectedDay! > daysInMonth) {
      _selectedDay = daysInMonth;
    }

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
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'בחר את תאריך הלידה שלך',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  // Day dropdown
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: _selectedDay,
                      decoration: const InputDecoration(
                        labelText: 'יום',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: List.generate(daysInMonth, (index) {
                        final day = index + 1;
                        return DropdownMenuItem(
                          value: day,
                          child: Text(day.toString()),
                        );
                      }),
                      onChanged: (value) {
                        setState(() {
                          _selectedDay = value;
                          _isDirty = true;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Month dropdown
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      value: _selectedMonth,
                      decoration: const InputDecoration(
                        labelText: 'חודש',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: List.generate(12, (index) {
                        final month = index + 1;
                        return DropdownMenuItem(
                          value: month,
                          child: Text(_hebrewMonths[index]),
                        );
                      }),
                      onChanged: (value) {
                        setState(() {
                          _selectedMonth = value;
                          _isDirty = true;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Year dropdown
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: _selectedYear,
                      decoration: const InputDecoration(
                        labelText: 'שנה',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: List.generate(_maxYear - _minYear + 1, (index) {
                        final year = _maxYear - index;
                        return DropdownMenuItem(
                          value: year,
                          child: Text(year.toString()),
                        );
                      }),
                      onChanged: (value) {
                        setState(() {
                          _selectedYear = value;
                          _isDirty = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_selectedDay != null || _selectedMonth != null || _selectedYear != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedDay = null;
                      _selectedMonth = null;
                      _selectedYear = null;
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

    final selectedDate = _getSelectedDate();

    try {
      // Use the UpdateBirthday event to update the birthday
      bloc.add(UpdateBirthday(selectedDate));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(selectedDate == null ? 'תאריך לידה הוסר' : 'תאריך לידה עודכן'),
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
