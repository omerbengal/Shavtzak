import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/phone_input_formatter.dart';
import '../../../../core/utils/rtl_text_field_utils.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/stage.dart';
import '../../event/widgets/event_time_field.dart';
import 'discard_changes_dialog.dart';

final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

const int _maxContacts = 30;

/// Create a stage of [event], or edit [existing].
///
/// Like the task form: saves through [onSave] and stays open with a spinner
/// until that answers, shows a failure in the form, allows saving an edit only
/// once something changed, and asks before discarding changes.
Future<void> showStageFormModal(
  BuildContext context, {
  Stage? existing,
  required Event event,
  required Future<CrudActionResult> Function(Stage stage) onSave,
  required String currentUserId,
  DateTime? now,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _StageFormModal(
      existing: existing,
      event: event,
      onSave: onSave,
      currentUserId: currentUserId,
      now: now ?? DateTime.now(),
    ),
  );
}

/// One editable contact row. Keeps the contact's id so an edit keeps it.
class _ContactDraft {
  _ContactDraft({
    required this.id,
    String name = '',
    String phone = '',
    String role = '',
  })  : name = TextEditingController(text: name),
        phone = TextEditingController(text: phone),
        role = TextEditingController(text: role) {
    nameFocus = createRtlCursorFixedFocusNode(this.name);
    roleFocus = createRtlCursorFixedFocusNode(this.role);
  }

  final String id;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController role;
  late final FocusNode nameFocus;
  late final FocusNode roleFocus;

  bool get isBlank =>
      name.text.trim().isEmpty &&
      phone.text.trim().isEmpty &&
      role.text.trim().isEmpty;

  StageContact toContact() => StageContact(
        id: id,
        name: name.text.trim(),
        phone: phone.text.trim(),
        role: role.text.trim(),
      );

  void dispose() {
    nameFocus.dispose();
    roleFocus.dispose();
    name.dispose();
    phone.dispose();
    role.dispose();
  }
}

class _StageFormModal extends StatefulWidget {
  const _StageFormModal({
    required this.existing,
    required this.event,
    required this.onSave,
    required this.currentUserId,
    required this.now,
  });

  final Stage? existing;
  final Event event;
  final Future<CrudActionResult> Function(Stage stage) onSave;
  final String currentUserId;
  final DateTime now;

  @override
  State<_StageFormModal> createState() => _StageFormModalState();
}

class _StageFormModalState extends State<_StageFormModal> {
  static const _uuid = Uuid();

  // Chosen once per form, so a retry after a failure sends the same stage.
  late final String _newStageId = _uuid.v4();

  late final List<DateTime> _days = eventDays(widget.event);

  late final TextEditingController _titleController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _requirementsController;
  late final TextEditingController _locationController;
  late final TextEditingController _notesController;
  late final FocusNode _titleFocus;
  late final FocusNode _requirementsFocus;
  late final FocusNode _locationFocus;
  late final FocusNode _notesFocus;
  late final List<_ContactDraft> _contacts;

  DateTime? _date;
  // The stage's stored day when the event has since moved away from it.
  DateTime? _strandedDate;
  String? _timeError;
  String? _contactsError;
  bool _isSaving = false;
  String? _saveError;

  late final List<Object?> _openingValue;

  bool get _isEditing => widget.existing != null;

  bool get _canSave =>
      !_isSaving &&
      _date != null &&
      _titleController.text.trim().isNotEmpty &&
      (!_isEditing || _hasChanges);

  /// What a save would send, reduced the way a save reduces it.
  List<Object?> _currentValue() => [
        _titleController.text.trim(),
        _date,
        _startController.text.trim(),
        _endController.text.trim(),
        _requirementsController.text.trim(),
        _locationController.text.trim(),
        _notesController.text.trim(),
        [
          for (final draft in _contacts)
            if (!draft.isBlank) ...[
              draft.id,
              draft.name.text.trim(),
              draft.phone.text.trim(),
              draft.role.text.trim(),
            ],
        ],
      ];

