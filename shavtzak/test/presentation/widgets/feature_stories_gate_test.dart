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
  bool pending;
  int takes = 0;

  _Source({this.ready = true, this.stories = const [], this.pending = true});

  @override
  Future<bool> takePending() async {
    takes++;
    final was = pending;
    pending = false;
    return was;
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

  tearDown(() => FeatureStoriesGate.launchQuery = null);

  Future<void> pumpGate(WidgetTester tester, _Source source,
      {String? query, bool fromLaunch = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => FeatureStoriesGate(
        currentUser: () => user,
        userChanges: users.stream,
        source: source,
        queryStories: fromLaunch ? FeatureStoriesGate.launchQuery : query,
        mediaBuilder: fakeMedia(),
        child: child!,
      ),
      home: const Scaffold(body: Text('home')),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('after the refresh: the member\'s stories open over the app', (tester) async {
    final source = _Source(stories: [_managers, _all]);
    await pumpGate(tester, source);
    expect(find.text('media:all.png'), findsOneWidget);
    // A regular member: the managers' story is not theirs.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('no marker (new device, normal open) = nothing, and the marker is read once',
      (tester) async {
    final source = _Source(stories: [_all], pending: false);
    await pumpGate(tester, source);
    expect(find.textContaining('media:'), findsNothing);
    source.notifyListeners();
    await tester.pump();
    expect(source.takes, 1);
  });

  testWidgets('no story for this member = no screen', (tester) async {
    await pumpGate(tester, _Source(stories: [_managers]));
    expect(find.textContaining('media:'), findsNothing);
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

  testWidgets('?stories= opens them without a version change', (tester) async {
    final source = _Source(pending: false, ready: false);
    await pumpGate(tester, source, query: 'stories/a.mp4,stories/b.png');
    expect(find.text('media:stories/a.mp4'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(source.takes, 0);
  });

  testWidgets('?stories= read at launch still opens after the sign-in screen dropped it',
      (tester) async {
    // Omer, msg 5395: the link opened, he signed in, nothing showed. The
    // first redirect to #/whoami drops "?stories=" from the address, so it
    // must be taken at launch (main.dart), not when the member signs in.
    FeatureStoriesGate.captureLaunchQuery(
        Uri.parse('https://x.web.app/?stories=stories/a.mp4'));
    user = null;
    await pumpGate(tester, _Source(pending: false, ready: false), fromLaunch: true);
    expect(find.textContaining('media:'), findsNothing);
    user = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
    users.add(1);
    await tester.pump();
    await tester.pump();
    expect(find.text('media:stories/a.mp4'), findsOneWidget);
  });

  test('captureLaunchQuery: no "stories" in the address = null', () {
    FeatureStoriesGate.captureLaunchQuery(Uri.parse('https://x.web.app/#/whoami'));
    expect(FeatureStoriesGate.launchQuery, isNull);
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
    await pumpGate(tester, _Source(pending: false));
    var idle = false;
    unawaited(FeatureStoriesGate.whenIdle().then((_) => idle = true));
    await tester.pump();
    expect(idle, isTrue);
  });
}
