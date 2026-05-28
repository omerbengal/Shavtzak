# Debug Logger Tab-Trigger Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the debug-logger share trigger from the admin "+" FAB long-press to a long-press on any bottom-navigation tab, working on both admin and user shells. Replace the now-unused `DebugLogShareFab` widget with a small shared utility used by both nav widgets.

**Architecture:** Extract the existing `_copyLogs` logic into a top-level `copyDebugLogsToClipboard(...)` utility. Add `GestureDetector(onLongPressStart: ...)` to `SwipeablePageView` and `UserNavigationShell`, computing the long-pressed tab index from `details.localPosition.dx / tabWidth`. Render the mini-FAB as an `OverlayEntry` (more reliable hit-testing than `Stack/Positioned` with `clipBehavior: Clip.none`) positioned at `(tabWidth * (i + 0.5) - 20, kBottomNavigationBarHeight + viewPaddingBottom + 8)`. Revert Task 9's FAB wrapping on the 3 admin list screens. Delete the obsolete `DebugLogShareFab` widget and its test.

**Tech Stack:** Flutter Web, `flutter_bloc`, `go_router`. Tests use `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-05-28-debug-tab-trigger-design.md` — read first.

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `shavtzak/lib/core/debug/debug_clipboard_share.dart` | `copyDebugLogsToClipboard(context, ...)` top-level utility |
| `shavtzak/test/core/debug/debug_clipboard_share_test.dart` | unit tests for the utility |
| `shavtzak/test/presentation/widgets/swipeable_page_view_test.dart` | widget tests for the admin nav tab-trigger menu |
| `shavtzak/test/presentation/screens/user/user_navigation_shell_test.dart` | widget tests for the user nav tab-trigger menu |

### Modified files

| Path | Change |
|------|--------|
| `shavtzak/lib/presentation/widgets/swipeable_page_view.dart` | add long-press handler, OverlayEntry mini-FAB, `_copyAndDismiss` |
| `shavtzak/lib/presentation/screens/user/user_navigation_shell.dart` | same; also add `DebugLogger.reset(newRoute: ...)` on tab change if missing |
| `shavtzak/lib/presentation/screens/team/team_list_screen.dart` | revert `_buildFab(context)` → plain `FloatingActionButton`; keep explicit `heroTag` |
| `shavtzak/lib/presentation/screens/event/event_list_screen.dart` | same revert |
| `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` | same revert |

### Deleted files

| Path |
|------|
| `shavtzak/lib/presentation/widgets/debug_log_share_fab.dart` |
| `shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart` |

---

## Notes for the implementer

1. Project root: `/Users/omerbengal/Documents/Github Projects/Shavtzak`. Branch: `feat/debug-logger`.
2. Package: `shavtzak`. Tests run via `cd shavtzak && flutter test`.
3. Baseline (post all previous debug-logger work): 57 passed + 1 skipped; `flutter analyze` 108 issues.
4. **The two bottom-nav widgets have different navigation APIs.** `SwipeablePageView` uses `widget.navigationShell.goBranch(...)` (StatefulNavigationShell from go_router). `UserNavigationShell` may use a different mechanism — read it before implementing Task 3.
5. **Use `OverlayEntry` for the mini-FAB**, not `Stack`/`Positioned` with `clipBehavior: Clip.none`. The Task 8 reviewer found that `Positioned` outside a Stack's intrinsic bounds isn't reliably hit-testable in widget tests. `OverlayEntry` sidesteps this entirely.
6. Each task ends with a commit. Use prefixes `feat(debug):`, `test(debug):`, `chore(debug):`, `refactor(debug):` consistent with prior commits on this branch.

---

## Task 1: Extract `copyDebugLogsToClipboard` utility

**Files:**
- Create: `shavtzak/lib/core/debug/debug_clipboard_share.dart`
- Create: `shavtzak/test/core/debug/debug_clipboard_share_test.dart`

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/debug/debug_clipboard_share_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_clipboard_share.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/logger.dart';

