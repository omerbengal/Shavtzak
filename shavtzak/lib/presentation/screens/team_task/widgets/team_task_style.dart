import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/entities/team_task.dart';
import '../../task/task_style.dart';

/// Colours and small formatters of the team tasks screen, on top of the
/// דו יומי [TaskStyle].
abstract final class TeamTaskStyle {
  static Color statusColor(TeamTaskStatus status) => switch (status) {
        TeamTaskStatus.open => TaskStyle.neutralText,
        TeamTaskStatus.inProgress => TaskStyle.mine,
        TeamTaskStatus.done => TaskStyle.doneDark,
        TeamTaskStatus.cancelled => TaskStyle.faintText,
        TeamTaskStatus.duplicate => TaskStyle.faintText,
      };

  static Color statusFill(TeamTaskStatus status) => switch (status) {
        TeamTaskStatus.open => TaskStyle.chip,
        TeamTaskStatus.inProgress => TaskStyle.currentLight,
        TeamTaskStatus.done => TaskStyle.doneLight,
        TeamTaskStatus.cancelled => TaskStyle.chip,
        TeamTaskStatus.duplicate => TaskStyle.chip,
      };

  /// Each urgency has its sign (Omer, 16/11/2026): "גבוהה" a red up arrow,
  /// "רגילה" a grey dash, "נמוכה" a light-blue down arrow. "רגילה" is not
  /// shown on a row.
  static IconData urgencyIcon(TeamTaskUrgency urgency) => switch (urgency) {
        TeamTaskUrgency.high => Icons.arrow_upward,
        TeamTaskUrgency.normal => Icons.remove,
        TeamTaskUrgency.low => Icons.arrow_downward,
      };

  static Color urgencyColor(TeamTaskUrgency urgency) => switch (urgency) {
        TeamTaskUrgency.high => TaskStyle.lateDark,
        TeamTaskUrgency.normal => TaskStyle.faintText,
        TeamTaskUrgency.low => urgencyLowBlue,
      };

  static Color urgencyFill(TeamTaskUrgency urgency) => switch (urgency) {
        TeamTaskUrgency.high => TaskStyle.lateLight,
        TeamTaskUrgency.normal => TaskStyle.chip,
        TeamTaskUrgency.low => const Color(0xFFE1F5FE),
      };

  /// "נמוכה"'s light blue (Material lightBlue 600: light, still readable on
  /// white).
  static const Color urgencyLowBlue = Color(0xFF039BE5);

  static const double maxListWidth = TaskStyle.readableWidth;

  // Design A (Omer, round 3): a card per link, a status circle per row.
  static const double statusIconSize = 20;
  static const double smallStatusIconSize = 16;
  static const double avatarSize = 24;

  /// An event's title row inside a category's card (16/11/2026): lighter
  /// than the card's header.
  static const Color sectionHeader = Color(0xFFF8FAFC);

  /// A row under the mouse (desktop): a light blue, clearly seen on white.
  static const Color rowHover = TaskStyle.currentLight;

  /// The row whose task is open in the side panel (wide window, round 7).
  static const Color rowSelected = Color(0xFFFFF3E0);

  /// From this width the list is not a phone's (round 7): a task opens in a
  /// panel on the left while the list slides right, instead of a sheet.
  static const double splitBreakpoint = 720;

  /// The list's width beside the open panel: 42% of the room, between these.
  static const double splitListMinWidth = 340;
  static const double splitListShare = 0.42;

  /// How long the list and the panel take to slide, both ways (Omer,
  /// 16/11/2026: a light 500 ms move).
  static const Duration splitDuration = Duration(milliseconds: 500);
  static const Curve splitCurve = Curves.easeInOut;
}

/// `d.M`, the way the team writes a date ("15.11").
String shortDate(DateTime date) => '${date.day}.${date.month}';

/// `d.M.yyyy`.
String fullDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

/// `d.M HH:mm` in local time, for the update log.
String logStamp(DateTime at) {
  final local = at.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${shortDate(local)} $hh:$mm';
}

/// `yyyy-MM-dd` of [date].
String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A small rounded status chip.
class TeamTaskStatusChip extends StatelessWidget {
  const TeamTaskStatusChip({super.key, required this.status, this.dense = false});

