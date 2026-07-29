import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/validators.dart';

void main() {
  group('Validators.validateOptionalTime', () {
    test('an empty value passes — the event time fields are all optional', () {
      expect(Validators.validateOptionalTime(null), isNull);
      expect(Validators.validateOptionalTime(''), isNull);
      expect(Validators.validateOptionalTime('   '), isNull);
    });

    test('a real time passes', () {
      expect(Validators.validateOptionalTime('18:00'), isNull);
      expect(Validators.validateOptionalTime('00:00'), isNull);
      expect(Validators.validateOptionalTime('23:59'), isNull);
    });

    test('an unpadded hour passes, for values stored before this change', () {
      expect(Validators.validateOptionalTime('9:05'), isNull);
    });

    test('surrounding whitespace is ignored', () {
      expect(Validators.validateOptionalTime(' 18:00 '), isNull);
    });

    test('an out-of-range hour or minute is rejected', () {
      expect(Validators.validateOptionalTime('24:00'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('25:70'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('18:60'), 'פורמט שעה לא תקין');
    });

    test('an incomplete or non-numeric value is rejected', () {
      expect(Validators.validateOptionalTime('18'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('93'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('18:'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('abc'), 'פורמט שעה לא תקין');
    });
  });
}
