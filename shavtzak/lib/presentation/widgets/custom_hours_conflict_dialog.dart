import 'package:flutter/material.dart';

import '../../core/debug/logger.dart';

/// The question put to the admin when the hours they gave a member overlap the
/// member's constraints (`customHoursWarningLines`): one line per constraint,
/// then "cancel" or "save anyway". The hours are not blocked, only warned
/// about, exactly like assigning a constrained member.
class CustomHoursConflictDialog extends StatelessWidget {
  /// One finished warning line per conflicting constraint.
  final List<String> lines;

  const CustomHoursConflictDialog({super.key, required this.lines});

  /// True when the admin chose "שמור בכל זאת"; false for "ביטול" or a dismissed
  /// dialog.
  static Future<bool> show(
    BuildContext context, {
    required List<String> lines,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => CustomHoursConflictDialog(lines: lines),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('⚠️ התנגשות עם אילוצים'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(line),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('tap:cancel:customHoursConflictDialog');
              Navigator.of(context).pop(false);
            },
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              Logger.action('tap:saveAnyway:customHoursConflictDialog');
              Navigator.of(context).pop(true);
            },
            child: const Text('שמור בכל זאת'),
          ),
        ],
      ),
    );
  }
}