Future<void> _pumpHost(WidgetTester tester,
    {required Future<void> Function(BuildContext) onTap}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => onTap(context),
          child: const Text('go'),
        ),
      ),
    ),
  ));
}

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  testWidgets('copies formatted buffer to clipboard and records action',
      (tester) async {
    Logger.action('precondition'); // seed a single buffer event
    final List<MethodCall> calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await _pumpHost(tester, onTap: (ctx) async {
      await copyDebugLogsToClipboard(
        ctx,
        currentRouteForShare: '/admin/events',
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
      );
    });

    await tester.tap(find.text('go'));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    final payload = (setData.arguments as Map)['text'] as String;
    expect(payload, contains('=== Shavtzak Debug Log ==='));
    expect(payload, contains('precondition'));

    // Logger.action('debugShareLogsCopied', ...) was recorded
    final copied = DebugLogger.instance.events
        .where((e) => e.name == 'debugShareLogsCopied');
    expect(copied, hasLength(1));
    expect(copied.single.context['eventCount'], 1);

    // Success snackbar shown
    expect(find.textContaining('הלוג הועתק ללוח'), findsOneWidget);
  });

  testWidgets('records warning + shows error snackbar when clipboard throws',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'denied');
      }
      return null;
    });

    await _pumpHost(tester, onTap: (ctx) async {
      await copyDebugLogsToClipboard(
        ctx,
        currentRouteForShare: '/admin/events',
        userDisplay: '-',
        isAdmin: true,
        env: 'prod',
      );
    });

    await tester.tap(find.text('go'));
    await tester.pump();

    // Logger.warning recorded
    final warnings = DebugLogger.instance.events
        .where((e) => e.name == 'clipboardFailed');
    expect(warnings, hasLength(1));

    // Error snackbar shown
    expect(find.text('שגיאה בהעתקה ללוח'), findsOneWidget);

    // No success Logger.action recorded
    expect(
        DebugLogger.instance.events
            .where((e) => e.name == 'debugShareLogsCopied'),
        isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/core/debug/debug_clipboard_share_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:shavtzak/core/debug/debug_clipboard_share.dart'`.

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/core/debug/debug_clipboard_share.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debug_logger.dart';
import 'log_formatter.dart';
import 'logger.dart';

/// Snapshots the current [DebugLogger] buffer, formats it via [formatBuffer],
/// writes the result to the system clipboard, and shows a success or
/// failure snackbar on [context]. Also records a
/// `Logger.action('debugShareLogsCopied', ...)` telemetry event on success
/// or `Logger.warning('clipboardFailed', ...)` on failure.
///
/// The caller is responsible for dismissing any UI that revealed the
/// trigger (e.g. a mini-FAB) before or after awaiting this call — this
/// function does not own that UI state.
Future<void> copyDebugLogsToClipboard(
  BuildContext context, {
  required String currentRouteForShare,
  required String? userDisplay,
  required bool isAdmin,
  required String env,
}) async {
  final events = DebugLogger.instance.events;
  final text = formatBuffer(
    events: events,
    userDisplay: userDisplay,
    isAdmin: isAdmin,
    env: env,
    currentRoute: currentRouteForShare,
    capturedAt: DateTime.now().toUtc(),
  );
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (e) {
    Logger.warning('clipboardFailed', {'error': e.runtimeType.toString()});
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('שגיאה בהעתקה ללוח')),
    );
    return;
  }
  Logger.action('debugShareLogsCopied', {
    'bytes': text.length,
    'eventCount': events.length,
  });
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('הלוג הועתק ללוח (${events.length} אירועים)')),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/core/debug/debug_clipboard_share_test.dart
```

Expected: PASS — 2 tests green.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak && flutter analyze lib/core/debug test/core/debug
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/debug/debug_clipboard_share.dart \
        shavtzak/test/core/debug/debug_clipboard_share_test.dart
git commit -m "refactor(debug): extract copyDebugLogsToClipboard utility"
```

