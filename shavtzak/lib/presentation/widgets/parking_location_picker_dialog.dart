import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_state.dart';
import '../../domain/entities/team_member.dart';
import 'map_location_picker.dart';

/// Result from parking location picker dialog
class ParkingLocationResult {
  final String parkingLocation;
  final List<String> editorIds;

  const ParkingLocationResult({
    required this.parkingLocation,
    required this.editorIds,
  });
}

/// Dialog for editing parking location and editors
class ParkingLocationPickerDialog extends StatefulWidget {
  final String eventLocation;
  final String? initialParkingLocation;
  final List<String> initialEditorIds;
  final bool isAdmin; // Whether the current user is an admin

  const ParkingLocationPickerDialog({
    super.key,
    required this.eventLocation,
    this.initialParkingLocation,
    this.initialEditorIds = const [],
    this.isAdmin = false,
  });

  static Future<ParkingLocationResult?> show(
    BuildContext context, {
    required String eventLocation,
    String? initialParkingLocation,
    List<String> initialEditorIds = const [],
    bool isAdmin = false,
  }) {
    return showDialog<ParkingLocationResult>(
      context: context,
      builder: (context) => ParkingLocationPickerDialog(
        eventLocation: eventLocation,
        initialParkingLocation: initialParkingLocation,
        initialEditorIds: initialEditorIds,
        isAdmin: isAdmin,
      ),
    );
  }

  @override
  State<ParkingLocationPickerDialog> createState() => _ParkingLocationPickerDialogState();
}

class _ParkingLocationPickerDialogState extends State<ParkingLocationPickerDialog> {
  String? _selectedParkingLocation;
  final List<String> _selectedEditorIds = [];
  final _editorSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedParkingLocation = widget.initialParkingLocation;
    _selectedEditorIds.addAll(widget.initialEditorIds);
  }

  @override
  void dispose() {
    _editorSearchController.dispose();
    super.dispose();
  }

  Future<void> _openMapPicker() async {
    // Parse existing coordinates if available
    double? initialLat;
    double? initialLng;
    String? initialName;

    if (_selectedParkingLocation != null && _selectedParkingLocation!.isNotEmpty) {
      final strippedName = MapLocationResult.stripCoordinates(_selectedParkingLocation!);
      final (lat, lng) = MapLocationResult.parseCoordinates(_selectedParkingLocation!);
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
    Navigator.of(context).pop(ParkingLocationResult(
      parkingLocation: '',
      editorIds: List.from(_selectedEditorIds),
    ));
  }

  void _save() {
    Navigator.of(context).pop(ParkingLocationResult(
      parkingLocation: _selectedParkingLocation ?? '',
      editorIds: List.from(_selectedEditorIds),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('עריכת מיקום חנייה'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Current parking location display
              if (_selectedParkingLocation != null && _selectedParkingLocation!.isNotEmpty)
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
                          MapLocationResult.stripCoordinates(_selectedParkingLocation!),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_selectedParkingLocation != null && _selectedParkingLocation!.isNotEmpty)
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
                label: const Text('מיקום האירוע'),
              ),

              // Clear button (show if there's currently a selected parking location)
              if (_selectedParkingLocation != null && _selectedParkingLocation!.isNotEmpty) ...[
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

              const SizedBox(height: 24),

              // Team member selector (only for admins)
              if (widget.isAdmin) ...[
                const Text(
                  'עורכים מורשים',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),

                BlocBuilder<TeamBloc, TeamState>(
                  builder: (context, state) {
                    if (state is TeamLoaded) {
                      final teamMembers = state.members.where((m) => m.isActive).toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Search bar
                          TextField(
                            controller: _editorSearchController,
                            textAlign: TextAlign.right,
                            textDirection: TextDirection.rtl,
                            decoration: const InputDecoration(
                              labelText: 'חיפוש חבר צוות...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),

                          const SizedBox(height: 12),

                          // Filter chips
                          Wrap(
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
                              final isSelected = _selectedEditorIds.contains(member.id);
                              return FilterChip(
                                label: Text(member.name),
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
                        ],
                      );
                    }

                    return const Center(child: CircularProgressIndicator());
                  },
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
