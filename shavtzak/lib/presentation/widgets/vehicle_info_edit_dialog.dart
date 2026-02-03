import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/vehicle_info.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../core/services/utilities_service.dart';
import 'loading_overlay.dart';

/// Dialog for editing user's vehicle information
class VehicleInfoEditDialog extends StatefulWidget {
  const VehicleInfoEditDialog({super.key});

  @override
  State<VehicleInfoEditDialog> createState() => _VehicleInfoEditDialogState();
}

class _VehicleInfoEditDialogState extends State<VehicleInfoEditDialog> {
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  String? _selectedManufacturer;
  bool _isDirty = false;
  bool _isSaving = false;

  // Error states
  bool _showValidationErrors = false;
  String? _vehicleNumberError;

  @override
  void initState() {
    super.initState();
    // Initialize real-time updates
    UtilitiesService.instance.initialize();
    _initializeFields();
  }

  void _initializeFields() {
    final state = context.read<UserSelectionBloc>().state;
    if (state is UserAuthenticated && state.user.vehicleInfo != null) {
      final vehicleInfo = state.user.vehicleInfo!;
      _vehicleNumberController.text = vehicleInfo.vehicleNumber;
      _selectedManufacturer = vehicleInfo.manufacturer;
      _modelController.text = vehicleInfo.model;
      _colorController.text = vehicleInfo.color;
    }
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    _colorController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  bool get _hasPartialSelection {
    final filledCount = [
      _vehicleNumberController.text.isNotEmpty,
      _selectedManufacturer != null && _selectedManufacturer!.isNotEmpty,
      _modelController.text.isNotEmpty,
      _colorController.text.isNotEmpty,
    ].where((v) => v).length;
    return filledCount > 0 && filledCount < 4;
  }

  bool get _isVehicleNumberValid {
    final number = _vehicleNumberController.text.trim();
    return VehicleInfo.isValidVehicleNumber(number);
  }

  VehicleInfo? _getVehicleInfo() {
    final number = _vehicleNumberController.text.trim();
    final manufacturer = _selectedManufacturer;
    final model = _modelController.text.trim();
    final color = _colorController.text.trim();

    // If all empty, return null (clear vehicle info)
    if (number.isEmpty && (manufacturer == null || manufacturer.isEmpty) &&
        model.isEmpty && color.isEmpty) {
      return null;
    }

    // All fields must be filled
    if (number.isEmpty || manufacturer == null || manufacturer.isEmpty ||
        model.isEmpty || color.isEmpty) {
      return null;
    }

    // Validate vehicle number
    if (!_isVehicleNumberValid) {
      return null;
    }

    return VehicleInfo(
      vehicleNumber: number,
      manufacturer: manufacturer,
      model: model,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.directions_car, color: Colors.blue),
            SizedBox(width: 8),
            Text('פרטי רכב'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'מלא את פרטי הרכב שלך',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              // Vehicle number field
              TextField(
                controller: _vehicleNumberController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  labelText: 'מספר רכב',
                  hintText: '7-8 ספרות',
                  prefixIcon: const Icon(Icons.numbers),
                  errorText: _showValidationErrors && _vehicleNumberError != null
                      ? _vehicleNumberError
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _isDirty = true;
                    if (_showValidationErrors) {
                      _validateVehicleNumber(value);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              // Manufacturer dropdown - StreamBuilder for real-time updates
              StreamBuilder<List<String>>(
                stream: UtilitiesService.instance.watchCarManufacturers(),
                builder: (context, snapshot) {
                  final manufacturers = snapshot.data ?? [];

                  return DropdownButtonFormField<String>(
                    value: _selectedManufacturer,
                    decoration: const InputDecoration(
                      labelText: 'יצרן',
                      prefixIcon: Icon(Icons.factory),
                      border: OutlineInputBorder(),
                    ),
                    items: manufacturers.map((manufacturer) {
                      return DropdownMenuItem(
                        value: manufacturer,
                        child: Text(manufacturer),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedManufacturer = value;
                        _isDirty = true;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              // Model field - free text input
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'דגם',
                  hintText: 'למשל: יונדאי אקונט X, סונטה סדאן',
                  prefixIcon: Icon(Icons.directions_car),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _isDirty = true;
                  });
                },
              ),
              const SizedBox(height: 12),
              // Color field
              TextField(
                controller: _colorController,
                decoration: const InputDecoration(
                  labelText: 'צבע',
                  hintText: 'למשל: לבן, שחור, כסף',
                  prefixIcon: Icon(Icons.palette),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _isDirty = true;
                  });
                },
              ),
              if (_showValidationErrors && _hasPartialSelection) ...[
                const SizedBox(height: 8),
                const Text(
                  'יש למלא את כל השדות או להשאיר ריק',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              // Clear button when has data
              if (_vehicleNumberController.text.isNotEmpty ||
                  _selectedManufacturer != null ||
                  _modelController.text.isNotEmpty ||
                  _colorController.text.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _vehicleNumberController.clear();
                      _selectedManufacturer = null;
                      _modelController.clear();
                      _colorController.clear();
                      _vehicleNumberError = null;
                      _isDirty = true;
                      _showValidationErrors = false;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                  label: const Text('נקה פרטים', style: TextStyle(color: Colors.red)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: (_isDirty && !_isSaving) ? _saveVehicleInfo : null,
            child: const Text('שמור'),
          ),
        ],
          ),
          LoadingOverlay(isLoading: _isSaving, message: 'מעדכן פרטי רכב...'),
        ],
      ),
    );
  }

  void _validateVehicleNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      // Empty is only valid if all fields are empty
      _vehicleNumberError = null;
    } else if (!VehicleInfo.isValidVehicleNumber(trimmed)) {
      _vehicleNumberError = 'מספר רכב חייב להכיל 7-8 ספרות';
    } else {
      _vehicleNumberError = null;
    }
  }

  void _saveVehicleInfo() async {
    if (_isSaving) return;

    // Check if selection is valid before saving
    final vehicleInfo = _getVehicleInfo();

    if (vehicleInfo == null) {
      setState(() {
        _showValidationErrors = true;
      });
      return;
    }

    setState(() => _isSaving = true);

    final bloc = context.read<UserSelectionBloc>();

    try {
      // Use the UpdateVehicleInfo event to update the vehicle info
      bloc.add(UpdateVehicleInfo(vehicleInfo));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(vehicleInfo == null ? 'פרטי רכב הוסרו' : 'פרטי רכב עודכנו'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון פרטי רכב: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
