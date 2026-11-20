# Feature stories after a version update - design

Approved by Omer 20/11/2026 (Telegram, Shavtzak topic, msgs 5348-5386).

## Intent

When a release brings a feature worth showing, the user who presses "רענון האפליקציה" lands on a
short, Instagram-style stories screen that SHOWS the new feature: motion graphics drawn in the
app's own look, no text, no sound. Per version we decide whether there are stories at all. A
reusable skill makes producing a story for every future feature routine.

## Decisions (Omer's)

- Style: motion graphics drawn in the app's look (not a screen recording). No sound, no text.
- A story is an IMAGE (a short feature, one screen; shown 5 s) or a VIDEO (a flow; up to 30 s).
- Several features in one version = several stories, exactly like Instagram / WhatsApp stories:
  segmented progress bars at the top (one per story, the current one fills while it plays), auto
  advance, tap a side = next / previous, X closes.
- It opens by itself right after the refresh, and the first story plays at once. After the last
  one: an end state with two buttons, "סגירה" and "צפייה מחדש" (from the first story). No "what's
  new" button anywhere; nothing to watch later.
- Audience per story: everyone / managers / permanent team members (blue shield). Default
  everyone. A user with no matching story gets no stories screen; a non-permanent member sees only
  the "everyone" stories.
- Per-version switch in the DB; the post-merge release flow asks Omer whether this version gets
  stories.
- The producing skill lives in the repo (`.claude/skills/feature-story/`), with each story's
  sources. Tool: Remotion (free licence: individual / up to 3 employees / non-profit; it bundles
  its own ffmpeg).

## Data

`utilities/information` gets an optional field next to `version` and `WhatsNew`:

```
WhatsNewStories: [
  {type: 'video' | 'image', file: 'stories/tagging.mp4', audience: 'all' | 'managers' | 'permanent'}
]
```

Missing / empty / unreadable = no stories. An item with an unknown type or no file is dropped; an
unknown audience reads as `all`. `file` is relative to the site (or an absolute https URL).

## When it shows

Changed 20/11/2026 (Omer, msg 5408 option A, clarified 5412 / 5415): the first design used a pending
marker written by the new refresh button, but every user still runs the old code, whose refresh
button writes nothing, so the first release would have shown the stories to nobody. Now:

- Per browser "seen" mark: prefs `stories_seen_version` = the version whose stories this browser
  opened.
- On app load, once the user is signed in and `utilities/information` has been read (and applied:
  a new device first saves the version as its cached one): the running version equals the server's
  (not waiting for a refresh), the mark is not that version, and stories match the user's audience
  = the stories screen opens over the app, and the mark is set as it opens (a tab closed mid-story
  never loops). Decided once per app session.
- No matching story = no screen and no mark. The pending marker of the first design is gone.
- Accepted consequences (Omer): a new device, cleared site data or a private window sees the
  current version's stories once; a member who joins a story's audience while that version is live
  (becomes permanent) sees them once on the next load.
- Audience: `managers` = `isAdmin`; `permanent` = `isPermanent` or `isAdmin` (my call: managers
  see everything); `all` = everyone.
- The notifications popup (`maybeShowPushPrompt`) waits until the stories close.

## The stories screen

Full screen, black. Bars at the top (RTL: the first story's bar on the right, bars fill right to
left, as Instagram in Hebrew - my call). Tap the left half = next, right half = previous; long
press pauses. Image: 5 s. Video: its own length (muted, inline, autoplay); a video that fails to
load (or is not ready within 10 s) is skipped. X closes at any time. After the last story: the
last frame dimmed with "צפייה מחדש" and "סגירה".

Player: the official `video_player` (web: an HTML `<video>`, muted autoplay works on iPhone).

## Files and caching

Story files live in `shavtzak/web/stories/` and deploy with the merge (GitHub Pages).
`web/stories/` holds ONLY the current version's story files (Omer, msg 5390): a version with new
stories deletes the previous version's files in the same merge, and a version with no stories
empties the folder. The Remotion sources (`feature_stories/`) and git history stay. They are
excluded from the service worker's precache manifest (`tool/generate_service_worker.mjs`), so the
in-app refresh never re-downloads every story ever made; the stories screen fetches them on demand.

## Checking without a version change

`?stories=<file>,<file>` in the address (before the `#`) opens the stories screen with those files
(`.mp4` = video, else image), audience ignored, and never sets the "seen" mark. Used by preview links and by the skill.

## Producing stories (the skill)

`feature_stories/` (repo root) is a Remotion project. Each story is a composition (1080x1920
portrait, 30 fps; a still for an image story) built from the app's real colours, the Rubik font
and the app's widgets' look, with made-up names. Renders go to `shavtzak/web/stories/`. The skill
(`.claude/skills/feature-story/SKILL.md`) walks: pick image vs video and the scenes from the
feature -> build the composition -> render -> check on a preview with `?stories=` -> after the
merge, add the item to `WhatsNewStories` with Omer's OK.

## First story

Tagging (V5.6.0): a manager writes an update with "@" on a task, picks a member, sends; the tagged
member's "המשימות שלי" gets the task with the @ mark; they tick it done.

## Non-goals

No sound, no text in the media, no replay entry point, no per-user "seen" state on the server (the mark is per browser).