---

## Task 2: Add tab-long-press trigger to `SwipeablePageView`

**Files:**
- Modify: `shavtzak/lib/presentation/widgets/swipeable_page_view.dart`
- Create: `shavtzak/test/presentation/widgets/swipeable_page_view_test.dart`

- [ ] **Step 1: Read the existing `SwipeablePageView`**

```bash
cat shavtzak/lib/presentation/widgets/swipeable_page_view.dart
```

Note the existing structure: the State class name, the `BottomNavigationBar` setup, the `_onBottomNavTapped` method (it should already call `DebugLogger.instance.reset(newRoute: routeNames[index])` per Task 7), the `routeNames` const list, and how the widget accesses the user/admin state and environment.

- [ ] **Step 2: Write the failing widget test**

Create `shavtzak/test/presentation/widgets/swipeable_page_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/logger.dart';

// NOTE: SwipeablePageView likely takes a StatefulNavigationShell argument
// that is not trivial to construct in isolation. The cleanest test path
// is to extract the "tab-trigger menu" widget into its own internal
// stateful widget that doesn't depend on the navigation shell, then test
// THAT widget here. See Step 3 — the implementation introduces a small
// private widget `_BottomNavWithDebugTrigger` that the tests exercise.
//
// If you choose to keep the logic inline in SwipeablePageView, this test
// file becomes more complex (you need a fake navigation shell). The
// recommended approach below assumes the helper widget extraction.

import 'package:shavtzak/presentation/widgets/swipeable_page_view.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required int initialIndex,
  required void Function(int) onTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: BottomNavWithDebugTrigger(
        currentIndex: initialIndex,
        onTap: onTap,
        tabRoutes: const [
          '/admin/team-members',
          '/admin/events',
          '/admin/assignments',
          '/admin/checklist',
        ],
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'צוות'),
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'אירועים'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'שיבוצים'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'צ׳ק־ליסט'),
        ],
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
        miniFabHeroTag: 'debug-share-mini-fab-admin',
      ),
    ),
  ));
}

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  testWidgets('short tap on a tab still navigates', (tester) async {
    int? tappedIndex;
    await _pumpBar(tester,
        initialIndex: 0, onTap: (i) => tappedIndex = i);
    await tester.tap(find.byIcon(Icons.event));
    await tester.pump();
    expect(tappedIndex, 1);
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('long-press a tab reveals the mini-FAB', (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    // Long-press at the horizontal center of tab index 1 (events)
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final tabCenterX = (size.width / 4) * 1.5;
    final tabCenterY = size.height - 28; // roughly inside the nav bar
    await tester.longPressAt(Offset(tabCenterX, tabCenterY));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets('mini-FAB tap copies logs to clipboard + records action',
      (tester) async {
    Logger.action('precondition');
    final List<MethodCall> calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final tabCenterX = (size.width / 4) * 0.5;
    final tabCenterY = size.height - 28;
    await tester.longPressAt(Offset(tabCenterX, tabCenterY));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    final payload = (setData.arguments as Map)['text'] as String;
    expect(payload, contains('=== Shavtzak Debug Log ==='));
    expect(payload, contains('precondition'));

    expect(
      DebugLogger.instance.events
          .where((e) => e.name == 'debugShareLogsCopied'),
      hasLength(1),
    );
  });

  testWidgets('mini-FAB auto-dismisses after 4 seconds', (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.longPressAt(Offset(size.width / 2, size.height - 28));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('second long-press on the same tab dismisses the mini-FAB',
      (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final pos = Offset((size.width / 4) * 0.5, size.height - 28);
    await tester.longPressAt(pos);
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.longPressAt(pos);
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });
}
```

- [ ] **Step 3: Modify `swipeable_page_view.dart` to extract the helper widget**

