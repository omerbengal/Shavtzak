import 'package:equatable/equatable.dart';

/// Feature stories (Omer, 20/11/2026): new features shown Instagram-style,
/// one story per feature, an image (a short feature) or a video (a flow, up
/// to 30 s). A standing list (26/11/2026), not tied to a version, in
/// `utilities/information` → `WhatsNewStories`:
/// `[{type: video|image, file: 'stories/x.mp4', audience: all|managers|permanent}]`.
/// Each story shows once per browser while it is in the list (a story added
/// later shows alone); one taken out of the list never shows. Missing or
/// empty = no stories screen. Pure rules; the screen is
/// `presentation/widgets/feature_stories/`.

enum FeatureStoryType { image, video }

/// Who sees a story. `all` = every member; `managers` = admins;
/// `permanent` = permanent members (blue shield). Admins see every story.
enum FeatureStoryAudience { all, managers, permanent }

/// How long an image story stays up (its bar fills over this time).
const Duration featureStoryImageDuration = Duration(seconds: 5);

/// A video that is not ready by then is skipped.
const Duration featureStoryLoadTimeout = Duration(seconds: 10);

class FeatureStory extends Equatable {
  final FeatureStoryType type;

  /// Relative to the site (`stories/tagging.mp4`) or an absolute https URL.
  final String file;
  final FeatureStoryAudience audience;

  const FeatureStory({
    required this.type,
    required this.file,
    this.audience = FeatureStoryAudience.all,
  });

  @override
  List<Object?> get props => [type, file, audience];
}

/// The stories in [raw] (the `WhatsNewStories` value). An item without a
/// known type or a file is dropped; an unknown audience reads as `all`.
List<FeatureStory> parseFeatureStories(dynamic raw) {
  if (raw is! List) return const [];
  final stories = <FeatureStory>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final type = switch (item['type']) {
      'video' => FeatureStoryType.video,
      'image' => FeatureStoryType.image,
      _ => null,
    };
    final file = item['file'];
    if (type == null || file is! String || file.trim().isEmpty) continue;
    final audience = switch (item['audience']) {
      'managers' => FeatureStoryAudience.managers,
      'permanent' => FeatureStoryAudience.permanent,
      _ => FeatureStoryAudience.all,
    };
    stories.add(FeatureStory(type: type, file: file.trim(), audience: audience));
  }
  return List.unmodifiable(stories);
}

/// The stories a member sees, in order. A non-permanent member sees only
/// the `all` ones; an admin sees every story.
List<FeatureStory> storiesFor(
  List<FeatureStory> all, {
  required bool isAdmin,
  required bool isPermanent,
}) {
  bool sees(FeatureStory story) => switch (story.audience) {
        FeatureStoryAudience.all => true,
        FeatureStoryAudience.managers => isAdmin,
        FeatureStoryAudience.permanent => isAdmin || isPermanent,
      };
  return [for (final story in all) if (sees(story)) story];
}

/// `?stories=a.mp4,b.png` in the address: open these stories now, seen or
/// not, without marking them (previews, checking a new story). `.mp4` / `.webm` = video,
/// anything else an image. Null when there is nothing to show.
List<FeatureStory>? storiesFromQuery(String? value) {
  if (value == null) return null;
  final stories = [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty)
        FeatureStory(
          type: RegExp(r'\.(mp4|webm)$', caseSensitive: false).hasMatch(part.trim())
              ? FeatureStoryType.video
              : FeatureStoryType.image,
          file: part.trim(),
        ),
  ];
  return stories.isEmpty ? null : stories;
}

/// The address of a story's [file] on the site the app runs from ([base] =
/// the page's address, `Uri.base` on the web; the `#/route` is ignored).
Uri featureStoryUri(String file, Uri base) {
  final parsed = Uri.tryParse(file);
  if (parsed != null && parsed.hasScheme) return parsed;
  return base.removeFragment().resolve(file);
}

/// Stories may open in this browser now: the version it runs ([cached]) is
/// the server's ([remote]), so a browser waiting for a refresh sees nothing.
bool storiesMayShow({String? cached, String? remote}) {
  final current = remote?.trim() ?? '';
  return current.isNotEmpty && cached?.trim() == current;
}

/// The stories of [stories] this browser has not opened yet ([seen] = their
/// files), in order (Omer, 26/11/2026: `WhatsNewStories` is a standing list,
/// each story shown once per browser while it is in the list).
List<FeatureStory> unseenStories(List<FeatureStory> stories, Set<String> seen) =>
    [for (final story in stories) if (!seen.contains(story.file)) story];

/// The stories each version showed while the mark was one version
/// (`stories_seen_version`, until V5.6.7): a browser that opened them keeps
/// them as seen.
const Map<String, List<String>> legacyStoriesByVersion = {
  'V5.6.7': ['stories/event-items.mp4'],
};

/// The files this browser opened: the saved list ([saved]) plus the stories
/// of the version the old mark names ([legacyVersion]; unknown = nothing).
Set<String> seenStoryFiles({List<String>? saved, String? legacyVersion}) => {
      ...?saved,
      ...?legacyStoriesByVersion[legacyVersion?.trim()],
    };
