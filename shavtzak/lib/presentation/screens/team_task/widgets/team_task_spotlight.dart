import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../core/utils/team_task_spotlight.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import 'team_task_actions.dart';
import 'team_task_style.dart';

/// "בליץ" (Spotlight, Omer 16/11/2026): a quick pass over the viewer's tasks
/// in "המשימות שלי", one card at a time, the quietest first
/// ([spotlightQueue]). Each card shows where the task belongs, how long it
/// has been quiet and its whole update log, with four big actions: a short
/// update, "סיימתי", "לא עכשיו" and another status. ✕ leaves at any moment;
/// after the last card a summary closes the pass.
///
/// Round 2 (Omer, 16/11/2026): everything centred and bigger, and animated -
/// the next card fades in, "לא עכשיו" bounces the card off to the side,
/// "סיימתי" throws confetti, a sent update lands in the log before the card
/// moves on, and the summary counts up (with confetti when nothing was left
/// for later).
///
/// Opens over the screen with [taskIds] in order ([title] = what the pass
/// covers, e.g. a topic). Returns the ids it changed (closed or updated) so
/// the list can flash them on the way back.
Future<Set<String>> showTeamTaskSpotlight(
  BuildContext context, {
  required List<String> taskIds,
  String? title,
  DateTime Function()? clock,
}) async {
  final bloc = context.read<TeamTaskBloc>();
  final touched = await Navigator.of(context).push<Set<String>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: TeamTaskSpotlight(taskIds: taskIds, title: title, clock: clock),
      ),
    ),
  );
  return touched ?? const {};
}

/// Every emoji the screen shows (the chips and the summary), laid out
/// offstage on open so the web's emoji font is fetched before it is needed.
const String _emojiWarmup = '👍⏳🧱🏁🎉👏';

/// The short updates one tap away (the "עדכון קצר" chips of the design).
const List<String> spotlightQuickUpdates = [
  'התקדמתי 👍',
  'מחכה למישהו ⏳',
  'תקוע 🧱',
  'כמעט גמור 🏁',
];

/// Sizes and timings of the Spotlight screen (round 2: "זה קטן").
abstract final class SpotlightStyle {
  /// The card column's width on a wide window.
  static const double maxWidth = 760;

  /// From this width the screen grows a little more ([scale]).
  static const double wideFrom = 720;
  static const double wideScale = 1.2;

  static const double titleSize = 24;
  static const double metaSize = 15;
  static const double bodySize = 16;
  static const double buttonHeight = 60;
  static const double buttonFont = 17;
  static const double buttonIcon = 24;
  static const double radius = 22;

  /// The update log's height: this share of the room, between the bounds.
  static const double logShare = 0.3;
  static const double logMin = 130;
  static const double logMax = 340;

  static const Duration enter = Duration(milliseconds: 300);

  /// The card's updates come in one after the other (Omer, msg 3913):
  /// [logStepMs] apart, each over [logEntryMs], at most [logMaxSteps] steps,
  /// so the whole effect stays under half a second however long the log.
  static const int logStepMs = 50;
  static const int logEntryMs = 250;
  static const int logMaxSteps = 4;
  static const Duration logIn = Duration(milliseconds: logStepMs * logMaxSteps + logEntryMs);
  /// "לא עכשיו": a wind-up to the right over the first [skipWindUp] of the
  /// time (by [skipWindUpOffset] of the card's width), then the fling left.
  /// Omer, msg 4024: the wind-up further right and a little longer.
  static const Duration fling = Duration(milliseconds: 640);
  static const double skipWindUp = 0.28;
  static const double skipWindUpOffset = 0.14;
  static const Duration done = Duration(milliseconds: 520);

  /// A sent update flies from the text field up to its place at the top of
  /// the log (Omer, msg 3969: "ממש יגיע משורת הטקסט למטה - ישר למעלה").
  static const Duration flight = Duration(milliseconds: 520);

  /// After it lands: it glows a moment, then the card goes.
  static const Duration update = Duration(milliseconds: 760);
  static const double updateHold = 0.35;

  /// Room around the card for its shadow (blur 28, 12 down), so the
  /// picture of the card taken for its way out holds the whole shadow.
  static const EdgeInsets cardShadowRoom = EdgeInsets.fromLTRB(52, 40, 52, 64);

  static const Duration confetti = Duration(milliseconds: 1600);
  static const Duration progress = Duration(milliseconds: 500);
}

/// How the current card leaves.
enum _Exit { none, skip, done, update }

class TeamTaskSpotlight extends StatefulWidget {
  const TeamTaskSpotlight({super.key, required this.taskIds, this.title, this.clock});

  final List<String> taskIds;
  final String? title;
  final DateTime Function()? clock;

  @override
  State<TeamTaskSpotlight> createState() => _TeamTaskSpotlightState();
}

class _TeamTaskSpotlightState extends State<TeamTaskSpotlight> with TickerProviderStateMixin {
  int _index = 0;
  SpotlightTally _tally = const SpotlightTally();

  /// The short update field is open on the current card.
  bool _composing = false;

  /// An action of the current card is on its way to the backend.
  bool _busy = false;

  /// The current card's way out, while [_exit] runs.
  _Exit _exitKind = _Exit.none;

  /// The update just sent, shown in the log until the stream brings it.
  String? _echo;

  /// The sent update in flight: where it took off (the field, global) and
  /// its text. Null when nothing flies.
  Rect? _flightFrom;
  String _flightText = '';

  /// The sent update reached its place in the log (its row shows from here).
  bool _landed = false;

