import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single digit input field for passcodes with proper backspace handling
class PasscodeDigitField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscureText;
  final bool autoFocus;
  final int index;
  final int totalDigits;
  final List<TextEditingController> allControllers;
  final List<FocusNode> allFocusNodes;
  final VoidCallback? onAllFilled;

  const PasscodeDigitField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.index,
    required this.totalDigits,
    required this.allControllers,
    required this.allFocusNodes,
    this.obscureText = true,
    this.autoFocus = false,
    this.onAllFilled,
  });

  @override
  State<PasscodeDigitField> createState() => _PasscodeDigitFieldState();
}

class _PasscodeDigitFieldState extends State<PasscodeDigitField> {
  /// Find the first empty field index, or 0 if all fields are empty
  int _findFirstEmptyFieldIndex() {
    for (int i = 0; i < widget.totalDigits; i++) {
      if (widget.allControllers[i].text.isEmpty) {
        return i;
      }
    }
    // All fields are filled, return last field
    return widget.totalDigits - 1;
  }

  /// Handle tap on this field - redirect to first empty field if needed
  void _handleTap() {
    final targetIndex = _findFirstEmptyFieldIndex();
    if (targetIndex != widget.index) {
      // Redirect focus to the correct field
      widget.allFocusNodes[targetIndex].requestFocus();
    }
    // If targetIndex == widget.index, normal focus behavior will apply
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 50,
        height: 55,
        child: GestureDetector(
          onTap: _handleTap,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            autofocus: false, // Disabled - user must tap to open keyboard
            obscureText: widget.obscureText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            keyboardType: TextInputType.number,
            showCursor: true,
            readOnly: false,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(1),
            ],
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
            ),
            onTap: _handleTap,
            onChanged: (value) {
              // When a digit is entered, move to next field
              if (value.isNotEmpty && widget.index < widget.totalDigits - 1) {
                widget.allFocusNodes[widget.index + 1].requestFocus();
              }
              // Check if all fields are filled
              if (widget.onAllFilled != null) {
                bool allFilled = true;
                for (int i = 0; i < widget.totalDigits; i++) {
                  if (widget.allControllers[i].text.isEmpty) {
                    allFilled = false;
                    break;
                  }
                }
                if (allFilled) {
                  widget.onAllFilled!();
                }
              }
            },
          ),
        ),
      ),
    );
  }
}

/// A widget that wraps passcode digit fields with proper backspace handling
class PasscodeInputRow extends StatefulWidget {
  final int digitCount;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final VoidCallback? onAllFilled;
  final bool obscureText;

  const PasscodeInputRow({
    super.key,
    required this.digitCount,
    required this.controllers,
    required this.focusNodes,
    this.onAllFilled,
    this.obscureText = true,
  });

  @override
  State<PasscodeInputRow> createState() => _PasscodeInputRowState();
}

class _PasscodeInputRowState extends State<PasscodeInputRow> {
  final FocusNode _rowFocusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _rowFocusNode,
      onKeyEvent: (KeyEvent event) {
        // Handle backspace key
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          // Find the currently focused field
          for (int i = 0; i < widget.digitCount; i++) {
            if (widget.focusNodes[i].hasFocus) {
              // Always clear current field if it has content
              if (widget.controllers[i].text.isNotEmpty) {
                widget.controllers[i].clear();
                return;
              }
              // If current field is empty and not the first field
              else if (i > 0) {
                // Move to previous field
                widget.focusNodes[i - 1].requestFocus();
                // Clear the previous field's content
                widget.controllers[i - 1].clear();
                return;
              }
              break;
            }
          }
        }
      },
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.digitCount, (index) {
                return PasscodeDigitField(
                  controller: widget.controllers[index],
                  focusNode: widget.focusNodes[index],
                  index: index,
                  totalDigits: widget.digitCount,
                  allControllers: widget.controllers,
                  allFocusNodes: widget.focusNodes,
                  onAllFilled: widget.onAllFilled,
                  obscureText: widget.obscureText,
                  autoFocus: false, // Disabled - user tap triggers keyboard
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _rowFocusNode.dispose();
    super.dispose();
  }
}