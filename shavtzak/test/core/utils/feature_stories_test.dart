import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/feature_stories.dart';

void main() {
  const video = FeatureStory(type: FeatureStoryType.video, file: 'stories/a.mp4');
  const managers = FeatureStory(
      type: FeatureStoryType.image, file: 'stories/m.png', audience: FeatureStoryAudience.managers);
  const permanent = FeatureStory(
      type: FeatureStoryType.image, file: 'stories/p.png', audience: FeatureStoryAudience.permanent);

  group('parseFeatureStories', () {
    test('reads type, file and audience; drops bad items', () {
      final stories = parseFeatureStories([
        {'type': 'video', 'file': ' stories/a.mp4 ', 'audience': 'all'},
        {'type': 'image', 'file': 'stories/m.png', 'audience': 'managers'},
        {'type': 'image', 'file': 'stories/p.png', 'audience': 'permanent'},
        {'type': 'gif', 'file': 'x.gif'},
        {'type': 'video'},
        {'type': 'video', 'file': '  '},
        'stories/a.mp4',
      ]);
      expect(stories, [video, managers, permanent]);
    });

    test('an unknown or missing audience is everyone', () {
      expect(parseFeatureStories([
        {'type': 'video', 'file': 'stories/a.mp4', 'audience': 'soldiers'},
        {'type': 'video', 'file': 'stories/a.mp4'},
      ]), [video, video]);
    });

    test('not a list = no stories', () {
      expect(parseFeatureStories(null), isEmpty);
      expect(parseFeatureStories('stories/a.mp4'), isEmpty);
      expect(parseFeatureStories(const <dynamic>[]), isEmpty);
    });
  });

  group('storiesFor', () {
    final all = [video, managers, permanent];

    test('a non-permanent member sees only the "everyone" stories', () {
      expect(storiesFor(all, isAdmin: false, isPermanent: false), [video]);
    });

    test('a permanent member sees everyone + permanent, in order', () {
      expect(storiesFor(all, isAdmin: false, isPermanent: true), [video, permanent]);
    });

    test('a manager sees every story', () {
      expect(storiesFor(all, isAdmin: true, isPermanent: false), all);
    });

    test('nothing for them = empty (no stories screen)', () {
      expect(storiesFor([managers], isAdmin: false, isPermanent: true), isEmpty);
    });
  });

  group('storiesFromQuery', () {
    test('files by extension, in order', () {
      expect(storiesFromQuery('stories/a.mp4, stories/b.PNG,stories/c.webm'), const [
        FeatureStory(type: FeatureStoryType.video, file: 'stories/a.mp4'),
        FeatureStory(type: FeatureStoryType.image, file: 'stories/b.PNG'),
        FeatureStory(type: FeatureStoryType.video, file: 'stories/c.webm'),
      ]);
    });

    test('missing or empty = null', () {
      expect(storiesFromQuery(null), isNull);
      expect(storiesFromQuery(''), isNull);
      expect(storiesFromQuery(' , '), isNull);
    });
  });

  group('featureStoryUri', () {
    test('relative to the site, ignoring the route and the query', () {
      final base = Uri.parse('https://x.github.io/Shavtzak/?stories=a#/user/assignments');
      expect(featureStoryUri('stories/a.mp4', base).toString(),
          'https://x.github.io/Shavtzak/stories/a.mp4');
    });

    test('an absolute address stays', () {
      expect(featureStoryUri('https://cdn.example/a.mp4', Uri.parse('https://x/')).toString(),
          'https://cdn.example/a.mp4');
    });
  });

  test('storiesUnseenFor: the running version, not opened here yet', () {
    // Never opened here (old refresh button, new browser) = due.
    expect(storiesUnseenFor(seen: null, cached: 'V5.6.0', remote: 'V5.6.0'), isTrue);
    expect(storiesUnseenFor(seen: 'V5.5.0', cached: 'V5.6.0', remote: 'V5.6.0'), isTrue);
    // Already opened for this version.
    expect(storiesUnseenFor(seen: 'V5.6.0', cached: 'V5.6.0', remote: 'V5.6.0'), isFalse);
    // Waiting for a refresh (runs an older version) = not yet.
    expect(storiesUnseenFor(seen: null, cached: 'V5.5.0', remote: 'V5.6.0'), isFalse);
    // No version on the server.
    expect(storiesUnseenFor(seen: null, cached: null, remote: null), isFalse);
    expect(storiesUnseenFor(seen: null, cached: '', remote: ''), isFalse);
  });
}
