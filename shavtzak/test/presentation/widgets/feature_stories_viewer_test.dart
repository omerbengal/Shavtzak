import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/feature_stories.dart';
import 'package:shavtzak/presentation/widgets/feature_stories/feature_stories_viewer.dart';
import 'package:shavtzak/presentation/widgets/feature_stories/story_media.dart';

const _a = FeatureStory(type: FeatureStoryType.image, file: 'a.png');
const _b = FeatureStory(type: FeatureStoryType.video, file: 'b.mp4');
const _c = FeatureStory(type: FeatureStoryType.image, file: 'c.png');

/// Stand-in media: shows the file's name and reports ready at once (a video
/// lasts 8 s), or an error for a file named "bad".
StoryMediaBuilder fakeMedia({Set<String> failing = const {}, Set<String> silent = const {}}) =>
    (context, story, callbacks) => _FakeMedia(
          story: story,
          callbacks: callbacks,
          fail: failing.contains(story.file),
          silent: silent.contains(story.file),
        );

class _FakeMedia extends StatefulWidget {
  final FeatureStory story;
  final StoryMediaCallbacks callbacks;
  final bool fail;
  final bool silent;

  const _FakeMedia({
    required this.story,
    required this.callbacks,
    required this.fail,
    required this.silent,
  });

  @override
  State<_FakeMedia> createState() => _FakeMediaState();
}

class _FakeMediaState extends State<_FakeMedia> {
  @override
  void initState() {
    super.initState();
    if (widget.silent) return;
    scheduleMicrotask(() => widget.fail
        ? widget.callbacks.onError('MEDIA_ERR_SRC_NOT_SUPPORTED')
        : widget.callbacks.onReady(widget.story.type == FeatureStoryType.video
            ? const Duration(seconds: 8)
            : featureStoryImageDuration));
  }

  @override
  Widget build(BuildContext context) => Text('media:${widget.story.file}');
}

Future<List<int>> pumpViewer(
  WidgetTester tester,
  List<FeatureStory> stories, {
  StoryMediaBuilder? media,
  bool showErrors = false,
}) async {
  final closed = <int>[];
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: FeatureStoriesViewer(
      key: UniqueKey(),
      stories: stories,
      onClose: () => closed.add(1),
      mediaBuilder: media ?? fakeMedia(),
      showErrors: showErrors,
    ),
  ));
  await tester.pump();
  return closed;
}

double bar(WidgetTester tester, int i) =>
    tester.widget<LinearProgressIndicator>(find.byKey(Key('story-bar-$i'))).value!;

