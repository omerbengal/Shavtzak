import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/debug/logger.dart';
import '../../../../domain/entities/participant_group.dart';

const int _maxParticipantRows = 10;
const int _maxLabelLength = 20;

/// The "כמות משתתפים" section of the event form: one row per נגלה, each an
/// optional label plus a count, with a "+" to append and a "✕" to remove.
///
/// Call [ParticipantGroupRowsState.toGroups] on save to collect the rows.
class ParticipantGroupRows extends StatefulWidget {
  final List<ParticipantGroup> initialGroups;

  /// Fired on any edit, so the host form can mark itself dirty.
  final VoidCallback onChanged;

  const ParticipantGroupRows({
    super.key,
    required this.initialGroups,
    required this.onChanged,
  });

  @override
  State<ParticipantGroupRows> createState() => ParticipantGroupRowsState();
}

class ParticipantGroupRowsState extends State<ParticipantGroupRows> {
  final List<_ParticipantRow> _rows = [];

  @override
  void initState() {
    super.initState();
    for (final group in widget.initialGroups) {
      final row = _ParticipantRow();
      row.label.text = group.normalizedLabel ?? '';
      row.count.text = group.count.toString();
      _rows.add(row);
    }
    // Always show at least one row, so the common single-number case needs no
    // extra tap. An untouched empty row is dropped by toGroups().
    if (_rows.isEmpty) {
      _rows.add(_ParticipantRow());
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Collect the rows into groups. A row with no count is dropped — a row that
  /// has a label but no count is caught first by the count field's validator.
  List<ParticipantGroup> toGroups() {
    final groups = <ParticipantGroup>[];
    for (final row in _rows) {
      final count = int.tryParse(row.count.text.trim());
      if (count == null) continue;
      final label = row.label.text.trim();
      groups.add(ParticipantGroup(
        label: label.isEmpty ? null : label,
        count: count,
      ));
    }
    return groups;
  }

  void _addRow() {
    Logger.action('tap:addParticipantRow', {'count': _rows.length});
    setState(() => _rows.add(_ParticipantRow()));
    widget.onChanged();
  }

  void _removeRow(int index) {
    Logger.action('tap:removeParticipantRow', {'index': index});
    final removed = _rows.removeAt(index);
    if (_rows.isEmpty) {
      _rows.add(_ParticipantRow());
    }
    setState(() {});
    widget.onChanged();
    // Dispose only after the rebuild has detached the field: during the current
    // frame a live EditableText still holds these controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'כמות משתתפים (אופציונלי)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            // Keyed by row identity so removing a middle row does not leave the
            // field below it holding the removed row's form state.
            key: ObjectKey(_rows[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _rows[i].label,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_maxLabelLength),
                    ],
                    onChanged: (_) {
                      // Rebuild so the count validator re-reads this label.
                      setState(() {});
                      widget.onChanged();
                    },
                    decoration: InputDecoration(
                      labelText: 'תווית (אופציונלי)',
                      hintText: 'נגלה ${i + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _rows[i].count,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(7),
                    ],
                    onChanged: (_) => widget.onChanged(),
                    validator: (value) {
                      final hasCount = (value ?? '').trim().isNotEmpty;
                      final hasLabel = _rows[i].label.text.trim().isNotEmpty;
                      // A fully empty row is fine — it is dropped on save. A
                      // labeled row without a count is a mistake worth flagging.
                      if (hasLabel && !hasCount) {
                        return 'יש להזין כמות';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'כמות',
                      // A full "e.g." phrase, not a bare number: InputDecorator
                      // keeps the hint's Text widget mounted (opacity-faded, not
                      // removed) even once the field has a value, so a bare
                      // '500' would collide with find.text('500') in tests (and
                      // visually, with a real row whose count is 500).
                      hintText: 'לדוגמה: 500',
                      prefixIcon: Icon(Icons.groups),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  tooltip: 'הסר נגלה',
                  onPressed: () => _removeRow(i),
                ),
              ],
            ),
          ),
        if (_rows.length < _maxParticipantRows)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add),
              label: const Text('הוסף נגלה'),
            ),
          ),
      ],
    );
  }
}

class _ParticipantRow {
  final TextEditingController label = TextEditingController();
  final TextEditingController count = TextEditingController();

  void dispose() {
    label.dispose();
    count.dispose();
  }
}
