import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
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

  @override
  Stream<TaskBoard> watchBoard() {
    watchCalls++;
    return controller.stream;
  }

  void emit(List<TaskItem> tasks) => controller.add(TaskBoard(tasks: tasks));

  Future<void> _record(String call) async {
    calls.add(call);
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

  TaskBloc buildBloc() => TaskBloc(repository: repository);

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
      ];

      expect(results.every((result) => result.isSuccess), isTrue);
      expect(repository.calls, [
        'insert:t1',
        'update:t1',
        'delete:t1',
        'subtask:t1:a:true',
        'complete:t1:false',
        'note:t1:בטיפול',
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
