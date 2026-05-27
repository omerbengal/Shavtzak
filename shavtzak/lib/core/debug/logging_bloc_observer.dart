import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'debug_logger.dart';
import 'log_event.dart';
import 'logger.dart';

/// Records every BLoC dispatch, state transition, and error into the
/// global [DebugLogger] buffer.
///
/// Wired in `main.dart` via `Bloc.observer = LoggingBlocObserver();`.
///
/// Privacy: dispatched events are recorded as `{eventType: <runtimeType>}`
/// only. We do not introspect event fields, since they may carry raw user
/// content. Callers wanting field-level visibility should add an explicit
/// [Logger.action] call alongside the BLoC dispatch.
class LoggingBlocObserver extends BlocObserver {
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.blocDispatch,
      name: '${bloc.runtimeType} ← ${event.runtimeType}',
      context: {'eventType': '${event.runtimeType}'},
    ));
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.blocEmit,
      name: '${bloc.runtimeType} → ${transition.nextState.runtimeType}',
      context: {
        'propsChanged':
            _propsChanged(transition.currentState, transition.nextState),
      },
    ));
  }

  @override
  void onError(
    BlocBase<dynamic> bloc,
    Object error,
    StackTrace stackTrace,
  ) {
    super.onError(bloc, error, stackTrace);
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.blocError,
      name: '${bloc.runtimeType} error',
      context: {
        'error': error.runtimeType.toString(),
        'messageLen': Logger.redact(error.toString()),
        'stackHead': stackTrace.toString().split('\n').first,
      },
    ));
  }

  /// Returns the indices at which `current.props` and `next.props` differ.
  /// If lengths differ or either is not [Equatable], returns `['structural']`.
  List<Object> _propsChanged(Object? current, Object? next) {
    if (current is! Equatable || next is! Equatable) {
      return const ['structural'];
    }
    final cp = current.props;
    final np = next.props;
    if (cp.length != np.length) return const ['structural'];
    final out = <int>[];
    for (var i = 0; i < cp.length; i++) {
      if (cp[i] != np[i]) out.add(i);
    }
    return out;
  }
}
