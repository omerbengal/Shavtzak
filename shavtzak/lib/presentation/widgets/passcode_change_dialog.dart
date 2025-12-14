import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'passcode_digit_field.dart';

/// Dialog for changing an existing passcode
class PasscodeChangeDialog extends StatefulWidget {
  final String currentPasscode;
  final int currentLength;

  const PasscodeChangeDialog({
    super.key,
    required this.currentPasscode,
    required this.currentLength,
  });

  @override
  State<PasscodeChangeDialog> createState() => _PasscodeChangeDialogState();
}

class _PasscodeChangeDialogState extends State<PasscodeChangeDialog> {
  int _currentStep = 0;
  int _selectedLength = 4;
  final List<TextEditingController> _currentControllers = [];
  final List<TextEditingController> _passcodeControllers = [];
  final List<TextEditingController> _confirmControllers = [];
  final List<FocusNode> _currentFocusNodes = [];
  final List<FocusNode> _passcodeFocusNodes = [];
  final List<FocusNode> _confirmFocusNodes = [];
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _selectedLength = widget.currentLength;

    // Initialize controllers and focus nodes
    for (int i = 0; i < 6; i++) {
      _currentControllers.add(TextEditingController());
      _passcodeControllers.add(TextEditingController());
      _confirmControllers.add(TextEditingController());
      _currentFocusNodes.add(FocusNode());
      _passcodeFocusNodes.add(FocusNode());
      _confirmFocusNodes.add(FocusNode());
    }

    // Robust focus mechanism: Use both postFrameCallback and delayed focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _currentFocusNodes[0].requestFocus();
        // Additional delayed focus to handle dialog animation completion
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _currentFocusNodes[0].requestFocus();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    for (var controller in _currentControllers) {
      controller.dispose();
    }
    for (var controller in _passcodeControllers) {
      controller.dispose();
    }
    for (var controller in _confirmControllers) {
      controller.dispose();
    }
    for (var focusNode in _currentFocusNodes) {
      focusNode.dispose();
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
        title: Text(_currentStep == 0 ? 'שינוי קוד גישה' :
                   _currentStep == 1 ? 'בחר אורך חדש' :
                   _currentStep == 2 ? 'הזן קוד גישה חדש' : 'אשר קוד גישה חדש'),
        content: SizedBox(
          width: 400,
          child: _buildCurrentStep(),
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildCurrentPasscodeEntry();
      case 1:
        return _buildLengthSelection();
      case 2:
        return _buildPasscodeEntry(isConfirm: false);
      case 3:
        return _buildPasscodeEntry(isConfirm: true);
      default:
        return Container();
    }
  }

  Widget _buildCurrentPasscodeEntry() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'הזן את קוד הגישה הנוכחי:',
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        if (_isError) ...[
          const SizedBox(height: 8),
          Text(
            'קוד גישה שגוי',
            style: TextStyle(
              fontSize: 14,
              color: Colors.red[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        PasscodeInputRow(
          digitCount: widget.currentLength,
          controllers: _currentControllers,
          focusNodes: _currentFocusNodes,
          obscureText: _obscureCurrent,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
            icon: Icon(
              _obscureCurrent ? Icons.visibility_off : Icons.visibility,
              size: 20,
            ),
            label: Text(_obscureCurrent ? 'הצג קוד' : 'הסתר קוד'),
          ),
        ),
      ],
    );
  }

  Widget _buildLengthSelection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'בחר אורך חדש לקוד גישה:',
          style: TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildLengthOption(4),
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
          color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
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
      children: [
        Text(
          isConfirm ? 'הזן שוב את קוד הגישה החדש:' : 'הזן קוד גישה חדש:',
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        PasscodeInputRow(
          digitCount: _selectedLength,
          controllers: controllers,
          focusNodes: focusNodes,
          obscureText: _obscureNew,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: () => setState(() => _obscureNew = !_obscureNew),
            icon: Icon(
              _obscureNew ? Icons.visibility_off : Icons.visibility,
              size: 20,
            ),
            label: Text(_obscureNew ? 'הצג קוד' : 'הסתר קוד'),
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
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _verifyCurrentPasscode,
            child: const Text('הבא'),
          ),
        ];
      case 1:
        return [
          TextButton(
            onPressed: () => setState(() => _currentStep = 0),
            child: const Text('חזור'),
          ),
          ElevatedButton(
            onPressed: _nextStep,
            child: const Text('הבא'),
          ),
        ];
      case 2:
        return [
          TextButton(
            onPressed: () => setState(() => _currentStep = 1),
            child: const Text('חזור'),
          ),
          ElevatedButton(
            onPressed: _validateAndProceed,
            child: const Text('הבא'),
          ),
        ];
      case 3:
        return [
          TextButton(
            onPressed: () => setState(() => _currentStep = 2),
            child: const Text('חזור'),
          ),
          ElevatedButton(
            onPressed: _validateAndConfirm,
            child: const Text('אישור'),
          ),
        ];
      default:
        return [];
    }
  }

  void _verifyCurrentPasscode() {
    final enteredPasscode = _getEnteredPasscode(_currentControllers, widget.currentLength);

    if (enteredPasscode.length != widget.currentLength) {
      _showError('אנא הזן קוד גישה שלם');
      return;
    }

    if (enteredPasscode != widget.currentPasscode) {
      setState(() => _isError = true);
      // Clear all fields
      for (var controller in _currentControllers) {
        controller.clear();
      }
      _currentFocusNodes[0].requestFocus();
      return;
    }

    // Success, proceed to length selection
    setState(() {
      _currentStep = 1;
      _isError = false;
    });
  }

  void _nextStep() {
    // Clear passcode fields
    for (int i = 0; i < _passcodeControllers.length; i++) {
      _passcodeControllers[i].clear();
    }
    
    setState(() {
      _currentStep = 2;
    });
    
    // Robust focus mechanism: Use both postFrameCallback and delayed focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _passcodeFocusNodes[0].requestFocus();
        // Additional delayed focus to handle dialog animation completion
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _passcodeFocusNodes[0].requestFocus();
          }
        });
      }
    });
  }

  void _validateAndProceed() {
    final passcode = _getEnteredPasscode(_passcodeControllers, _selectedLength);

    if (passcode.length != _selectedLength) {
      _showError('אנא הזן קוד גישה שלם');
      return;
    }

    // Clear confirm fields
    for (int i = 0; i < _confirmControllers.length; i++) {
      _confirmControllers[i].clear();
    }

    setState(() {
      _currentStep = 3;
    });
    
    // Robust focus mechanism: Use both postFrameCallback and delayed focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _confirmFocusNodes[0].requestFocus();
        // Additional delayed focus to handle dialog animation completion
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _confirmFocusNodes[0].requestFocus();
          }
        });
      }
    });
  }

  void _validateAndConfirm() {
    final passcode = _getEnteredPasscode(_passcodeControllers, _selectedLength);
    final confirm = _getEnteredPasscode(_confirmControllers, _selectedLength);

    if (confirm.length != _selectedLength) {
      _showError('אנא הזן קוד גישה שלם');
      return;
    }

    if (passcode != confirm) {
      _showError('הקודים אינם תואמים, אנא נסה שוב');
      return;
    }

    // Success! Return the new passcode
    Navigator.of(context).pop({
      'passcode': passcode,
      'length': _selectedLength,
    });
  }

  String _getEnteredPasscode(List<TextEditingController> controllers, int length) {
    return controllers
        .take(length)
        .map((c) => c.text)
        .join();
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