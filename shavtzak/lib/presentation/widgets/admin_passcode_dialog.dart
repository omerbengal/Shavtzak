import 'package:flutter/material.dart';
import 'passcode_setup_dialog.dart';

/// Dialog for admins to manage team member passcodes
class AdminPasscodeDialog extends StatefulWidget {
  final String teamMemberName;
  final int? currentLength;
  final Future<String> Function()? onRevealPasscode;

  const AdminPasscodeDialog({
    super.key,
    required this.teamMemberName,
    this.currentLength,
    this.onRevealPasscode,
  });

  @override
  State<AdminPasscodeDialog> createState() => _AdminPasscodeDialogState();
}

class _AdminPasscodeDialogState extends State<AdminPasscodeDialog> {
  bool _showPasscode = false;
  bool _isLoadingPasscode = false;
  String? _currentPasscode;

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
                  color: Colors.orange.withValues(alpha: 0.1),
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
              if (widget.currentLength != null) ...[
                Text(
                  'קוד גישה מוגדר (${widget.currentLength} ספרות)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _showPasscode && _currentPasscode != null
                              ? _currentPasscode!
                              : '•' * (widget.currentLength ?? 4),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      if (widget.onRevealPasscode != null)
                        _isLoadingPasscode
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                onPressed: _togglePasscodeVisibility,
                                icon: Icon(
                                  _showPasscode
                                      ? Icons.visibility_off
                                      : Icons.visibility,
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
                      backgroundColor: widget.currentLength != null
                          ? Theme.of(context).primaryColor
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: Text(
                        widget.currentLength != null ? 'שנה קוד' : 'הגדר קוד'),
                  ),
                  if (widget.currentLength != null) ...[
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _showRemoveConfirmation(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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

  Future<void> _togglePasscodeVisibility() async {
    if (_showPasscode) {
      setState(() => _showPasscode = false);
      return;
    }

    if (_currentPasscode != null) {
      setState(() => _showPasscode = true);
      return;
    }

    if (widget.onRevealPasscode == null || _isLoadingPasscode) {
      return;
    }

    setState(() => _isLoadingPasscode = true);

    try {
      final passcode = await widget.onRevealPasscode!();
      if (!mounted) {
        return;
      }
      setState(() {
        _currentPasscode = passcode;
        _showPasscode = true;
        _isLoadingPasscode = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingPasscode = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('UserSelectionException: ', ''),
            ),
            backgroundColor: Colors.red,
          ),
        );
    }
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
