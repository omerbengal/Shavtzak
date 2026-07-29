import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/time_input_formatter.dart';

/// A `TextEditingValue` with the caret parked at the end, which is where it
/// sits during ordinary typing.
TextEditingValue _at(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

/// Replay [keystrokes] one character at a time through the formatter and
/// return what the field ends up showing.
String _type(String keystrokes) {
  final formatter = TimeTextInputFormatter();
  var value = TextEditingValue.empty;
  for (final char in keystrokes.split('')) {
    value = formatter.formatEditUpdate(value, _at(value.text + char));
  }
  return value.text;
}

/// One backspace against a field currently showing [current].
String _backspace(String current) {
  final shortened =
      current.isEmpty ? '' : current.substring(0, current.length - 1);
  return TimeTextInputFormatter()
      .formatEditUpdate(_at(current), _at(shortened))
      .text;
}

void main() {
  group('TimeTextInputFormatter', () {
    test('lays typed digits into HH:mm, colon appearing on the third digit',
        () {
      expect(_type('1'), '1');
      expect(_type('18'), '18');
      expect(_type('180'), '18:0');
      expect(_type('1800'), '18:00');
    });

    test('lets an impossible time be typed — save-time validation catches it',
        () {
      expect(_type('2570'), '25:70');
      expect(_type('1875'), '18:75');
    });

    test('drops digits past the fourth', () {
      expect(_type('180099'), '18:00');
    });

    test('strips everything that is not a digit', () {
      final formatter = TimeTextInputFormatter();
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, _at('a1b8c0d0')).text,
        '18:00',
      );
    });

    test('accepts a pasted time, with or without its colon', () {
      final formatter = TimeTextInputFormatter();
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, _at('18:00')).text,
        '18:00',
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, _at('1800')).text,
        '18:00',
      );
    });

    test('backspace walks back down the same ladder', () {
      expect(_backspace('18:00'), '18:0');
      expect(_backspace('18:0'), '18');
      expect(_backspace('18'), '1');
      expect(_backspace('1'), '');
    });

    test('leaves the caret at the end of the formatted text', () {
      final formatter = TimeTextInputFormatter();
      final result =
          formatter.formatEditUpdate(_at('18'), _at('180'));
      expect(result.text, '18:0');
      expect(result.selection.baseOffset, 4);
    });
  });

  group('completePartialTime', () {
    test('leaves an empty field empty — every time field is optional', () {
      expect(completePartialTime(''), '');
      expect(completePartialTime('   '), '');
    });

    test('fills in the minutes when only an hour was typed', () {
      expect(completePartialTime('18'), '18:00');
      expect(completePartialTime('9'), '09:00');
      expect(completePartialTime('0'), '00:00');
    });

    test('reads a lone minute digit as the tens place', () {
      expect(completePartialTime('18:3'), '18:30');
      expect(completePartialTime('183'), '18:30');
    });

    test('returns an already-valid time untouched', () {
      expect(completePartialTime('18:00'), '18:00');
      expect(completePartialTime('00:00'), '00:00');
      expect(completePartialTime('23:59'), '23:59');
    });

    test('does not rewrite a stored unpadded time such as 9:05', () {
      // Three digits, so the tens-first rule would otherwise turn this into
      // 90:50. Hydrated values never pass through the input formatter, so the
      // already-valid guard is the only thing protecting them.
      expect(completePartialTime('9:05'), '9:05');
    });

    test('keeps the raw text when completing it would not be a real time', () {
      // 93 would complete to 93:00. Better to leave 93 on screen and let the
      // validator flag it than to invent a wrong time.
      expect(completePartialTime('93'), '93');
      expect(completePartialTime('99'), '99');
    });

    test('leaves a full but impossible time alone', () {
      expect(completePartialTime('25:70'), '25:70');
      expect(completePartialTime('24:00'), '24:00');
    });

    test('leaves non-digit text untouched instead of crashing', () {
      // Without the digits.isEmpty guard, the fallback branch would call
      // substring(0, 2) on an empty string and throw a RangeError.
      expect(completePartialTime('abc'), 'abc');
    });

    test('more than four digits truncates to the first four', () {
      // Intentional, not incidental: the switch's fallback branch only ever
      // reads digits[0:2] and digits[2:4], so anything typed past the fourth
      // digit is silently dropped.
      expect(completePartialTime('18:00:00'), '18:00');
    });
  });
}
