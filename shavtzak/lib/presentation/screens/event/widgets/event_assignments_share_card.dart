import 'package:flutter/material.dart';

import 'event_assignments_share_models.dart';

class EventAssignmentsShareCard extends StatelessWidget {
  static const double captureWidth = 1080;

  final EventAssignmentsShareData data;

  /// Layout width; the export always uses [captureWidth].
  final double width;

  /// The "מי איתי" view only: this member's row reads "אני" in green, and
  /// with [onCall] every row gets a phone mark (greyed out on "אני") and
  /// a row with a number is tapped as a whole to call (the picture is shrunk,
  /// so a button alone would be too small for a finger).
  final String? currentMemberId;
  final void Function(EventAssignmentsShareRow row)? onCall;

  /// 1 = the export's single column of role cards; 2 = two side by side
  /// (the "מי איתי" view, so the whole picture fits a phone at a readable
  /// size). The header and missing-roles line stay full width.
  final int columns;

  const EventAssignmentsShareCard({
    super.key,
    required this.data,
    this.width = captureWidth,
    this.currentMemberId,
    this.onCall,
    this.columns = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.white,
        child: Container(
          width: width,
          color: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: columns > 1 ? 4 : 48,
            vertical: columns > 1 ? 16 : 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(data: data),
              const SizedBox(height: 24),
              ..._buildSections(data.sections),
              if (data.missingRolesLine case final missing?) ...[
                _MissingRoles(text: missing),
                const SizedBox(height: 18),
              ],
              const SizedBox(height: 20),
              const Text(
                'נוצר משבצק',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections(List<EventAssignmentsShareSection> sections) {
    final compact = columns > 1;
    List<Widget> stack(Iterable<EventAssignmentsShareSection> part) => [
          for (final section in part) ...[
            _ShareSection(
              section: section,
              compact: compact,
              currentMemberId: currentMemberId,
              onCall: onCall,
            ),
            SizedBox(height: compact ? 12 : 18),
          ],
        ];
    if (columns < 2 || sections.length < 2) return stack(sections);
    // Reading order kept: the first cards fill the right column top to
    // bottom, the next ones the column to its left, and so on, cut where the
    // columns come out most even.
    final parts = splitColumns(sections, columns);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, part) in parts.indexed) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: stack(part),
              ),
            ),
          ],
        ],
      ),
    ];
  }

  /// [sections], in order, cut into at most [columns] runs whose estimated
  /// heights are as even as possible (the tallest run as short as it can be).
  static List<List<EventAssignmentsShareSection>> splitColumns(
    List<EventAssignmentsShareSection> sections,
    int columns,
  ) {
    double weight(EventAssignmentsShareSection section) =>
        2 +
        section.rows.length +
        section.rows
                .where((row) => (row.noteText ?? '').trim().isNotEmpty)
                .length *
            0.8 +
        section.children.fold<double>(0, (sum, child) => sum + weight(child));
    final n = sections.length;
    final k = columns.clamp(1, n);
    final prefix = <double>[0];
    for (final section in sections) {
      prefix.add(prefix.last + weight(section));
    }
    double run(int from, int to) => prefix[to] - prefix[from];
    // best[c][i]: the tallest run when the first i sections fill c columns.
    final best = List.generate(
        k + 1, (_) => List<double>.filled(n + 1, double.infinity));
    final cut = List.generate(k + 1, (_) => List<int>.filled(n + 1, 0));
    best[0][0] = 0;
    for (var c = 1; c <= k; c++) {
      for (var i = c; i <= n; i++) {
        for (var j = c - 1; j < i; j++) {
          final tallest =
              best[c - 1][j] > run(j, i) ? best[c - 1][j] : run(j, i);
          if (tallest < best[c][i]) {
            best[c][i] = tallest;
            cut[c][i] = j;
          }
        }
      }
    }
    final parts = <List<EventAssignmentsShareSection>>[];
    var end = n;
    for (var c = k; c >= 1; c--) {
      final start = cut[c][end];
      parts.insert(0, sections.sublist(start, end));
      end = start;
    }
    return parts;
  }
}

class _Header extends StatelessWidget {
  final EventAssignmentsShareData data;

  const _Header({required this.data});

