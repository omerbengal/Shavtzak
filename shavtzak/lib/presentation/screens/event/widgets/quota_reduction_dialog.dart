import 'package:flutter/material.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../core/debug/logger.dart';
import '../quota_reduction_analyzer.dart';

/// Dialog for selecting which assignments to remove when reducing role quotas
class QuotaReductionDialog extends StatefulWidget {
  final List<RoleQuotaConflict> conflicts;

  const QuotaReductionDialog({
    super.key,
    required this.conflicts,
  });

  /// Show the quota reduction dialog
  /// Returns list of assignment IDs to delete, or null if cancelled
  static Future<List<String>?> show(
    BuildContext context,
    List<RoleQuotaConflict> conflicts,
  ) async {
    return await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => QuotaReductionDialog(conflicts: conflicts),
    );
  }

  @override
  State<QuotaReductionDialog> createState() => _QuotaReductionDialogState();
}

class _QuotaReductionDialogState extends State<QuotaReductionDialog> {
  // Map<roleKey, Set<assignmentId>>
  final Map<String, Set<String>> _selectedAssignments = {};

  @override
  void initState() {
    super.initState();
    // Initialize selection state for each role
    for (final conflict in widget.conflicts) {
      _selectedAssignments[conflict.roleKey] = {};
    }
  }

  /// Check if the current selection is valid
  /// User must select exactly the number of assignments that need to be removed per role
  bool _isValidSelection() {
    for (final conflict in widget.conflicts) {
      final selected = _selectedAssignments[conflict.roleKey]?.length ?? 0;
      final required = conflict.removalCount;
      if (selected != required) return false;
    }
    return true;
  }

  /// Get validation message for current selection state
  String _getValidationMessage() {
    int totalSelected = 0;
    int totalRequired = 0;

    for (final conflict in widget.conflicts) {
      final selected = _selectedAssignments[conflict.roleKey]?.length ?? 0;
      totalSelected += selected;
      totalRequired += conflict.removalCount;
    }

    final diff = totalRequired - totalSelected;

    if (diff > 0) {
      return 'יש לבחור עוד $diff שיבוצים';
    } else if (diff < 0) {
      return 'בחרת יותר מדי - הסר ${-diff} שיבוצים';
    } else {
      // Check if all roles are valid
      if (_isValidSelection()) {
        return '✓ בחירה תקינה';
      } else {
        return 'יש לבחור את המספר הנכון עבור כל תפקיד';
      }
    }
  }

  /// Get color for validation message
  Color _getValidationColor() {
    if (_isValidSelection()) {
      return Colors.green;
    } else {
      return Colors.orange;
    }
  }

  /// Get all selected assignment IDs
  List<String> _getAllSelectedIds() {
    final allIds = <String>[];
    for (final selectedSet in _selectedAssignments.values) {
      allIds.addAll(selectedSet);
    }
    return allIds;
  }

  @override
  Widget build(BuildContext context) {
    final totalToRemove = widget.conflicts.fold<int>(
      0,
      (sum, conflict) => sum + conflict.removalCount,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber,
              color: Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'צמצום תפקידים - בחר שיבוצים למחיקה',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Explanation
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'עליך להסיר $totalToRemove שיבוצים עקב הקטנת מכסות:',
                  style: const TextStyle(fontSize: 14),
                ),
              ),

              // Scrollable content with role sections
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final conflict in widget.conflicts) ...[
                        _buildRoleSection(conflict),
                        if (conflict != widget.conflicts.last)
                          const Divider(height: 24),
                      ],
                    ],
                  ),
                ),
              ),

              // Validation message
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getValidationColor().withAlpha(25),
                  border: Border.all(
                    color: _getValidationColor(),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isValidSelection() ? Icons.check_circle : Icons.info,
                      color: _getValidationColor(),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getValidationMessage(),
                        style: TextStyle(
                          color: _getValidationColor(),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('tap:cancel:quotaReductionDialog');
              Navigator.of(context).pop(null);
            },
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _isValidSelection()
                ? () {
                    Logger.action('tap:confirmQuotaReduction', {
                      'count': _getAllSelectedIds().length,
                    });
                    Navigator.of(context).pop(_getAllSelectedIds());
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('מחק ושמור אירוע'),
          ),
        ],
      ),
    );
  }

  /// Build section for one role's conflicts
  Widget _buildRoleSection(RoleQuotaConflict conflict) {
    // Get the Hebrew name for the role
    // Try to use RoleType enum if available, otherwise use roleKey directly
    final String roleHebrewName = conflict.roleType?.hebrewName ?? conflict.roleKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Role header
        Text(
          roleHebrewName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),

        // Quota change info
        Text(
          'מכסה חדשה: ${conflict.newQuota} (ירדה מ-${conflict.oldQuota})',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),

        // Required removal count
        Text(
          'בחר ${conflict.removalCount} שיבוצים למחיקה מתוך ${conflict.assignmentCandidates.length}:',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 8),

        // Assignment checkboxes
        ...conflict.assignmentCandidates.map((assignment) {
          final isSelected = _selectedAssignments[conflict.roleKey]
                  ?.contains(assignment.id) ??
              false;

          return CheckboxListTile(
            value: isSelected,
            onChanged: (bool? value) {
              Logger.action('toggle:assignmentSelection', {
                'assignmentId': assignment.id,
                'roleKey': conflict.roleKey,
                'on': value ?? false,
              });
              setState(() {
                if (value == true) {
                  _selectedAssignments[conflict.roleKey]!.add(assignment.id);
                } else {
                  _selectedAssignments[conflict.roleKey]!
                      .remove(assignment.id);
                }
              });
            },
            title: Text(
              assignment.teamMemberName ?? 'שם לא ידוע',
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: assignment.teamMember != null
                ? Text(
                    'משבצת ${assignment.slotIndex + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  )
                : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          );
        }),
      ],
    );
  }
}
