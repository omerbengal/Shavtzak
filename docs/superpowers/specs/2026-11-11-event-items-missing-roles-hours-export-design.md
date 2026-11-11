# Event items, missing roles, and custom hours in the Drive export — design

Date: 2026-11-11. Worktree: `.claude/worktrees/event-items-missing-roles-hours-export`.
Mockups the user reviewed: https://claude.ai/artifact/2CLCBtbwF5tjgTnNUvMzxB (v2).

Three independent features, shipped together. Each section says what the user
decided and what was left to the builder ("builder's call" marks my own
decisions, which the user can still overturn).

---

## Feature 1 — "תפקידים חסרים" on the per-event assignments picture

**Why:** the picture is what gets sent to the team; whoever reads it should see
at a glance which roles are still unfilled.

**What the user decided**
- A line at the bottom of the per-event picture (the one built by
  `EventAssignmentsShareDataBuilder` / `EventAssignmentsShareCard`), after the
  numbered notes, before the "נוצר משבצק" footer:
  `תפקידים חסרים: 1 נהג | 3 צלם`
- Missing for a role = the event's quota (`roleRequirements[roleKey]`) minus
  the number of assignments in that role. Over-filled roles count as 0.
- Roles appear in the same order the picture already uses for roles
  (`activeRoles` order). Format per role: `<count> <hebrewName>`, joined by ` | `.
- No line at all when nothing is missing.
- Same line whether the picture is grouped by role or by label.

**Builder's call**
- Count every assignment of the event in that role, including ones whose
  `teamMember` didn't populate (they still occupy a slot). Only roles present
  in `activeRoles` are listed; a quota for an archived/unknown role is ignored.
- Styling: visually distinct (warning tone, like the mockup), legible at the
  picture's capture width.

---

## Feature 2 — "מה יש באירוע" (event items)

**Why:** events have extras the team must prepare for (סריקה, חנוכייה, להקה…).
Today that lives in free-text comments; the user wants it as a short, reusable,
emoji-tagged list that shows up wherever the team looks at the event.

### Data
- New field on `Event`: `items: List<EventItem>` (default empty), where
  `EventItem { String name; String? emoji }` (Equatable; order preserved as the
  admin entered it). Included in `Event.props`, `copyWith`, `EventModel`
  to/from Firestore.
- Firestore: `items: [{name, emoji}]` on the event doc (`emoji` null when none).
- **Backend** (`functions/src/index.ts`, `eventDocFromJson`): add `items`,
  normalized (trimmed names, empty names dropped, duplicate names collapsed,
  emoji trimmed → null when empty, sane length caps). **Absent key keeps the
  stored items** (same rule as custom hours): an old build's `event.update`
  carries no `items` key and must not wipe them; an explicit `[]` clears.
  Applies to `event.insert`, `event.update`, `event.insertBatch`.
  Deploy Functions before the client is tested (backward compatible).
- Event duplication copies the items (builder: verify the duplicate path
  carries them through; it should via the entity).

### Reuse without a management screen (user decision)
- No "manage items" screen. Suggestions come from items already used in other
  events.
- In the event form, typing a name suggests matching names from all events'
  items, each with its emoji. Picking one adds it with that emoji; typing a
  new name adds it as new (no emoji until the admin adds one).
- Changing an item's emoji in one event changes **only that event**. But the
  suggestion offered next time uses the **most recent** emoji for that name.
- **Builder's call:** "most recent" = from the event with the latest
  `updatedAt` among events that have an item with that exact (trimmed) name;
  that event's emoji (possibly none). Suggestions come from the events list the
  `EventBloc` already streams (all events, no new query). Match by substring of
  the trimmed name. Items already on this event are not suggested.

### Event form (create + edit) — `event_form_modal.dart`
- New section "מה יש באירוע" directly above "הערות" (as in the mockup).
- Each item is a chip: name, a round emoji slot (shows the emoji, or "＋" when
  none), and ✕ to remove. Tapping the emoji slot opens a small dialog to set,
  change or clear the emoji.
- Below the chips: a text field with the suggestion dropdown described above,
  last option "הוספת "<typed>" כחדש".
