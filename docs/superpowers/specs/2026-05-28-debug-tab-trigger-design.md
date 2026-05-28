# Debug Logger Share — Tab-Trigger Redesign

- **Date:** 2026-05-28
- **Status:** Draft (awaiting review)
- **Owner:** Omer
- **Supersedes parts of:** `docs/superpowers/specs/2026-05-18-debug-logger-design.md` §6.7 and §3 (admin-only constraint)

## 1. Background

The original debug-logger spec (2026-05-18) placed the share trigger on the "+" FAB of the three admin management tabs: long-press → mini-FAB → tap to copy. After living with that for a release-candidate, two limitations became clear:

1. **The FAB is admin-only.** The user-facing screens (`/user/assignments`, `/user/constraints`) have no FAB, so non-admin users (and admins on the user routes) have no way to share a buffer. But the bugs we want to diagnose can happen anywhere, including on the user routes.
2. **Wrapping every FAB is invasive.** The three admin screens each gained a `_buildFab(context)` helper and an explicit `heroTag`. Three near-identical wrappers existed solely for the debug trigger.

This change moves the share trigger to the bottom-navigation tab labels. The bottom nav is present on every shell route (admin management + user shell), so the trigger becomes universal in one change instead of N per-screen wrappers.

## 2. Goals

- One trigger surface that exists on **all** admin and user shell routes.
- Trigger removes the per-screen FAB wrapping entirely; the original FABs go back to being plain `FloatingActionButton`s.
- Preserve the existing mini-FAB confirmation step (long-press → mini-FAB → tap to copy), because:
  - A two-step gesture prevents accidental clipboard writes from stray long-presses.
  - The mini-FAB gives clear visual feedback that the menu opened, without firing off a snackbar before the user committed.
- Mini-FAB is **anchored above the specific tab the user long-pressed**, centered on the tab's horizontal midpoint.
- All other behaviour from the original spec preserved: `formatBuffer`, clipboard write with `try/catch`, success snackbar `הלוג הועתק ללוח (N אירועים)`, error snackbar `שגיאה בהעתקה ללוח`, 4-second auto-dismiss, second-long-press toggle-off, `Logger.action('debugShareLogsCopied', ...)` telemetry.

## 3. Non-Goals

