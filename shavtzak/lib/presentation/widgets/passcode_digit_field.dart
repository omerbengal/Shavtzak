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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 40,
        height: 55,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: widget.autoFocus,
          obscureText: widget.obscureText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          keyboardType: TextInputType.numberWithOptions(signed: false, decimal: false),
          enableInteractiveSelection: false,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          decoration: InputDecoration(
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
    );
  }
}

/// A widget that wraps passcode digit fields with proper backspace handling
class PasscodeInputRow extends StatefulWidget {
  final int digitCount;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final VoidCallback? onAllFilled;

  const PasscodeInputRow({
    super.key,
    required this.digitCount,
    required this.controllers,
    required this.focusNodes,
    this.onAllFilled,
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
        child: Row(
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
            );
          }),
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