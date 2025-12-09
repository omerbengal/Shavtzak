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

  /// Minimum selectable date (optional)
  final DateTime? minDate;

  const DualCalendarDatePicker({
    super.key,
    required this.isSingleDate,
    this.initialStartDate,
    this.initialEndDate,
    required this.title,
    this.minDate,
  });

  @override
  State<DualCalendarDatePicker> createState() => _DualCalendarDatePickerState();
}

class _DualCalendarDatePickerState extends State<DualCalendarDatePicker> {
  List<DateTime?> _selectedDates = [];
  String? _errorMessage;
  bool _isProcessingChange = false;

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // Use tighter constraints on very small screens to prevent overflow
    final dialogWidth = isMobile
        ? (screenWidth < 360 ? screenWidth * 0.95 : screenWidth * 0.9)
        : 700.0;

    final horizontalPadding = isMobile
        ? (screenWidth < 360 ? 8.0 : 12.0)
        : 24.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: Container(
          width: dialogWidth,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: isMobile ? 16 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: isMobile ? 18 : 20,
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
                      Flexible(
                        child: Text(
                          widget.isSingleDate
                              ? _formatDate(_selectedDates.first!)
                              : _selectedDates.length > 1 && _selectedDates[1] != null
                                  ? '${_formatDate(_selectedDates.first!)} - ${_formatDate(_selectedDates[1]!)}'
                                  : 'מ-${_formatDate(_selectedDates.first!)} (בחר תאריך סיום)',
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          textAlign: TextAlign.center,
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

              // Calendar(s) with constrained width
              Flexible(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: dialogWidth - (horizontalPadding * 2),
                    ),
                    child: CalendarDatePicker2(
                      config: CalendarDatePicker2Config(
                        calendarType: widget.isSingleDate
                            ? CalendarDatePicker2Type.single
                            : CalendarDatePicker2Type.range,
                        selectedDayHighlightColor: Colors.blue,
                        weekdayLabels: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
                        weekdayLabelTextStyle: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 10 : 14,
                        ),
                        firstDayOfWeek: 0,
                        controlsHeight: isMobile ? 40 : 50,
                        controlsTextStyle: TextStyle(
                          color: Colors.black,
                          fontSize: isMobile ? 10 : 15,
                          fontWeight: FontWeight.w600,
                        ),
                        dayTextStyle: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.normal,
                          fontSize: isMobile ? 11 : 14,
                        ),
                        disabledDayTextStyle: TextStyle(
                          color: Colors.grey,
                          fontSize: isMobile ? 11 : 14,
                        ),
                        // Set the minimum date that can be viewed/selected
                        firstDate: widget.minDate ?? DateTime.now(),
                        // Set the current date to initially display
                        currentDate: widget.minDate ?? DateTime.now(),
                        selectableDayPredicate: widget.minDate != null
          ? (day) => !day.isBefore(widget.minDate!)
          : (day) => true,
                        lastMonthIcon: Icon(
                          Icons.chevron_left,
                          size: isMobile ? 18 : 24,
                        ),
                        nextMonthIcon: Icon(
                          Icons.chevron_right,
                          size: isMobile ? 18 : 24,
                        ),
                        // Improve mobile touch handling
                        dayBorderRadius: BorderRadius.circular(8),
                        selectedDayTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        // Better touch targets for mobile
                        dayMaxWidth: isMobile ? 40 : double.infinity,
                      ),
                      value: _selectedDates,
                      onValueChanged: (dates) {
                        if (_isProcessingChange) return; // Prevent rapid changes

                        _isProcessingChange = true;

                        setState(() {
                          _selectedDates = dates;
                          _errorMessage = null; // Clear error on selection
                        });

                        // Reset the flag after a short delay - longer for mobile
                        Future.delayed(const Duration(milliseconds: isMobile ? 150 : 50), () {
                          if (mounted) {
                            _isProcessingChange = false;
                          }
                        });
                      },
                    ),
                  ),
                ),
              ),

              SizedBox(height: isMobile ? 16 : 24),

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
