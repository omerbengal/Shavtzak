import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'passcode_setup_dialog.dart';

/// Dialog for admins to manage team member passcodes
class AdminPasscodeDialog extends StatefulWidget {
  final String teamMemberName;
  final String? currentPasscode;
  final int? currentLength;

  const AdminPasscodeDialog({
    super.key,
    required this.teamMemberName,
    this.currentPasscode,
    this.currentLength,
  });

  @override
  State<AdminPasscodeDialog> createState() => _AdminPasscodeDialogState();
}

class _AdminPasscodeDialogState extends State<AdminPasscodeDialog> {
  bool _showPasscode = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          'ניהול קוד גישה: ${widget.teamMemberName}',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'את/ה נכנס/ת כמנהל/ת לחשבון של חבר צוות אחר',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (widget.currentPasscode != null) ...[
                const Text(
                  'קוד גישה נוכחי:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showPasscode
                            ? widget.currentPasscode!
                            : '•' * (widget.currentLength ?? 4),
                        style: const TextStyle(
                          fontSize: 20,
                          letterSpacing: 4,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _showPasscode = !_showPasscode),
                        icon: Icon(
                          _showPasscode ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey[600],
                        ),
                        tooltip: _showPasscode ? 'הסתר קוד' : 'הצג קוד',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                Icon(
                  Icons.lock_open,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                const Text(
                  'לא הוגדר קוד גישה',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 24),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => _showSetPasscodeDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.currentPasscode != null
                          ? Theme.of(context).primaryColor
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: Text(widget.currentPasscode != null ? 'שנה קוד' : 'הגדר קוד'),
                  ),
                  if (widget.currentPasscode != null) ...[
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _showRemoveConfirmation(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: const Text('הסר קוד'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  void _showSetPasscodeDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => const PasscodeSetupDialog(),
    );

    if (result != null && context.mounted) {
      Navigator.of(context).pop({
        'action': 'set',
        'passcode': result['passcode'],
        'length': result['length'],
      });
    }
  }

  void _showRemoveConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('אישור הסרת קוד גישה', textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          content: Text(
            'האם את/ה בטוח/ה שברצונך להסיר את קוד הגישה עבור ${widget.teamMemberName}?\n\nפעולה זו תאפשר לכל אחד לגשת לחשבון זה.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול', textAlign: TextAlign.center),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('הסר קוד', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop({
        'action': 'remove',
      });
    }
  }
}