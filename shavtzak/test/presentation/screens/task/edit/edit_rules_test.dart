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

  group('the editing screen search', () {
    final now = DateTime(2026, 1, 1);
    final dana = buildMember(id: 'm1', name: 'דנה כהן');
    final stage = buildStage(
      title: 'קליטה',
      notes: 'להביא שולחנות מהמחסן',
      hotelLocation: 'לובי קומה 2',
      requirements: 'מקרן וחשמל',
      contacts: const [
        StageContact(id: 'c', name: 'יוסי', role: 'אחראי משמרת', phone: '052-2010344'),
      ],
    );
    final bus = buildTask(
      id: 't1',
      title: 'להזמין אוטובוס',
      description: 'מהחניה הדרומית',
      subtasks: const [Subtask(id: 's', title: 'לאשר מחיר', isDone: false)],
      assemblyTime: '08:30',
      assignees: [dana],
      assigneeUpdate: 'הנהג מאשר',
    );
    final food = buildTask(
      id: 't2',
      title: 'ארוחת בוקר',
      assigneeIds: const ['m2'],
    );
    final board = EventTaskBoard(
      event: buildEvent(),
      stages: [stage],
      tasks: [bus, food],
    );
    List<String> visible(String query, {String? assignee}) => visibleStageTasks(
          board,
          stage,
          query: query,
          assigneeId: assignee,
          now: now,
        ).map((t) => t.id).toList();

    test('part of a stage note, location, requirements or contact finds the whole stage', () {
      for (final q in ['שולחנות מהמ', 'לובי', 'מקרן', 'יוסי', 'משמרת', '052-201', '0522010344']) {
        expect(visible(q), ['t1', 't2'], reason: q);
        expect(stageMatchesSearch(stage, q), isTrue, reason: q);
      }
    });

    test('a task match shows only that task', () {
      for (final q in ['אוטובוס', 'הדרומית', 'לאשר מחיר', 'דנה', '08:30', 'הנהג']) {
        expect(visible(q), ['t1'], reason: q);
      }
      expect(visible('בוקר'), ['t2']);
    });

    test('ignores case, Hebrew points and quotes', () {
      final quoted = buildStage(notes: 'תיאום עם צה"ל ו-Hotel');
      expect(stageMatchesSearch(quoted, 'צהל'), isTrue);
      expect(stageMatchesSearch(quoted, 'hotel'), isTrue);
      expect(stageMatchesSearch(buildStage(notes: 'שׁוּלְחָן'), 'שולחן'), isTrue);
    });

    test('no match hides every task; an empty query keeps them all', () {
      expect(visible('אין כזה'), isEmpty);
      expect(visible('  '), ['t1', 't2']);
    });

    test('the assignee filter still applies to a stage match', () {
      expect(visible('שולחנות', assignee: 'm2'), ['t2']);
    });

    test('a stage found by its own text shows even without tasks', () {
      expect(showStageCard(stage, const [], query: 'שולחנות', assigneeId: null), isTrue);
      expect(showStageCard(stage, const [], query: 'אין כזה', assigneeId: null), isFalse);
      expect(showStageCard(stage, const [], query: 'שולחנות', assigneeId: 'm1'), isFalse);
      expect(showStageCard(stage, const [], query: '', assigneeId: null), isTrue);
    });
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

    test('to any other task of the event, its stage or another, and only '
        'a value that has something', () {
      final elsewhere = buildTask(
        id: 'far',
        stage: buildStage(id: 's2', date: DateTime(2026, 6, 15)),
      );
      expect(canCopyField(from, empty, TaskField.description), isTrue);
      expect(canCopyField(from, from, TaskField.description), isFalse);
      expect(canCopyField(from, elsewhere, TaskField.description), isTrue);
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