  final TeamTaskStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 1 : 4),
      decoration: BoxDecoration(
        color: TeamTaskStyle.statusFill(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.hebrewLabel,
        style: TextStyle(
          fontSize: dense ? TaskStyle.rowMetaSize : 13,
          color: TeamTaskStyle.statusColor(status),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The urgency as a small chip ("דחיפות גבוהה"); nothing for "רגילה" unless
/// [showNormal].
class TeamTaskUrgencyChip extends StatelessWidget {
  const TeamTaskUrgencyChip({
    super.key,
    required this.urgency,
    this.dense = true,
    this.showNormal = false,
  });

  final TeamTaskUrgency urgency;
  final bool dense;
  final bool showNormal;

  @override
  Widget build(BuildContext context) {
    if (urgency == TeamTaskUrgency.normal && !showNormal) return const SizedBox.shrink();
    final high = urgency == TeamTaskUrgency.high;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 1 : 4),
      decoration: BoxDecoration(
        color: TeamTaskStyle.urgencyFill(urgency),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TeamTaskUrgencyIcon(urgency: urgency, size: dense ? 13 : 15),
          const SizedBox(width: 2),
          Text(
            'דחיפות ${urgency.hebrewLabel}',
            style: TextStyle(
              fontSize: dense ? TaskStyle.rowMetaSize : 13,
              color: urgency == TeamTaskUrgency.normal
                  ? TaskStyle.neutralText
                  : TeamTaskStyle.urgencyColor(urgency),
              fontWeight: high ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The urgency's sign alone: a red up arrow, a grey dash or a light-blue
/// down arrow.
class TeamTaskUrgencyIcon extends StatelessWidget {
  const TeamTaskUrgencyIcon({super.key, required this.urgency, this.size = 16, this.color});

  final TeamTaskUrgency urgency;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
        TeamTaskStyle.urgencyIcon(urgency),
        key: Key('urgency-icon-${urgency.key}'),
        size: size,
        color: color ?? TeamTaskStyle.urgencyColor(urgency),
      );
}

/// The urgency's three choices in one row (the form and the task screen),
/// in the app's segmented-switch colours, each with its sign; "גבוהה" in
/// its red.
class TeamTaskUrgencyPicker extends StatelessWidget {
  const TeamTaskUrgencyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.showLabel = true,
  });

  final TeamTaskUrgency value;
  final ValueChanged<TeamTaskUrgency> onChanged;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final picker = SizedBox(
      width: double.infinity,
      child: SegmentedButton<TeamTaskUrgency>(
        key: const Key('team-task-urgency-picker'),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: value == TeamTaskUrgency.high
              ? TaskStyle.lateDark
              : AppTheme.primaryDark,
          selectedForegroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
        segments: [
          for (final urgency in TeamTaskUrgency.values)
            ButtonSegment(
              value: urgency,
              icon: TeamTaskUrgencyIcon(
                urgency: urgency,
                size: 16,
                // On the selected (dark) segment the sign turns white.
                color: urgency == value ? Colors.white : null,
              ),
              label: Text(urgency.hebrewLabel, key: Key('team-task-urgency-${urgency.key}')),
            ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
    if (!showLabel) return picker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('דחיפות', style: TextStyle(fontSize: 12.5, color: TaskStyle.neutralText)),
        const SizedBox(height: 4),
        picker,
      ],
    );
  }
}

/// An event's name as a small outlined chip: the events of a task linked to
/// several of them (16/11/2026).
class TeamTaskEventChip extends StatelessWidget {
  const TeamTaskEventChip({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: TaskStyle.stageHeader,
          border: Border.all(color: TaskStyle.rest),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          name,
          style: const TextStyle(fontSize: TaskStyle.rowMetaSize, color: TaskStyle.neutralText),
        ),
      );
}

/// The app's mark of a permanent team member (חבר צוות קבוע), as in the
/// team list and the assignment member picker.
class PermanentMemberMark extends StatelessWidget {
  const PermanentMemberMark({super.key, this.size = 12});

  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Icon(Icons.verified_user, size: size, color: Colors.blue.shade700),
      );
}

/// A member's name followed by the permanent mark when [permanent].
class MemberNameText extends StatelessWidget {
  const MemberNameText({super.key, required this.name, required this.permanent, this.style});

  final String name;
  final bool permanent;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: name),
          if (permanent)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: PermanentMemberMark(),
            ),
        ]),
        style: style,
      );
}

/// A member's name as a small chip.
class MemberNameChip extends StatelessWidget {
  const MemberNameChip({
    super.key,
    required this.name,
    this.highlight = false,
    this.permanent = false,
  });