- **Builder's call:** the emoji is whatever the admin types (phone emoji
  keyboard), limited to one grapheme cluster (`characters` package) so skin-tone
  emojis like 🤳🏻 count as one. Name max ~30 chars. Same name can't be added
  twice to one event. The form's unsaved-changes check includes items.
  Reordering chips is not needed.

### Where items show
Display text helper (one shared pure function): each item renders as
`name emoji` (or just `name` with no emoji).

1. **Per-event assignments picture:** a line after the event's details and the
   event note, before the assignment sections:
   `באירוע זה יש: סריקה 🤳🏻, חנוכייה 🕎, להקה`. Hidden when the event has no items.
2. **Calendar picture** (`/summary` calendar share, `CalendarShareCard`
   `_EventBlock`): one extra line after the location: emojis only, and the full
   name for an item without an emoji, separated by `, ` —
   `🤳🏻, 🕎, להקה`. The user said "let's try to squeeze; if it's not good I'll
   tell you", so the text fallback is deliberate. **Builder's call:** the line
   wraps (not scaled down like the time lines); on a continuation day (`המשך`)
   it is shown too.
3. **Member's personal area** (`/user/assignments` card): the same
   `באירוע זה יש: …` bar as the picture, after the location/parking rows.
   Hidden when empty.

**Non-goals:** items in the Google Calendar/ICS description, the Drive
export, the admin event list, filtering by item, a global rename of an item.

---

## Feature 3 — custom hours in the Drive ("אקסל") assignments export

**Why:** the export from the admin home (`AssignmentExportDialog` →
`exportAssignmentsOnly` → `serializeAssignmentsOnly` in
`functions/src/drive_export.ts`) shows the event's times for everybody, so a
member with their own hours looks like they come for the whole event.

**What the user decided:** do what `/user/assignments` already does for a member
with custom hours (`memberCardTimeRows` in `user_assignments_screen.dart`), in
the existing columns. Both modes (לפי חבר צוות, לפי אירוע). Rows without
custom hours are unchanged.

For a row whose assignment has readable custom hours (`customHoursInterval`):

| Column | Value |
|---|---|
| תאריך תחילת אירוע | member's first day; `(האירוע מ-d.M)` appended when it differs from the event's first day |
| תאריך סיום | member's last day (blank when single-day, as today); `(האירוע עד d.M)` when it differs from the event's last day |
| שעת התייצבות | member's arrival `HH:mm` (prefixed by `d.M` when not the event's first day) + ` (התייצבות צוות <assembly>)` when the event has an assembly time |
| שעת תחילת אירוע / שעת סיום אירוע | unchanged — the show doesn't move |
| (single own day inside a multi-day event) | as on the card: end column blank, and both notes on the start column, e.g. `5.12 (האירוע מ-4.12) (האירוע עד 6.12)` (builder's call, follows the card) |
| הערות שיבוץ | `יציאה d.M HH:mm (סיום צוות משוער d.M HH:mm)` — bracket worded as on the card (team end / show end / dropped) — then ` · <existing note>` when there is one. **Only on rows with custom hours** (user decision). |

**Builder's call**
- Port the card's wording to TypeScript next to the existing helpers in
  `event_stretch.ts` (it already has the stretch / wall-day logic) and keep the
  Dart and TS wording in sync, with a shared case table in tests like the
  conflict-check work did. Date format `d.M` and the 00:00-departure rule
  (reads as the next day's 00:00) follow the card.
- Sorting keeps using the event's start date/time (not the member's), so rows
  of one event stay together.
- Functions-only change: deploy Functions; no client change needed.

---

## Testing (builder)
- Dart unit tests: missing-roles computation (quota/assigned/over-filled/role
  order/no line), item display strings, suggestion ranking (most recent emoji
  wins, exclusion of items already on the event), `EventModel` round trip with
  and without `items`.
- Widget test for the form section (add from suggestion, add new, set/clear
  emoji, remove).
- Functions tests: `eventDocFromJson` items normalization and absent-key-keeps;
  `serializeAssignmentsOnly` custom-hours rows in both modes (same-day, crosses
  midnight, starts on a later day, no assembly time, with and without a note).
- `flutter analyze` (zero new issues), `flutter test`, `npm test`.

## Deploy order
1. `firebase deploy --only functions` (items field + export) — backward
   compatible with the live web build.
2. Merge to `main` → web auto-deploys.
