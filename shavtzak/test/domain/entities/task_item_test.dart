import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/team_member_model.dart';
import 'package:shavtzak/domain/entities/subtask.dart';

import '../../support/task_fixtures.dart';

void main() {
  group('Subtask', () {
    test('defaults to not done', () {
      expect(const Subtask(id: 'a', title: 'שלב').isDone, isFalse);
    });

    test('is equal by value and differs when any field differs', () {
      const base = Subtask(id: 'a', title: 'שלב');
      expect(base, const Subtask(id: 'a', title: 'שלב'));
      expect(base, isNot(const Subtask(id: 'b', title: 'שלב')));
      expect(base, isNot(const Subtask(id: 'a', title: 'אחר')));
      expect(base, isNot(base.copyWith(isDone: true)));
    });
  });

  group('TaskItem progress', () {
    test('a task without subtasks has no progress', () {
      final task = buildTask();
      expect(task.hasSubtasks, isFalse);
      expect(task.doneSubtaskCount, 0);
      expect(task.progress, 0);
    });

    test('counts done subtasks', () {
      final task = buildTask(subtasks: const [
        Subtask(id: 'a', title: 'א', isDone: true),
        Subtask(id: 'b', title: 'ב'),
        Subtask(id: 'c', title: 'ג'),
      ]);
      expect(task.hasSubtasks, isTrue);
      expect(task.doneSubtaskCount, 1);
      expect(task.progress, closeTo(1 / 3, 0.0001));
    });

    test('is at full progress when every subtask is done', () {
      final task = buildTask(subtasks: const [
        Subtask(id: 'a', title: 'א', isDone: true),
        Subtask(id: 'b', title: 'ב', isDone: true),
      ]);
      expect(task.doneSubtaskCount, 2);
      expect(task.progress, 1);
    });
  });

  group('TaskItem assignment', () {
    test('isAssignedTo is membership in assigneeIds', () {
      final task = buildTask(assigneeIds: const ['m1', 'm2']);
      expect(task.isAssignedTo('m2'), isTrue);
      expect(task.isAssignedTo('m3'), isFalse);
    });
  });

  group('TaskItem equality (drives real-time rebuilds)', () {
    test('two tasks built from the same values are equal', () {
      expect(buildTask(), buildTask());
    });

    test('changes when a subtask is ticked', () {
      final open = buildTask(subtasks: const [Subtask(id: 'a', title: 'א')]);
      final ticked = buildTask(
        subtasks: const [Subtask(id: 'a', title: 'א', isDone: true)],
      );
      expect(open, isNot(ticked));
    });

    test('changes when the populated event changes but its id does not', () {
      final before = buildTask(event: buildEvent(location: 'חיפה'));
      final after = buildTask(event: buildEvent(location: 'עכו'));
      expect(before, isNot(after));
    });

    test('changes when a populated assignee is renamed', () {
      final before = buildTask(assignees: [buildMember(name: 'דנה')]);
      final after = buildTask(assignees: [buildMember(name: 'דנה כהן')]);
      expect(before, isNot(after));
    });

    test('changes for each scalar field', () {
      final base = buildTask();
      final variants = [
        buildTask(title: 'אחר'),
        buildTask(description: 'פירוט'),
        buildTask(eventId: 'e2'),
        buildTask(stageId: 'st2'),
        buildTask(assemblyTime: '08:00'),
        buildTask(stage: buildStage(title: 'ערב')),
        buildTask(assigneeIds: const ['m2']),
        buildTask(assigneeUpdate: 'בטיפול'),
        buildTask(assigneeUpdateAt: DateTime(2026, 10, 2)),
        buildTask(assigneeUpdateById: 'm1'),
        buildTask(assigneeUpdateByName: 'דנה'),
        buildTask(isComplete: true),
        buildTask(completedAt: DateTime(2026, 10, 2)),
        buildTask(completedById: 'm1'),
        buildTask(updatedAt: DateTime(2026, 10, 3)),
        buildTask(createdById: 'm2'),
      ];
      for (final variant in variants) {
        expect(variant, isNot(base));
      }
    });
  });

  group('TaskItem.copyWith', () {
    test('keeps untouched fields', () {
      final task = buildTask(
        assemblyTime: '08:00',
        assigneeUpdate: 'בטיפול',
      );
      final copy = task.copyWith(title: 'חדש');
      expect(copy.title, 'חדש');
      expect(copy.assemblyTime, '08:00');
      expect(copy.stageId, task.stageId);
      expect(copy.assigneeUpdate, 'בטיפול');
      expect(copy.id, task.id);
    });

    test('clearAssemblyTime removes the assembly time', () {
      final task = buildTask(assemblyTime: '08:00');
      expect(task.copyWith(clearAssemblyTime: true).assemblyTime, isNull);
    });
  });

  group('TaskItem.dueAt', () {
    final stage = buildStage(date: DateTime(2026, 10, 21));

    test('is the stage day at the assembly time', () {
      final task = buildTask(stage: stage, assemblyTime: '09:30');
      expect(task.dueAt, DateTime(2026, 10, 21, 9, 30));
    });

    test('is the end of the stage day when there is no assembly time', () {
      final task = buildTask(stage: stage);
      expect(task.dueAt, DateTime(2026, 10, 21, 23, 59));
    });

    test('is null while the stage is unknown', () {
      expect(buildTask(assemblyTime: '09:30').dueAt, isNull);
    });

    test('follows the stage when the stage moves', () {
      final task = buildTask(stage: stage, assemblyTime: '09:30');
      final moved = task.copyWith(
        stage: stage.copyWith(date: DateTime(2026, 10, 22)),
      );
      expect(moved.dueAt, DateTime(2026, 10, 22, 9, 30));
    });
  });

  group('TeamMember.canManageTasks', () {
    test('defaults to false', () {
      expect(buildMember().canManageTasks, isFalse);
    });

    test('takes part in equality and copyWith', () {
      final member = buildMember();
      final manager = member.copyWith(canManageTasks: true);
      expect(manager.canManageTasks, isTrue);
      expect(manager, isNot(member));
    });

    test('survives the model round trip to the backend payload and back', () {
      final manager = buildMember(canManageTasks: true);
      final json = TeamMemberModel.fromEntity(manager).toJson();
      expect(json['canManageTasks'], isTrue);
      expect(TeamMemberModel.fromJson(json).toEntity().canManageTasks, isTrue);
    });

    test('is written to the Firestore map', () {
      final manager = buildMember(canManageTasks: true);
      expect(
        TeamMemberModel.fromEntity(manager).toFirestore()['canManageTasks'],
        isTrue,
      );
    });

    test('reads as false from a payload written before the flag existed', () {
      final json = TeamMemberModel.fromEntity(buildMember()).toJson()
        ..remove('canManageTasks');
      expect(TeamMemberModel.fromJson(json).toEntity().canManageTasks, isFalse);
    });
  });
}
