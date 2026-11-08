import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';

import '../../support/task_fixtures.dart';

/// A repository whose stream the test drives; every save is accepted and
/// nothing comes back through the stream unless the test sends it.
class _SilentRepository extends Fake implements TaskRepository {
  final controller = StreamController<TaskBoard>();

  @override
  Stream<TaskBoard> watchBoard() => controller.stream;

  @override
  Future<void> updateStage(Stage stage) async {}

  @override
  Future<void> updateTask(TaskItem task) async {}

  @override
  Future<void> insertTask(TaskItem task) async {}
}

// The 2026-11-08 report: a stage's contacts edited on a phone, the save
// accepted, the screen kept the old contacts until a refresh because the live
// stream had stopped delivering.
void main() {
  late _SilentRepository repository;
  late List<String> staleReports;

  final oldContacts = [
    const StageContact(id: 'c1', name: 'שגיב', phone: '054-6219399', role: 'קרן הסיוע'),
  ];
  final newContacts = [
    const StageContact(id: 'c2', name: 'אליסף', phone: '054-4543733', role: 'קרן הסיוע'),
  ];
  final liveStage = buildStage(contacts: oldContacts);
  final savedStage = buildStage(contacts: newContacts);

  setUp(() {
    repository = _SilentRepository();
    staleReports = [];
  });

  TaskBloc buildBloc({bool withReconnect = true}) => TaskBloc(
        repository: repository,
        onStaleStream: withReconnect ? staleReports.add : null,
        staleAfter: const Duration(milliseconds: 40),
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> load(TaskBloc bloc, TaskBoard board) async {
    bloc.add(const LoadTasks());
    await settle();
    repository.controller.add(board);
    await settle();
  }

  Future<CrudActionResult> dispatch(
    TaskBloc bloc,
    TaskEvent Function(CrudActionCompleter completion) build,
  ) async {
    final completion = CrudActionCompleter();
    bloc.add(build(completion));
    final result = await completion.future;
    await settle();
    return result;
  }

  List<Stage> shownStages(TaskBloc bloc) => (bloc.state as TasksLoaded).stages;
  List<TaskItem> shownTasks(TaskBloc bloc) => (bloc.state as TasksLoaded).tasks;

  group('a saved stage', () {
    test('shows at once, while the stream has not brought it back', () async {
      final bloc = buildBloc();
      await load(bloc, TaskBoard(tasks: const [], stages: [liveStage]));

      final result = await dispatch(bloc, (c) => UpdateStage(savedStage, completion: c));

      expect(result.isSuccess, isTrue);
      expect(shownStages(bloc).single.contacts, newContacts);
      await bloc.close();
    });

    test('also re-dates the tasks under it', () async {
      final bloc = buildBloc();
      await load(
        bloc,
        TaskBoard(tasks: [buildTask(stage: liveStage)], stages: [liveStage]),
      );
      final moved = liveStage.copyWith(date: DateTime(2026, 10, 21));

      await dispatch(bloc, (c) => UpdateStage(moved, completion: c));

      expect(shownTasks(bloc).single.stage?.date, DateTime(2026, 10, 21));
      await bloc.close();
    });

    test('once the stream carries it, the stream is shown and nothing is '
        'reported', () async {
      final bloc = buildBloc();
      await load(bloc, TaskBoard(tasks: const [], stages: [liveStage]));
      await dispatch(bloc, (c) => UpdateStage(savedStage, completion: c));

      final fromStream = savedStage.copyWith(updatedAt: DateTime(2026, 11, 8));
      repository.controller.add(TaskBoard(tasks: const [], stages: [fromStream]));
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(shownStages(bloc).single, fromStream);
      expect(staleReports, isEmpty);
      await bloc.close();
    });

    test('a stream that stays silent is reported stuck once', () async {
      final bloc = buildBloc();
      await load(bloc, TaskBoard(tasks: const [], stages: [liveStage]));
      await dispatch(bloc, (c) => UpdateStage(savedStage, completion: c));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(staleReports, ['tasks:stageUpdate']);
      // Still shown while the reconnect has its chance.
      expect(shownStages(bloc).single.contacts, newContacts);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(staleReports, ['tasks:stageUpdate']);
      await bloc.close();
    });

    test('a stream that brings something else after the reconnect wins',
        () async {
      final bloc = buildBloc();
      await load(bloc, TaskBoard(tasks: const [], stages: [liveStage]));
      await dispatch(bloc, (c) => UpdateStage(savedStage, completion: c));

      // Someone else's edit, not ours.
      final other = buildStage(notes: 'עריכה של מישהו אחר');
      repository.controller.add(TaskBoard(tasks: const [], stages: [other]));
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(shownStages(bloc).single, other);
      await bloc.close();
    });

    test('without a reconnect hook, no timer is left running', () async {
      final bloc = buildBloc(withReconnect: false);
      await load(bloc, TaskBoard(tasks: const [], stages: [liveStage]));
      await dispatch(bloc, (c) => UpdateStage(savedStage, completion: c));

      expect(shownStages(bloc).single.contacts, newContacts);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(staleReports, isEmpty);
      await bloc.close();
    });
  });

  group('a saved task', () {
    test('shows its edit at once, keeping ticks and looking up assignees',
        () async {
      final bloc = buildBloc();
      final dana = buildMember(id: 'm1', name: 'דנה');
      final yossi = buildMember(id: 'm2', name: 'יוסי');
      final live = buildTask(
        title: 'ישן',
        assigneeIds: const ['m1'],
        assignees: [dana],
        subtasks: const [
          Subtask(id: 'a', title: 'א', isDone: true),
          Subtask(id: 'b', title: 'ב'),
        ],
      );
      await load(
        bloc,
        TaskBoard(tasks: [live], members: [dana, yossi]),
      );
      final saved = live.copyWith(
        title: 'חדש',
        assigneeIds: const ['m2'],
        // The form's copy may hold stale ticks; the live ones win.
        subtasks: const [
          Subtask(id: 'a', title: 'א'),
          Subtask(id: 'c', title: 'ג'),
        ],
      );

      await dispatch(bloc, (c) => UpdateTask(saved, completion: c));

      final shown = shownTasks(bloc).single;
      expect(shown.title, 'חדש');
      expect(shown.assignees, [yossi]);
      expect(shown.subtasks, const [
        Subtask(id: 'a', title: 'א', isDone: true),
        Subtask(id: 'c', title: 'ג'),
      ]);
      await bloc.close();
    });

    test('a created task that never arrives is reported stuck', () async {
      final bloc = buildBloc();
      await load(bloc, const TaskBoard(tasks: []));

      await dispatch(bloc, (c) => CreateTask(buildTask(id: 'new'), completion: c));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(staleReports, ['tasks:taskCreate']);
      await bloc.close();
    });
  });
}
