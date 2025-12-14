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
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  int _failedAttempts = 0;
  bool _isError = false;
  bool _isBlocked = false;
  int _blockCountdown = 0;

  @override
  void initState() {
    super.initState();
    // Initialize controllers and focus nodes
    for (int i = 0; i < 6; i++) {
      _controllers.add(TextEditingController());
      _focusNodes.add(FocusNode());
    }

    // Focus on first field
    Future.delayed(const Duration(milliseconds: 100), () {
      _focusNodes[0].requestFocus();
    });
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
        title: const Text('הזן קוד גישה'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isBlocked) ...[
                Icon(
                  Icons.lock,
                  size: 64,
                  color: Colors.red[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'יותר מדי ניסיונות כושלים',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.red[600],
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'נסה שוב בעוד $_blockCountdown שניות',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Text(
                  'הזן קוד גישה של ${widget.passcodeLength} ספרות:',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                if (_isError) ...[
                  const SizedBox(height: 8),
                  Text(
                    'קוד שגוי. ניסיונות נותרים: ${3 - _failedAttempts}',
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
                ),
              ],
            ],
          ),
        ),
        actions: _isBlocked
            ? [
                TextButton(
                  onPressed: null,
                  child: Text('חכה $_blockCountdown שניות'),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ביטול'),
                ),
                ElevatedButton(
                  onPressed: _isBlocked ? null : _verifyPasscode,
                  child: const Text('אישור'),
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
        _failedAttempts++;
        _isError = true;
      });

      // Clear all fields
      for (var controller in _controllers) {
        controller.clear();
      }

      // Focus back to first field
      _focusNodes[0].requestFocus();

      if (_failedAttempts >= 3) {
        // Block user with exponential backoff
        _blockUser();
      } else {
        // Shake animation
        _shakeError();
      }
    }
  }

  String _getEnteredPasscode() {
    return _controllers
        .take(widget.passcodeLength)
        .map((c) => c.text)
        .join();
  }

  void _blockUser() {
    setState(() {
      _isBlocked = true;
      _blockCountdown = _getBlockDuration();
    });

    // Countdown timer
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _blockCountdown > 1) {
        setState(() => _blockCountdown--);
        _blockUser();
      } else if (mounted) {
        // Unblock and reset
        setState(() {
          _isBlocked = false;
          _isError = false;
          _failedAttempts = 0;
          _blockCountdown = 0;
        });
        _focusNodes[0].requestFocus();
      }
    });
  }

  int _getBlockDuration() {
    // Exponential backoff: 2^failedAttempts seconds
    // 3 attempts: 8 seconds
    return 8;
  }

  void _shakeError() {
    HapticFeedback.lightImpact();
    // Visual feedback is handled by the red border
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}