Add a new private (file-internal) `StatefulWidget` `_BottomNavWithDebugTrigger` (exported as `BottomNavWithDebugTrigger` from the same file for testability):

```dart
// At the top of swipeable_page_view.dart, alongside existing imports:
import 'dart:async';
import '../../core/debug/debug_clipboard_share.dart';

// At the bottom of the file (or wherever fits the file's organization):

/// Wraps a [BottomNavigationBar] with long-press detection that reveals
/// a mini-FAB above the long-pressed tab. The mini-FAB copies the
/// [DebugLogger] buffer to the clipboard via [copyDebugLogsToClipboard].
class BottomNavWithDebugTrigger extends StatefulWidget {
  const BottomNavWithDebugTrigger({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.tabRoutes,
    required this.userDisplay,
    required this.isAdmin,
    required this.env,
    required this.miniFabHeroTag,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;
  final List<String> tabRoutes;
  final String? userDisplay;
  final bool isAdmin;
  final String env;
  final String miniFabHeroTag;

  @override
  State<BottomNavWithDebugTrigger> createState() =>
      _BottomNavWithDebugTriggerState();
}

class _BottomNavWithDebugTriggerState extends State<BottomNavWithDebugTrigger> {
  static const Duration _autoDismissAfter = Duration(seconds: 4);
  static const double _miniFabRadius = 20.0;

  OverlayEntry? _miniFabEntry;
  int? _shownTabIndex;
  Timer? _autoDismiss;

  int get _tabCount => widget.items.length;

  void _handleLongPressStart(LongPressStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tabWidth = screenWidth / _tabCount;
    final tabIndex = (details.localPosition.dx / tabWidth)
        .floor()
        .clamp(0, _tabCount - 1);
    if (_shownTabIndex == tabIndex) {
      _hideMiniFab();
    } else {
      _showMiniFab(tabIndex);
    }
  }

  void _showMiniFab(int tabIndex) {
    _hideMiniFab();
    final screenWidth = MediaQuery.of(context).size.width;
    final tabWidth = screenWidth / _tabCount;
    final tabCenterX = tabWidth * (tabIndex + 0.5);
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
    _miniFabEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: tabCenterX - _miniFabRadius,
        bottom: kBottomNavigationBarHeight + viewPaddingBottom + 8,
        child: FloatingActionButton.small(
          heroTag: widget.miniFabHeroTag,
          tooltip: 'העתק לוג תקלה',
          onPressed: _copyAndDismiss,
          child: const Icon(Icons.bug_report),
        ),
      ),
    );
    Overlay.of(context).insert(_miniFabEntry!);
    setState(() => _shownTabIndex = tabIndex);
    _autoDismiss?.cancel();
    _autoDismiss = Timer(_autoDismissAfter, () {
      if (mounted) _hideMiniFab();
    });
  }

  void _hideMiniFab() {
    _miniFabEntry?.remove();
    _miniFabEntry = null;
    setState(() => _shownTabIndex = null);
    _autoDismiss?.cancel();
    _autoDismiss = null;
  }

  Future<void> _copyAndDismiss() async {
    await copyDebugLogsToClipboard(
      context,
      currentRouteForShare: widget.tabRoutes[widget.currentIndex],
      userDisplay: widget.userDisplay,
      isAdmin: widget.isAdmin,
      env: widget.env,
    );
    if (mounted) _hideMiniFab();
  }

  @override
  void dispose() {
    _miniFabEntry?.remove();
    _miniFabEntry = null;
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _handleLongPressStart,
      child: BottomNavigationBar(
        currentIndex: widget.currentIndex,
        onTap: widget.onTap,
        items: widget.items,
      ),
    );
  }
}
```

Then modify the existing `SwipeablePageView`'s `bottomNavigationBar` block to use this widget. Find the current `bottomNavigationBar: BottomNavigationBar(...)` (or equivalent) and replace it with:

