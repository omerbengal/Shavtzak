import 'package:flutter/services.dart';

/// Text input formatter for Israeli phone numbers
/// Automatically adds dash after 3 digits when entering the 4th digit
/// Allows manual dash input after 3 digits
class PhoneNumberTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Handle selection-based deletion properly
    if (newValue.text.length < oldValue.text.length &&
        !oldValue.selection.isCollapsed) {
      // User has selected and deleted text
      return _handleSelectionDeletion(oldValue, newValue);
    }

    // Handle regular deletion (from end, backspace, etc.)
    final isDeleting = newValue.text.length < oldValue.text.length;

    // Get only digits from new value
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Limit to 10 digits
    if (digitsOnly.length > 10) {
      digitsOnly = digitsOnly.substring(0, 10);
    }

    // Build formatted string
    String formatted = digitsOnly;

    // Auto-add dash after 3 digits
    if (digitsOnly.length >= 4) {
      formatted = '${digitsOnly.substring(0, 3)}-${digitsOnly.substring(3)}';
    }

    // Special case: if user manually typed dash after exactly 3 digits
    if (!isDeleting &&
        newValue.text.endsWith('-') &&
        digitsOnly.length == 3 &&
        newValue.text.length == 4) {
      formatted = newValue.text; // Keep the dash user typed
    }

    // Determine cursor position
    int cursorPos = newValue.selection.baseOffset;

    // Adjust cursor position for auto-added dash
    if (!isDeleting &&
        formatted.contains('-') &&
        !oldValue.text.contains('-') &&
        cursorPos > 3) {
      // If we just added a dash and cursor was after position 3, shift it right by 1
      cursorPos += 1;
    } else if (cursorPos > formatted.length) {
      cursorPos = formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorPos),
    );
  }

  TextEditingValue _handleSelectionDeletion(TextEditingValue oldValue, TextEditingValue newValue) {
    // Extract remaining digits from the new value
    String newDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // If no digits left, return empty
    if (newDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Format the remaining digits
    String formatted = newDigits;
    if (newDigits.length >= 4) {
      formatted = '${newDigits.substring(0, 3)}-${newDigits.substring(3)}';
    }

    // Position cursor at the end of the formatted string
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}