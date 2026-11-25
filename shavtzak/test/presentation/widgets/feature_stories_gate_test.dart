import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/feature_stories.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/widgets/feature_stories/feature_stories_gate.dart';

import '../../support/task_fixtures.dart';
import 'feature_stories_viewer_test.dart' show fakeMedia;

class _Source extends ChangeNotifier implements FeatureStoriesSource {
  @override
  bool ready;
  @override
  List<FeatureStory> stories;
  @override
  bool mayOpen;
  Set<String> seen;
  int takes = 0;
  int marks = 0;
  final List<String> marked = [];

  _Source({
    this.ready = true,
    this.stories = const [],
    Set<String>? seen,
    this.mayOpen = true,
  }) : seen = {...?seen};

  @override
  Future<Set<String>?> seenFiles() async {
    takes++;
    return {...seen};
  }

  @override
  Future<void> markSeen(Iterable<String> files) async {
    marks++;
    marked.addAll(files);
    seen.addAll(files);
  }

  void arrive() {
    ready = true;
    notifyListeners();
  }
}

const _all = FeatureStory(type: FeatureStoryType.image, file: 'all.png');
const _managers = FeatureStory(
    type: FeatureStoryType.image, file: 'm.png', audience: FeatureStoryAudience.managers);

void main() {
  late StreamController<Object?> users;
  TeamMember? user;

  setUp(() {
    users = StreamController<Object?>.broadcast();
    user = buildMember(id: 'm1', name: 'דנה');
  });
  tearDown(() => users.close());

  Future<void> pumpGate(WidgetTester tester, _Source source, {String? query}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FeatureStoriesGate(
        currentUser: () => user,
        userChanges: users.stream,
        source: source,
        queryStories: query,
        mediaBuilder: fakeMedia(),
        child: child!,
      ),
      home: const Scaffold(body: Text('home')),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('not seen yet: the member\'s stories open over the app, once, and are marked',
      (tester) async {
    final source = _Source(stories: [_managers, _all]);
    await pumpGate(tester, source);
    expect(find.text('media:all.png'), findsOneWidget);
    // A regular member: the managers' story is not theirs.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
    // Marked as the screen opened (a closed tab never loops), only the
    // story shown.
    expect(source.marks, 1);
    expect(source.marked, ['all.png']);
    await tester.tap(find.byKey(const Key('stories-close')));
    await tester.pump();
    source.notifyListeners();
    users.add(2);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('media:'), findsNothing);
    expect(source.takes, 1);
    expect(source.marks, 1);
  });

  testWidgets('already seen = nothing, and the mark is read once', (tester) async {
    final source = _Source(stories: [_all], seen: {'all.png'});
    await pumpGate(tester, source);
    expect(find.textContaining('media:'), findsNothing);
    source.notifyListeners();
    await tester.pump();
    expect(source.takes, 1);
    expect(source.marks, 0);
  });

  testWidgets('a story added to the list later shows alone', (tester) async {
    user = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
    final source = _Source(stories: [_all, _managers], seen: {'all.png'});
    await pumpGate(tester, source);
    expect(find.text('media:m.png'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(source.marked, ['m.png']);
  });

  testWidgets('waiting for a refresh = nothing, the mark is not read', (tester) async {
    final source = _Source(stories: [_all], mayOpen: false);
    await pumpGate(tester, source);
    expect(find.textContaining('media:'), findsNothing);
    expect(source.takes, 0);
    expect(source.marks, 0);
  });

  testWidgets('no story for this member = no screen, no mark, idle', (tester) async {
    final source = _Source(stories: [_managers]);
    await pumpGate(tester, source);
    expect(find.textContaining('media:'), findsNothing);
    expect(source.marks, 0);
    var idle = false;
    unawaited(FeatureStoriesGate.whenIdle().then((_) => idle = true));
    await tester.pump();
    expect(idle, isTrue);
  });

  testWidgets('waits for the sign-in and for the version doc', (tester) async {
    user = null;
    final source = _Source(stories: [_all], ready: false);
    await pumpGate(tester, source);
    expect(source.takes, 0);
    user = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
    users.add(1);
    await tester.pump();
    expect(source.takes, 0);
    source.arrive();
    await tester.pump();
    await tester.pump();
    expect(source.takes, 1);
    expect(find.text('media:all.png'), findsOneWidget);
  });

  testWidgets('?stories= opens them without a version change, and never marks', (tester) async {
    final source = _Source(stories: [_all], ready: false);
    await pumpGate(tester, source, query: 'stories/a.mp4,stories/b.png');
    expect(find.text('media:stories/a.mp4'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    source.arrive();
    await tester.pump();
    expect(source.takes, 0);
    expect(source.marks, 0);
  });

  testWidgets('other start popups wait until the stories close', (tester) async {
    await pumpGate(tester, _Source(stories: [_all]));
    var idle = false;
    unawaited(FeatureStoriesGate.whenIdle().then((_) => idle = true));
    await tester.pump();
    expect(idle, isFalse);
    await tester.tap(find.byKey(const Key('stories-close')));
    await tester.pump();
    expect(find.textContaining('media:'), findsNothing);
    expect(idle, isTrue);
  });

  testWidgets('nothing to show = idle at once', (tester) async {
    await pumpGate(tester, _Source(stories: [_all], seen: {'all.png'}));
    var idle = false;
    unawaited(FeatureStoriesGate.whenIdle().then((_) => idle = true));
    await tester.pump();
    expect(idle, isTrue);
  });
}
