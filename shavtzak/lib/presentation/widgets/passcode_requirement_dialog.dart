import 'package:flutter/material.dart';
import '../../core/debug/logger.dart';

/// Dialog that prompts users without a passcode to set one
class PasscodeRequirementDialog extends StatelessWidget {
  final VoidCallback onGoToSettings;
  final VoidCallback? onDismiss;

  const PasscodeRequirementDialog({
    super.key,
    required this.onGoToSettings,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final isSmallScreen = screenWidth < 470;

          // Calculate continuous font size scaling for small screens
          // When width is 470, use full size (16 and 14)
          // When width is 300, use reduced size (13.5 and 11.5)
          final double mainFontSize = isSmallScreen
              ? 16 * (screenWidth / 470)
              : 16;

          final double descriptionFontSize = isSmallScreen
              ? 14 * (screenWidth / 470)
              : 14;

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).primaryColor,
                  size: isSmallScreen ? 20 : 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'הגדרת קוד גישה',
                    style: TextStyle(fontSize: mainFontSize),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'שמנו לב שעדיין לא הגדרת קוד גישה לחשבון שלך.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: mainFontSize),
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(
                  'קוד גישה עוזר להגן על החשבון שלך ומונע מאחרים לגשת אליו.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: descriptionFontSize,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            actions: [
              if (isSmallScreen)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Logger.action('tap:cancel:passcodeRequirement');
                          Navigator.of(context).pop();
                          onDismiss?.call();
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('אחר כך'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Logger.action('tap:goToSettings');
                          Navigator.of(context).pop();
                          onGoToSettings();
                        },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('הבנתי, קחו אותי להגדרות'),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        Logger.action('tap:cancel:passcodeRequirement');
                        Navigator.of(context).pop();
                        onDismiss?.call();
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('אחר כך'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Logger.action('tap:goToSettings');
                        Navigator.of(context).pop();
                        onGoToSettings();
                      },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('הבנתי, קחו אותי להגדרות'),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  /// Show the passcode requirement dialog
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onGoToSettings,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PasscodeRequirementDialog(
        onGoToSettings: onGoToSettings,
        onDismiss: onDismiss,
      ),
    );
  }
}