void main() {
  testWidgets('a bar per story, the first on the right, filling as it plays', (tester) async {
    await pumpViewer(tester, [_a, _b, _c]);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(tester.getCenter(find.byKey(const Key('story-bar-0'))).dx,
        greaterThan(tester.getCenter(find.byKey(const Key('story-bar-1'))).dx));
    expect(find.text('media:a.png'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(bar(tester, 0), closeTo(0.5, 0.05));
    expect(bar(tester, 1), 0);
  });

  testWidgets('an image moves on after 5 s, a video after its length', (tester) async {
    await pumpViewer(tester, [_a, _b, _c]);
    await tester.pump(const Duration(milliseconds: 5100));
    await tester.pump();
    expect(find.text('media:b.mp4'), findsOneWidget);
    expect(bar(tester, 0), 1);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('media:b.mp4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('media:c.png'), findsOneWidget);
  });

  testWidgets('tap the left half = next, the right half = previous', (tester) async {
    await pumpViewer(tester, [_a, _b, _c]);
    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    expect(find.text('media:b.mp4'), findsOneWidget);
    await tester.tapAt(const Offset(330, 400));
    await tester.pump();
    expect(find.text('media:a.png'), findsOneWidget);
    // Previous on the first story restarts it.
    await tester.tapAt(const Offset(330, 400));
    await tester.pump();
    expect(find.text('media:a.png'), findsOneWidget);
  });

  testWidgets('after the last story: "צפייה מחדש" from the first, and "סגירה"', (tester) async {
    final closed = await pumpViewer(tester, [_a, _c]);
    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    expect(find.text('צפייה מחדש'), findsOneWidget);
    expect(find.text('סגירה'), findsOneWidget);
    // The last story stays under the end screen, every bar full.
    expect(find.text('media:c.png'), findsOneWidget);
    expect(bar(tester, 0), 1);
    expect(bar(tester, 1), 1);

    await tester.tap(find.byKey(const Key('stories-replay')));
    await tester.pump();
    expect(find.text('צפייה מחדש'), findsNothing);
    expect(find.text('media:a.png'), findsOneWidget);
    expect(bar(tester, 1), 0);

    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stories-end-close')));
    expect(closed, [1]);
  });

  testWidgets('✕ closes at any time', (tester) async {
    final closed = await pumpViewer(tester, [_a, _b]);
    await tester.tap(find.byKey(const Key('stories-close')));
    expect(closed, [1]);
  });

  testWidgets('a story that fails is skipped; all failing = the end screen', (tester) async {
    await pumpViewer(tester, [_a, _b, _c], media: fakeMedia(failing: {'b.mp4'}));
    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    await tester.pump();
    expect(find.text('media:c.png'), findsOneWidget);

    await pumpViewer(tester, [_b], media: fakeMedia(failing: {'b.mp4'}));
    await tester.pump();
    expect(find.text('צפייה מחדש'), findsOneWidget);
    // Never a silent end (Omer, msg 5402): it says a video did not load.
    expect(find.byKey(const Key('stories-failed')), findsOneWidget);
    expect(find.text('סרטון אחד לא נטען'), findsOneWidget);
    expect(find.textContaining('MEDIA_ERR'), findsNothing);
  });

  testWidgets('a preview link also shows why it was skipped', (tester) async {
    await pumpViewer(tester, [_b], media: fakeMedia(failing: {'b.mp4'}), showErrors: true);
    await tester.pump();
    expect(find.text('b.mp4: MEDIA_ERR_SRC_NOT_SUPPORTED'), findsOneWidget);
  });

  testWidgets('a popup card in the story shape over the dimmed app, not the whole screen',
      (tester) async {
    await pumpViewer(tester, [_a]);
    final card = tester.getSize(find.byKey(const Key('stories-card')));
    expect(card.width, lessThan(390 * 0.9));
    expect(card.height, lessThan(844 * 0.8));
    expect(card.width / card.height, closeTo(9 / 16, 0.01));
    // The bars and ✕ are inside it.
    final box = tester.getRect(find.byKey(const Key('stories-card')));
    expect(box.contains(tester.getCenter(find.byKey(const Key('story-bar-0')))), isTrue);
    expect(box.contains(tester.getCenter(find.byKey(const Key('stories-close')))), isTrue);
  });

  test('cardSize: 9:16, at most 86% wide, 78% high, 380 px', () {
    expect(FeatureStoriesViewer.cardSize(const Size(390, 844)).width, closeTo(335.4, 0.1));
    final tall = FeatureStoriesViewer.cardSize(const Size(390, 600));
    expect(tall.height, closeTo(468, 0.1));
    expect(FeatureStoriesViewer.cardSize(const Size(1400, 2600)).width, 380);
  });

  testWidgets('a story that never loads is skipped after 10 s', (tester) async {
    await pumpViewer(tester, [_b, _c], media: fakeMedia(silent: {'b.mp4'}));
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('media:b.mp4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('media:c.png'), findsOneWidget);
  });

  testWidgets('a long press holds the story', (tester) async {
    await pumpViewer(tester, [_a, _c]);
    await tester.pump(const Duration(seconds: 1));
    final gesture = await tester.startGesture(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 600));
    final held = bar(tester, 0);
    await tester.pump(const Duration(seconds: 6));
    expect(bar(tester, 0), held);
    expect(find.text('media:a.png'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(bar(tester, 0), held);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(bar(tester, 0), 1);
    expect(find.text('media:c.png'), findsOneWidget);
  });
}
