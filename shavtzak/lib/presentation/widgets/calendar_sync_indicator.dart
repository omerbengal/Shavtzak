import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar_sync/calendar_sync_bloc.dart';
import '../bloc/calendar_sync/calendar_sync_state.dart';

/// A widget that displays the current calendar sync status
/// Shows different icons and colors based on the sync state
class CalendarSyncIndicator extends StatelessWidget {
  final bool showLabel;
  final VoidCallback? onTap;

  const CalendarSyncIndicator({
    super.key,
    this.showLabel = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarSyncBloc, CalendarSyncState>(
      builder: (context, state) {
        return _buildIndicator(context, state);
      },
    );
  }

  Widget _buildIndicator(BuildContext context, CalendarSyncState state) {
    IconData icon;
    Color color;
    String label;
    bool isAnimating = false;

    if (state is CalendarSyncInitial || state is CalendarSyncInitializing) {
      icon = Icons.cloud_outlined;
      color = Colors.grey;
      label = 'מאתחל...';
    } else if (state is CalendarSyncReady) {
      if (state.failedSyncs > 0) {
        icon = Icons.cloud_off;
        color = Colors.orange;
        label = '${state.failedSyncs} סנכרונים נכשלו';
      } else if (state.isTestMode) {
        icon = Icons.cloud_queue;
        color = Colors.blue;
        label = 'מצב בדיקה';
      } else {
        icon = Icons.cloud_done;
        color = Colors.green;
        label = 'מסונכרן';
      }
    } else if (state is CalendarSyncInProgress) {
      icon = Icons.cloud_sync;
      color = Colors.blue;
      label = 'מסנכרן...';
      isAnimating = true;
    } else if (state is CalendarSyncSuccess || state is CalendarSyncRemovalSuccess) {
      icon = Icons.cloud_done;
      color = Colors.green;
      label = 'סנכרון הושלם';
    } else if (state is CalendarSyncFailure) {
      icon = Icons.cloud_off;
      color = Colors.red;
      label = 'שגיאה בסנכרון';
    } else if (state is CalendarSyncDisabled) {
      icon = Icons.cloud_off;
      color = Colors.grey;
      label = 'סנכרון כבוי';
    } else if (state is CalendarSyncInitializationFailed) {
      icon = Icons.error_outline;
      color = Colors.red;
      label = 'שגיאה באתחול';
    } else {
      icon = Icons.cloud_outlined;
      color = Colors.grey;
      label = 'לא מוגדר';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAnimating)
              _AnimatedSyncIcon(icon: icon, color: color)
            else
              Icon(icon, color: color, size: 20),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated icon for sync in progress
class _AnimatedSyncIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _AnimatedSyncIcon({
    required this.icon,
    required this.color,
  });

  @override
  State<_AnimatedSyncIcon> createState() => _AnimatedSyncIconState();
}

class _AnimatedSyncIconState extends State<_AnimatedSyncIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: 20),
    );
  }
}

/// A badge widget that shows sync status on constraint cards
class ConstraintSyncBadge extends StatelessWidget {
  final String constraintId;

  const ConstraintSyncBadge({
    super.key,
    required this.constraintId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarSyncBloc, CalendarSyncState>(
      builder: (context, state) {
        // Only show badge for relevant states
        if (state is CalendarSyncInProgress && state.constraintId == constraintId) {
          return _buildBadge(
            icon: Icons.sync,
            color: Colors.blue,
            isAnimating: true,
          );
        } else if (state is CalendarSyncSuccess && state.constraintId == constraintId) {
          return _buildBadge(
            icon: Icons.check_circle,
            color: Colors.green,
          );
        } else if (state is CalendarSyncFailure && state.constraintId == constraintId) {
          return _buildBadge(
            icon: Icons.error,
            color: Colors.red,
          );
        }

        // Default - no badge
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required Color color,
    bool isAnimating = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isAnimating
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : Icon(icon, size: 16, color: color),
    );
  }
}
