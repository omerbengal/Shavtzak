import 'package:flutter/material.dart';
import 'passcode_digit_field.dart';

/// Dialog for setting up a new passcode
class PasscodeSetupDialog extends StatefulWidget {
  const PasscodeSetupDialog({super.key});

  @override
  State<PasscodeSetupDialog> createState() => _PasscodeSetupDialogState();
}

class _PasscodeSetupDialogState extends State<PasscodeSetupDialog> {
  static const double _iconSize = 20.0;
  
  int _currentStep = 0;
  int _selectedLength = 4;
  final List<TextEditingController> _passcodeControllers = [];
  final List<TextEditingController> _confirmControllers = [];
  final List<FocusNode> _passcodeFocusNodes = [];
  final List<FocusNode> _confirmFocusNodes = [];
  bool _obscurePasscode = true;

  @override
  void initState() {
    super.initState();
    // Initialize controllers and focus nodes
    for (int i = 0; i < 6; i++) {
      _passcodeControllers.add(TextEditingController());
      _confirmControllers.add(TextEditingController());
      _passcodeFocusNodes.add(FocusNode());
      _confirmFocusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    for (var controller in _passcodeControllers) {
      controller.dispose();
    }
    for (var controller in _confirmControllers) {
      controller.dispose();
    }
    for (var focusNode in _passcodeFocusNodes) {
      focusNode.dispose();
    }
    for (var focusNode in _confirmFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          _currentStep == 0 ? 'הגדרת קוד גישה' :
          _currentStep == 1 ? 'הזן קוד גישה' : 'אשר קוד גישה',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: _buildCurrentStep(),
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildLengthSelection();
      case 1:
        return _buildPasscodeEntry(isConfirm: false);
      case 2:
        return _buildPasscodeEntry(isConfirm: true);
      default:
        return Container();
    }
  }

  Widget _buildLengthSelection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'בחר אורך קוד גישה:',
          style: TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLengthOption(4),
            const SizedBox(width: 20),
            _buildLengthOption(6),
          ],
        ),
      ],
    );
  }

  Widget _buildLengthOption(int length) {
    final isSelected = _selectedLength == length;
    return GestureDetector(
      onTap: () => setState(() => _selectedLength = length),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$length',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey[700],
              ),
            ),
            Text(
              'ספרות',
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasscodeEntry({required bool isConfirm}) {
    final controllers = isConfirm ? _confirmControllers : _passcodeControllers;
    final focusNodes = isConfirm ? _confirmFocusNodes : _passcodeFocusNodes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          isConfirm ? 'הזן שוב את קוד הגישה:' : 'הזן קוד גישה:',
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PasscodeInputRow(
          digitCount: _selectedLength,
          controllers: controllers,
          focusNodes: focusNodes,
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
    );
  }

  List<Widget> _buildActions() {
    switch (_currentStep) {
      case 0:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול', textAlign: TextAlign.center),
          ),
          ElevatedButton(
            onPressed: _nextStep,
            child: const Text('הבא', textAlign: TextAlign.center),
          ),
        ];
      case 1:
        return [
          TextButton(
            onPressed: () => setState(() => _currentStep = 0),
            child: const Text('חזור', textAlign: TextAlign.center),
          ),
          ElevatedButton(
            onPressed: _validateAndProceed,
            child: const Text('הבא', textAlign: TextAlign.center),
          ),
        ];
      case 2:
        return [
          TextButton(
            onPressed: () => setState(() {
              _currentStep = 1;
              _obscurePasscode = true; // Reset visibility state when going back
            }),
            child: const Text('חזור', textAlign: TextAlign.center),
          ),
          ElevatedButton(
            onPressed: _validateAndConfirm,
            child: const Text('אישור', textAlign: TextAlign.center),
          ),
        ];
      default:
        return [];
    }
  }

  void _nextStep() {
    setState(() {
      _currentStep = 1;
    });
    // No auto-focus: user must tap a digit field to open keyboard
  }

  void _validateAndProceed() {
    final passcode = _getEnteredPasscode(_passcodeControllers);

    if (passcode.length != _selectedLength) {
      _showError('אנא הזן קוד גישה שלם');
      return;
    }

    // Clear previous entries
    for (int i = 0; i < _confirmControllers.length; i++) {
      _confirmControllers[i].clear();
    }

    setState(() {
      _currentStep = 2;
      _obscurePasscode = true; // Reset visibility state for confirm step
    });
    // No auto-focus: user must tap a digit field to open keyboard
  }

  void _validateAndConfirm() {
    final passcode = _getEnteredPasscode(_passcodeControllers);
    final confirm = _getEnteredPasscode(_confirmControllers);

    if (confirm.length != _selectedLength) {
      _showError('אנא הזן קוד גישה שלם');
      return;
    }

    if (passcode != confirm) {
      _showError('הקודים אינם תואמים, אנא נסה שוב');
      return;
    }

    // Success! Return the passcode
    Navigator.of(context).pop({
      'passcode': passcode,
      'length': _selectedLength,
    });
  }

  String _getEnteredPasscode(List<TextEditingController> controllers) {
    return controllers
        .take(_selectedLength)
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