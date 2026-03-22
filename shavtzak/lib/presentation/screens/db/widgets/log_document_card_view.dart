import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/role_types.dart';
import 'json_tree_view.dart';

enum _LogCardMode { summary, raw }

class LogDocumentCardView extends StatefulWidget {
  final String documentId;
  final Map<String, dynamic> data;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Map<String, Map<String, Map<String, dynamic>>>? collectionsData;

  const LogDocumentCardView({
    super.key,
    required this.documentId,
    required this.data,
    required this.isExpanded,
    required this.onToggle,
    this.collectionsData,
  });

  @override
  State<LogDocumentCardView> createState() => _LogDocumentCardViewState();
}

class _LogDocumentCardViewState extends State<LogDocumentCardView> {
  _LogCardMode _mode = _LogCardMode.summary;

  @override
  void didUpdateWidget(covariant LogDocumentCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId &&
        _mode != _LogCardMode.summary) {
      _mode = _LogCardMode.summary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _buildViewModel();
    final actionColor = viewModel.action.color;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: _blendWithWhite(actionColor, 0.05),
      elevation: widget.isExpanded ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: actionColor.withValues(
            alpha: widget.isExpanded ? 0.35 : 0.18,
          ),
          width: 1.1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, viewModel),
          if (widget.isExpanded) _buildExpandedContent(context, viewModel),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, _LogSummaryViewModel viewModel) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: widget.onToggle,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeadingIcon(viewModel.action),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viewModel.primaryLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    viewModel.secondaryLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LogBadge(
                        label: viewModel.action.label,
                        icon: viewModel.action.icon,
                        color: viewModel.action.color,
                      ),
                      _LogBadge(
                        label: viewModel.entityLabel,
                        icon: Icons.category_outlined,
                        color: Colors.blueGrey.shade600,
                      ),
                      _LogBadge(
                        label: viewModel.status.label,
                        icon: viewModel.status.icon,
                        color: viewModel.status.color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _copyId(context),
                    child: Row(
                      children: [
                        Icon(
                          Icons.copy_outlined,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.documentId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              widget.isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey.shade600,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(
    BuildContext context,
    _LogSummaryViewModel viewModel,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
        color: Colors.white.withValues(alpha: 0.88),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModeToggle(),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _mode == _LogCardMode.summary
                ? KeyedSubtree(
                    key: const ValueKey(_LogCardMode.summary),
                    child: _buildSummaryTab(context, viewModel),
                  )
                : KeyedSubtree(
                    key: const ValueKey(_LogCardMode.raw),
                    child: _buildRawTab(viewModel.rawData),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('סקירה'),
          selected: _mode == _LogCardMode.summary,
          onSelected: (_) {
            setState(() {
              _mode = _LogCardMode.summary;
            });
          },
        ),
        ChoiceChip(
          label: const Text('נתונים גולמיים'),
          selected: _mode == _LogCardMode.raw,
          onSelected: (_) {
            setState(() {
              _mode = _LogCardMode.raw;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSummaryTab(
    BuildContext context,
    _LogSummaryViewModel viewModel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viewModel.showDiffSection && viewModel.diffRows.isNotEmpty)
          _buildSectionCard(
            title: viewModel.diffSectionTitle,
            child: Column(
              children: [
                for (int index = 0;
                    index < viewModel.diffRows.length;
                    index++) ...[
                  _LogDiffRow(
                    row: viewModel.diffRows[index],
                    singleValueMode: viewModel.useCreatedValuesMode,
                  ),
                  if (index != viewModel.diffRows.length - 1)
                    Divider(
                      height: 18,
                      color: Colors.grey.shade300,
                    ),
                ],
              ],
            ),
          )
        else if (viewModel.showDiffSection)
          _buildSectionCard(
            title: viewModel.diffSectionTitle,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'לא זוהו שדות שינוי מפורטים עבור לוג זה.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        if (viewModel.detailRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionCard(
            title: 'פרטים נוספים',
            child: Column(
              children: [
                for (int index = 0;
                    index < viewModel.detailRows.length;
                    index++) ...[
                  _LogDetailRow(row: viewModel.detailRows[index]),
                  if (index != viewModel.detailRows.length - 1)
                    Divider(
                      height: 18,
                      color: Colors.grey.shade300,
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRawTab(Map<String, dynamic> rawData) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.grey.shade50,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: JsonTreeView(
          data: rawData,
          initiallyExpanded: false,
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(_LogChipData action) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: action.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        action.icon,
        color: action.color,
        size: 22,
      ),
    );
  }

  Widget _buildSectionCard({
    String? title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }

  _LogSummaryViewModel _buildViewModel() {
    final isCreateStyleAction = _isCreateStyleAction();
    final isRemoveStyleAction = _isRemoveStyleAction();
    final resolvedActionCode = _getResolvedActionCode();
    final resolvedEntityType = _getResolvedEntityType();
    final action = _getActionChipData(resolvedActionCode);
    final status = _getStatusChipData();
    final actor = _getActor();
    final entityLabel = _getEntityTypeLabel(resolvedEntityType);
    final entityDisplay = _getPrimaryEntityDisplay(resolvedEntityType);
    final operationLabel = _getOperationLabel();
    final constraintSummary = _getConstraintSummary();

    final primaryLine = [
      actor,
      action.label,
      entityLabel,
      if (entityDisplay != null) entityDisplay,
    ].join(' ');

    final secondaryParts = <String>[
      if (_isConstraintLikeEntity(resolvedEntityType) &&
          constraintSummary != null)
        constraintSummary,
      _getTimestampText(),
      if (_readTrimmedString(widget.data['source']) case final String source)
        _getSourceLabel(source),
      operationLabel,
    ];

    final summarySentence = entityDisplay == null
        ? '$actor ${action.label} $entityLabel.'
        : '$actor ${action.label} $entityLabel $entityDisplay.';

    return _LogSummaryViewModel(
      action: action,
      status: status,
      actor: actor,
      entityLabel: entityLabel,
      entityName: entityDisplay,
      primaryLine: primaryLine,
      secondaryLine: secondaryParts.join(' • '),
      summarySentence: summarySentence,
      timestampText: _getTimestampText(),
      operationLabel: operationLabel,
      sourceLabel: _readTrimmedString(widget.data['source']) == null
          ? null
          : _getSourceLabel(widget.data['source'] as String),
      diffRows: _extractDiffRows(),
      detailRows: _extractDetailRows(entityDisplay),
      rawData: _buildRawJsonData(),
      showDiffSection: !isRemoveStyleAction,
      useCreatedValuesMode: isCreateStyleAction,
      diffSectionTitle: isCreateStyleAction ? 'ערכים שנוצרו' : 'שדות שהשתנו',
    );
  }

  _LogChipData _getActionChipData(String actionCode) {
    switch (actionCode) {
      case 'create':
      case 'insert':
      case 'add':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.add_circle_outline,
          color: Colors.green.shade700,
        );
      case 'approve':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
        );
      case 'complete':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.task_alt,
          color: Colors.green.shade700,
        );
      case 'reject':
      case 'autoreject':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.cancel_outlined,
          color: Colors.red.shade700,
        );
      case 'reopen':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.restart_alt,
          color: Colors.orange.shade800,
        );
      case 'returntopending':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.history_toggle_off_outlined,
          color: Colors.orange.shade800,
        );
      case 'update':
      case 'edit':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.edit_outlined,
          color: Colors.blue.shade700,
        );
      case 'delete':
      case 'remove':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.delete_outline,
          color: Colors.red.shade700,
        );
      case 'archive':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.archive_outlined,
          color: Colors.orange.shade800,
        );
      case 'restore':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.unarchive_outlined,
          color: Colors.blue.shade700,
        );
      case 'reorder':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.swap_vert,
          color: Colors.indigo.shade700,
        );
      case 'updatepasscode':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.password_outlined,
          color: Colors.blue.shade700,
        );
      case 'clearpasscode':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.password,
          color: Colors.red.shade700,
        );
      case 'updatearchivestatus':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.inventory_2_outlined,
          color: Colors.orange.shade800,
        );
      case 'loadintoevent':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.playlist_add_check_circle_outlined,
          color: Colors.teal.shade700,
        );
      case 'clearalldata':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.layers_clear_outlined,
          color: Colors.red.shade700,
        );
      case 'seed':
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.auto_fix_high_outlined,
          color: Colors.blueGrey.shade700,
        );
      default:
        return _LogChipData(
          label: _getActionTypeLabel(actionCode),
          icon: Icons.receipt_long_outlined,
          color: Colors.blueGrey.shade700,
        );
    }
  }

  _LogChipData _getStatusChipData() {
    final rawStatus = _readTrimmedString(widget.data['status'])?.toLowerCase();

    switch (rawStatus) {
      case 'success':
        return _LogChipData(
          label: 'הצלחה',
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
        );
      case 'failed':
      case 'error':
        return _LogChipData(
          label: 'שגיאה',
          icon: Icons.error_outline,
          color: Colors.red.shade700,
        );
      case 'pending':
        return _LogChipData(
          label: 'ממתין',
          icon: Icons.schedule_outlined,
          color: Colors.orange.shade800,
        );
      default:
        return _LogChipData(
          label: 'ללא סטטוס',
          icon: Icons.help_outline,
          color: Colors.grey.shade600,
        );
    }
  }

  List<_LogDiffRowViewModel> _extractDiffRows() {
    final changeMap = _asStringMap(widget.data['changes']);
    final oldValue = _asStringMap(widget.data['oldValue']);
    final newValue = _asStringMap(widget.data['newValue']);
    final rows = <_LogDiffRowViewModel>[];

    if (changeMap != null && changeMap.isNotEmpty) {
      for (final entry in changeMap.entries) {
        final fieldKey = entry.key;
        final values = _extractChangeValues(
          fieldKey: fieldKey,
          rawChange: entry.value,
          oldValueMap: oldValue,
          newValueMap: newValue,
        );
        rows.addAll(
          _buildDiffRowsForField(
            fieldKey: fieldKey,
            oldValue: values.oldValue,
            newValue: values.newValue,
          ),
        );
      }
      return rows;
    }

    final keys = <String>{
      ...?oldValue?.keys,
      ...?newValue?.keys,
    }.toList()
      ..sort();

    for (final fieldKey in keys) {
      rows.addAll(
        _buildDiffRowsForField(
          fieldKey: fieldKey,
          oldValue: oldValue?[fieldKey],
          newValue: newValue?[fieldKey],
        ),
      );
    }

    return rows;
  }

  List<_LogDiffRowViewModel> _buildDiffRowsForField({
    required String fieldKey,
    required dynamic oldValue,
    required dynamic newValue,
  }) {
    if (fieldKey == 'roleRequirements') {
      final roleRows = _buildRoleRequirementDiffRows(oldValue, newValue);
      if (roleRows.isNotEmpty) {
        return roleRows;
      }
    }

    return [
      _LogDiffRowViewModel(
        label: _getFieldLabel(fieldKey),
        oldValue: _formatValue(fieldKey, oldValue),
        newValue: _formatValue(fieldKey, newValue),
      ),
    ];
  }

  List<_LogDiffRowViewModel> _buildRoleRequirementDiffRows(
    dynamic oldValue,
    dynamic newValue,
  ) {
    final oldMap = _asStringMap(oldValue) ?? const <String, dynamic>{};
    final newMap = _asStringMap(newValue) ?? const <String, dynamic>{};
    final roleKeys = <String>{
      ...oldMap.keys,
      ...newMap.keys,
    }.toList()
      ..sort((a, b) => _formatRoleType(a).compareTo(_formatRoleType(b)));

    final rows = <_LogDiffRowViewModel>[];
    for (final roleKey in roleKeys) {
      final oldQuota = _asRoleRequirementCount(oldMap[roleKey]);
      final newQuota = _asRoleRequirementCount(newMap[roleKey]);
      if (oldQuota == newQuota) {
        continue;
      }

      rows.add(
        _LogDiffRowViewModel(
          label: 'מכסה: ${_formatRoleType(roleKey)}',
          oldValue: _FormattedValue(text: oldQuota.toString()),
          newValue: _FormattedValue(text: newQuota.toString()),
        ),
      );
    }

    return rows;
  }

  List<_LogDetailRowViewModel> _extractDetailRows(String? entityDisplay) {
    final details = _asStringMap(widget.data['details']);
    if (details == null || details.isEmpty) {
      return const [];
    }

    const hiddenKeys = {
      'name',
      'entityName',
      'actionType',
      'operation',
      'status',
      'source',
      'semanticAction',
    };
    final hasTeamMemberName =
        _readTrimmedString(details['teamMemberName']) != null;
    final hasEventName = _readTrimmedString(details['eventName']) != null;
    final hasRichConstraintFields = [
      'startDate',
      'endDate',
      'startTime',
      'endTime',
      'note',
      'repeatType',
      'repeatEndDate',
    ].any(details.containsKey);

    final rows = <_LogDetailRowViewModel>[];

    for (final entry in details.entries) {
      if (hiddenKeys.contains(entry.key)) {
        continue;
      }

      if (hasTeamMemberName && entry.key == 'teamMemberId') {
        continue;
      }

      if (hasEventName && entry.key == 'eventId') {
        continue;
      }

      if (hasRichConstraintFields && entry.key == 'constraintSummary') {
        continue;
      }

      if (entityDisplay != null &&
          entry.key == 'entityId' &&
          _formatEntityFallback(_readTrimmedString(entry.value)) ==
              entityDisplay) {
        continue;
      }

      final expandableItems =
          _buildExpandableDetailItems(entry.key, entry.value);
      if (expandableItems != null) {
        rows.add(
          _LogDetailRowViewModel(
            label: _getFieldLabel(entry.key),
            value: _FormattedValue(text: '${expandableItems.length} פריטים'),
            expandableItems: expandableItems,
          ),
        );
        continue;
      }

      final nestedMap = _asStringMap(entry.value);
      if (nestedMap != null && nestedMap.isNotEmpty) {
        for (final nestedEntry in nestedMap.entries) {
          rows.add(
            _LogDetailRowViewModel(
              label:
                  '${_getFieldLabel(entry.key)} / ${_getFieldLabel(nestedEntry.key)}',
              value: _formatValue(nestedEntry.key, nestedEntry.value),
            ),
          );
        }
        continue;
      }

      rows.add(
        _LogDetailRowViewModel(
          label: _getFieldLabel(entry.key),
          value: _formatValue(entry.key, entry.value),
        ),
      );
    }

    return rows;
  }

  List<_LogExpandableListItem>? _buildExpandableDetailItems(
    String fieldKey,
    dynamic value,
  ) {
    if (value is! List) {
      return null;
    }

    switch (fieldKey) {
      case 'deletedAssignments':
        final items = value
            .asMap()
            .entries
            .map((entry) => _buildDeletedAssignmentItem(entry.value, entry.key))
            .whereType<_LogExpandableListItem>()
            .toList();
        return items.isEmpty ? null : items;
      case 'deletedChecklistItems':
        final items = value
            .asMap()
            .entries
            .map((entry) => _buildDeletedChecklistItem(entry.value, entry.key))
            .whereType<_LogExpandableListItem>()
            .toList();
        return items.isEmpty ? null : items;
      default:
        return null;
    }
  }

  _LogExpandableListItem? _buildDeletedAssignmentItem(
    dynamic rawItem,
    int index,
  ) {
    final item = _asStringMap(rawItem);
    if (item == null) {
      return null;
    }

    final teamMemberName = _readTrimmedString(item['teamMemberName']) ??
        _resolveReferenceName(
          'teamMemberId',
          _readTrimmedString(item['teamMemberId']) ?? '',
        ) ??
        'חבר צוות לא ידוע';
    final roleType = _readTrimmedString(item['roleType']);
    final id = _readTrimmedString(item['id']);
    final statusValue = item['status'];
    final formattedStatus =
        statusValue == null ? null : _formatValue('status', statusValue);

    final titleParts = <String>[
      teamMemberName,
      if (roleType != null) _formatRoleType(roleType),
    ];
    final subtitleParts = <String>[
      if (formattedStatus != null && formattedStatus.hasValue)
        formattedStatus.text,
      if (id != null) _shortId(id),
    ];

    return _LogExpandableListItem(
      title: titleParts.join(' | '),
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
      icon: Icons.assignment_ind_outlined,
      color: Colors.red.shade700,
    );
  }

  _LogExpandableListItem? _buildDeletedChecklistItem(
    dynamic rawItem,
    int index,
  ) {
    final item = _asStringMap(rawItem);
    if (item == null) {
      return null;
    }

    final name =
        _readTrimmedString(item['name']) ?? 'פריט צ\'קליסט ${index + 1}';
    final responsibleName = _readTrimmedString(item['responsibleName']) ??
        _resolveReferenceName(
          'responsibleId',
          _readTrimmedString(item['responsibleId']) ?? '',
        );
    final id = _readTrimmedString(item['id']);
    final statusValue = item['status'];
    final formattedStatus =
        statusValue == null ? null : _formatValue('status', statusValue);

    final subtitleParts = <String>[
      if (responsibleName != null) 'אחראי: $responsibleName',
      if (formattedStatus != null && formattedStatus.hasValue)
        'סטטוס: ${formattedStatus.text}',
      if (id != null) _shortId(id),
    ];

    return _LogExpandableListItem(
      title: name,
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
      icon: Icons.checklist_outlined,
      color: Colors.red.shade700,
    );
  }

  Map<String, dynamic> _buildRawJsonData() {
    const orderedKeys = [
      'timestampLocalIsrael',
      'timestampUtc',
      'performerName',
      'performerId',
      'performerUniqueKey',
      'actionType',
      'operation',
      'entityType',
      'entityId',
      'entityName',
      'status',
      'source',
      'changes',
      'oldValue',
      'newValue',
      'details',
      'operationId',
      'parentOperationId',
    ];

    final rawData = <String, dynamic>{
      'id': widget.documentId,
    };

    for (final key in orderedKeys) {
      if (widget.data.containsKey(key)) {
        rawData[key] = widget.data[key];
      }
    }

    for (final entry in widget.data.entries) {
      if (!rawData.containsKey(entry.key)) {
        rawData[entry.key] = entry.value;
      }
    }

    return rawData;
  }

  _FormattedValue _formatValue(String fieldKey, dynamic value) {
    if (value == null) {
      return const _FormattedValue.placeholder('ללא ערך');
    }

    final timestampLike = _tryParseTimestampLike(value);
    if (timestampLike != null) {
      return _FormattedValue(text: _formatDateTime(timestampLike));
    }

    if (value is bool) {
      return _FormattedValue(
        text: value ? 'כן' : 'לא',
        icon: value ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: value ? Colors.green.shade700 : Colors.red.shade700,
      );
    }

    if (value is num) {
      return _FormattedValue(text: value.toString());
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const _FormattedValue.placeholder('ריק');
      }

      if (fieldKey == 'status' || fieldKey == 'newStatus') {
        return _formatStatusValue(trimmed);
      }

      if (fieldKey == 'constraintType') {
        return _FormattedValue(text: _formatConstraintType(trimmed));
      }

      if (fieldKey == 'repeatType') {
        return _FormattedValue(text: _formatRepeatType(trimmed));
      }

      if (fieldKey == 'semanticAction') {
        return _FormattedValue(text: _getActionTypeLabel(trimmed));
      }

      final relatedName = _resolveReferenceName(fieldKey, trimmed);
      if (relatedName != null) {
        return _FormattedValue(text: relatedName);
      }

      if (fieldKey == 'roleType') {
        return _FormattedValue(text: _formatRoleType(trimmed));
      }

      if (_looksLikeDateField(fieldKey, trimmed)) {
        final parsed = DateTime.tryParse(trimmed);
        if (parsed != null) {
          return _FormattedValue(text: _formatDateTime(parsed));
        }
      }

      if (_looksLikeIdentifierField(fieldKey)) {
        return _FormattedValue(
          text: _shortId(trimmed),
          monospace: true,
        );
      }

      return _FormattedValue(text: trimmed);
    }

    if (value is List) {
      if (value.isEmpty) {
        return const _FormattedValue.placeholder('רשימה ריקה');
      }

      final scalarValues =
          value.where((item) => item is! Map && item is! List).toList();
      if (scalarValues.length == value.length) {
        final preview = scalarValues
            .take(3)
            .map((item) => _formatValue(fieldKey, item).text)
            .join(', ');
        final suffix = value.length > 3 ? ' ועוד ${value.length - 3}' : '';
        return _FormattedValue(text: '$preview$suffix');
      }

      return _FormattedValue(text: '${value.length} פריטים');
    }

    final nestedMap = _asStringMap(value);
    if (nestedMap != null) {
      if (nestedMap.isEmpty) {
        return const _FormattedValue.placeholder('ללא שדות');
      }

      if (fieldKey == 'roleCapabilities') {
        final enabledRoles = nestedMap.entries
            .where((entry) => entry.value == true)
            .map((entry) => _formatRoleType(entry.key))
            .toList();
        if (enabledRoles.isEmpty) {
          return const _FormattedValue.placeholder('ללא תפקידים פעילים');
        }
        final preview = enabledRoles.take(3).join(', ');
        final suffix =
            enabledRoles.length > 3 ? ' ועוד ${enabledRoles.length - 3}' : '';
        return _FormattedValue(text: '$preview$suffix');
      }

      if (fieldKey == 'roleRequirements') {
        final activeRequirements = nestedMap.entries
            .where((entry) => entry.value is num && (entry.value as num) > 0)
            .map((entry) => '${_formatRoleType(entry.key)} × ${entry.value}')
            .toList();
        if (activeRequirements.isEmpty) {
          return const _FormattedValue.placeholder('ללא מכסות');
        }
        final preview = activeRequirements.take(2).join(', ');
        final suffix = activeRequirements.length > 2
            ? ' ועוד ${activeRequirements.length - 2}'
            : '';
        return _FormattedValue(text: '$preview$suffix');
      }

      final simpleEntries = nestedMap.entries
          .where((entry) => entry.value is! Map && entry.value is! List)
          .toList();

      if (simpleEntries.isNotEmpty) {
        final preview = simpleEntries.take(2).map((entry) {
          final nestedLabel = _getFieldLabel(entry.key);
          final nestedValue = _formatValue(entry.key, entry.value).text;
          return '$nestedLabel: $nestedValue';
        }).join(', ');

        final suffix =
            simpleEntries.length > 2 ? ' ועוד ${simpleEntries.length - 2}' : '';
        return _FormattedValue(text: '$preview$suffix');
      }

      return _FormattedValue(text: '${nestedMap.length} שדות');
    }

    return _FormattedValue(text: value.toString());
  }

  String _getActor() {
    for (final candidate in [
      widget.data['performerName'],
      widget.data['performerUniqueKey'],
      widget.data['performerId'],
    ]) {
      final value = _readTrimmedString(candidate);
      if (value != null) {
        return value;
      }
    }
    return 'לא ידוע';
  }

  String? _getEntityName() {
    final topLevelName = _readTrimmedString(widget.data['entityName']);
    if (topLevelName != null) {
      return topLevelName;
    }

    final details = _asStringMap(widget.data['details']);
    if (details != null) {
      for (final key in ['name', 'entityName']) {
        final value = _readTrimmedString(details[key]);
        if (value != null) {
          return value;
        }
      }
    }

    return null;
  }

  String _getResolvedActionCode() {
    final normalized =
        _normalizeActionType(widget.data['actionType'] as String?);
    if (normalized != 'updatestatus') {
      return normalized;
    }

    final details = _asStringMap(widget.data['details']);
    final newValue = _asStringMap(widget.data['newValue']);
    final rawStatus =
        _readTrimmedString(details?['newStatus'] ?? newValue?['status']);
    final isAutoRejected = details?['wasAutoRejectedFromCalendar'] == true ||
        newValue?['wasAutoRejectedFromCalendar'] == true;

    if (isAutoRejected) {
      return 'autoreject';
    }

    switch (rawStatus?.toLowerCase()) {
      case 'approved':
        return 'approve';
      case 'rejected':
        return 'reject';
      case 'pending':
        return 'returntopending';
      default:
        return normalized;
    }
  }

  String? _getResolvedEntityType() {
    final topLevel = _readTrimmedString(widget.data['entityType']);
    if (topLevel == 'constraint' || topLevel == 'availability') {
      final details = _asStringMap(widget.data['details']);
      if (_readTrimmedString(details?['constraintType']) == 'availability') {
        return 'availability';
      }
    }

    return topLevel;
  }

  bool _isConstraintLikeEntity(String? entityType) {
    return entityType == 'constraint' || entityType == 'availability';
  }

  String? _getPrimaryEntityDisplay(String? entityType) {
    if (_isConstraintLikeEntity(entityType)) {
      final teamMemberName = _getConstraintTeamMemberName();
      if (teamMemberName != null) {
        return 'של $teamMemberName';
      }

      final constraintSummary = _getConstraintSummary();
      if (constraintSummary != null) {
        return '"$constraintSummary"';
      }

      return null;
    }

    if ((entityType ?? '').trim().toLowerCase() == 'assignment') {
      final assignmentDisplay = _getAssignmentDisplay();
      if (assignmentDisplay != null) {
        return assignmentDisplay;
      }
    }

    final batchScopeDisplay = _getBatchScopeDisplay(entityType);
    if (batchScopeDisplay != null) {
      return batchScopeDisplay;
    }

    final entityName = _getEntityName();
    if (entityName != null) {
      return '"$entityName"';
    }

    final resolvedEntityName = _getResolvedEntityNameFromEntityId(entityType);
    if (resolvedEntityName != null) {
      return '"$resolvedEntityName"';
    }

    return null;
  }

  String? _getConstraintTeamMemberName() {
    final details = _asStringMap(widget.data['details']);
    final explicitName = _readTrimmedString(details?['teamMemberName']);
    if (explicitName != null) {
      return explicitName;
    }

    final teamMemberId = _readTrimmedString(details?['teamMemberId']);
    if (teamMemberId != null) {
      return _resolveReferenceName('teamMemberId', teamMemberId);
    }

    return null;
  }

  String? _getConstraintSummary() {
    final details = _asStringMap(widget.data['details']);
    final explicitSummary = _readTrimmedString(details?['constraintSummary']);
    if (explicitSummary != null) {
      return explicitSummary;
    }

    return _buildConstraintSummaryFromMap(_getConstraintSnapshot());
  }

  String? _getAssignmentDisplay() {
    final details = _asStringMap(widget.data['details']);
    final oldValue = _asStringMap(widget.data['oldValue']);
    final newValue = _asStringMap(widget.data['newValue']);

    final teamMemberName = _readTrimmedString(details?['teamMemberName']) ??
        _resolveReferenceName(
          'teamMemberId',
          _readTrimmedString(
                details?['teamMemberId'] ??
                    oldValue?['teamMemberId'] ??
                    newValue?['teamMemberId'],
              ) ??
              '',
        );
    final eventName = _readTrimmedString(details?['eventName']) ??
        _resolveReferenceName(
          'eventId',
          _readTrimmedString(
                details?['eventId'] ??
                    oldValue?['eventId'] ??
                    newValue?['eventId'],
              ) ??
              '',
        );
    final roleType = _readTrimmedString(
      details?['roleType'] ?? oldValue?['roleType'] ?? newValue?['roleType'],
    );

    final parts = <String>[
      if (teamMemberName != null) teamMemberName,
      if (roleType != null) _formatRoleType(roleType),
      if (eventName != null) eventName,
    ];

    if (parts.isEmpty) {
      return null;
    }

    return '"${parts.join(' | ')}"';
  }

  String _getTimestampText() {
    final timestampLocalIsrael =
        _readTrimmedString(widget.data['timestampLocalIsrael']);
    if (timestampLocalIsrael != null) {
      final parsed = DateTime.tryParse(timestampLocalIsrael);
      if (parsed != null) {
        return DateFormat('dd/MM/yyyy, HH:mm:ss').format(parsed);
      }
    }

    final timestampUtc = widget.data['timestampUtc'];
    if (timestampUtc is Timestamp) {
      return DateFormat('dd/MM/yyyy, HH:mm:ss').format(timestampUtc.toDate());
    }
    if (timestampUtc is DateTime) {
      return DateFormat('dd/MM/yyyy, HH:mm:ss').format(timestampUtc);
    }
    if (timestampUtc is String) {
      final parsed = DateTime.tryParse(timestampUtc);
      if (parsed != null) {
        return DateFormat('dd/MM/yyyy, HH:mm:ss').format(parsed);
      }
    }

    return 'תאריך לא זמין';
  }

  String _getActionTypeLabel(String? actionType) {
    switch (_normalizeActionType(actionType)) {
      case 'approve':
        return 'אישר';
      case 'complete':
        return 'השלים';
      case 'reject':
        return 'דחה';
      case 'autoreject':
        return 'נדחה אוטומטית';
      case 'reopen':
        return 'פתח מחדש';
      case 'returntopending':
        return 'החזיר להמתנה';
      case 'create':
      case 'insert':
        return 'יצר';
      case 'insertbatch':
        return 'יצר';
      case 'edit':
      case 'update':
        return 'עדכן';
      case 'delete':
      case 'deletebatch':
      case 'deletebyevent':
      case 'deletebyperson':
        return 'מחק';
      case 'add':
        return 'הוסיף';
      case 'remove':
        return 'הסיר';
      case 'archive':
        return 'העביר לארכיון';
      case 'restore':
        return 'שחזר';
      case 'reorder':
        return 'סידר מחדש';
      case 'loadintoevent':
        return 'טען לאירוע';
      case 'clearalldata':
        return 'ניקה נתונים';
      case 'updatepasscode':
        return 'עדכן קוד גישה';
      case 'clearpasscode':
        return 'איפס קוד גישה';
      case 'updatearchivestatus':
        return 'עדכן ארכיון';
      case 'seed':
        return 'אתחל';
      default:
        return actionType ?? 'פעולה לא ידועה';
    }
  }

  String _getEntityTypeLabel(String? entityType) {
    switch ((entityType ?? '').toLowerCase()) {
      case 'event':
        return 'אירוע';
      case 'teammember':
        return 'חבר צוות';
      case 'checklistitem':
        return 'פריט צ\'קליסט';
      case 'constraint':
        return 'מגבלה';
      case 'availability':
        return 'זמינות';
      case 'assignment':
        return 'שיבוץ';
      case 'assignmentlabel':
        return 'לייבל';
      case 'checklistnote':
        return 'הערת צ\'קליסט';
      case 'preset':
        return 'תבנית צ\'קליסט';
      case 'role':
        return 'תפקיד';
      case 'category':
        return 'קטגוריה';
      case 'teammemberbatch':
        return 'חברי צוות';
      case 'eventbatch':
        return 'אירועים';
      case 'assignmentbatch':
        return 'שיבוצים';
      case 'assignmentlabelbatch':
        return 'לייבלים';
      case 'checklistitembatch':
        return 'פריטי צ\'קליסט';
      case 'rolebatch':
        return 'תפקידים';
      default:
        return entityType ?? 'ישות לא ידועה';
    }
  }

  String _getSourceLabel(String source) {
    switch (source.trim().toLowerCase()) {
      case 'cloud_function':
        return 'Cloud Function';
      case 'client':
        return 'Client';
      default:
        return source;
    }
  }

  String _getFieldLabel(String fieldKey) {
    const labels = {
      'name': 'שם',
      'entityName': 'שם הישות',
      'entityId': 'מזהה ישות',
      'entityType': 'סוג ישות',
      'phoneNumber': 'טלפון',
      'phone': 'טלפון',
      'email': 'אימייל',
      'birthday': 'יום הולדת',
      'roleRequirements': 'מכסות תפקידים',
      'roleCapabilities': 'כשירויות תפקיד',
      'responsibleId': 'אחראי',
      'status': 'סטטוס',
      'passcodeLength': 'אורך קוד גישה',
      'startDate': 'תאריך התחלה',
      'endDate': 'תאריך סיום',
      'location': 'מיקום',
      'roleType': 'תפקיד',
      'semanticLabelId': 'לייבל',
      'labelId': 'לייבל',
      'teamMemberId': 'חבר צוות',
      'memberId': 'חבר צוות',
      'eventId': 'אירוע',
      'eventName': 'אירוע',
      'assignmentId': 'שיבוץ',
      'presetId': 'תבנית',
      'categoryId': 'קטגוריה',
      'checklistItemId': 'פריט צ\'קליסט',
      'constraintId': 'מגבלה',
      'teamMemberName': 'חבר צוות',
      'constraintSummary': 'סיכום',
      'constraintType': 'סוג מגבלה',
      'note': 'הערה',
      'notes': 'הערות',
      'count': 'כמות',
      'newStatus': 'סטטוס חדש',
      'repeatType': 'חזרתיות',
      'repeatDay': 'יום חזרה',
      'repeatEndDate': 'סיום חזרתיות',
      'startTime': 'שעת התחלה',
      'endTime': 'שעת סיום',
      'wasAutoRejectedFromCalendar': 'נדחה אוטומטית ביומן',
      'semanticAction': 'פעולה סמנטית',
      'length': 'אורך',
      'isActive': 'פעיל',
      'isAdmin': 'מנהל',
      'isPermanent': 'קבוע',
      'isArchived': 'בארכיון',
      'uniqueKey': 'מפתח ייחודי',
      'performerName': 'מבצע',
      'performerId': 'מזהה מבצע',
      'performerUniqueKey': 'מפתח מבצע',
      'createdAt': 'נוצר בתאריך',
      'updatedAt': 'עודכן בתאריך',
      'statusLastUpdatedAt': 'עודכן סטטוס בתאריך',
      'deletedChecklistItems': 'פריטי צ\'קליסט שנמחקו',
      'deletedAssignments': 'שיבוצים שנמחקו',
      'title': 'כותרת',
      'description': 'תיאור',
      'type': 'סוג',
      'order': 'סדר',
      'sortOrder': 'סדר תצוגה',
      'hebrewName': 'שם לייבל',
      'color': 'צבע',
      'key': 'מפתח',
      'clearedAssignmentsCount': 'מספר שיבוצים שאופסו',
      'responsibleName': 'אחראי',
      'source': 'מקור',
      'operation': 'פעולה טכנית',
      'environment': 'סביבה',
    };

    return labels[fieldKey] ?? fieldKey;
  }

  String _formatRoleType(String roleType) {
    try {
      return RoleTypeExtension.fromString(roleType).hebrewName;
    } catch (_) {
      return roleType;
    }
  }

  _FormattedValue _formatStatusValue(String status) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
        return _FormattedValue(
          text: 'מאושר',
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
        );
      case 'rejected':
        return _FormattedValue(
          text: 'נדחה',
          icon: Icons.cancel_outlined,
          color: Colors.red.shade700,
        );
      case 'pending':
        return _FormattedValue(
          text: 'ממתין',
          icon: Icons.schedule_outlined,
          color: Colors.orange.shade800,
        );
      case 'confirmed':
        return _FormattedValue(
          text: 'מאושר',
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
        );
      case 'declined':
        return _FormattedValue(
          text: 'סירב',
          icon: Icons.cancel_outlined,
          color: Colors.red.shade700,
        );
      default:
        return _FormattedValue(text: status);
    }
  }

  String _formatConstraintType(String constraintType) {
    switch (constraintType.trim().toLowerCase()) {
      case 'availability':
        return 'זמינות';
      case 'unavailability':
        return 'אי זמינות';
      default:
        return constraintType;
    }
  }

  String _formatRepeatType(String repeatType) {
    switch (repeatType.trim().toLowerCase()) {
      case 'daily':
        return 'יומי';
      case 'weekly':
        return 'שבועי';
      case 'monthly':
        return 'חודשי';
      default:
        return repeatType;
    }
  }

  String _normalizeActionType(String? actionType) {
    final raw = (actionType ?? '').trim().toLowerCase();
    if (raw.isEmpty) {
      return '';
    }

    final parts = raw.split('.');
    final normalized = parts.isNotEmpty ? parts.last : raw;
    switch (normalized) {
      case 'deletebyevent':
      case 'deletebyperson':
      case 'deletebatch':
        return 'delete';
      case 'insertbatch':
        return 'create';
      default:
        return normalized;
    }
  }

  int _asRoleRequirementCount(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }

    return 0;
  }

  String? _getBatchScopeDisplay(String? entityType) {
    final normalizedEntityType = (entityType ?? '').trim().toLowerCase();
    final operation =
        _readTrimmedString(widget.data['operation'])?.toLowerCase();
    final entityId = _readTrimmedString(widget.data['entityId']);
    if (operation == null || entityId == null) {
      return null;
    }

    if ((normalizedEntityType == 'assignmentbatch' ||
            normalizedEntityType == 'checklistitembatch') &&
        operation.endsWith('deletebyevent')) {
      final eventName = _resolveReferenceName('eventId', entityId);
      if (eventName != null) {
        return 'של "$eventName"';
      }
    }

    if (normalizedEntityType == 'assignmentbatch' &&
        operation.endsWith('deletebyperson')) {
      final teamMemberName = _resolveReferenceName('teamMemberId', entityId);
      if (teamMemberName != null) {
        return 'של $teamMemberName';
      }
    }

    return null;
  }

  String? _getResolvedEntityNameFromEntityId(String? entityType) {
    final normalizedEntityType = (entityType ?? '').trim().toLowerCase();
    final entityId = _readTrimmedString(widget.data['entityId']);
    if (entityId == null) {
      return null;
    }

    switch (normalizedEntityType) {
      case 'teammember':
        return _resolveReferenceName('teamMemberId', entityId);
      case 'event':
        return _resolveReferenceName('eventId', entityId);
      case 'assignment':
        return _resolveReferenceName('assignmentId', entityId);
      case 'checklistitem':
        return _resolveReferenceName('checklistItemId', entityId);
      case 'preset':
        return _resolveReferenceName('presetId', entityId);
      case 'assignmentlabel':
        return _resolveReferenceName('semanticLabelId', entityId);
      default:
        return null;
    }
  }

  String _getOperationLabel() {
    final operation =
        _readTrimmedString(widget.data['operation'])?.trim() ?? '';
    switch (operation.toLowerCase()) {
      case 'assignment.deletebyevent':
        return 'מחיקת שיבוצים לפי אירוע';
      case 'assignment.deletebyperson':
        return 'מחיקת שיבוצים לפי חבר צוות';
      case 'assignment.deletebatch':
        return 'מחיקת שיבוצים מרובה';
      case 'assignment.insertbatch':
        return 'יצירת שיבוצים מרובה';
      case 'assignmentlabel.insert':
        return 'יצירת לייבל';
      case 'assignmentlabel.update':
        return 'עדכון לייבל';
      case 'assignmentlabel.archive':
        return 'העברת לייבל לארכיון';
      case 'assignmentlabel.restore':
        return 'שחזור לייבל';
      case 'assignmentlabel.delete':
        return 'מחיקת לייבל';
      case 'assignmentlabel.reorder':
        return 'סידור מחדש של לייבלים';
      case 'checklist.deletebyevent':
        return 'מחיקת פריטי צ\'קליסט לפי אירוע';
      default:
        return operation.isEmpty ? 'ללא operation' : operation;
    }
  }

  bool _isCreateStyleAction() {
    switch (_getResolvedActionCode()) {
      case 'create':
      case 'insert':
      case 'add':
      case 'seed':
        return true;
      default:
        return false;
    }
  }

  bool _isRemoveStyleAction() {
    switch (_getResolvedActionCode()) {
      case 'delete':
      case 'remove':
      case 'clearalldata':
        return true;
      default:
        return false;
    }
  }

  Map<String, dynamic>? _getConstraintSnapshot() {
    final details = _asStringMap(widget.data['details']);
    const constraintKeys = {
      'constraintType',
      'startDate',
      'endDate',
      'startTime',
      'endTime',
      'note',
      'repeatType',
      'repeatDay',
      'repeatEndDate',
    };

    if (details != null && details.keys.any(constraintKeys.contains)) {
      return details;
    }

    final newValue = _asStringMap(widget.data['newValue']);
    if (newValue != null && newValue.keys.any(constraintKeys.contains)) {
      return newValue;
    }

    final oldValue = _asStringMap(widget.data['oldValue']);
    if (oldValue != null && oldValue.keys.any(constraintKeys.contains)) {
      return oldValue;
    }

    return null;
  }

  String? _buildConstraintSummaryFromMap(Map<String, dynamic>? value) {
    if (value == null) {
      return null;
    }

    final repeatType = _readTrimmedString(value['repeatType']);
    final startDate = _formatConstraintDateValue(value['startDate']);
    final endDate = _formatConstraintDateValue(value['endDate']);
    final startTime = _readTrimmedString(value['startTime']);
    final endTime = _readTrimmedString(value['endTime']);
    final note = _readTrimmedString(value['note']);

    final parts = <String>[
      if (repeatType != null) _formatRepeatType(repeatType),
      if (startDate != null && endDate != null && startDate != endDate)
        '$startDate - $endDate'
      else if (startDate != null)
        startDate,
      if (startTime != null && endTime != null)
        '$startTime - $endTime'
      else if (startTime != null || endTime != null)
        startTime ?? endTime!,
      if (note != null) note,
    ];

    return parts.isEmpty ? null : parts.join(' | ');
  }

  String? _formatConstraintDateValue(dynamic value) {
    final timestampLike = _tryParseTimestampLike(value);
    if (timestampLike == null) {
      return null;
    }
    return DateFormat('dd/MM/yyyy').format(
      timestampLike.isUtc ? timestampLike.toLocal() : timestampLike,
    );
  }

  String? _resolveReferenceName(String fieldKey, String id) {
    if (widget.collectionsData == null) {
      return null;
    }

    if (fieldKey == 'performerUniqueKey') {
      final members = widget.collectionsData!['teamMembers'];
      if (members != null) {
        for (final member in members.values) {
          if (_readTrimmedString(member['uniqueKey']) == id) {
            return _readTrimmedString(member['name']);
          }
        }
      }
    }

    final collectionKey = _getReferenceCollectionKey(fieldKey);
    if (collectionKey == null) {
      return null;
    }

    final collection = widget.collectionsData![collectionKey];
    if (collection == null) {
      return null;
    }

    final doc = collection[id];
    if (doc == null) {
      return null;
    }

    for (final candidateKey in [
      'name',
      'entityName',
      'title',
      'label',
      'hebrewName',
    ]) {
      final value = _readTrimmedString(doc[candidateKey]);
      if (value != null) {
        return value;
      }
    }

    return null;
  }

  String? _getReferenceCollectionKey(String fieldKey) {
    switch (fieldKey) {
      case 'eventId':
        return 'events';
      case 'teamMemberId':
      case 'memberId':
      case 'responsibleId':
      case 'performerId':
        return 'teamMembers';
      case 'assignmentId':
        return 'assignments';
      case 'semanticLabelId':
      case 'labelId':
        return 'assignmentLabels';
      case 'presetId':
        return 'checklist_presets';
      case 'checklistItemId':
        return 'checklist_items';
      case 'constraintId':
        return 'constraints';
      default:
        return null;
    }
  }

  bool _looksLikeDateField(String fieldKey, String value) {
    final lowerField = fieldKey.toLowerCase();
    if (lowerField.contains('date') ||
        lowerField.endsWith('at') ||
        lowerField.contains('timestamp')) {
      return true;
    }

    return RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value);
  }

  bool _looksLikeIdentifierField(String fieldKey) {
    final lowerField = fieldKey.toLowerCase();
    return lowerField.endsWith('id') || lowerField.contains('uniquekey');
  }

  String? _formatEntityFallback(String? entityId) {
    if (entityId == null) {
      return null;
    }
    return _shortId(entityId);
  }

  String _shortId(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 18) {
      return trimmed;
    }
    return '${trimmed.substring(0, 8)}...${trimmed.substring(trimmed.length - 6)}';
  }

  String _formatDateTime(DateTime dateTime) {
    final localDateTime = dateTime.isUtc ? dateTime.toLocal() : dateTime;

    if (localDateTime.hour == 0 &&
        localDateTime.minute == 0 &&
        localDateTime.second == 0 &&
        localDateTime.millisecond == 0) {
      return DateFormat('dd/MM/yyyy').format(localDateTime);
    }

    if (localDateTime.second == 0 && localDateTime.millisecond == 0) {
      return DateFormat('dd/MM/yyyy HH:mm').format(localDateTime);
    }

    return DateFormat('dd/MM/yyyy HH:mm:ss').format(localDateTime);
  }

  DateTime? _tryParseTimestampLike(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    final map = _asStringMap(value);
    if (map == null) {
      return null;
    }

    final seconds =
        _asInt(map['seconds'] ?? map['_seconds'] ?? map['epochSeconds']);
    if (seconds == null) {
      return null;
    }

    final nanoseconds = _asInt(
          map['nanoseconds'] ?? map['_nanoseconds'] ?? map['nanos'],
        ) ??
        0;

    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).add(Duration(microseconds: nanoseconds ~/ 1000));
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map) {
      return value
          .map((key, entryValue) => MapEntry(key.toString(), entryValue));
    }
    return null;
  }

  String? _readTrimmedString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  _ChangeValues _extractChangeValues({
    required String fieldKey,
    required dynamic rawChange,
    required Map<String, dynamic>? oldValueMap,
    required Map<String, dynamic>? newValueMap,
  }) {
    final changeMap = _asStringMap(rawChange);
    if (changeMap != null) {
      final oldValue = changeMap['oldValue'] ??
          changeMap['old_value'] ??
          changeMap['before'] ??
          oldValueMap?[fieldKey];
      final newValue = changeMap['newValue'] ??
          changeMap['new_value'] ??
          changeMap['after'] ??
          newValueMap?[fieldKey];

      if (oldValue != null || newValue != null) {
        return _ChangeValues(oldValue: oldValue, newValue: newValue);
      }
    }

    return _ChangeValues(
      oldValue: oldValueMap?[fieldKey],
      newValue: newValueMap?[fieldKey],
    );
  }

  Color _blendWithWhite(Color color, double opacity) {
    return Color.alphaBlend(color.withValues(alpha: opacity), Colors.white);
  }

  void _copyId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.documentId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('הועתק: ${widget.documentId}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _LogBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _LogBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogDiffRow extends StatelessWidget {
  final _LogDiffRowViewModel row;
  final bool singleValueMode;

  const _LogDiffRow({
    required this.row,
    this.singleValueMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (singleValueMode) {
      final value = row.newValue.hasValue ? row.newValue : row.oldValue;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              row.label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DiffValueBox(
              title: 'ערך',
              value: value,
              tone: _ValueTone.newValue,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  row.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: _DiffValueBox(
                  title: 'לפני',
                  value: row.oldValue,
                  tone: _ValueTone.old,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.grey.shade500,
                  textDirection: TextDirection.ltr,
                ),
              ),
              Expanded(
                child: _DiffValueBox(
                  title: 'אחרי',
                  value: row.newValue,
                  tone: _ValueTone.newValue,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            _DiffValueBox(
              title: 'לפני',
              value: row.oldValue,
              tone: _ValueTone.old,
            ),
            const SizedBox(height: 8),
            _DiffValueBox(
              title: 'אחרי',
              value: row.newValue,
              tone: _ValueTone.newValue,
            ),
          ],
        );
      },
    );
  }
}

