import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/custom_hours.dart';
import '../../../../core/utils/event_stretch.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../widgets/custom_hours_fields.dart';

const String _unnamedMember = 'חבר/ת הצוות';
const String _eventHoursLabel = 'שעות האירוע הרגילות';
const String _otherHoursLabel = 'שעות אחרות…';
const String _cancelLabel = 'ביטול';
const String _confirmLabel = 'אישור';

/// The admin's answer: the hours the incoming member gets, null for the
/// event's own hours.
typedef ReplacementHours = ({WallInterval? hours});

enum _Choice { keepPrevious, incomingExisting, eventHours, other }

/// Asked on the admin assignments screen when a slot is filled or its member
/// replaced and custom hours are involved: the slot's previous occupant had
/// hours of their own, or the incoming member already has hours on another
/// role of the event. Which hours does the incoming member get?
///
/// The choices are shown only where they apply ([previousHours],
/// [incomingExistingHours]); the event's own hours and "other hours" always
/// are. Nothing is preselected: the previous occupant's hours may have been
/// made for their own needs. Each choice shows its hours and whether they
/// collide with the incoming member's constraints. "ביטול" returns null and
/// the previous occupant stays.
class ReplacementHoursDialog extends StatefulWidget {
  final Event event;

  /// The member being put into the slot.
  final TeamMember incoming;

  /// The slot's occupant before, if any; names their hours.
  final TeamMember? previous;

  /// The hours the slot's occupant had.
  final WallInterval? previousHours;

  /// The hours [incoming] already holds on another role of the event.
  final WallInterval? incomingExistingHours;

  /// Whether [incoming] holds another role in the event: the hours chosen
  /// then apply to every one of them (unless the member is flagged
  /// `allowMultipleAssignments`), and the dialog says so.
  final bool incomingHasOtherRoles;

  const ReplacementHoursDialog({
    super.key,
    required this.event,
    required this.incoming,
    this.previous,
    this.previousHours,
    this.incomingExistingHours,
    required this.incomingHasOtherRoles,
  });

  /// The admin's choice, or null for "ביטול". `(hours: null)` is the event's
  /// own hours.
  static Future<ReplacementHours?> show(
    BuildContext context, {
    required Event event,
    required TeamMember incoming,
    TeamMember? previous,
    WallInterval? previousHours,
    WallInterval? incomingExistingHours,
    required bool incomingHasOtherRoles,
  }) {
    return showDialog<ReplacementHours>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReplacementHoursDialog(
        event: event,
        incoming: incoming,
        previous: previous,
        previousHours: previousHours,
        incomingExistingHours: incomingExistingHours,
        incomingHasOtherRoles: incomingHasOtherRoles,
      ),
    );
  }

  @override
  State<ReplacementHoursDialog> createState() => _ReplacementHoursDialogState();
}

class _ReplacementHoursDialogState extends State<ReplacementHoursDialog> {
  late final WallInterval _eventStretch;
  late final String _incomingName;
  late final String _previousName;

  _Choice? _choice;

  /// The hours typed under "שעות אחרות…"; null while they are not a usable
  /// interval.
  WallInterval? _otherValue;

