# Feature Stories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After the in-app refresh, show the version's feature stories (images / videos) Instagram-style, chosen per version and per audience; plus a Remotion project + skill that produce them, with tagging as the first story.

**Architecture:** Pure rules (`core/utils/feature_stories.dart`) parse `WhatsNewStories`, filter by audience and decide whether to show. `AppVersionService` exposes the parsed list and writes the pending marker in `refreshApp()`. `FeatureStoriesGate` (in `MaterialApp.router`'s builder) opens `FeatureStoriesViewer` over the app. Story media: `video_player` / `Image.network`. Production: Remotion in `feature_stories/`, renders into `shavtzak/web/stories/`.

**Tech Stack:** Flutter 3.50 web, video_player, shared_preferences, Remotion 4 (React/TS).

**Spec:** `docs/superpowers/specs/2026-11-20-feature-stories-design.md`

## Global Constraints

- DB field `WhatsNewStories` in `utilities/information`; item `{type: video|image, file, audience: all|managers|permanent}`.
- Image 5 s; video max 30 s (the skill enforces length; the app plays what it gets).
- No sound (videos muted), no text in media.
- RTL: first bar on the right; tap left half = next, right half = previous.
- End state buttons exactly "צפייה מחדש" and "סגירה".
- `stories/` excluded from the SW precache manifest.

## Review Focus

- Marker set but the doc's version moved on again (another bump) -> no stories, marker cleared.
- Every story fails to load -> straight to the end state, never a black screen stuck.
- `?stories=` with an empty value -> nothing opens.
- Signed-out user after refresh (whoami) -> marker kept until a user is signed in.
- Push prompt never stacks on top of the stories screen.

---

### Task 1: Rules

**Files:** Create `shavtzak/lib/core/utils/feature_stories.dart`; Test `shavtzak/test/core/utils/feature_stories_test.dart`

**Produces:**
- `enum FeatureStoryType { image, video }`, `enum FeatureStoryAudience { all, managers, permanent }`
- `class FeatureStory extends Equatable { type, file, audience }`, `const Duration featureStoryImageDuration = Duration(seconds: 5)`
- `List<FeatureStory> parseFeatureStories(dynamic raw)`
- `List<FeatureStory> storiesFor(List<FeatureStory> all, {required bool isAdmin, required bool isPermanent})`
- `List<FeatureStory>? storiesFromQuery(String? value)` (`.mp4`/`.webm` = video)
- `Uri featureStoryUri(String file, Uri base)`

- [ ] Tests: parse drops bad items, unknown audience = all, non-list = []; storiesFor (non-permanent sees only all; permanent sees all+permanent; admin sees everything); storiesFromQuery ('' -> null, 'a.mp4,b.png' -> video,image); featureStoryUri resolves against `https://x/Shavtzak/#/user` to `https://x/Shavtzak/stories/a.mp4`, keeps absolute https.
- [ ] Implement, pass, commit.

### Task 2: Version service marker + list

**Files:** Modify `shavtzak/lib/core/services/app_version_service.dart`; Test `shavtzak/test/core/services/feature_stories_pending_test.dart`

- `List<FeatureStory> get stories`; parsed from `WhatsNewStories` in `_handleSnapshot`.
- `refreshApp()` writes prefs `stories_pending_version` = remote version before reload.
- `Future<bool> takePendingStories()` : true when the marker equals the current cached version; clears the marker either way. Pure decision helper `bool pendingStoriesDue(String? marker, String? current)` in the rules file, tested.
- [ ] Test helper, implement, commit.

### Task 3: Viewer

**Files:** Create `shavtzak/lib/presentation/widgets/feature_stories/feature_stories_viewer.dart`, `story_media.dart`; Test `shavtzak/test/presentation/widgets/feature_stories_viewer_test.dart`

- `FeatureStoriesViewer({required List<FeatureStory> stories, required VoidCallback onClose, StoryMediaBuilder? mediaBuilder})` - the builder seam lets tests replace video/image loading.
- Tests (images via a fake media builder): bars count = stories; after 5 s advances; tap left = next, right = previous; after the last -> "צפייה מחדש" + "סגירה"; replay returns to the first; X calls onClose; a media error skips.
- [ ] Implement, pass, commit.

### Task 4: Gate + wiring

**Files:** Create `shavtzak/lib/presentation/widgets/feature_stories/feature_stories_gate.dart`; Modify `shavtzak/lib/main.dart` (builder), `shavtzak/lib/presentation/widgets/push_prompt_dialog.dart` (await `FeatureStoriesGate.whenIdle`), `shavtzak/tool/generate_service_worker.mjs` (EXCLUDED `^stories\/`), `shavtzak/pubspec.yaml` (video_player).
- Gate: once signed in + version doc read, `?stories=` wins, else `takePendingStories()` + `storiesFor` -> show viewer in an overlay Stack. `static Future<void> whenIdle` completes when nothing is showing.
- [ ] Widget test: gate with injected decision shows the viewer and push waits; commit.

### Task 5: Remotion project + tagging story + skill

**Files:** Create `feature_stories/` (package.json, tsconfig, src/index.ts, src/Root.tsx, src/theme.ts, src/components/*, src/stories/Tagging.tsx), `shavtzak/web/stories/tagging.mp4`, `.claude/skills/feature-story/SKILL.md`; Modify `.gitignore` (`.claude/*` + `!.claude/skills/`, `feature_stories/node_modules`, `feature_stories/out`).
- [ ] npm install (mem_guard), build composition, render mp4 (mem_guard), check length <= 30 s, size, look at frames; commit.

### Task 6: Checks, docs, preview

- [ ] CLAUDE.md: a short "Feature stories" paragraph.
- [ ] analyze / test / build web (each after mem_guard), push branch, preview, open `?stories=stories/tagging.mp4`.
