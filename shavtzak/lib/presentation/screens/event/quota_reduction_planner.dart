import '../../../core/utils/slot_annotations.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/slot_annotation.dart';

/// What occupies one row of a role, cheapest-to-lose first. The whole point of
/// a quota reduction is to pick victims in this order.
enum QuotaRowKind {
  /// Nothing at all — no assignment, no note. Free to delete.
  clean,

  /// Empty, but carries a gap note/label (saved OR staged-but-unsaved).
  noted,

  /// Someone is assigned to it.
  assigned,
}

/// One row of a role at its CURRENT (pre-reduction) slot index.
class QuotaRow {
  final int slotIndex;
  final QuotaRowKind kind;

  /// The note shown on a [QuotaRowKind.noted] row — the staged (unsaved) value
  /// when there is one, else the stored value. Null for other kinds.
  final SlotAnnotation? annotation;

  /// True when [annotation] is an unsaved staged edit rather than the stored
  /// value — the dialog says so, since deleting the row discards a draft.
  final bool annotationIsStaged;

  /// The assignment on a [QuotaRowKind.assigned] row; null otherwise.
  final Assignment? assignment;

  const QuotaRow({
    required this.slotIndex,
    required this.kind,
    this.annotation,
    this.annotationIsStaged = false,
    this.assignment,
  });
}

/// How a role's quota reduction resolves: which rows die outright, and whether
/// the admin still has to choose some.
class RoleReductionPlan {
  final String roleKey;
  final int oldQuota;
  final int newQuota;

  /// Rows removed with no prompt — clean rows first (rung 1), plus every noted
  /// row when an ASSIGNMENT has to go anyway (rung 3 consumes all empties, so
  /// there is nothing left to choose between).
  final Set<int> autoDeletedIndices;

  /// Rung 2: noted rows the admin must choose between, and how many of them
  /// have to go. Empty when no choice is needed.
  final List<QuotaRow> notedCandidates;
  final int notedToRemove;

  /// Rung 3: assignments that must go, delegated to the existing
  /// QuotaReductionDialog. 0 when every survivor fits.
  final int assignmentsToRemove;

  const RoleReductionPlan({
    required this.roleKey,
    required this.oldQuota,
    required this.newQuota,
    required this.autoDeletedIndices,
    required this.notedCandidates,
    required this.notedToRemove,
    required this.assignmentsToRemove,
  });

  /// Rung 2 applies: the admin picks which noted row(s) to lose.
  bool get needsNoteChoice => notedToRemove > 0;

  /// Rung 3 applies: the existing assignment-removal dialog runs.
  bool get needsAssignmentChoice => assignmentsToRemove > 0;

  /// Nothing to ask — [autoDeletedIndices] is the whole answer.
  bool get isSilent => !needsNoteChoice && !needsAssignmentChoice;
}

/// Classify a role's current rows [0, quota).
///
/// [stagedNoteIndices] carries slots holding an UNSAVED staged note; they count
/// as [QuotaRowKind.noted] exactly like a stored one, so reducing the quota can
/// never silently bin a note the admin just typed. [stagedNoteValues] supplies
/// the text to show for them. A staged CLEAR (an index in [stagedNoteIndices]
/// with no value) makes the row clean again — the admin already asked for that
/// note to go.
List<QuotaRow> classifyRoleRows({
  required String roleKey,
  required int quota,
  required List<Assignment> assignments,
  required Map<String, SlotAnnotation> slotAnnotations,
  Set<int> stagedNoteIndices = const {},
  Map<int, SlotAnnotation> stagedNoteValues = const {},
}) {
  final byIndex = <int, Assignment>{
    for (final a in assignments)
      if (a.roleType == roleKey) a.slotIndex: a,
  };

  final rows = <QuotaRow>[];
  for (var i = 0; i < quota; i++) {
    final assignment = byIndex[i];
    if (assignment != null) {
      rows.add(QuotaRow(
          slotIndex: i,
          kind: QuotaRowKind.assigned,
          assignment: assignment));
      continue;
    }
    final staged = stagedNoteValues[i];
    final stored = slotAnnotations[slotAnnotationKey(roleKey, i)];
    // A staged edit wins over the stored value — it is what the admin sees.
    final SlotAnnotation? shown;
    final bool isStaged;
    if (stagedNoteIndices.contains(i)) {
      shown = (staged != null && !staged.isEmpty) ? staged : null;
      isStaged = true;
    } else {
      shown = (stored != null && !stored.isEmpty) ? stored : null;
      isStaged = false;
    }
    rows.add(shown == null
        ? QuotaRow(slotIndex: i, kind: QuotaRowKind.clean)
        : QuotaRow(
            slotIndex: i,
            kind: QuotaRowKind.noted,
            annotation: shown,
            annotationIsStaged: isStaged));
  }
  return rows;
}