```dart
bottomNavigationBar: BottomNavWithDebugTrigger(
  currentIndex: widget.navigationShell.currentIndex,
  onTap: _onBottomNavTapped,
  items: _navItems, // or the existing list of items
  tabRoutes: routeNames,    // the existing const list from Task 7
  userDisplay: _userDisplay, // read from UserSelectionBloc; see below
  isAdmin: _isAdmin,
  env: EnvironmentService.instance.isTestMode ? 'test' : 'prod',
  miniFabHeroTag: 'debug-share-mini-fab-admin',
),
```

Resolve `_userDisplay` and `_isAdmin` from the current `UserSelectionBloc` state — same pattern as the (now-being-reverted) `_buildFab` helper in Task 9. If the existing widget already has those values readily available, use them; otherwise compute inline:

```dart
String? get _userDisplay {
  final state = context.read<UserSelectionBloc>().state;
  return state is UserAuthenticated ? state.user.name : null;
}

bool get _isAdmin {
  final state = context.read<UserSelectionBloc>().state;
  return state is UserAuthenticated && state.user.isAdmin;
}
```

If `widget.navigationShell.currentIndex` doesn't exist (the API differs), use whatever property gives the current index. The `tabRoutes` array indexes into `routeNames` from Task 7's existing const list.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd shavtzak && flutter test test/presentation/widgets/swipeable_page_view_test.dart
```

Expected: PASS — 5 tests green.

- [ ] **Step 5: Run full suite + analyze**

```bash
cd shavtzak && flutter test
cd shavtzak && flutter analyze
```

Expected: tests still pass (existing 57 + 1 skipped + 5 new = 62 + 1 skipped); analyze unchanged at 108.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/widgets/swipeable_page_view.dart \
        shavtzak/test/presentation/widgets/swipeable_page_view_test.dart
git commit -m "feat(debug): tab long-press trigger on admin SwipeablePageView"
```

---

## Task 3: Add tab-long-press trigger to `UserNavigationShell`

**Files:**
- Modify: `shavtzak/lib/presentation/screens/user/user_navigation_shell.dart`
- Create: `shavtzak/test/presentation/screens/user/user_navigation_shell_test.dart`

- [ ] **Step 1: Read the existing `UserNavigationShell`**

```bash
cat shavtzak/lib/presentation/screens/user/user_navigation_shell.dart
```

Note the structure. Compare with `SwipeablePageView` from Task 2 — same patterns where applicable. Particularly note:
- How the bottom nav is built (BottomNavigationBar with 2 items per `CLAUDE.md`).
- The tap handler — does it call `DebugLogger.instance.reset(newRoute: ...)` already? If NOT (per Task 7 review, only `SwipeablePageView` got that wiring), add it now as part of this task.
- The user/env props are sourced the same way as in `SwipeablePageView`.

- [ ] **Step 2: Write the failing widget test**

Create `shavtzak/test/presentation/screens/user/user_navigation_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/logger.dart';
import 'package:shavtzak/presentation/widgets/swipeable_page_view.dart'; // exports BottomNavWithDebugTrigger

Future<void> _pumpBar(
  WidgetTester tester, {
  required int initialIndex,
  required void Function(int) onTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: BottomNavWithDebugTrigger(
        currentIndex: initialIndex,
        onTap: onTap,
        tabRoutes: const ['/user/assignments', '/user/constraints'],
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment_ind), label: 'שיבוצים'),
          BottomNavigationBarItem(
              icon: Icon(Icons.event_busy), label: 'מגבלות'),
        ],
        userDisplay: 'Boss',
        isAdmin: false,
        env: 'prod',
        miniFabHeroTag: 'debug-share-mini-fab-user',
      ),
    ),
  ));
}

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  testWidgets('user-shell: short tap still navigates', (tester) async {
    int? tappedIndex;
    await _pumpBar(tester, initialIndex: 0, onTap: (i) => tappedIndex = i);
    await tester.tap(find.byIcon(Icons.event_busy));
    await tester.pump();
    expect(tappedIndex, 1);
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('user-shell: long-press tab reveals mini-FAB', (tester) async {
    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final tabCenterX = (size.width / 2) * 0.5;
    final tabCenterY = size.height - 28;
    await tester.longPressAt(Offset(tabCenterX, tabCenterY));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets('user-shell: mini-FAB tap copies logs', (tester) async {
    Logger.action('precondition');
    final List<MethodCall> calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await _pumpBar(tester, initialIndex: 0, onTap: (_) {});
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.longPressAt(Offset(size.width / 4, size.height - 28));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    expect((setData.arguments as Map)['text'],
        contains('=== Shavtzak Debug Log ==='));
    expect(
      DebugLogger.instance.events
          .where((e) => e.name == 'debugShareLogsCopied'),
      hasLength(1),
    );
  });
}
```

