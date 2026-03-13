import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../data/repositories/user_selection_repository.dart';
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
  bool _isDeleting = false;

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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocListener<UserSelectionBloc, UserSelectionState>(
        listener: (context, state) {
          if (state is UserSelectionError) {
            // Show error message and reset loading state
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
              setState(() {
                _isDeleting = false;
              });
            }
            // Reset to previous state
            context.read<UserSelectionBloc>().add(const RefreshUserData());
          }

          // Listen for successful phone updates
          if (_isDeleting && state is UserAuthenticated) {
            // Show success message when phone is updated
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('מספר טלפון נמחק בהצלחה'),
                  backgroundColor: Colors.green,
                ),
              );
              setState(() {
                _isDeleting = false;
              });
            }
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
                  padding: EdgeInsets.all(_getResponsivePadding(context, 8)),
                  child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                    builder: (context, state) {
                      if (state is! UserAuthenticated) {
                        return const SizedBox.shrink();
                      }

                      final phone = state.user.phoneNumber;
                      final hasPhone = phone != null && phone.isNotEmpty;
                      final formattedPhone = Validators.formatPhoneNumber(phone);
                      final iconSize = _getResponsiveIconSize(context, 18);
                      final fontSize = _getResponsiveFontSize(context, 16);
                      final titleFontSize = _getResponsiveFontSize(context, 18);
                      final buttonPadding = _getResponsivePadding(context, 16);
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              formattedPhone,
                              style: TextStyle(
                                fontSize: fontSize,
                                color: Colors.blue,
                              ),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showPhoneEditDialog(context),
                                  icon: Icon(Icons.edit, size: iconSize, color: Colors.white),
                                  label: Text('ערוך', style: TextStyle(fontSize: fontSize * 0.75)),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
                                  ),
                                ),
                                SizedBox(width: spacing),
                                OutlinedButton.icon(
                                  onPressed: _isDeleting ? null : () => _deletePhoneNumber(context),
                                  icon: _isDeleting
                                      ? SizedBox(
                                          width: iconSize,
                                          height: iconSize,
                                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: const AlwaysStoppedAnimation<Color>(Colors.red)),
                                        )
                                      : Icon(Icons.delete, size: iconSize, color: Colors.red),
                                  label: Text(
                                    _isDeleting ? 'מוחק...' : 'מחק',
                                    style: TextStyle(color: Colors.red, fontSize: fontSize * 0.75),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    side: const BorderSide(color: Colors.red),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              'לא הוגדר מספר טלפון',
                              style: TextStyle(fontSize: fontSize, color: Colors.grey),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            ElevatedButton.icon(
                              onPressed: () => _showPhoneEditDialog(context),
                              icon: Icon(Icons.add, color: Colors.white, size: iconSize),
                              label: Text(
                                'הוסף מספר טלפון',
                                style: TextStyle(fontSize: fontSize * 0.85),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                  padding: EdgeInsets.all(_getResponsivePadding(context, 8)),
                  child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                    builder: (context, state) {
                      if (state is! UserAuthenticated) {
                        return const SizedBox.shrink();
                      }

                      final email = state.user.email;
                      final hasEmail = email != null && email.isNotEmpty;
                      final iconSize = _getResponsiveIconSize(context, 18);
                      final fontSize = _getResponsiveFontSize(context, 16);
                      final titleFontSize = _getResponsiveFontSize(context, 18);
                      final buttonPadding = _getResponsivePadding(context, 16);
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              email,
                              style: TextStyle(
                                fontSize: fontSize,
                                color: Colors.blue,
                              ),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showEmailEditDialog(context),
                                  icon: Icon(Icons.edit, size: iconSize, color: Colors.white),
                                  label: Text('ערוך', style: TextStyle(fontSize: fontSize * 0.75)),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
                                  ),
                                ),
                                SizedBox(width: spacing),
                                OutlinedButton.icon(
                                  onPressed: _isDeleting ? null : () => _deleteEmail(context),
                                  icon: _isDeleting
                                      ? SizedBox(
                                          width: iconSize,
                                          height: iconSize,
                                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: const AlwaysStoppedAnimation<Color>(Colors.red)),
                                        )
                                      : Icon(Icons.delete, size: iconSize, color: Colors.red),
                                  label: Text(
                                    _isDeleting ? 'מוחק...' : 'מחק',
                                    style: TextStyle(color: Colors.red, fontSize: fontSize * 0.75),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    side: const BorderSide(color: Colors.red),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              'לא הוגדרה כתובת אימייל',
                              style: TextStyle(fontSize: fontSize, color: Colors.grey),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            ElevatedButton.icon(
                              onPressed: () => _showEmailEditDialog(context),
                              icon: Icon(Icons.add, color: Colors.white, size: iconSize),
                              label: Text(
                                'הוסף כתובת אימייל',
                                style: TextStyle(fontSize: fontSize * 0.85),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                  padding: EdgeInsets.all(_getResponsivePadding(context, 8)),
                  child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                    builder: (context, state) {
                      if (state is! UserAuthenticated) {
                        return const SizedBox.shrink();
                      }

                      final birthday = state.user.birthday;
                      final hasBirthday = birthday != null;
                      final iconSize = _getResponsiveIconSize(context, 18);
                      final fontSize = _getResponsiveFontSize(context, 16);
                      final titleFontSize = _getResponsiveFontSize(context, 18);
                      final buttonPadding = _getResponsivePadding(context, 16);
                      final spacing = _getResponsivePadding(context, 8);
                      final iconSpacing = _getResponsivePadding(context, 4);

                      if (hasBirthday) {
                        final formattedBirthday = '${birthday.day.toString().padLeft(2, '0')}/${birthday.month.toString().padLeft(2, '0')}/${birthday.year}';
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              formattedBirthday,
                              style: TextStyle(
                                fontSize: fontSize,
                                color: Colors.pink,
                              ),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showBirthdayEditDialog(context),
                                  icon: Icon(Icons.edit, size: iconSize, color: Colors.white),
                                  label: Text('ערוך', style: TextStyle(fontSize: fontSize * 0.75)),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
                                  ),
                                ),
                                SizedBox(width: spacing),
                                OutlinedButton.icon(
                                  onPressed: () => _deleteBirthday(context),
                                  icon: Icon(Icons.delete, size: iconSize, color: Colors.red),
                                  label: Text(
                                    'מחק',
                                    style: TextStyle(color: Colors.red, fontSize: fontSize * 0.75),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    side: const BorderSide(color: Colors.red),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              'לא הוגדר יום הולדת',
                              style: TextStyle(fontSize: fontSize, color: Colors.grey),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            ElevatedButton.icon(
                              onPressed: () => _showBirthdayEditDialog(context),
                              icon: Icon(Icons.add, color: Colors.white, size: iconSize),
                              label: Text(
                                'הוסף יום הולדת',
                                style: TextStyle(fontSize: fontSize * 0.85),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                  padding: EdgeInsets.all(_getResponsivePadding(context, 8)),
                  child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                    builder: (context, state) {
                      if (state is! UserAuthenticated) {
                        return const SizedBox.shrink();
                      }

                      final vehicleInfo = state.user.vehicleInfo;
                      final hasVehicleInfo = vehicleInfo != null;
                      final iconSize = _getResponsiveIconSize(context, 18);
                      final fontSize = _getResponsiveFontSize(context, 16);
                      final titleFontSize = _getResponsiveFontSize(context, 18);
                      final buttonPadding = _getResponsivePadding(context, 16);
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              vehicleInfo.displayString,
                              style: TextStyle(
                                fontSize: fontSize,
                                color: Colors.blue,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showVehicleInfoEditDialog(context),
                                  icon: Icon(Icons.edit, size: iconSize, color: Colors.white),
                                  label: Text('ערוך', style: TextStyle(fontSize: fontSize * 0.75)),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
                                  ),
                                ),
                                SizedBox(width: spacing),
                                OutlinedButton.icon(
                                  onPressed: () => _deleteVehicleInfo(context),
                                  icon: Icon(Icons.delete, size: iconSize, color: Colors.red),
                                  label: Text(
                                    'מחק',
                                    style: TextStyle(color: Colors.red, fontSize: fontSize * 0.75),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    side: const BorderSide(color: Colors.red),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              'לא הוגדרו פרטי רכב',
                              style: TextStyle(fontSize: fontSize, color: Colors.grey),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            ElevatedButton.icon(
                              onPressed: () => _showVehicleInfoEditDialog(context),
                              icon: Icon(Icons.add, color: Colors.white, size: iconSize),
                              label: Text(
                                'הוסף פרטי רכב',
                                style: TextStyle(fontSize: fontSize * 0.85),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                  padding: EdgeInsets.all(_getResponsivePadding(context, 8)),
                  child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
                    builder: (context, state) {
                      if (state is! UserAuthenticated) {
                        return const SizedBox.shrink();
                      }

                      final hasPasscode = state.user.hasPasscode;
                      final passcodeLength = state.user.passcodeLength ?? 0;
                      final iconSize = _getResponsiveIconSize(context, 18);
                      final fontSize = _getResponsiveFontSize(context, 16);
                      final titleFontSize = _getResponsiveFontSize(context, 18);
                      final buttonPadding = _getResponsivePadding(context, 16);
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              'קוד גישה מוגדר ($passcodeLength ספרות)',
                              style: TextStyle(fontSize: fontSize),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.015),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showChangePasscodeDialog(context),
                                  icon: Icon(Icons.edit, size: iconSize, color: Colors.white),
                                  label: Text('ערוך', style: TextStyle(fontSize: fontSize * 0.75)),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
                                  ),
                                ),
                                SizedBox(width: spacing),
                                OutlinedButton.icon(
                                  onPressed: () => _showRemovePasscodeDialog(context),
                                  icon: Icon(Icons.delete, size: iconSize, color: Colors.red),
                                  label: Text(
                                    'מחק',
                                    style: TextStyle(color: Colors.red, fontSize: fontSize * 0.75),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size(0, 36 * (MediaQuery.of(context).size.width / 400).clamp(0.7, 1.0)),
                                    side: const BorderSide(color: Colors.red),
                                    padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
                                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
                            Text(
                              'לא הוגדר קוד גישה',
                              style: TextStyle(fontSize: fontSize, color: Colors.grey),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                            ElevatedButton.icon(
                              onPressed: () => _showSetupPasscodeDialog(context),
                              icon: Icon(Icons.add, color: Colors.white, size: iconSize),
                              label: Text(
                                'הגדר קוד גישה',
                                style: TextStyle(fontSize: fontSize * 0.85),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: buttonPadding, vertical: buttonPadding * 0.5),
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
            onPressed: () => Navigator.of(context).pop(),
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
          await userSelectionRepo.setTeamMemberPasscode(
            currentState.user.uniqueKey,
            passcode,
            length,
          );

          // Refresh user data
          bloc.add(const RefreshUserData());

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
      ),
    );

    if (result != null && context.mounted) {
      final currentPasscode = result['currentPasscode'] as String;
      final passcode = result['passcode'] as String;
      final length = result['length'] as int;

      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();

        await userSelectionRepo.setTeamMemberPasscode(
          currentState.user.uniqueKey,
          passcode,
          length,
          currentPasscode: currentPasscode,
        );

        // Refresh user data
        bloc.add(const CheckCachedUser());

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הסרת קוד גישה'),
          content: const Text(
            'האם את/ה בטוח/ה שברצונך להסיר את קוד הגישה?\nכל אחד יוכל לגשת לחשבון שלך ללא הגבלה.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('הסר קוד'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();
        final bloc = context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is UserAuthenticated) {
          await userSelectionRepo.clearTeamMemberPasscode(currentState.user.uniqueKey);

          // Refresh user data
          bloc.add(const RefreshUserData());

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('קוד גישה הוסר בהצלחה'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאה בהסרת קוד גישה: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showPhoneEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PhoneEditDialog(),
    );
  }

  void _deletePhoneNumber(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת מספר טלפון'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק את מספר הטלפון?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      setState(() {
        _isDeleting = true;
      });

      final bloc = context.read<UserSelectionBloc>();
      final currentState = bloc.state;

      if (currentState is UserAuthenticated) {
        // Add the update event to delete the phone number
        bloc.add(const UpdatePhoneNumber(null));
      }
    }
  }

  void _showEmailEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const EmailEditDialog(),
    );
  }

  void _deleteEmail(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת כתובת אימייל'),
          content: const Text('האם אתה בטוח/ה בטוח/ה שברצונך למחוק את כתובת האימייל?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      final bloc = context.read<UserSelectionBloc>();
      final currentState = bloc.state;

      if (currentState is UserAuthenticated) {
        // Add UpdateEmail event to delete the email
        bloc.add(const UpdateEmail(null));
      }
    }
  }

  void _launchEmail(String email) async {
    final Uri emailUri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  void _showBirthdayEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const BirthdayEditDialog(),
    );
  }

  void _deleteBirthday(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת תאריך לידה'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק את תאריך הלידה?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      final bloc = context.read<UserSelectionBloc>();
      final currentState = bloc.state;

      if (currentState is UserAuthenticated) {
        // Add the update event to delete the birthday
        bloc.add(const UpdateBirthday(null));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('תאריך לידה נמחק בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showVehicleInfoEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const VehicleInfoEditDialog(),
    );
  }

  void _deleteVehicleInfo(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת פרטי רכב'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק את פרטי הרכב?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      final bloc = context.read<UserSelectionBloc>();
      final currentState = bloc.state;

      if (currentState is UserAuthenticated) {
        // Add the update event to delete the vehicle info
        bloc.add(const UpdateVehicleInfo(null));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('פרטי רכב נמחקו בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}
