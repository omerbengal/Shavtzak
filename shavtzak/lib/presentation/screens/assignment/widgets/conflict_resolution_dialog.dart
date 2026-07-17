import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../bloc/assignment/models/assignment_conflict.dart';

/// Save-time conflict-resolution dialog — shown when
/// `AssignmentBloc.classifyStagedConflicts` finds one or more staged-vs-DB
/// divergences (the admin's stored baseline no longer matches the current
/// DB for that slot). See
/// docs/superpowers/specs/2026-07-15-assignments-staged-save-design.md
/// ("Conflict handling" / "Resolution dialog (on Save)").
///
/// One row per [AssignmentConflict], each showing its Hebrew "event · role"
/// title (which slot the conflict is about), its description, and a resolution
/// control:
/// - Two-button conflicts offer **דרוס DB** ([ConflictResolution.overrideDb],
///   the default) vs **קח מה-DB** ([ConflictResolution.takeDb]). For
///   [AssignmentConflictType.slotVanished] (quota shrank under a staged
///   fill), the override button is instead labeled **צור מחוץ למכסה** — it
///   still records `overrideDb`; the Save handler creates the assignment
///   and it renders as an off-quota row.
/// - `discardOnly` conflicts (member record fully deleted — not produced by
///   `classifyStagedConflicts` today, see that method's doc; this branch is
///   forward-ready) have no valid override target, so they render a single,
///   fixed **הבנתי — בטל את השינוי** indicator and always resolve to
///   `takeDb`.
///
/// Bulk shortcuts at the top apply to every non-`discardOnly` conflict at
/// once; `discardOnly` rows always stay `takeDb`.
///
/// Returns the resolved `Map<slotKey, ConflictResolution>` via
/// `Navigator.pop` on **שמור**, or `null` on **ביטול** (cancel — nothing is
/// saved, staging stays intact).
class ConflictResolutionDialog extends StatefulWidget {
  final List<AssignmentConflict> conflicts;

  const ConflictResolutionDialog({super.key, required this.conflicts});

  @override
  State<ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<ConflictResolutionDialog> {
  // slotKey -> the admin's current choice. Seeded so every non-discardOnly
  // conflict defaults to overrideDb (the admin's staged edits are
  // intentional), and every discardOnly conflict is pinned to takeDb (it has
  // no override option — see class doc).
  late final Map<String, ConflictResolution> _resolutions;

  @override
  void initState() {
    super.initState();
    _resolutions = {
      for (final conflict in widget.conflicts)
        conflict.slotKey: conflict.discardOnly
            ? ConflictResolution.takeDb
            : ConflictResolution.overrideDb,
    };
  }

  void _setAll(ConflictResolution resolution) {
    setState(() {
      for (final conflict in widget.conflicts) {
        if (conflict.discardOnly) continue; // pinned; not bulk-affected
        _resolutions[conflict.slotKey] = resolution;
      }
    });
  }

  void _setOne(String slotKey, ConflictResolution resolution) {
    setState(() => _resolutions[slotKey] = resolution);
  }

  String _overrideLabel(AssignmentConflict conflict) =>
      conflict.type == AssignmentConflictType.slotVanished
          ? 'צור מחוץ למכסה'
          : 'דרוס DB';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text('נמצאו התנגשויות', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'ה-DB השתנה מאז שערכת את השינויים האלה. בחר/י כיצד לפתור כל התנגשות:',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              _buildBulkRow(),
              const Divider(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final conflict in widget.conflicts)
                        _buildConflictRow(conflict),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('tap:cancel:conflictResolutionDialog');
              Navigator.of(context).pop(null);
            },
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              Logger.action('tap:confirm:conflictResolutionDialog',
                  {'count': _resolutions.length});
              Navigator.of(context)
                  .pop(Map<String, ConflictResolution>.from(_resolutions));
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  /// Bulk shortcuts: "דרוס הכל" / "קח הכל מה-DB", applied to every
  /// non-discardOnly conflict at once.
  Widget _buildBulkRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: () {
            Logger.action('tap:bulkOverride:conflictResolutionDialog');
            _setAll(ConflictResolution.overrideDb);
          },
          child: const Text('דרוס הכל'),
        ),
        OutlinedButton(
          onPressed: () {
            Logger.action('tap:bulkTakeDb:conflictResolutionDialog');
            _setAll(ConflictResolution.takeDb);
          },
          child: const Text('קח הכל מה-DB'),
        ),
      ],
    );
  }

  Widget _buildConflictRow(AssignmentConflict conflict) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "<event name> · <role>" context header so the admin knows WHICH
          // assignment this conflict is about (omitted only if unresolved).
          if (conflict.title != null && conflict.title!.isNotEmpty) ...[
            Text(
              conflict.title!,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
          ],
          Text(conflict.description, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: conflict.discardOnly
                ? _buildDiscardOnlyIndicator()
                : _buildChoiceRow(conflict),
          ),
        ],
      ),
    );
  }

  /// discardOnly (E — member fully deleted): no valid write target, so the
  /// only "choice" is a fixed, non-selectable acknowledgement. The
  /// resolution for this slotKey is pinned to takeDb in [initState]/[_setAll]
  /// — this control never mutates state, it only communicates the fixed
  /// outcome.
  Widget _buildDiscardOnlyIndicator() {
    return Chip(
      avatar: const Icon(Icons.block, size: 16, color: Colors.white),
      label: const Text('הבנתי — בטל את השינוי'),
      backgroundColor: Colors.grey.shade600,
      labelStyle: const TextStyle(color: Colors.white),
    );
  }

  /// Two mutually-exclusive resolution chips for a normal (non-discardOnly)
  /// conflict. The override label is type-dependent (see [_overrideLabel]).
  Widget _buildChoiceRow(AssignmentConflict conflict) {
    final selected = _resolutions[conflict.slotKey];
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: Text(_overrideLabel(conflict)),
          selected: selected == ConflictResolution.overrideDb,
          onSelected: (_) {
            Logger.action('select:override:conflictResolutionDialog',
                {'slotKey': conflict.slotKey});
            _setOne(conflict.slotKey, ConflictResolution.overrideDb);
          },
        ),
        ChoiceChip(
          label: const Text('קח מה-DB'),
          selected: selected == ConflictResolution.takeDb,
          onSelected: (_) {
            Logger.action('select:takeDb:conflictResolutionDialog',
                {'slotKey': conflict.slotKey});
            _setOne(conflict.slotKey, ConflictResolution.takeDb);
          },
        ),
      ],
    );
  }
}
