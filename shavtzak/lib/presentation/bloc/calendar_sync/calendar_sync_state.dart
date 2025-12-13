import 'package:equatable/equatable.dart';
import '../../../core/constants/calendar_constants.dart';

/// Base class for calendar sync states
abstract class CalendarSyncState extends Equatable {
  const CalendarSyncState();

  @override
  List<Object?> get props => [];
}

/// Initial state before initialization
class CalendarSyncInitial extends CalendarSyncState {
  const CalendarSyncInitial();
}

/// Service is being initialized
class CalendarSyncInitializing extends CalendarSyncState {
  const CalendarSyncInitializing();
}

/// Service is initialized and ready
class CalendarSyncReady extends CalendarSyncState {
  final bool isTestMode;
  final int pendingSyncs;
  final int failedSyncs;

  const CalendarSyncReady({
    this.isTestMode = false,
    this.pendingSyncs = 0,
    this.failedSyncs = 0,
  });

  @override
  List<Object?> get props => [isTestMode, pendingSyncs, failedSyncs];

  CalendarSyncReady copyWith({
    bool? isTestMode,
    int? pendingSyncs,
    int? failedSyncs,
  }) {
    return CalendarSyncReady(
      isTestMode: isTestMode ?? this.isTestMode,
      pendingSyncs: pendingSyncs ?? this.pendingSyncs,
      failedSyncs: failedSyncs ?? this.failedSyncs,
    );
  }
}

/// A sync operation is in progress
class CalendarSyncInProgress extends CalendarSyncState {
  final String constraintId;
  final String message;

  const CalendarSyncInProgress({
    required this.constraintId,
    this.message = 'מסנכרן עם יומן גוגל...',
  });

  @override
  List<Object?> get props => [constraintId, message];
}

/// A sync operation completed successfully
class CalendarSyncSuccess extends CalendarSyncState {
  final String constraintId;
  final String? calendarEventId;
  final String message;

  const CalendarSyncSuccess({
    required this.constraintId,
    this.calendarEventId,
    this.message = 'סנכרון הושלם בהצלחה',
  });

  @override
  List<Object?> get props => [constraintId, calendarEventId, message];
}

/// A sync operation failed
class CalendarSyncFailure extends CalendarSyncState {
  final String constraintId;
  final String errorMessage;
  final bool isRetryable;
  final int retryCount;

  const CalendarSyncFailure({
    required this.constraintId,
    required this.errorMessage,
    this.isRetryable = true,
    this.retryCount = 0,
  });

  @override
  List<Object?> get props => [constraintId, errorMessage, isRetryable, retryCount];
}

/// Multiple syncs completed (batch operation)
class CalendarSyncBatchComplete extends CalendarSyncState {
  final int successCount;
  final int failureCount;
  final List<String> failedConstraintIds;

  const CalendarSyncBatchComplete({
    required this.successCount,
    required this.failureCount,
    this.failedConstraintIds = const [],
  });

  @override
  List<Object?> get props => [successCount, failureCount, failedConstraintIds];
}

/// Service failed to initialize
class CalendarSyncInitializationFailed extends CalendarSyncState {
  final String errorMessage;

  const CalendarSyncInitializationFailed({
    required this.errorMessage,
  });

  @override
  List<Object?> get props => [errorMessage];
}

/// Sync status for a specific constraint
class ConstraintSyncStatus extends CalendarSyncState {
  final String constraintId;
  final CalendarSyncStatus status;
  final String? calendarEventId;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  const ConstraintSyncStatus({
    required this.constraintId,
    required this.status,
    this.calendarEventId,
    this.lastSyncedAt,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [
        constraintId,
        status,
        calendarEventId,
        lastSyncedAt,
        errorMessage,
      ];
}

/// Removal operation completed
class CalendarSyncRemovalSuccess extends CalendarSyncState {
  final String constraintId;
  final String message;

  const CalendarSyncRemovalSuccess({
    required this.constraintId,
    this.message = 'הוסר מיומן גוגל בהצלחה',
  });

  @override
  List<Object?> get props => [constraintId, message];
}

/// Service is disabled (no credentials configured)
class CalendarSyncDisabled extends CalendarSyncState {
  final String reason;

  const CalendarSyncDisabled({
    this.reason = 'שירות סנכרון יומן לא מוגדר',
  });

  @override
  List<Object?> get props => [reason];
}

/// Calendar sync validation completed
class CalendarSyncValidationComplete extends CalendarSyncState {
  final int rejectedCount;
  final String message;

  const CalendarSyncValidationComplete({
    required this.rejectedCount,
    required this.message,
  });

  @override
  List<Object?> get props => [rejectedCount, message];
}

/// Bidirectional sync completed
class CalendarSyncBidirectionalComplete extends CalendarSyncState {
  final int rejectedCount;
  final int retriedCount;
  final int successCount;
  final String message;

  const CalendarSyncBidirectionalComplete({
    required this.rejectedCount,
    required this.retriedCount,
    required this.successCount,
    required this.message,
  });

  @override
  List<Object?> get props => [rejectedCount, retriedCount, successCount, message];
}
