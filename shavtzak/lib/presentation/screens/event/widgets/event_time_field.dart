import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/time_input_formatter.dart';
import '../../../../core/utils/validators.dart';

/// One of the five optional time fields in the event form.
///
/// Typing is the primary path: the field raises a numpad and a formatter lays
/// the digits into `HH:mm`. The Cupertino wheel is still there, behind the clock
/// button — which RTL renders at the far *left* edge of the field, because the
/// `suffixIcon` slot is the trailing one.
class EventTimeField extends StatefulWidget {
  /// Owned by the host form, which also disposes it.
  final TextEditingController controller;
  final String label;
  final String hint;

  /// Suffix for this field's `Logger.action` keys, e.g. `assembly`.
  final String logKey;

  /// Fires on every edit, so the host form can mark itself dirty and rebuild.
  /// The two derive arrows read the controllers' text at build time, so without
  /// this they would go stale as soon as the admin typed instead of picked.
  final VoidCallback onChanged;

  /// Fires once the field holds a complete, valid time — from the wheel, or
  /// from blur completion after typing. Never fires per keystroke, and never
  /// when the value is unchanged since the field gained focus.
  final void Function(String value)? onTimeSet;

  const EventTimeField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.logKey,
    required this.onChanged,
    this.onTimeSet,
  });

  @override
  State<EventTimeField> createState() => _EventTimeFieldState();
}

class _EventTimeFieldState extends State<EventTimeField> {
  late final FocusNode _focusNode;
  late bool _hasValue;
  late String _valueOnFocusGain;

  /// True while the wheel dialog is up. Pushing that dialog steals primary
  /// focus off this field, which fires a blur — `_completeOnBlur` — before
  /// the admin has touched the wheel at all. This flag tells that blur to
  /// skip `onTimeSet`; the wheel calls it itself, on confirm, with whatever
  /// the admin actually picked.
  bool _openingWheel = false;

  /// `_valueOnFocusGain`, captured the instant before the wheel opens.
  ///
  /// The dialog-opening blur above makes `_completeOnBlur` skip `onTimeSet`
  /// unconditionally, on the assumption that the wheel will report the
  /// final value itself. Cancelling means it never does, so
  /// `_completeOnWheelCancel` is the only place left that can still fire it
  /// for a value the admin had already finished typing. It cannot compare
  /// against `_valueOnFocusGain` directly at that point: popping the dialog
  /// hands focus straight back to this field, re-running the focus-gained
  /// branch and refreshing `_valueOnFocusGain` to whatever the field now
  /// holds — erasing the very difference the cancel path needs to detect.
  /// This snapshot is taken before that round trip and stays put through it.
  String _valueBeforeWheelOpened = '';

  @override
  void initState() {
    super.initState();
    _hasValue = widget.controller.text.isNotEmpty;
    _valueOnFocusGain = widget.controller.text;
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    // The controller belongs to the host form — do not dispose it here.
    super.dispose();
  }

  /// Drives the ✕ button's visibility without depending on the host rebuilding.
  void _handleControllerChange() {
    final hasValue = widget.controller.text.isNotEmpty;
    if (hasValue != _hasValue) {
      setState(() => _hasValue = hasValue);
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _valueOnFocusGain = widget.controller.text;
      return;
    }
    _completeOnBlur();
  }

  /// Fill in a partial entry now that the admin has moved on.
  void _completeOnBlur() {
    final raw = widget.controller.text;
    final completed = completePartialTime(raw);
    if (completed != raw) {
      widget.controller.text = completed;
    }
    if (completed == _valueOnFocusGain) {
      return; // Focused and left without changing anything.
    }
    widget.onChanged();
    if (_openingWheel) {
      // This blur was caused by the wheel dialog stealing focus, not by the
      // admin actually leaving the field — see _openingWheel. The wheel
      // fires onTimeSet itself, on confirm, with whatever was actually
      // picked.
      return;
    }
    if (completed.isNotEmpty &&
        Validators.validateOptionalTime(completed) == null) {
      widget.onTimeSet?.call(completed);
    }
  }

