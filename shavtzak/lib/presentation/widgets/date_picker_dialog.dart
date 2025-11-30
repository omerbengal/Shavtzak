import 'package:flutter/material.dart';
import 'package:calendar_date_picker2/calendar_date_picker2.dart';

/// A reusable date picker dialog that supports both single date and date range selection.
///
/// For single date mode, shows one calendar.
/// For date range mode, shows two calendars side by side on desktop/tablet,
/// and stacked vertically on mobile devices.
class DualCalendarDatePicker extends StatefulWidget {
  /// Whether this is a single date picker (true) or date range picker (false)
  final bool isSingleDate;

  /// Initial start date (optional)
  final DateTime? initialStartDate;

  /// Initial end date (optional, only used when isSingleDate is false)
  final DateTime? initialEndDate;

  /// Dialog title
  final String title;

  const DualCalendarDatePicker({
    super.key,
    required this.isSingleDate,
    this.initialStartDate,
    this.initialEndDate,
    required this.title,
  });

  @override
  State<DualCalendarDatePicker> createState() => _DualCalendarDatePickerState();
}

class _DualCalendarDatePickerState extends State<DualCalendarDatePicker> {
  List<DateTime?> _selectedDates = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // Initialize selected dates based on mode and initial values
    if (widget.isSingleDate) {
      _selectedDates = widget.initialStartDate != null ? [widget.initialStartDate] : [];
    } else {
      // For range mode, initialize with both dates if available
      if (widget.initialStartDate != null && widget.initialEndDate != null) {
        _selectedDates = [widget.initialStartDate, widget.initialEndDate];
      } else if (widget.initialStartDate != null) {
        _selectedDates = [widget.initialStartDate];
      } else {
        _selectedDates = [];
      }
    }
  }

  void _handleSave() {
    if (widget.isSingleDate) {
      // Single date mode
      if (_selectedDates.isEmpty || _selectedDates.first == null) {
        setState(() {
          _errorMessage = 'יש לבחור תאריך';
        });
        return;
      }
      Navigator.pop(context, {'startDate': _selectedDates.first});
    } else {
      // Date range mode
      if (_selectedDates.isEmpty || _selectedDates.first == null) {
        setState(() {
          _errorMessage = 'יש לבחור תאריך התחלה';
        });
        return;
      }

      // Allow returning with just start date (confirmation will be handled by caller)
      if (_selectedDates.length < 2 || _selectedDates[1] == null) {
        Navigator.pop(context, {
          'startDate': _selectedDates.first,
          'endDate': null,
        });
        return;
      }

      // Validate end date is not before start date
      if (_selectedDates[1]!.isBefore(_selectedDates.first!)) {
        setState(() {
          _errorMessage = 'תאריך הסיום לא יכול להיות לפני תאריך ההתחלה';
        });
        return;
      }

      Navigator.pop(context, {
        'startDate': _selectedDates.first,
        'endDate': _selectedDates[1],
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: Container(
          width: isMobile ? MediaQuery.of(context).size.width * 0.9 : 700,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Selected dates display
              if (_selectedDates.isNotEmpty && _selectedDates.first != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        widget.isSingleDate
                            ? _formatDate(_selectedDates.first!)
                            : _selectedDates.length > 1 && _selectedDates[1] != null
                                ? '${_formatDate(_selectedDates.first!)} - ${_formatDate(_selectedDates[1]!)}'
                                : 'מ-${_formatDate(_selectedDates.first!)} (בחר תאריך סיום)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              // Calendar(s)
              Flexible(
                child: SingleChildScrollView(
                  child: CalendarDatePicker2(
                    config: CalendarDatePicker2Config(
                      calendarType: widget.isSingleDate
                          ? CalendarDatePicker2Type.single
                          : CalendarDatePicker2Type.range,
                      selectedDayHighlightColor: Colors.blue,
                      weekdayLabels: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
                      weekdayLabelTextStyle: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                      firstDayOfWeek: 0,
                      controlsHeight: 50,
                      controlsTextStyle: const TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      dayTextStyle: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.normal,
                      ),
                      disabledDayTextStyle: const TextStyle(
                        color: Colors.grey,
                      ),
                      selectableDayPredicate: (day) => true,
                    ),
                    value: _selectedDates,
                    onValueChanged: (dates) {
                      setState(() {
                        _selectedDates = dates;
                        _errorMessage = null; // Clear error on selection
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ביטול'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _handleSave,
                    child: const Text('אישור'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
