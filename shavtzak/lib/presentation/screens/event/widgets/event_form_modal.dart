import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../core/utils/validators.dart';
import '../../../../domain/entities/event.dart';
import '../../../../data/repositories/assignment_repository.dart';
import '../../../../data/repositories/event_repository.dart';
import '../../../bloc/event/event_bloc.dart';
import '../../../bloc/event/event_event.dart';
import '../../../bloc/event/event_state.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';
import '../../../widgets/date_picker_dialog.dart';
import '../../../widgets/map_location_picker.dart';
import '../../../widgets/parking_location_picker_dialog.dart';
import '../quota_reduction_analyzer.dart';
import 'quota_reduction_dialog.dart';
import 'duplication_conflict_resolution_dialog.dart';
import 'event_drive_files_section.dart';

/// Public Event Form Modal Widget for creating/editing events
/// Can be used from any screen that needs to create or edit events
class EventFormModal extends StatefulWidget {
  final Event? event; // null for create, non-null for edit
  final VoidCallback onSuccess;
  final RoleType? selectedRole; // Optional role to highlight/scroll to
  final int filterIndex; // Filter index to reload with after operations (0=all, 1=future, 2=past)
  final bool isDuplication; // true if this is a duplication modal

  const EventFormModal({
    super.key,
    this.event,
    required this.onSuccess,
    this.selectedRole,
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
  final _assemblyTimeController = TextEditingController();
  final _actualShowStartTimeController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _requiresArmed = false;
  Map<String, int> _roleRequirements = {};
  bool _isDirty = false;
  bool _validateName = false; // Enable name validation after blur or submit
  String? _dateError; // Track date validation error
  final _nameFocusNode = FocusNode(); // For name field blur detection
  bool _duplicateAssignments = false; // For duplication mode checkbox
  String? _rawLocationValue; // Stores location with hidden coordinates (Name||lat,lng)
  String? _rawParkingLocationValue; // Stores parking location with hidden coordinates
  List<String> _parkingEditorIds = const []; // IDs of team members who can edit parking

  // For highlighting selected role
  ScrollController? _scrollController; // Will be set from DraggableScrollableSheet
  final _sheetController = DraggableScrollableController(); // Controller to expand sheet
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
      _locationController.text = MapLocationResult.stripCoordinates(widget.event!.location);
      _rawParkingLocationValue = widget.event!.parkingLocation;
      _parkingLocationController.text = widget.event!.parkingLocation != null
          ? MapLocationResult.stripCoordinates(widget.event!.parkingLocation!)
          : '';
      _parkingEditorIds = widget.event!.parkingEditorIds;
      _commentsController.text = widget.event!.comments;
      _startTimeController.text = widget.event!.startTime;
      _endTimeController.text = widget.event!.endTime;
      _assemblyTimeController.text = widget.event!.assemblyTime;
      _actualShowStartTimeController.text = widget.event!.actualShowStartTime;

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
    }

    _nameController.addListener(() => _isDirty = true);
    _locationController.addListener(() => _isDirty = true);
    _parkingLocationController.addListener(() => _isDirty = true);
    _commentsController.addListener(() => _isDirty = true);

    // Enable validation when name field loses focus
    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus && _nameController.text.isNotEmpty) {
        setState(() {
          _validateName = true;
        });
      }
    });

    // If a role was selected, scroll to it and highlight after build
    if (widget.selectedRole != null) {
      _highlightedRole = widget.selectedRole;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToRole(widget.selectedRole!);
      });
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
    _assemblyTimeController.dispose();
    _actualShowStartTimeController.dispose();
    _nameFocusNode.dispose();
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

  Future<void> _saveEvent() async {
    // Enable validation for all fields after first submit attempt
    setState(() {
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
      return;
    }
    if (_startDate == null || _endDate == null) {
      // This is now redundant since we set the error above, but keeping for safety
      return;
    }

    // For duplication mode, create the duplicated event
    if (widget.isDuplication) {
      // Validate that dates are selected
      if (_startDate == null || _endDate == null) {
        setState(() {
          _dateError = '↑ יש לבחור תאריכי התחלה וסיום לאירוע המשוכפל ↑';
        });
        return;
      }

      // Use raw location value (with hidden coordinates) if available and unchanged
      String dupLocationValue = _locationController.text.trim();
      if (_rawLocationValue != null) {
        final strippedRaw = MapLocationResult.stripCoordinates(_rawLocationValue!);
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
        newAssemblyTime: _assemblyTimeController.text,
        newActualShowStartTime: _actualShowStartTimeController.text,
        newRequiresArmed: _requiresArmed,
        newRoleRequirements: Map.from(_roleRequirements),
        duplicateAssignments: _duplicateAssignments,
      ));

      // If duplicating WITH assignments, DON'T close immediately!
      // The BlocListener will handle showing conflict dialog or closing on success.
      // If duplicating WITHOUT assignments, close immediately (no conflicts possible).
      if (!_duplicateAssignments) {
        widget.onSuccess();
      }
      // When _duplicateAssignments is true, the modal stays open
      // and the BlocListener will handle the response
      return;
    }

    // NEW: Quota reduction analysis (edit mode only)
    if (_isEditMode) {
      try {
        final conflicts = await QuotaReductionAnalyzer.analyzeQuotaReductions(
          originalEvent: widget.event!,
          newRoleRequirements: _roleRequirements, // Directly pass String-keyed map
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
              remainingAssignments.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

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
            final roleAssignments = allAssignments
                .where((a) => a.roleType == roleKey)
                .toList();

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
        return;
      }
    }

    final now = DateTime.now();
    // Use raw location value (with hidden coordinates) if available and unchanged
    // Otherwise use the text field value (user typed manually)
    String locationValue = _locationController.text.trim();
    if (_rawLocationValue != null) {
      final strippedRaw = MapLocationResult.stripCoordinates(_rawLocationValue!);
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
      assemblyTime: _assemblyTimeController.text.trim(),
      actualShowStartTime: _actualShowStartTimeController.text.trim(),
      location: locationValue,
      parkingLocation: _rawParkingLocationValue,
      parkingEditorIds: _parkingEditorIds,
      requiresArmed: _requiresArmed,
      comments: _commentsController.text.trim(),
      roleRequirements: _roleRequirements,
      createdAt: _isEditMode ? widget.event!.createdAt : now,
      updatedAt: now,
      // Preserve Drive-related fields when updating
      driveFolderId: _isEditMode ? widget.event!.driveFolderId : null,
      driveFolderLink: _isEditMode ? widget.event!.driveFolderLink : null,
      isArchived: _isEditMode ? widget.event!.isArchived : false,
    );

    if (!mounted) return;
    final bloc = context.read<EventBloc>();
    if (_isEditMode) {
      bloc.add(UpdateEvent(event));
    } else {
      bloc.add(CreateEvent(event));
    }

  
    // Close modal after save operation
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
            content: const Text('האם אתה בטוח שברצונך לצאת? השינויים לא יישמרו.'),
            actions: [
              TextButton(
                child: const Text('ביטול'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('צא'),
                onPressed: () {
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
                final horizontalPadding = maxWidth > 1000
                  ? (maxWidth - 1000) / 2
                  : 0.0;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                                  _isEditMode ? 'עריכת אירוע' : 'הוספת אירוע',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        if (_isEditMode)
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (dialogContext) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AlertDialog(
                                    title: const Text('מחיקת אירוע'),
                                    content: Text(
                                      'האם אתה בטוח שברצונך למחוק את ${widget.event!.name}?\nפעולה זו תמחק גם את כל השיבוצים.',
                                    ),
                                    actions: [
                                      TextButton(
                                        child: const Text('ביטול'),
                                        onPressed: () => Navigator.of(dialogContext).pop(),
                                      ),
                                      TextButton(
                                        child: const Text('מחק', style: TextStyle(color: Colors.red)),
                                        onPressed: () {
                                          final bloc = context.read<EventBloc>();
                                          bloc.add(DeleteEvent(widget.event!.id));
                                          Navigator.of(dialogContext).pop(); // Close dialog
                                          widget.onSuccess(); // Close modal
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
                            icon: const Icon(Icons.copy, color: Colors.blue),
                            onPressed: () {
                              Navigator.of(context).pop(); // Close current modal
                              _showDuplicationModal(); // Open duplication modal
                            },
                            tooltip: 'שכפל אירוע',
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _handleClose,
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
                        if (state is DuplicationRequiresConflictResolution) {
                          // Show the unified conflict resolution dialog
                          final excludedIds = await DuplicationConflictResolutionDialog.show(
                            context,
                            state,
                          );

                          if (excludedIds != null) {
                            // User confirmed - dispatch confirmation event with exclusions
                            if (context.mounted) {
                              context.read<EventBloc>().add(ConfirmDuplicationWithExclusions(
                                originalEvent: state.originalEvent,
                                proposedEvent: state.proposedEvent,
                                assignmentIdsToExclude: excludedIds,
                                originalAssignmentIds: state.assignmentInfos
                                    .map((info) => info.assignment.id)
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
                          if (context.mounted) {
                            widget.onSuccess();
                          }
                        }

                        // Handle old quota conflicts state (LEGACY - kept for backwards compatibility)
                        if (state is EventDuplicatedWithQuotaConflicts) {
                          // Show the quota reduction dialog
                          final assignmentIdsToRemove = await QuotaReductionDialog.show(
                            context,
                            state.quotaConflicts,
                          );

                          // If user made selections, remove the selected assignments
                          if (assignmentIdsToRemove != null) {
                            // Convert old assignment IDs to new assignment IDs
                            final newAssignmentIdsToRemove = assignmentIdsToRemove
                                .map((oldId) => state.oldToNewAssignmentIds[oldId])
                                .where((id) => id != null)
                                .cast<String>()
                                .toList();

                            // Remove the assignments using the repository
                            if (context.mounted) {
                              final repository = context.read<EventRepository>();
                              await repository.removeAssignmentsAfterDuplication(newAssignmentIdsToRemove);
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                              const SizedBox(height: 16),

                              // Name field
                              TextFormField(
                                controller: _nameController,
                                focusNode: _nameFocusNode,
                                textDirection: TextDirection.rtl,
                                decoration: InputDecoration(
                                  labelText: 'שם האירוע',
                                  hintText: 'לדוגמה: חתונת כהן',
                                  prefixIcon: const Icon(Icons.abc_rounded),
                                  border: const OutlineInputBorder(),
                                  helperText: widget.isDuplication && _nameController.text.isNotEmpty && !_validateName
                                      ? '↑ ניתן לערוך את שם האירוע המשוכפל ↑'
                                      : null,
                                  helperStyle: widget.isDuplication && _nameController.text.isNotEmpty && !_validateName
                                      ? const TextStyle(color: Colors.green)
                                      : null,
                                  errorText: _validateName && _nameController.text.isEmpty
                                      ? 'שדה חובה'
                                      : null,
                                ),
                                autovalidateMode: _validateName
                                    ? AutovalidateMode.onUserInteraction
                                    : AutovalidateMode.disabled,
                                validator: Validators.validateName,
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Location field
                              TextFormField(
                                controller: _locationController,
                                textDirection: TextDirection.rtl,
                                decoration: InputDecoration(
                                  labelText: 'מיקום',
                                  hintText: 'לדוגמה: אולמי ורסאי',
                                  prefixIcon: const Icon(Icons.location_on),
                                  border: const OutlineInputBorder(),
                                  // Map picker button and clear button
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Map picker button
                                      IconButton(
                                        icon: const Icon(Icons.map, color: Colors.blue),
                                        tooltip: 'בחר מיקום במפה',
                                        onPressed: () async {
                                          // Try to parse existing coordinates from raw location value
                                          // Only use if user hasn't manually edited the field
                                          double? initialLat;
                                          double? initialLng;
                                          String? initialName;

                                          final currentText = _locationController.text.trim();
                                          final rawLocation = _rawLocationValue;

                                          // Check if user manually edited the field
                                          if (rawLocation != null && currentText.isNotEmpty) {
                                            final strippedRaw = MapLocationResult.stripCoordinates(rawLocation);
                                            if (strippedRaw == currentText) {
                                              // User didn't edit, use saved coordinates
                                              final (lat, lng) = MapLocationResult.parseCoordinates(rawLocation);
                                              initialLat = lat;
                                              initialLng = lng;
                                              initialName = strippedRaw;
                                              // Only use name if it's not just coordinates
                                              if (initialName == rawLocation && lat != null) {
                                                initialName = null;
                                              }
                                            }
                                            // If user edited, leave initialLat/Lng/Name as null (fresh start)
                                          }

                                          final result = await MapLocationPicker.show(
                                            context,
                                            title: 'בחר מיקום לאירוע',
                                            initialLatitude: initialLat,
                                            initialLongitude: initialLng,
                                            initialLocationName: initialName,
                                          );
                                          if (result != null) {
                                            setState(() {
                                              // Store raw value with coordinates for later use
                                              _rawLocationValue = result.toDisplayString();
                                              // Display stripped version (name only, no coordinates)
                                              _locationController.text = MapLocationResult.stripCoordinates(result.toDisplayString());
                                              _isDirty = true;
                                            });
                                          }
                                        },
                                      ),
                                      // Clear button (only show if there's a value)
                                      if (_locationController.text.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.clear, color: Colors.grey),
                                          tooltip: 'נקה מיקום',
                                          onPressed: () {
                                            setState(() {
                                              _rawLocationValue = null;
                                              _locationController.clear();
                                              _isDirty = true;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'נא למלא מיקום';
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Parking Location field
                              TextFormField(
                                controller: _parkingLocationController,
                                textDirection: TextDirection.rtl,
                                decoration: InputDecoration(
                                  labelText: 'מיקום חנייה',
                                  hintText: 'לדוגמה: חניון יקב',
                                  prefixIcon: const Icon(Icons.local_parking, color: Colors.purple),
                                  border: const OutlineInputBorder(),
                                  // Parking picker button and clear button
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Parking picker button
                                      IconButton(
                                        icon: const Icon(Icons.map, color: Colors.blue),
                                        tooltip: 'בחר מיקום חנייה במפה',
                                        onPressed: () async {
                                          final result = await ParkingLocationPickerDialog.show(
                                            context,
                                            eventLocation: _rawLocationValue ?? _locationController.text,
                                            initialParkingLocation: _rawParkingLocationValue,
                                            initialEditorIds: _parkingEditorIds,
                                            isAdmin: true, // Admin can edit team members
                                          );

                                          if (result != null) {
                                            // Convert empty string to null (user clicked "Clear")
                                            final parkingLocation = result.parkingLocation.isEmpty ? null : result.parkingLocation;
                                            setState(() {
                                              _rawParkingLocationValue = parkingLocation;
                                              _parkingLocationController.text = parkingLocation != null
                                                  ? MapLocationResult.stripCoordinates(parkingLocation)
                                                  : '';
                                              _parkingEditorIds = result.editorIds;
                                              _isDirty = true;
                                            });
                                          }
                                        },
                                      ),
                                      // Clear button (only show if there's a value)
                                      if (_parkingLocationController.text.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.clear, color: Colors.grey),
                                          tooltip: 'נקה מיקום חנייה',
                                          onPressed: () {
                                            setState(() {
                                              _rawParkingLocationValue = null;
                                              _parkingLocationController.clear();
                                              _parkingEditorIds = const [];
                                              _isDirty = true;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Date Selection (Dual Calendar)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                            final result = await showDialog<Map<String, DateTime?>>(
                                              context: context,
                                              builder: (context) => DualCalendarDatePicker(
                                                isSingleDate: false,
                                                initialStartDate: _startDate,
                                                initialEndDate: _endDate,
                                                title: 'בחר תאריכי אירוע',
                                              ),
                                            );

                                            if (result != null) {
                                              final selectedStartDate = result['startDate'];
                                              final selectedEndDate = result['endDate'];

                                              // Check if only start date was selected
                                              if (selectedStartDate != null && selectedEndDate == null) {
                                                // Show confirmation dialog for single-day event
                                                final confirmed = await showDialog<bool>(
                                                  context: context,
                                                  builder: (dialogContext) => Directionality(
                                                    textDirection: TextDirection.rtl,
                                                    child: AlertDialog(
                                                      title: const Text('אישור אירוע ליום בודד'),
                                                      content: Text(
                                                        'האם זה אירוע ליום בודד (${_formatDate(selectedStartDate!)})?',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          child: const Text('ביטול'),
                                                          onPressed: () => Navigator.of(dialogContext).pop(false),
                                                        ),
                                                        ElevatedButton(
                                                          child: const Text('כן, אירוע ליום בודד'),
                                                          onPressed: () => Navigator.of(dialogContext).pop(true),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );

                                                if (confirmed == true) {
                                                  setState(() {
                                                    _startDate = selectedStartDate;
                                                    _endDate = selectedStartDate; // For single day event
                                                    _dateError = null;
                                                    _isDirty = true;
                                                  });
                                                }
                                              } else if (selectedStartDate != null && selectedEndDate != null) {
                                                // Check if start and end dates are the same
                                                final isSameDate = selectedStartDate.year == selectedEndDate.year &&
                                                    selectedStartDate.month == selectedEndDate.month &&
                                                    selectedStartDate.day == selectedEndDate.day;

                                                if (isSameDate) {
                                                  // Show confirmation dialog for single-day event
                                                  final confirmed = await showDialog<bool>(
                                                    context: context,
                                                    builder: (dialogContext) => Directionality(
                                                      textDirection: TextDirection.rtl,
                                                      child: AlertDialog(
                                                        title: const Text('אישור אירוע ליום בודד'),
                                                        content: Text(
                                                          'האם זה אירוע ליום בודד (${_formatDate(selectedStartDate)})?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            child: const Text('ביטול'),
                                                            onPressed: () => Navigator.of(dialogContext).pop(false),
                                                          ),
                                                          ElevatedButton(
                                                            child: const Text('כן, אירוע ליום בודד'),
                                                            onPressed: () => Navigator.of(dialogContext).pop(true),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );

                                                  if (confirmed == true) {
                                                    setState(() {
                                                      _startDate = selectedStartDate;
                                                      _endDate = selectedStartDate; // For single day event
                                                      _dateError = null;
                                                      _isDirty = true;
                                                    });
                                                  }
                                                } else {
                                                  // Multi-day event
                                                  setState(() {
                                                    _startDate = selectedStartDate;
                                                    _endDate = selectedEndDate;
                                                    _dateError = null;
                                                    _isDirty = true;
                                                  });
                                                }
                                              }
                                            }
                                          },
                                          icon: const Icon(Icons.calendar_month),
                                          label: Text(
                                            _startDate == null
                                                ? 'בחר תאריכי אירוע'
                                                : (_endDate != null && _isSameDay(_startDate!, _endDate!))
                                                    ? _formatDate(_startDate!)
                                                    : _endDate == null
                                                        ? 'מ-${_formatDate(_startDate!)}'
                                                        : '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.all(16),
                                            alignment: Alignment.centerRight,
                                            side: BorderSide(
                                              color: _dateError != null ? Colors.red.shade700 : Colors.grey,
                                              width: _dateError != null ? 2 : 1,
                                            ),
                                            backgroundColor: _dateError != null ? Colors.red.shade50 : null,
                                          ),
                                        ),
                                      ),
                                      // Clear button (only show if dates are selected)
                                      if (_startDate != null)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: IconButton(
                                            onPressed: () => setState(() {
                                              _startDate = null;
                                              _endDate = null;
                                              _isDirty = true;
                                            }),
                                            icon: const Icon(Icons.clear, color: Colors.red),
                                            tooltip: 'נקה תאריכים',
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (widget.isDuplication && _startDate == null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 16, top: 4, bottom: 8),
                                      child: Text(
                                        _dateError ?? '↑ יש לבחור תאריכים חדשים לאירוע המשוכפל ↑',
                                        style: TextStyle(
                                          color: _dateError != null ? Colors.red.shade700 : Colors.green,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (!widget.isDuplication && _dateError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 16, top: 4, bottom: 8),
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

                              // Start Time (Audience Gathering Time)
                              TextFormField(
                                controller: _startTimeController,
                                decoration: const InputDecoration(
                                  labelText: 'שעת התכנסות קהל (אופציונלי)',
                                  hintText: 'לדוגמה: 18:00',
                                  prefixIcon: Icon(Icons.access_time),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // End Time
                              TextFormField(
                                controller: _endTimeController,
                                decoration: const InputDecoration(
                                  labelText: 'שעת סיום (אופציונלי)',
                                  hintText: 'לדוגמה: 23:00',
                                  prefixIcon: Icon(Icons.access_time),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Assembly Time
                              TextFormField(
                                controller: _assemblyTimeController,
                                decoration: const InputDecoration(
                                  labelText: 'שעת התייצבות (אופציונלי)',
                                  hintText: 'לדוגמה: 17:00',
                                  prefixIcon: Icon(Icons.access_time),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Actual Show Start Time
                              TextFormField(
                                controller: _actualShowStartTimeController,
                                decoration: const InputDecoration(
                                  labelText: 'שעת תחילת המופע בפועל (אופציונלי)',
                                  hintText: 'לדוגמה: 19:00',
                                  prefixIcon: Icon(Icons.play_circle_outline),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              const SizedBox(height: 16),

                              // Requires Armed
                              SwitchListTile(
                                title: const Text('דרוש חמוש'),
                                value: _requiresArmed,
                                onChanged: (v) => setState(() {
                                  _requiresArmed = v;
                                  _isDirty = true;
                                }),
                              ),

                              // Duplicate Assignments (only show in duplication mode)
                              if (widget.isDuplication) ...[
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  title: const Text('שכפל גם את השיבוצים'),
                                  subtitle: Text(
                                    _duplicateAssignments
                                      ? 'כל השיבוצים יועברו לאירוע החדש (בהתחשב בזמינות)'
                                      : 'רק פרטי האירוע ישוכפלו, ללא שיבוצים',
                                  ),
                                  value: _duplicateAssignments,
                                  onChanged: (v) => setState(() {
                                    _duplicateAssignments = v;
                                    _isDirty = true;
                                  }),
                                ),
                                const SizedBox(height: 8),
                              ],

                              const Divider(height: 32),

                              // Role Requirements
                              const Text(
                                'תפקידים נדרשים',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              BlocBuilder<RoleBloc, RoleState>(
                                builder: (context, roleState) {
                                  // Handle different states
                                  if (roleState is! RolesLoaded) {
                                    // Show loading or fallback to RoleType.values during initial load
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: RoleType.values.map((role) {
                                        final isHighlighted = _highlightedRole == role;
                                        return AnimatedContainer(
                                          key: _roleKeys[role],
                                          duration: const Duration(milliseconds: 500),
                                          decoration: BoxDecoration(
                                            color: isHighlighted
                                                ? Colors.blue.shade100.withValues(alpha: _highlightOpacity)
                                                : null,
                                            borderRadius: BorderRadius.circular(8),
                                            border: isHighlighted
                                                ? Border.all(
                                                    color: Colors.blue.shade700.withValues(alpha: _highlightOpacity),
                                                    width: 2,
                                                  )
                                                : null,
                                          ),
                                          child: ListTile(
                                            title: Text(
                                              role.hebrewName,
                                              style: TextStyle(
                                                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                                                color: isHighlighted ? Colors.blue.shade900 : null,
                                              ),
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove_circle_outline),
                                                  onPressed: () {
                                                    if ((_roleRequirements[role.key] ?? 0) > 0) {
                                                      setState(() {
                                                        _roleRequirements[role.key] = (_roleRequirements[role.key] ?? 0) - 1;
                                                        _isDirty = true;
                                                      });
                                                    }
                                                  },
                                                ),
                                                SizedBox(
                                                  width: 40,
                                                  child: Text(
                                                    (_roleRequirements[role.key] ?? 0).toString(),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add_circle_outline),
                                                  onPressed: () {
                                                    setState(() {
                                                      _roleRequirements[role.key] = (_roleRequirements[role.key] ?? 0) + 1;
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
                                  final roles = (roleState as RolesLoaded).visibleRoles;

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: roles.map((roleObj) {
                                      // Use role key (String) directly as the map key
                                      final roleKey = roleObj.key;

                                      // Map role.key to RoleType enum for highlighting (legacy support)
                                      final RoleType? roleType = _tryParseRoleType(roleKey);
                                      final isHighlighted = roleType != null && _highlightedRole == roleType;

                                      return AnimatedContainer(
                                        key: roleType != null ? _roleKeys[roleType] : null,
                                        duration: const Duration(milliseconds: 500),
                                        decoration: BoxDecoration(
                                          color: isHighlighted
                                              ? Colors.blue.shade100.withValues(alpha: _highlightOpacity)
                                              : null,
                                          borderRadius: BorderRadius.circular(8),
                                          border: isHighlighted
                                              ? Border.all(
                                                  color: Colors.blue.shade700.withValues(alpha: _highlightOpacity),
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                        child: ListTile(
                                          title: Text(
                                            roleObj.hebrewName,
                                            style: TextStyle(
                                              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                                              color: isHighlighted ? Colors.blue.shade900 : null,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline),
                                                onPressed: () {
                                                  if (_roleRequirements[roleKey]! > 0) {
                                                    setState(() {
                                                      _roleRequirements[roleKey] = _roleRequirements[roleKey]! - 1;
                                                      _isDirty = true;
                                                    });
                                                  }
                                                },
                                              ),
                                              SizedBox(
                                                width: 40,
                                                child: Text(
                                                  (_roleRequirements[roleKey] ?? 0).toString(),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.add_circle_outline),
                                                onPressed: () {
                                                  setState(() {
                                                    _roleRequirements[roleKey] = (_roleRequirements[roleKey] ?? 0) + 1;
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

                              // Drive Files Section (only in edit mode, not duplication)
                              // Show immediately even if drive folder doesn't exist yet - section handles pending state
                              if (_isEditMode && !widget.isDuplication) ...[
                                  EventDriveFilesSection(
                                    eventId: widget.event!.id,
                                    driveFolderId: widget.event?.driveFolderId,
                                    driveFolderLink: widget.event?.driveFolderLink,
                                    eventName: widget.event!.name,
                                  ),
                                  const Divider(height: 32),
                                ],

                              // Comments
                              TextFormField(
                                controller: _commentsController,
                                decoration: const InputDecoration(
                                  labelText: 'הערות',
                                  hintText: 'הערות על האירוע',
                                  prefixIcon: Icon(Icons.comment),
                                  border: OutlineInputBorder(),
                                ),
                                minLines: 1,
                                maxLines: 3,
                                scrollPadding: const EdgeInsets.only(bottom: 300),
                                onChanged: (_) => setState(() => _isDirty = true),
                              ),

                              // Dynamic bottom spacing for keyboard
                              SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
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
                            onPressed: _handleClose,
                            child: const Text('ביטול'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveEvent,
                            child: Text(widget.isDuplication ? 'שכפל אירוע' : 'שמור'),
                          ),
                        ),
                      ],
                    ),
                  ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }, // Close DraggableScrollableSheet builder
      ); // Close DraggableScrollableSheet
  }

  
  void _showDuplicationModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => EventFormModal(
        event: widget.event,
        isDuplication: true,
        filterIndex: widget.filterIndex,
        onSuccess: () {
          Navigator.of(modalContext).pop(); // Close the duplication modal
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
