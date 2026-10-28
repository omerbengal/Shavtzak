import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/custom_hours.dart';
import '../../../../core/utils/event_stretch.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/custom_hours_resolution.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../widgets/custom_hours_fields.dart';

const String _title = '⏰ לחלק מהצוות יש שעות מותאמות';
const String _intro =
    'מועדי האירוע השתנו. בחר/י מה קורה עם השעות של כל אחד לפני השמירה.';
const String _moveLabel = 'להזיז עם האירוע';
const String _keepLabel = 'להשאיר כמו שזה';
const String _keepNoOverlapSuffix = ' ⚠️ לא חופף לאירוע החדש';
const String _editLabel = 'לערוך…';
const String _removeLabel = 'להסיר שעות מותאמות';
const String _removeHint = 'יקבל/תקבל את שעות האירוע';
const String _cancelLabel = 'ביטול';
const String _saveLabel = 'שמור אירוע';

/// What the admin decided for one card.
enum _Choice { move, keep, edit, remove }

/// A pair of stored hours; both null clears them.
typedef _Hours = ({String? start, String? end});

/// One thing to decide: a member's hours across their roles in the event, or
/// for a member flagged `allowMultipleAssignments` (a placeholder whose slots
/// are different people) one assignment's hours.
class _HoursCard {
  _HoursCard({
    required this.key,
    required this.member,
    required this.name,
    required Assignment first,
    required this.current,
  }) : assignments = [first] {
    editSeed = current;
  }

  final String key;

  /// Null when the form could not load the member: the card then names them
  /// generically and shows no constraint warnings.
  final TeamMember? member;
  final String name;
  final List<Assignment> assignments;

  /// The hours the member holds now.
  final WallInterval current;

  _Choice? choice;

  /// The hours typed under "לערוך…"; null while they are not a usable interval.
  WallInterval? editValue;

  /// Where the edit fields start: the current hours, then the last usable ones
  /// typed, so switching away and back does not lose them.
  late WallInterval editSeed;

  /// Whether the admin still has something to settle here.
  bool get needsAttention =>
      choice == null || (choice == _Choice.edit && editValue == null);
}

/// Asked when an event save moves the event in time and some members have
/// custom hours: what happens to each member's hours. Nothing is saved until
/// every member has an answer; "ביטול" returns null and nothing is written.
///
/// Returns one [CustomHoursResolution] per assignment, ordered by member name.
/// A member's roles all get the same hours; a card's choice is applied to each
/// of its assignments.
class CustomHoursResolveDialog extends StatefulWidget {
  /// The event as stored.
  final Event oldEvent;

  /// The event as the form is about to save it.
  final Event newEvent;

  /// The event's assignments that carry hours. Their `teamMember`, when
  /// populated, gives the name and the constraints to warn about.
  final List<Assignment> withHours;

  /// Hebrew role names by role key, for the card titles. A role not in the map
  /// is left out of the title.
  final Map<String, String> roleNames;

  const CustomHoursResolveDialog({
    super.key,
    required this.oldEvent,
    required this.newEvent,
    required this.withHours,
    this.roleNames = const {},
  });

  /// The admin's resolutions, or null for "ביטול".
  static Future<List<CustomHoursResolution>?> show(
    BuildContext context, {
    required Event oldEvent,
    required Event newEvent,
    required List<Assignment> withHours,
    Map<String, String> roleNames = const {},
  }) {
    return showDialog<List<CustomHoursResolution>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomHoursResolveDialog(
        oldEvent: oldEvent,
        newEvent: newEvent,
        withHours: withHours,
        roleNames: roleNames,
      ),
    );
  }

  @override
  State<CustomHoursResolveDialog> createState() =>
      _CustomHoursResolveDialogState();
}

class _CustomHoursResolveDialogState extends State<CustomHoursResolveDialog> {
  late final List<_HoursCard> _cards;

  /// Whole days the event's first day moved. Zero when only times changed (or
  /// only the last day moved): there is then nothing to move the hours by.
  late final int _shift;

