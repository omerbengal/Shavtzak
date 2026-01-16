import 'package:equatable/equatable.dart';

/// Vehicle information for a team member
class VehicleInfo extends Equatable {
  final String vehicleNumber; // 7-8 digits (0-9 only)
  final String manufacturer;  // From predefined list
  final String model;         // Car model (דגם)
  final String color;         // Free text

  const VehicleInfo({
    required this.vehicleNumber,
    required this.manufacturer,
    required this.model,
    required this.color,
  });

  /// Check if all fields are filled (required for validation)
  bool get isComplete =>
      vehicleNumber.isNotEmpty &&
      manufacturer.isNotEmpty &&
      model.isNotEmpty &&
      color.isNotEmpty;

  /// Validate vehicle number format (7-8 digits)
  static bool isValidVehicleNumber(String number) {
    if (number.length < 7 || number.length > 8) return false;
    return RegExp(r'^[0-9]+$').hasMatch(number);
  }

  /// Format vehicle number for display (add dashes: XX-XXX-XX or XXX-XX-XXX)
  String get formattedVehicleNumber {
    if (vehicleNumber.length == 7) {
      // Format: XX-XXX-XX
      return '${vehicleNumber.substring(0, 2)}-${vehicleNumber.substring(2, 5)}-${vehicleNumber.substring(5, 7)}';
    } else if (vehicleNumber.length == 8) {
      // Format: XXX-XX-XXX
      return '${vehicleNumber.substring(0, 3)}-${vehicleNumber.substring(3, 5)}-${vehicleNumber.substring(5, 8)}';
    }
    return vehicleNumber;
  }

  /// Get display string for the vehicle info
  String get displayString => '$formattedVehicleNumber | $manufacturer $model | $color';

  /// Copy with method for immutability
  VehicleInfo copyWith({
    String? vehicleNumber,
    String? manufacturer,
    String? model,
    String? color,
  }) {
    return VehicleInfo(
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      color: color ?? this.color,
    );
  }

  @override
  List<Object?> get props => [vehicleNumber, manufacturer, model, color];

  @override
  String toString() => 'VehicleInfo($formattedVehicleNumber, $manufacturer, $model, $color)';
}
