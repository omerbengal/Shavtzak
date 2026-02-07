import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/utils/rtl_text_field_utils.dart';

// Conditional imports for web-specific geolocation API
import 'web/geolocation_stub.dart'
    if (dart.library.js) 'web/geolocation_web.dart';

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

  /// Format as a string for display and storage
  /// - If location has a name (from search): "Name||lat,lng" (coordinates hidden after ||)
  /// - If manually tapped (no name): "lat, lng"
  /// Use stripCoordinates() to get display-only version
  String toDisplayString() {
    if (locationName != null) {
      // Store coordinates after || separator for later parsing
      return '$locationName||${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
    }
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  /// Get the display-friendly version (strips hidden coordinates)
  static String stripCoordinates(String location) {
    final separatorIndex = location.indexOf('||');
    if (separatorIndex != -1) {
      return location.substring(0, separatorIndex);
    }
    return location;
  }

  /// Get coordinates as a string
  String toCoordinatesString() {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  /// Parse a location string to extract coordinates
  /// Handles: "Name||lat,lng", "Name (lat, lng)", and "lat, lng" formats
  static (double?, double?) parseCoordinates(String location) {
    // Try to extract coordinates after || separator: "Name||lat,lng"
    final separatorIndex = location.indexOf('||');
    if (separatorIndex != -1) {
      final coordsPart = location.substring(separatorIndex + 2);
      final parts = coordsPart.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          return (lat, lng);
        }
      }
    }

    // Try to extract coordinates from parentheses: "Name (lat, lng)"
    final parenMatch = RegExp(r'\(([^)]+)\)$').firstMatch(location);
    String coordsPart;

    if (parenMatch != null) {
      coordsPart = parenMatch.group(1)!;
    } else {
      coordsPart = location;
    }

    final parts = coordsPart.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) {
        return (lat, lng);
      }
    }
    return (null, null);
  }
}

/// A search result from Nominatim geocoding
class _SearchResult {
  final String displayName;
  final String formattedName; // Our custom formatted name
  final double latitude;
  final double longitude;

  const _SearchResult({
    required this.displayName,
    required this.formattedName,
    required this.latitude,
    required this.longitude,
  });

  /// Create a search result from Nominatim JSON response
  /// Uses addressdetails for structured address fields
  factory _SearchResult.fromJson(Map<String, dynamic> json) {
    final lat = double.parse(json['lat'] as String);
    final lng = double.parse(json['lon'] as String);
    final displayName = json['display_name'] as String;

    // Extract structured address fields
    final address = json['address'] as Map<String, dynamic>?;
    String formattedName = displayName;

    if (address != null) {
      final parts = <String>[];

      // 1. Place name (amenity, building, tourism, etc.) - if it's a named place
      final name = address['amenity'] ??
          address['building'] ??
          address['tourism'] ??
          address['shop'] ??
          address['leisure'] ??
          address['office'] ??
          address['historic'];
      if (name != null) {
        parts.add(name as String);
      }

      // 2. Street with house number
      final road = address['road'] ?? address['street'];
      final houseNumber = address['house_number'];
      if (road != null) {
        if (houseNumber != null) {
          parts.add('$road $houseNumber');
        } else {
          parts.add(road as String);
        }
      }

      // 3. City (try multiple fields)
      final city = address['city'] ??
          address['town'] ??
          address['village'] ??
          address['municipality'];
      if (city != null) {
        parts.add(city as String);
      }

      if (parts.isNotEmpty) {
        formattedName = parts.join(', ');
      }
    }

    return _SearchResult(
      displayName: displayName,
      formattedName: formattedName,
      latitude: lat,
      longitude: lng,
    );
  }
}

/// A dialog that displays an interactive map for picking a location.
/// Uses OpenStreetMap tiles (free, no API key required).
class MapLocationPicker extends StatefulWidget {
  /// Initial latitude (defaults to Tel Aviv)
  final double? initialLatitude;

  /// Initial longitude (defaults to Tel Aviv)
  final double? initialLongitude;

  /// Initial location name (to display when re-opening with existing location)
  final String? initialLocationName;

  /// Initial zoom level
  final double initialZoom;

  /// Title for the dialog
  final String title;

