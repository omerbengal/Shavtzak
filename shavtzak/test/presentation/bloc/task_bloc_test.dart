import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';

import '../../support/task_fixtures.dart';

/// A repository whose stream the test drives and whose mutations can be made
/// to fail.
class _FakeTaskRepository extends Fake implements TaskRepository {
  StreamController<TaskBoard> controller = StreamController<TaskBoard>();
  int watchCalls = 0;
  final calls = <String>[];
  Object? failWith;

  /// While set, a mutation does not answer until the test completes it. Each
  /// call keeps the gate it started under.
  Completer<void>? gate;

  @override
  Stream<TaskBoard> watchBoard() {
    watchCalls++;
    return controller.stream;
  }

  void emit(List<TaskItem> tasks) => controller.add(TaskBoard(tasks: tasks));

  Future<void> _record(String call) async {
    calls.add(call);
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<void> insertTask(TaskItem task) => _record('insert:${task.id}');

  @override
  Future<void> updateTask(TaskItem task) => _record('update:${task.id}');

  @override
  Future<void> deleteTask(String taskId) => _record('delete:$taskId');

  @override
  Future<void> setSubtaskDone(String taskId, String subtaskId, bool isDone) =>
      _record('subtask:$taskId:$subtaskId:$isDone');

  @override
  Future<void> setTaskComplete(String taskId, bool isComplete) =>
      _record('complete:$taskId:$isComplete');

  @override
  Future<void> setTaskAssigneeUpdate(String taskId, String text) =>
      _record('note:$taskId:$text');

  @override
  Future<void> insertStage(Stage stage) => _record('insertStage:${stage.id}');

  @override
  Future<void> updateStage(Stage stage) => _record('updateStage:${stage.id}');

  @override
  Future<void> deleteStage(String stageId) => _record('deleteStage:$stageId');
}

void main() {
  late _FakeTaskRepository repository;

  setUp(() {
    repository = _FakeTaskRepository();
  });

  tearDown(() {
    // Not awaited: closing a controller nobody listened to never completes.
    if (!repository.controller.isClosed) {
      unawaited(repository.controller.close());
    }
  });

  // What the bloc stamps on a task it shows as completed before the backend
  // has answered.
  final tickedAt = DateTime(2026, 10, 11, 14, 5);

  TaskBloc buildBloc() =>
      TaskBloc(repository: repository, clock: () => tickedAt);

  group('LoadTasks', () {
    blocTest<TaskBloc, TaskState>(
      'emits loading, then the tasks, then again on every stream update',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.emit([buildTask(id: 't1')]);
        await Future<void>.delayed(Duration.zero);
        repository.emit([buildTask(id: 't1', isComplete: true)]);
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded([buildTask(id: 't1')]),
        TasksLoaded([buildTask(id: 't1', isComplete: true)]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'carries the events and members the form picks from',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.controller.add(TaskBoard(
          tasks: [buildTask()],
          events: [buildEvent()],
          members: [buildMember()],
        ));
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded(
          [buildTask()],
          events: [buildEvent()],
          members: [buildMember()],
        ),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'carries the stages, and a moved stage is a new state',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.controller.add(TaskBoard(
          tasks: const [],
          stages: [buildStage(date: DateTime(2026, 10, 21))],
        ));
        await Future<void>.delayed(Duration.zero);
        repository.controller.add(TaskBoard(
          tasks: const [],
          stages: [buildStage(date: DateTime(2026, 10, 22))],
        ));
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded(const [], stages: [buildStage(date: DateTime(2026, 10, 21))]),
        TasksLoaded(const [], stages: [buildStage(date: DateTime(2026, 10, 22))]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'a renamed event is a new state even when no task changed',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.controller.add(TaskBoard(
          tasks: const [],
          events: [buildEvent(name: 'שם ישן')],
        ));
        await Future<void>.delayed(Duration.zero);
        repository.controller.add(TaskBoard(
          tasks: const [],
          events: [buildEvent(name: 'שם חדש')],
        ));
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded(const [], events: [buildEvent(name: 'שם ישן')]),
        TasksLoaded(const [], events: [buildEvent(name: 'שם חדש')]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'a second LoadTasks while already watching does not subscribe again',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.emit([buildTask()]);
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded([buildTask()]),
      ],
      verify: (_) => expect(repository.watchCalls, 1),
    );

    blocTest<TaskBloc, TaskState>(
      'a stream error becomes an error state',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.controller.addError(Exception('permission-denied'));
      },
      expect: () => [
        const TasksLoading(),
        isA<TasksError>(),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'a stream that errors without closing can still be retried',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        // A dead Firestore listener reports an error and then just sits
        // there: it never closes.
        repository.controller.addError(Exception('permission-denied'));
        await Future<void>.delayed(Duration.zero);

        repository.controller = StreamController<TaskBoard>();
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.emit([buildTask(id: 'new')]);
      },
      expect: () => [
        const TasksLoading(),
        isA<TasksError>(),
        const TasksLoading(),
        TasksLoaded([buildTask(id: 'new')]),
      ],
      verify: (_) => expect(repository.watchCalls, 2),
    );

    blocTest<TaskBloc, TaskState>(
      'after the stream ends, LoadTasks subscribes afresh',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.emit([buildTask(id: 'old')]);
        await Future<void>.delayed(Duration.zero);
        await repository.controller.close();
        await Future<void>.delayed(Duration.zero);

        repository.controller = StreamController<TaskBoard>();
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.emit([buildTask(id: 'new')]);
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded([buildTask(id: 'old')]),
        // No second loading flash: the list already on screen stays until the
        // new subscription delivers.
        TasksLoaded([buildTask(id: 'new')]),
      ],
      verify: (_) => expect(repository.watchCalls, 2),
    );
  });

  group('mutations', () {
    Future<CrudActionResult> dispatch(
      TaskBloc bloc,
      TaskEvent Function(CrudActionCompleter completion) build,
    ) {
      final completion = CrudActionCompleter();
      bloc.add(build(completion));
      return completion.future;
    }

    test('each event calls the matching repository method and reports success',
        () async {
      final bloc = buildBloc();
      final task = buildTask(id: 't1');

      final results = [
        await dispatch(bloc, (c) => CreateTask(task, completion: c)),
        await dispatch(bloc, (c) => UpdateTask(task, completion: c)),
        await dispatch(bloc, (c) => DeleteTask('t1', completion: c)),
        await dispatch(
          bloc,
          (c) => ToggleSubtask(
            taskId: 't1',
            subtaskId: 'a',
            isDone: true,
            completion: c,
          ),
        ),
        await dispatch(
          bloc,
          (c) => SetTaskComplete(taskId: 't1', isComplete: false, completion: c),
        ),
        await dispatch(
          bloc,
          (c) =>
              SaveAssigneeUpdate(taskId: 't1', text: 'בטיפול', completion: c),
        ),
        await dispatch(
          bloc,
          (c) => CreateStage(buildStage(id: 's1'), completion: c),
        ),
        await dispatch(
          bloc,
          (c) => UpdateStage(buildStage(id: 's1'), completion: c),
        ),
        await dispatch(bloc, (c) => DeleteStage('s1', completion: c)),
      ];

      expect(results.every((result) => result.isSuccess), isTrue);
      expect(repository.calls, [
        'insert:t1',
        'update:t1',
        'delete:t1',
        'subtask:t1:a:true',
        'complete:t1:false',
        'note:t1:בטיפול',
        'insertStage:s1',
        'updateStage:s1',
        'deleteStage:s1',
      ]);
      await bloc.close();
    });

    test('a mutation without a completer still reaches the repository',
        () async {
      final bloc = buildBloc();
      bloc.add(const DeleteTask('t1'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, ['delete:t1']);
      await bloc.close();
    });

    blocTest<TaskBloc, TaskState>(
      'a failed mutation reports the backend message and keeps the list on screen',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const LoadTasks());
        await Future<void>.delayed(Duration.zero);
        repository.emit([buildTask(id: 't1')]);
        await Future<void>.delayed(Duration.zero);

        repository.failWith = DatabaseException(
          'Failed backend mutation task.setSubtaskDone: תת-המשימה לא נמצאה',
        );
        final result = await dispatch(
          bloc,
          (c) => ToggleSubtask(
            taskId: 't1',
            subtaskId: 'gone',
            isDone: true,
            completion: c,
          ),
        );

        expect(result.isFailure, isTrue);
        expect(result.message, 'תת-המשימה לא נמצאה');
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded([buildTask(id: 't1')]),
      ],
    );
  });

