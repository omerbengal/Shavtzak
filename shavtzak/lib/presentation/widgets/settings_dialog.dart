import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../data/repositories/user_selection_repository.dart';
import '../../core/utils/crud_action_result.dart';
import '../../core/utils/validators.dart';
import 'passcode_setup_dialog.dart';
import 'passcode_change_dialog.dart';
import 'phone_edit_dialog.dart';
import 'email_edit_dialog.dart';
import 'birthday_edit_dialog.dart';
import 'vehicle_info_edit_dialog.dart';

/// Settings dialog with passcode management
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _isMutating = false;
  String? _activeAction;

  // Helper method to calculate responsive font size
  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 400) return baseSize;
    return baseSize * (width / 400);
  }

  // Helper method to calculate responsive padding
  double _getResponsivePadding(BuildContext context, double basePadding) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 400) return basePadding;
    return basePadding * (width / 400);
  }

  // Helper method to calculate responsive icon size
  double _getResponsiveIconSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 400) return baseSize;
    return baseSize * (width / 400);
  }

  void _startMutation(String actionKey) {
    setState(() {
      _isMutating = true;
      _activeAction = actionKey;
    });
  }

  void _finishMutation() {
    if (!mounted) return;
    setState(() {
      _isMutating = false;
      _activeAction = null;
    });
  }

  bool _isActionLoading(String actionKey) =>
      _isMutating && _activeAction == actionKey;

  Future<CrudActionResult> _runUserSelectionAction({
    required void Function(CrudActionCompleter completion) dispatch,
  }) async {
    final completion = Completer<CrudActionResult>();
    dispatch(completion);
    return completion.future;
  }

  Future<void> _runSettingsMutation({
    required String actionKey,
    required Future<void> Function() action,
  }) async {
    if (_isMutating) {
      return;
    }

    _startMutation(actionKey);
    try {
      await action();
    } finally {
      _finishMutation();
    }
  }

  Future<CrudActionResult?> _showLoadingConfirmationDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required Future<CrudActionResult> Function() onConfirm,
    Color confirmColor = Colors.red,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    return showDialog<CrudActionResult?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var isProcessing = false;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text(title),
              content: Text(message, textAlign: TextAlign.center),
              actions: [
                TextButton(
                  onPressed: isProcessing
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('ביטול'),
                ),
                TextButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          setDialogState(() => isProcessing = true);
                          final result = await onConfirm();

                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }

                          if (result.isFailure) {
                            setDialogState(() => isProcessing = false);
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  result.message ?? 'הפעולה נכשלה',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          Navigator.of(dialogContext).pop(result);
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: confirmColor,
                  ),
                  child: isProcessing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: confirmColor,
                          ),
                        )
                      : Text(confirmLabel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocListener<UserSelectionBloc, UserSelectionState>(
        listener: (context, state) {
          if (state is UserSelectionError) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            }
            context.read<UserSelectionBloc>().add(const RefreshUserData());
          }
        },
        child: AlertDialog(
          title: const Center(child: Text('הגדרות')),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 350,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Phone number section
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding:
                          EdgeInsets.all(_getResponsivePadding(context, 8)),
                      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                        builder: (context, state) {
                          if (state is! UserAuthenticated) {
                            return const SizedBox.shrink();
                          }

                          final phone = state.user.phoneNumber;
                          final hasPhone = phone != null && phone.isNotEmpty;
                          final formattedPhone =
                              Validators.formatPhoneNumber(phone);
                          final iconSize = _getResponsiveIconSize(context, 18);
                          final fontSize = _getResponsiveFontSize(context, 16);
                          final titleFontSize =
                              _getResponsiveFontSize(context, 18);
                          final buttonPadding =
                              _getResponsivePadding(context, 16);
                          final spacing = _getResponsivePadding(context, 8);
                          final iconSpacing = _getResponsivePadding(context, 4);

                          if (hasPhone) {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.phone,
                                      color: Theme.of(context).primaryColor,
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'מספר טלפון',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  formattedPhone,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    color: Colors.blue,
                                  ),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _showPhoneEditDialog(context),
                                      icon: Icon(Icons.edit,
                                          size: iconSize, color: Colors.white),
                                      label: Text('ערוך',
                                          style: TextStyle(
                                              fontSize: fontSize * 0.75)),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                    SizedBox(width: spacing),
                                    OutlinedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _deletePhoneNumber(context),
                                      icon: Icon(Icons.delete,
                                          size: iconSize, color: Colors.red),
                                      label: Text(
                                        'מחק',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: fontSize * 0.75),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        side:
                                            const BorderSide(color: Colors.red),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.phone_disabled,
                                      color: Colors.grey[400],
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'מספר טלפון',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  'לא הוגדר מספר טלפון',
                                  style: TextStyle(
                                      fontSize: fontSize, color: Colors.grey),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                ElevatedButton.icon(
                                  onPressed: _isMutating
                                      ? null
                                      : () => _showPhoneEditDialog(context),
                                  icon: Icon(Icons.add,
                                      color: Colors.white, size: iconSize),
                                  label: Text(
                                    'הוסף מספר טלפון',
                                    style: TextStyle(fontSize: fontSize * 0.85),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: buttonPadding,
                                        vertical: buttonPadding * 0.5),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  // Email section
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding:
                          EdgeInsets.all(_getResponsivePadding(context, 8)),
                      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                        builder: (context, state) {
                          if (state is! UserAuthenticated) {
                            return const SizedBox.shrink();
                          }

                          final email = state.user.email;
                          final hasEmail = email != null && email.isNotEmpty;
                          final iconSize = _getResponsiveIconSize(context, 18);
                          final fontSize = _getResponsiveFontSize(context, 16);
                          final titleFontSize =
                              _getResponsiveFontSize(context, 18);
                          final buttonPadding =
                              _getResponsivePadding(context, 16);
                          final spacing = _getResponsivePadding(context, 8);
                          final iconSpacing = _getResponsivePadding(context, 4);

                          if (hasEmail) {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.email,
                                      color: Colors.blue,
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'כתובת אימייל',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  email,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    color: Colors.blue,
                                  ),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _showEmailEditDialog(context),
                                      icon: Icon(Icons.edit,
                                          size: iconSize, color: Colors.white),
                                      label: Text('ערוך',
                                          style: TextStyle(
                                              fontSize: fontSize * 0.75)),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                    SizedBox(width: spacing),
                                    OutlinedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _deleteEmail(context),
                                      icon: Icon(Icons.delete,
                                          size: iconSize, color: Colors.red),
                                      label: Text(
                                        'מחק',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: fontSize * 0.75),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        side:
                                            const BorderSide(color: Colors.red),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.email_outlined,
                                      color: Colors.grey[400],
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'כתובת אימייל',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  'לא הוגדרה כתובת אימייל',
                                  style: TextStyle(
                                      fontSize: fontSize, color: Colors.grey),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                ElevatedButton.icon(
                                  onPressed: _isMutating
                                      ? null
                                      : () => _showEmailEditDialog(context),
                                  icon: Icon(Icons.add,
                                      color: Colors.white, size: iconSize),
                                  label: Text(
                                    'הוסף כתובת אימייל',
                                    style: TextStyle(fontSize: fontSize * 0.85),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: buttonPadding,
                                        vertical: buttonPadding * 0.5),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  // Birthday section
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding:
                          EdgeInsets.all(_getResponsivePadding(context, 8)),
                      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                        builder: (context, state) {
                          if (state is! UserAuthenticated) {
                            return const SizedBox.shrink();
                          }

                          final birthday = state.user.birthday;
                          final hasBirthday = birthday != null;
                          final iconSize = _getResponsiveIconSize(context, 18);
                          final fontSize = _getResponsiveFontSize(context, 16);
                          final titleFontSize =
                              _getResponsiveFontSize(context, 18);
                          final buttonPadding =
                              _getResponsivePadding(context, 16);
                          final spacing = _getResponsivePadding(context, 8);
                          final iconSpacing = _getResponsivePadding(context, 4);

                          if (hasBirthday) {
                            final formattedBirthday =
                                '${birthday.day.toString().padLeft(2, '0')}/${birthday.month.toString().padLeft(2, '0')}/${birthday.year}';
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cake,
                                      color: Colors.pink,
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'יום הולדת',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  formattedBirthday,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    color: Colors.pink,
                                  ),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () =>
                                              _showBirthdayEditDialog(context),
                                      icon: Icon(Icons.edit,
                                          size: iconSize, color: Colors.white),
                                      label: Text('ערוך',
                                          style: TextStyle(
                                              fontSize: fontSize * 0.75)),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                    SizedBox(width: spacing),
                                    OutlinedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _deleteBirthday(context),
                                      icon: Icon(Icons.delete,
                                          size: iconSize, color: Colors.red),
                                      label: Text(
                                        'מחק',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: fontSize * 0.75),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        side:
                                            const BorderSide(color: Colors.red),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cake_outlined,
                                      color: Colors.grey[400],
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'יום הולדת',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  'לא הוגדר יום הולדת',
                                  style: TextStyle(
                                      fontSize: fontSize, color: Colors.grey),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                ElevatedButton.icon(
                                  onPressed: _isMutating
                                      ? null
                                      : () => _showBirthdayEditDialog(context),
                                  icon: Icon(Icons.add,
                                      color: Colors.white, size: iconSize),
                                  label: Text(
                                    'הוסף יום הולדת',
                                    style: TextStyle(fontSize: fontSize * 0.85),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: buttonPadding,
                                        vertical: buttonPadding * 0.5),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  // Vehicle info section
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding:
                          EdgeInsets.all(_getResponsivePadding(context, 8)),
                      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                        builder: (context, state) {
                          if (state is! UserAuthenticated) {
                            return const SizedBox.shrink();
                          }

                          final vehicleInfo = state.user.vehicleInfo;
                          final hasVehicleInfo = vehicleInfo != null;
                          final iconSize = _getResponsiveIconSize(context, 18);
                          final fontSize = _getResponsiveFontSize(context, 16);
                          final titleFontSize =
                              _getResponsiveFontSize(context, 18);
                          final buttonPadding =
                              _getResponsivePadding(context, 16);
                          final spacing = _getResponsivePadding(context, 8);
                          final iconSpacing = _getResponsivePadding(context, 4);

                          if (hasVehicleInfo) {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.directions_car,
                                      color: Colors.blue,
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'פרטי רכב',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  vehicleInfo.displayString,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    color: Colors.blue,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _showVehicleInfoEditDialog(
                                              context),
                                      icon: Icon(Icons.edit,
                                          size: iconSize, color: Colors.white),
                                      label: Text('ערוך',
                                          style: TextStyle(
                                              fontSize: fontSize * 0.75)),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                    SizedBox(width: spacing),
                                    OutlinedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _deleteVehicleInfo(context),
                                      icon: Icon(Icons.delete,
                                          size: iconSize, color: Colors.red),
                                      label: Text(
                                        'מחק',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: fontSize * 0.75),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        side:
                                            const BorderSide(color: Colors.red),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.directions_car_outlined,
                                      color: Colors.grey[400],
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'פרטי רכב',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  'לא הוגדרו פרטי רכב',
                                  style: TextStyle(
                                      fontSize: fontSize, color: Colors.grey),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                ElevatedButton.icon(
                                  onPressed: _isMutating
                                      ? null
                                      : () =>
                                          _showVehicleInfoEditDialog(context),
                                  icon: Icon(Icons.add,
                                      color: Colors.white, size: iconSize),
                                  label: Text(
                                    'הוסף פרטי רכב',
                                    style: TextStyle(fontSize: fontSize * 0.85),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: buttonPadding,
                                        vertical: buttonPadding * 0.5),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                  // Passcode section
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding:
                          EdgeInsets.all(_getResponsivePadding(context, 8)),
                      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                        builder: (context, state) {
                          if (state is! UserAuthenticated) {
                            return const SizedBox.shrink();
                          }

                          final hasPasscode = state.user.hasPasscode;
                          final passcodeLength = state.user.passcodeLength ?? 0;
                          final iconSize = _getResponsiveIconSize(context, 18);
                          final fontSize = _getResponsiveFontSize(context, 16);
                          final titleFontSize =
                              _getResponsiveFontSize(context, 18);
                          final buttonPadding =
                              _getResponsivePadding(context, 16);
                          final spacing = _getResponsivePadding(context, 8);
                          final iconSpacing = _getResponsivePadding(context, 4);

                          if (hasPasscode) {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.lock,
                                      color: Theme.of(context).primaryColor,
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'קוד גישה',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  'קוד גישה מוגדר ($passcodeLength ספרות)',
                                  style: TextStyle(fontSize: fontSize),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.015),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _showChangePasscodeDialog(
                                              context),
                                      icon: _isActionLoading('change_passcode')
                                          ? SizedBox(
                                              width: iconSize,
                                              height: iconSize,
                                              child:
                                                  const CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Icon(Icons.edit,
                                              size: iconSize,
                                              color: Colors.white),
                                      label: Text('ערוך',
                                          style: TextStyle(
                                              fontSize: fontSize * 0.75)),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                    SizedBox(width: spacing),
                                    OutlinedButton.icon(
                                      onPressed: _isMutating
                                          ? null
                                          : () => _showRemovePasscodeDialog(
                                              context),
                                      icon: Icon(Icons.delete,
                                          size: iconSize, color: Colors.red),
                                      label: Text(
                                        'מחק',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: fontSize * 0.75),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: Size(
                                            0,
                                            36 *
                                                (MediaQuery.of(context)
                                                            .size
                                                            .width /
                                                        400)
                                                    .clamp(0.7, 1.0)),
                                        side:
                                            const BorderSide(color: Colors.red),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadding,
                                            vertical: buttonPadding * 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.lock_open,
                                      color: Colors.grey[400],
                                      size: iconSize,
                                    ),
                                    SizedBox(width: iconSpacing),
                                    Text(
                                      'קוד גישה',
                                      style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.01),
                                Text(
                                  'לא הוגדר קוד גישה',
                                  style: TextStyle(
                                      fontSize: fontSize, color: Colors.grey),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.02),
                                ElevatedButton.icon(
                                  onPressed: _isMutating
                                      ? null
                                      : () => _showSetupPasscodeDialog(context),
                                  icon: _isActionLoading('setup_passcode')
                                      ? SizedBox(
                                          width: iconSize,
                                          height: iconSize,
                                          child:
                                              const CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(Icons.add,
                                          color: Colors.white, size: iconSize),
                                  label: Text(
                                    'הגדר קוד גישה',
                                    style: TextStyle(fontSize: fontSize * 0.85),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: buttonPadding,
                                        vertical: buttonPadding * 0.5),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isMutating ? null : () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSetupPasscodeDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => const PasscodeSetupDialog(),
    );

    if (result != null && context.mounted) {
      final passcode = result['passcode'] as String;
      final length = result['length'] as int;

      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();
        final bloc = context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is UserAuthenticated) {
          await _runSettingsMutation(
            actionKey: 'setup_passcode',
            action: () async {
              await userSelectionRepo.setTeamMemberPasscode(
                currentState.user.uniqueKey,
                passcode,
                length,
              );
              bloc.add(const RefreshUserData());
            },
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('קוד גישה הוגדר בהצלחה'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאה בהגדרת קוד גישה: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showChangePasscodeDialog(BuildContext context) async {
    final bloc = context.read<UserSelectionBloc>();
    final currentState = bloc.state;

    if (currentState is! UserAuthenticated ||
        currentState.user.passcodeLength == null) {
      return;
    }

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => PasscodeChangeDialog(
        currentLength: currentState.user.passcodeLength!,
        verifyCurrentPasscode: (enteredCurrentPasscode) async {
          final userSelectionRepo =
              this.context.read<UserSelectionRepository>();
          return userSelectionRepo.verifyTeamMemberPasscode(
            currentState.user.uniqueKey,
            enteredCurrentPasscode,
          );
        },
      ),
    );

    if (result != null && context.mounted) {
      final currentPasscode = result['currentPasscode'] as String;
      final passcode = result['passcode'] as String;
      final length = result['length'] as int;

      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();

        await _runSettingsMutation(
          actionKey: 'change_passcode',
          action: () async {
            await userSelectionRepo.setTeamMemberPasscode(
              currentState.user.uniqueKey,
              passcode,
              length,
              currentPasscode: currentPasscode,
            );
            bloc.add(const RefreshUserData());
          },
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('קוד גישה שונה בהצלחה'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאה בשינוי קוד גישה: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showRemovePasscodeDialog(BuildContext context) async {
    final result = await _showLoadingConfirmationDialog(
      context: context,
      title: 'הסרת קוד גישה',
      message:
          'האם את/ה בטוח/ה שברצונך להסיר את קוד הגישה?\nכל אחד יוכל לגשת לחשבון שלך ללא הגבלה.',
      confirmLabel: 'הסר קוד',
      onConfirm: () async {
        try {
          final userSelectionRepo =
              this.context.read<UserSelectionRepository>();
          final bloc = this.context.read<UserSelectionBloc>();
          final currentState = bloc.state;

          if (currentState is! UserAuthenticated) {
            return const CrudActionResult.failure('לא נמצא משתמש מחובר');
          }

          await userSelectionRepo.clearTeamMemberPasscode(
            currentState.user.uniqueKey,
          );
          bloc.add(const RefreshUserData());
          return const CrudActionResult.success('קוד גישה הוסר בהצלחה');
        } catch (e) {
          return CrudActionResult.failure('שגיאה בהסרת קוד גישה: $e');
        }
      },
    );

    if (result == null || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'קוד גישה הוסר בהצלחה'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showPhoneEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PhoneEditDialog(),
    );
  }

  void _deletePhoneNumber(BuildContext context) async {
    final result = await _showLoadingConfirmationDialog(
      context: context,
      title: 'מחיקת מספר טלפון',
      message: 'האם את/ה בטוח/ה שברצונך למחוק את מספר הטלפון?',
      confirmLabel: 'מחק',
      onConfirm: () async {
        final bloc = this.context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is! UserAuthenticated) {
          return const CrudActionResult.failure('לא נמצא משתמש מחובר');
        }

        return _runUserSelectionAction(
          dispatch: (completion) =>
              bloc.add(UpdatePhoneNumber(null, completion: completion)),
        );
      },
    );

    if (result == null || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'מספר טלפון נמחק בהצלחה'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showEmailEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const EmailEditDialog(),
    );
  }

  void _deleteEmail(BuildContext context) async {
    final result = await _showLoadingConfirmationDialog(
      context: context,
      title: 'מחיקת כתובת אימייל',
      message: 'האם אתה בטוח/ה בטוח/ה שברצונך למחוק את כתובת האימייל?',
      confirmLabel: 'מחק',
      onConfirm: () async {
        final bloc = this.context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is! UserAuthenticated) {
          return const CrudActionResult.failure('לא נמצא משתמש מחובר');
        }

        return _runUserSelectionAction(
          dispatch: (completion) =>
              bloc.add(UpdateEmail(null, completion: completion)),
        );
      },
    );

    if (result == null || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'כתובת אימייל נמחקה בהצלחה'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showBirthdayEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const BirthdayEditDialog(),
    );
  }

  void _deleteBirthday(BuildContext context) async {
    final result = await _showLoadingConfirmationDialog(
      context: context,
      title: 'מחיקת תאריך לידה',
      message: 'האם את/ה בטוח/ה שברצונך למחוק את תאריך הלידה?',
      confirmLabel: 'מחק',
      onConfirm: () async {
        final bloc = this.context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is! UserAuthenticated) {
          return const CrudActionResult.failure('לא נמצא משתמש מחובר');
        }

        return _runUserSelectionAction(
          dispatch: (completion) =>
              bloc.add(UpdateBirthday(null, completion: completion)),
        );
      },
    );

    if (result == null || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'תאריך לידה נמחק בהצלחה'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showVehicleInfoEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const VehicleInfoEditDialog(),
    );
  }

  void _deleteVehicleInfo(BuildContext context) async {
    final result = await _showLoadingConfirmationDialog(
      context: context,
      title: 'מחיקת פרטי רכב',
      message: 'האם את/ה בטוח/ה שברצונך למחוק את פרטי הרכב?',
      confirmLabel: 'מחק',
      onConfirm: () async {
        final bloc = this.context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is! UserAuthenticated) {
          return const CrudActionResult.failure('לא נמצא משתמש מחובר');
        }

        return _runUserSelectionAction(
          dispatch: (completion) =>
              bloc.add(UpdateVehicleInfo(null, completion: completion)),
        );
      },
    );

    if (result == null || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message ?? 'פרטי רכב נמחקו בהצלחה'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
