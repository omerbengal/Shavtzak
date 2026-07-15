import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../core/debug/logger.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/date_utils.dart' as app_date_utils;
import '../../../../core/utils/rtl_text_field_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../domain/entities/event.dart';
// Re-exported (not just imported) so callers that only import this file —
// e.g. the widget test — can reference ParticipantGroupRows /
// ParticipantGroupRowsState. A plain `import` is not transitive in Dart.
export 'participant_group_rows.dart';
import '../../../../data/repositories/assignment_repository.dart';
import '../../../../data/repositories/event_repository.dart';
import '../../../bloc/category/category_bloc.dart';
import '../../../bloc/category/category_state.dart';
import '../../../bloc/category/category_event.dart';
import '../../../bloc/event/event_bloc.dart';
import '../../../bloc/event/event_event.dart';
import '../../../bloc/event/event_state.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';
import '../../../widgets/date_picker_dialog.dart';
import '../../../widgets/map_location_picker.dart';
import '../../../widgets/parking_location_picker_dialog.dart';
import '../../../widgets/loading_overlay.dart';
import '../quota_reduction_analyzer.dart';
import 'quota_reduction_dialog.dart';
import 'duplication_conflict_resolution_dialog.dart';

/// Public Event Form Modal Widget for creating/editing events
/// Can be used from any screen that needs to create or edit events
class EventFormModal extends StatefulWidget {
  final Event? event; // null for create, non-null for edit
  final VoidCallback onSuccess;
  final String? selectedRoleKey; // Optional role key to highlight/scroll to
  final int
      filterIndex; // Filter index to reload with after operations (0=all, 1=future, 2=past)
  final bool isDuplication; // true if this is a duplication modal

  const EventFormModal({
    super.key,
    this.event,
    required this.onSuccess,
    this.selectedRoleKey,
    this.filterIndex = 1, // Default to future
    this.isDuplication = false, // Default to false
  });

  @override
  State<EventFormModal> createState() => _EventFormModalState();
}