  test('a refused stage change reports the backend message', () async {
    final bloc = buildBloc();
    repository.failWith = DatabaseException(
      'Failed backend mutation stage.insert: התאריך אינו מתאריכי האירוע',
    );
    final completion = CrudActionCompleter();
    bloc.add(CreateStage(buildStage(), completion: completion));
    final result = await completion.future;

    expect(result.isFailure, isTrue);
    expect(result.message, 'התאריך אינו מתאריכי האירוע');
    await bloc.close();
  });

  group('progress shows at once', () {
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    Future<void> load(TaskBloc bloc, List<TaskItem> tasks) async {
      bloc.add(const LoadTasks());
      await settle();
      repository.emit(tasks);
      await settle();
    }

    const stepA = Subtask(id: 'a', title: 'טופס');
    const stepB = Subtask(id: 'b', title: 'חתימה');
    const stepADone = Subtask(id: 'a', title: 'טופס', isDone: true);
    const stepBDone = Subtask(id: 'b', title: 'חתימה', isDone: true);

    final twoSteps = buildTask(id: 't1', subtasks: const [stepA, stepB]);
    final plain = buildTask(id: 't1');
    final later = DateTime(2026, 10, 11, 14, 6);

    blocTest<TaskBloc, TaskState>(
      'a ticked subtask is shown done before the backend answers, and the '
      'stream then takes over',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [twoSteps]);
        repository.gate = Completer<void>();
        bloc.add(const ToggleSubtask(
          taskId: 't1',
          subtaskId: 'a',
          isDone: true,
        ));
        await settle();
        expect(repository.calls, ['subtask:t1:a:true']);

        repository.gate!.complete();
        await settle();
        repository.emit([
          twoSteps.copyWith(
            subtasks: const [stepADone, stepB],
            updatedAt: later,
          ),
        ]);
      },
      expect: () => [
        const TasksLoading(),
        TasksLoaded([twoSteps]),
        TasksLoaded([
          twoSteps.copyWith(subtasks: const [stepADone, stepB]),
        ]),
        TasksLoaded([
          twoSteps.copyWith(
            subtasks: const [stepADone, stepB],
            updatedAt: later,
          ),
        ]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'ticking the last open subtask shows the task complete at once',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [
          twoSteps.copyWith(subtasks: const [stepADone, stepB]),
        ]);
        repository.gate = Completer<void>();
        bloc.add(const ToggleSubtask(
          taskId: 't1',
          subtaskId: 'b',
          isDone: true,
        ));
        await settle();
        repository.gate!.complete();
      },
      skip: 2,
      expect: () => [
        TasksLoaded([
          twoSteps.copyWith(
            subtasks: const [stepADone, stepBDone],
            isComplete: true,
            completedAt: tickedAt,
          ),
        ]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'unticking a subtask of a completed task reopens it at once',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [
          twoSteps.copyWith(
            subtasks: const [stepADone, stepBDone],
            isComplete: true,
            completedAt: DateTime(2026, 10, 10),
          ),
        ]);
        repository.gate = Completer<void>();
        bloc.add(const ToggleSubtask(
          taskId: 't1',
          subtaskId: 'a',
          isDone: false,
        ));
        await settle();
        repository.gate!.complete();
      },
      skip: 2,
      verify: (bloc) {
        final task = (bloc.state as TasksLoaded).tasks.single;
        expect(task.isComplete, isFalse);
        expect(task.subtasks, const [stepA, stepBDone]);
      },
    );

