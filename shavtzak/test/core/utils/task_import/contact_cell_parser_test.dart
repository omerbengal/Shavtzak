import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/contact_cell_parser.dart';

void main() {
  var counter = 0;
  String newId() => 'c${++counter}';
  setUp(() => counter = 0);

  ContactCellResult parse(String cell) => parseContactCell(cell, newId: newId);

  test('reads the sample file\'s cell', () {
    final result = parse(
      'שם: הלל, טלפון: 0522010344, תפקיד: צייר קריקטורה (מהשעה 10:30) | '
      'שם:יוכי, טלפון: 050-628-5016\u2069, תפקיד: ביטוח לאומי | '
      'שם: אמיר פידלמן, טלפון: 052-2756524\u2069, תפקיד: קרן הסיוע',
    );

    expect(result.problems, isEmpty);
    expect(result.contacts.map((c) => [c.name, c.phone, c.role]), [
      ['הלל', '052-2010344', 'צייר קריקטורה (מהשעה 10:30)'],
      ['יוכי', '050-6285016', 'ביטוח לאומי'],
      ['אמיר פידלמן', '052-2756524', 'קרן הסיוע'],
    ]);
    expect(result.contacts.map((c) => c.id), ['c1', 'c2', 'c3']);
  });

  test('labels may come in any order; phone and role are optional', () {
    final result = parse('תפקיד: קבלה, שם: דנה | שם: אבי');
    expect(result.problems, isEmpty);
    expect(result.contacts.map((c) => [c.name, c.phone, c.role]), [
      ['דנה', '', 'קבלה'],
      ['אבי', '', ''],
    ]);
  });

  test('a comma inside a value stays in it', () {
    final result = parse('שם: רונית, תפקיד: מנהלת אירועים, קומה 2');
    expect(result.problems, isEmpty);
    expect(result.contacts.single.role, 'מנהלת אירועים, קומה 2');
  });

  test('contacts may also be one per line', () {
    final result = parse('שם: דנה, טלפון: 0501234567\nשם: אבי, תפקיד: קבלה');
    expect(result.problems, isEmpty);
    expect(result.contacts.map((c) => c.name), ['דנה', 'אבי']);
  });

  test('an empty cell or empty entries give nothing', () {
    expect(parse('').contacts, isEmpty);
    expect(parse(' | ').problems, isEmpty);
  });

  test('a contact without a name is a problem', () {
    final result = parse('טלפון: 0501234567');
    expect(result.contacts, isEmpty);
    expect(result.problems, ['איש קשר 1: חסר שם']);
  });

  test('a phone that is not a mobile number is a problem', () {
    final result = parse('שם: אבי, טלפון: 02-6234567');
    expect(result.contacts, isEmpty);
    expect(
      result.problems.single,
      contains('איש קשר 1 (אבי): מספר הטלפון "02-6234567"'),
    );
  });

  test('text before the first label is a problem', () {
    expect(parse('אבי 0501234567').problems.single, contains('איש קשר 1'));
    expect(
      parse('אבי, שם: דנה').problems.single,
      contains('טקסט לא מזוהה "אבי"'),
    );
  });

  test('an unknown label is a problem', () {
    expect(
      parse('שם: אבי, מייל: avi@example.com').problems.single,
      contains('תווית לא מוכרת "מייל"'),
    );
  });

  test('a label twice in one contact is a problem', () {
    expect(
      parse('שם: אבי, שם: דנה').problems.single,
      contains('"שם" מופיע פעמיים'),
    );
  });

  test('long names and roles, and too many contacts, are problems', () {
    expect(parse('שם: ${'א' * 101}').problems.single, contains('ארוך מ-100'));
    final many =
        List.generate(maxImportContacts + 1, (i) => 'שם: איש $i').join(' | ');
    expect(parse(many).problems, contains('יותר מ-$maxImportContacts אנשי קשר'));
  });
}
