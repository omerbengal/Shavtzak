import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar_sync/calendar_sync_bloc.dart';
import '../bloc/calendar_sync/calendar_sync_state.dart';

/// A widget that listens for calendar sync state changes and shows notifications
/// Wrap your screen content with this widget to receive sync notifications
class CalendarSyncListener extends StatelessWidget {
  final Widget child;
  final bool showSuccessNotifications;
  final bool showFailureNotifications;

  const CalendarSyncListener({
    super.key,
    required this.child,
    this.showSuccessNotifications = false,
    this.showFailureNotifications = true,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<CalendarSyncBloc, CalendarSyncState>(
      listener: (context, state) {
        _handleStateChange(context, state);
      },
      child: child,
    );
  }

  void _handleStateChange(BuildContext context, CalendarSyncState state) {
    if (state is CalendarSyncSuccess && showSuccessNotifications) {
      _showSnackBar(
        context,
        message: state.message,
        icon: Icons.cloud_done,
        backgroundColor: Colors.green,
      );
    } else if (state is CalendarSyncRemovalSuccess && showSuccessNotifications) {
      _showSnackBar(
        context,
        message: state.message,
        icon: Icons.cloud_off,
        backgroundColor: Colors.green,
      );
    } else if (state is CalendarSyncFailure && showFailureNotifications) {
      _showSnackBar(
        context,
        message: 'שגיאה בסנכרון יומן: ${state.errorMessage}',
        icon: Icons.error_outline,
        backgroundColor: Colors.red,
        action: state.isRetryable
            ? SnackBarAction(
                label: 'נסה שוב',
                textColor: Colors.white,
                onPressed: () {
                  // TODO: Implement retry action when constraint data is available
                },
              )
            : null,
      );
    } else if (state is CalendarSyncBatchComplete) {
      if (state.failureCount > 0) {
        _showSnackBar(
          context,
          message: 'סנכרון הושלם: ${state.successCount} הצליחו, ${state.failureCount} נכשלו',
          icon: Icons.warning,
          backgroundColor: Colors.orange,
        );
      } else if (showSuccessNotifications && state.successCount > 0) {
        _showSnackBar(
          context,
          message: 'כל ${state.successCount} המגבלות סונכרנו בהצלחה',
          icon: Icons.cloud_done,
          backgroundColor: Colors.green,
        );
      }
    } else if (state is CalendarSyncInitializationFailed) {
      _showSnackBar(
        context,
        message: 'שגיאה באתחול שירות סנכרון היומן',
        icon: Icons.error_outline,
        backgroundColor: Colors.red,
      );
    } else if (state is CalendarSyncValidationComplete) {
      if (state.rejectedCount > 0) {
        _showSnackBar(
          context,
          message: state.message,
          icon: Icons.warning,
          backgroundColor: Colors.orange,
        );
      } else if (showSuccessNotifications) {
        _showSnackBar(
          context,
          message: state.message,
          icon: Icons.check_circle,
          backgroundColor: Colors.green,
        );
      }
    }
  }

  void _showSnackBar(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color backgroundColor,
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: action,
      ),
    );
  }
}

/// A simple button to manually trigger sync for all approved constraints
class SyncAllButton extends StatelessWidget {
  const SyncAllButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarSyncBloc, CalendarSyncState>(
      builder: (context, state) {
        final isLoading = state is CalendarSyncInProgress;
        final isDisabled = state is CalendarSyncDisabled ||
            state is CalendarSyncInitializationFailed;

        return Tooltip(
          message: 'סנכרן את כל המגבלות המאושרות',
          child: IconButton(
            onPressed: isLoading || isDisabled
                ? null
                : () {
                    // This requires team member data - should be triggered from a screen
                    // with access to the team data
                  },
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.cloud_sync,
                    color: isDisabled ? Colors.grey : Colors.blue,
                  ),
          ),
        );
      },
    );
  }
}