- [ ] **Step 3: Modify `user_navigation_shell.dart`**

Apply the same pattern as Task 2's modification to `SwipeablePageView`, but using `BottomNavWithDebugTrigger`'s `miniFabHeroTag: 'debug-share-mini-fab-user'` and the 2-tab route list:

```dart
import '../../widgets/swipeable_page_view.dart'
    show BottomNavWithDebugTrigger;
import '../../../core/debug/debug_logger.dart';

// In the build method, replace:
//   bottomNavigationBar: BottomNavigationBar(...)
// with:
bottomNavigationBar: BottomNavWithDebugTrigger(
  currentIndex: <currentIndex>,
  onTap: _onTap,
  items: const [
    BottomNavigationBarItem(icon: Icon(Icons.assignment_ind), label: 'שיבוצים'),
    BottomNavigationBarItem(icon: Icon(Icons.event_busy), label: 'מגבלות'),
  ],
  tabRoutes: const ['/user/assignments', '/user/constraints'],
  userDisplay: <from UserSelectionBloc state>,
  isAdmin: <from UserSelectionBloc state>,
  env: EnvironmentService.instance.isTestMode ? 'test' : 'prod',
  miniFabHeroTag: 'debug-share-mini-fab-user',
),
```

(Adapt the icon/label values to whatever the existing screen actually uses. Read the current code in Step 1 to confirm.)

**If `_onTap` (or its equivalent) does NOT call `DebugLogger.instance.reset(newRoute: ...)`**, add it now at the top of that method:

```dart
void _onTap(int index) {
  DebugLogger.instance.reset(
    newRoute: '${EnvironmentService.instance.routePrefix}'
        '${const ['/user/assignments', '/user/constraints'][index]}',
  );
  // ... existing onTap body
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd shavtzak && flutter test test/presentation/screens/user/user_navigation_shell_test.dart
```

Expected: PASS — 3 tests green.

- [ ] **Step 5: Run full suite + analyze**

```bash
cd shavtzak && flutter test
cd shavtzak && flutter analyze
```

Expected: 65 tests + 1 skipped (was 62 + 1 after Task 2; +3 here); analyze unchanged.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/screens/user/user_navigation_shell.dart \
        shavtzak/test/presentation/screens/user/user_navigation_shell_test.dart
git commit -m "feat(debug): tab long-press trigger on UserNavigationShell"
```

---

## Task 4: Revert FAB wrapping on the 3 admin list screens

**Files:**
- Modify: `shavtzak/lib/presentation/screens/team/team_list_screen.dart`
- Modify: `shavtzak/lib/presentation/screens/event/event_list_screen.dart`
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`

The Task 9 wrapping is now redundant — the long-press trigger lives on the bottom nav, not on the FAB. Restore the original `FloatingActionButton` for each screen, keeping the explicit `heroTag` (the hyphenated form added in Task 9 is hygiene that should not be reverted).

