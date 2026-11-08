import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
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

  group('edgeScrollSpeed', () {
    double speed(double y) => edgeScrollSpeed(
        pointerY: y, top: 100, bottom: 900, edge: 64, maxSpeed: 1200);
    test('still in the middle', () {
      expect(speed(500), 0);
      expect(speed(164), 0);
      expect(speed(836), 0);
    });
    test('up near the top, faster nearer the edge', () {
      expect(speed(132), -600);
      expect(speed(100), -1200);
      expect(speed(40), -1200);
    });
    test('down near the bottom', () {
      expect(speed(868), 600);
      expect(speed(950), 1200);
    });
  });

  test('initials and first names', () {
    expect(initials('דנה כהן'), 'דכ');
    expect(firstName('דנה כהן'), 'דנה');
    expect(initials('יואב'), 'י');
  });

  group('reordering tasks due at the same moment', () {
    final stage = buildStage(id: 's1', date: DateTime(2026, 6, 15));
    final other = buildStage(id: 's2', date: DateTime(2026, 6, 15));
    TaskItem at(String id, String? time, {Stage? on}) =>
        buildTask(id: id, stage: on ?? stage, assemblyTime: time);

    test('only another task of the stage due at the same moment', () {
      final a = at('a', '09:00');
      expect(canReorderOnto(a, at('b', '09:00')), isTrue);
      expect(canReorderOnto(a, a), isFalse);
      expect(canReorderOnto(a, at('c', '09:30')), isFalse);
      expect(canReorderOnto(a, at('d', '09:00', on: other)), isFalse);
      expect(canReorderOnto(at('e', null), at('f', null)), isTrue);
    });

    test('puts the task before or after the target, numbering the stage', () {
      final early = at('early', '08:00');
      final a = at('a', '09:00');
      final b = at('b', '09:00');
      final c = at('c', '09:00');
      final stageTasks = [early, a, b, c];

      final before = reorderedStageTasks(stageTasks, c, a, after: false);
      expect(before.map((t) => t.id), ['early', 'c', 'a', 'b']);
      expect(before.map((t) => t.order), [0, 1, 2, 3]);

      final after = reorderedStageTasks(stageTasks, a, c, after: true);
      expect(after.map((t) => t.id), ['early', 'b', 'c', 'a']);

      expect(orderChanged(stageTasks, before), isTrue);
      final same = reorderedStageTasks(stageTasks, a, b, after: false);
      expect(orderChanged(stageTasks, same), isFalse);
    });
  });

  group('copying a value to another task', () {
    final stage = buildStage(id: 's1', date: DateTime(2026, 6, 15));
    final from = buildTask(
      id: 'from',
      stage: stage,
      assemblyTime: '09:00',
      description: 'להביא שלטים',
      assigneeIds: const ['m1', 'm2'],
      subtasks: const [
        Subtask(id: 'x', title: 'הדפסה', isDone: true),
        Subtask(id: 'y', title: 'תלייה'),
      ],
    );
    final empty = buildTask(id: 'to', stage: stage, assigneeIds: const ['m3']);

    test('only within the stage, and only a value that has something', () {
      final elsewhere = buildTask(
        id: 'far',
        stage: buildStage(id: 's2', date: DateTime(2026, 6, 15)),
      );
      expect(canCopyField(from, empty, TaskField.description), isTrue);
      expect(canCopyField(from, from, TaskField.description), isFalse);
      expect(canCopyField(from, elsewhere, TaskField.description), isFalse);
      expect(canCopyField(empty, from, TaskField.description), isFalse);
    });

    test('empty and same', () {
      expect(isTaskFieldEmpty(empty, TaskField.time), isTrue);
      expect(isTaskFieldEmpty(empty, TaskField.subtasks), isTrue);
      expect(isTaskFieldEmpty(empty, TaskField.assignees), isFalse);
      expect(
        sameTaskField(
          from,
          from.copyWith(assigneeIds: const ['m2', 'm1']),
          TaskField.assignees,
        ),
        isTrue,
      );
      expect(sameTaskField(from, empty, TaskField.description), isFalse);
    });

    test('copies each value; subtasks come new and unticked', () {
      var n = 0;
      String newId() => 'new${n++}';
      expect(
        copyTaskField(from, empty, TaskField.time, newId: newId).assemblyTime,
        '09:00',
      );
      expect(
        copyTaskField(from, empty, TaskField.description, newId: newId)
            .description,
        'להביא שלטים',
      );
      expect(
        copyTaskField(from, empty, TaskField.assignees, newId: newId)
            .assigneeIds,
        ['m1', 'm2'],
      );
      final subtasks =
          copyTaskField(from, empty, TaskField.subtasks, newId: newId).subtasks;
      expect(subtasks.map((s) => s.title), ['הדפסה', 'תלייה']);
      expect(subtasks.map((s) => s.id), ['new0', 'new1']);
      expect(subtasks.every((s) => !s.isDone), isTrue);
    });
  });
}
