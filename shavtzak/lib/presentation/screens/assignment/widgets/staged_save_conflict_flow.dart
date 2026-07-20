import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../bloc/assignment/assignment_bloc.dart';
import '../../../bloc/assignment/models/assignment_conflict.dart';
import '../models/assignment_slot.dart';
import 'conflict_resolution_dialog.dart';

/// Classify staged-vs-DB conflicts and, if any exist, show the
/// [ConflictResolutionDialog] and await the admin's resolutions.
///
/// Returns:
/// - `const {}` (empty map) when there are no conflicts — nothing to
///   resolve; the caller should proceed straight to Save.
/// - the chosen `Map<slotKey, ConflictResolution>` once the admin confirms
///   the dialog.
/// - `null` if the admin cancelled the dialog — the caller MUST NOT save;
///   staging stays fully intact.
///
/// Shared by the on-screen Save button (`assignment_list_screen.dart`'s
/// `_onSavePressed`) and the tab-switch leave-guard
/// (`swipeable_page_view.dart`'s `_onBottomNavTapped`, the
/// `LeaveDecision.save` branch) so BOTH paths resolve staged-vs-DB
/// conflicts identically — see docs/superpowers/specs/
/// 2026-07-15-assignments-staged-save-design.md ("Conflict handling" /
/// "Resolution dialog (on Save)").
Future<Map<String, ConflictResolution>?> resolveStagedConflictsForSave(
  BuildContext context,
  AssignmentBloc bloc,
  List<AssignmentSlot> slots,
) async {
  final conflicts = bloc.classifyStagedConflicts(slots);
  if (conflicts.isEmpty) return const {};

  Logger.action('open:conflictResolutionDialog', {'count': conflicts.length});
  final result = await showDialog<Map<String, ConflictResolution>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ConflictResolutionDialog(conflicts: conflicts),
  );
  if (result == null) {
    Logger.action('tap:cancel:conflictResolutionDialog');
    return null; // cancelled — nothing saved, staging intact
  }
  return result;
}
