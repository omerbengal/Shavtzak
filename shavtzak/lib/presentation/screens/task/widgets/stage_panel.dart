import 'package:flutter/material.dart';

import '../task_style.dart';
import 'task_sheet.dart';

/// The wide layout's left panel: the sheet's content without the sheet.
///
/// A header row (back, title, X) over the content's body, which scrolls on
/// its own; with nothing open, a hint to pick a stage.
class StagePanel extends StatelessWidget {
  const StagePanel({
    super.key,
    required this.content,
    required this.onClose,
    this.onBack,
    this.viewKey,
  });

  /// What is open; null shows the hint.
  final SheetContent? content;

  /// What is being shown; a new one starts the body at its top.
  final Object? viewKey;

  final VoidCallback onClose;

  /// Back to the previous view; no back arrow when null.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final content = this.content;
    if (content == null) {
      return const Center(
        key: Key('stage-panel'),
        child: Padding(
          key: Key('stage-panel-hint'),
          padding: EdgeInsets.all(TaskStyle.panelPadding),
          child: Text(
            'בחרו שלב בלוח כדי לראות את המשימות שלו',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TaskStyle.panelHintSize,
              color: TaskStyle.neutralText,
            ),
          ),
        ),
      );
    }
    return Column(
      key: const Key('stage-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              TaskStyle.panelPadding / 2,
              TaskStyle.panelPadding / 4,
              TaskStyle.panelPadding / 2,
              TaskStyle.panelPadding / 4),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  key: const Key('stage-panel-back'),
                  tooltip: 'חזרה',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
              Expanded(child: content.header),
              IconButton(
                key: const Key('stage-panel-close'),
                tooltip: 'סגירה',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey(viewKey),
            child: content.body,
          ),
        ),
      ],
    );
  }
}
