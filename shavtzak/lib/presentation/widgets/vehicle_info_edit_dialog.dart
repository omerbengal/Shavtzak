import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/vehicle_info.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../core/debug/logger.dart';
import '../../core/services/utilities_service.dart';
import '../../core/utils/crud_action_result.dart';
import '../../core/utils/rtl_text_field_utils.dart';

/// Dialog for editing user's vehicle information
class VehicleInfoEditDialog extends StatefulWidget {
  const VehicleInfoEditDialog({super.key});

  @override
  State<VehicleInfoEditDialog> createState() => _VehicleInfoEditDialogState();
}

class _VehicleInfoEditDialogState extends State<VehicleInfoEditDialog> {
  final TextEditingController _vehicleNumberController =
      TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  late final FocusNode _modelFocusNode;
  late final FocusNode _colorFocusNode;
  String? _selectedManufacturer;
  bool _isDirty = false;
  bool _isSaving = false;

  // Error states
  bool _showValidationErrors = false;
  String? _vehicleNumberError;

  @override
  void initState() {
    super.initState();
    _modelFocusNode = createRtlCursorFixedFocusNode(_modelController);
    _colorFocusNode = createRtlCursorFixedFocusNode(_colorController);
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
    _modelFocusNode.dispose();
    _colorFocusNode.dispose();
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
    if (number.isEmpty &&
        (manufacturer == null || manufacturer.isEmpty) &&
        model.isEmpty &&
        color.isEmpty) {
      return null;
    }

    // All fields must be filled
    if (number.isEmpty ||
        manufacturer == null ||
        manufacturer.isEmpty ||
        model.isEmpty ||
        color.isEmpty) {
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
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.directions_car, color: Colors.blue),
            SizedBox(width: 8),
            Text('פרטי רכב'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'מלא את פרטי הרכב שלך',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
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
                    errorText:
                        _showValidationErrors && _vehicleNumberError != null
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
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Center(
                              child: Text(manufacturer),
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        Logger.action('select:manufacturer',
                            {'manufacturer': Logger.redact(value ?? '')});
                        setState(() {
                          _selectedManufacturer = value;
                          _isDirty = true;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelController,
                  focusNode: _modelFocusNode,
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
                TextField(
                  controller: _colorController,
                  focusNode: _colorFocusNode,
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
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
              ],
            ),
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_vehicleNumberController.text.isNotEmpty ||
                  _selectedManufacturer != null ||
                  _modelController.text.isNotEmpty ||
                  _colorController.text.isNotEmpty)
                TextButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () {
                          Logger.action('tap:clearVehicleInfo');
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
                  label: const Text(
                    'נקה פרטים',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        Logger.action('tap:cancel:vehicleInfoDialog');
                        Navigator.of(context).pop();
                      },
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: (_isDirty && !_isSaving)
                    ? () {
                        Logger.action('tap:saveVehicleInfo');
                        _saveVehicleInfo();
                      }
                    : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('שמור'),
              ),
            ],
          ),
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

  Future<void> _saveVehicleInfo() async {
    if (_isSaving) return;

    // Check if selection is valid before saving
    final vehicleInfo = _getVehicleInfo();

    if (vehicleInfo == null) {
      setState(() {
        _showValidationErrors = true;
      });
      return;
    }

    final bloc = context.read<UserSelectionBloc>();

    setState(() => _isSaving = true);

    try {
      final completion = Completer<CrudActionResult>();
      bloc.add(UpdateVehicleInfo(vehicleInfo, completion: completion));
      final result = await completion.future;

      if (!mounted) {
        return;
      }

      if (result.isFailure) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'שגיאה בעדכון פרטי רכב'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'פרטי רכב עודכנו'),
          backgroundColor: Colors.green,
        ),
      );
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
