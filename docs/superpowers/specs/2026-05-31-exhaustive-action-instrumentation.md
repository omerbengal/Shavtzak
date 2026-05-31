# Exhaustive UI Action Instrumentation — Convention

- **Date:** 2026-05-31
- **Status:** Active contract for the instrumentation sweep
- **Goal:** Every user-initiated interactive handler in `lib/presentation/**` records a `Logger.action(...)`, so a shared debug log shows EXACTLY what the user did, in order.

## 1. Naming convention: `verb:subject`

Action names are colon-grouped, lowerCamelCase after each colon. Verbs:

| Verb | When | Example |
|------|------|---------|
| `tap:` | A button press that performs an action | `tap:saveEvent`, `tap:deleteTeamMember`, `tap:approveConstraint`, `tap:duplicateEvent`, `tap:editMember`, `tap:callPhone`, `tap:copyToClipboard` |
| `tap:cancel:` / `tap:close:` | Dismiss / cancel / close a dialog or form | `tap:cancel:eventForm`, `tap:close:settingsDialog` |
| `open:` | Opens a dialog / modal / sheet / sub-screen | `open:eventFormModal`, `open:settingsDialog`, `open:roleManagementDialog` |
| `filter:` | A filter change (chip/segment/dropdown acting as a filter) | `filter:scope {value: permanent}` |
| `toggle:` | A `Switch` / `Checkbox` change | `toggle:permanentOnly {on: true}` |
| `select:` | A dropdown / radio / popup-menu / choice-chip selection | `select:role {role: medic}`, `select:category {categoryId: c_12}` |
| `swipeDelete:` | A `Dismissible.onDismissed` | `swipeDelete:assignment {assignmentId: a_77}` |
| `longPress:` | A long-press that does something (NOT the debug trigger) | `longPress:memberCard {memberId: m_3}` |

**Subject** = a short, stable, descriptive name of the thing acted on. Prefer the domain concept (`saveEvent`, `eventFormModal`) over the widget type. Be consistent within a file.

Multi-segment subjects are fine when they clarify (`tap:cancel:eventForm`, `tap:close:settingsDialog`).

## 2. Context policy (privacy-critical)

`Logger.action(name, {context})`. The context map carries **only**:

- Entity IDs: `eventId`, `memberId`, `assignmentId`, `roleId`, `categoryId`, `labelId`, `constraintId`, `presetId`, `checklistItemId`, etc.
- Booleans / enums / mode strings: `isPermanent`, `mode: 'edit'`, `status: 'approved'`.
- Selected values that are **non-PII** enums/keys: `role: 'medic'`, `scope: 'permanent'`.
- Counts / indices: `count: 12`, `index: 2`, `tabIndex: 1`.
- For toggles/filters/selects, include the new value: `{on: bool}`, `{value: ...}`, `{<field>: ...}`.

**NEVER** put raw content in the context:
- No names, notes, emails, phone numbers, passcodes, locations, addresses, free text.
- If a value might be content, wrap it: `Logger.redact(thatString)` → `<N chars>`.
- For a phone-call button: `tap:callPhone {memberId: ...}` — never the number.
- For a dropdown whose value is a display name, log the **id/enum**, not the label; if only a label is available and it could be PII, `Logger.redact(label)`.

When in doubt, log the ID and the verb; omit the value.

## 3. Transformation rules (must NOT change behavior)

Add `Logger.action(...)` as the **first statement** the handler runs. Patterns:

| Existing | Becomes |
|----------|---------|
| `onPressed: () { body }` | `onPressed: () { Logger.action('tap:x'); body }` |
| `onPressed: () => _save()` | `onPressed: () { Logger.action('tap:saveX'); _save(); }` |
| `onPressed: _save` (tear-off) | `onPressed: () { Logger.action('tap:saveX'); _save(); }` |
| `onPressed: _busy ? null : () => _save()` | `onPressed: _busy ? null : () { Logger.action('tap:saveX'); _save(); }` |
| `onPressed: null` (disabled) | **skip** — no handler runs |
| `onChanged: (v) { body }` on Switch/Checkbox | first line `Logger.action('toggle:x', {'on': v});` |
| `onChanged: (v) {...}` on Dropdown | first line `Logger.action('select:x', {'x': v?.toString()});` (id/enum, not PII) |
| `onChanged` on TextField/TextFormField (free text) | **skip** — per-keystroke text is noise + PII |
| `onSubmitted` on a search/filter field | `tap:submit:searchX` (no raw text; optionally length via `Logger.redact`) |
| `onSelected: (v) {...}` (PopupMenuButton) | first line `Logger.action('select:menuX', {'choice': v.toString()});` |
| `onTap: () {...}` (InkWell / GestureDetector / ListTile) | `tap:<rowThing>` with id if available |
| `onDismissed: (dir) {...}` (Dismissible) | first line `Logger.action('swipeDelete:x', {'xId': ...});` |
| `onLongPress: () {...}` | `longPress:<thing>` |

If converting an arrow/tear-off to a block changes the return type expectation (rare — most handlers are `void`), keep the original return: `() { Logger.action(...); return _f(); }`.

**Never** reorder, remove, or restructure existing logic. The only change is inserting the log call (and, where required, wrapping an arrow/tear-off in a block).

## 4. Coverage (maximal)

Instrument every handler in §3 — including Cancel/Close/Back buttons (knowing the user backed out is diagnostic), toggles, list-row taps, swipes, menu/dropdown/chip selections, navigation buttons.

**Exclusions:**
- Per-keystroke `onChanged` on free-text fields (PII + flood).
- Pure presentation toggles with no logic (e.g. a local `setState` expand/collapse chevron) MAY be logged as `tap:expandX`/`toggle:expandX` for completeness — include them (maximal coverage), they're cheap.
- Debug-infra widgets: do NOT touch `swipeable_page_view.dart` (debug trigger + the bottom-nav taps already produce `NAV` entries) or any `core/debug/**`.
- Pure stream/listener callbacks that are not user gestures (e.g. a `BlocListener`, a calendar-sync stream listener) — skip; they're not button presses.

## 5. Import

Each touched file needs `import '<relative>/core/debug/logger.dart';`. Compute the relative path by file depth (e.g. `screens/team/team_list_screen.dart` → `../../../core/debug/logger.dart`; `screens/event/widgets/event_form_modal.dart` → `../../../../core/debug/logger.dart`; `widgets/settings_dialog.dart` → `../../core/debug/logger.dart`). If the file already imports it, do not duplicate.

## 6. Normalizing the existing 10 sites

These already-instrumented **user-action** names get renamed to the convention (and any test asserting the old literal is updated):

| Old | New |
|-----|-----|
| `openMemberModal` | `open:memberModal` |
| `openEventFormModal` | `open:eventFormModal` |
| `openManualAssignmentFlow` | `open:manualAssignmentFlow` |
| `swipeDeleteAssignment` | `swipeDelete:assignment` |
| `filterChange` | `filter:bar` (interactive_filter_bar; keep its existing context) |
| `openSettingsDialog` | `open:settingsDialog` |
| `openWhoIsWithMeDialog` | `open:whoIsWithMe` |

**Do NOT rename** internal debug telemetry — `debugShareMenuOpen`, `debugShareLogsCopied`, `clipboardFailed` — they are asserted by tests and are not user actions. (`swipeable_page_view.dart` is excluded from the sweep anyway.)

## 7. Verification (per file + global)

- Per file: after editing, run `flutter analyze <thatfile>` (or `dart analyze <thatfile>`) — must be clean of NEW errors. No unused-import, no syntax error.
- Global (after the whole sweep): `flutter analyze` (no new errors vs the 108 baseline) and `flutter test` (all green; fix any test asserting a renamed name).
- A completeness pass re-greps each file for handlers still lacking a `Logger.action`.
- A PII pass scans the diff for any context value that looks like raw content.

## 8. Out of scope

- No new `LogEventType` (reuse `action`). No formatter changes (done separately).
- No behavior changes, no refactors beyond the minimal closure-wrapping in §3.
