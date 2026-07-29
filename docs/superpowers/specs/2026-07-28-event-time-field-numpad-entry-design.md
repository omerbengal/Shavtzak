# Event time fields: numpad entry with an opt-in wheel picker

**Date:** 2026-07-28
**Branch:** `worktree-feat-time-field-numpad-entry`
**Status:** Approved

## Problem

The event create/edit modal has five time fields — התייצבות, התכנסות קהל, תחילת המופע
בפועל, סיום המופע, סיום הצוות. All five are `readOnly`, and tapping anywhere on a
field opens a Cupertino wheel carousel. Spinning a wheel to reach 18:00 is slower
than typing `1800`, and it is the only way to set a time.

The admin should be able to type the time on a plain numpad, and reach the wheel
only when they want it.

## Current implementation

One helper, `_buildTimeField` at `event_form_modal.dart:391`, backs all five
fields. Each renders as:

- `readOnly: true`, `onTap:` opens `_showTimePickerFor` (the wheel dialog at
  `event_form_modal.dart:286`)
- `prefixIcon:` a decorative `Icons.access_time` (`Icons.play_circle_outline` on
  the show-start field)
- `suffixIcon:` a clear ✕ `IconButton`, rendered only when the controller has text

The modal is wrapped in `Directionality(textDirection: TextDirection.rtl)` at
`event_form_modal.dart:995`, so **the prefix icon renders at the far right of the
field and the suffix ✕ at the far left**. Every "left"/"right" in this document
means the physical position on screen, not the prefix/suffix slot.

Two of the fields carry an `onPicked` callback that auto-fills a neighbour when
that neighbour is still empty: picking התכנסות קהל fills התייצבות at −2h, and
picking סיום המופע fills סיום הצוות at +1h. Two `_buildDeriveArrow` buttons
(שעתיים לפני / שעה אחרי) do the same thing on demand, and grey themselves out when
pressing them would change nothing.

`_saveEvent` already calls `_formKey.currentState!.validate()` at
`event_form_modal.dart:491` and aborts the save when it returns false. None of the
five time fields currently supplies a `validator`, because a read-only field
cannot hold a bad value.

## Design

### 1. Extract the field into its own widget

`event_form_modal.dart` is 2793 lines, and the time field is about to acquire real
behavior — an input formatter, blur completion, and validation — that should be
testable without mounting the whole modal and its BLoCs.

New file: `lib/presentation/screens/event/widgets/event_time_field.dart`, holding
an `EventTimeField` widget. This mirrors `ParticipantGroupRows`, which already
lives in that folder and is covered by a standalone widget test
(`test/presentation/screens/event/widgets/event_form_participant_groups_test.dart`)
that constructs the widget directly with no BLoC scaffolding.

`_buildTimeField` is deleted from the modal; the five call sites construct
`EventTimeField` instead.

Public API:

```dart
EventTimeField({
  required TextEditingController controller,
  required String label,
  required String hint,
  required String logKey,
  void Function(String value)? onTimeSet,   // was: onPicked
  required VoidCallback onChanged,          // modal marks itself dirty + rebuilds
})
```

`onTimeSet` replaces `onPicked` and fires for **both** input paths — wheel and
typing — see §6. `prefixIcon` is not a parameter any more; see §3.

The wheel dialog itself (`_showTimePickerFor`) moves into the new file unchanged.
It keeps its Hebrew ביטול / אישור footer, its `use24hFormat: true`, and its
existing `Logger.action` calls.

### 2. The field becomes typable

- `readOnly: true` removed. Tapping the field focuses it and raises the numpad.
  The `onTap` that opened the wheel is gone — the wheel is now reachable only via
  the clock button.
- `keyboardType: TextInputType.number` — a digits-only keypad on mobile browsers,
  which is where this matters. On desktop web `keyboardType` has no effect and the
  physical keyboard is used; the formatter (§4) still constrains what lands in the
  field.
- `textDirection: TextDirection.ltr` on the input, so digits and the caret are not
  reordered by the surrounding RTL context while editing. `textAlign` keeps the
  value hugging the right-hand edge, exactly where it sits today.

### 3. Icon layout

Physically, as rendered on screen:

```
 ┌──────────────────────────────────────┐
 │  🕐  ✕                       18:00   │
 └──────────────────────────────────────┘
    ▲   ▲
    │   └─ clears the field (only when it has a value)
    └───── opens the wheel carousel
```

- Far left (the `suffixIcon` slot under RTL): a `Row(mainAxisSize: MainAxisSize.min)`
  holding the clock `IconButton` then the ✕ `IconButton`. The ✕ keeps its current
  conditional rendering — present only when the controller is non-empty — so an
  empty field shows the clock alone.
- Far right (the `prefixIcon` slot under RTL): **removed**. The decorative
  `Icons.access_time` / `Icons.play_circle_outline` is dropped from all five
  fields. The Hebrew labels already name each field, and a clock at both edges
  reads as two different buttons.

Both buttons need `tooltip`s for the widget tests to target them, and to match the
`byTooltip` convention already used in `ParticipantGroupRows`.

### 4. Typing: the input formatter

New `TimeTextInputFormatter` in `lib/core/utils/time_input_formatter.dart`, beside
the existing `phone_input_formatter.dart` it is modelled on.

Rules:

- Strip every non-digit from the incoming value.
- Cap at 4 digits; extra digits are dropped.
- Insert `:` after the second digit once there are 3 or more digits.
- Do **not** reject digits that make an impossible time. `2570` is typable and is
  caught at save time (§7). This was an explicit decision: the formatter never
  fights the keyboard.

Resulting display while typing:

| Keystrokes | Field shows |
|---|---|
| `1` | `1` |
| `1` `8` | `18` |
| `1` `8` `0` | `18:0` |
| `1` `8` `0` `0` | `18:00` |
| `2` `5` `7` `0` | `25:70` |

Backspace walks back down the same ladder (`18:00` → `18:0` → `18` → `1` → empty).
Pasting is run through the same digit-strip-and-mask path. The cursor is kept at
the end of the formatted text, following `PhoneNumberTextInputFormatter`'s
approach, including its handling of selection-based deletion.

### 5. Blur completion

On focus loss the field completes a partial entry. New pure helper —
`completePartialTime(String raw) -> String` — placed next to the formatter so it
can be unit-tested in isolation.

| Typed | After tapping away | Why |
|---|---|---|
| (empty) | (empty) | All five fields are optional |
| `9` | `09:00` | Hour padded left, minutes filled |
| `18` | `18:00` | Minutes filled |
| `18:3` | `18:30` | Minutes are typed tens-first, so the trailing 0 is added |
| `18:00` | `18:00` | Already complete — first guard |
| `9:05` | `9:05` | Already valid — first guard |
| `93` | `93` | Unchanged — second guard |
| `25:70` | `25:70` | Already 4 digits, nothing to complete |

**First guard — already valid wins.** If the raw text is already a valid `HH:mm`,
return it untouched without looking at its digit count. This matters for legacy
data: a stored `9:05` is three digits, and the tens-first minute rule would
otherwise rewrite it to `90:50`. Hydrated values bypass the input formatter
(formatters only run on user input), so this check is the only thing protecting
them.

**Second guard — never complete into an invalid time.** Otherwise, completion is
applied only if the completed result is a valid `HH:mm`. `93` would complete to
`93:00`, which is not a real time, so the raw text is left exactly as typed and the
user sees the red error on Save instead of a silently mangled value.

Implemented by wrapping the `TextFormField` in a `Focus` widget and running
completion in `onFocusChange` when focus is lost.

### 6. Auto-fill fires for typed input too

The `onPicked` callback currently fires only from the wheel. Renamed `onTimeSet`,
it now also fires after blur completion produces a complete valid time. So typing
`1800` into התכנסות קהל auto-fills התייצבות with `16:00` when it is empty, exactly
as picking `18:00` from the wheel does today. Same for סיום המופע → סיום הצוות at
+1h. The existing "only when the target is empty" condition at the call sites is
unchanged.

`onTimeSet` must not fire per keystroke — filling התייצבות from a half-typed `1`
would be wrong. Blur (and wheel confirm) are the only trigger points.

### 7. Validation

New `Validators.validateOptionalTime` in `lib/core/utils/validators.dart`, beside
the existing `validateTime`. The existing one cannot be reused: it returns
`שעה היא שדה חובה` for an empty value, and all five of these fields are optional.

```
empty / whitespace  -> null (valid)
matches ^([01]?\d|2[0-3]):[0-5]\d$ -> null (valid)
otherwise -> 'פורמט שעה לא תקין'
```

Wired as the `validator:` on `EventTimeField`. No change is needed in `_saveEvent`:
it already calls `validate()` at `event_form_modal.dart:491` and returns early when
it fails, so an invalid time turns its field red and blocks the save for free.

### 8. Live rebuild

Today the ✕ appears and disappears only because `_showTimePickerFor` calls
`setState`. With typing, the modal must rebuild on each keystroke, or the ✕ will
not appear and the two derive arrows will not update their enabled state — both
are computed from `controller.text` at build time.

`EventTimeField` takes an `onChanged` callback; each of the five call sites passes
a closure that sets `_isDirty = true` and calls `setState`. This also fixes a
latent rough edge: the derive arrows currently only re-evaluate when the wheel is
used.

## Out of scope

- The `showTimePicker` / `TimeOfDay` usages in `constraints_screen.dart` and
  `team_list_screen.dart`. The request was specifically about the event modal.
- The wheel dialog's own appearance and behavior. It moves files but is otherwise
  untouched.
- The date fields in the same modal.

## Testing

Unit tests:

- `TimeTextInputFormatter` — progressive typing 1/18/180/1800, backspace down the
  ladder, paste of `1800` and of `18:00`, more than 4 digits truncated, letters and
  symbols stripped, impossible times like `2570` allowed through.
- `completePartialTime` — every row of the §5 table, including the `93` no-op, the
  empty no-op, and the `9:05` legacy-value no-op that the first guard protects.
- `Validators.validateOptionalTime` — empty and whitespace pass, `18:00`, `00:00`,
  `23:59`, `9:05` pass, `25:70`, `24:00`, `18:60`, `18`, `93`, `abc` fail.

Widget tests for `EventTimeField`, following the `ParticipantGroupRows` host
pattern (direct construction, no BLoCs), inside an RTL `Directionality` and a
`Form`:

- typing `1800` leaves `18:00` in the controller
- typing `18` then unfocusing leaves `18:00`; typing `93` then unfocusing leaves `93`
- the clock button opens the wheel dialog
- the ✕ is absent on an empty field, present once it has a value, and clears it
- an invalid value fails `Form.validate()` and shows `פורמט שעה לא תקין`
- `onTimeSet` fires on blur completion and on wheel confirm, and not per keystroke

Regression check: the existing suite must stay green. Per the project baseline,
`flutter analyze` carries ~107 pre-existing infos — "clean" means zero *new*
findings, not zero findings.

## Verification

From `shavtzak/`:

```
flutter analyze
flutter test
```

Manual smoke in the running app, on the event create modal and the event edit
modal: type a time, use the clock button, use the ✕, confirm the derive arrows
grey out as you type, confirm an invalid time blocks Save with a red error.