  late final WallInterval _newStretch;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _cards = _buildCards();
    _shift = calendarDaysBetween(
      widget.oldEvent.startDate,
      widget.newEvent.startDate,
    );
    _newStretch = eventStretch(widget.newEvent);
  }

  List<_HoursCard> _buildCards() {
    final byKey = <String, _HoursCard>{};
    for (final assignment in widget.withHours) {
      final window = assignment.customWindow;
      // Hours that cannot be read need no decision: nothing to show or shift.
      if (window == null) continue;
      final member = assignment.teamMember;
      final exempt = member?.allowMultipleAssignments ?? false;
      final key = exempt ? assignment.id : assignment.teamMemberId;
      final existing = byKey[key];
      if (existing != null) {
        existing.assignments.add(assignment);
        continue;
      }
      final name = member?.name.trim() ?? '';
      byKey[key] = _HoursCard(
        key: key,
        member: member,
        name: name.isEmpty ? unnamedMemberName : name,
        first: assignment,
        current: window,
      );
    }
    // Dart's sort is not stable: ties keep the order the assignments came in.
    final order = {
      for (final entry in byKey.values.indexed) entry.$2.key: entry.$1,
    };
    return byKey.values.toList()
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : order[a.key]!.compareTo(order[b.key]!);
      });
  }

  // ----- what a choice means -------------------------------------------

  String _text(DateTime moment) => formatWallMoment(moment);

  /// The hours [card] resolves to under [choice]; null while an edit is not a
  /// usable interval.
  _Hours? _hoursFor(_HoursCard card, _Choice choice) {
    switch (choice) {
      case _Choice.move:
        return (
          start: shiftWallMoment(_text(card.current.start), _shift),
          end: shiftWallMoment(_text(card.current.end), _shift),
        );
      case _Choice.keep:
        return (start: _text(card.current.start), end: _text(card.current.end));
      case _Choice.edit:
        final edited = card.editValue;
        if (edited == null) return null;
        return (start: _text(edited.start), end: _text(edited.end));
      case _Choice.remove:
        return (start: null, end: null);
    }
  }

  /// The window the member would be held for under [choice]: the hours, or the
  /// new event's stretch once they are removed. Null while an edit is unusable.
  WallInterval? _windowFor(_HoursCard card, _Choice choice) {
    if (choice == _Choice.remove) return _newStretch;
    final hours = _hoursFor(card, choice);
    if (hours == null) return null;
    return customHoursInterval(hours.start, hours.end);
  }

  List<String> _warningsFor(_HoursCard card) {
    final choice = card.choice;
    final member = card.member;
    if (choice == null || member == null) return const [];
    final window = _windowFor(card, choice);
    if (window == null) return const [];
    return customHoursWarningLines(member, window);
  }

  int get _remaining => _cards.where((card) => card.needsAttention).length;

  /// One resolution per assignment, called only once every card is settled.
  List<CustomHoursResolution> _resolutions() {
    final resolutions = <CustomHoursResolution>[];
    for (final card in _cards) {
      final hours = _hoursFor(card, card.choice!)!;
      for (final assignment in card.assignments) {
        resolutions.add(CustomHoursResolution(
          assignmentId: assignment.id,
          customStartAt: hours.start,
          customEndAt: hours.end,
        ));
      }
    }
    return resolutions;
  }

  // ----- actions -------------------------------------------------------

  void _choose(_HoursCard card, _Choice choice) {
    if (card.choice == choice) return;
    Logger.action('tap:choice:customHoursResolveDialog', {
      'choice': choice.name,
    });
    setState(() {
      card.choice = choice;
      if (choice == _Choice.edit) card.editValue = card.editSeed;
    });
  }

  void _moveEveryone() {
    Logger.action('tap:moveAll:customHoursResolveDialog', {'days': _shift});
    setState(() {
      for (final card in _cards) {
        card.choice = _Choice.move;
      }
    });
  }

  Future<void> _close(List<CustomHoursResolution>? result) async {
    if (_closing) return;
    _closing = true;
    // Let a focused time field finish its blur before the dialog goes (the
    // same settle the notes dialog does).
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _save() {
    Logger.action('tap:save:customHoursResolveDialog', {
      'cards': _cards.length,
    });
    _close(_resolutions());
  }

  void _cancel() {
    Logger.action('tap:cancel:customHoursResolveDialog');
    _close(null);
  }

  // ----- views ---------------------------------------------------------

  /// '27–28.10', '30.10–2.11' or '27.10', then the times that are set.
  String _when(Event event) {
    final first = event.startDate;
    final last = event.endDate;
    final String days;
    if (calendarDaysBetween(first, last) <= 0) {
      days = '${first.day}.${first.month}';
    } else if (first.year == last.year && first.month == last.month) {
      days = '${first.day}–${last.day}.${last.month}';
    } else {
      days = '${first.day}.${first.month}–${last.day}.${last.month}';
    }
    final times = [
      ('התייצבות', event.assemblyTime),
      ('התכנסות קהל', event.startTime),
      ('תחילת המופע', event.actualShowStartTime),
      ('סיום המופע', event.endTime),
      ('סיום הצוות', event.teamEndTime),
    ];
    return [
      days,
      for (final (label, time) in times)
        if (time.trim().isNotEmpty) '$label ${time.trim()}',
    ].join(' · ');
  }

  Widget _changeBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FC),
        border: Border.all(color: const Color(0xFFD6E3F3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.newEvent.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            _when(widget.oldEvent),
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Colors.grey.shade600,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(
            _when(widget.newEvent),
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _bulkButton() {
    final days = _shift.abs() == 1 ? '1 יום' : '${_shift.abs()} ימים';
    final label = _shift > 0
        ? 'להזיז את כולם עם האירוע (+$days)'
        : 'להזיז את כולם עם האירוע (-$days)';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _moveEveryone,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _option({
    required _HoursCard card,
    required _Choice choice,
    required String label,
    String? hint,
  }) {
    final selected = card.choice == choice;
    final primary = Theme.of(context).colorScheme.primary;
    final foreground = selected ? Colors.white : Colors.grey.shade900;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? primary : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: selected ? primary : Colors.grey.shade400),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          onTap: () => _choose(card, choice),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: foreground.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The choices as two columns of tiles; "להזיז עם האירוע" only when the
  /// event's first day moved.
  Widget _options(_HoursCard card) {
    final keepOverlaps = card.current.overlaps(_newStretch);
    final tiles = <Widget>[
      if (_shift != 0)
        _option(
          card: card,
          choice: _Choice.move,
          label: _moveLabel,
          hint: formatCustomHours(_windowFor(card, _Choice.move)!),
        ),
      _option(
        card: card,
        choice: _Choice.keep,
        label: keepOverlaps ? _keepLabel : '$_keepLabel$_keepNoOverlapSuffix',
        hint: formatCustomHours(card.current),
      ),
      _option(card: card, choice: _Choice.edit, label: _editLabel),
      _option(
        card: card,
        choice: _Choice.remove,
        label: _removeLabel,
        hint: _removeHint,
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? tiles[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _cardTitle(_HoursCard card) {
    final roles = <String>[];
    for (final assignment in card.assignments) {
      final role = widget.roleNames[assignment.roleType];
      if (role != null && !roles.contains(role)) roles.add(role);
    }
    return roles.isEmpty ? card.name : '${card.name} · ${roles.join(', ')}';
  }

  Widget _card(_HoursCard card) {
    final done = !card.needsAttention;
    final warnings = _warningsFor(card);
    return Container(
      key: ValueKey('hoursCard:${card.key}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: done ? const Color(0xFFF5FBF5) : const Color(0xFFFFFAF0),
        border: Border.all(
          color: done ? const Color(0xFF9CCC9C) : const Color(0xFFF0B429),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _cardTitle(card),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 8),
            child: Text(
              formatCustomHours(card.current),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          _options(card),
          if (card.choice == _Choice.edit) ...[
            const SizedBox(height: 10),
            CustomHoursFields(
              key: ValueKey('hoursFields:${card.key}'),
              event: widget.newEvent,
              initial: card.editSeed,
              onChanged: (window) {
                setState(() {
                  card.editValue = window;
                  if (window != null) card.editSeed = window;
                });
              },
            ),
          ],
          for (final line in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                line,
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final remaining = _remaining;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 6,
            children: [
              TextButton(onPressed: _cancel, child: const Text(_cancelLabel)),
              ElevatedButton(
                onPressed: remaining == 0 ? _save : null,
                child: const Text(_saveLabel),
              ),
            ],
          ),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'נשאר $remaining לבחירה',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  _title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _intro,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      _changeBox(),
                      if (_shift != 0) _bulkButton(),
                      for (final card in _cards) _card(card),
                    ],
                  ),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }
}