  final GlobalKey _bodyKey = GlobalKey();
  final GlobalKey _fieldKey = GlobalKey();
  final GlobalKey _landingKey = GlobalKey();
  final ScrollController _logScroll = ScrollController();

  /// While "לא עכשיו" / "סיימתי" throw the card away it is painted from one
  /// picture of it ([SnapshotWidget]): a turned or shrinking card with its
  /// blurred shadow is costly to redraw on every frame, enough to halve the
  /// frame rate in a browser tab (Omer, msg 3998 / 4001: only the installed
  /// app was smooth). The picture is the same pixels, so it looks the same.
  final SnapshotController _cardPicture = SnapshotController();

  /// The update ids the current card opened with: any other one is new and
  /// lands with the "sent" animation.
  Set<String> _seenUpdates = const {};
  String? _seenFor;

  late final AnimationController _enter =
      AnimationController(vsync: this, duration: SpotlightStyle.enter);
  late final AnimationController _exit = AnimationController(vsync: this);
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: SpotlightStyle.confetti);
  late final AnimationController _logIn =
      AnimationController(vsync: this, duration: SpotlightStyle.logIn);
  late final AnimationController _flight =
      AnimationController(vsync: this, duration: SpotlightStyle.flight);
  late final Listenable _motion = Listenable.merge([_enter, _exit, _flight]);
  List<_ConfettiPiece> _pieces = const [];
  final math.Random _random = math.Random();

  final TextEditingController _update = TextEditingController();
  final FocusNode _updateFocus = FocusNode();

  int get _total => widget.taskIds.length;
  bool get _finished => _index >= _total;
  bool get _leaving => _exitKind != _Exit.none;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _enter.forward();
    _logIn.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    _logIn.dispose();
    _exit.dispose();
    _flight.dispose();
    _logScroll.dispose();
    _cardPicture.dispose();
    _confetti.dispose();
    _update.dispose();
    _updateFocus.dispose();
    super.dispose();
  }

  void _leave() {
    Logger.action('tap:spotlightClose', {'at': _index, 'of': _total});
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    Navigator.of(context).pop(_tally.touched);
  }

  /// The next card fades in (or the summary, after the last one).
  void _next() {
    setState(() {
      _index++;
      _composing = false;
      _echo = null;
      _flightFrom = null;
      _landed = false;
      _exitKind = _Exit.none;
      _update.clear();
    });
    _cardPicture.allowSnapshotting = false;
    _exit.value = 0;
    _flight.value = 0;
    _enter.forward(from: 0);
    _logIn.forward(from: 0);
    if (_finished && _tally.skipped.isEmpty && _total > 0) _celebrate();
  }

  /// Plays [kind]'s way out, then moves on.
  Future<void> _leaveCard(_Exit kind) async {
    setState(() => _exitKind = kind);
    // Not for a sent update: its row still glows inside the card.
    _cardPicture.allowSnapshotting = kind == _Exit.skip || kind == _Exit.done;
    _exit.duration = switch (kind) {
      _Exit.skip => SpotlightStyle.fling,
      _Exit.done => SpotlightStyle.done,
      _Exit.update => SpotlightStyle.update,
      _Exit.none => Duration.zero,
    };
    await _exit.forward(from: 0).orCancel.catchError((_) {});
    if (mounted && _exitKind == kind) _next();
  }

  void _celebrate() {
    final colors = [
      TaskStyle.done,
      TaskStyle.mine,
      TaskStyle.soon,
      TaskStyle.late,
      Colors.amber,
      const Color(0xFFEC407A),
      const Color(0xFF8E24AA),
      const Color(0xFF26C6DA),
    ];
    setState(() {
      _pieces = [
        for (var i = 0; i < 70; i++)
          _ConfettiPiece(
            // Upwards, fanned out: -165° .. -15°.
            angle: -math.pi * (0.08 + 0.84 * _random.nextDouble()),
            speed: 520 + 640 * _random.nextDouble(),
            color: colors[i % colors.length],
            size: 6 + 5 * _random.nextDouble(),
            spin: (_random.nextDouble() - 0.5) * 18,
            round: _random.nextDouble() < 0.3,
            drift: (_random.nextDouble() - 0.5) * 120,
          ),
      ];
    });
    _confetti.forward(from: 0);
  }

  void _skip(String id) {
    if (_leaving) return;
    Logger.action('tap:spotlightSkip');
    HapticFeedback.selectionClick();
    setState(() => _tally = _tally.skip(id));
    _leaveCard(_Exit.skip);
  }

  void _openComposer() {
    Logger.action('tap:spotlightCompose');
    HapticFeedback.selectionClick();
    setState(() => _composing = true);
    _updateFocus.requestFocus();
  }

  void _pickQuick(String text) {
    Logger.action('tap:spotlightQuickUpdate', {'text': text});
    HapticFeedback.selectionClick();
    final current = _update.text.trim();
    _update.text = current.isEmpty ? '$text ' : '$text $current';
    _update.selection = TextSelection.collapsed(offset: _update.text.length);
    _updateFocus.requestFocus();
  }

  Future<CrudActionResult> _await(CrudActionCompleter completion) async {
    setState(() => _busy = true);
    final result = await completion.future;
    if (mounted) setState(() => _busy = false);
    return result;
  }

  void _failed(CrudActionResult result) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
    );
  }

  Future<void> _send(TeamTask task) async {
    final text = _update.text.trim();
    if (text.isEmpty || _leaving) return;
    Logger.action('tap:spotlightSend');
    final completion = CrudActionCompleter();
    context.read<TeamTaskBloc>().add(task.isSubtask
        ? AddTeamTaskUpdate(task.parentId!, text, subtaskId: task.id, completion: completion)
        : AddTeamTaskUpdate(task.id, text, completion: completion));
    // Take off right away, from where the field is now, before the keyboard
    // goes. Not after the save: Firestore shows the new update in the log
    // the moment it is written locally, while the save itself waits for the
    // server (long on the first send after the app opens), so waiting made
    // the update just appear on top, with the flight late or never seen
    // (Omer, msg 4004: no flight in the first Blitz).
    final field = _fieldKey.currentContext?.findRenderObject();
    final from = field is RenderBox && field.attached && field.hasSize
        ? field.localToGlobal(Offset.zero) & field.size
        : null;
    _updateFocus.unfocus();
    setState(() {
      _echo = text;
      _update.clear();
      _exitKind = _Exit.update;
      _flightFrom = from;
      _flightText = text;
      _landed = false;
    });
    // Its place is the top of the log: bring the log back there.
    if (_logScroll.hasClients && _logScroll.offset > 0) _logScroll.jumpTo(0);
    // It lands when the flight ends, even while the server still holds the
    // save; the card moves on only once the save is confirmed.
    final flown = (from == null
            ? Future<void>.value()
            : _flight.forward(from: 0).orCancel.catchError((_) {}))
        .then((_) {
      if (!mounted || _exitKind != _Exit.update || _echo != text) return;
      setState(() {
        _landed = true;
        _flightFrom = null;
      });
    });
    final result = await _await(completion);
    if (!mounted) return;
    if (!result.isSuccess) {
      // Back to the field with the text, as if it never left.
      _flight.value = 0;
      setState(() {
        _echo = null;
        _exitKind = _Exit.none;
        _flightFrom = null;
        _landed = false;
        _update.text = text;
      });
      return _failed(result);
    }
    HapticFeedback.lightImpact();
    await flown;
    if (!mounted || _exitKind != _Exit.update) return;
    setState(() => _tally = _tally.update(task.id));
    _leaveCard(_Exit.update);
  }

  Future<bool> _setStatus(TeamTask task, TeamTaskStatus status, {String? original}) async {
    final completion = CrudActionCompleter();
    context.read<TeamTaskBloc>().add(task.isSubtask
        ? SetTeamTaskStatus(task.parentId!, status,
            subtaskId: task.id, duplicateOfId: original, completion: completion)
        : SetTeamTaskStatus(task.id, status, duplicateOfId: original, completion: completion));
    final result = await _await(completion);
    if (!mounted) return false;
    if (!result.isSuccess) _failed(result);
    return result.isSuccess;
  }

  /// "סיימתי" or a status from the menu. Closing it (done, cancelled,
  /// duplicate) moves on with a "ביטול" that puts the old status back and
  /// returns to the card; "פתוחה" / "בטיפול" stays on the card.
  Future<void> _changeStatus(TeamTask task, TeamTaskStatus status) async {
    if (status == task.status || _leaving) return;
    Logger.action('tap:spotlightStatus', {'status': status.key});
    String? original;
    if (status == TeamTaskStatus.duplicate) {
      final state = context.read<TeamTaskBloc>().state;
      if (state is! TeamTasksLoaded) return;
      original = await pickDuplicateOriginal(context, state, task);
      if (original == null || !mounted) return;
    }
    final previous = task.status;
    final at = _index;
    if (!await _setStatus(task, status, original: original) || !mounted) return;
    if (status.isActive) {
      HapticFeedback.selectionClick();
      return;
    }
    setState(() => _tally = _tally.close(task.id));
    if (status == TeamTaskStatus.done) {
      HapticFeedback.mediumImpact();
      _celebrate();
    } else {
      HapticFeedback.lightImpact();
    }
    _leaveCard(_Exit.done);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      key: const Key('spotlight-undo-bar'),
      duration: const Duration(seconds: 4),
      content:
          Text(status == TeamTaskStatus.done ? 'סומנה כבוצעה' : 'סומנה כ"${status.hebrewLabel}"'),
      action: SnackBarAction(
        key: const Key('spotlight-undo'),
        label: 'ביטול',
        onPressed: () async {
          Logger.action('tap:spotlightUndo');
          if (!mounted) return;
          final current = context.read<TeamTaskBloc>().state;
          final now = current is TeamTasksLoaded ? current.taskById(task.id) : null;
          if (now == null || !await _setStatus(now, previous) || !mounted) return;
          _exit.stop();
          setState(() {
            _tally = _tally.reopen(task.id);
            _index = at;
            _composing = false;
            _echo = null;
            _exitKind = _Exit.none;
          });
          _exit.value = 0;
          _enter.forward(from: 0);
          _logIn.forward(from: 0);
        },
      ),
    ));
  }

  // ---------------------------------------------------------------- build --

  double _scale(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= SpotlightStyle.wideFrom ? SpotlightStyle.wideScale : 1;

  @override
  Widget build(BuildContext context) {
    final label = widget.title == null ? 'בליץ' : 'בליץ · ${widget.title}';
    final s = _scale(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('spotlight-screen'),
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          // The app's own header (blue, white title and icon), as on every
          // other screen: the light bar left the theme's white title unreadable.
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('spotlight-close'),
            tooltip: 'יציאה מהבליץ',
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
          title: Text(label, overflow: TextOverflow.ellipsis),
        ),
        body: Stack(
          key: _bodyKey,
          children: [
            Column(
              children: [
                _progress(s),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      const pad = EdgeInsets.fromLTRB(16, 12, 16, 24);
                      final logHeight = (box.maxHeight * SpotlightStyle.logShare)
                          .clamp(SpotlightStyle.logMin, SpotlightStyle.logMax)
                          .toDouble();
                      return SingleChildScrollView(
                        padding: pad,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: math.max(0, box.maxHeight - pad.vertical)),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: SpotlightStyle.maxWidth),
                              child: _finished ? _summary(s) : _current(s, logHeight),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_flightFrom != null)
              Positioned.fill(child: IgnorePointer(child: _flightLayer(s))),
            Positioned.fill(child: _confettiLayer()),
            // On the web the emoji come from a fallback font downloaded the
            // first time one is laid out: lay them all out, unseen, when the
            // screen opens, so the chips and the summary do not stall on it.
            const Offstage(child: Text(_emojiWarmup)),
          ],
        ),
      ),
    );
  }

  /// The bar on top fills smoothly; the counter rolls to the next number.
  Widget _progress(double s) {
    final value = _total == 0 ? 1.0 : (_index / _total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: SpotlightStyle.maxWidth),
          child: Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: value),
                  duration: SpotlightStyle.progress,
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => LinearProgressIndicator(
                    key: const Key('spotlight-progress'),
                    value: v,
                    minHeight: 10 * s,
                    borderRadius: BorderRadius.circular(999),
                    backgroundColor: TaskStyle.rest,
                    color: TaskStyle.done,
                  ),
                ),
              ),
              if (!_finished) ...[
                SizedBox(width: 12 * s),
                ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween(begin: const Offset(0, 0.8), end: Offset.zero)
                          .chain(CurveTween(curve: Curves.easeOutCubic))
                          .animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Text(
                      '${_index + 1}/$_total',
                      key: const Key('spotlight-counter'),
                      style: TextStyle(
                        fontSize: 17 * s,
                        fontWeight: FontWeight.w800,
                        color: TaskStyle.neutralText,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _confettiLayer() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _confetti,
        builder: (context, _) {
          if (!_confetti.isAnimating || _pieces.isEmpty) return const SizedBox.shrink();
          return RepaintBoundary(
            child: CustomPaint(
              key: const Key('spotlight-confetti'),
              painter: _ConfettiPainter(_pieces, _confetti.value),
              size: Size.infinite,
            ),
          );
        },
      ),
    );
  }

  Widget _current(double s, double logHeight) {
    return BlocBuilder<TeamTaskBloc, TeamTaskState>(
      builder: (context, state) {
        final id = widget.taskIds[_index];
        final task = state is TeamTasksLoaded ? state.taskById(id) : null;
        if (task != null && _seenFor != id) {
          _seenFor = id;
          _seenUpdates = {for (final entry in task.updates) entry.id};
        }
        return KeyedSubtree(
          key: ValueKey('spotlight-$_index-$id'),
          child: task == null ? _gone(id) : _page(task, s, logHeight),
        );
      },
    );
  }

  /// The task left the viewer's list meanwhile (deleted, given to another).
  Widget _gone(String id) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('המשימה הזו כבר לא ברשימה שלך',
              style: TextStyle(fontSize: 16, color: TaskStyle.neutralText)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('spotlight-gone-next'),
            onPressed: () => _skip(id),
            child: const Text('הבאה'),
          ),
        ],
      ),
    );
  }

  Widget _page(TeamTask task, double s, double logHeight) {
    // Their own layers: the card's move / fade / turn only composites the
    // cached picture instead of repainting the card (its blurred shadow, the
    // timeline) on every frame.
    final card = _ShadowRoom(
      room: SpotlightStyle.cardShadowRoom,
      child: SnapshotWidget(
        controller: _cardPicture,
        mode: SnapshotMode.permissive,
        child: Padding(
          padding: SpotlightStyle.cardShadowRoom,
          child: RepaintBoundary(child: _card(task, s, logHeight)),
        ),
      ),
    );
    final lower = RepaintBoundary(child: _composing ? _composer(task, s) : _actions(task, s));
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, _) {
        // In: a plain fade (Omer, msg 3911: no rise / scale on entry).
        final inT = Curves.easeOut.transform(_enter.value);
        final e = _exit.value;
        var dx = 0.0, dy = 0.0, angle = 0.0, scale = 1.0, opacity = inT;
        var lowerOpacity = inT;
        double check = 0;
        switch (_exitKind) {
          case _Exit.skip:
            // A small wind-up to the right, then flung off to the left.
            const w = SpotlightStyle.skipWindUp, o = SpotlightStyle.skipWindUpOffset;
            if (e < w) {
              dx = o * Curves.easeOutCubic.transform(e / w);
            } else {
              dx = o - (1.75 + o) * Curves.easeInCubic.transform((e - w) / (1 - w));
            }
            angle = dx * 0.22;
            opacity *= 1 - const Interval(0.7, 1).transform(e);
            lowerOpacity *= 1 - const Interval(0, 0.35).transform(e);
          case _Exit.done:
            check = Curves.easeOutBack.transform(const Interval(0, 0.45).transform(e));
            final out = Curves.easeInCubic.transform(const Interval(0.35, 1).transform(e));
            dy = -0.18 * out;
            scale *= 1 - 0.18 * out;
            opacity *= 1 - out;
            lowerOpacity *= 1 - const Interval(0, 0.3).transform(e);
          case _Exit.update:
            final out = _landed
                ? Curves.easeInCubic.transform(Interval(SpotlightStyle.updateHold, 1).transform(e))
                : 0.0;
            dy = -0.2 * out;
            opacity *= 1 - out;
            // The field's row fades while the update flies out of it.
            lowerOpacity *= 1 - const Interval(0, 0.35).transform(math.max(_flight.value, e));
          case _Exit.none:
            break;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: FractionalTranslation(
                translation: Offset(dx, dy),
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(
                    scale: scale,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        card,
                        if (check > 0)
                          Transform.scale(
                            scale: check,
                            child: Container(
                              key: const Key('spotlight-done-check'),
                              width: 96 * s,
                              height: 96 * s,
                              decoration: const BoxDecoration(
                                color: TaskStyle.done,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Color(0x552E7D32),
                                      blurRadius: 24,
                                      offset: Offset(0, 8)),
                                ],
                              ),
                              child: Icon(Icons.check_rounded, color: Colors.white, size: 60 * s),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 18 * s),
            Opacity(
              opacity: lowerOpacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, _leaving ? 24 * (1 - lowerOpacity) : 0),
                child: IgnorePointer(ignoring: _leaving, child: lower),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(TeamTask task, double s, double logHeight) {
    final now = _now;
    final quiet = teamTaskQuietDays(task, now);
    final isQuiet = quiet == null || quiet >= spotlightQuietDays;
    final deadline = task.deadlineDate;
    final late = isTeamTaskLate(task, now);
    final owners = teamTaskOwnerChips(task);
    final linkKind = switch (task.link?.type) {
      TaskLinkType.event => 'אירוע · ',
      TaskLinkType.category => 'קטגוריה · ',
      TaskLinkType.topic => 'נושא · ',
      null => '',
    };
    final meta = SpotlightStyle.metaSize * s;
    return Container(
      key: Key('spotlight-card-${task.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TaskStyle.stageCard,
        border: Border.all(color: TaskStyle.stageCardBorder),
        borderRadius: BorderRadius.circular(SpotlightStyle.radius),
        boxShadow: const [
          BoxShadow(color: Color(0x220A1E3C), blurRadius: 28, offset: Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: TaskStyle.stageHeader,
            padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 11 * s),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$linkKind${teamTaskLinkLabel(task)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: meta,
                      fontWeight: FontWeight.w700,
                      color: TaskStyle.neutralText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: Key('spotlight-quiet-${task.id}'),
                  padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
                  decoration: BoxDecoration(
                    color: isQuiet ? TaskStyle.soonLight : TaskStyle.chip,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    teamTaskQuietLabel(task, now),
                    style: TextStyle(
                      fontSize: 13.5 * s,
                      fontWeight: FontWeight.w700,
                      color: isQuiet ? TaskStyle.soonDark : TaskStyle.neutralText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20 * s, 18 * s, 20 * s, 20 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.isSubtask)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      task.parentTitle ?? '',
                      style: TextStyle(fontSize: meta, color: TaskStyle.neutralText),
                    ),
                  ),
                Text(
                  task.title,
                  key: Key('spotlight-title-${task.id}'),
                  style: TextStyle(
                    fontSize: SpotlightStyle.titleSize * s,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 12 * s),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MorphStatusChip(status: task.status, scale: s),
                    if (deadline != null)
                      Text(
                        late ? 'באיחור · עד ${shortDate(deadline)}' : 'עד ${shortDate(deadline)}',
                        style: TextStyle(
                          fontSize: meta,
                          color: late ? TaskStyle.late : TaskStyle.neutralText,
                          fontWeight: late ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    for (final owner in owners)
                      MemberInitialsAvatar(
                        memberId: owner.id,
                        name: owner.name,
                        highlight: owner.id == _viewerId(),
                        size: 30 * s,
                      ),
                  ],
                ),
                if (task.description.trim().isNotEmpty) ...[
                  SizedBox(height: 14 * s),
                  Text(
                    task.description.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: SpotlightStyle.bodySize * s,
                      color: TaskStyle.neutralText,
                      height: 1.35,
                    ),
                  ),
                ],
                SizedBox(height: 16 * s),
                _log(task, s, logHeight),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Every update of [task], newest first, as a timeline that scrolls inside
  /// the card (round 2: "כל העדכונים, לא רק האחרון"). A new one (just sent)
  /// flies up into place with a highlight.
  Widget _log(TeamTask task, double s, double maxHeight) {
    final fresh = [
      for (final entry in task.updates)
        if (!_seenUpdates.contains(entry.id)) entry.id,
    ];
    final echo = fresh.isEmpty ? _echo : null;
    final count = task.updates.length + (echo == null ? 0 : 1);
    final rows = <Widget>[
      if (echo != null)
        _logRow(
          key: const Key('spotlight-log-echo'),
          text: echo,
          stamp: 'עכשיו',
          s: s,
          fresh: true,
          landing: true,
          first: true,
          last: task.updates.isEmpty,
        ),
      for (var i = 0; i < task.updates.length; i++)
        _staggered(
          i,
          _logRow(
            key: Key('spotlight-log-${task.updates[i].id}'),
            text: task.updates[i].text,
            stamp:
                '${task.updates[i].byName ?? unknownMemberLabel} · ${logStamp(task.updates[i].at)}',
            s: s,
            fresh: fresh.contains(task.updates[i].id),
            landing: fresh.isNotEmpty && task.updates[i].id == fresh.first,
            first: i == 0 && echo == null,
            last: i == task.updates.length - 1,
          ),
        ),
    ];
    return Container(
      key: Key('spotlight-updates-${task.id}'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: TaskStyle.updateBox,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: EdgeInsets.fromLTRB(14 * s, 10 * s, 14 * s, 6 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            count == 0 ? 'עדכונים' : 'עדכונים ($count)',
            style: TextStyle(
              fontSize: 13.5 * s,
              fontWeight: FontWeight.w700,
              color: TaskStyle.faintText,
            ),
          ),
          SizedBox(height: 6 * s),
          if (count == 0)
            Padding(
              padding: EdgeInsets.only(bottom: 8 * s),
              child: Text('אין עדכון עדיין',
                  style:
                      TextStyle(fontSize: SpotlightStyle.bodySize * s, color: TaskStyle.faintText)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Scrollbar(
                controller: _logScroll,
                child: SingleChildScrollView(
                  key: Key('spotlight-updates-scroll-${task.id}'),
                  controller: _logScroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Entry [i] slides up and fades in after the one above it.
  Widget _staggered(int i, Widget child) {
    const total = SpotlightStyle.logStepMs * SpotlightStyle.logMaxSteps + SpotlightStyle.logEntryMs;
    final begin = math.min(i, SpotlightStyle.logMaxSteps) * SpotlightStyle.logStepMs / total;
    final interval = Interval(begin, begin + SpotlightStyle.logEntryMs / total);
    return AnimatedBuilder(
      animation: _logIn,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(interval.transform(_logIn.value));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
        );
      },
      child: child,
    );
  }

  /// One update on the timeline: a dot on a line, the text, who and when.
  /// A [fresh] one (just sent) flies up into place and glows a moment.
  Widget _logRow({
    required Key key,
    required String text,
    required String stamp,
    required double s,
    required bool fresh,
    bool landing = false,
    required bool first,
    required bool last,
  }) {
    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18 * s,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 9 * s,
                  color: first ? Colors.transparent : TaskStyle.rest,
                ),
                Container(
                  width: 10 * s,
                  height: 10 * s,
                  decoration: BoxDecoration(
                    color: first ? TaskStyle.mine : TaskStyle.faintText,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(width: 2, color: last ? Colors.transparent : TaskStyle.rest),
                ),
              ],
            ),
          ),
          SizedBox(width: 10 * s),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4 * s, bottom: 10 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      style: TextStyle(
                          fontSize: SpotlightStyle.bodySize * s,
                          height: 1.35,
                          fontWeight: first ? FontWeight.w600 : FontWeight.normal)),
                  SizedBox(height: 2 * s),
                  Text(stamp, style: TextStyle(fontSize: 12.5 * s, color: TaskStyle.faintText)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (!fresh) return KeyedSubtree(key: key, child: row);
    // A sent update keeps its place empty while it flies up (the flight
    // lands on this row's box, [_flightLayer]); once there it glows a moment.
    return AnimatedBuilder(
      key: key,
      animation: _exit,
      builder: (context, child) {
        final sent = _exitKind == _Exit.update;
        final glow = sent && _landed ? 1 - const Interval(0.1, 0.8).transform(_exit.value) : 0.0;
        return Opacity(
          opacity: sent && !_landed ? 0 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Fade the blue's own alpha: from Colors.transparent (black,
              // alpha 0) the way passed through grey.
              color: TaskStyle.currentLight.withValues(alpha: glow),
              borderRadius: BorderRadius.circular(10),
            ),
            child: child,
          ),
        );
      },
      child: landing ? KeyedSubtree(key: _landingKey, child: row) : row,
    );
  }

  /// The sent update on its way from the field (bottom) to its row at the
  /// top of the log: one box that moves and reshapes from the field's look
  /// (white, bordered) to the row's landing glow, the text riding inside.
  /// Only this layer rebuilds per frame; it reads where the row is every
  /// frame, so it follows the card if the keyboard closing moves it.
  Widget _flightLayer(double s) {
    return AnimatedBuilder(
      animation: _flight,
      builder: (context, _) {
        final body = _bodyKey.currentContext?.findRenderObject();
        final target = _landingKey.currentContext?.findRenderObject();
        final from = _flightFrom;
        if (from == null ||
            body is! RenderBox ||
            target is! RenderBox ||
            !target.attached ||
            !target.hasSize) {
          return const SizedBox.shrink();
        }
        final origin = body.localToGlobal(Offset.zero);
        final to = (target.localToGlobal(Offset.zero) & target.size).shift(-origin);
        final t = Curves.easeInOutCubic.transform(_flight.value);
        final rect = Rect.lerp(from.shift(-origin), to, t)!;
        final lift = math.sin(math.pi * t);
        final padding = EdgeInsetsDirectional.lerp(
          const EdgeInsetsDirectional.fromSTEB(12, 14, 12, 14),
          EdgeInsetsDirectional.fromSTEB(28 * s, 4 * s, 0, 10 * s),
          t,
        )!;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: RepaintBoundary(
                child: Transform.scale(
                  scale: 1 + 0.04 * lift,
                  child: Container(
                    key: const Key('spotlight-update-flight'),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Color.lerp(TaskStyle.stageCard, TaskStyle.currentLight, t),
                      border: Border.all(
                        color: Color.lerp(TaskStyle.stageCardBorder, TaskStyle.currentLight, t)!,
                      ),
                      borderRadius: BorderRadius.circular(14 - 4 * t),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(10, 30, 60, 0.22 * lift),
                          blurRadius: 22 * lift,
                          offset: Offset(0, 8 * lift),
                        ),
                      ],
                    ),
                    padding: padding,
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Text(
                        _flightText,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: SpotlightStyle.bodySize * s,
                          height: 1.35,
                          fontWeight: FontWeight.lerp(FontWeight.normal, FontWeight.w600, t),
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String? _viewerId() {
    final state = context.read<TeamTaskBloc>().state;
    return state is TeamTasksLoaded ? state.viewer.id : null;
  }

  Widget _bigButton({
    required Key key,
    required String label,
    IconData? icon,
    required Color background,
    required Color foreground,
    required double s,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: SpotlightStyle.buttonHeight * s,
      child: FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle:
              TextStyle(fontSize: SpotlightStyle.buttonFont * s, fontWeight: FontWeight.w800),
        ),
        onPressed: _busy || _leaving ? null : onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: SpotlightStyle.buttonIcon * s),
              SizedBox(width: 8 * s),
            ],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _actions(TeamTask task, double s) {
    final gap = SizedBox(width: 10 * s);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _bigButton(
                key: const Key('spotlight-update'),
                label: 'עדכון קצר',
                icon: Icons.add_comment_outlined,
                background: TaskStyle.currentLight,
                foreground: TaskStyle.mine,
                s: s,
                onPressed: _openComposer,
              ),
            ),
            gap,
            Expanded(
              child: _bigButton(
                key: const Key('spotlight-done'),
                label: 'סיימתי',
                icon: Icons.check_rounded,
                background: TaskStyle.done,
                foreground: Colors.white,
                s: s,
                onPressed: () => _changeStatus(task, TeamTaskStatus.done),
              ),
            ),
          ],
        ),
        SizedBox(height: 10 * s),
        Row(
          children: [
            Expanded(
              child: _bigButton(
                key: const Key('spotlight-skip'),
                label: 'לא עכשיו',
                icon: Icons.schedule,
                background: TaskStyle.chip,
                foreground: TaskStyle.neutralText,
                s: s,
                onPressed: () => _skip(task.id),
              ),
            ),
            gap,
            Expanded(
              child: PopupMenuButton<TeamTaskStatus>(
                key: const Key('spotlight-status'),
                tooltip: 'שינוי סטטוס',
                enabled: !_busy && !_leaving,
                onSelected: (status) => _changeStatus(task, status),
                itemBuilder: (context) => teamTaskStatusMenuItems(),
                child: Container(
                  height: SpotlightStyle.buttonHeight * s,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TaskStyle.chip,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TeamTaskStatusIcon(status: task.status, size: 22 * s),
                      SizedBox(width: 8 * s),
                      Text(
                        'סטטוס',
                        style: TextStyle(
                          fontSize: SpotlightStyle.buttonFont * s,
                          fontWeight: FontWeight.w800,
                          color: TaskStyle.neutralText,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: TaskStyle.neutralText),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _busy
              ? const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: SizedBox(
                    key: Key('spotlight-busy'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _composer(TeamTask task, double s) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 20 * (1 - t)), child: child),
      ),
      child: Column(
        key: const Key('spotlight-composer'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < spotlightQuickUpdates.length; i++)
                ActionChip(
                  key: Key('spotlight-chip-$i'),
                  label: Text(spotlightQuickUpdates[i],
                      style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w600)),
                  padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 6 * s),
                  backgroundColor: TaskStyle.stageCard,
                  side: const BorderSide(color: TaskStyle.stageCardBorder),
                  onPressed: _busy || _leaving ? null : () => _pickQuick(spotlightQuickUpdates[i]),
                ),
            ],
          ),
          SizedBox(height: 12 * s),
          RtlArrowKeys(
            key: _fieldKey,
            multiline: true,
            child: TextField(
              key: const Key('spotlight-update-field'),
              controller: _update,
              focusNode: _updateFocus,
              readOnly: _busy || _leaving,
              minLines: 2,
              maxLines: 5,
              style: TextStyle(fontSize: SpotlightStyle.bodySize * s),
              decoration: InputDecoration(
                hintText: 'מה קרה במשימה?',
                filled: true,
                fillColor: TaskStyle.stageCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          SizedBox(height: 12 * s),
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _update,
                  builder: (context, value, _) => _bigButton(
                    key: const Key('spotlight-send'),
                    label: 'שליחה והבאה',
                    icon: Icons.send_rounded,
                    background: TaskStyle.mine,
                    foreground: Colors.white,
                    s: s,
                    onPressed: value.text.trim().isEmpty ? null : () => _send(task),
                  ),
                ),
              ),
              SizedBox(width: 10 * s),
              TextButton(
                key: const Key('spotlight-compose-cancel'),
                onPressed: _busy || _leaving
                    ? null
                    : () => setState(() {
                          _composing = false;
                          _update.clear();
                        }),
                child: Text('ביטול', style: TextStyle(fontSize: 16 * s)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(double s) {
    final allClear = _tally.skipped.isEmpty && _total > 0;
    final updatedOnly = _tally.updated.difference(_tally.closed).length;
    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_enter.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 50 * (1 - t)),
            child: Transform.scale(
              scale: 0.9 + 0.1 * Curves.easeOutBack.transform(_enter.value),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        key: const Key('spotlight-summary'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: Text(allClear ? '🎉' : '👏', style: TextStyle(fontSize: 64 * s)),
            ),
            SizedBox(height: 12 * s),
            Text(
              _total == 1 ? 'עברת על משימה אחת' : 'עברת על $_total משימות',
              style: TextStyle(fontSize: 28 * s, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 22 * s),
            Row(
              children: [
                _stat('נסגרו', _tally.closed.length, TaskStyle.doneDark, TaskStyle.doneLight, s, 0),
                SizedBox(width: 10 * s),
                _stat('עודכנו', updatedOnly, TaskStyle.mine, TaskStyle.currentLight, s, 1),
                SizedBox(width: 10 * s),
                _stat('לפעם אחרת', _tally.skipped.length, TaskStyle.neutralText, TaskStyle.chip, s,
                    2),
              ],
            ),
            SizedBox(height: 14 * s),
            Text(
              _tally.summary,
              key: const Key('spotlight-tally'),
              style: TextStyle(fontSize: 16 * s, color: TaskStyle.neutralText),
            ),
            SizedBox(height: 26 * s),
            SizedBox(
              height: SpotlightStyle.buttonHeight * s,
              width: 260 * s,
              child: FilledButton(
                key: const Key('spotlight-finish'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: TextStyle(
                      fontSize: SpotlightStyle.buttonFont * s, fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  Logger.action('tap:spotlightFinish');
                  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
                  Navigator.of(context).pop(_tally.touched);
                },
                child: const Text('חזרה לרשימה'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A number of the summary that counts up from 0.
  Widget _stat(String label, int value, Color color, Color fill, double s, int order) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14 * s),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: Duration(milliseconds: 700 + order * 200),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                '${v.round()}',
                key: Key('spotlight-stat-$order'),
                style: TextStyle(fontSize: 34 * s, fontWeight: FontWeight.w900, color: color),
              ),
            ),
            Text(label,
                style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

/// The status chip of the card: its colour morphs and its label rolls when
/// the status changes (the [TeamTaskStatusChip] colours, bigger).
class _MorphStatusChip extends StatelessWidget {
  const _MorphStatusChip({required this.status, required this.scale});

  final TeamTaskStatus status;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: const Key('spotlight-status-chip'),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 5 * scale),
      decoration: BoxDecoration(
        color: TeamTaskStyle.statusFill(status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation, child: FadeTransition(opacity: animation, child: child)),
        child: Text(
          status.hebrewLabel,
          key: ValueKey(status),
          style: TextStyle(
            fontSize: 14 * scale,
            color: TeamTaskStyle.statusColor(status),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// One piece of confetti: thrown at [angle] with [speed] (px/s), it falls,
/// spins and drifts sideways.
class _ConfettiPiece {
  const _ConfettiPiece({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.spin,
    required this.round,
    required this.drift,
  });

  final double angle;
  final double speed;
  final Color color;
  final double size;
  final double spin;
  final bool round;
  final double drift;
}

/// A short burst from the middle of the screen (round 2: "קונפטי חמוד").
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_ConfettiPiece> pieces;
  final double t;

  static const double _seconds = 1.6;
  static const double _gravity = 1500;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.48);
    final time = t * _seconds;
    final fade = 1 - const Interval(0.65, 1).transform(t);
    final paint = Paint();
    for (final piece in pieces) {
      // Air slows the throw: the speed eases off over the first half second.
      final drag = 1 - math.exp(-time * 2.2);
      final travel = piece.speed * drag / 2.2;
      final position = origin +
          Offset(math.cos(piece.angle) * travel + piece.drift * time,
              math.sin(piece.angle) * travel + 0.5 * _gravity * 0.35 * time * time);
      paint.color = piece.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(piece.spin * time);
      if (piece.round) {
        canvas.drawCircle(Offset.zero, piece.size * 0.45, paint);
      } else {
        // A flat strip that seems to flip as it spins.
        final flip = math.cos(piece.spin * time * 1.7).abs();
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: piece.size, height: piece.size * 0.55 * (0.25 + flip)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t || old.pieces != pieces;
}

/// Lays [child] out [room] bigger on every side than its own box and paints it
/// that much up and to the side, so the child can hold the paint that spills
/// out of the card (its shadow) while the layout around sees only the card.
class _ShadowRoom extends SingleChildRenderObjectWidget {
  const _ShadowRoom({required this.room, required super.child});

  final EdgeInsets room;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShadowRoom(room);

  @override
  void updateRenderObject(BuildContext context, _RenderShadowRoom renderObject) {
    renderObject.room = room;
  }
}

class _RenderShadowRoom extends RenderProxyBox {
  _RenderShadowRoom(this._room);

  EdgeInsets _room;
  EdgeInsets get room => _room;
  set room(EdgeInsets value) {
    if (value == _room) return;
    _room = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final inner = BoxConstraints(
      minWidth: constraints.minWidth + room.horizontal,
      maxWidth: constraints.maxWidth + room.horizontal,
      minHeight: constraints.minHeight + room.vertical,
      maxHeight: constraints.maxHeight + room.vertical,
    );
    child.layout(inner, parentUsesSize: true);
    size = constraints.constrain(
        Size(child.size.width - room.horizontal, child.size.height - room.vertical));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(0, super.computeMinIntrinsicWidth(height + room.vertical) - room.horizontal);
  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(0, super.computeMaxIntrinsicWidth(height + room.vertical) - room.horizontal);
  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(0, super.computeMinIntrinsicHeight(width + room.horizontal) - room.vertical);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(0, super.computeMaxIntrinsicHeight(width + room.horizontal) - room.vertical);

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  Offset get _shift => Offset(-room.left, -room.top);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _shift);
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }
}