  bool get _hasChanges =>
      !const DeepCollectionEquality().equals(_currentValue(), _openingValue);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _startController = TextEditingController(text: existing?.startTime ?? '');
    _endController = TextEditingController(text: existing?.endTime ?? '');
    _requirementsController =
        TextEditingController(text: existing?.requirements ?? '');
    _locationController =
        TextEditingController(text: existing?.hotelLocation ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _titleFocus = createRtlCursorFixedFocusNode(_titleController);
    _requirementsFocus = createRtlCursorFixedFocusNode(_requirementsController);
    _locationFocus = createRtlCursorFixedFocusNode(_locationController);
    _notesFocus = createRtlCursorFixedFocusNode(_notesController);
    _contacts = [
      for (final contact in existing?.contacts ?? const <StageContact>[])
        _ContactDraft(
          id: contact.id,
          name: contact.name,
          phone: contact.phone,
          role: contact.role,
        ),
    ];

    final existingDate = existing?.date;
    if (existingDate != null) {
      if (_days.contains(existingDate)) {
        _date = existingDate;
      } else {
        // The event moved: the old day is shown as invalid and a new one must
        // be picked before saving.
        _strandedDate = existingDate;
      }
    } else if (_days.length == 1) {
      _date = _days.single;
    }

    _openingValue = _currentValue();
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _requirementsFocus.dispose();
    _locationFocus.dispose();
    _notesFocus.dispose();
    _titleController.dispose();
    _startController.dispose();
    _endController.dispose();
    _requirementsController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    for (final draft in _contacts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _addContact() {
    setState(() => _contacts.add(_ContactDraft(id: _uuid.v4())));
  }

  void _removeContact(_ContactDraft draft) {
    setState(() => _contacts.remove(draft));
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }

  Future<void> _cancel() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await confirmDiscardChanges(context, keyPrefix: 'stage-form');
    if (leave && mounted) Navigator.of(context).pop();
  }

  /// Why the times cannot be saved, or null when they can.
  String? _validateTimes(String start, String end) {
    if (start.isNotEmpty && !isValidDueTime(start)) {
      return 'שעת ההתחלה אינה תקינה. יש להזין שעה כמו 08:00, או להשאיר ריק.';
    }
    if (end.isNotEmpty && !isValidDueTime(end)) {
      return 'שעת הסיום אינה תקינה. יש להזין שעה כמו 10:45, או להשאיר ריק.';
    }
    if (end.isNotEmpty && start.isEmpty) {
      return 'שעת סיום דורשת שעת התחלה.';
    }
    if (end.isNotEmpty && end.compareTo(start) <= 0) {
      return 'שעת הסיום חייבת להיות אחרי שעת ההתחלה.';
    }
    return null;
  }

  /// Why the contacts cannot be saved, or null when they can.
  String? _validateContacts() {
    for (final draft in _contacts) {
      if (draft.isBlank) continue;
      if (draft.name.text.trim().isEmpty) return 'לכל איש קשר נדרש שם.';
      // The same rule as a team member's phone.
      final phoneError = Validators.validatePhoneNumber(draft.phone.text);
      if (phoneError != null) {
        return 'הטלפון של ${draft.name.text.trim()}: $phoneError';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final start = _startController.text.trim();
    final end = _endController.text.trim();
    final timeError = _validateTimes(start, end);
    final contactsError = _validateContacts();
    if (timeError != null || contactsError != null) {
      setState(() {
        _timeError = timeError;
        _contactsError = contactsError;
      });
      return;
    }

    final fields = (
      title: _titleController.text.trim(),
      date: _date!,
      startTime: start.isEmpty ? null : start,
      endTime: end.isEmpty ? null : end,
      requirements: _requirementsController.text.trim(),
      hotelLocation: _locationController.text.trim(),
      notes: _notesController.text.trim(),
      contacts: [
        for (final draft in _contacts)
          if (!draft.isBlank) draft.toContact(),
      ],
    );
    final existing = widget.existing;
    final stage = existing == null
        ? Stage(
            id: _newStageId,
            eventId: widget.event.id,
            title: fields.title,
            date: fields.date,
            startTime: fields.startTime,
            endTime: fields.endTime,
            requirements: fields.requirements,
            hotelLocation: fields.hotelLocation,
            notes: fields.notes,
            contacts: fields.contacts,
            // Placeholders: the backend stamps the real times.
            createdAt: widget.now,
            createdById: widget.currentUserId,
            updatedAt: widget.now,
          )
        : existing.copyWith(
            title: fields.title,
            date: fields.date,
            startTime: fields.startTime,
            endTime: fields.endTime,
            clearStartTime: fields.startTime == null,
            clearEndTime: fields.endTime == null,
            requirements: fields.requirements,
            hotelLocation: fields.hotelLocation,
            notes: fields.notes,
            contacts: fields.contacts,
          );

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    final result = await widget.onSave(stage);
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSaving = false;
      _saveError = result.message ?? 'השמירה נכשלה. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_isSaving && !_hasChanges,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_isSaving) _cancel();
        },
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(
                    _isEditing ? 'עריכת שלב' : 'שלב חדש',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Flexible(
                  child: AbsorbPointer(
                    absorbing: _isSaving,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('stage-form-title'),
                            controller: _titleController,
                            focusNode: _titleFocus,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: 'כותרת',
                              border: OutlineInputBorder(),
                              counterText: '',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          _buildDateField(theme),
                          const SizedBox(height: 16),
                          _buildTimeFields(theme),
                          const SizedBox(height: 16),
                          _multiline(
                            key: 'stage-form-requirements',
                            controller: _requirementsController,
                            focusNode: _requirementsFocus,
                            label: 'דרישות מהמלון ולוגיסטיקה',
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('stage-form-location'),
                            controller: _locationController,
                            focusNode: _locationFocus,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: 'מיקום במלון',
                              border: OutlineInputBorder(),
                              counterText: '',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          _multiline(
                            key: 'stage-form-notes',
                            controller: _notesController,
                            focusNode: _notesFocus,
                            label: 'הערות',
                          ),
                          const SizedBox(height: 20),
                          _buildContacts(theme),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      _saveError!,
                      key: const Key('stage-form-save-error'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const Key('stage-form-cancel'),
                        onPressed: _isSaving ? null : _cancel,
                        child: const Text('ביטול'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('stage-form-save'),
                        onPressed: _canSave ? _save : null,
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('שמירה'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _multiline({
    required String key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
  }) {
    return TextField(
      key: Key(key),
      controller: controller,
      focusNode: focusNode,
      minLines: 2,
      maxLines: 6,
      maxLength: 5000,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
        alignLabelWithHint: true,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildDateField(ThemeData theme) {
    final stranded = _strandedDate;
    return DropdownButtonFormField<DateTime>(
      key: const Key('stage-form-date'),
      initialValue: _date,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'תאריך',
        border: const OutlineInputBorder(),
        errorText: stranded != null && _date == null
            ? 'התאריך הקודם (${_dateFormat.format(stranded)}) אינו מתאריכי '
                'האירוע. יש לבחור תאריך חדש.'
            : null,
        errorMaxLines: 2,
      ),
      items: [
        for (final day in _days)
          DropdownMenuItem<DateTime>(
            value: day,
            // The open list is drawn above the dialog, outside its RTL
            // wrapper, so it needs its own.
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(_dateFormat.format(day)),
            ),
          ),
      ],
      onChanged: (day) => setState(() => _date = day),
    );
  }

  Widget _buildTimeFields(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Right to left like the rest of the form: start on the right. (The
        // stage card shows the range the other way, "start – end" left to
        // right.)
        Row(
          children: [
            Expanded(
              child: EventTimeField(
                key: const Key('stage-form-start'),
                controller: _startController,
                label: 'שעת התחלה',
                hint: 'לא חובה',
                logKey: 'stageStart',
                onChanged: () => setState(() => _timeError = null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EventTimeField(
                key: const Key('stage-form-end'),
                controller: _endController,
                label: 'שעת סיום',
                hint: 'לטווח שעות',
                logKey: 'stageEnd',
                onChanged: () => setState(() => _timeError = null),
              ),
            ),
          ],
        ),
        if (_timeError != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6, start: 12),
            child: Text(
              _timeError!,
              key: const Key('stage-form-time-error'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _buildContacts(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('אנשי קשר', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var index = 0; index < _contacts.length; index++)
          KeyedSubtree(
            key: ObjectKey(_contacts[index]),
            child: _buildContactRow(index, _contacts[index]),
          ),
        if (_contactsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _contactsError!,
              key: const Key('stage-form-contacts-error'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        TextButton.icon(
          key: const Key('stage-form-add-contact'),
          onPressed: _contacts.length >= _maxContacts ? null : _addContact,
          icon: const Icon(Icons.person_add_alt),
          label: const Text('הוספת איש קשר'),
        ),
      ],
    );
  }

  Widget _buildContactRow(int index, _ContactDraft draft) {
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          counterText: '',
        );
    void changed(String _) => setState(() => _contactsError = null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('stage-form-contact-name-$index'),
                        controller: draft.name,
                        focusNode: draft.nameFocus,
                        maxLength: 100,
                        decoration: field('שם'),
                        onChanged: changed,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // The same field as a team member's phone.
                    Expanded(
                      child: TextField(
                        key: Key('stage-form-contact-phone-$index'),
                        controller: draft.phone,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.end,
                        smartQuotesType: SmartQuotesType.disabled,
                        smartDashesType: SmartDashesType.disabled,
                        inputFormatters: [PhoneNumberTextInputFormatter()],
                        decoration: field('טלפון').copyWith(
                          hintText: '05X-XXXXXXX',
                          prefixIcon: const Icon(Icons.phone),
                        ),
                        onChanged: changed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  key: Key('stage-form-contact-role-$index'),
                  controller: draft.role,
                  focusNode: draft.roleFocus,
                  maxLength: 100,
                  decoration: field('תפקיד (לא חובה)'),
                  onChanged: changed,
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('stage-form-contact-remove-$index'),
            tooltip: 'הסרת איש הקשר',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _removeContact(draft),
          ),
        ],
      ),
    );
  }
}
