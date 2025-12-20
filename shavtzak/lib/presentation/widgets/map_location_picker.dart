import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Result from the map location picker containing latitude, longitude, and optional name
class MapLocationResult {
  final double latitude;
  final double longitude;
  final String? locationName; // Name from search, null if manually tapped

  const MapLocationResult({
    required this.latitude,
    required this.longitude,
    this.locationName,
  });

  /// Format as a string for display
  /// Returns location name if available, otherwise coordinates
  String toDisplayString() {
    return locationName ?? '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  /// Get coordinates as a string
  String toCoordinatesString() {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }
}

/// A search result from Nominatim geocoding
class _SearchResult {
  final String displayName;
  final double latitude;
  final double longitude;

  const _SearchResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
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
  String? _selectedLocationName; // Name of the selected location (from search)
  late LatLng _initialCenter;

  // Search functionality
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<_SearchResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

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
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
      _selectedLocationName = null; // Clear name when tapping manually
      _searchResults = []; // Clear search results when tapping map
    });
  }

  /// Format the display name from Nominatim to be more readable
  /// Nominatim format: "Name, Number, Street, Neighborhood, City, District, Country"
  /// We want: "Name, Street Number, City" or "Street Number, City"
  String _formatDisplayName(String displayName) {
    final parts = displayName.split(',').map((p) => p.trim()).toList();

    if (parts.isEmpty) return displayName;
    if (parts.length == 1) return parts[0];

    final result = <String>[];

    // Check if first part is a place name (not just a number)
    final firstPart = parts[0];
    final isFirstPartNumber = RegExp(r'^\d+$').hasMatch(firstPart);

    String? placeName;
    String? streetWithNumber;
    String? city;

    int startIndex = 0;

    // If first part is not a number, it's likely a place name
    if (!isFirstPartNumber) {
      // Check if it looks like a street name (contains common street words)
      final streetKeywords = ['רחוב', 'שדרות', 'דרך', 'סמטת', 'משעול', 'כיכר'];
      final isStreet = streetKeywords.any((keyword) => firstPart.contains(keyword));

      if (!isStreet) {
        placeName = firstPart;
        startIndex = 1;
      }
    }

    // Find street with number
    // Look for a number followed by street name, or street name followed by number
    for (int i = startIndex; i < parts.length && i < startIndex + 3; i++) {
      final part = parts[i];
      final hasNumber = RegExp(r'\d').hasMatch(part);
      final isJustNumber = RegExp(r'^\d+$').hasMatch(part);

      if (isJustNumber && i + 1 < parts.length) {
        // Number followed by street name: "123, Dizengoff Street"
        streetWithNumber = '${parts[i + 1]} $part';
        startIndex = i + 2;
        break;
      } else if (hasNumber) {
        // Street with number included: "Dizengoff Street 123"
        streetWithNumber = part;
        startIndex = i + 1;
        break;
      }
    }

    // If no street with number found, take the first available part as street
    if (streetWithNumber == null && startIndex < parts.length) {
      streetWithNumber = parts[startIndex];
      startIndex++;
    }

    // Find city - skip neighborhoods/districts, look for a city-like part
    // Cities in Israel usually don't have "רחוב", numbers, or "נפת"
    for (int i = startIndex; i < parts.length; i++) {
      final part = parts[i];
      // Skip if it's a district, country, or has street indicators
      if (part.contains('נפת') ||
          part.contains('מחוז') ||
          part.contains('ישראל') ||
          part.contains('Israel')) {
        continue;
      }
      city = part;
      break;
    }

    // Build result
    if (placeName != null) result.add(placeName);
    if (streetWithNumber != null) result.add(streetWithNumber);
    if (city != null) result.add(city);

    return result.isNotEmpty ? result.join(', ') : displayName;
  }

  void _confirmSelection() {
    if (_selectedLocation != null) {
      Navigator.of(context).pop(MapLocationResult(
        latitude: _selectedLocation!.latitude,
        longitude: _selectedLocation!.longitude,
        locationName: _selectedLocationName,
      ));
    }
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  /// Search for locations using Nominatim (OpenStreetMap geocoding)
  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Use Nominatim API (free, no API key required)
      // Adding countrycodes=il to prioritize Israel results
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&limit=5'
        '&countrycodes=il'
        '&accept-language=he',
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Shavtzak App (contact@shavtzak.com)',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _searchResults = data.map((item) {
            return _SearchResult(
              displayName: item['display_name'] as String,
              latitude: double.parse(item['lat'] as String),
              longitude: double.parse(item['lon'] as String),
            );
          }).toList();
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  /// Handle search input with debouncing
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchLocation(query);
    });
  }

  /// Select a search result
  void _selectSearchResult(_SearchResult result) {
    final location = LatLng(result.latitude, result.longitude);
    setState(() {
      _selectedLocation = location;
      _selectedLocationName = _formatDisplayName(result.displayName);
      _searchResults = [];
      _searchController.clear();
    });
    _searchFocusNode.unfocus();
    _mapController.move(location, 16.0); // Zoom in to selected location
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
                                  alignment: Alignment.topCenter,
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

                      // Search bar
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                textDirection: TextDirection.rtl,
                                decoration: InputDecoration(
                                  hintText: 'חיפוש מיקום...',
                                  prefixIcon: _isSearching
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.search),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchResults = [];
                                            });
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                onChanged: _onSearchChanged,
                              ),
                            ),
                            // Search results dropdown
                            if (_searchResults.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                constraints: const BoxConstraints(maxHeight: 200),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: _searchResults.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: Colors.grey.shade200,
                                  ),
                                  itemBuilder: (context, index) {
                                    final result = _searchResults[index];
                                    final formattedName = _formatDisplayName(result.displayName);
                                    return InkWell(
                                      onTap: () => _selectSearchResult(result),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              color: Colors.grey.shade600,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                formattedName,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 14),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Selected location display (when location selected and no search results)
                      if (_selectedLocation != null && _searchResults.isEmpty)
                        Positioned(
                          top: 60,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green.shade700,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    // Show location name if available, otherwise show coordinates
                                    _selectedLocationName ??
                                        '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Instruction text (when no location selected and no search)
                      if (_selectedLocation == null && _searchResults.isEmpty && !_isSearching)
                        Positioned(
                          top: 60,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: const Text(
                              'חפש מיקום או לחץ על המפה',
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
