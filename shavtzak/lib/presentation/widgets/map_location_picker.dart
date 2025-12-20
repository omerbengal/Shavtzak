import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Result from the map location picker containing latitude and longitude
class MapLocationResult {
  final double latitude;
  final double longitude;

  const MapLocationResult({
    required this.latitude,
    required this.longitude,
  });

  /// Format as a string for display
  String toDisplayString() {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }
}

/// A dialog that displays an interactive map for picking a location.
/// Uses OpenStreetMap tiles (free, no API key required).
class MapLocationPicker extends StatefulWidget {
  /// Initial latitude (defaults to Tel Aviv)
  final double? initialLatitude;

  /// Initial longitude (defaults to Tel Aviv)
  final double? initialLongitude;

  /// Initial zoom level
  final double initialZoom;

  /// Title for the dialog
  final String title;

  const MapLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialZoom = 13.0,
    this.title = 'בחר מיקום',
  });

  /// Show the map picker as a dialog and return the selected location
  static Future<MapLocationResult?> show(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
    double initialZoom = 13.0,
    String title = 'בחר מיקום',
  }) {
    return showDialog<MapLocationResult>(
      context: context,
      builder: (context) => MapLocationPicker(
        initialLatitude: initialLatitude,
        initialLongitude: initialLongitude,
        initialZoom: initialZoom,
        title: title,
      ),
    );
  }

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late MapController _mapController;
  LatLng? _selectedLocation;
  late LatLng _initialCenter;

  // Default to Tel Aviv if no initial location provided
  static const _defaultLatitude = 32.0853;
  static const _defaultLongitude = 34.7818;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initialCenter = LatLng(
      widget.initialLatitude ?? _defaultLatitude,
      widget.initialLongitude ?? _defaultLongitude,
    );
    // If initial location was provided, set it as selected
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = _initialCenter;
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
    });
  }

  void _confirmSelection() {
    if (_selectedLocation != null) {
      Navigator.of(context).pop(MapLocationResult(
        latitude: _selectedLocation!.latitude,
        longitude: _selectedLocation!.longitude,
      ));
    }
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width > 800 ? 700.0 : screenSize.width * 0.9;
    final dialogHeight = screenSize.height > 600 ? 500.0 : screenSize.height * 0.8;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Header
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
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _cancel,
                    ),
                  ],
                ),
              ),

              // Map
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _initialCenter,
                          initialZoom: widget.initialZoom,
                          onTap: _onMapTap,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.shavtzak.app',
                          ),
                          if (_selectedLocation != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _selectedLocation!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_pin,
                                    color: Colors.red,
                                    size: 40,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // Coordinates display
                      if (_selectedLocation != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              'נקודה נבחרה: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      // Instruction text
                      if (_selectedLocation == null)
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: const Text(
                              'לחץ על המפה לבחירת מיקום',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),

                      // Confirm button
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _cancel,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('ביטול'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _selectedLocation != null
                                    ? _confirmSelection
                                    : null,
                                icon: const Icon(Icons.check),
                                label: const Text('אישור'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