  @override
  Widget build(BuildContext context) {
    final detailLines = data.detailLines;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          data.eventName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 36,
            fontWeight: FontWeight.w800,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 12),
        // Each detail line stays on one line, shrunk to fit when long.
        for (final line in detailLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                line,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ),
        if (data.eventNoteLine.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          _EventNote(note: data.eventNoteLine),
        ],
        if (data.itemsLine case final items?) ...[
          const SizedBox(height: 10),
          Text(
            items,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _MissingRoles extends StatelessWidget {
  final String text;

  const _MissingRoles({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.orange.shade900,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _EventNote extends StatelessWidget {
  final String note;

  const _EventNote({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 22,
            color: Colors.amber.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontSize: 19,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareSection extends StatelessWidget {
  final EventAssignmentsShareSection section;
  final bool isChild;
  final bool compact;
  final String? currentMemberId;
  final void Function(EventAssignmentsShareRow row)? onCall;

  const _ShareSection({
    required this.section,
    this.isChild = false,
    this.compact = false,
    this.currentMemberId,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : (isChild ? 14 : 18)),
      decoration: BoxDecoration(
        color: isChild ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            section.title,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: isChild ? 21 : 24,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (section.rows.isNotEmpty || section.hasChildren) ...[
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color:
                  isChild ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1),
            ),
          ],
          if (section.rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final row in section.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ShareRow(
                  row: row,
                  compact: compact,
                  isMe: currentMemberId != null &&
                      row.memberId == currentMemberId,
                  onCall: onCall,
                ),
              ),
          ],
          if (section.hasChildren) ...[
            const SizedBox(height: 14),
            for (final child in section.children) ...[
              _ShareSection(
                section: child,
                isChild: true,
                compact: compact,
                currentMemberId: currentMemberId,
                onCall: onCall,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  final EventAssignmentsShareRow row;
  final bool isMe;
  final void Function(EventAssignmentsShareRow row)? onCall;

  /// Narrow columns: no bullet, and a long name wraps to a second line.
  final bool compact;

  const _ShareRow({
    required this.row,
    this.isMe = false,
    this.onCall,
    this.compact = false,
  });

  static const _me = Color(0xFF15803D);

  @override
  Widget build(BuildContext context) {
    final note = row.noteText?.trim() ?? '';
    final call = onCall;
    final nameText = Text(
      isMe ? 'אני' : row.memberName,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isMe ? _me : const Color(0xFF111827),
        fontSize: 21,
        fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
        height: 1.25,
      ),
    );
    final name = Row(
      mainAxisSize: call == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (!compact) ...[
          const Text(
            '•',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (call == null)
          Flexible(child: nameText)
        else ...[
          Expanded(child: nameText),
          _PhoneMark(callable: !isMe && row.phoneNumber != null, isMe: isMe),
        ],
      ],
    );

    final content = note.isEmpty ? name : _withNote(name, note);
    if (call == null || isMe || row.phoneNumber == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('call-${row.memberId}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => call(row),
        child: content,
      ),
    );
  }

  /// The member's note (hours and/or the assignment note) sits right under
  /// their name.
  Widget _withNote(Widget name, String note) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        name,
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsetsDirectional.only(start: compact ? 0 : 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                border: Border.all(color: Colors.purple.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                note,
                style: TextStyle(
                  color: Colors.purple.shade900,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The "מי איתי" view's phone mark at the end of a row: blue when the row
/// calls, grey on the viewer's own row, empty when there is no number.
class _PhoneMark extends StatelessWidget {
  final bool callable;
  final bool isMe;

  const _PhoneMark({required this.callable, required this.isMe});

  static const double _size = 30;

  /// A pill, wider than tall: more of it to aim a finger at.
  static const double _width = 56;
  static const double _icon = 24;

  @override
  Widget build(BuildContext context) {
    if (!callable && !isMe) return const SizedBox(width: _width);
    return Container(
      width: _width,
      height: _size,
      decoration: BoxDecoration(
        color: isMe ? null : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(_size / 2),
      ),
      child: Icon(
        Icons.phone,
        size: _icon,
        color: isMe ? Colors.grey.shade400 : Colors.blue.shade700,
      ),
    );
  }
}
