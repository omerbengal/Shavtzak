import 'package:flutter/material.dart';

/// Save / discard-all cluster for the assignments screen's staged-save
/// workflow. Rendered beside the existing manual-add FAB — see
/// docs/superpowers/specs/2026-07-15-assignments-staged-save-design.md
/// ("UI controls").
///
/// - **Clean** ([stagedCount] == 0): Save is visible but disabled (greyed,
///   `onPressed: null`); no count suffix; the "בטל הכל" discard-all control
///   is not shown at all.
/// - **Dirty** ([stagedCount] > 0): Save is enabled, labeled
///   "שמור · N", and a "בטל הכל" control appears beside it.
class AssignmentSaveBar extends StatelessWidget {
  final int stagedCount;
  final VoidCallback onSave;
  final VoidCallback onDiscardAll;

  const AssignmentSaveBar({
    super.key,
    required this.stagedCount,
    required this.onSave,
    required this.onDiscardAll,
  });

  bool get _isDirty => stagedCount > 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isDirty) ...[
            OutlinedButton(
              onPressed: onDiscardAll,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                backgroundColor: Colors.white,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: const Text('בטל הכל'),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: _isDirty ? onSave : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              elevation: _isDirty ? 3 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            icon: const Icon(Icons.save),
            label: Text(_isDirty ? 'שמור · $stagedCount' : 'שמור'),
          ),
        ],
      ),
    );
  }
}
