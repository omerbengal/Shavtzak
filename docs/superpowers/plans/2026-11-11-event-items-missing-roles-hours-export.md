# Event items, missing roles, custom hours in Drive export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the three features in the spec: missing-roles line on the event picture, event items ("מה יש באירוע") end to end, custom hours in the Drive assignments export.

**Architecture:** Backend (`functions/src`) learns an `items` event field (absent key keeps) and the member-hours cells for the export, as pure helpers with unit tests. Client adds an `EventItem` entity on `Event`, pure display/suggestion helpers in `lib/core/utils/event_items.dart`, and wires them into the form, the two pictures and the member card.

**Tech Stack:** Flutter web (bloc, equatable, characters), Firebase Functions TypeScript (jest).

**Spec:** `docs/superpowers/specs/2026-11-11-event-items-missing-roles-hours-export-design.md`

## Global Constraints
- All UI text Hebrew, RTL. Code comments English.
- Item sentence: `באירוע זה יש: ` + items as `name emoji` / `name`, joined `, `.
- Calendar line: emoji, or name when no emoji, joined `, `.
- Missing roles: `תפקידים חסרים: ` + `<n> <hebrewName>` joined ` | `.
- Export departure note: `יציאה d.M HH:mm` + optional ` (<label> d.M HH:mm)` + optional ` · <note>`.
- Backend: absent `items` key on update keeps stored items; explicit `[]` clears.
- `flutter analyze` zero new issues; `flutter test` and `npm test` green.

## Review Focus
- Old web build saves an event (no `items` key) → items survive (Task 1 test).
- Item with emoji cleared to '' → stored as null, renders without emoji (Tasks 1, 3).
- Event with quota for a role no longer in active roles → not listed as missing (Task 4).
- Custom hours unreadable (bad string) → row identical to today (Task 2).
- Departure exactly at 00:00 → reads as next day's 00:00, not previous day 24:00 (Task 2).

---

### Task 1: Backend `items` field
**Files:** Create `functions/src/event_items.ts`, `functions/src/event_items.test.ts`; Modify `functions/src/index.ts` (`eventDocFromJson`).
**Produces:** `normalizeEventItems(value: unknown): {name: string; emoji: string | null}[] | undefined` — `undefined` when value is `undefined` (absent key); non-array → `[]`; trims; drops empty names; names capped at 40 chars; duplicate names keep first; emoji trimmed, `''`→null, capped at 16 chars.
- [ ] Tests: absent → undefined; `[{name:' סריקה ',emoji:'🤳🏻'},{name:'להקה',emoji:''},{name:''},{name:'סריקה',emoji:'x'}]` → `[{name:'סריקה',emoji:'🤳🏻'},{name:'להקה',emoji:null}]`; `null` → `[]`.
- [ ] Implement; `eventDocFromJson` sets `items: normalizeEventItems(event['items'])` (stripUndefined drops it when absent).
- [ ] `cd functions && npm test` green. Commit.

### Task 2: Export custom-hours cells
**Files:** Create `functions/src/member_hours_cells.ts` + test; Modify `functions/src/drive_export.ts` (`serializeAssignmentsOnly` row build + `AssignmentOnlyRow`).
**Produces:** `memberHoursCells(event: {firstDay: Date; lastDay: Date; assemblyTime; startTime; endTime; teamEndTime}, customStartAt: unknown, customEndAt: unknown): {startDate: string; endDate: string; assembly: string; departureNote: string} | null` — null when `customHoursInterval` is null. Dates `dd/MM/yyyy` (the export's format), notes `(האירוע מ-d.M)` / `(האירוע עד d.M)`; single own day → end '' and both notes on start. Arrival `HH:mm` or `d.M HH:mm` when not the event's first day, + ` (התייצבות צוות X)` when assembly set. Departure: `יציאה d.M HH:mm` (end at 00:00 is that next day 00:00 — format `end` directly), bracket label `סיום צוות משוער` if teamEndTime readable else `סיום מופע משוער` if endTime readable else none, time = `eventStretch(event).end`.
- [ ] Tests: same-day 14:00–23:00 on single-day event (assembly 12:00, teamEnd 01:00); middle day of 3-day event; arrival on day 2; no assembly; end 00:00; invalid hours → null. Plus `__testSerializeAssignmentsOnly` row with hours: columns replaced, note `יציאה … · existing`; row without hours unchanged.
- [ ] Implement; in the serializer, when cells non-null override startDate/endDate/assemblyTime and prepend departure to notes (`notes ? `${dep} · ${notes}` : dep`). Sorting still by event key.
- [ ] `npm test` green. Commit.

### Task 3: `EventItem` entity + helpers
**Files:** Create `lib/domain/entities/event_item.dart`, `lib/core/utils/event_items.dart`, `test/core/utils/event_items_test.dart`; Modify `event.dart` (field `items`, props, copyWith), `event_model.dart` (to/from Firestore + json), `test/data/models` round trip.
**Produces:** `EventItem(name, emoji)` with `label` getter (`name emoji`/`name`) and `compact` getter (emoji ?? name); `String? eventItemsSentence(List<EventItem>)`; `String? eventItemsCompactLine(List<EventItem>)`; `List<EventItem> suggestEventItems(String query, List<Event> events, List<EventItem> exclude)` (substring of trimmed name, newest event `updatedAt` wins emoji, excludes names already present, sorted by name, max 6).
- [ ] Tests for each helper (spec values); model round trip with/without `items`.
- [ ] Implement. Commit.

### Task 4: Event picture — items line + missing roles
**Files:** Modify `event_assignments_share_models.dart` (`itemsLine`, `missingRolesLine`), `event_assignments_share_data_builder.dart`, `event_assignments_share_card.dart`; tests in the two existing test files.
**Produces:** `static String? missingRolesLine(Event, List<Assignment>, List<Role> activeRoles)` on the builder.
- [ ] Tests: quota {driver:2, photographer:3}, 1 driver assigned → `תפקידים חסרים: 1 נהג | 3 צלם` (role names from fixture); overfilled → no entry; unknown role key ignored; all filled → null; card shows both lines.
- [ ] Implement (items line after event note, missing line after notes). Commit.

### Task 5: Calendar picture line
**Files:** `calendar_share_models.dart` (`itemsLine` on `CalendarShareEvent`, default ''), `calendar_share_data_builder.dart`, `calendar_share_card.dart` (`_EventBlock`, after location, wraps); test in `calendar_share_data_builder_test.dart`.
- [ ] Test, implement, commit.

### Task 6: Member card bar
**Files:** `user_assignments_screen.dart` card (after parking section): `באירוע זה יש: …` bar when non-empty; test in `test/presentation/screens/user/`.
- [ ] Test, implement, commit.

### Task 7: Event form section + duplication
**Files:** Create `lib/presentation/screens/event/widgets/event_items_field.dart` (`EventItemsField({items, allEvents, onChanged})`), test; Modify `event_form_modal.dart` (state `_items`, init from event, dirty, Event(items:), above הערות), `event_event.dart` `DuplicateEvent.newItems`, `event_bloc.dart` duplicate passes `items`.
- [ ] Widget test: typing "סר" shows existing "סריקה 🤳🏻" suggestion; tap adds chip; "הוספת "X" כחדש" adds without emoji; tapping emoji slot → dialog sets/clears; ✕ removes; emoji limited to 1 grapheme.
- [ ] Implement; analyze; full `flutter test`. Commit.

### Task 8: Docs + verification
- [ ] CLAUDE.md: mention `items` collection field + export hours. `flutter analyze`, `flutter test`, `npm test`, `npm run build`. Commit.
