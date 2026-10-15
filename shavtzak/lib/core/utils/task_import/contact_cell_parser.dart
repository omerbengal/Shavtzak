import '../../../domain/entities/stage.dart';
import 'cell_values.dart';

/// The "אנשי קשר" cell of an import file:
/// `שם: הלל, טלפון: 0522010344, תפקיד: צייר | שם: יוכי, ...`.
///
/// Entries are split on `|`. Inside an entry each of the three labels is
/// followed by a colon; a value runs until the next label, so commas and
/// colons inside a value are kept.

const int maxImportContacts = 30;
const int _maxContactText = 100;

class ContactCellResult {
  const ContactCellResult(this.contacts, this.problems);

  final List<StageContact> contacts;

  /// Without a sheet or row; the caller adds those.
  final List<String> problems;
}

// A label is not part of a longer word: "רשם:" is no label.
final RegExp _label =
    RegExp(r'(?<![א-תA-Za-z])(שם|טלפון|תפקיד)\s*:');

// One or two words and a colon right after a comma inside a value: a label
// this format does not know, such as ", מייל:". "(מהשעה 10:30)" is not one.
final RegExp _unknownLabel = RegExp(
  r',\s*([א-תA-Za-z]+(?: [א-תA-Za-z]+)?)\s*:',
);

final RegExp _trailingCommas = RegExp(r'[,\s]+$');
final RegExp _notDigit = RegExp(r'\D');

ContactCellResult parseContactCell(
  String cell, {
  required String Function() newId,
}) {
  final contacts = <StageContact>[];
  final problems = <String>[];
  final entries = cleanText(cell)
      .split('|')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();

  for (var index = 0; index < entries.length; index++) {
    final where = 'איש קשר ${index + 1}';
    final entry = entries[index];
    final labels = _label.allMatches(entry).toList();
    if (labels.isEmpty) {
      problems.add('$where: לא נמצאו "שם:", "טלפון:" או "תפקיד:"');
      continue;
    }

    var isValid = true;
    final before = _value(entry.substring(0, labels.first.start));
    if (before.isNotEmpty) {
      problems.add('$where: טקסט לא מזוהה "$before"');
      isValid = false;
    }

    final values = <String, String>{};
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i].group(1)!;
      final end = i + 1 < labels.length ? labels[i + 1].start : entry.length;
      final value = _value(entry.substring(labels[i].end, end));
      if (values.containsKey(label)) {
        problems.add('$where: "$label" מופיע פעמיים');
        isValid = false;
        continue;
      }
      final unknown = _unknownLabel.firstMatch(value);
      if (unknown != null) {
        problems.add('$where: תווית לא מוכרת "${unknown.group(1)}"');
        isValid = false;
      }
      values[label] = value;
    }

    final name = values['שם'] ?? '';
    final phoneText = values['טלפון'] ?? '';
    final role = values['תפקיד'] ?? '';
    final who = name.isEmpty ? where : '$where ($name)';

    if (name.isEmpty) {
      problems.add('$where: חסר שם');
      isValid = false;
    } else if (name.length > _maxContactText) {
      problems.add('$who: השם ארוך מ-$_maxContactText תווים');
      isValid = false;
    }
    if (role.length > _maxContactText) {
      problems.add('$who: התפקיד ארוך מ-$_maxContactText תווים');
      isValid = false;
    }

    var phone = '';
    if (phoneText.isNotEmpty) {
      final digits = phoneText.replaceAll(_notDigit, '');
      if (digits.length != 10 || !digits.startsWith('05')) {
        problems.add(
          '$who: מספר הטלפון "$phoneText" אינו מספר נייד תקין (05X-XXXXXXX)',
        );
        isValid = false;
      } else {
        // The team-member format, the same as a phone typed in the form.
        phone = '${digits.substring(0, 3)}-${digits.substring(3)}';
      }
    }

    if (isValid) {
      contacts.add(
        StageContact(id: newId(), name: name, phone: phone, role: role),
      );
    }
  }

  if (entries.length > maxImportContacts) {
    problems.add('יותר מ-$maxImportContacts אנשי קשר');
  }
  return ContactCellResult(contacts, problems);
}

String _value(String raw) => raw.trim().replaceAll(_trailingCommas, '').trim();
