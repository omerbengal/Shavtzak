import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/native_field_rules.dart';

void main() {
  group('cleanNativeText', () {
    test('drops invisible marks and turns non-breaking spaces into spaces', () {
      expect(cleanNativeText('‏שלום עולם​﻿‎'),
          'שלום עולם');
    });

    test('keeps line breaks and plain text as is', () {
      expect(cleanNativeText('שורה\n\nעוד'), 'שורה\n\nעוד');
    });
  });

  group('nativeFieldLines', () {
    test('an empty text has no lines, so the hint shows', () {
      expect(nativeFieldLines(''), isEmpty);
    });

    test('empty lines in the middle and at the end are kept', () {
      expect(nativeFieldLines('א\n\nב\n'), ['א', '', 'ב', '']);
    });
  });

  group('nativeEnterKeyHint', () {
    test('maps the actions the app uses', () {
      expect(nativeEnterKeyHint(TextInputAction.search, multiline: false),
          'search');
      expect(nativeEnterKeyHint(TextInputAction.next, multiline: false), 'next');
      expect(nativeEnterKeyHint(TextInputAction.done, multiline: false), 'done');
      expect(nativeEnterKeyHint(TextInputAction.send, multiline: true), 'send');
      expect(nativeEnterKeyHint(TextInputAction.newline, multiline: true),
          'enter');
    });

    test('no action: a new line in several lines, done in one', () {
      expect(nativeEnterKeyHint(null, multiline: true), 'enter');
      expect(nativeEnterKeyHint(null, multiline: false), 'done');
    });
  });

  test('nativeInputMode picks the phone keyboard', () {
    expect(nativeInputMode(TextInputType.emailAddress), 'email');
    expect(nativeInputMode(TextInputType.phone), 'tel');
    expect(nativeInputMode(TextInputType.number), 'numeric');
    expect(nativeInputMode(TextInputType.multiline), 'text');
    expect(nativeInputMode(null), 'text');
  });

  group('nativeFieldHeight', () {
    test('at least minLines', () {
      expect(
          nativeFieldHeight(
              contentHeight: 10, lineHeight: 24, minLines: 2, maxLines: 5),
          48);
    });

    test('grows with the text up to maxLines', () {
      expect(
          nativeFieldHeight(
              contentHeight: 72, lineHeight: 24, minLines: 2, maxLines: 5),
          72);
      expect(
          nativeFieldHeight(
              contentHeight: 500, lineHeight: 24, minLines: 2, maxLines: 5),
          120);
    });

    test('no maxLines: grows up to the cap, then scrolls', () {
      expect(
          nativeFieldHeight(
              contentHeight: 1000, lineHeight: 24, minLines: 1, maxLines: null),
          340);
    });

    test('maxLines below minLines never shrinks under minLines', () {
      expect(
          nativeFieldHeight(
              contentHeight: 0, lineHeight: 20, minLines: 3, maxLines: 1),
          60);
    });
  });

  group('nativeExceedsMaxLength', () {
    test('no limit never exceeds', () {
      expect(
          nativeExceedsMaxLength(
              length: 9999, selected: 0, inserted: 10, maxLength: null),
          isFalse);
    });

    test('typing over a selection counts the replaced letters', () {
      expect(
          nativeExceedsMaxLength(
              length: 10, selected: 3, inserted: 3, maxLength: 10),
          isFalse);
      expect(
          nativeExceedsMaxLength(
              length: 10, selected: 0, inserted: 1, maxLength: 10),
          isTrue);
    });
  });

  group('nativeCounterText', () {
    test('as TextField writes it', () {
      expect(nativeCounterText(length: 3, maxLength: 200), '3/200');
    });

    test('a given counter text wins (counterText: "" hides it)', () {
      expect(nativeCounterText(length: 3, maxLength: 200, counterText: ''), '');
    });

    test('no maxLength, no counter', () {
      expect(nativeCounterText(length: 3, maxLength: null), isNull);
    });
  });

  test('the field keeps every key but Tab and Escape', () {
    expect(nativeFieldKeepsKey(LogicalKeyboardKey.arrowLeft), isTrue);
    expect(nativeFieldKeepsKey(LogicalKeyboardKey.space), isTrue);
    expect(nativeFieldKeepsKey(LogicalKeyboardKey.enter), isTrue);
    expect(nativeFieldKeepsKey(LogicalKeyboardKey.tab), isFalse);
    expect(nativeFieldKeepsKey(LogicalKeyboardKey.escape), isFalse);
  });
}