  /// Where the "שעות אחרות…" fields start: the hours already in play, then the
  /// last usable ones typed, so switching away and back does not lose them.
  late WallInterval _otherSeed;

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _eventStretch = eventStretch(widget.event);
    _incomingName = _firstNameOf(widget.incoming);
    _previousName = _firstNameOf(widget.previous);
    _otherSeed = widget.previousHours ??
        widget.incomingExistingHours ??
        _eventStretch;
  }

  static String _firstNameOf(TeamMember? member) {
    final first = memberFirstName(member?.name ?? '');
    return first.isEmpty ? _unnamedMember : first;
  }

  // ----- what a choice means -------------------------------------------

  /// The hours [choice] gives the incoming member; null for the event's own
  /// hours, and for "other" while the typed hours are unusable.
  WallInterval? _hoursFor(_Choice choice) {
    switch (choice) {
      case _Choice.keepPrevious:
        return widget.previousHours;
      case _Choice.incomingExisting:
        return widget.incomingExistingHours;
      case _Choice.eventHours:
        return null;
      case _Choice.other:
        return _otherValue;
    }
  }

  /// The stretch the incoming member is held for under [choice], which their
  /// constraints are judged against; null while "other" is unusable.
  WallInterval? _windowFor(_Choice choice) =>
      choice == _Choice.eventHours ? _eventStretch : _hoursFor(choice);

  bool get _canConfirm =>
      _choice != null && (_choice != _Choice.other || _otherValue != null);

  // ----- actions -------------------------------------------------------

  void _choose(_Choice choice) {
    if (_choice == choice) return;
    Logger.action('tap:choice:replacementHoursDialog', {'choice': choice.name});
    setState(() {
      _choice = choice;
      if (choice == _Choice.other) _otherValue = _otherSeed;
    });
  }

  Future<void> _close(ReplacementHours? result) async {
    if (_closing) return;
    _closing = true;
    // Let a focused time field finish its blur before the dialog goes (the
    // same settle the notes dialog does).
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _confirm() {
    final choice = _choice!;
    Logger.action('tap:confirm:replacementHoursDialog', {
      'choice': choice.name,
    });
    _close((hours: _hoursFor(choice)));
  }

  void _cancel() {
    Logger.action('tap:cancel:replacementHoursDialog');
    _close(null);
  }

  // ----- views ---------------------------------------------------------

  String get _title => widget.previousHours != null
      ? '⏰ ל$_previousName היו שעות מותאמות'
      : '⏰ ל$_incomingName יש שעות מותאמות באירוע';

  String get _intro {
    final question = 'אילו שעות יהיו ל$_incomingName?';
    if (widget.previous == null) {
      return '$_incomingName משובץ/ת ל${widget.event.name}. $question';
    }
    return '$_incomingName מחליף/ה את $_previousName '
        '(${widget.event.name}). $question';
  }

  bool get _showsOtherRolesLine =>
      widget.incomingHasOtherRoles &&
      !widget.incoming.allowMultipleAssignments;

  /// The conflict result of [window] for the incoming member: a "no conflict"
  /// line, or one warning line per constraint it runs into.
  List<Widget> _resultLines(WallInterval window) {
    final warnings = customHoursWarningLines(widget.incoming, window);
    if (warnings.isEmpty) {
      return [
        Text(
          '✅ אין התנגשות עם אילוצים של $_incomingName',
          style: TextStyle(fontSize: 12, color: Colors.green.shade800),
        ),
      ];
    }
    return [
      for (final line in warnings)
        Text(
          line,
          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
        ),
    ];
  }

  Widget _option({
    required _Choice choice,
    required String label,
    String? hoursText,
    List<Widget> below = const [],
  }) {
    final selected = _choice == choice;
    final primary = Theme.of(context).colorScheme.primary;
    final window = _windowFor(choice);
    // "Other" has nothing to judge until it is chosen and usable.
    final showsResult =
        window != null && (choice != _Choice.other || selected);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        key: ValueKey('replacementHours:${choice.name}'),
        button: true,
        selected: selected,
        child: Material(
          color: selected ? primary.withValues(alpha: 0.06) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected ? primary : Colors.grey.shade400,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            onTap: () => _choose(choice),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hoursText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hoursText,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ...below,
                  if (showsResult)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _resultLines(window),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _options() {
    final previousHours = widget.previousHours;
    final existingHours = widget.incomingExistingHours;
    return [
      if (previousHours != null)
        _option(
          choice: _Choice.keepPrevious,
          label: 'לשמור את השעות של $_previousName',
          hoursText: formatCustomHours(previousHours),
        ),
      if (existingHours != null)
        _option(
          choice: _Choice.incomingExisting,
          label: 'השעות הקיימות של $_incomingName',
          hoursText: formatCustomHours(existingHours),
        ),
      _option(
        choice: _Choice.eventHours,
        label: _eventHoursLabel,
        hoursText: formatCustomHours(_eventStretch),
      ),
      _option(
        choice: _Choice.other,
        label: _otherHoursLabel,
        below: [
          if (_choice == _Choice.other) ...[
            const SizedBox(height: 10),
            CustomHoursFields(
              key: const ValueKey('replacementHours:fields'),
              event: widget.event,
              initial: _otherSeed,
              onChanged: (window) {
                setState(() {
                  _otherValue = window;
                  if (window != null) _otherSeed = window;
                });
              },
            ),
          ],
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
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
                      if (_showsOtherRolesLine)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'השעות יחולו על כל התפקידים של $_incomingName '
                            'באירוע',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ..._options(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 24,
                  runSpacing: 6,
                  children: [
                    TextButton(
                      onPressed: _cancel,
                      child: const Text(_cancelLabel),
                    ),
                    ElevatedButton(
                      onPressed: _canConfirm ? _confirm : null,
                      child: const Text(_confirmLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
