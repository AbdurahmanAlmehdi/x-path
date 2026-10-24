import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// A short message about something that just happened, with an [action]
/// such as Undo.
class Toast extends Equatable {
  /// Creates a toast.
  const new({
    required this.id,
    required this.message,
    this.action,
    this.onAction,
  });

  /// Tells it apart from the others shown.
  final int id;
  final String message;

  /// The label of what [onAction] does.
  final String? action;
  final void Function()? onAction;

  /// How long it stays: longer when it offers an action.
  Duration get duration => action == null ? toastShort : toastLong;

  @override
  List<Object?> get props => [id, message, action];
}

/// How long a toast stays.
const toastShort = Duration(seconds: 4);

/// How long a toast with an action stays.
const toastLong = Duration(seconds: 6);

/// The toasts shown, oldest first.
class ToastState extends Equatable {
  const new([this.toasts = const []]);

  final List<Toast> toasts;

  @override
  List<Object?> get props => [toasts];
}

/// Shows toasts, bottom right, each for its [Toast.duration]: at most
/// [limit] at once, the oldest going first.
class ToastCubit extends Cubit<ToastState> {
  new({this.limit = 3}) : super(const ToastState());

  final int limit;
  final _timers = <int, Timer>{};
  var _next = 0;

  /// Shows [message], with [action] when [onAction] is given; its id.
  int show(String message, {String? action, void Function()? onAction}) {
    final toast = Toast(
      id: _next++,
      message: message,
      action: onAction == null ? null : action,
      onAction: onAction,
    );
    final shown = [...state.toasts, toast];
    final over = max(0, shown.length - limit);
    for (final old in shown.take(over)) {
      _timers.remove(old.id)?.cancel();
    }
    emit(ToastState(shown.skip(over).toList()));
    _timers[toast.id] = Timer(toast.duration, () => dismiss(toast.id));
    return toast.id;
  }

  /// Takes the toast [id] away.
  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    if (isClosed) return;
    emit(
      ToastState([
        for (final t in state.toasts)
          if (t.id != id) t,
      ]),
    );
  }

  /// Does what the toast [id] offers, and takes it away.
  void act(int id) {
    final toast = state.toasts.where((t) => t.id == id).firstOrNull;
    dismiss(id);
    toast?.onAction?.call();
  }

  @override
  Future<void> close() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    return super.close();
  }
}
