/// Validation utilities for forms and user input
class Validators {
  /// Validate that a string is not empty
  static String? required(String? value, {String fieldName = 'שדה זה'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName הוא שדה חובה';
    }
    return null;
  }

  /// Validate team member name
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'שם הוא שדה חובה';
    }

    if (value.trim().length < 2) {
      return 'שם חייב להכיל לפחות 2 תווים';
    }

    if (value.trim().length > 50) {
      return 'שם לא יכול להכיל יותר מ-50 תווים';
    }

    return null;
  }

  /// Validate event name
  static String? validateEventName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'שם אירוע הוא שדה חובה';
    }

    if (value.trim().length < 3) {
      return 'שם אירוע חייב להכיל לפחות 3 תווים';
    }

    if (value.trim().length > 100) {
      return 'שם אירוע לא יכול להכיל יותר מ-100 תווים';
    }

    return null;
  }

  /// Validate location
  static String? validateLocation(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'מיקום הוא שדה חובה';
    }

    if (value.trim().length < 2) {
      return 'מיקום חייב להכיל לפחות 2 תווים';
    }

    if (value.trim().length > 100) {
      return 'מיקום לא יכול להכיל יותר מ-100 תווים';
    }

    return null;
  }

  /// Validate time format (HH:mm)
  static String? validateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'שעה היא שדה חובה';
    }

    final timeRegex = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
    if (!timeRegex.hasMatch(value.trim())) {
      return 'פורמט שעה לא תקין (HH:mm)';
    }

    return null;
  }

  /// Validate date range (end date must be after or equal to start date)
  static String? validateDateRange(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) {
      return 'יש לבחור תאריכי התחלה וסיום';
    }

    if (endDate.isBefore(startDate)) {
      return 'תאריך סיום חייב להיות אחרי או שווה לתאריך התחלה';
    }

    return null;
  }

  /// Validate time range (end time must be after start time)
  static String? validateTimeRange(String? startTime, String? endTime) {
    if (startTime == null ||
        startTime.isEmpty ||
        endTime == null ||
        endTime.isEmpty) {
      return 'יש להזין שעות התחלה וסיום';
    }

    // Parse times
    final startParts = startTime.split(':');
    final endParts = endTime.split(':');

    if (startParts.length != 2 || endParts.length != 2) {
      return 'פורמט שעה לא תקין';
    }

    final startMinutes =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    if (endMinutes <= startMinutes) {
      return 'שעת סיום חייבת להיות אחרי שעת התחלה';
    }

    return null;
  }

  /// Validate that at least one role is selected
  static String? validateRoleSelection(Map<dynamic, bool> roleCapabilities) {
    if (roleCapabilities.values.every((selected) => selected == false)) {
      return 'יש לבחור לפחות תפקיד אחד';
    }
    return null;
  }

  /// Validate that at least one role requirement is set
  static String? validateRoleRequirements(Map<dynamic, int> roleRequirements) {
    if (roleRequirements.values.every((count) => count == 0)) {
      return 'יש להגדיר לפחות דרישה אחת לתפקיד';
    }
    return null;
  }

  /// Validate positive number
  static String? validatePositiveNumber(
    String? value, {
    String fieldName = 'ערך זה',
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName הוא שדה חובה';
    }

    final number = int.tryParse(value.trim());
    if (number == null) {
      return '$fieldName חייב להיות מספר';
    }

    if (number < 0) {
      return '$fieldName חייב להיות חיובי';
    }

    return null;
  }

  /// Validate non-negative number (allows 0)
  static String? validateNonNegativeNumber(
    String? value, {
    String fieldName = 'ערך זה',
  }) {
    if (value == null || value.trim().isEmpty) {
      return null; // Optional field
    }

    final number = int.tryParse(value.trim());
    if (number == null) {
      return '$fieldName חייב להיות מספר';
    }

    if (number < 0) {
      return '$fieldName לא יכול להיות שלילי';
    }

    return null;
  }

  /// Validate notes length
  static String? validateNotes(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Notes are optional
    }

    if (value.trim().length > 500) {
      return 'הערות לא יכולות להכיל יותר מ-500 תווים';
    }

    return null;
  }

  /// Validate Israeli phone number
  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Phone number is optional
    }

    // Remove any non-digit characters except dash
    final clean = value.replaceAll(RegExp(r'[^0-9-]'), '');

    // Check if matches allowed patterns
    if (!RegExp(r'^05[0-9]-?[0-9]{7}$').hasMatch(clean)) {
      return 'מספר טלפון חייב להיות בתבנית: 05XXXXXXXX או 05X-XXXXXXX';
    }

    // Ensure dash is only in correct position if present
    if (clean.contains('-')) {
      if (clean.indexOf('-') != 3 || clean.lastIndexOf('-') != 3) {
        return 'המקף יכול להופיע רק בין הספרה השלישית לרביעית';
      }
    }

    return null;
  }

  /// Format Israeli phone number for display
  static String formatPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null || phoneNumber.isEmpty) return '';

    // Remove any existing dash and other non-digit characters
    final clean = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');

    // Format as XXX-XXXXXXX if we have 10 digits
    if (clean.length == 10) {
      return '${clean.substring(0, 3)}-${clean.substring(3)}';
    }

    return phoneNumber;
  }

  /// Auto-format phone number as user types with smart dash handling
  static String autoFormatPhoneInput(String text, {bool isDeleting = false}) {
    // Remove any non-digit characters
    String clean = text.replaceAll(RegExp(r'[^0-9]'), '');

    // Limit to 10 digits
    if (clean.length > 10) {
      clean = clean.substring(0, 10);
    }

    // If deleting and we have 4+ digits, check if we need to delete the 3rd digit with the dash
    if (isDeleting && clean.length == 3) {
      // When deleting from 4 digits to 3, return only the first 3 digits (no dash)
      return clean;
    }

    // Auto-add dash after 3 digits
    if (clean.length >= 4) {
      return '${clean.substring(0, 3)}-${clean.substring(3)}';
    }

    return clean;
  }

  /// Combine multiple validators
  static String? combine(
    String? value,
    List<String? Function(String?)> validators,
  ) {
    for (final validator in validators) {
      final error = validator(value);
      if (error != null) {
        return error;
      }
    }
    return null;
  }
}