- **No keep-both triggers.** The FAB trigger is removed in its entirety. `DebugLogShareFab` widget is deleted; the three admin FABs revert to plain `FloatingActionButton(...)` (keeping the explicit `heroTag`s — that's hygiene that should not be reverted).
- **No new content in the log.** The buffer, formatter, BLoC observer, DB decorator, route observer, and `Logger.action` instrumentation are unchanged. Only the trigger UI changes.
- **No new screens.** Trigger lives on the existing two bottom-nav widgets (`SwipeablePageView` for admin management, `UserNavigationShell` for user routes). No new top-level navigation surfaces.

## 4. UX Flow

```
[ Bottom nav strip with tabs: "צוות"  "אירועים"  "שיבוצים"  "צ׳ק־ליסט" ]
                                          ▲
                                   long-press here
                                          ▼

                                      ┌────┐
                                      │ 🐞 │   ← mini-FAB, centered above the
                                      └────┘     long-pressed tab; auto-dismisses
                                          ▼     after 4s or on second long-press;
                                   tap the 🐞    tapping it copies + snackbar.
                                          ▼

[ Snackbar: "הלוג הועתק ללוח (47 אירועים)" ]
```

**Tap behaviour unchanged.** A normal short tap on a tab still triggers navigation. Only long-press triggers the debug menu. The tab being long-pressed need NOT be the currently-active tab — the log buffer is route-scoped and resets on navigation, so the captured buffer always reflects the current screen (whichever tab is active when the user long-presses). Choosing which tab to long-press is purely a UI-affordance choice for the user.

**One mini-FAB at a time.** Long-pressing tab A then long-pressing tab B before A's mini-FAB auto-dismisses replaces the position (the mini-FAB moves to above tab B). It does NOT show two mini-FABs.

**Second long-press toggles off.** If the user long-presses the same tab while its mini-FAB is visible, the mini-FAB disappears (matches existing `DebugLogShareFab` behaviour from Task 8).

## 5. Architecture

### 5.1 Shared utility

Extract the existing `_copyLogs` logic from `DebugLogShareFab` into a top-level utility so both navigation widgets call it instead of duplicating:

```dart
// shavtzak/lib/core/debug/debug_clipboard_share.dart

/// Copies the current DebugLogger buffer to the clipboard, formatted via
/// formatBuffer, and shows a success or error snackbar. Also records a
/// `Logger.action('debugShareLogsCopied', {...})` telemetry event on success.
///
/// Caller is responsible for dismissing whatever UI revealed the trigger
/// (e.g. the mini-FAB).
Future<void> copyDebugLogsToClipboard(
  BuildContext context, {
  required String currentRouteForShare,
  required String? userDisplay,
  required bool isAdmin,
  required String env,
}) async {
  // — formatBuffer
  // — Clipboard.setData inside try/catch
  // — success or error snackbar
  // — Logger.action telemetry on success
}
```

This function is the single source of truth for the clipboard write. Both bottom-nav widgets call it from their mini-FAB `onPressed`.

### 5.2 Long-press handler on each bottom-nav widget

Each bottom-nav widget gains:

1. **Two pieces of state:**
   - `int? _longPressedTabIndex` — which tab is currently revealing a mini-FAB (`null` = no menu visible).
   - `Timer? _autoDismiss` — 4-second auto-dismiss timer.

2. **One long-press handler:**
   - The `BottomNavigationBar` is wrapped with a `GestureDetector(onLongPressStart: _handleLongPress)`.
   - `_handleLongPress(LongPressStartDetails details)` computes which tab was pressed from `details.localPosition.dx`:
     ```dart
     final tabWidth = MediaQuery.of(context).size.width / _tabCount;
     final tabIndex = (details.localPosition.dx / tabWidth).floor().clamp(0, _tabCount - 1);
     ```
   - Toggle: if `tabIndex == _longPressedTabIndex`, set to `null` (hide). Otherwise, set to `tabIndex` (show / re-position).
   - Cancel any pending `_autoDismiss`; if showing, start a new 4-second timer.

3. **The mini-FAB rendering:**
   - The Scaffold wraps its `bottomNavigationBar` in a `Stack(clipBehavior: Clip.none)`.
   - Inside the stack: the `GestureDetector`-wrapped `BottomNavigationBar` (positioned at the bottom of the stack), plus a conditional `Positioned` mini-FAB rendered ~8px above the bar, centered horizontally on the tab.

4. **The mini-FAB:**
   - `FloatingActionButton.small` (or `mini: true`) with `Icons.bug_report`.
   - `heroTag: 'debug-share-mini-fab-<context>'` where `<context>` distinguishes the two navigation widgets (admin vs. user) to avoid a hero collision if both are ever rendered in the same overlay (they aren't, but the unique tag prevents future surprise).
   - `onPressed: _copyAndDismiss` calls the shared utility then sets `_longPressedTabIndex = null`.

### 5.3 Positioning math

For a bottom nav with `N` tabs in a screen of width `W`:

- Each tab spans `W / N` pixels horizontally.
- The center of tab `i` is at `x = (W / N) * (i + 0.5)`.
- The mini-FAB's `left` is `x - miniFabRadius` (~20dp for `mini: true`).
- The mini-FAB's `bottom` inside the stack: `kBottomNavigationBarHeight + 8` (the bar height plus 8dp gap).

We use `MediaQuery.of(context).size.width` for `W`, which is correct because `BottomNavigationBar` spans the full screen width. Safe-area insets at the bottom are handled by the Scaffold; the mini-FAB is positioned relative to the bar's top edge, not the screen.

### 5.4 Reverting Task 9's FAB wrapping

For each of `team_list_screen.dart`, `event_list_screen.dart`, `assignment_list_screen.dart`:

1. Remove the `_buildFab(context)` helper.
2. Restore the original `floatingActionButton: FloatingActionButton(...)`.
3. **Keep** the explicit `heroTag` (`team-list-fab`, `event-list-fab`, `assignment-list-fab`). The original code had implicit/underscore-style tags; the explicit hyphen-style tags are hygiene and stay.
4. Remove the now-unused imports (`debug_log_share_fab.dart`, `user_selection_bloc`, `environment_service` if not used elsewhere).

### 5.5 Deletion

- `shavtzak/lib/presentation/widgets/debug_log_share_fab.dart` — delete.
- `shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart` — delete.

## 6. Component-Level Spec

### 6.1 `copyDebugLogsToClipboard` (new utility)

**File:** `shavtzak/lib/core/debug/debug_clipboard_share.dart`

**Signature:**

```dart
Future<void> copyDebugLogsToClipboard(
  BuildContext context, {
  required String currentRouteForShare,
  required String? userDisplay,
  required bool isAdmin,
  required String env,
});
```

**Behaviour:**

1. Snapshot `DebugLogger.instance.events` to `events`.
2. Format via `formatBuffer(events: events, ...)`.
3. Try `Clipboard.setData(ClipboardData(text: formatted))`.
4. On failure: log `Logger.warning('clipboardFailed', {'error': ...runtimeType})`, show `SnackBar(content: Text('שגיאה בהעתקה ללוח'))` if mounted, return.
5. On success: record `Logger.action('debugShareLogsCopied', {'bytes': ..., 'eventCount': events.length})`, show `SnackBar(content: Text('הלוג הועתק ללוח (${events.length} אירועים)'))` if mounted.

This is the same logic as the existing `DebugLogShareFab._copyLogs`, extracted verbatim — only the call sites change.

### 6.2 `DebugTabMenu` helper (optional internal struct)

The state and rendering logic in each bottom-nav widget is similar enough that it could be extracted into a mixin or helper class. **For v1 we do NOT extract** — the bottom nav widgets are likely to have differences (admin shell uses `goBranch`, user shell may use `go` or a different mechanism), and an early abstraction would obscure those differences. Each widget gets its own copy of the four pieces (state field, handler, rendering, dismiss). If a third bottom nav appears later, abstract then.

### 6.3 `SwipeablePageView` changes

**File:** `shavtzak/lib/presentation/widgets/swipeable_page_view.dart`

- Add `int? _longPressedTabIndex` and `Timer? _autoDismiss` fields to the State class.
- Add `_handleLongPress(LongPressStartDetails details)` method.
- Add `_copyAndDismiss()` method that calls the shared utility, then sets `_longPressedTabIndex = null`.
- Modify the `bottomNavigationBar` slot to return a `Stack(clipBehavior: Clip.none)` containing:
  - `GestureDetector(onLongPressStart: _handleLongPress, child: BottomNavigationBar(...))` (existing nav).
  - Conditional `Positioned` mini-FAB when `_longPressedTabIndex != null`.
- Wire `_copyAndDismiss` to pass the current route, user, env to `copyDebugLogsToClipboard`. The current route is derivable from `widget.navigationShell.currentIndex` and the existing `routeNames` const list (already added in Task 7).
- Cancel `_autoDismiss` in `dispose()`.

The existing `_onBottomNavTapped` logic (including `DebugLogger.reset` per Task 7) is unchanged.

### 6.4 `UserNavigationShell` changes

**File:** `shavtzak/lib/presentation/screens/user/user_navigation_shell.dart` (read first to confirm structure)

Same pattern as `SwipeablePageView`:

- Add the two state fields (`_longPressedTabIndex`, `_autoDismiss`).
- Add the long-press handler and the copy-and-dismiss method.
- Wrap the existing bottom navigation with the `Stack` + `GestureDetector` pattern.
- Map the 2 tab indices to route names (`/user/assignments`, `/user/constraints`) for the `currentRouteForShare` parameter.

If `UserNavigationShell` does not currently call `DebugLogger.reset` on tab change (Task 7 only wired the admin's `SwipeablePageView`), add that call now (small spec gap fix from the original Task 7 review).

### 6.5 Admin list screens (Task 9 revert)

For each of:
- `shavtzak/lib/presentation/screens/team/team_list_screen.dart`
- `shavtzak/lib/presentation/screens/event/event_list_screen.dart`
- `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`

Replace the current pattern:

```dart
floatingActionButton: _buildFab(context),
```

with the original (Task 9-pre) pattern, **but keep the explicit `heroTag`**:

```dart
floatingActionButton: FloatingActionButton(
  heroTag: 'team-list-fab',          // keep — explicit tag is hygiene
  onPressed: () => _showTeamMemberFormModal(null),
  child: const Icon(Icons.add),
),
```

Remove the `_buildFab` method body. Remove unused imports.

### 6.6 Deletions

Files removed entirely:

- `shavtzak/lib/presentation/widgets/debug_log_share_fab.dart`
- `shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart`

## 7. Tests

### 7.1 Existing tests removed

- `debug_log_share_fab_test.dart` — deleted along with the widget.

### 7.2 New tests

For each of the two bottom-nav widgets, add widget tests covering:

1. **Tap on a tab still navigates** — no regression; the long-press handler does not consume tap events.
2. **Long-press a tab reveals the mini-FAB above that tab** — verify by `find.byIcon(Icons.bug_report)`, and (optionally) by inspecting the mini-FAB's rendered position via `tester.getCenter(...)` and asserting it falls within the tab's horizontal range.
3. **Mini-FAB tap copies logs + snackbar appears** — same pattern as the existing `DebugLogShareFab` test (using `TestDefaultBinaryMessengerBinding.setMockMethodCallHandler` to intercept clipboard).
4. **Mini-FAB auto-dismisses after 4 seconds** — `tester.pump(Duration(seconds: 5))`.
5. **Second long-press on the SAME tab dismisses the mini-FAB** — toggle-off.
6. **Long-press a DIFFERENT tab while the mini-FAB is visible re-positions it** — assert the mini-FAB is now within the new tab's horizontal range.

Tests can use a fixture `Scaffold(bottomNavigationBar: <widget under test>)` so the widget under test is exercised in isolation, without needing a full router stack. The shared `copyDebugLogsToClipboard` utility can also get its own unit test (calls clipboard, calls `Logger.action`, shows snackbar on `mounted` context).

### 7.3 Existing tests preserved unchanged

All 57 other tests stay as-is. They cover the layers below the trigger UI (logger, formatter, observers, decorator), which are not affected by this change.

## 8. Privacy / Behaviour Invariants

- **Buffer content unchanged.** Same `Logger.action` call sites, same BLoC observer, same DB decorator, same route observer, same `_emitOrLog` in `AssignmentBloc`.
- **Privacy redactions unchanged.** All existing PII redactions (passcode length, error messages, etc.) stay.
- **No new persistence.** Clipboard write remains the only output channel; no Firestore upload, no file write.
- **Buffer reset on navigation unchanged.** Long-pressing tab B while on tab A does NOT navigate (long-press doesn't trigger nav), so the buffer is NOT reset by the long-press itself.

## 9. Edge Cases & Error Handling

- **Long-press lands at the very edge of the screen** — `clamp(0, _tabCount - 1)` ensures the computed tab index is always valid even if `localPosition.dx == screenWidth`.
- **Screen rotation while mini-FAB is visible** — the `Positioned`'s `left` is computed inside `build`, so it re-flows on rotation; the mini-FAB stays approximately above the correct tab. Acceptable for v1; not worth a `LayoutBuilder` rewrite.
- **Bottom nav with a different number of tabs at runtime** (e.g. admin's checklist tab visibility depends on a config) — `_tabCount` is read at handler invocation, so the math adapts. If the tabs change DURING a long-press (impossible in practice), the result is harmless misalignment for one frame.
- **Clipboard write fails on web** — handled by the shared utility's `try/catch` (preserves the Task 8 fix-5 behaviour).
- **`mounted` checks** — the shared utility checks `if (!context.mounted) return;` before showing snackbars, same as the existing widget.
- **Two long-press menus open simultaneously** — impossible; each bottom-nav widget has its own state and the two widgets are never visible together (admin shell vs. user shell are different routes).

## 10. Implementation Order (suggested for the implementation plan)

Each item is independently mergeable.

1. Extract `copyDebugLogsToClipboard` utility + unit test.
2. Modify `SwipeablePageView`: long-press handler + Stack-wrapped bottom nav + mini-FAB.
3. Widget tests for `SwipeablePageView`'s new menu (long-press, tap, auto-dismiss, toggle, re-position).
4. Modify `UserNavigationShell`: same pattern; also add `DebugLogger.reset` on tab change if missing.
5. Widget tests for `UserNavigationShell`'s new menu.
6. Revert FAB wrapping on the 3 admin list screens (`team_list_screen.dart`, `event_list_screen.dart`, `assignment_list_screen.dart`) — keep explicit `heroTag`s.
7. Delete `debug_log_share_fab.dart` + its test file. Confirm no remaining imports reference them.
8. `flutter analyze` + `flutter test`. Expected: 108 issues, full suite passes minus the 5 deleted `debug_log_share_fab_test` tests (so 52 + new bottom-nav tests).

## 11. Out of Scope (for this change)

- All banked follow-ups from the original feature implementation (e.g. `_emitOrLog` `stateType` in context, `BlocBuilder` instead of `context.read`, double-disposal guard). They live or die independently.

## 12. Open Questions

None tracked. (Anything that comes up during planning lands in the implementation plan, not this design.)
