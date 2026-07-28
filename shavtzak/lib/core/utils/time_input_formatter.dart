import 'package:flutter/services.dart';

/// The `HH:mm` shape a finished time field must hold. Accepts an unpadded hour
/// (`9:05`) because values stored before this field became typable may not be
/// padded.
final RegExp _validTime = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');

/// Masks free typing into an `HH:mm` shape for the event time fields.
///
/// Digits only, capped at four, with the colon inserted once a third digit
/// arrives: `1` → `1`, `18` → `18`, `180` → `18:0`, `1800` → `18:00`.
///
/// Impossible times are deliberately allowed through — `25:70` is typable — so
/// the formatter never fights the keyboard. `Validators.validateOptionalTime`
/// catches them when the form is saved.
class TimeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 4) {
      digits = digits.substring(0, 4);
    }

    final formatted = digits.length > 2
        ? '${digits.substring(0, 2)}:${digits.substring(2)}'
        : digits;

    // The field is five characters wide and the mask is rebuilt from the digits
    // on every edit, so parking the caret at the end is both simpler and what
    // typing and backspacing both want.
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Fills in what the admin did not type, once they leave the field.
///
/// `9` → `09:00`, `18` → `18:00`, `18:3` → `18:30`. Minutes are typed
/// tens-first, so a lone minute digit is the tens place.
///
/// Two guards keep this from corrupting a value:
///   * text that is already a valid time is returned untouched, so a stored
///     `9:05` is not re-read as three digits and rewritten to `90:50`;
///   * a completion that would not itself be a valid time is discarded and the
///     raw text kept, so `93` stays `93` and is flagged on save rather than
///     silently becoming `93:00`.
String completePartialTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (_validTime.hasMatch(text)) return text;

  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return text;

  final completed = switch (digits.length) {
    1 || 2 => '${digits.padLeft(2, '0')}:00',
    3 => '${digits.substring(0, 2)}:${digits.substring(2)}0',
    _ => '${digits.substring(0, 2)}:${digits.substring(2, 4)}',
  };

  return _validTime.hasMatch(completed) ? completed : text;
}
