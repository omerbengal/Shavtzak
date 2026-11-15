import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  static const double maxListWidth = TaskStyle.readableWidth;

  // Design A (Omer, round 3): a card per link, a status circle per row.
  static const double statusIconSize = 20;
  static const double subtaskIconSize = 16;
  static const double avatarSize = 24;
  static const double subtaskAvatarSize = 20;

  /// A row under the mouse (desktop): a light blue, clearly seen on white.
  static const Color rowHover = TaskStyle.currentLight;
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
