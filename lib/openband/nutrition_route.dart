import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/day_label.dart';
import '../state/app_state.dart';
import 'controller.dart';
import 'local_repository.dart';
import 'nutrition.dart' show OpenBandNutrition;

/// Host for the Alpin nutrition parent.
///
/// A supplied [controller] is borrowed from the shell and never disposed.
/// Without one, this route owns a controller for [date] or local today,
/// captured once. Live writes subscribe to [AppState.insightsRevision] only —
/// not the ~1 Hz AppState tick. The shared shell controller is already
/// refreshed by the shell; an owned controller is refreshed on that signal.
class OpenBandNutritionRoute extends StatefulWidget {
  final OpenBandController? controller;
  final String? date;
  final FutureOr<void> Function(BuildContext context, String day, String meal)?
  onBarcode;

  const OpenBandNutritionRoute({
    super.key,
    this.controller,
    this.date,
    this.onBarcode,
  });

  @override
  State<OpenBandNutritionRoute> createState() => _OpenBandNutritionRouteState();
}

class _OpenBandNutritionRouteState extends State<OpenBandNutritionRoute> {
  OpenBandController? _owned;
  OpenBandController? _pendingDispose;
  AppState? _app;
  AppState? _ownedApp;
  ValueNotifier<int>? _rev;
  int _revision = 0;
  String? _ownedDate;

  bool get _borrowed => widget.controller != null;

  OpenBandController? get _active => widget.controller ?? _owned;

  @override
  void dispose() {
    _rev?.removeListener(_onRevision);
    _pendingDispose?.dispose();
    _owned?.dispose();
    super.dispose();
  }

  AppState? _appFromContext() {
    try {
      // Selecting the identity binds this State to provider replacement without
      // rebuilding for AppState's high-rate notifyListeners ticks.
      return context.select<AppState, AppState>((app) => app);
    } on ProviderNotFoundException {
      // Synthetic hosts pass a borrowed controller and intentionally have no
      // AppState or personal database in their widget tree.
      return null;
    }
  }

  void _bindApp(AppState? app) {
    final next = app?.insightsRevision;
    if (identical(_app, app) && identical(_rev, next)) return;
    _rev?.removeListener(_onRevision);
    _app = app;
    _rev = next;
    if (_rev != null) {
      _revision = _rev!.value;
      _rev!.addListener(_onRevision);
    } else {
      _revision = 0;
    }
  }

  void _syncHost() {
    if (_borrowed) {
      _retireOwned();
      return;
    }
    final app = _app;
    if (app == null) {
      _retireOwned();
      return;
    }
    final date = widget.date ?? _ownedDate ?? todayLabel();
    if (_owned != null && _ownedDate == date && identical(_ownedApp, app)) {
      return;
    }
    final next = OpenBandController(
      repository: LocalOpenBandRepository(app),
      initialDay: date,
    );
    _replaceOwned(next, date, app);
    unawaited(next.refresh());
  }

  void _retireOwned() {
    if (_owned == null) return;
    _replaceOwned(null, null, null);
  }

  void _replaceOwned(OpenBandController? next, String? date, AppState? app) {
    final previous = _owned;
    if (_pendingDispose != null) {
      _pendingDispose!.dispose();
      _pendingDispose = null;
    }
    _owned = next;
    _ownedDate = date;
    _ownedApp = app;
    if (previous == null) return;
    // The outgoing controller is still mounted on [OpenBandNutrition] until
    // this frame's [didUpdateWidget]. Dispose after the child unsubscribes.
    _pendingDispose = previous;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // dispose() already retires _pendingDispose when the route leaves before
      // this callback. A stale callback must never dispose the same controller
      // again (or one retired by a later replacement).
      if (mounted && identical(_pendingDispose, previous)) {
        _pendingDispose = null;
        previous.dispose();
      }
    });
  }

  void _onRevision() {
    final next = _rev?.value ?? 0;
    if (!mounted || next == _revision) return;
    setState(() => _revision = next);
    if (!_borrowed) unawaited(_owned?.refresh());
  }

  @override
  Widget build(BuildContext context) {
    _bindApp(_appFromContext());
    _syncHost();
    final controller = _active;
    if (controller == null) return const SizedBox.shrink();
    return OpenBandNutrition(
      controller: controller,
      onBarcode: widget.onBarcode,
      revision: _revision,
    );
  }
}
