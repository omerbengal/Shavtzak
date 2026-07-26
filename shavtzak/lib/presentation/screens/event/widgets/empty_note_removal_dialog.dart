import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../domain/entities/assignment_label.dart';
import '../../../widgets/assignment_label_chip.dart';
import '../quota_reduction_planner.dart';

/// One role's rung-2 choice: which of its EMPTY-but-annotated rows to give up
/// when a quota reduction has run out of clean rows to spend.
class EmptyNoteRemovalRequest {
  final String roleKey;
  final String roleHebrewName;
  final List<QuotaRow> candidates;

  /// How many of [candidates] must be selected.
  final int countToRemove;

  const EmptyNoteRemovalRequest({
    required this.roleKey,
    required this.roleHebrewName,
    required this.candidates,
    required this.countToRemove,
  });
}

/// Asks which annotated empty rows a quota reduction should consume.
///
/// Only reached when the reduction cannot be absorbed by clean rows (those go
/// silently) and does not require deleting an assignment (that is
/// [QuotaReductionDialog]'s job). Deliberately shows the note text and label so
/// the admin is choosing between contents, not slot numbers — the whole reason
/// this prompt exists rather than "the app quietly deletes the highest note".
///
/// Returns the chosen slot indices per role, or null when cancelled (the caller
/// reverts the quota, exactly as the assignment dialog does).
class EmptyNoteRemovalDialog extends StatefulWidget {
  final List<EmptyNoteRemovalRequest> requests;
  final List<AssignmentLabel> labels;

  const EmptyNoteRemovalDialog({
    super.key,
    required this.requests,
    required this.labels,
  });

  static Future<Map<String, Set<int>>?> show(
    BuildContext context,
    List<EmptyNoteRemovalRequest> requests,
    List<AssignmentLabel> labels,
  ) {
    return showDialog<Map<String, Set<int>>>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          EmptyNoteRemovalDialog(requests: requests, labels: labels),
    );
  }

  @override
  State<EmptyNoteRemovalDialog> createState() => _EmptyNoteRemovalDialogState();
}

class _EmptyNoteRemovalDialogState extends State<EmptyNoteRemovalDialog> {
  final Map<String, Set<int>> _selected = {};

  @override
  void initState() {
    super.initState();
    for (final r in widget.requests) {
      _selected[r.roleKey] = {};
      // A role with exactly as many candidates as it must lose has no real
      // choice — preselect them so the admin only has to confirm.
      if (r.candidates.length == r.countToRemove) {
        _selected[r.roleKey] = r.candidates.map((c) => c.slotIndex).toSet();
      }
    }
  }

  bool get _isValid => widget.requests.every(
      (r) => (_selected[r.roleKey]?.length ?? 0) == r.countToRemove);

  String get _validationMessage {
    var remaining = 0;
    for (final r in widget.requests) {
      remaining += r.countToRemove - (_selected[r.roleKey]?.length ?? 0);
    }
    if (remaining > 0) return 'יש לבחור עוד $remaining שורות';
    if (remaining < 0) return 'בחרת יותר מדי – בטל ${-remaining}';
    return '✓ בחירה תקינה';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('אילו שורות עם הערה להסיר?'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'הקטנת המכסה מחייבת להסיר שורות ריקות שיש עליהן הערה. '
                  'בחר/י אילו – ההערה שלהן תימחק.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                for (final request in widget.requests) ...[
                  Text(
                    '${request.roleHebrewName} — יש לבחור '
                    '${request.countToRemove} מתוך ${request.candidates.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  for (final candidate in request.candidates)
                    _buildCandidateTile(request, candidate),
                  const SizedBox(height: 12),
                ],
                Text(
                  _validationMessage,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isValid ? Colors.green.shade700 : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('cancel:emptyNoteRemovalDialog');
              Navigator.of(context).pop();
            },
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _isValid
                ? () {
                    Logger.action('confirm:emptyNoteRemovalDialog', {
                      'selected': _selected
                          .map((k, v) => MapEntry(k, v.toList()..sort())),
                    });
                    Navigator.of(context).pop(_selected);
                  }
                : null,
            child: const Text('אישור'),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateTile(
      EmptyNoteRemovalRequest request, QuotaRow candidate) {
    final selected =
        _selected[request.roleKey]?.contains(candidate.slotIndex) ?? false;
    final annotation = candidate.annotation!;
    final label = annotation.labelId == null
        ? null
        : widget.labels.firstWhereOrNull((l) => l.id == annotation.labelId);
    final note = annotation.note.trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: selected ? Colors.red.shade50 : null,
      child: CheckboxListTile(
        value: selected,
        onChanged: (value) {
          setState(() {
            final set = _selected.putIfAbsent(request.roleKey, () => {});
            if (value == true) {
              set.add(candidate.slotIndex);
            } else {
              set.remove(candidate.slotIndex);
            }
          });
        },
        title: Row(
          children: [
            Text('שורה ${candidate.slotIndex + 1}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            if (candidate.annotationIsStaged) ...[
              const SizedBox(width: 6),
              // The admin typed this and has not saved it yet — say so, or
              // deleting the row looks like it ate something that was on screen.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('טרם נשמר',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: AssignmentLabelChip(label: label, fontSize: 10),
              ),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(note, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      ),
    );
  }
}