  const MapLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialLocationName,
    this.initialZoom = 13.0,
    this.title = 'בחר מיקום',
  });

  /// Show the map picker as a dialog and return the selected location
  static Future<MapLocationResult?> show(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
    String? initialLocationName,
    double initialZoom = 13.0,
    String title = 'בחר מיקום',
  }) {
    return showDialog<MapLocationResult>(
      context: context,
      builder: (context) => MapLocationPicker(
        initialLatitude: initialLatitude,
        initialLongitude: initialLongitude,
        initialLocationName: initialLocationName,
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

  // Current location functionality
  bool _isGettingLocation = false;
  String? _locationError;

  // Default to Tel Aviv if no initial location provided
  static const _defaultLatitude = 32.0853;
  static const _defaultLongitude = 34.7818;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    addRtlCursorFix(_searchFocusNode, _searchController);
    _initialCenter = LatLng(
      widget.initialLatitude ?? _defaultLatitude,
      widget.initialLongitude ?? _defaultLongitude,
    );
    // If initial location was provided, set it as selected
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = _initialCenter;
      _selectedLocationName = widget.initialLocationName;
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
      // addressdetails=1 returns structured address fields (road, city, etc.)
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&limit=5'
        '&countrycodes=il'
        '&accept-language=he'
        '&addressdetails=1',
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
          _searchResults = data
              .map((item) => _SearchResult.fromJson(item as Map<String, dynamic>))
              .toList();
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
      _selectedLocationName = result.formattedName;
      _searchResults = [];
      _locationError = null; // Clear any previous errors
      // Keep search text so admin can see what they searched for
    });
    _searchFocusNode.unfocus();
    _mapController.move(location, 16.0); // Zoom in to selected location
  }

  /// Get current user location using browser geolocation API (web only)
  Future<void> _getCurrentLocation() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('אפשרות המיקום הנוכחי זמינה רק בגרסת האינטרנט'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isGettingLocation = true;
      _locationError = null;
    });

    try {
      // Get current position using the browser's geolocation API
      final result = await GeolocationService.getCurrentPosition();
      final location = LatLng(
        result['latitude'] as double,
        result['longitude'] as double,
      );

      setState(() {
        _selectedLocation = location;
        _selectedLocationName = null; // No name for current location - coordinates only
        _searchResults = [];
        _isGettingLocation = false;
      });

      // Move map to current location
      _mapController.move(location, 15.0);

      // Clear any search text when using current location
      _searchController.clear();
      _searchFocusNode.unfocus();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('המיקום הנוכחי זוהה בהצלחה'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isGettingLocation = false;
        _locationError = _getGeolocationErrorMessage(e);
      });

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_locationError!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'הסבר',
              textColor: Colors.white,
              onPressed: () {
                _showLocationPermissionDialog();
              },
            ),
          ),
        );
      }
    }
  }

  /// Get user-friendly error message for geolocation errors
  String _getGeolocationErrorMessage(dynamic error) {
    // Handle common geolocation error codes
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('permission denied') || errorString.contains('user denied')) {
      return 'הגישה למיקום נדחתה. אנא אפשר גישה למיקום בהגדרות הדפדפן.';
    } else if (errorString.contains('position unavailable')) {
      return 'לא ניתן לקבוע את המיקום הנוכחי. אנא נסה שוב מאוחר יותר.';
    } else if (errorString.contains('timeout')) {
      return 'פג תום הזמן לקבלת המיקום. אנא נסה שוב.';
    } else {
      return 'לא הצלחתי לקבל את המיקום הנוכחי. אנא ודא שהרשאת המיקום מופעלת.';
    }
  }

  /// Show dialog with instructions for enabling location permissions
  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הפעלת הרשאות מיקום'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('כדי להשתמש במיקום הנוכחי, יש להפעיל את הרשאות המיקום:'),
              SizedBox(height: 16),
              Text('ב-Chrome:'),
              Text('1. לחץ על סמל המנעול בשורת הכתובת'),
              Text('2. בסעיף "מיקום", בחר "אפשר"'),
              SizedBox(height: 16),
              Text('ב-Safari:'),
              Text('1. לחץ על סמל ההגדרות'),
              Text('2. בחר "אתר" > "מיקום"'),
              Text('3. בחר "בעת הביקור"'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('הבנתי'),
            ),
          ],
        ),
      ),
    );
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
                            Row(
                              children: [
                                // Search field
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
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
                                ),
                                const SizedBox(width: 8),
                                // Current location button
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    onPressed: _isGettingLocation ? null : _getCurrentLocation,
                                    icon: _isGettingLocation
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.my_location),
                                    tooltip: 'המיקום הנוכחי שלי',
                                  ),
                                ),
                              ],
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
                                      color: Colors.black.withValues(alpha: 0.15),
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
                                                result.formattedName,
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
                              color: Colors.green.shade50.withValues(alpha: 0.95),
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
                              color: Colors.blue.shade50.withValues(alpha: 0.95),
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
