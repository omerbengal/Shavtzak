import 'package:flutter/material.dart';

import '../../core/debug/logger.dart';
import '../../core/services/push_notification_service.dart';
import 'push_prompt_dialog.dart';

/// How to undo a refusal in the browser's own window (the app cannot).
const String pushUnblockSteps =
    'איך לפתוח: אנדרואיד ← לפתוח את האתר ב-Chrome ← הסמל שליד הכתובת ← הרשאות ← התראות. '
    'אייפון ← הגדרות ← עדכונים ← shavtzak, או למחוק ולהוסיף שוב למסך הבית.';

/// The "התראות" row of the settings dialog: on (a switch to turn it off), off
/// (a button), blocked (how to undo it), or an iPhone in the browser.
/// [PushNotificationService] holds the rules; this only shows them.
class PushSettingsSection extends StatefulWidget {
  const PushSettingsSection({super.key, this.service});

  final PushNotificationService? service;

  @override
  State<PushSettingsSection> createState() => _PushSettingsSectionState();
}

class _PushSettingsSectionState extends State<PushSettingsSection> {
  PushNotificationService get _push => widget.service ?? PushNotificationService.instance;
  PushStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await _push.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _run(String action, Future<PushStatus> Function() step) async {
    Logger.action(action);
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final status = await step();
      if (!mounted) return;
      setState(() => _status = status);
      if (status == PushStatus.notAsked || (action == 'tap:pushSettingsEnable' && status == PushStatus.off)) {
        messenger?.showSnackBar(const SnackBar(content: Text(pushNotEnabledText)));
      }
    } catch (error) {
      debugPrint('push: $action failed: $error');
      Logger.warning('push:actionFailed', {'action': action, 'error': error.toString()});
      messenger?.showSnackBar(const SnackBar(content: Text('הפעולה נכשלה. נסה שוב')));
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _enable() {
    // Started inside the tap: iPhone asks for permission only then.
    final result = _push.enable();
    _run('tap:pushSettingsEnable', () => result);
  }

  void _disable() => _run('tap:pushSettingsDisable', _push.disable);

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final theme = Theme.of(context);
    Widget body;
    switch (status) {
      case null:
        body = const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      case PushStatus.enabled:
        body = Row(
          children: [
            const Expanded(child: Text('פעיל במכשיר הזה')),
            Switch(
              key: const Key('push-settings-switch'),
              value: true,
              onChanged: _busy ? null : (_) => _disable(),
            ),
          ],
        );
      case PushStatus.off:
      case PushStatus.notAsked:
      case PushStatus.noWindow:
        body = Column(
          children: [
            const Text('כבוי'),
            if (status == PushStatus.noWindow) ...[
              const SizedBox(height: 6),
              Text(pushChromeAllowSteps, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            ElevatedButton.icon(
              key: const Key('push-settings-enable'),
              onPressed: _busy ? null : _enable,
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('הפעל התראות'),
            ),
          ],
        );
      case PushStatus.blocked:
        body = Column(
          children: [
            const Text('חסום בדפדפן', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(pushUnblockSteps, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        );
      case PushStatus.iosInstallNeeded:
        body = Text(
          'באייפון התראות עובדות רק מהאייקון במסך הבית: ${iosInstallSteps.join(' ← ')}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        );
      case PushStatus.unsupported:
        body = const Text('הדפדפן הזה לא תומך בהתראות', textAlign: TextAlign.center);
    }
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_outlined, color: theme.primaryColor, size: 18),
                const SizedBox(width: 4),
                const Text('התראות', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            body,
          ],
        ),
      ),
    );
  }
}
