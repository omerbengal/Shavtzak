import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/team_member.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_state.dart';
import 'map_location_picker.dart';
import '../../core/utils/rtl_text_field_utils.dart';

/// Result from parking location picker dialog
class ParkingLocationResult {
  final String parkingLocation;

  const ParkingLocationResult({
    required this.parkingLocation,
  });
}

/// Dialog for editing parking location (map picker only)
class ParkingLocationPickerDialog extends StatefulWidget {
  final String eventLocation;
  final String? initialParkingLocation;

  const ParkingLocationPickerDialog({
    super.key,
    required this.eventLocation,
    this.initialParkingLocation,
  });

  static Future<ParkingLocationResult?> show(
    BuildContext context, {
    required String eventLocation,
    String? initialParkingLocation,
  }) {
    return showDialog<ParkingLocationResult>(
      context: context,
      builder: (context) => ParkingLocationPickerDialog(
        eventLocation: eventLocation,
        initialParkingLocation: initialParkingLocation,
      ),
    );
  }

  @override
  State<ParkingLocationPickerDialog> createState() =>
      _ParkingLocationPickerDialogState();
}

class _ParkingLocationPickerDialogState
    extends State<ParkingLocationPickerDialog> {
  String? _selectedParkingLocation;

  @override
  void initState() {
    super.initState();
    _selectedParkingLocation = widget.initialParkingLocation;
  }

  Future<void> _openMapPicker() async {
    // Parse existing coordinates if available
    double? initialLat;
    double? initialLng;
    String? initialName;

    if (_selectedParkingLocation != null &&
        _selectedParkingLocation!.isNotEmpty) {
      final strippedName =
          MapLocationResult.stripCoordinates(_selectedParkingLocation!);
      final (lat, lng) =
          MapLocationResult.parseCoordinates(_selectedParkingLocation!);
      initialLat = lat;
      initialLng = lng;
      initialName = strippedName;
    }

    final result = await MapLocationPicker.show(
      context,
      title: 'בחר מיקום חנייה',
      initialLatitude: initialLat,
      initialLongitude: initialLng,
      initialLocationName: initialName,
    );

    if (result != null) {
      setState(() {
        _selectedParkingLocation = result.toDisplayString();
      });
    }
  }

  void _copyEventLocation() {
    setState(() {
      _selectedParkingLocation = widget.eventLocation;
    });
  }

  void _clear() {
    // Just clear the local state, don't close the dialog
    setState(() {
      _selectedParkingLocation = '';
    });
  }

  void _save() {
    Navigator.of(context).pop(ParkingLocationResult(
      parkingLocation: _selectedParkingLocation ?? '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('עריכת מיקום חנייה'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Current parking location display
              if (_selectedParkingLocation != null &&
                  _selectedParkingLocation!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_parking, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          MapLocationResult.stripCoordinates(
                              _selectedParkingLocation!),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_selectedParkingLocation != null &&
                  _selectedParkingLocation!.isNotEmpty)
                const SizedBox(height: 16),

              // Map picker button
              ElevatedButton.icon(
                onPressed: _openMapPicker,
                icon: const Icon(Icons.map),
                label: const Text('בחר במפה'),
              ),

              const SizedBox(height: 8),

              // Copy event location button
              OutlinedButton.icon(
                onPressed: _copyEventLocation,
                icon: const Icon(Icons.content_copy),
                label: const Text('העתק מיקום אירוע'),
              ),

              // Clear button (show if there's currently a selected parking location)
              if (_selectedParkingLocation != null &&
                  _selectedParkingLocation!.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text(
                    'נקה',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _save,
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }
}

/// Dialog for selecting parking editors (team members who can edit parking location)
class ParkingEditorsDialog extends StatefulWidget {
  final List<String> initialEditorIds;

  const ParkingEditorsDialog({
    super.key,
    this.initialEditorIds = const [],
  });

  static Future<List<String>?> show(
    BuildContext context, {
    List<String> initialEditorIds = const [],
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (context) => ParkingEditorsDialog(
        initialEditorIds: initialEditorIds,
      ),
    );
  }

  @override
  State<ParkingEditorsDialog> createState() => _ParkingEditorsDialogState();
}

class _ParkingEditorsDialogState extends State<ParkingEditorsDialog> {
  final List<String> _selectedEditorIds = [];
  final _editorSearchController = TextEditingController();
  late final FocusNode _editorSearchFocusNode;

  Widget _buildMemberChipLabel(TeamMember member) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(member.name),
        ),
        if (member.isPermanent) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.verified_user,
            size: 14,
            color: Colors.blue.shade700,
          ),
        ],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _editorSearchFocusNode =
        createRtlCursorFixedFocusNode(_editorSearchController);
    _selectedEditorIds.addAll(widget.initialEditorIds);
  }

  @override
  void dispose() {
    _editorSearchFocusNode.dispose();
    _editorSearchController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(List<String>.from(_selectedEditorIds));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('עורכים מורשים למיקום חנייה'),
        content: SizedBox(
          width: 400,
          child: BlocBuilder<TeamBloc, TeamState>(
            builder: (context, state) {
              if (state is TeamLoaded) {
                final teamMembers =
                    state.members.where((m) => m.isActive).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Explanation text
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'בחר את חברי הצוות שיוכלו לערוך את מיקום החנייה של האירוע',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Search bar
                    TextField(
                      controller: _editorSearchController,
                      focusNode: _editorSearchFocusNode,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'חיפוש חבר צוות...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 12),

                    // Selected count
                    if (_selectedEditorIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'נבחרו: ${_selectedEditorIds.length}',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    // Filter chips in a scrollable container
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: teamMembers.where((member) {
                            if (_editorSearchController.text.isNotEmpty) {
                              return member.name.toLowerCase().contains(
                                    _editorSearchController.text.toLowerCase(),
                                  );
                            }
                            return true;
                          }).map((member) {
                            final isSelected =
                                _selectedEditorIds.contains(member.id);
                            return FilterChip(
                              label: _buildMemberChipLabel(member),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedEditorIds.add(member.id);
                                  } else {
                                    _selectedEditorIds.remove(member.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _save,
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }
}