/// Decide which rows a reduction from [oldQuota] to [newQuota] consumes.
///
/// Strict priority — always spend the cheapest rows first:
///   1. clean rows (no assignment, no note)  → deleted silently
///   2. noted empty rows                     → the admin chooses which
///   3. assigned rows                        → the existing dialog chooses
///
/// Clean rows are spent HIGHEST INDEX FIRST so the surviving rows keep their
/// positions wherever possible (deleting the bottom row shifts nothing).
///
/// When an assignment has to go (rung 3), every empty row — clean AND noted —
/// is already consumed by definition (that is what makes rung 3 necessary), so
/// there is nothing to choose between and the noted ones go silently with them.
RoleReductionPlan planRoleQuotaReduction({
  required String roleKey,
  required int oldQuota,
  required int newQuota,
  required List<QuotaRow> rows,
}) {
  final removeCount = oldQuota - newQuota;
  if (removeCount <= 0) {
    return RoleReductionPlan(
      roleKey: roleKey,
      oldQuota: oldQuota,
      newQuota: newQuota,
      autoDeletedIndices: const {},
      notedCandidates: const [],
      notedToRemove: 0,
      assignmentsToRemove: 0,
    );
  }

  final clean = [
    for (final r in rows)
      if (r.kind == QuotaRowKind.clean) r
  ]..sort((a, b) => b.slotIndex.compareTo(a.slotIndex)); // highest first
  final noted = [
    for (final r in rows)
      if (r.kind == QuotaRowKind.noted) r
  ]..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
  final assignedCount =
      rows.where((r) => r.kind == QuotaRowKind.assigned).length;

  // Rung 3: more assignments than the new quota holds. Every empty row is
  // consumed, and the dialog picks which assignments join them.
  if (assignedCount > newQuota) {
    return RoleReductionPlan(
      roleKey: roleKey,
      oldQuota: oldQuota,
      newQuota: newQuota,
      autoDeletedIndices: {
        for (final r in [...clean, ...noted]) r.slotIndex,
      },
      notedCandidates: const [],
      notedToRemove: 0,
      assignmentsToRemove: assignedCount - newQuota,
    );
  }

  // Rung 1: enough clean rows to absorb the whole reduction.
  final autoDeleted = <int>{};
  for (final r in clean) {
    if (autoDeleted.length == removeCount) break;
    autoDeleted.add(r.slotIndex);
  }
  final stillToRemove = removeCount - autoDeleted.length;

  // Rung 2: the rest has to come out of the noted rows — the admin's choice.
  return RoleReductionPlan(
    roleKey: roleKey,
    oldQuota: oldQuota,
    newQuota: newQuota,
    autoDeletedIndices: autoDeleted,
    notedCandidates: stillToRemove > 0 ? noted : const [],
    notedToRemove: stillToRemove,
    assignmentsToRemove: 0,
  );
}

/// The new slot index of [slotIndex] once [deletedIndices] are gone —
/// visual-order-preserving (Model B): shift up by the number of deleted rows
/// BELOW it, so gaps stay where they are and rows never leapfrog each other.
/// The same mapping `AssignmentBloc._reindexRoleAfterDeletion` and
/// `computeNoteReindexAfterDeletion` use, so assignments and notes move in
/// lockstep no matter which screen drove the deletion.
int shiftedSlotIndex(int slotIndex, Set<int> deletedIndices) =>
    slotIndex - deletedIndices.where((d) => d < slotIndex).length;