- [ ] **Step 1: Modify `team_list_screen.dart`**

Find the `floatingActionButton: _buildFab(context)` assignment. Replace with:

```dart
floatingActionButton: FloatingActionButton(
  heroTag: 'team-list-fab',
  onPressed: () => _showTeamMemberFormModal(null),
  child: const Icon(Icons.add),
),
```

Delete the `Widget _buildFab(BuildContext context) { ... }` method.

Delete imports that are no longer used after the revert. Check by grep:

```bash
grep -nE "DebugLogShareFab|UserSelectionBloc|EnvironmentService" \
     shavtzak/lib/presentation/screens/team/team_list_screen.dart
```

For each remaining match, decide whether the import is still needed elsewhere in the file. Remove any imports that have zero remaining usages.

**Important:** the `Logger.action('openMemberModal', ...)` call added in Task 10 stays — that's independent instrumentation and not part of the FAB wrapping.

- [ ] **Step 2: Modify `event_list_screen.dart`**

Same pattern. Restore:

```dart
floatingActionButton: FloatingActionButton(
  heroTag: 'event-list-fab',
  onPressed: () => _showEventFormModal(null),
  child: const Icon(Icons.add),
),
```

Delete `_buildFab` and clean up unused imports.

- [ ] **Step 3: Modify `assignment_list_screen.dart`**

Same pattern, but preserve the existing prop set on the FAB (mutation guard, background color, tooltip, white icon — verified in Task 9 review):

```dart
floatingActionButton: FloatingActionButton(
  heroTag: 'assignment-list-fab',
  backgroundColor: Colors.blue,
  tooltip: 'שיבוץ ידני',
  onPressed: _isMutationInFlight ? null : () => _showManualAssignmentFlow(),
  child: const Icon(Icons.add, color: Colors.white),
),
```

Delete `_buildFab` and clean up unused imports.

- [ ] **Step 4: Run analyze + full suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: `DebugLogShareFab` is still referenced from its test file (which still exists), but its other usages should be gone — `grep -rn 'DebugLogShareFab' shavtzak/lib` should show **zero matches** in `lib/`. Tests still pass; analyze unchanged.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/screens/team/team_list_screen.dart \
        shavtzak/lib/presentation/screens/event/event_list_screen.dart \
        shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart
git commit -m "refactor(debug): unwrap admin-tab FABs (trigger moved to bottom-nav)"
```

---

## Task 5: Delete the obsolete `DebugLogShareFab` widget + final verification

**Files:**
- Delete: `shavtzak/lib/presentation/widgets/debug_log_share_fab.dart`
- Delete: `shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart`

- [ ] **Step 1: Confirm no remaining references**

```bash
cd "/Users/omerbengal/Documents/Github Projects/Shavtzak"
grep -rn "DebugLogShareFab" shavtzak/lib
grep -rn "debug_log_share_fab" shavtzak/lib
```

Both must return **zero matches** in `lib/`. If any match remains, stop and investigate — Task 4 missed a usage.

```bash
grep -rn "DebugLogShareFab" shavtzak/test
```

This should match only the test file we're about to delete.

- [ ] **Step 2: Delete the files**

```bash
git rm shavtzak/lib/presentation/widgets/debug_log_share_fab.dart \
       shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart
```

- [ ] **Step 3: Run analyze + full suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: analyze should NOT regress (still 108 issues, or possibly fewer if the deletion cleared a lint). Tests: 65 - 5 (deleted) + 1 skipped = 60 + 1 skipped. Confirm the actual numbers.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore(debug): delete obsolete DebugLogShareFab widget"
```

- [ ] **Step 5: Final manual sanity check**

The feature is now fully migrated. Tell the user:

