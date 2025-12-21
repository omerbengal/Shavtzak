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
    // Check if user is deleting
    final isDeleting = newValue.text.length < oldValue.text.length;

    
    // Special handling for deletion around the dash
    if (isDeleting && oldValue.text.contains('-') && oldValue.text[3] == '-') {
      // If we had a dash and now we don't, or if we're deleting from the end
      if (!newValue.text.contains('-') || newValue.text.length < 4) {
        // User is deleting the 4th digit or the dash
        // Return just the first 3 digits
        String firstThree = oldValue.text.substring(0, 3);
        return TextEditingValue(
          text: firstThree,
          selection: TextSelection.collapsed(offset: 3),
        );
      }
    }

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

    // If we just auto-added the dash
    if (!isDeleting &&
        formatted.contains('-') &&
        !oldValue.text.contains('-')) {
      // Place cursor at the end
      cursorPos = formatted.length;
    } else if (cursorPos > formatted.length) {
      cursorPos = formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorPos),
    );
  }
}