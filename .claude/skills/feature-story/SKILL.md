---
name: feature-story
description: Use when a Shavtzak release should show users a new feature after the in-app refresh - making the feature's "story" (a motion-graphics video up to 30 s, or a single image), from the app's real screens, and registering it for a version. Triggers - "סרטון לפיצ'ר", "סטורי לגרסה", "motion graphics for the feature", the post-merge question "סרטון לגרסה הזו?".
---

# Feature story

After the in-app refresh ("רענון האפליקציה"), the app plays the version's stories, Instagram-style
(`shavtzak/lib/presentation/widgets/feature_stories/`, design:
`docs/superpowers/specs/2026-11-20-feature-stories-design.md`). This skill makes one story for one
feature and registers it.

## Omer's rules (20/11/2026)

- Motion graphics in the app's own look: the real screens, the app's colours (`feature_stories/src/theme.ts`)
  and font (Rubik). Never invented UI.
- **No text and no sound.** The screens' own labels are fine; no captions, titles or narration.
- Made-up names only (the repo is public). Never real team members.
- A short feature that fits one screen = an **image** (shown 5 s). A flow with steps = a **video**,
  at most 30 s (aim for 10-15).
- One story per feature. Each story has an audience: `all` (default), `managers`, `permanent`
  (blue-shield members; managers see everything).

## Steps

1. **Pick image or video and the scenes.** Read the feature's diff and its tests: which screen
   shows it, which taps tell the story, whose phone (one member, or two: who acts and who receives).
   Write the storyboard as a few lines (scene, frames, what moves) and show it to Omer before
   building when the feature has more than one reasonable way to show it.

2. **Capture the real screens.** Add `shavtzak/tool/story_capture/<story>_capture_test.dart`, modelled
   on `tagging_capture_test.dart`: pump the real screen with fixtures (`pumpTeamTasksAsApp` or a new
   helper in `capture_support.dart` with the app theme), `capture(tester, '<story>/NN_name')` after each
   step, `mark(...)` every tap target, `writePoints('<story>')` at the end. Run from `shavtzak/`
   (one heavy job at a time; on Kai's PC `python D:/Kai/scripts/mem_guard.py --wait 300` first):
   `FLUTTER_ROOT=<flutter sdk> flutter test tool/story_capture/<story>_capture_test.dart --update-goldens`.
   Look at every PNG. Known gap: text whose style names no font family (e.g. the "בליץ" button)
   comes out as boxes; redraw it in the composition (`BlitzLabel` in `Tagging.tsx`).
   Copy `tool/story_capture/out/<story>/` to `feature_stories/public/<story>/`.

3. **Build the composition** in `feature_stories/src/stories/<Story>.tsx`, registered in
   `src/Root.tsx` with `id` = the file name. Reuse `Phone` (screen points = capture points),
   `Screens` (one PNG fades into the next), `Finger` (glide + tap ripple), `Background`.
   1080 x 1920, 30 fps. Frame the part of the screen the story is about large (the phone may run off
   the canvas). An image story = a `<Still>` of the same size.
   `cd feature_stories && npm ci` once, then `npm run studio` to scrub it.

4. **Render** (heavy): `npm run render -- <id>` (video) or `npm run render -- <id> --image`.
   It refuses more than 30 s or another size and writes `shavtzak/web/stories/<id>.mp4|png`
   (H.264, no audio; Remotion brings its own ffmpeg). Pull a few frames out of the result and look
   at them (`node_modules/@remotion/compositor-*/ffmpeg -ss <t> -i ... -frames:v 1 x.png`).

5. **Check it in the app** on the branch's preview (`bash scripts/preview.sh`), opening
   `<preview url>/?stories=stories/<id>.mp4` (comma-separated for several; before the `#`). Send
   Omer that link and the mp4 itself in Telegram.

6. **Only this version's files in `shavtzak/web/stories/`** (Omer, msg 5390): the branch that adds
   this version's stories also deletes every older story file there (`git rm`), so the site never
   keeps old ones. A release with no stories: the release removes whatever is left in
   `web/stories/` (a small commit before the version bump). The Remotion sources stay.

7. **Register it for the version** - only after the merge, and only with Omer's OK (production
   data): in `utilities/information` set `WhatsNewStories` to this version's list
   `{type: 'video'|'image', file: 'stories/<id>.mp4', audience: 'all'|'managers'|'permanent'}`,
   in the order they should play, together with the version bump. Read it back after writing.
   A version with no stories: `WhatsNewStories: []`, never the previous version's (its files are gone).

## Files

- `feature_stories/` - the Remotion project (sources of every story, `render.mjs`).
- `shavtzak/tool/story_capture/` - the capture scripts (not part of `flutter test`).
- `shavtzak/web/stories/` - the current version's rendered stories only, served with the site,
  kept out of the service worker's precache (fetched only when shown).
- Licence: Remotion is free for individuals, companies of up to 3 employees and non-profits
  (checked 20/11/2026, https://www.remotion.dev/license).
