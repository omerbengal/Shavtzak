import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'passcode_digit_field.dart';

/// Dialog for verifying passcode before allowing user selection
class PasscodeVerificationDialog extends StatefulWidget {
  final int passcodeLength;
  final String correctPasscode;

  const PasscodeVerificationDialog({
    super.key,
    required this.passcodeLength,
    required this.correctPasscode,
  });

  @override
  State<PasscodeVerificationDialog> createState() => _PasscodeVerificationDialogState();
}

class _PasscodeVerificationDialogState extends State<PasscodeVerificationDialog> {
  static const double _iconSize = 20.0;

  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  bool _isError = false;
  bool _obscurePasscode = true;

  @override
  void initState() {
    super.initState();
    // Initialize controllers and focus nodes
    for (int i = 0; i < 6; i++) {
      _controllers.add(TextEditingController());
      _focusNodes.add(FocusNode());
    }
    // No auto-focus: user must tap a digit field to open keyboard.
    // This ensures keyboard opens reliably on mobile (direct user gesture).
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('הזן קוד גישה', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'הזן קוד גישה של ${widget.passcodeLength} ספרות:',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              if (_isError) ...[
                const SizedBox(height: 8),
                Text(
                  'קוד שגוי',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              PasscodeInputRow(
                digitCount: widget.passcodeLength,
                controllers: _controllers,
                focusNodes: _focusNodes,
                onAllFilled: () {
                  // Auto-submit when all fields are filled
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _verifyPasscode();
                  });
                },
                obscureText: _obscurePasscode,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: () => setState(() => _obscurePasscode = !_obscurePasscode),
                  icon: Icon(
                    _obscurePasscode ? Icons.visibility_off : Icons.visibility,
                    size: _iconSize,
                  ),
                  label: Text(_obscurePasscode ? 'הצג קוד' : 'הסתר קוד'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול', textAlign: TextAlign.center),
          ),
          ElevatedButton(
            onPressed: _verifyPasscode,
            child: const Text('אישור', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  void _verifyPasscode() {
    final enteredPasscode = _getEnteredPasscode();

    if (enteredPasscode.length != widget.passcodeLength) {
      _showError('אנא הזן קוד גישה שלם');
      return;
    }

    if (enteredPasscode == widget.correctPasscode) {
      // Success!
      Navigator.of(context).pop(true);
    } else {
      // Failed attempt
      setState(() {
        _isError = true;
      });

      // Clear all fields
      for (var controller in _controllers) {
        controller.clear();
      }

      // Focus back to first field
      _focusNodes[0].requestFocus();

      // Haptic feedback
      HapticFeedback.lightImpact();
    }
  }

  String _getEnteredPasscode() {
    return _controllers
        .take(widget.passcodeLength)
        .map((c) => c.text)
        .join();
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שגיאה', textAlign: TextAlign.center),
          content: Text(message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('אישור', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}