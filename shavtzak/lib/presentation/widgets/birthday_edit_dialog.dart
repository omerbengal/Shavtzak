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
  bool _showValidationErrors = false;

  // Hebrew month names
  static const List<String> _hebrewMonths = [
    'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
    'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
  ];

  int get _maxYear => DateTime.now().year - 20;
  int get _minYear => DateTime.now().year - 100;

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

  /// Returns true if there's a partial selection (some fields filled, some not)
  bool get _hasPartialSelection {
    final filledCount = [_selectedDay, _selectedMonth, _selectedYear]
        .where((v) => v != null)
        .length;
    return filledCount > 0 && filledCount < 3;
  }

  /// Returns true if this specific field should show an error
  bool _fieldHasError(int? fieldValue) {
    return _showValidationErrors && _hasPartialSelection && fieldValue == null;
  }

  /// Builds InputDecoration with proper error styling
  InputDecoration _buildFieldDecoration(String label, int? fieldValue) {
    final hasError = _fieldHasError(fieldValue);
    return InputDecoration(
      labelText: label,
      labelStyle: hasError ? const TextStyle(color: Colors.red) : null,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: hasError ? Colors.red : Colors.grey,
          width: hasError ? 2 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: hasError ? Colors.red : Colors.blue,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'בחר את תאריך הלידה שלך',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              // Day dropdown
              DropdownButtonFormField<int>(
                value: _selectedDay,
                decoration: _buildFieldDecoration('יום', _selectedDay),
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
              const SizedBox(height: 12),
              // Month dropdown
              DropdownButtonFormField<int>(
                value: _selectedMonth,
                decoration: _buildFieldDecoration('חודש', _selectedMonth),
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
              const SizedBox(height: 12),
              // Year dropdown
              DropdownButtonFormField<int>(
                value: _selectedYear,
                decoration: _buildFieldDecoration('שנה', _selectedYear),
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
              if (_showValidationErrors && _hasPartialSelection) ...[
                const SizedBox(height: 8),
                const Text(
                  'יש למלא את כל השדות',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              if (_selectedDay != null || _selectedMonth != null || _selectedYear != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedDay = null;
                      _selectedMonth = null;
                      _selectedYear = null;
                      _isDirty = true;
                      _showValidationErrors = false;
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
    // Check if selection is valid before saving
    if (_hasPartialSelection) {
      setState(() {
        _showValidationErrors = true;
      });
      return;
    }

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