class _EventFormModalState extends State<EventFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _parkingLocationController = TextEditingController();
  final _commentsController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _teamEndTimeController = TextEditingController();
  final _assemblyTimeController = TextEditingController();
  final _actualShowStartTimeController = TextEditingController();
  final _participantCountController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _requiresArmed = false;
  Map<String, int> _roleRequirements = {};
  bool _isDirty = false;
  bool _validateName = false; // Enable name validation after blur or submit
  String? _dateError; // Track date validation error
  final _nameFocusNode = FocusNode(); // For name field blur detection
  late final FocusNode _locationFocusNode;
  late final FocusNode _parkingLocationFocusNode;
  late final FocusNode _commentsFocusNode;
  bool _duplicateAssignments = false; // For duplication mode checkbox
  String?
      _rawLocationValue; // Stores location with hidden coordinates (Name||lat,lng)
  String?
      _rawParkingLocationValue; // Stores parking location with hidden coordinates
  List<String> _parkingEditorIds =
      const []; // IDs of team members who can edit parking
  String? _selectedCategoryId; // Selected category ID for the event
  bool _relevantForExtendedTeam =
      true; // Event is relevant for extended team (UI is inverted)
  // Calendar: invite all permanent staff while the event has no assignments.
  // Only meaningful when the "permanent team only" switch is ON.
  bool _inviteAllPermanentWhenUnassigned = false;

  // For highlighting selected role
  ScrollController?
      _scrollController; // Will be set from DraggableScrollableSheet
  bool _isSaving = false; // Loading state during save
  String _loadingMessage = '';
  final _sheetController =
      DraggableScrollableController(); // Controller to expand sheet
  final Map<RoleType, GlobalKey> _roleKeys = {};
  RoleType? _highlightedRole;
  double _highlightOpacity = 1.0; // For fade animation

  bool get _isEditMode => widget.event != null || widget.isDuplication;

  /// Safely parse a role key string to RoleType enum
  /// Returns null if the key doesn't match any RoleType value
  RoleType? _tryParseRoleType(String key) {
    try {
      return RoleType.values.firstWhere((role) => role.key == key);
    } catch (e) {
      // Role key not found in RoleType enum
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize role requirements with all roles set to 0
    // Will be populated from RoleBloc when state is loaded
    // Initialize role keys mapping
    for (final role in RoleType.values) {
      _roleKeys[role] = GlobalKey();
    }
    if (_isEditMode) {
      _nameController.text = widget.event!.name;
      // Store raw location value and display stripped version
      _rawLocationValue = widget.event!.location;
      _locationController.text =
          MapLocationResult.stripCoordinates(widget.event!.location);
      _rawParkingLocationValue = widget.event!.parkingLocation;
      _parkingLocationController.text = widget.event!.parkingLocation != null
          ? MapLocationResult.stripCoordinates(widget.event!.parkingLocation!)
          : '';
      _parkingEditorIds = widget.event!.parkingEditorIds;
      _commentsController.text = widget.event!.comments;
      _startTimeController.text = widget.event!.startTime;
      _endTimeController.text = widget.event!.endTime;
      _teamEndTimeController.text = widget.event!.teamEndTime;
      _assemblyTimeController.text = widget.event!.assemblyTime;
      _actualShowStartTimeController.text = widget.event!.actualShowStartTime;
      _participantCountController.text =
          widget.event!.participantCount?.toString() ?? '';

      if (widget.isDuplication) {
        // For duplication mode, reset dates to allow user to select new ones
        _startDate = null;
        _endDate = null;
      } else {
        // For regular edit mode
        _startDate = widget.event!.startDate;
        _endDate = widget.event!.endDate;
      }

      _requiresArmed = widget.event!.requiresArmed;
      // Load role requirements from event (already String keys)
      _roleRequirements = Map.from(widget.event!.roleRequirements);
      // Load category
      _selectedCategoryId = widget.event!.categoryId;
      // Load relevant for extended team (inverted for UI)
      _relevantForExtendedTeam = !widget.event!.relevantForExtendedTeam;
      // In duplication mode this flag intentionally stays false (its default):
      // the DuplicateEvent save path does not carry it, so inheriting the
      // source value would show the toggle ON while it would be saved OFF.
      // Admins can enable it after editing the newly created event.
      if (!widget.isDuplication) {
        _inviteAllPermanentWhenUnassigned =
            widget.event!.inviteAllPermanentWhenUnassigned;
      }
    }

    _nameController.addListener(() => _isDirty = true);
    _locationController.addListener(() => _isDirty = true);
    _parkingLocationController.addListener(() => _isDirty = true);
    _commentsController.addListener(() => _isDirty = true);

    // RTL cursor fix for all text fields
    addRtlCursorFix(_nameFocusNode, _nameController);
    _locationFocusNode = createRtlCursorFixedFocusNode(_locationController);
    _parkingLocationFocusNode =
        createRtlCursorFixedFocusNode(_parkingLocationController);
    _commentsFocusNode = createRtlCursorFixedFocusNode(_commentsController);

    // Enable validation when name field loses focus
    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus && _nameController.text.isNotEmpty) {
        setState(() {
          _validateName = true;
        });
      }
    });

    // If a role was selected, scroll to it and highlight after build
    if (widget.selectedRoleKey != null) {
      final RoleType? roleType = _tryParseRoleType(widget.selectedRoleKey!);
      if (roleType != null) {
        _highlightedRole = roleType;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToRole(roleType);
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _parkingLocationController.dispose();
    _commentsController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _teamEndTimeController.dispose();
    _assemblyTimeController.dispose();
    _actualShowStartTimeController.dispose();
    _participantCountController.dispose();
    _nameFocusNode.dispose();
    _locationFocusNode.dispose();
    _parkingLocationFocusNode.dispose();
    _commentsFocusNode.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  /// Scroll to a specific role and highlight it
  void _scrollToRole(RoleType role) {
    final key = _roleKeys[role];

    // Wait for layout to complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // First, expand the sheet to maximum size
      _sheetController.animateTo(
        0.95, // maxChildSize
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

      // Wait for sheet to expand, then scroll to role
      Future.delayed(const Duration(milliseconds: 400), () {
        if (key?.currentContext == null) return;

        // Now this works because SingleChildScrollView renders all content!
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          alignment: 0.2, // Position role at 20% from top of viewport
        );
      });
    });

    // Fade out highlight over 2 seconds
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _highlightOpacity = 0.0;
        });

        // Remove highlight completely after fade animation
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _highlightedRole = null;
              _highlightOpacity = 1.0; // Reset for next use
            });
          }
        });
      }
    });
  }

  Future<void> _showTimePickerFor(
    TextEditingController controller, {
    void Function(String value)? onPicked,
  }) async {
    // Parse existing value as initial time, default to current time
    final now = DateTime.now();
    DateTime initialTime = now;
    if (controller.text.isNotEmpty) {
      final parts = controller.text.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          initialTime = DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
    }

    DateTime selectedTime = initialTime;

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

    if (result != null) {
      setState(() {
        final value =
            '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
        controller.text = value;
        _isDirty = true;
        onPicked?.call(value);
      });
    }
  }

  /// Parse the participant-count field into an int, or null when empty/invalid.
  int? _parseParticipantCount() {
    final raw = _participantCountController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  /// Overwrite [target] with [source] shifted by [offsetMinutes]. Used by the
  /// derive arrows (שעתיים לפני / שעה אחרי) and the live empty-target auto-fill.
  void _deriveTime(
    TextEditingController source,
    TextEditingController target,
    int offsetMinutes,
  ) {
    final derived =
        app_date_utils.DateUtils.shiftHmByMinutes(source.text.trim(), offsetMinutes);
    if (derived == null) return;
    setState(() {
      target.text = derived;
      _isDirty = true;
    });
  }

  /// A read-only time-picker field (tap opens the wheel picker). Extracted so
  /// the five event time fields share one definition instead of duplicating it.
  Widget _buildTimeField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    required String logKey,
    void Function(String value)? onPicked,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: () {
        Logger.action('open:timePicker:$logKey');
        _showTimePickerFor(controller, onPicked: onPicked);
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon),
        border: const OutlineInputBorder(),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  Logger.action('tap:clearTime:$logKey');
                  setState(() {
                    controller.clear();
                    _isDirty = true;
                  });
                },
              )
            : null,
      ),
    );
  }

  /// A small up/down arrow button placed between a source and a target time
  /// field. Tapping it overwrites the target with the source shifted by
  /// [offsetMinutes]. Only shown once the source field has a value.
  Widget _buildDeriveArrow({
    required TextEditingController source,
    required TextEditingController target,
    required int offsetMinutes,
    required bool pointsUp,
    required String label,
    required String logKey,
  }) {
    // Always render the arrow; disable (gray out) it unless pressing it would
    // actually change something — i.e. the source has a value AND the target is
    // not already equal to the derived value. This grays the arrow after a
    // sync, and re-enables it if the source time later changes.
    final derived = app_date_utils.DateUtils.shiftHmByMinutes(
        source.text.trim(), offsetMinutes);
    final enabled = derived != null && target.text.trim() != derived;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: enabled
              ? () {
                  Logger.action('tap:deriveTime:$logKey');
                  _deriveTime(source, target, offsetMinutes);
                }
              : null,
          icon: Icon(
            pointsUp ? Icons.arrow_upward : Icons.arrow_downward,
            size: 18,
          ),
          label: Text(label),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  Future<void> _saveEvent() async {
    if (_isSaving) return; // Prevent double-submit

    // Enable validation for all fields after first submit attempt
    setState(() {
      _isSaving = true;
      _loadingMessage = widget.isDuplication
          ? 'משכפל אירוע...'
          : (_isEditMode ? 'שומר אירוע...' : 'יוצר אירוע...');
      _validateName = true;
      // Always validate date field when save is attempted
      if (_startDate == null || _endDate == null) {
        _dateError = widget.isDuplication
            ? '↑ יש לבחור תאריכי התחלה וסיום לאירוע המשוכפל ↑'
            : 'יש לבחור תאריכי התחלה וסיום לאירוע';
      } else {
        _dateError = null;
      }
    });

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = false;
        _loadingMessage = '';
      });
      return;
    }
    if (_startDate == null || _endDate == null) {
      setState(() {
        _isSaving = false;
        _loadingMessage = '';
      });
      // This is now redundant since we set the error above, but keeping for safety
      return;
    }

    // For duplication mode, create the duplicated event
    if (widget.isDuplication) {
      // Validate that dates are selected
      if (_startDate == null || _endDate == null) {
        setState(() {
          _dateError = '↑ יש לבחור תאריכי התחלה וסיום לאירוע המשוכפל ↑';
          _isSaving = false;
          _loadingMessage = '';
        });
        return;
      }

      // Use raw location value (with hidden coordinates) if available and unchanged
      String dupLocationValue = _locationController.text.trim();
      if (_rawLocationValue != null) {
        final strippedRaw =
            MapLocationResult.stripCoordinates(_rawLocationValue!);
        if (strippedRaw == dupLocationValue) {
          dupLocationValue = _rawLocationValue!;
        }
      }

      context.read<EventBloc>().add(DuplicateEvent(
            eventId: widget.event!.id,
            newName: _nameController.text,
            newLocation: dupLocationValue,
            newComments: _commentsController.text,
            newStartDate: _startDate!,
            newEndDate: _endDate!,
            newStartTime: _startTimeController.text,
            newEndTime: _endTimeController.text,
            newTeamEndTime: _teamEndTimeController.text,
            newAssemblyTime: _assemblyTimeController.text,
            newActualShowStartTime: _actualShowStartTimeController.text,
            newParticipantCount: _parseParticipantCount(),
            newRequiresArmed: _requiresArmed,
            newRoleRequirements: Map.from(_roleRequirements),
            duplicateAssignments: _duplicateAssignments,
            categoryId: _selectedCategoryId,
            newRelevantForExtendedTeam:
                !_relevantForExtendedTeam, // Invert back for database
          ));

      // Don't close here. Duplication completion (or conflict handling) is
      // managed by the BlocListener to avoid double-pop race conditions.
      return;
    }

    // NEW: Quota reduction analysis (edit mode only)
    if (_isEditMode) {
      try {
        final conflicts = await QuotaReductionAnalyzer.analyzeQuotaReductions(
          originalEvent: widget.event!,
          newRoleRequirements:
              _roleRequirements, // Directly pass String-keyed map
          assignmentRepo: context.read<AssignmentRepository>(),
        );

        // If there are assignments that need to be removed, show dialog
        if (conflicts.isNotEmpty) {
          if (!mounted) return;
          final selectedIds = await QuotaReductionDialog.show(
            context,
            conflicts,
          );

          if (selectedIds == null) {
            // User cancelled - revert quotas to original values
            setState(() {
              _roleRequirements = Map.from(widget.event!.roleRequirements);
              _isSaving = false;
              _loadingMessage = '';
            });
            return;
          }

          // Delete selected assignments
          if (selectedIds.isNotEmpty && mounted) {
            final assignmentRepo = context.read<AssignmentRepository>();
            await assignmentRepo.deleteAssignmentsBatch(selectedIds);

            // Reorder remaining assignments to fill slots sequentially
            // This ensures slots 0, 1, 2, ... are filled without gaps
            for (final conflict in conflicts) {
              // Get all remaining assignments for this role
              final allAssignments = await assignmentRepo.getAssignmentsByEvent(
                widget.event!.id,
              );
              final remainingAssignments = allAssignments
                  .where((a) =>
                      a.roleType == conflict.roleKey &&
                      !selectedIds.contains(a.id))
                  .toList();

              // Sort by current slotIndex to maintain relative order
              remainingAssignments
                  .sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

              // Reassign sequential slot indices starting from 0
              for (int i = 0; i < remainingAssignments.length; i++) {
                if (remainingAssignments[i].slotIndex != i) {
                  // Update this assignment with new slotIndex
                  final updated = remainingAssignments[i].copyWith(
                    slotIndex: i,
                    updatedAt: DateTime.now(),
                  );
                  await assignmentRepo.updateAssignmentUnchecked(updated);
                }
              }
            }
            // Note: No need to manually reload - assignment screen uses real-time streams
          }
        }

        // IMPORTANT: Always reorder assignments after quota reduction,
        // even if there were no conflicts requiring deletion.
        // This handles cases where assignments are beyond the new quota range
        // (e.g., Person at slot 5 when quota reduced to 4)
        if (mounted) {
          final assignmentRepo = context.read<AssignmentRepository>();
          final allAssignments = await assignmentRepo.getAssignmentsByEvent(
            widget.event!.id,
          );

          // Check each role where quota was reduced
          // Get all unique role keys from both old and new requirements
          final allRoleKeys = {
            ...widget.event!.roleRequirements.keys,
            ..._roleRequirements.keys,
          };

          for (final roleKey in allRoleKeys) {
            final oldQuota = widget.event!.roleRequirements[roleKey] ?? 0;
            final newQuota = _roleRequirements[roleKey] ?? 0;

            // Only process roles where quota was reduced
            if (newQuota >= oldQuota) continue;

            // Get all assignments for this role
            final roleAssignments =
                allAssignments.where((a) => a.roleType == roleKey).toList();

            // Sort by current slotIndex to maintain relative order
            roleAssignments.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

            // Reassign sequential slot indices starting from 0
            // This moves any assignments beyond the quota range into the valid range
            for (int i = 0; i < roleAssignments.length; i++) {
              if (roleAssignments[i].slotIndex != i) {
                final updated = roleAssignments[i].copyWith(
                  slotIndex: i,
                  updatedAt: DateTime.now(),
                );
                await assignmentRepo.updateAssignmentUnchecked(updated);
              }
            }
          }
        }
      } catch (e) {
        // Show error and don't proceed with save
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text('שגיאה בניתוח שיבוצים: $e'),
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
        }
        setState(() {
          _isSaving = false;
          _loadingMessage = '';
        });
        return;
      }
    }

    final now = DateTime.now();
    // Use raw location value (with hidden coordinates) if available and unchanged
    // Otherwise use the text field value (user typed manually)
    String locationValue = _locationController.text.trim();
    if (_rawLocationValue != null) {
      final strippedRaw =
          MapLocationResult.stripCoordinates(_rawLocationValue!);
      if (strippedRaw == locationValue) {
        // User didn't manually edit, use raw value with coordinates
        locationValue = _rawLocationValue!;
      }
    }

    final event = Event(
      id: _isEditMode ? widget.event!.id : const Uuid().v4(),
      name: _nameController.text.trim(),
      startDate: _startDate!,
      endDate: _endDate!,
      startTime: _startTimeController.text.trim(),
      endTime: _endTimeController.text.trim(),
      teamEndTime: _teamEndTimeController.text.trim(),
      assemblyTime: _assemblyTimeController.text.trim(),
      actualShowStartTime: _actualShowStartTimeController.text.trim(),
      participantCount: _parseParticipantCount(),
      location: locationValue,
      parkingLocation: _rawParkingLocationValue,
      parkingEditorIds: _parkingEditorIds,
      requiresArmed: _requiresArmed,
      comments: _commentsController.text.trim(),
      categoryId: _selectedCategoryId,
      roleRequirements: _roleRequirements,
      createdAt: _isEditMode ? widget.event!.createdAt : now,
      updatedAt: now,
      // Preserve Drive-related fields when updating
      driveFolderId: _isEditMode ? widget.event!.driveFolderId : null,
      driveFolderLink: _isEditMode ? widget.event!.driveFolderLink : null,
      relevantForExtendedTeam:
          !_relevantForExtendedTeam, // Invert back for database
      inviteAllPermanentWhenUnassigned:
          _relevantForExtendedTeam && _inviteAllPermanentWhenUnassigned,
    );

    if (!mounted) return;
    final bloc = context.read<EventBloc>();
    final completion = Completer<CrudActionResult>();
    if (_isEditMode) {
      // Pass the pre-edit event so the save doesn't await a one-shot
      // getEventById() that can park for tens of seconds on a flaky connection.
      bloc.add(UpdateEvent(event,
          originalEvent: widget.event, completion: completion));
    } else {
      bloc.add(CreateEvent(event, completion: completion));
    }

    final result = await completion.future;
    if (!mounted) return;

    if (result.isFailure) {
      setState(() {
        _isSaving = false;
        _loadingMessage = '';
      });
      return;
    }

    widget.onSuccess();
  }

  /// Show confirm dialog and toggle the event's isDeactivated state.
  /// On success, closes the modal — the list will refresh via real-time streams.
  Future<void> _handleToggleDeactivation() async {
    if (widget.event == null) return; // Edit mode only

    final isCurrentlyDeactivated = widget.event!.isDeactivated;
    final eventName = widget.event!.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            isCurrentlyDeactivated ? 'הפעלת אירוע מחדש' : 'השבתת אירוע',
          ),
          content: SingleChildScrollView(
            child: isCurrentlyDeactivated
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('"$eventName" יוצג שוב במלואו:'),
                      const SizedBox(height: 8),
                      const Text('• אירועי יומן Google ייווצרו מחדש עם המשובצים הנוכחיים'),
                      const Text('• ההצבות יחזרו להופיע בכל המסכים'),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('"$eventName" יושבת. המשמעות:'),
                      const SizedBox(height: 8),
                      const Text('• אירועי יומן Google הקשורים יימחקו'),
                      const Text('• המשובצים לא יראו את האירוע במסך שלהם'),
                      const Text('• האירוע יוסתר ממסך ההצבות וממסך המנהלים'),
                      const Text('• ההצבות יישמרו במערכת'),
                      const SizedBox(height: 8),
                      const Text(
                        'ניתן להפעיל מחדש בכל עת — אירועי היומן ייווצרו שוב וההצבות יחזרו להופיע.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              child: const Text('ביטול'),
              onPressed: () {
                Logger.action('tap:cancel:toggleDeactivation',
                    {'eventId': widget.event!.id});
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor:
                    isCurrentlyDeactivated ? Colors.green : Colors.red,
              ),
              child: Text(isCurrentlyDeactivated ? 'הפעל מחדש' : 'השבת אירוע'),
              onPressed: () {
                Logger.action('tap:confirmToggleDeactivation', {
                  'eventId': widget.event!.id,
                  'isCurrentlyDeactivated': isCurrentlyDeactivated,
                });
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isSaving = true;
      _loadingMessage =
          isCurrentlyDeactivated ? 'מפעיל אירוע מחדש...' : 'משבית אירוע...';
    });

    final completion = Completer<CrudActionResult>();
    final bloc = context.read<EventBloc>();
    if (isCurrentlyDeactivated) {
      bloc.add(ReactivateEventRequested(widget.event!.id,
          completion: completion));
    } else {
      bloc.add(DeactivateEventRequested(widget.event!.id,
          completion: completion));
    }

    final result = await completion.future;
    if (!mounted) return;

    if (result.isFailure) {
      setState(() {
        _isSaving = false;
        _loadingMessage = '';
      });
      return;
    }

    widget.onSuccess();
  }

  void _handleClose() {
    if (_isDirty) {
      showDialog(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('שינויים לא נשמרו'),
            content:
                const Text('האם אתה בטוח שברצונך לצאת? השינויים לא יישמרו.'),
            actions: [
              TextButton(
                child: const Text('ביטול'),
                onPressed: () {
                  Logger.action('tap:cancel:discardChanges');
                  Navigator.of(dialogContext).pop();
                },
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('צא'),
                onPressed: () {
                  Logger.action('tap:confirmDiscardChanges');
                  Navigator.of(dialogContext).pop(); // Close dialog
                  widget.onSuccess(); // Close modal
                },
              ),
            ],
          ),
        ),
      );
    } else {
      widget.onSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        // Capture the scroll controller from DraggableScrollableSheet
        _scrollController = scrollController;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final horizontalPadding =
                  maxWidth > 1000 ? (maxWidth - 1000) / 2 : 0.0;

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Stack(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          // Modal Header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: widget.isDuplication
                                      ? RichText(
                                          text: TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: 'שכפול אירוע: ',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red,
                                                ),
                                              ),
                                              TextSpan(
                                                text: widget.event?.name ?? '',
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Text(
                                          _isEditMode
                                              ? 'עריכת אירוע'
                                              : 'הוספת אירוע',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                                if (_isEditMode && !widget.isDuplication)
                                  IconButton(
                                    icon: Icon(
                                      Icons.power_settings_new,
                                      color: widget.event!.isDeactivated
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                            Logger.action(
                                                'tap:toggleDeactivation', {
                                              'eventId': widget.event!.id,
                                              'isDeactivated':
                                                  widget.event!.isDeactivated,
                                            });
                                            _handleToggleDeactivation();
                                          },
                                    tooltip: widget.event!.isDeactivated
                                        ? 'הפעל אירוע מחדש'
                                        : 'השבת אירוע',
                                  ),
                                if (_isEditMode)
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                      Logger.action('open:deleteEventDialog',
                                          {'eventId': widget.event!.id});
                                      showDialog(
                                        context: context,
                                        builder: (dialogContext) =>
                                            Directionality(
                                          textDirection: TextDirection.rtl,
                                          child: AlertDialog(
                                            title: const Text('מחיקת אירוע'),
                                            content: Text(
                                              'האם אתה בטוח שברצונך למחוק את ${widget.event!.name}?\nפעולה זו תמחק גם את כל השיבוצים.',
                                            ),
                                            actions: [
                                              TextButton(
                                                child: const Text('ביטול'),
                                                onPressed: () {
                                                  Logger.action(
                                                      'tap:cancel:deleteEvent',
                                                      {
                                                        'eventId':
                                                            widget.event!.id
                                                      });
                                                  Navigator.of(dialogContext)
                                                      .pop();
                                                },
                                              ),
                                              TextButton(
                                                child: const Text('מחק',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                                onPressed: () async {
                                                  Logger.action(
                                                      'tap:deleteEvent', {
                                                    'eventId': widget.event!.id
                                                  });
                                                  Navigator.of(dialogContext)
                                                      .pop();
                                                  if (mounted) {
                                                    setState(() {
                                                      _isSaving = true;
                                                      _loadingMessage =
                                                          'מוחק אירוע...';
                                                    });
                                                  }
                                                  final completion =
                                                      Completer<
                                                          CrudActionResult>();
                                                  context.read<EventBloc>().add(
                                                        DeleteEvent(
                                                          widget.event!.id,
                                                          completion:
                                                              completion,
                                                        ),
                                                      );
                                                  final result =
                                                      await completion.future;
                                                  if (!context.mounted) {
                                                    return;
                                                  }
                                                  if (result.isFailure) {
                                                    setState(() {
                                                      _isSaving = false;
                                                      _loadingMessage = '';
                                                    });
                                                    return;
                                                  }
                                                  widget.onSuccess();
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                    tooltip: 'מחק',
                                  ),
                                if (_isEditMode && !widget.isDuplication)
                                  IconButton(
                                    icon: const Icon(Icons.copy,
                                        color: Colors.blue),
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                      Logger.action('tap:duplicateEvent',
                                          {'eventId': widget.event!.id});
                                      // Close the current modal and signal duplication intent
                                      Navigator.of(context).pop({
                                        'action': 'duplicate',
                                        'event': widget.event
                                      });
                                    },
                                    tooltip: 'שכפל אירוע',
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: _isSaving
                                      ? null
                                      : () {
                                          Logger.action(
                                              'tap:close:eventFormModal');
                                          _handleClose();
                                        },
                                ),
                              ],
                            ),
                          ),

                          // Deactivated status banner
                          if (_isEditMode &&
                              !widget.isDuplication &&
                              widget.event!.isDeactivated)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              color: Colors.grey.shade200,
                              child: Row(
                                children: [
                                  Icon(Icons.power_settings_new,
                                      color: Colors.grey.shade700, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'האירוע מושבת',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Modal Body (Scrollable)
                          Expanded(
                            child: BlocConsumer<EventBloc, EventState>(
                              listener: (context, state) async {
                                // Only handle duplication-related states when in duplication mode
                                if (!widget.isDuplication) return;

                                // Handle duplication conflict resolution state (NEW FLOW)
                                // This is triggered BEFORE any database writes
                                if (state
                                    is DuplicationRequiresConflictResolution) {
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _loadingMessage = '';
                                    });
                                  }
                                  // Show the unified conflict resolution dialog
                                  final excludedIds =
                                      await DuplicationConflictResolutionDialog
                                          .show(
                                    context,
                                    state,
                                  );

                                  if (excludedIds != null) {
                                    // User confirmed - dispatch confirmation event with exclusions
                                    if (context.mounted) {
                                      setState(() {
                                        _isSaving = true;
                                        _loadingMessage = 'משכפל אירוע...';
                                      });
                                      context
                                          .read<EventBloc>()
                                          .add(ConfirmDuplicationWithExclusions(
                                            originalEvent: state.originalEvent,
                                            proposedEvent: state.proposedEvent,
                                            assignmentIdsToExclude: excludedIds,
                                            originalAssignmentIds: state
                                                .assignmentInfos
                                                .map((info) =>
                                                    info.assignment.id)
                                                .toList(),
                                          ));
                                    }
                                  } else {
                                    // User cancelled - close the modal
                                    if (context.mounted) {
                                      widget.onSuccess();
                                    }
                                  }
                                }

                                // Handle success state - close modal when duplication completes
                                if (state is EventOperationSuccess) {
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _loadingMessage = '';
                                    });
                                  }
                                  if (context.mounted) {
                                    widget.onSuccess();
                                  }
                                }

                                if (state is EventError && mounted) {
                                  setState(() {
                                    _isSaving = false;
                                    _loadingMessage = '';
                                  });
                                }

                                // Handle old quota conflicts state (LEGACY - kept for backwards compatibility)
                                if (state
                                    is EventDuplicatedWithQuotaConflicts) {
                                  // Show the quota reduction dialog
                                  final assignmentIdsToRemove =
                                      await QuotaReductionDialog.show(
                                    context,
                                    state.quotaConflicts,
                                  );

                                  // If user made selections, remove the selected assignments
                                  if (assignmentIdsToRemove != null) {
                                    // Convert old assignment IDs to new assignment IDs
                                    final newAssignmentIdsToRemove =
                                        assignmentIdsToRemove
                                            .map((oldId) => state
                                                .oldToNewAssignmentIds[oldId])
                                            .where((id) => id != null)
                                            .cast<String>()
                                            .toList();

                                    // Remove the assignments using the repository
                                    if (context.mounted) {
                                      final repository =
                                          context.read<EventRepository>();
                                      await repository
                                          .removeAssignmentsAfterDuplication(
                                              newAssignmentIdsToRemove);
                                    }
                                  }

                                  // Close the modal after handling quota reduction
                                  if (context.mounted) {
                                    widget.onSuccess();
                                  }
                                }
                              },
                              builder: (context, state) {
                                return Form(
                                  key: _formKey,
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                      bottom: 16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const SizedBox(height: 16),

                                        // Category Dropdown (first field)
                                        BlocBuilder<CategoryBloc,
                                            CategoryState>(
                                          builder: (context, state) {
                                            if (state is CategoriesLoaded) {
                                              final categories =
                                                  state.activeCategories;

                                              // If the event's original category is archived, keep it
                                              // in the dropdown for the entire modal session so the user
                                              // can switch back to it after changing away.
                                              final originalCategoryId =
                                                  widget.event?.categoryId;
                                              final archivedOriginal =
                                                  originalCategoryId != null &&
                                                          !categories.any((c) =>
                                                              c.id ==
                                                              originalCategoryId)
                                                      ? state.archivedCategories
                                                          .where((c) =>
                                                              c.id ==
                                                              originalCategoryId)
                                                          .firstOrNull
                                                      : null;

                                              return DropdownButtonFormField<
                                                  String?>(
                                                value: _selectedCategoryId,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'קטגוריה',
                                                  hintText:
                                                      'בחר קטגוריה (אופציונלי)',
                                                  prefixIcon:
                                                      Icon(Icons.category),
                                                  border: OutlineInputBorder(),
                                                ),
                                                selectedItemBuilder: (context) {
                                                  // Build items for display when selected
                                                  final items = <Widget>[];

                                                  // Null option
                                                  items.add(
                                                      const DropdownMenuItem<
                                                          String?>(
                                                    value: null,
                                                    child: Directionality(
                                                      textDirection:
                                                          TextDirection.rtl,
                                                      child: Center(
                                                        child:
                                                            Text('ללא קטגוריה'),
                                                      ),
                                                    ),
                                                  ));

                                                  // Archived original (if exists)
                                                  if (archivedOriginal !=
                                                      null) {
                                                    items.add(DropdownMenuItem<
                                                        String?>(
                                                      value:
                                                          archivedOriginal.id,
                                                      child: Directionality(
                                                        textDirection:
                                                            TextDirection.rtl,
                                                        child: Center(
                                                          child: Text(
                                                            '${archivedOriginal.name} (בארכיון)',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .grey),
                                                          ),
                                                        ),
                                                      ),
                                                    ));
                                                  }

                                                  // Active categories
                                                  for (final category
                                                      in categories) {
                                                    items.add(DropdownMenuItem<
                                                        String?>(
                                                      value: category.id,
                                                      child: Directionality(
                                                        textDirection:
                                                            TextDirection.rtl,
                                                        child: Center(
                                                          child: Text(
                                                              category.name),
                                                        ),
                                                      ),
                                                    ));
                                                  }

                                                  // For "New Category" button index - repeat the first item as fallback
                                                  // This prevents empty display when the button is clicked
                                                  if (items.isNotEmpty) {
                                                    items.add(items.first);
                                                  } else {
                                                    items.add(
                                                        const DropdownMenuItem<
                                                            String?>(
                                                      value: null,
                                                      child: Directionality(
                                                        textDirection:
                                                            TextDirection.rtl,
                                                        child: Center(
                                                          child: Text(
                                                              'ללא קטגוריה'),
                                                        ),
                                                      ),
                                                    ));
                                                  }

                                                  return items;
                                                },
                                                items: [
                                                  // Null option for uncategorized
                                                  const DropdownMenuItem<
                                                      String?>(
                                                    value: null,
                                                    child: Directionality(
                                                      textDirection:
                                                          TextDirection.rtl,
                                                      child: Center(
                                                        child:
                                                            Text('ללא קטגוריה'),
                                                      ),
                                                    ),
                                                  ),
                                                  // If the event's original category is archived, show it
                                                  // greyed out so the user can see and re-select it
                                                  if (archivedOriginal != null)
                                                    DropdownMenuItem<String?>(
                                                      value:
                                                          archivedOriginal.id,
                                                      child: Directionality(
                                                        textDirection:
                                                            TextDirection.rtl,
                                                        child: Center(
                                                          child: Text(
                                                            '${archivedOriginal.name} (בארכיון)',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .grey),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  // Active category options
                                                  ...categories.map((category) {
                                                    return DropdownMenuItem<
                                                        String?>(
                                                      value: category.id,
                                                      child: Directionality(
                                                        textDirection:
                                                            TextDirection.rtl,
                                                        child: Center(
                                                          child: Text(
                                                              category.name),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                  // "New Category" button at the end
                                                  DropdownMenuItem<String?>(
                                                    value:
                                                        '__create_new_category__',
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        // Divider line - shifted up by 4px to counteract DropdownMenuItem's top padding
                                                        Transform.translate(
                                                          offset: const Offset(
                                                              0, -4),
                                                          child: Container(
                                                            height: 1,
                                                            color: Colors
                                                                .grey.shade300,
                                                          ),
                                                        ),
                                                        // Content
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 8),
                                                          child: Directionality(
                                                            textDirection:
                                                                TextDirection
                                                                    .rtl,
                                                            child: Center(
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Icon(
                                                                      Icons
                                                                          .add_circle,
                                                                      size: 16,
                                                                      color: Colors
                                                                          .green
                                                                          .shade700),
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  Flexible(
                                                                    child: Text(
                                                                      'קטגוריה חדשה',
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                      style:
                                                                          TextStyle(
                                                                        color: Colors
                                                                            .green
                                                                            .shade700,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                                onChanged: (value) {
                                                  Logger.action(
                                                      'select:category',
                                                      {'categoryId': value});
                                                  if (value ==
                                                      '__create_new_category__') {
                                                    // Don't update state, just show dialog
                                                    _showCreateCategoryDialog();
                                                    return;
                                                  }
                                                  setState(() {
                                                    _selectedCategoryId = value;
                                                    _isDirty = true;
                                                  });
                                                },
                                              );
                                            } else {
                                              // Loading state or error
                                              return DropdownButtonFormField<
                                                  String?>(
                                                value: null,
                                                decoration: InputDecoration(
                                                  labelText: 'קטגוריה',
                                                  prefixIcon: const Icon(
                                                      Icons.category),
                                                  border: OutlineInputBorder(),
                                                ),
                                                items: [],
                                                onChanged: null,
                                              );
                                            }
                                          },
                                        ),

                                        const SizedBox(height: 16),

                                        // Name field
                                        TextFormField(
                                          controller: _nameController,
                                          focusNode: _nameFocusNode,
                                          decoration: InputDecoration(
                                            labelText: 'שם האירוע',
                                            hintText: 'לדוגמה: חתונת כהן',
                                            prefixIcon:
                                                const Icon(Icons.abc_rounded),
                                            border: const OutlineInputBorder(),
                                            helperText: widget.isDuplication &&
                                                    _nameController
                                                        .text.isNotEmpty &&
                                                    !_validateName
                                                ? '↑ ניתן לערוך את שם האירוע המשוכפל ↑'
                                                : null,
                                            helperStyle: widget.isDuplication &&
                                                    _nameController
                                                        .text.isNotEmpty &&
                                                    !_validateName
                                                ? const TextStyle(
                                                    color: Colors.green)
                                                : null,
                                            errorText: _validateName &&
                                                    _nameController.text.isEmpty
                                                ? 'שדה חובה'
                                                : null,
                                          ),
                                          autovalidateMode: _validateName
                                              ? AutovalidateMode
                                                  .onUserInteraction
                                              : AutovalidateMode.disabled,
                                          validator: Validators.validateName,
                                          onChanged: (_) =>
                                              setState(() => _isDirty = true),
                                        ),

                                        const SizedBox(height: 16),

                                        // Location field
                                        TextFormField(
                                          controller: _locationController,
                                          focusNode: _locationFocusNode,
                                          decoration: InputDecoration(
                                            labelText: 'מיקום',
                                            hintText: 'לדוגמה: אולמי ורסאי',
                                            prefixIcon:
                                                const Icon(Icons.location_on),
                                            border: const OutlineInputBorder(),
                                            // Map picker button and clear button
                                            suffixIcon: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Map picker button
                                                IconButton(
                                                  icon: const Icon(Icons.map,
                                                      color: Colors.blue),
                                                  tooltip: 'בחר מיקום במפה',
                                                  onPressed: () async {
                                                    Logger.action(
                                                        'open:mapLocationPicker');
                                                    // Try to parse existing coordinates from raw location value
                                                    // Only use if user hasn't manually edited the field
                                                    double? initialLat;
                                                    double? initialLng;
                                                    String? initialName;

                                                    final currentText =
                                                        _locationController.text
                                                            .trim();
                                                    final rawLocation =
                                                        _rawLocationValue;

                                                    // Check if user manually edited the field
                                                    if (rawLocation != null &&
                                                        currentText
                                                            .isNotEmpty) {
                                                      final strippedRaw =
                                                          MapLocationResult
                                                              .stripCoordinates(
                                                                  rawLocation);
                                                      if (strippedRaw ==
                                                          currentText) {
                                                        // User didn't edit, use saved coordinates
                                                        final (
                                                          lat,
                                                          lng
                                                        ) = MapLocationResult
                                                            .parseCoordinates(
                                                                rawLocation);
                                                        initialLat = lat;
                                                        initialLng = lng;
                                                        initialName =
                                                            strippedRaw;
                                                        // Only use name if it's not just coordinates
                                                        if (initialName ==
                                                                rawLocation &&
                                                            lat != null) {
                                                          initialName = null;
                                                        }
                                                      }
                                                      // If user edited, leave initialLat/Lng/Name as null (fresh start)
                                                    }

                                                    final result =
                                                        await MapLocationPicker
                                                            .show(
                                                      context,
                                                      title: 'בחר מיקום לאירוע',
                                                      initialLatitude:
                                                          initialLat,
                                                      initialLongitude:
                                                          initialLng,
                                                      initialLocationName:
                                                          initialName,
                                                    );
                                                    if (result != null) {
                                                      setState(() {
                                                        // Store raw value with coordinates for later use
                                                        _rawLocationValue = result
                                                            .toDisplayString();
                                                        // Display stripped version (name only, no coordinates)
                                                        _locationController
                                                                .text =
                                                            MapLocationResult
                                                                .stripCoordinates(
                                                                    result
                                                                        .toDisplayString());
                                                        _isDirty = true;
                                                      });
                                                    }
                                                  },
                                                ),
                                                // Clear button (only show if there's a value)
                                                if (_locationController
                                                    .text.isNotEmpty)
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.clear,
                                                        color: Colors.grey),
                                                    tooltip: 'נקה מיקום',
                                                    onPressed: () {
                                                      Logger.action(
                                                          'tap:clearLocation');
                                                      setState(() {
                                                        _rawLocationValue =
                                                            null;
                                                        _locationController
                                                            .clear();
                                                        _isDirty = true;
                                                      });
                                                    },
                                                  ),
                                              ],
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'נא למלא מיקום';
                                            }
                                            return null;
                                          },
                                          onChanged: (_) =>
                                              setState(() => _isDirty = true),
                                        ),

                                        const SizedBox(height: 16),

                                        // Parking Location field
                                        TextFormField(
                                          controller:
                                              _parkingLocationController,
                                          focusNode: _parkingLocationFocusNode,
                                          decoration: InputDecoration(
                                            labelText: 'מיקום חנייה',
                                            hintText: 'לדוגמה: חניון יקב',
                                            prefixIcon: const Icon(
                                                Icons.local_parking,
                                                color: Colors.purple),
                                            border: const OutlineInputBorder(),
                                            // Parking picker button, editors button, and clear button
                                            suffixIcon: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Parking picker button (map)
                                                IconButton(
                                                  icon: const Icon(Icons.map,
                                                      color: Colors.blue),
                                                  tooltip:
                                                      'בחר מיקום חנייה במפה',
                                                  onPressed: () async {
                                                    Logger.action(
                                                        'open:parkingLocationPicker');
                                                    // Get current event location from form (not from DB)
                                                    String
                                                        currentEventLocation =
                                                        _locationController.text
                                                            .trim();
                                                    if (_rawLocationValue !=
                                                        null) {
                                                      final strippedRaw =
                                                          MapLocationResult
                                                              .stripCoordinates(
                                                                  _rawLocationValue!);
                                                      if (strippedRaw ==
                                                          currentEventLocation) {
                                                        // User didn't edit, use raw value with coordinates
                                                        currentEventLocation =
                                                            _rawLocationValue!;
                                                      }
                                                    }

                                                    final result =
                                                        await ParkingLocationPickerDialog
                                                            .show(
                                                      context,
                                                      eventLocation:
                                                          currentEventLocation,
                                                      initialParkingLocation:
                                                          _rawParkingLocationValue,
                                                    );

                                                    if (result != null) {
                                                      // Convert empty string to null (user clicked "Clear")
                                                      final parkingLocation =
                                                          result.parkingLocation
                                                                  .isEmpty
                                                              ? null
                                                              : result
                                                                  .parkingLocation;
                                                      setState(() {
                                                        _rawParkingLocationValue =
                                                            parkingLocation;
                                                        _parkingLocationController
                                                            .text = parkingLocation !=
                                                                null
                                                            ? MapLocationResult
                                                                .stripCoordinates(
                                                                    parkingLocation)
                                                            : '';
                                                        _isDirty = true;
                                                      });
                                                    }
                                                  },
                                                ),
                                                // Parking editors button (people)
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.people,
                                                    color: _parkingEditorIds
                                                            .isNotEmpty
                                                        ? Colors.green
                                                        : Colors.grey,
                                                  ),
                                                  tooltip:
                                                      'עורכים מורשים למיקום חנייה',
                                                  onPressed: () async {
                                                    Logger.action(
                                                        'open:parkingEditorsDialog',
                                                        {
                                                          'count':
                                                              _parkingEditorIds
                                                                  .length
                                                        });
                                                    final result =
                                                        await ParkingEditorsDialog
                                                            .show(
                                                      context,
                                                      initialEditorIds:
                                                          _parkingEditorIds,
                                                    );

                                                    if (result != null) {
                                                      setState(() {
                                                        _parkingEditorIds =
                                                            result;
                                                        _isDirty = true;
                                                      });
                                                    }
                                                  },
                                                ),
                                                // Clear button (only show if there's a value)
                                                if (_parkingLocationController
                                                    .text.isNotEmpty)
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.clear,
                                                        color: Colors.grey),
                                                    tooltip: 'נקה מיקום חנייה',
                                                    onPressed: () {
                                                      Logger.action(
                                                          'tap:clearParkingLocation');
                                                      setState(() {
                                                        _rawParkingLocationValue =
                                                            null;
                                                        _parkingLocationController
                                                            .clear();
                                                        _parkingEditorIds =
                                                            const [];
                                                        _isDirty = true;
                                                      });
                                                    },
                                                  ),
                                              ],
                                            ),
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              _isDirty = true;
                                              // Update raw value when user types directly
                                              // (without coordinates since they're typing manually)
                                              _rawParkingLocationValue =
                                                  value.trim().isEmpty
                                                      ? null
                                                      : value.trim();
                                            });
                                          },
                                        ),

                                        const SizedBox(height: 16),

                                        // Participant count (כמות משתתפים)
                                        TextFormField(
                                          controller: _participantCountController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(7),
                                          ],
                                          onChanged: (_) {
                                            _isDirty = true;
                                          },
                                          decoration: InputDecoration(
                                            labelText:
                                                'כמות משתתפים (אופציונלי)',
                                            hintText: 'לדוגמה: 250',
                                            prefixIcon:
                                                const Icon(Icons.groups),
                                            border: const OutlineInputBorder(),
                                            suffixIcon: _participantCountController
                                                    .text.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(
                                                        Icons.clear,
                                                        color: Colors.grey),
                                                    onPressed: () {
                                                      Logger.action(
                                                          'tap:clearParticipantCount');
                                                      setState(() {
                                                        _participantCountController
                                                            .clear();
                                                        _isDirty = true;
                                                      });
                                                    },
                                                  )
                                                : null,
                                          ),
                                        ),

                                        const SizedBox(height: 16),

                                        // Date Selection (Dual Calendar)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Label for dates field
                                            const Text(
                                              'תאריכי האירוע',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                // Date picker button
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () async {
                                                      Logger.action(
                                                          'open:datePicker');
                                                      final today =
                                                          DateTime.now();
                                                      final todayDate =
                                                          DateTime(
                                                              today.year,
                                                              today.month,
                                                              today.day);
                                                      final result =
                                                          await showDialog<
                                                              Map<String,
                                                                  DateTime?>>(
                                                        context: context,
                                                        builder: (context) =>
                                                            DualCalendarDatePicker(
                                                          isSingleDate: false,
                                                          initialStartDate:
                                                              _startDate,
                                                          initialEndDate:
                                                              _endDate,
                                                          // Prevent selecting
                                                          // dates before today
                                                          minDate: todayDate,
                                                          title:
                                                              'בחר תאריכי אירוע',
                                                        ),
                                                      );

                                                      if (result != null) {
                                                        final selectedStartDate =
                                                            result['startDate'];
                                                        final selectedEndDate =
                                                            result['endDate'];

                                                        // Check if only start date was selected
                                                        if (selectedStartDate !=
                                                                null &&
                                                            selectedEndDate ==
                                                                null) {
                                                          // Single day event - no confirmation needed
                                                          setState(() {
                                                            _startDate =
                                                                selectedStartDate;
                                                            _endDate =
                                                                selectedStartDate; // For single day event
                                                            _dateError = null;
                                                            _isDirty = true;
                                                          });
                                                        } else if (selectedStartDate !=
                                                                null &&
                                                            selectedEndDate !=
                                                                null) {
                                                          // Check if start and end dates are the same
                                                          final isSameDate = selectedStartDate
                                                                      .year ==
                                                                  selectedEndDate
                                                                      .year &&
                                                              selectedStartDate
                                                                      .month ==
                                                                  selectedEndDate
                                                                      .month &&
                                                              selectedStartDate
                                                                      .day ==
                                                                  selectedEndDate
                                                                      .day;

                                                          if (isSameDate) {
                                                            // Single day event - no confirmation needed
                                                            setState(() {
                                                              _startDate =
                                                                  selectedStartDate;
                                                              _endDate =
                                                                  selectedStartDate; // For single day event
                                                              _dateError = null;
                                                              _isDirty = true;
                                                            });
                                                          } else {
                                                            // Multi-day event
                                                            setState(() {
                                                              _startDate =
                                                                  selectedStartDate;
                                                              _endDate =
                                                                  selectedEndDate;
                                                              _dateError = null;
                                                              _isDirty = true;
                                                            });
                                                          }
                                                        }
                                                      }
                                                    },
                                                    icon: const Icon(
                                                        Icons.calendar_month),
                                                    label: Text(
                                                      _startDate == null
                                                          ? 'בחר תאריכי אירוע'
                                                          : (_endDate != null &&
                                                                  _isSameDay(
                                                                      _startDate!,
                                                                      _endDate!))
                                                              ? _formatDate(
                                                                  _startDate!)
                                                              : _endDate == null
                                                                  ? 'מ-${_formatDate(_startDate!)}'
                                                                  : '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}',
                                                    ),
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16),
                                                      alignment:
                                                          Alignment.centerRight,
                                                      side: BorderSide(
                                                        color:
                                                            _dateError != null
                                                                ? Colors.red
                                                                    .shade700
                                                                : Colors.grey,
                                                        width:
                                                            _dateError != null
                                                                ? 2
                                                                : 1,
                                                      ),
                                                      backgroundColor:
                                                          _dateError != null
                                                              ? Colors
                                                                  .red.shade50
                                                              : null,
                                                    ),
                                                  ),
                                                ),
                                                // Clear button (only show if dates are selected)
                                                if (_startDate != null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 8),
                                                    child: IconButton(
                                                      onPressed: () {
                                                        Logger.action(
                                                            'tap:clearDates');
                                                        setState(() {
                                                          _startDate = null;
                                                          _endDate = null;
                                                          _isDirty = true;
                                                        });
                                                      },
                                                      icon: const Icon(
                                                          Icons.clear,
                                                          color: Colors.red),
                                                      tooltip: 'נקה תאריכים',
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (widget.isDuplication &&
                                                _startDate == null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 16,
                                                    top: 4,
                                                    bottom: 8),
                                                child: Text(
                                                  _dateError ??
                                                      '↑ יש לבחור תאריכים חדשים לאירוע המשוכפל ↑',
                                                  style: TextStyle(
                                                    color: _dateError != null
                                                        ? Colors.red.shade700
                                                        : Colors.green,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            if (!widget.isDuplication &&
                                                _dateError != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 16,
                                                    top: 4,
                                                    bottom: 8),
                                                child: Text(
                                                  _dateError!,
                                                  style: TextStyle(
                                                    color: Colors.red.shade700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),

                                        const SizedBox(height: 16),

                                        // Label marking the start of the event
                                        // time fields (mirrors 'תאריכי האירוע').
                                        const Text(
                                          'שעות האירוע',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),

                                        // Assembly Time (שעת התייצבות)
                                        _buildTimeField(
                                          controller: _assemblyTimeController,
                                          label: 'שעת התייצבות (אופציונלי)',
                                          hint: 'לדוגמה: 17:00',
                                          prefixIcon: Icons.access_time,
                                          logKey: 'assembly',
                                        ),

                                        // Derive arrow: התכנסות קהל → התייצבות
                                        // (2h before). Points up toward the
                                        // target field above.
                                        _buildDeriveArrow(
                                          source: _startTimeController,
                                          target: _assemblyTimeController,
                                          offsetMinutes: -120,
                                          pointsUp: true,
                                          label: 'שעתיים לפני',
                                          logKey: 'assemblyFromStart',
                                        ),

                                        const SizedBox(height: 8),

                                        // Start Time (Audience Gathering Time)
                                        _buildTimeField(
                                          controller: _startTimeController,
                                          label: 'שעת התכנסות קהל (אופציונלי)',
                                          hint: 'לדוגמה: 18:00',
                                          prefixIcon: Icons.access_time,
                                          logKey: 'start',
                                          onPicked: (value) {
                                            // Live auto-fill: if התייצבות is
                                            // still empty, default it to 2h
                                            // before the gathering time.
                                            if (_assemblyTimeController.text
                                                .trim()
                                                .isEmpty) {
                                              final derived = app_date_utils
                                                  .DateUtils
                                                  .shiftHmByMinutes(value, -120);
                                              if (derived != null) {
                                                _assemblyTimeController.text =
                                                    derived;
                                              }
                                            }
                                          },
                                        ),

                                        const SizedBox(height: 16),

                                        // Actual Show Start Time
                                        _buildTimeField(
                                          controller:
                                              _actualShowStartTimeController,
                                          label:
                                              'שעת תחילת המופע בפועל (אופציונלי)',
                                          hint: 'לדוגמה: 19:00',
                                          prefixIcon: Icons.play_circle_outline,
                                          logKey: 'actualShowStart',
                                        ),

                                        const SizedBox(height: 16),

                                        // End Time (show estimated end)
                                        _buildTimeField(
                                          controller: _endTimeController,
                                          label:
                                              'שעת סיום משוערת של המופע (אופציונלי)',
                                          hint: 'לדוגמה: 23:00',
                                          prefixIcon: Icons.access_time,
                                          logKey: 'end',
                                          onPicked: (value) {
                                            // Live auto-fill: if סיום הצוות is
                                            // still empty, default it to 1h
                                            // after the show end time.
                                            if (_teamEndTimeController.text
                                                .trim()
                                                .isEmpty) {
                                              final derived = app_date_utils
                                                  .DateUtils
                                                  .shiftHmByMinutes(value, 60);
                                              if (derived != null) {
                                                _teamEndTimeController.text =
                                                    derived;
                                              }
                                            }
                                          },
                                        ),

                                        // Derive arrow: סיום המופע → סיום הצוות
                                        // (1h after). Points down toward the
                                        // target field below.
                                        _buildDeriveArrow(
                                          source: _endTimeController,
                                          target: _teamEndTimeController,
                                          offsetMinutes: 60,
                                          pointsUp: false,
                                          label: 'שעה אחרי',
                                          logKey: 'teamEndFromEnd',
                                        ),

                                        const SizedBox(height: 8),

                                        // Team End Time (שעת סיום משוערת של הצוות)
                                        _buildTimeField(
                                          controller: _teamEndTimeController,
                                          label:
                                              'שעת סיום משוערת של הצוות (אופציונלי)',
                                          hint: 'לדוגמה: 00:00',
                                          prefixIcon: Icons.access_time,
                                          logKey: 'teamEnd',
                                        ),

                                        const SizedBox(height: 16),

                                        // Requires Armed
                                        SwitchListTile(
                                          title: const Text('דרוש חמוש'),
                                          value: _requiresArmed,
                                          onChanged: (v) {
                                            Logger.action('toggle:requiresArmed',
                                                {'on': v});
                                            setState(() {
                                              _requiresArmed = v;
                                              _isDirty = true;
                                            });
                                          },
                                        ),

                                        // Permanent Team Only (inverted logic for UI)
                                        SwitchListTile(
                                          title: const Text('צוות קבוע בלבד?'),
                                          subtitle: const Text(
                                              'האם האירוע מיועד לצוות הקבוע בלבד (לא לצוות המורחב)?'),
                                          value: _relevantForExtendedTeam,
                                          onChanged: (v) {
                                            Logger.action(
                                                'toggle:permanentTeamOnly',
                                                {'on': v});
                                            setState(() {
                                              _relevantForExtendedTeam = v;
                                              if (!v) {
                                                // Not permanent-only: this feature
                                                // is not applicable.
                                                _inviteAllPermanentWhenUnassigned =
                                                    false;
                                              }
                                              _isDirty = true;
                                            });
                                          },
                                        ),

                                        // Invite all permanent staff to the
                                        // calendar while the event has no
                                        // assignments. Enabled only while
                                        // "permanent team only" is ON.
                                        // In duplication mode this toggle is
                                        // always OFF and non-interactive:
                                        // DuplicateEvent does not carry this
                                        // flag, so we start it disabled to
                                        // avoid a misleading "saved as ON"
                                        // illusion. Enable it via edit after
                                        // duplicating.
                                        SwitchListTile(
                                          title: const Text(
                                              'הזמן את כל הצוות הקבוע כשאין שיבוצים?'),
                                          subtitle: const Text(
                                              'כשאין אף שיבוץ באירוע, כל הצוות הקבוע עם אימייל יוזמן ליומן. עם השיבוץ הראשון – רק המשובצים יוזמנו.'),
                                          value: !widget.isDuplication &&
                                              _relevantForExtendedTeam &&
                                              _inviteAllPermanentWhenUnassigned,
                                          onChanged: !widget.isDuplication &&
                                                  _relevantForExtendedTeam
                                              ? (v) {
                                                  Logger.action(
                                                      'toggle:inviteAllPermanentWhenUnassigned',
                                                      {'on': v});
                                                  setState(() {
                                                    _inviteAllPermanentWhenUnassigned =
                                                        v;
                                                    _isDirty = true;
                                                  });
                                                }
                                              : null,
                                        ),

                                        // Duplicate Assignments (only show in duplication mode)
                                        if (widget.isDuplication) ...[
                                          const SizedBox(height: 8),
                                          SwitchListTile(
                                            title: const Text(
                                                'שכפל גם את השיבוצים'),
                                            subtitle: Text(
                                              _duplicateAssignments
                                                  ? 'כל השיבוצים יועברו לאירוע החדש (בהתחשב בזמינות)'
                                                  : 'רק פרטי האירוע ישוכפלו, ללא שיבוצים',
                                            ),
                                            value: _duplicateAssignments,
                                            onChanged: (v) {
                                              Logger.action(
                                                  'toggle:duplicateAssignments',
                                                  {'on': v});
                                              setState(() {
                                                _duplicateAssignments = v;
                                                _isDirty = true;
                                              });
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                        ],

                                        const Divider(height: 32),

                                        // Role Requirements
                                        const Text(
                                          'תפקידים נדרשים',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 8),
                                        BlocBuilder<RoleBloc, RoleState>(
                                          builder: (context, roleState) {
                                            // Handle different states
                                            if (roleState is! RolesLoaded) {
                                              // Show loading or fallback to RoleType.values during initial load
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children:
                                                    RoleType.values.map((role) {
                                                  final isHighlighted =
                                                      _highlightedRole == role;
                                                  return AnimatedContainer(
                                                    key: _roleKeys[role],
                                                    duration: const Duration(
                                                        milliseconds: 500),
                                                    decoration: BoxDecoration(
                                                      color: isHighlighted
                                                          ? Colors.blue.shade100
                                                              .withValues(
                                                                  alpha:
                                                                      _highlightOpacity)
                                                          : null,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: isHighlighted
                                                          ? Border.all(
                                                              color: Colors
                                                                  .blue.shade700
                                                                  .withValues(
                                                                      alpha:
                                                                          _highlightOpacity),
                                                              width: 2,
                                                            )
                                                          : null,
                                                    ),
                                                    child: ListTile(
                                                      title: Text(
                                                        role.hebrewName,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              isHighlighted
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .normal,
                                                          color: isHighlighted
                                                              ? Colors
                                                                  .blue.shade900
                                                              : null,
                                                        ),
                                                      ),
                                                      trailing: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          IconButton(
                                                            icon: const Icon(Icons
                                                                .remove_circle_outline),
                                                            onPressed: () {
                                                              Logger.action(
                                                                  'tap:decrementRoleQuota',
                                                                  {
                                                                    'role':
                                                                        role.key
                                                                  });
                                                              if ((_roleRequirements[
                                                                          role.key] ??
                                                                      0) >
                                                                  0) {
                                                                setState(() {
                                                                  _roleRequirements[
                                                                          role.key] =
                                                                      (_roleRequirements[role.key] ??
                                                                              0) -
                                                                          1;
                                                                  _isDirty =
                                                                      true;
                                                                });
                                                              }
                                                            },
                                                          ),
                                                          SizedBox(
                                                            width: 40,
                                                            child: Text(
                                                              (_roleRequirements[
                                                                          role.key] ??
                                                                      0)
                                                                  .toString(),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: const TextStyle(
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold),
                                                            ),
                                                          ),
                                                          IconButton(
                                                            icon: const Icon(Icons
                                                                .add_circle_outline),
                                                            onPressed: () {
                                                              Logger.action(
                                                                  'tap:incrementRoleQuota',
                                                                  {
                                                                    'role':
                                                                        role.key
                                                                  });
                                                              setState(() {
                                                                _roleRequirements[
                                                                        role.key] =
                                                                    (_roleRequirements[role.key] ??
                                                                            0) +
                                                                        1;
                                                                _isDirty = true;
                                                              });
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              );
                                            }

                                            // Use roles from RoleBloc
                                            final roles =
                                                (roleState as RolesLoaded)
                                                    .visibleRoles;

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: roles.map((roleObj) {
                                                // Use role key (String) directly as the map key
                                                final roleKey = roleObj.key;

                                                // Map role.key to RoleType enum for highlighting (legacy support)
                                                final RoleType? roleType =
                                                    _tryParseRoleType(roleKey);
                                                final isHighlighted =
                                                    roleType != null &&
                                                        _highlightedRole ==
                                                            roleType;

                                                return AnimatedContainer(
                                                  key: roleType != null
                                                      ? _roleKeys[roleType]
                                                      : null,
                                                  duration: const Duration(
                                                      milliseconds: 500),
                                                  decoration: BoxDecoration(
                                                    color: isHighlighted
                                                        ? Colors.blue.shade100
                                                            .withValues(
                                                                alpha:
                                                                    _highlightOpacity)
                                                        : null,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    border: isHighlighted
                                                        ? Border.all(
                                                            color: Colors
                                                                .blue.shade700
                                                                .withValues(
                                                                    alpha:
                                                                        _highlightOpacity),
                                                            width: 2,
                                                          )
                                                        : null,
                                                  ),
                                                  child: ListTile(
                                                    title: Text(
                                                      roleObj.hebrewName,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            isHighlighted
                                                                ? FontWeight
                                                                    .bold
                                                                : FontWeight
                                                                    .normal,
                                                        color: isHighlighted
                                                            ? Colors
                                                                .blue.shade900
                                                            : null,
                                                      ),
                                                    ),
                                                    trailing: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(Icons
                                                              .remove_circle_outline),
                                                          onPressed: () {
                                                            Logger.action(
                                                                'tap:decrementRoleQuota',
                                                                {
                                                                  'role': roleKey
                                                                });
                                                            if (_roleRequirements[
                                                                    roleKey]! >
                                                                0) {
                                                              setState(() {
                                                                _roleRequirements[
                                                                        roleKey] =
                                                                    _roleRequirements[
                                                                            roleKey]! -
                                                                        1;
                                                                _isDirty = true;
                                                              });
                                                            }
                                                          },
                                                        ),
                                                        SizedBox(
                                                          width: 40,
                                                          child: Text(
                                                            (_roleRequirements[
                                                                        roleKey] ??
                                                                    0)
                                                                .toString(),
                                                            textAlign: TextAlign
                                                                .center,
                                                            style: const TextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold),
                                                          ),
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(Icons
                                                              .add_circle_outline),
                                                          onPressed: () {
                                                            Logger.action(
                                                                'tap:incrementRoleQuota',
                                                                {
                                                                  'role': roleKey
                                                                });
                                                            setState(() {
                                                              _roleRequirements[
                                                                      roleKey] =
                                                                  (_roleRequirements[
                                                                              roleKey] ??
                                                                          0) +
                                                                      1;
                                                              _isDirty = true;
                                                            });
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            );
                                          },
                                        ),

                                        // Comments
                                        TextFormField(
                                          controller: _commentsController,
                                          focusNode: _commentsFocusNode,
                                          decoration: const InputDecoration(
                                            labelText: 'הערות',
                                            hintText: 'הערות על האירוע',
                                            prefixIcon: Icon(Icons.comment),
                                            border: OutlineInputBorder(),
                                          ),
                                          minLines: 1,
                                          maxLines: 3,
                                          scrollPadding: const EdgeInsets.only(
                                              bottom: 300),
                                          onChanged: (_) =>
                                              setState(() => _isDirty = true),
                                        ),

                                        // Dynamic bottom spacing for keyboard
                                        SizedBox(
                                            height: MediaQuery.of(context)
                                                .viewInsets
                                                .bottom),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          // Modal Footer (Fixed at bottom)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                            Logger.action(
                                                'tap:cancel:eventFormModal');
                                            _handleClose();
                                          },
                                    child: const Text('ביטול'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                            Logger.action('tap:saveEvent', {
                                              'mode': widget.isDuplication
                                                  ? 'duplicate'
                                                  : (_isEditMode
                                                      ? 'edit'
                                                      : 'create'),
                                            });
                                            _saveEvent();
                                          },
                                    child: _isSaving
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : Text(widget.isDuplication
                                            ? 'שכפל אירוע'
                                            : 'שמור'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Loading overlay
                    LoadingOverlay(
                      isLoading: _isSaving,
                      message: _loadingMessage,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }, // Close DraggableScrollableSheet builder
    ); // Close DraggableScrollableSheet
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Show dialog to create a new category
  void _showCreateCategoryDialog() {
    final controller = TextEditingController();
    final focusNode = createRtlCursorFixedFocusNode(controller);

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('צור קטגוריה חדשה'),
          content: TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: const InputDecoration(
              labelText: 'שם הקטגוריה',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:cancel:createCategory');
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                Logger.action('tap:createCategory');
                if (controller.text.trim().isNotEmpty) {
                  context.read<CategoryBloc>().add(CreateCategory(
                        controller.text.trim(),
                      ));
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('צור'),
            ),
          ],
        ),
      ),
    ).then((_) {
      focusNode.dispose();
      controller.dispose();
    });
  }
}