class _DiffValueBox extends StatelessWidget {
  final String title;
  final _FormattedValue value;
  final _ValueTone tone;

  const _DiffValueBox({
    required this.title,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final palette = switch (tone) {
      _ValueTone.old => (
          background: Colors.grey.shade100,
          border: Colors.grey.shade300,
          text: Colors.grey.shade800,
        ),
      _ValueTone.newValue => (
          background: Colors.green.shade50,
          border: Colors.green.shade200,
          text: Colors.green.shade900,
        ),
    };

    final textColor = value.color ??
        (value.isPlaceholder ? Colors.grey.shade600 : palette.text);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (value.icon != null) ...[
                Icon(value.icon, size: 16, color: textColor),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  value.text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    height: 1.4,
                    fontFamily: value.monospace ? 'monospace' : null,
                    fontStyle: value.isPlaceholder ? FontStyle.italic : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ValueTone { old, newValue }

class _LogDetailRow extends StatefulWidget {
  final _LogDetailRowViewModel row;

  const _LogDetailRow({
    required this.row,
  });

  @override
  State<_LogDetailRow> createState() => _LogDetailRowState();
}

class _LogDetailRowState extends State<_LogDetailRow> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final textColor = row.value.color ??
        (row.value.isPlaceholder ? Colors.grey.shade600 : Colors.grey.shade900);

    if (row.expandableItems.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.value.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          _isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  for (int index = 0;
                      index < row.expandableItems.length;
                      index++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: index == row.expandableItems.length - 1 ? 0 : 8,
                      ),
                      child: _LogExpandableListItemView(
                        item: row.expandableItems[index],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            row.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.value.icon != null) ...[
                Icon(row.value.icon, size: 15, color: textColor),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  row.value.text,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                    height: 1.4,
                    fontFamily: row.value.monospace ? 'monospace' : null,
                    fontStyle:
                        row.value.isPlaceholder ? FontStyle.italic : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogExpandableListItemView extends StatelessWidget {
  final _LogExpandableListItem item;

  const _LogExpandableListItemView({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.color.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 18, color: item.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogSummaryViewModel {
  final _LogChipData action;
  final _LogChipData status;
  final String actor;
  final String entityLabel;
  final String? entityName;
  final String primaryLine;
  final String secondaryLine;
  final String summarySentence;
  final String timestampText;
  final String operationLabel;
  final String? sourceLabel;
  final List<_LogDiffRowViewModel> diffRows;
  final List<_LogDetailRowViewModel> detailRows;
  final Map<String, dynamic> rawData;
  final bool showDiffSection;
  final bool useCreatedValuesMode;
  final String diffSectionTitle;

  const _LogSummaryViewModel({
    required this.action,
    required this.status,
    required this.actor,
    required this.entityLabel,
    required this.entityName,
    required this.primaryLine,
    required this.secondaryLine,
    required this.summarySentence,
    required this.timestampText,
    required this.operationLabel,
    required this.sourceLabel,
    required this.diffRows,
    required this.detailRows,
    required this.rawData,
    required this.showDiffSection,
    required this.useCreatedValuesMode,
    required this.diffSectionTitle,
  });
}

class _LogChipData {
  final String label;
  final IconData icon;
  final Color color;

  const _LogChipData({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _LogDiffRowViewModel {
  final String label;
  final _FormattedValue oldValue;
  final _FormattedValue newValue;

  const _LogDiffRowViewModel({
    required this.label,
    required this.oldValue,
    required this.newValue,
  });
}

class _LogDetailRowViewModel {
  final String label;
  final _FormattedValue value;
  final List<_LogExpandableListItem> expandableItems;

  const _LogDetailRowViewModel({
    required this.label,
    required this.value,
    this.expandableItems = const [],
  });
}

class _LogExpandableListItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _LogExpandableListItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _ChangeValues {
  final dynamic oldValue;
  final dynamic newValue;

  const _ChangeValues({
    required this.oldValue,
    required this.newValue,
  });
}

class _FormattedValue {
  final String text;
  final bool isPlaceholder;
  final IconData? icon;
  final Color? color;
  final bool monospace;

  const _FormattedValue({
    required this.text,
    this.isPlaceholder = false,
    this.icon,
    this.color,
    this.monospace = false,
  });

  const _FormattedValue.placeholder(String text)
      : this(
          text: text,
          isPlaceholder: true,
        );

  bool get hasValue => !isPlaceholder;
}
