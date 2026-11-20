// Shared by the story capture scripts (tool/story_capture/*_capture_test.dart):
// the app's real fonts, a phone-sized screen at 3x, and a PNG per step.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/theme/app_theme.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/team_task/team_task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_place.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_screen.dart';

import '../../test/support/fake_task_repository.dart' show MockUserSelectionBloc;
import '../../test/support/fake_team_task_repository.dart';
import '../../test/support/team_tasks_harness.dart';

/// The phone the stories show: 390 x 844 points, captured at 3x
/// (1170 x 2532 px), so a story at 1080 wide stays sharp.
const Size storyPhoneSize = Size(390, 844);
const double storyPixelRatio = 3;

/// Rubik (the app's font) and the Material icons, so the PNGs look like the
/// app instead of the test font's boxes.
Future<void> loadStoryFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  const rubik = [
    'assets/fonts/Rubik-Regular.ttf',
    'assets/fonts/Rubik-Medium.ttf',
    'assets/fonts/Rubik-Bold.ttf',
  ];
  await load('Rubik', rubik);
  // A style that names no family gets the test font (boxes); the browser
  // shows a Hebrew sans there.
  await load('Roboto', rubik);
  await load('FlutterTest', rubik);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf']);
}

/// The screen as a phone at 3x.
Future<void> phone(WidgetTester tester) async {
  tester.view.devicePixelRatio = storyPixelRatio;
  tester.view.physicalSize = storyPhoneSize * storyPixelRatio;
  await tester.pumpAndSettle();
}

/// Writes `tool/story_capture/out/<name>.png`.
Future<void> capture(WidgetTester tester, String name) async {
  await expectLater(find.byType(WidgetsApp), matchesGoldenFile('out/$name.png'));
}

/// As `pumpTeamTasks` (test/support/team_tasks_harness.dart), but inside the
/// app's real theme and without the debug banner: what the member sees.
Future<TeamTasksHarness> pumpTeamTasksAsApp(
  WidgetTester tester, {
  required TeamMember user,
  required TeamTaskBoard board,
  TeamTasksPlace place = TeamTasksPlace.standalone,
}) async {
  await phone(tester);
  addTearDown(tester.view.reset);
  final repository = FakeTeamTaskRepository();
  final bloc = TeamTaskBloc(repository: repository, clock: () => DateTime(2026, 11, 15, 8, 5));
  final userBloc = MockUserSelectionBloc();
  addTearDown(() {
    unawaited(bloc.close());
    unawaited(repository.controller.close());
  });
  whenListen(userBloc, const Stream<UserSelectionState>.empty(),
      initialState: UserAuthenticated(user));
  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider<TeamTaskBloc>.value(value: bloc),
      BlocProvider<UserSelectionBloc>.value(value: userBloc),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: TeamTasksScreen(place: place),
    ),
  ));
  await tester.pump();
  final harness = TeamTasksHarness(repository, bloc);
  await harness.deliver(tester, board);
  await tester.pumpAndSettle();
  return harness;
}

/// Where things are on the captured screens, in points (390 x 844), for the
/// story to point a finger at: `out/<story>/points.json`.
final Map<String, Map<String, double>> _points = {};

void mark(WidgetTester tester, String name, Finder finder) {
  final rect = tester.getRect(finder);
  _points[name] = {
    'x': rect.center.dx, 'y': rect.center.dy,
    'left': rect.left, 'top': rect.top, 'width': rect.width, 'height': rect.height,
  };
}

void writePoints(String story) {
  final file = File('tool/story_capture/out/$story/points.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_points));
}