  final String name;
  final bool highlight;
  final bool permanent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? TaskStyle.currentLight : TaskStyle.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: MemberNameText(
        name: name,
        permanent: permanent,
        style: TextStyle(
          fontSize: TaskStyle.rowMetaSize,
          color: highlight ? TaskStyle.mine : TaskStyle.neutralText,
        ),
      ),
    );
  }
}

/// A member's initials for an owner circle: the first letter of the first
/// name and of the last name ("עומר בנגל" = "עב"); one word = one letter
/// (Omer, round 3).
String memberInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  if (words.length == 1) return first;
  return '$first${words.last.characters.first}';
}

/// An owner as a coloured circle with their initials; the viewer's own has a
/// blue ring.
class MemberInitialsAvatar extends StatelessWidget {
  const MemberInitialsAvatar({
    super.key,
    required this.memberId,
    required this.name,
    this.highlight = false,
    this.size = 24,
  });

  final String memberId;
  final String name;
  final bool highlight;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: Container(
        constraints: BoxConstraints(minWidth: size),
        height: size,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: TaskStyle.editAvatarColor(memberId),
          borderRadius: BorderRadius.circular(size / 2),
          border: highlight ? Border.all(color: Colors.white, width: 1.5) : null,
          boxShadow: highlight ? const [BoxShadow(color: TaskStyle.mine, spreadRadius: 1.5)] : null,
        ),
        // widthFactor 1: as wide as the initials, never the whole row.
        child: Center(
          widthFactor: 1,
          child: Text(
            memberInitials(name),
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.44,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// A status as a circle whose shape alone tells it (Omer, round 3): open =
/// an empty grey ring, in progress = half filled blue, done = filled green
/// with a tick, cancelled = a grey ring struck through, duplicate = two
/// overlapping orange rings.
class TeamTaskStatusIcon extends StatelessWidget {
  const TeamTaskStatusIcon({super.key, required this.status, this.size = 20});

  final TeamTaskStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: status.hebrewLabel,
        child: CustomPaint(
          key: Key('team-status-icon-${status.name}'),
          size: Size.square(size),
          painter: _StatusIconPainter(status),
        ),
      );
}

class _StatusIconPainter extends CustomPainter {
  _StatusIconPainter(this.status);

  final TeamTaskStatus status;

  static const Color _grey = Color(0xFF9E9E9E);
  static const Color _darkGrey = Color(0xFF757575);
  static const Color _orange = Color(0xFFEF6C00);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24-unit grid, as the mockup.
    final unit = size.width / 24;
    canvas.save();
    canvas.scale(unit);
    const center = Offset(12, 12);
    Paint ring(Color color, [double width = 2.4]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    Paint fill(Color color) => Paint()..color = color;
    switch (status) {
      case TeamTaskStatus.open:
        canvas.drawCircle(center, 9, ring(_grey));
      case TeamTaskStatus.inProgress:
        canvas.drawCircle(center, 9, ring(TaskStyle.mine));
        // The half on the reading side (right, in Hebrew) filled.
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 5.5),
          -math.pi / 2,
          math.pi,
          true,
          fill(TaskStyle.mine),
        );
      case TeamTaskStatus.done:
        canvas.drawCircle(center, 10.2, fill(TaskStyle.doneDark));
        final tick = Path()
          ..moveTo(7.3, 12.4)
          ..lineTo(10.4, 15.5)
          ..lineTo(16.7, 8.9);
        canvas.drawPath(
          tick,
          ring(Colors.white)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      case TeamTaskStatus.cancelled:
        canvas.drawCircle(center, 9, fill(const Color(0xFFF5F5F5)));
        canvas.drawCircle(center, 9, ring(_darkGrey));
        canvas.drawLine(
          const Offset(6.6, 17.4),
          const Offset(17.4, 6.6),
          ring(_darkGrey)..strokeCap = StrokeCap.round,
        );
      case TeamTaskStatus.duplicate:
        canvas.drawCircle(const Offset(9, 12), 6.6, ring(_orange, 2.2));
        canvas.drawCircle(const Offset(15, 12), 6.6, fill(const Color(0xD9FFF3E0)));
        canvas.drawCircle(const Offset(15, 12), 6.6, ring(_orange, 2.2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StatusIconPainter oldDelegate) => oldDelegate.status != status;
}
