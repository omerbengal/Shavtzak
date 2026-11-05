import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/presentation/screens/task/edit/edit_rules.dart';

import '../../../../support/task_fixtures.dart';

void main() {
  group('validateStageTimes', () {
    test('end without start is refused', () {
      expect(validateStageTimes('', '10:00'), 'שעת סיום דורשת שעת התחלה.');
    });
    test('end not after start is refused', () {
      expect(validateStageTimes('10:00', '10:00'),
          'שעת הסיום חייבת להיות אחרי שעת ההתחלה.');
    });
    test('a bad start is refused', () {
      expect(validateStageTimes('9', ''), contains('שעת ההתחלה אינה תקינה'));
    });
    test('valid and empty pass', () {
      expect(validateStageTimes('08:00', '09:30'), isNull);
      expect(validateStageTimes('', ''), isNull);
      expect(validateStageTimes('08:00', ''), isNull);
    });
  });

  test('validateContacts needs a name and a valid phone', () {
    expect(validateContacts(const [StageContact(id: 'c', name: ' ')]),
        'לכל איש קשר נדרש שם.');
    expect(
      validateContacts(const [StageContact(id: 'c', name: 'הלל', phone: '12')]),
      startsWith('הטלפון של הלל'),
    );
    expect(
      validateContacts(
          const [StageContact(id: 'c', name: 'הלל', phone: '0522010344')]),
      isNull,
    );
  });

  test('assigneeFilterMembers includes a removed member still on a task', () {
    final dana = buildMember(id: 'm1', name: 'דנה');
    final gone = buildMember(id: 'm9', name: 'אביב');
    final board = EventTaskBoard(
      event: buildEvent(),
      stages: [buildStage()],
      tasks: [
        buildTask(assigneeIds: const ['m9'], assignees: [gone]),
      ],
    );
    expect(
      assigneeFilterMembers(board, [dana]).map((m) => m.id),
      ['m9', 'm1'],
    );
  });

  test('initials and first names', () {
    expect(initials('דנה כהן'), 'דכ');
    expect(firstName('דנה כהן'), 'דנה');
    expect(initials('יואב'), 'י');
  });
}
