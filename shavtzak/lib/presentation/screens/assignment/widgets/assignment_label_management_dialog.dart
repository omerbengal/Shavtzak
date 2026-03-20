import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/assignment_label_palette.dart';
import '../../../../data/repositories/assignment_label_repository.dart';
import '../../../../data/repositories/assignment_repository.dart';
import '../../../../domain/entities/assignment_label.dart';
import '../../../widgets/loading_overlay.dart';

class AssignmentLabelManagementDialog extends StatefulWidget {
  const AssignmentLabelManagementDialog({super.key});

  @override
  State<AssignmentLabelManagementDialog> createState() =>
      _AssignmentLabelManagementDialogState();
}

class _AssignmentLabelManagementDialogState
    extends State<AssignmentLabelManagementDialog> {
  bool _showArchive = false;
  bool _isLoading = false;
  List<AssignmentLabel>? _pendingReorderedLabels;
  String? _lastLabelsSignature;

  AssignmentLabelRepository get _repository =>
      context.read<AssignmentLabelRepository>();

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _runMutation(
    Future<void> Function() action, {
    String concurrentMessage = 'פעולה אחרת עדיין מתבצעת',
  }) async {
    if (_isLoading) {
      _showError(concurrentMessage);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pendingReorderedLabels = null;
      });
      _showError(_extractErrorMessage(e));
    }
  }

  void _handleIncomingLabels(List<AssignmentLabel> labels) {
    final signature = labels
        .map(
          (label) =>
              '${label.id}:${label.sortOrder}:${label.isActive}:${label.hebrewName}:${label.color}:${label.updatedAt.microsecondsSinceEpoch}',
        )
        .join('|');

    if (signature == _lastLabelsSignature) {
      return;
    }
    _lastLabelsSignature = signature;

    if (!_isLoading && _pendingReorderedLabels == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pendingReorderedLabels = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showArchive ? 'ארכיון לייבלים' : 'ניהול לייבלים',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon:
                                Icon(_showArchive ? Icons.list : Icons.history),
                            onPressed: () {
                              setState(() {
                                _showArchive = !_showArchive;
                                _pendingReorderedLabels = null;
                              });
                            },
                            tooltip: _showArchive
                                ? 'חזרה לרשימה הראשית'
                                : 'צפייה בארכיון',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<List<AssignmentLabel>>(
                      stream: _repository.watchAssignmentLabels(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'שגיאה בטעינת לייבלים',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }

                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final labels = snapshot.data!;
                        _handleIncomingLabels(labels);

                        return _showArchive
                            ? _buildArchiveView(labels)
                            : _buildMainView(labels);
                      },
                    ),
                  ),
                  if (!_showArchive)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showAddOrEditLabelDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('צור לייבל חדש'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          LoadingOverlay(isLoading: _isLoading, message: 'מעבד...'),
        ],
      ),
    );
  }

  Widget _buildMainView(List<AssignmentLabel> allLabels) {
    final activeLabels = _pendingReorderedLabels ??
        allLabels.where((label) => label.isActive).toList();

    if (activeLabels.isEmpty) {
      return const Center(
        child: Text('אין לייבלים זמינים'),
      );
    }

    return ReorderableListView.builder(
      itemCount: activeLabels.length,
      onReorder: (oldIndex, newIndex) {
        final reordered = List<AssignmentLabel>.from(activeLabels);
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        final label = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, label);

        setState(() {
          _pendingReorderedLabels = reordered;
        });

        _runMutation(() => _repository.reorderAssignmentLabels(reordered));
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Transform(
                transform: Matrix4.identity(),
                alignment: Alignment.center,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final label = activeLabels[index];
        return Container(
          key: ValueKey(label.id),
          child: _buildLabelListTile(label, isArchived: false),
        );
      },
    );
  }

  Widget _buildArchiveView(List<AssignmentLabel> allLabels) {
    final archivedLabels = allLabels.where((label) => !label.isActive).toList();

    if (archivedLabels.isEmpty) {
      return const Center(
        child: Text('אין לייבלים בארכיון'),
      );
    }

    return ListView.builder(
      itemCount: archivedLabels.length,
      itemBuilder: (context, index) {
        final label = archivedLabels[index];
        return _buildLabelListTile(label, isArchived: true);
      },
    );
  }

  Widget _buildLabelListTile(
    AssignmentLabel label, {
    required bool isArchived,
  }) {
    final labelColor = _colorFromHex(label.color);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: labelColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12),
          ),
        ),
        title: Text(
          label.hebrewName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isArchived ? Colors.grey : Colors.black,
          ),
        ),
        subtitle: Text(
          isArchived ? 'בארכיון' : 'פעיל',
          style: TextStyle(
            color: isArchived ? Colors.grey : Colors.green,
          ),
        ),
        trailing: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isArchived) ...[
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: ElevatedButton.icon(
                    onPressed: () => _runMutation(
                      () => _repository.restoreAssignmentLabel(label.id),
                    ),
                    icon: const Icon(
                      Icons.restore,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text('שחזר'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
                const SizedBox(width: 4),
                IconButton(
                  icon:
                      const Icon(Icons.archive, color: Colors.orange, size: 20),
                  tooltip: 'העבר לארכיון',
                  onPressed: () => _confirmArchiveLabel(label),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  tooltip: 'מחק לצמיתות',
                  onPressed: () => _confirmDeleteLabel(label),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ),
        onTap:
            isArchived ? null : () => _showAddOrEditLabelDialog(label: label),
      ),
    );
  }

  Future<void> _confirmArchiveLabel(AssignmentLabel label) async {
    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('העברה לארכיון'),
          content: Text('להעביר את "${label.hebrewName}" לארכיון?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('העבר לארכיון'),
            ),
          ],
        ),
      ),
    );

    if (shouldArchive != true) {
      return;
    }

    await _runMutation(() => _repository.archiveAssignmentLabel(label.id));
  }

  Future<void> _confirmDeleteLabel(AssignmentLabel label) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'מחיקת לייבל?',
            style: TextStyle(color: Colors.red),
          ),
          content: Text('האם למחוק את "${label.hebrewName}" לצמיתות?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('מחק לצמיתות'),
            ),
          ],
        ),
      ),
    );

    if (shouldDelete != true) {
      return;
    }

    if (!mounted) {
      return;
    }

    final assignments = await context.read<AssignmentRepository>().getAllAssignments();
    if (!mounted) {
      return;
    }

    final affectedAssignmentsCount = assignments
        .where((assignment) => assignment.semanticLabelId == label.id)
        .length;

    if (affectedAssignmentsCount > 0) {
      final shouldClearAssignments = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('אישור נוסף למחיקה'),
            content: Text(
              '$affectedAssignmentsCount שיבוצים עם הלייבל "${label.hebrewName}" יאופסו מהלייבל הזה ויישארו ללא לייבל. להמשיך?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('כן, למחוק'),
              ),
            ],
          ),
        ),
      );

      if (shouldClearAssignments != true) {
        return;
      }
    }

    await _runMutation(() => _repository.deleteAssignmentLabel(label.id));
  }

  Future<void> _showAddOrEditLabelDialog({
    AssignmentLabel? label,
  }) async {
    List<AssignmentLabel> existingLabels;
    try {
      existingLabels = await _repository.getAssignmentLabels();
    } catch (e) {
      if (mounted) {
        _showError(_extractErrorMessage(e));
      }
      return;
    }
    if (!mounted) {
      return;
    }

    final nameController = TextEditingController(text: label?.hebrewName ?? '');
    String selectedColor = label?.color ?? AssignmentLabelPalette.defaultColor;
    bool isSaving = false;
    String? errorText;

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final trimmedName = nameController.text.trim();
            final duplicateNameError = _duplicateLabelError(
              trimmedName,
              existingLabels,
              excludeId: label?.id,
            );

            Future<void> save() async {
              if (trimmedName.isEmpty) {
                setDialogState(() {
                  errorText = 'יש להזין שם ללייבל';
                });
                return;
              }

              if (duplicateNameError != null) {
                setDialogState(() {
                  errorText = null;
                });
                return;
              }

              setDialogState(() {
                isSaving = true;
                errorText = null;
              });

              try {
                if (label == null) {
                  await _repository.createAssignmentLabel(
                    hebrewName: trimmedName,
                    color: selectedColor,
                  );
                } else {
                  await _repository.updateAssignmentLabel(
                    label: label,
                    hebrewName: trimmedName,
                    color: selectedColor,
                  );
                }

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.of(dialogContext).pop(true);
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  isSaving = false;
                  errorText = _extractErrorMessage(e);
                });
              }
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(label == null ? 'יצירת לייבל חדש' : 'עריכת לייבל'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameController,
                          enabled: !isSaving,
                          autofocus: false,
                          onChanged: (_) {
                            setDialogState(() {
                              errorText = null;
                            });
                          },
                          decoration: InputDecoration(
                            labelText: 'שם לייבל',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            errorText: duplicateNameError ?? errorText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'צבע',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              AssignmentLabelPalette.colors.map((colorHex) {
                            final isSelected = colorHex == selectedColor;
                            return InkWell(
                              onTap: isSaving
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        selectedColor = colorHex;
                                      });
                                    },
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _colorFromHex(colorHex),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.black87
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 18,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('ביטול'),
                  ),
                  ElevatedButton(
                    onPressed: isSaving ? null : save,
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(label == null ? 'יצירה' : 'שמירה'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _extractErrorMessage(Object error) {
    final message = error.toString();
    const exceptionPrefix = 'Exception: ';
    if (message.startsWith(exceptionPrefix)) {
      return message.substring(exceptionPrefix.length);
    }
    return message;
  }

  String? _duplicateLabelError(
    String trimmedName,
    List<AssignmentLabel> existingLabels, {
    String? excludeId,
  }) {
    if (trimmedName.isEmpty) {
      return null;
    }

    AssignmentLabel? duplicateLabel;
    for (final label in existingLabels) {
      final isDuplicate = label.id != excludeId &&
          label.hebrewName.trim().toLowerCase() == trimmedName.toLowerCase();
      if (isDuplicate) {
        duplicateLabel = label;
        break;
      }
    }

    if (duplicateLabel == null) {
      return null;
    }

    return duplicateLabel.isActive
        ? 'כבר קיים לייבל בשם הזה'
        : 'כבר קיים לייבל בשם הזה (בארכיון)';
  }

  Color _colorFromHex(String hex) {
    final normalized = hex.replaceAll('#', '').trim();
    final buffer = StringBuffer();
    if (normalized.length == 6) {
      buffer.write('FF');
    }
    buffer.write(normalized);
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
