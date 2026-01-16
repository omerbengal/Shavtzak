import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'environment_service.dart';

/// Service to fetch utility data from Firebase
/// Collection: utilities, Document: Lists
class UtilitiesService {
  static final UtilitiesService _instance = UtilitiesService._internal();
  factory UtilitiesService() => _instance;
  UtilitiesService._internal();

  static UtilitiesService get instance => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream controllers for real-time updates
  final BehaviorSubject<List<String>> _manufacturersSubject = BehaviorSubject.seeded([]);
  final BehaviorSubject<Map<String, List<String>>> _modelsSubject = BehaviorSubject.seeded({});

  // Stream subscriptions
  StreamSubscription? _listsDocSubscription;

  /// Get the collection name with environment prefix
  String get _collectionName => '${EnvironmentService.instance.collectionPrefix}utilities';

  /// Initialize the service and start listening for real-time updates
  void initialize() {
    _startListeningToLists();
  }

  /// Start listening to the Lists document for real-time updates
  void _startListeningToLists() {
    _listsDocSubscription?.cancel();
    _listsDocSubscription = _firestore
        .collection(_collectionName)
        .doc('Lists')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final manufacturers = List<String>.from(data['car_manufacturers'] as List? ?? []);
        final modelsMap = Map<String, dynamic>.from(data['car_models'] as Map? ?? {});

        // Sort manufacturers alphabetically in Hebrew
        manufacturers.sort((a, b) => a.compareTo(b));

        // Add manufacturers to stream
        _manufacturersSubject.add(manufacturers);

        // Process models - sort each manufacturer's models
        final sortedModels = <String, List<String>>{};
        for (final entry in modelsMap.entries) {
          final models = List<String>.from(entry.value as List? ?? []);
          models.sort((a, b) => a.compareTo(b));
          sortedModels[entry.key] = models;
        }
        _modelsSubject.add(sortedModels);
      } else {
        // Document doesn't exist, use defaults
        _manufacturersSubject.add(_getDefaultManufacturers());
        _modelsSubject.add({});
      }
    });
  }

  /// Watch car manufacturers as a stream for real-time updates
  Stream<List<String>> watchCarManufacturers() {
    // Ensure we're listening
    if (_listsDocSubscription == null) {
      initialize();
    }
    return _manufacturersSubject.stream;
  }

  /// Watch car models for a specific manufacturer as a stream
  Stream<List<String>> watchCarModels(String manufacturer) {
    // Ensure we're listening
    if (_listsDocSubscription == null) {
      initialize();
    }
    return _modelsSubject.stream.map((modelsMap) => modelsMap[manufacturer] ?? []);
  }

  /// Get car manufacturers (cached, non-stream version - kept for backward compatibility)
  @Deprecated('Use watchCarManufacturers() for real-time updates')
  Future<List<String>> getCarManufacturers() async {
    // If we have a stream subscription, use the current value
    if (_listsDocSubscription != null) {
      return _manufacturersSubject.value;
    }

    // Otherwise, fetch once
    try {
      final doc = await _firestore
          .collection(_collectionName)
          .doc('Lists')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final manufacturers = List<String>.from(data['car_manufacturers'] as List? ?? []);

        // Sort alphabetically in Hebrew
        manufacturers.sort((a, b) => a.compareTo(b));

        return manufacturers;
      }

      // Return default list if document doesn't exist
      return _getDefaultManufacturers();
    } catch (e) {
      // Return default list on error
      return _getDefaultManufacturers();
    }
  }

  /// Get car models for a specific manufacturer (cached, non-stream version)
  Future<List<String>> getCarModels(String manufacturer) async {
    // If we have a stream subscription, use the current value
    if (_listsDocSubscription != null) {
      return _modelsSubject.value[manufacturer] ?? [];
    }

    // Otherwise, fetch once
    try {
      final doc = await _firestore
          .collection(_collectionName)
          .doc('Lists')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final modelsMap = Map<String, dynamic>.from(data['car_models'] as Map? ?? {});
        final models = List<String>.from(modelsMap[manufacturer] as List? ?? []);
        models.sort((a, b) => a.compareTo(b));
        return models;
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  /// Clear the cache (useful when testing or after updates)
  void clearCache() {
    // No-op with stream-based approach - data updates automatically
  }

  /// Dispose of resources
  void dispose() {
    _listsDocSubscription?.cancel();
    _manufacturersSubject.close();
    _modelsSubject.close();
  }

  /// Default list of car manufacturers (fallback)
  List<String> _getDefaultManufacturers() {
    return [
      'אאודי',
      'אופל',
      'אלפא רומיאו',
      'ב.מ.וו',
      'ג\'יפ',
      'דאצ\'יה',
      'הונדה',
      'וולוו',
      'טויוטה',
      'יונדאי',
      'לקסוס',
      'מאזדה',
      'מזראטי',
      'מיני',
      'מיצובישי',
      'מרצדס',
      'ניסאן',
      'סאנגיונג',
      'סובארו',
      'סוזוקי',
      'סיאט',
      'סיטרואן',
      'סקודה',
      'פולקסווגן',
      'פורד',
      'פורשה',
      'פיאט',
      'פיג\'ו',
      'קאדילק',
      'קיה',
      'רנו',
      'שברולט',
      'אחר',
    ];
  }
}