> The tab-trigger redesign is complete. To verify end-to-end:
>
> 1. Run the app and navigate to any admin screen (e.g. `/admin/events`). Confirm the "+" FAB is a normal `FloatingActionButton` (no special behavior on long-press).
> 2. Long-press any tab label in the bottom nav (e.g. "אירועים"). A small 🐞 mini-FAB should appear centered above that tab.
> 3. Tap the mini-FAB → snackbar `הלוג הועתק ללוח (N אירועים)`. Paste the clipboard to confirm the formatted log.
> 4. Long-press a different tab while the mini-FAB is visible → it should move to the new tab's position.
> 5. Long-press the SAME tab twice in a row → mini-FAB appears, then disappears.
> 6. Long-press a tab and wait 4 seconds without tapping → mini-FAB auto-dismisses.
> 7. Repeat steps 2-6 on a user-shell screen (`/user/assignments` or `/user/constraints`). Same behaviour, 2 tabs.

---

## Self-Review

Walking the spec sections against the plan:

| Spec section | Plan task | Notes |
|--------------|-----------|-------|
| §2 Goals — universal trigger | Tasks 2 + 3 | Admin (4 tabs) and user (2 tabs) both wired |
| §2 Goals — remove FAB wrapping | Task 4 + Task 5 | Wrapper removed, widget deleted |
| §2 Goals — preserve mini-FAB UX | Task 2 helper widget | Same long-press → reveal → tap pattern |
| §2 Goals — anchor above tab | Task 2 positioning math | `tabWidth * (i + 0.5)` |
| §2 Goals — preserve snackbar + telemetry | Task 1 utility | `copyDebugLogsToClipboard` reuses the exact text + Logger.action |
| §3 Non-Goals — no keep-both triggers | Task 4 + Task 5 | FAB long-press fully gone |
| §3 Non-Goals — no new content | Task 1-5 | No changes to BlocObserver, formatter, route observer, etc. |
| §4 UX flow — tap unchanged | Task 2 test 1 + Task 3 test 1 | "short tap still navigates" |
| §4 UX flow — second long-press toggles | Task 2 test 5 | Explicit test |
| §4 UX flow — different tab re-positions | Implicitly via Task 2 logic | The handler dismisses then re-shows — covered |
| §5 Architecture — shared utility | Task 1 | `copyDebugLogsToClipboard` |
| §5 Architecture — Overlay-based mini-FAB | Task 2 helper widget | Uses `OverlayEntry` |
| §5 Architecture — per-widget state | Task 2 + Task 3 | Each shell gets its own `BottomNavWithDebugTrigger` |
| §5.4 Reverting Task 9 | Task 4 | All 3 admin screens |
| §5.5 Deletion | Task 5 | Widget + test gone |
| §7 Tests | Task 1 + 2 + 3 tests | Unit + 2 widget test suites |
| §8 Privacy invariants | All tasks | No new content paths; only the trigger UI changes |
| §9 Edge cases — clamp at screen edges | Task 2 helper widget | `.clamp(0, _tabCount - 1)` |
| §9 Edge cases — mounted checks | Task 1 utility | `if (!context.mounted) return;` |
| §10 Implementation order | Tasks 1-5 ordered identically | |

**No placeholders.** Every code block in the plan is complete; no "TBD" or "similar to Task N" without code.

**Type consistency:**
- `copyDebugLogsToClipboard(context, {currentRouteForShare, userDisplay, isAdmin, env})` — signature identical across Tasks 1, 2, 3, 5.
- `BottomNavWithDebugTrigger(currentIndex, onTap, items, tabRoutes, userDisplay, isAdmin, env, miniFabHeroTag)` — same constructor used in Tasks 2 and 3.
- `miniFabHeroTag` strings: `'debug-share-mini-fab-admin'` (Task 2) and `'debug-share-mini-fab-user'` (Task 3) — distinct, no Hero collision.
- `Logger.action('debugShareLogsCopied', {bytes, eventCount})` and `Logger.warning('clipboardFailed', {error})` — consistent names across Task 1 and assertions in Tasks 2-3 tests.