    blocTest<TaskBloc, TaskState>(
      'completing a task without subtasks shows at once',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [plain]);
        repository.gate = Completer<void>();
        bloc.add(const SetTaskComplete(taskId: 't1', isComplete: true));
        await settle();
        expect(repository.calls, ['complete:t1:true']);
        repository.gate!.complete();
      },
      skip: 2,
      expect: () => [
        TasksLoaded([
          plain.copyWith(isComplete: true, completedAt: tickedAt),
        ]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'reopening a completed task shows at once',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [plain.copyWith(isComplete: true)]);
        repository.gate = Completer<void>();
        bloc.add(const SetTaskComplete(taskId: 't1', isComplete: false));
        await settle();
        repository.gate!.complete();
      },
      skip: 2,
      verify: (bloc) {
        expect((bloc.state as TasksLoaded).tasks.single.isComplete, isFalse);
      },
    );

    blocTest<TaskBloc, TaskState>(
      'a tick the backend refuses is undone and reported',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [plain]);
        repository.gate = Completer<void>();
        repository.failWith = DatabaseException(
          'Failed backend mutation task.setComplete: אין הרשאה לעדכן את המשימה',
        );
        final completion = CrudActionCompleter();
        bloc.add(SetTaskComplete(
          taskId: 't1',
          isComplete: true,
          completion: completion,
        ));
        await settle();
        repository.gate!.complete();

        final result = await completion.future;
        expect(result.isFailure, isTrue);
        expect(result.message, 'אין הרשאה לעדכן את המשימה');
      },
      skip: 2,
      expect: () => [
        TasksLoaded([
          plain.copyWith(isComplete: true, completedAt: tickedAt),
        ]),
        TasksLoaded([plain]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'a stream update that arrives while the tick is in flight does not undo '
      'it',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [plain]);
        repository.gate = Completer<void>();
        bloc.add(const SetTaskComplete(taskId: 't1', isComplete: true));
        await settle();

        // Someone else adds a task; t1 is still unfinished on the server.
        repository.emit([plain, buildTask(id: 't2')]);
        await settle();
        repository.gate!.complete();
      },
      skip: 3,
      expect: () => [
        TasksLoaded([
          plain.copyWith(isComplete: true, completedAt: tickedAt),
          buildTask(id: 't2'),
        ]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'once the backend has answered, the stream is the truth again',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [plain]);
        bloc.add(const SetTaskComplete(taskId: 't1', isComplete: true));
        await settle();

        // The write landed, and someone else reopened the task right after.
        repository.emit([plain.copyWith(updatedAt: later)]);
      },
      skip: 3,
      expect: () => [
        TasksLoaded([plain.copyWith(updatedAt: later)]),
      ],
    );

    blocTest<TaskBloc, TaskState>(
      'a second tick sent before the first is answered is the one that shows',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [twoSteps]);
        final first = repository.gate = Completer<void>();
        bloc.add(const ToggleSubtask(
          taskId: 't1',
          subtaskId: 'a',
          isDone: true,
        ));
        await settle();
        final second = repository.gate = Completer<void>();
        bloc.add(const ToggleSubtask(
          taskId: 't1',
          subtaskId: 'a',
          isDone: false,
        ));
        await settle();

        // The first write lands and is answered while the second is still out.
        first.complete();
        await settle();
        repository.emit([
          twoSteps.copyWith(
            subtasks: const [stepADone, stepB],
            updatedAt: later,
          ),
        ]);
        await settle();
        expect(
          (bloc.state as TasksLoaded).tasks.single.subtasks,
          const [stepA, stepB],
          reason: 'the later untick must still be the one on screen',
        );
        second.complete();
      },
      verify: (_) => expect(
        repository.calls,
        ['subtask:t1:a:true', 'subtask:t1:a:false'],
      ),
    );

    blocTest<TaskBloc, TaskState>(
      'a tick on a task that is not on the board is still sent',
      build: buildBloc,
      act: (bloc) async {
        await load(bloc, [plain]);
        bloc.add(const SetTaskComplete(taskId: 'gone', isComplete: true));
        await settle();
      },
      skip: 2,
      expect: () => const <TaskState>[],
      verify: (_) => expect(repository.calls, ['complete:gone:true']),
    );
  });

  group('taskErrorMessage', () {
    test('digs the backend Hebrew message out of the wrapped exception', () {
      final error = DatabaseException(
        'Failed backend mutation task.update: אין לך הרשאה לנהל משימות',
      );
      expect(taskErrorMessage(error), 'אין לך הרשאה לנהל משימות');
    });

    test('falls back to a generic message for a technical error', () {
      expect(
        taskErrorMessage(Exception('SocketException: Connection reset')),
        'הפעולה נכשלה. נסו שוב.',
      );
    });

    test('falls back for a wrapped English backend message', () {
      final error = DatabaseException(
        'Failed backend mutation task.insert: Missing or invalid task',
      );
      expect(taskErrorMessage(error), 'הפעולה נכשלה. נסו שוב.');
    });
  });
}
