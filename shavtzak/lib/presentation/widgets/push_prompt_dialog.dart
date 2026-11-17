import 'package:flutter/material.dart';

import '../../core/debug/logger.dart';
import '../../core/services/push_notification_service.dart';

/// The steps that add the app to an iPhone's home screen, where its
/// notifications live.
const List<String> iosInstallSteps = [
  'כפתור השיתוף בספארי',
  '"הוספה למסך הבית"',
  'לפתוח משם וללחוץ "הפעל"',
];

/// After "הפעל התראות" when the browser gave no permission and did not block.
const String pushNotEnabledText =
    'ההתראות לא הופעלו: לא התקבל אישור מהדפדפן. אפשר לנסות שוב בהגדרות';

/// The text after "הפעל התראות", or null when there is nothing to say.
String? pushEnableResultText(PushStatus status) {
  switch (status) {
    case PushStatus.enabled:
      return '🔔 ההתראות הופעלו במכשיר הזה';
    case PushStatus.blocked:
      return 'ההתראות נחסמו בדפדפן. אפשר לפתוח אותן בהגדרות';
    case PushStatus.notAsked:
    case PushStatus.off:
      // The browser answered without a "yes" (its window closed, or it never
      // showed one): never leave the tap without a word.
      return pushNotEnabledText;
    default:
      return null;
  }
}

/// The popup that asks this device for notifications (design approved by
/// Omer, 16/11/2026): it opens by itself while the device was not asked
/// ([PushNotificationService.shouldPrompt]); on an iPhone in the browser it
/// explains the home-screen app instead. "לא עכשיו" / "הבנתי" hold it back
/// until the next app version.
class PushPromptDialog extends StatelessWidget {
  const PushPromptDialog({
    super.key,
    required this.iosInstall,
    required this.onEnable,
    required this.onLater,
  });

  final bool iosInstall;

  /// Runs straight from the tap: iPhone asks for permission only then.
  final VoidCallback onEnable;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = iosInstall ? 'התראות באייפון' : 'התראות על משימות';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: theme.primaryColor),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: iosInstall
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('באייפון התראות עובדות רק מהאייקון במסך הבית:'),
                  const SizedBox(height: 12),
                  for (var i = 0; i < iosInstallSteps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${i + 1}. ${iosInstallSteps[i]}'),
                    ),
                ],
              )
            : const Text(
                'נעדכן אותך כשמשבצים אותך למשימה, גם כשהאפליקציה סגורה.',
                textAlign: TextAlign.center,
              ),
        actionsAlignment: MainAxisAlignment.center,
        actions: iosInstall
            ? [
                ElevatedButton(
                  key: const Key('push-prompt-ok'),
                  onPressed: onLater,
                  child: const Text('הבנתי'),
                ),
              ]
            : [
                TextButton(
                  key: const Key('push-prompt-later'),
                  onPressed: onLater,
                  child: const Text('לא עכשיו'),
                ),
                ElevatedButton(
                  key: const Key('push-prompt-enable'),
                  onPressed: onEnable,
                  child: const Text('הפעל התראות'),
                ),
              ],
      ),
    );
  }
}

bool _promptedThisSession = false;

@visibleForTesting
void resetPushPromptSession() => _promptedThisSession = false;

/// Opens [PushPromptDialog] when this device should be asked (once per app
/// session at most). [canReceive]: the member may get notifications at all.
Future<void> maybeShowPushPrompt(
  BuildContext context, {
  required bool canReceive,
  required String? appVersion,
  PushNotificationService? service,
}) async {
  if (!canReceive || _promptedThisSession) return;
  final push = service ?? PushNotificationService.instance;
  final status = await push.status();
  if (!await push.shouldPrompt(status, appVersion)) return;
  if (!context.mounted || _promptedThisSession) return;
  _promptedThisSession = true;
  Logger.action('open:pushPrompt', {'status': status.name});
  final messenger = ScaffoldMessenger.maybeOf(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => PushPromptDialog(
      iosInstall: status == PushStatus.iosInstallNeeded,
      onLater: () {
        Logger.action('tap:pushPromptLater');
        Navigator.of(dialogContext).pop();
        push.snooze(appVersion);
      },
      onEnable: () {
        Logger.action('tap:pushPromptEnable');
        // Started inside the tap, before anything awaits.
        final result = push.enable();
        Navigator.of(dialogContext).pop();
        result.then((status) {
          final text = pushEnableResultText(status);
          if (text != null) messenger?.showSnackBar(SnackBar(content: Text(text)));
        }).catchError((Object error) {
          debugPrint('push: enable from the popup failed: $error');
          Logger.warning('push:enableFailed', {'error': error.toString()});
          messenger?.showSnackBar(
            const SnackBar(content: Text('לא הצלחנו להפעיל התראות. אפשר לנסות שוב בהגדרות')),
          );
        });
      },
    ),
  );
}
