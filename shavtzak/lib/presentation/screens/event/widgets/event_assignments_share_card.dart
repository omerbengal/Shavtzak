import 'package:flutter/material.dart';

import 'event_assignments_share_models.dart';

class EventAssignmentsShareCard extends StatelessWidget {
  static const double captureWidth = 1080;

  final EventAssignmentsShareData data;

  const EventAssignmentsShareCard({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.white,
        child: Container(
          width: captureWidth,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(data: data),
              const SizedBox(height: 24),
              ..._buildSections(data.sections),
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
    return [
      for (final section in sections) ...[
        _ShareSection(section: section),
        const SizedBox(height: 18),
      ],
    ];
  }
}

class _Header extends StatelessWidget {
  final EventAssignmentsShareData data;

  const _Header({required this.data});

  @override
  Widget build(BuildContext context) {
    final detailLines = [
      data.dateLine,
      if (data.timeLine.trim().isNotEmpty) data.timeLine,
      if (data.participantsLine.trim().isNotEmpty) data.participantsLine,
      if (data.locationLine.trim().isNotEmpty) data.locationLine,
    ];

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
        for (final line in detailLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        if (data.eventNoteLine.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          _EventNote(note: data.eventNoteLine),
        ],
      ],
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

  const _ShareSection({
    required this.section,
    this.isChild = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isChild ? 14 : 18),
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
                child: _ShareRow(row: row),
              ),
          ],
          if (section.hasChildren) ...[
            const SizedBox(height: 14),
            for (final child in section.children) ...[
              _ShareSection(section: child, isChild: true),
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

  const _ShareRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final note = row.noteText?.trim() ?? '';
    final name = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        Flexible(
          child: Text(
            row.memberName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 21,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
        ),
      ],
    );

    if (note.isEmpty) {
      return name;
    }

    // The member's note (hours and/or the assignment note) sits right under
    // their name.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        name,
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 16),
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