  /// The wheel's cancel path. `_completeOnBlur` already suppressed
  /// `onTimeSet` unconditionally for the blur that opening the dialog
  /// caused (see `_openingWheel`); the wheel's own confirm branch is the
  /// only other place that fires it. Cancelling skips both, so without this
  /// a value the admin finished typing before opening the wheel would never
  /// reach the host — purely because they detoured through the wheel and
  /// backed out, instead of tapping away directly. Whether this fires must
  /// depend only on the value having actually changed, exactly like a plain
  /// blur: focusing and cancelling without typing anything is a no-op.
  void _completeOnWheelCancel() {
    final completed = widget.controller.text;
    if (completed.isEmpty) return;
    if (completed == _valueBeforeWheelOpened) return;
    if (Validators.validateOptionalTime(completed) != null) return;
    widget.onTimeSet?.call(completed);
  }

  Future<void> _showWheelPicker() async {
    final now = DateTime.now();
    var initialTime = now;
    // Seed from the completed value — e.g. a partially-typed "18" becomes
    // "18:00" — rather than the raw text, so the wheel opens on what the
    // admin has typed so far instead of on DateTime.now().
    final seedText = completePartialTime(widget.controller.text).trim();
    final parts = seedText.split(':');
    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      // The range check matters now that the field is typable: DateTime would
      // silently roll 25:70 over into the next day rather than reject it.
      if (hour != null &&
          minute != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        initialTime = DateTime(now.year, now.month, now.day, hour, minute);
      }
    }

    var selectedTime = initialTime;

    // Snapshot before anything below can change it — see
    // _valueBeforeWheelOpened's doc comment for why _valueOnFocusGain itself
    // cannot be read for this later, after the dialog has closed.
    _valueBeforeWheelOpened = _valueOnFocusGain;

    // showDialog pushes a route, which steals primary focus off this field
    // and fires _completeOnBlur before the admin has touched the wheel.
    // _openingWheel tells that blur to skip onTimeSet; cleared in `finally`
    // so it resets on both the confirm and the cancel path. The cancel path
    // itself is handled below, once the dialog result comes back null.
    _openingWheel = true;
    DateTime? result;
    try {
      result = await showDialog<DateTime>(
        context: context,
        builder: (context) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 280,
            height: 220,
            child: Column(
              children: [
                // Cupertino time picker wheel
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    initialDateTime: initialTime,
                    use24hFormat: true,
                    onDateTimeChanged: (DateTime newTime) {
                      selectedTime = newTime;
                    },
                  ),
                ),
                // Footer with cancel/confirm buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        child: const Text('ביטול'),
                        onPressed: () {
                          Logger.action('tap:cancel:timePicker');
                          Navigator.of(context).pop();
                        },
                      ),
                      TextButton(
                        child: const Text('אישור'),
                        onPressed: () {
                          Logger.action('tap:confirm:timePicker');
                          Navigator.of(context).pop(selectedTime);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _openingWheel = false;
    }

    if (!mounted) return;
    if (result == null) {
      _completeOnWheelCancel();
      return;
    }

    final value = '${result.hour.toString().padLeft(2, '0')}:'
        '${result.minute.toString().padLeft(2, '0')}';
    widget.controller.text = value;
    widget.onChanged();
    widget.onTimeSet?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      inputFormatters: [TimeTextInputFormatter()],
      // Keep the digits and the caret LTR inside the RTL form — mixed-direction
      // content is what makes Flutter's BiDi caret mapping misplace backspace.
      // textAlign keeps the value hugging the right edge, where it has always
      // sat.
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      validator: Validators.validateOptionalTime,
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        // RTL renders the suffix slot at the far left of the field.
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.access_time),
              tooltip: 'בחירת שעה',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Logger.action('open:timePicker:${widget.logKey}');
                _showWheelPicker();
              },
            ),
            if (_hasValue)
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                tooltip: 'נקה שעה',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Logger.action('tap:clearTime:${widget.logKey}');
                  widget.controller.clear();
                  widget.onChanged();
                },
              ),
          ],
        ),
      ),
    );
  }
}
