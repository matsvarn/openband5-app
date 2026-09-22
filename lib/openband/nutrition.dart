import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'alp_tokens.dart';
import 'controller.dart';
import 'domain.dart';
import 'health.dart';
import 'journal_controls.dart';
import 'meal_entry.dart';
import 'nutrition_browser.dart';
import 'nutrition_goals.dart';
import 'theme.dart';
import 'undo_notice.dart';
import 'water.dart';

export 'nutrition_browser.dart' show obMeals;
export 'domain.dart' show MealDraftSaveResult;

class _FoodUndo {
  _FoodUndo(this.controller, this.repo, this.viewDay, this.receipt);
  final OpenBandController controller;
  final OpenBandRepository repo;
  final String viewDay;
  final FoodEntry receipt;
  bool busy = false;
  bool restored = false;
  bool conflict = false;
}

class _DraftPending {
  _DraftPending({
    required this.controller,
    required this.repo,
    required this.day,
    required this.meal,
    required this.expected,
    required this.draft,
    this.phase = _DraftPhase.save,
    this.error,
    this.resumeSearch = false,
    this.additions = const [],
  });
  final OpenBandController controller;
  final OpenBandRepository repo;
  final String day, meal;
  MealDraft? expected;
  MealDraft draft;
  _DraftPhase phase;
  String? error;
  bool resumeSearch;
  List<MealDraftEntry> additions;
  bool busy = false;
}

enum _DraftPhase { read, save, conflict, committedRead }

class OpenBandNutrition extends StatefulWidget {
  final OpenBandController controller;
  final FutureOr<void> Function(String meal)? onAdd;
  final FutureOr<void> Function(BuildContext context, String day, String meal)?
  onBarcode;
  final int revision;
  const OpenBandNutrition({
    super.key,
    required this.controller,
    this.onAdd,
    this.onBarcode,
    this.revision = 0,
  });
  @override
  State<OpenBandNutrition> createState() => _OpenBandNutritionState();
}

class _OpenBandNutritionState extends State<OpenBandNutrition> {
  late String _day = controller.selectedDay;
  DayMeals? _meals;
  Object? _mealsError;
  NutritionTargetValues? _targets;
  bool _targetsReady = false;
  bool _targetsUnavailable = false;
  bool _targetsLoading = true;
  int _tab = 0;
  int _mealRead = 0;
  int _targetRead = 0;
  int _weekRead = 0;
  int _recentRead = 0;
  List<NutritionDay>? _weekDays;
  Object? _weekError;
  List<FoodEntry>? _recent;
  Object? _recentError;
  _DraftPending? _pending;
  final _snack = GlobalKey<ScaffoldMessengerState>();
  _FoodUndo? _undo;
  bool _mealPickerBusy = false;
  bool _addBusy = false;
  bool _reuseBusy = false;
  bool _selectingDay = false;

  OpenBandController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    _loadMeals(_day);
    _loadTargets(_day);
  }

  @override
  void didUpdateWidget(covariant OpenBandNutrition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_onController);
      controller.addListener(_onController);
      _forgetStaleUndo();
      _syncDay();
      return;
    }
    if (oldWidget.revision != widget.revision) {
      _reloadRevision();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    if (controller.selectedDay != _day) {
      _syncDay();
      return;
    }
    setState(() {});
  }

  void _syncDay() {
    final day = controller.selectedDay;
    _forgetStaleUndo();
    _pending = null;
    _messenger?.removeCurrentSnackBar();
    setState(() {
      _day = day;
      _meals = null;
      _mealsError = null;
      _targets = null;
      _targetsReady = false;
      _targetsUnavailable = false;
      _targetsLoading = true;
      _weekDays = null;
      _weekError = null;
      _recent = null;
      _recentError = null;
    });
    _loadMeals(day);
    _loadTargets(day);
    if (_tab == 1) _loadWeek(day);
    if (_tab == 2) _loadRecent();
  }

  void _reloadRevision() {
    final day = controller.selectedDay;
    _loadMeals(day);
    _loadTargets(day);
    if (_tab == 1) _loadWeek(day);
    if (_tab == 2) _loadRecent();
  }

  void _forgetStaleUndo() {
    final undo = _undo;
    if (undo == null) return;
    if (identical(controller, undo.controller) &&
        identical(controller.repository, undo.repo) &&
        controller.selectedDay == undo.viewDay) {
      return;
    }
    _messenger?.removeCurrentSnackBar();
    _undo = null;
  }

  bool _displayLive(
    int token,
    int current,
    String day,
    OpenBandRepository repo,
    OpenBandController captured,
  ) =>
      mounted &&
      token == current &&
      identical(controller, captured) &&
      identical(controller.repository, repo) &&
      controller.selectedDay == day;

  Future<void> _loadMeals(String day) async {
    final repo = controller.repository;
    final captured = controller;
    final token = ++_mealRead;
    try {
      final meals = await repo.readMeals(day);
      if (!_displayLive(token, _mealRead, day, repo, captured)) return;
      setState(() {
        _meals = meals;
        _mealsError = null;
      });
    } catch (e) {
      if (!_displayLive(token, _mealRead, day, repo, captured)) return;
      setState(() {
        _meals = null;
        _mealsError = e;
      });
    }
  }

  Future<void> _loadTargets(String day) async {
    final repo = controller.repository;
    final captured = controller;
    final token = ++_targetRead;
    try {
      final snap = await repo.readNutritionTargets(day);
      if (!_displayLive(token, _targetRead, day, repo, captured)) return;
      setState(() {
        _targets = snap.values;
        _targetsReady = true;
        _targetsUnavailable = false;
        _targetsLoading = false;
      });
    } catch (_) {
      if (!_displayLive(token, _targetRead, day, repo, captured)) return;
      setState(() {
        _targets = null;
        _targetsReady = false;
        _targetsUnavailable = true;
        _targetsLoading = false;
      });
    }
  }

  Future<void> _retryTargets() async {
    if (_targetsLoading) return;
    final day = controller.selectedDay;
    setState(() => _targetsLoading = true);
    await _loadTargets(day);
  }

  Future<void> _openGoals() async {
    final day = controller.selectedDay;
    final repo = controller.repository;
    final captured = controller;
    await openOpenBandNutritionGoals(
      context,
      repository: repo,
      day: day,
      now: captured.day?.synthetic == true
          ? () => DateTime(2026, 9, 15, 9, 41)
          : captured.now,
      synthetic: captured.day?.synthetic == true,
    );
    if (!_sameCapture(repo, day, captured)) return;
    await _loadTargets(day);
  }

  Future<void> _onAdd(String meal) async {
    if (_addBusy || _pendingBlocksNewOperation()) return;
    _addBusy = true;
    try {
      if (widget.onAdd != null) {
        final day = controller.selectedDay;
        final repo = controller.repository;
        final captured = controller;
        await widget.onAdd!(meal);
        if (!_sameCapture(repo, day, captured)) return;
        await _reloadAll(repo, day, captured);
        return;
      }
      await _addViaSearch(meal);
    } finally {
      _addBusy = false;
    }
  }

  bool _sameCapture(
    OpenBandRepository repo,
    String day,
    OpenBandController captured,
  ) =>
      mounted &&
      identical(controller, captured) &&
      identical(controller.repository, repo) &&
      controller.selectedDay == day;

  Future<void> _reloadAll(
    OpenBandRepository repo,
    String day,
    OpenBandController captured,
  ) async {
    if (!_sameCapture(repo, day, captured)) return;
    await _loadMeals(day);
    if (!_sameCapture(repo, day, captured)) return;
    if (_mealsError case final error?) throw error;
    await _loadWeek(day);
    if (!_sameCapture(repo, day, captured)) return;
    await _loadRecent();
    if (!_sameCapture(repo, day, captured)) return;
    await captured.refresh();
    if (!_sameCapture(repo, day, captured)) return;
    if (captured.loadError case final error?) throw error;
  }

  ScaffoldMessengerState? get _messenger {
    final messenger = _snack.currentState;
    if (messenger == null || !messenger.mounted) return null;
    return messenger;
  }

  bool _undoLive(_FoodUndo undo) =>
      mounted &&
      identical(_undo, undo) &&
      identical(controller, undo.controller) &&
      identical(controller.repository, undo.repo) &&
      controller.selectedDay == undo.viewDay;

  Future<void> _openEntry(MealEntry entry) async {
    if (_pendingBlocksNewOperation()) return;
    final day = controller.selectedDay;
    final repo = controller.repository;
    final captured = controller;
    FoodEntryRouteResult? result;
    try {
      result = await openOpenBandFoodEntry(
        context,
        repository: repo,
        id: entry.id,
        day: day,
        synthetic: captured.day?.synthetic == true,
        now: captured.day?.synthetic == true
            ? () => DateTime(2026, 9, 15, 9, 41)
            : captured.now,
      );
    } catch (_) {
      return;
    }
    if (!mounted || result == null) return;
    final removed = result.removed;
    if (removed != null) {
      final undo = _FoodUndo(captured, repo, day, removed);
      if (_sameCapture(repo, day, captured)) {
        _undo = undo;
        _showRemovedSnack(undo);
      }
    }
    if (result.changed || removed != null) {
      try {
        await _reloadAll(repo, day, captured);
      } catch (_) {}
    }
  }

  void _showRemovedSnack(_FoodUndo undo) {
    _showFoodSnack(
      undo: undo,
      message: 'Eintrag entfernt',
      action: 'Rückgängig',
      onAction: () => _undoRestore(undo),
    );
  }

  void _showRestoreFailed(_FoodUndo undo) {
    _showFoodSnack(
      undo: undo,
      message: 'Wiederherstellen fehlgeschlagen',
      action: 'Erneut',
      onAction: () => _undoRestore(undo),
    );
  }

  void _showReadFailed(_FoodUndo undo) {
    _showFoodSnack(
      undo: undo,
      message: 'Einträge konnten nicht geladen werden.',
      action: 'Erneut',
      onAction: () => _undoReload(undo),
    );
  }

  void _showConflictSnack(_FoodUndo undo) {
    _showFoodSnack(
      undo: undo,
      message: 'Eintrag wurde geändert',
      action: 'Neu laden',
      onAction: () => _undoReload(undo),
      secondary: 'Schließen',
      onSecondary: () => _dismissUndo(undo),
    );
  }

  void _showFoodSnack({
    required _FoodUndo undo,
    required String message,
    required String action,
    required VoidCallback onAction,
    String? secondary,
    VoidCallback? onSecondary,
  }) {
    if (!_undoLive(undo)) return;
    final messenger = _messenger;
    if (messenger == null) return;
    VoidCallback guarded(VoidCallback pressed) => () {
      if (!identical(_undo, undo) || undo.busy) return;
      pressed();
    };
    showOpenBandUndoNotice(
      context: context,
      messenger: messenger,
      message: message,
      primaryLabel: action,
      onPrimary: guarded(onAction),
      secondaryLabel: secondary,
      onSecondary: onSecondary == null ? null : guarded(onSecondary),
    );
  }

  Future<void> _undoRestore(_FoodUndo undo) async {
    if (!_undoLive(undo) || undo.busy || undo.conflict) return;
    if (undo.restored) {
      await _undoReload(undo);
      return;
    }
    undo.busy = true;
    try {
      final result = await undo.repo.restoreFoodEntry(undo.receipt);
      if (!mounted) return;
      if (!identical(_undo, undo)) {
        if (result.saved &&
            _sameCapture(undo.repo, undo.viewDay, undo.controller)) {
          try {
            await _reloadAll(undo.repo, undo.viewDay, undo.controller);
          } catch (_) {}
        }
        return;
      }
      if (result.conflict) {
        undo.conflict = true;
        _showConflictSnack(undo);
        return;
      }
      undo.restored = true;
      if (_undoLive(undo)) {
        _messenger?.removeCurrentSnackBar();
      }
    } catch (_) {
      if (!mounted || !identical(_undo, undo)) return;
      _showRestoreFailed(undo);
      return;
    } finally {
      undo.busy = false;
    }
    if (identical(_undo, undo) && undo.restored) {
      await _undoReload(undo);
    }
  }

  Future<void> _undoReload(_FoodUndo undo) async {
    if (!identical(_undo, undo) || undo.busy) return;
    undo.busy = true;
    try {
      if (!_sameCapture(undo.repo, undo.viewDay, undo.controller)) {
        _messenger?.removeCurrentSnackBar();
        return;
      }
      try {
        await _reloadAll(undo.repo, undo.viewDay, undo.controller);
      } catch (_) {
        if (_undoLive(undo)) _showReadFailed(undo);
        return;
      }
      if (!mounted || !identical(_undo, undo)) return;
      if (_undoLive(undo)) {
        _messenger?.removeCurrentSnackBar();
        if (undo.restored || undo.conflict) _undo = null;
      }
    } finally {
      undo.busy = false;
    }
  }

  void _dismissUndo(_FoodUndo undo) {
    if (!identical(_undo, undo)) return;
    _messenger?.removeCurrentSnackBar();
    _undo = null;
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == 1) _loadWeek(controller.selectedDay);
    if (tab == 2) _loadRecent();
  }

  bool _weekLive(
    int token,
    String day,
    OpenBandRepository repo,
    OpenBandController captured,
  ) =>
      mounted &&
      token == _weekRead &&
      identical(controller, captured) &&
      identical(controller.repository, repo) &&
      controller.selectedDay == day;

  bool _recentLive(
    int token,
    OpenBandRepository repo,
    OpenBandController captured,
  ) =>
      mounted &&
      token == _recentRead &&
      identical(controller, captured) &&
      identical(controller.repository, repo);

  Future<void> _loadWeek(String day) async {
    final repo = controller.repository;
    final captured = controller;
    final token = ++_weekRead;
    try {
      final window = await repo.readNutritionWindow(day, days: 7);
      if (!_weekLive(token, day, repo, captured)) return;
      setState(() {
        _weekDays = window.days;
        _weekError = null;
      });
    } catch (e) {
      if (!_weekLive(token, day, repo, captured)) return;
      setState(() {
        _weekDays = null;
        _weekError = e;
      });
    }
  }

  Future<void> _loadRecent() async {
    final repo = controller.repository;
    final captured = controller;
    final token = ++_recentRead;
    try {
      final foods = await repo.readRecentFoods();
      if (!_recentLive(token, repo, captured)) return;
      setState(() {
        _recent = foods;
        _recentError = null;
      });
    } catch (e) {
      if (!_recentLive(token, repo, captured)) return;
      setState(() {
        _recent = null;
        _recentError = e;
      });
    }
  }

  void _info() {
    showOpenBandJournalInfo(
      context,
      title: 'Ernährung',
      body:
          'Unvollständige Einträge bleiben offen und senken die Summe nicht.\n'
          'Ziele über die Zielzeile.',
    );
  }

  Future<void> _openWeekDay(String day) async {
    if (_selectingDay || _pendingBlocksNewOperation()) return;
    final captured = controller;
    final repo = captured.repository;
    _selectingDay = true;
    try {
      await captured.selectDay(day);
      if (!mounted ||
          !identical(controller, captured) ||
          !identical(controller.repository, repo) ||
          controller.selectedDay != day) {
        return;
      }
      _selectTab(0);
    } finally {
      _selectingDay = false;
    }
  }

  bool _pendingBlocksNewOperation() {
    final pending = _pending;
    if (pending == null || !_pendingLive(pending)) return false;
    if (pending.error != null) _showPendingError(pending);
    return true;
  }

  Future<void> _pickMealThen(Future<void> Function(String meal) next) async {
    if (_mealPickerBusy || _pendingBlocksNewOperation()) return;
    final captured = controller;
    final repo = captured.repository;
    final day = captured.selectedDay;
    _mealPickerBusy = true;
    try {
      final meal = await showOpenBandMealPicker(context);
      if (meal == null || !_sameCapture(repo, day, captured)) return;
      await next(meal);
    } finally {
      _mealPickerBusy = false;
    }
  }

  MealDraft _emptyDraft(String day, String meal) => MealDraft(
    id: 'draft-$day-$meal',
    day: day,
    meal: meal,
    entries: const [],
    updatedAt: DateTime.now(),
  );

  Future<void> _addViaSearch(String meal) async {
    if (_pendingBlocksNewOperation()) return;
    final repo = controller.repository;
    final day = controller.selectedDay;
    final pending = _DraftPending(
      controller: controller,
      repo: repo,
      day: day,
      meal: meal,
      expected: null,
      draft: _emptyDraft(day, meal),
      phase: _DraftPhase.read,
      resumeSearch: true,
    );
    setState(() => _pending = pending);
    await _runPending(pending, () => _continueSearch(pending));
  }

  Future<void> _runPending(
    _DraftPending pending,
    Future<void> Function() operation,
  ) async {
    if (!_pendingLive(pending) || pending.busy) return;
    pending.busy = true;
    if (mounted) setState(() {});
    try {
      await operation();
    } finally {
      pending.busy = false;
      if (_pendingLive(pending)) {
        setState(() {});
        if (pending.error != null) _showPendingError(pending);
      }
    }
  }

  Future<void> _continueSearch(_DraftPending pending) async {
    if (!_pendingLive(pending)) return;
    final host = context;
    MealDraft? expected;
    try {
      expected = await pending.repo.readMealDraft(pending.day, pending.meal);
    } catch (_) {
      if (!_pendingLive(pending)) return;
      pending.phase = _DraftPhase.read;
      pending.error = 'Entwurf nicht geladen';
      _showPendingError(pending);
      return;
    }
    if (!_pendingLive(pending)) return;
    pending.expected = expected;
    pending.error = null;
    final seed = expected ?? _emptyDraft(pending.day, pending.meal);
    if (!host.mounted) return;
    final updated = await showModalBottomSheet<MealDraft>(
      context: host,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OBFoodSearchSheet(repository: pending.repo, draft: seed),
    );
    if (!_pendingLive(pending)) return;
    if (updated == null) {
      _pending = null;
      return;
    }
    pending.draft = updated;
    final originalIds = {for (final entry in seed.entries) entry.id};
    pending.additions = [
      for (final entry in updated.entries)
        if (!originalIds.contains(entry.id)) entry,
    ];
    pending.phase = _DraftPhase.save;
    pending.resumeSearch = false;
    await _commitPending(pending);
  }

  Future<void> _reuseFood(FoodEntry food) async {
    if (_reuseBusy || _mealPickerBusy || _pendingBlocksNewOperation()) return;
    final captured = controller;
    final repo = captured.repository;
    final day = captured.selectedDay;
    _reuseBusy = true;
    try {
      final meal = await showOpenBandMealPicker(context);
      if (meal == null || !_sameCapture(repo, day, captured)) return;
      final addition = mealDraftEntryFromFood(food, newOpenBandDraftEntryId());
      MealDraft? expected;
      try {
        expected = await repo.readMealDraft(day, meal);
      } catch (_) {
        if (!_sameCapture(repo, day, captured)) return;
        final pending = _DraftPending(
          controller: captured,
          repo: repo,
          day: day,
          meal: meal,
          expected: null,
          draft: MealDraft(
            id: 'draft-$day-$meal',
            day: day,
            meal: meal,
            entries: [addition],
            updatedAt: DateTime.now(),
          ),
          phase: _DraftPhase.read,
          error: 'Entwurf nicht geladen',
          additions: [addition],
        );
        setState(() => _pending = pending);
        _showPendingError(pending);
        return;
      }
      if (!_sameCapture(repo, day, captured)) return;
      final base = expected ?? _emptyDraft(day, meal);
      final pending = _DraftPending(
        controller: captured,
        repo: repo,
        day: day,
        meal: meal,
        expected: expected,
        draft: MealDraft(
          id: base.id,
          day: day,
          meal: meal,
          entries: [...base.entries, addition],
          updatedAt: DateTime.now(),
        ),
        additions: [addition],
      );
      setState(() => _pending = pending);
      await _runPending(pending, () => _commitPending(pending));
    } finally {
      _reuseBusy = false;
    }
  }

  bool _pendingLive(_DraftPending pending) =>
      mounted &&
      identical(_pending, pending) &&
      identical(controller, pending.controller) &&
      identical(controller.repository, pending.repo) &&
      controller.selectedDay == pending.day;

  Future<void> _commitPending(_DraftPending pending) async {
    if (!_pendingLive(pending)) return;
    try {
      final result = await saveOpenBandMealDraftCas(
        pending.repo,
        expected: pending.expected,
        draft: pending.draft,
      );
      if (!_pendingLive(pending)) return;
      if (result == MealDraftSaveResult.conflict) {
        pending.phase = _DraftPhase.conflict;
        pending.error = 'Konflikt';
        _showPendingError(pending);
        return;
      }
    } catch (_) {
      if (!_pendingLive(pending)) return;
      pending.phase = _DraftPhase.save;
      pending.error = 'Speichern fehlgeschlagen';
      _showPendingError(pending);
      return;
    }
    if (!_pendingLive(pending)) return;
    pending.error = null;
    _messenger?.removeCurrentSnackBar();
    await _reviewPending(pending);
  }

  Future<void> _reviewPending(_DraftPending pending) async {
    if (!_pendingLive(pending)) return;
    final saved = await showOpenBandMealDraft(
      context,
      pending.repo,
      pending.draft,
    );
    if (!_pendingLive(pending)) return;
    if (saved != true) {
      _messenger?.removeCurrentSnackBar();
      _pending = null;
      return;
    }
    pending.phase = _DraftPhase.committedRead;
    try {
      await _reloadAll(pending.repo, pending.day, pending.controller);
      if (_pendingLive(pending)) _pending = null;
    } catch (_) {
      if (!_pendingLive(pending)) return;
      pending.error = 'Einträge konnten nicht geladen werden.';
      _showPendingError(pending);
    }
  }

  Future<void> _retryPending(_DraftPending pending) async {
    if (!_pendingLive(pending) || pending.error == null || pending.busy) return;
    await _runPending(pending, () async {
      switch (pending.phase) {
        case _DraftPhase.read:
          if (pending.resumeSearch) {
            await _continueSearch(pending);
            return;
          }
          await _rereadMergeAndSave(pending);
        case _DraftPhase.conflict:
        case _DraftPhase.save:
          // A thrown write has unknown durability. Re-read and reconcile only
          // this operation's additions before attempting another CAS.
          await _rereadMergeAndSave(pending);
        case _DraftPhase.committedRead:
          try {
            await _reloadAll(pending.repo, pending.day, pending.controller);
            if (_pendingLive(pending)) {
              pending.error = null;
              _messenger?.removeCurrentSnackBar();
              _pending = null;
            }
          } catch (_) {
            if (_pendingLive(pending)) {
              pending.error = 'Einträge konnten nicht geladen werden.';
              _showPendingError(pending);
            }
          }
      }
    });
  }

  Future<void> _rereadMergeAndSave(_DraftPending pending) async {
    MealDraft? expected;
    try {
      expected = await pending.repo.readMealDraft(pending.day, pending.meal);
    } catch (_) {
      if (_pendingLive(pending)) {
        pending.phase = _DraftPhase.read;
        pending.error = 'Entwurf nicht geladen';
        _showPendingError(pending);
      }
      return;
    }
    if (!_pendingLive(pending)) return;
    pending.expected = expected;
    final base = expected ?? _emptyDraft(pending.day, pending.meal);
    final seen = {for (final e in base.entries) e.id};
    pending.draft = MealDraft(
      id: base.id,
      day: pending.day,
      meal: pending.meal,
      entries: [
        ...base.entries,
        for (final e in pending.additions)
          if (!seen.contains(e.id)) e,
      ],
      updatedAt: DateTime.now(),
    );
    pending.phase = _DraftPhase.save;
    pending.error = null;
    await _commitPending(pending);
  }

  void _showPendingError(_DraftPending pending) {
    if (!_pendingLive(pending)) return;
    final messenger = _messenger;
    if (messenger == null) return;
    messenger.removeCurrentSnackBar();
    final p = OB.of(context);
    final inverse = p.dark ? p.canvas : AlpColor.canvas;
    final bottom = 16.0 + MediaQuery.paddingOf(context).bottom;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        elevation: 0,
        // SnackBar requires a finite duration; this is operationally persistent.
        // Resolution/cancellation removes it explicitly.
        duration: const Duration(days: 36500),
        dismissDirection: DismissDirection.none,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottom),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Builder(
            builder: (context) {
              TextButton action(String label, VoidCallback onPressed) =>
                  TextButton(
                    onPressed: pending.busy ? null : onPressed,
                    style: TextButton.styleFrom(
                      foregroundColor: inverse,
                      disabledForegroundColor: inverse.withValues(alpha: .5),
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      label,
                      style: p
                          .text(15, weight: FontWeight.w600, color: inverse)
                          .copyWith(height: 20 / 15),
                    ),
                  );
              final actions = [
                action('Erneut', () => _retryPending(pending)),
                action('Schließen', () => _cancelPending(pending)),
              ];
              final message = Text(
                pending.error ?? 'Fehler',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: p.text(15, color: inverse).copyWith(height: 20 / 15),
              );
              final large = MediaQuery.textScalerOf(context).scale(15) > 20;
              if (large) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    message,
                    const SizedBox(height: 4),
                    Wrap(alignment: WrapAlignment.end, children: actions),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: message),
                  ...actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _cancelPending(_DraftPending pending) {
    if (!_pendingLive(pending) || pending.busy) return;
    _messenger?.removeCurrentSnackBar();
    setState(() => _pending = null);
  }

  Future<void> _barcode(String meal) async {
    final onBarcode = widget.onBarcode;
    if (onBarcode == null) return;
    final repo = controller.repository;
    final day = controller.selectedDay;
    final captured = controller;
    await onBarcode(context, day, meal);
    if (!_sameCapture(repo, day, captured)) return;
    try {
      await _reloadAll(repo, day, captured);
    } catch (_) {}
  }

  String get _headerSubtitle {
    if (_tab == 1) {
      final days = _weekDays;
      if (days != null && days.isNotEmpty) {
        return nutritionWeekRangeLabel([for (final d in days) d.date]);
      }
      return nutritionWeekRangeLabel(openBandDaysEnding(_day, 7));
    }
    return obDate(_day);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final meals = _meals;
    final repo = controller.repository;
    final day = controller.selectedDay;
    return ScaffoldMessenger(
      key: _snack,
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OBPageHeader(
                  title: 'Ernährung',
                  subtitle: _headerSubtitle,
                  onInfo: _info,
                  infoLabel: 'Information',
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        children: [
                          OBSegmented(
                            labels: const ['Tag', 'Woche', 'Lebensmittel'],
                            selected: _tab,
                            onChanged: _selectTab,
                          ),
                          const SizedBox(height: 12),
                          if (_tab == 0) ..._dayBody(p, meals, repo, day),
                          if (_tab == 1) ..._weekBody(),
                          if (_tab == 2) ..._recentBody(),
                        ],
                      ),
                    ),
                    if (_tab != 1)
                      OpenBandNutritionFooter(
                        onSearch: () => _pickMealThen(_onAdd),
                        onBarcode: widget.onBarcode == null
                            ? null
                            : () => _pickMealThen(_barcode),
                        onAdd: () => _pickMealThen(_onAdd),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _dayBody(
    OB p,
    DayMeals? meals,
    OpenBandRepository repo,
    String day,
  ) {
    if (_mealsError != null) {
      return [
        OpenBandNutritionError(
          message: 'Einträge konnten nicht geladen werden.',
          onRetry: () => _loadMeals(day),
        ),
      ];
    }
    if (meals == null) return const [SizedBox.shrink()];
    return [
      if (_targetsUnavailable || _targetsReady) ...[
        OBMacroBars(
          meals: meals,
          targets: _targetsUnavailable ? null : _targets,
          targetsUnavailable: _targetsUnavailable,
          onGoalTap: _openGoals,
        ),
        if (_targetsUnavailable)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _targetsLoading ? null : _retryTargets,
              style: TextButton.styleFrom(
                foregroundColor: p.ink,
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Erneut', style: p.text(13, weight: FontWeight.w600)),
            ),
          ),
        const SizedBox(height: 12),
      ],
      OpenBandWaterCard(
        repository: repo,
        day: day,
        revision: widget.revision,
        onSaved: () async {
          final captured = controller;
          if (!_sameCapture(repo, day, captured)) return;
          await captured.refresh();
        },
      ),
      const SizedBox(height: 12),
      for (final (key, label) in obMeals) ...[
        OBMealSection(
          meal: key,
          label: label,
          entries: meals.entries.where((e) => e.meal == key).toList(),
          onAdd: () => _onAdd(key),
          onOpen: _openEntry,
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _weekBody() {
    if (_weekError != null) {
      return [
        OpenBandNutritionError(
          message: 'Woche nicht geladen',
          onRetry: () => _loadWeek(controller.selectedDay),
        ),
      ];
    }
    final days = _weekDays;
    if (days == null) return const [SizedBox.shrink()];
    return [OpenBandNutritionWeek(days: days, onOpenDay: _openWeekDay)];
  }

  List<Widget> _recentBody() {
    if (_recentError != null) {
      return [
        OpenBandNutritionError(
          message: 'Einträge konnten nicht geladen werden.',
          onRetry: _loadRecent,
        ),
      ];
    }
    final foods = _recent;
    if (foods == null) return const [SizedBox.shrink()];
    return [OpenBandRecentFoods(foods: foods, onReuse: _reuseFood)];
  }
}

String _nutritionQty(double? value) {
  if (value == null || !value.isFinite) return '—';
  if (value == value.roundToDouble()) return obNumber(value);
  var text = obNumber(value, digits: 2);
  if (text.contains(',')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith(',')) text = text.substring(0, text.length - 1);
  }
  return text;
}

int _missingShownNutrientCount(DayMeals meals) {
  var n = 0;
  for (final e in meals.entries) {
    if (e.kcal == null ||
        e.proteinG == null ||
        e.fatG == null ||
        e.carbsG == null) {
      n++;
    }
  }
  return n;
}

String _macroGramsLine(NutrientSum sum, double? target) {
  final actual = _nutritionQty(sum.value);
  if (target == null || !target.isFinite) return '$actual g';
  return '$actual / ${_nutritionQty(target)} g';
}

String _missingNutrientLabel(int count) =>
    '$count ${count == 1 ? 'Eintrag' : 'Einträge'} unvollständig';

bool _positiveTarget(double? value) =>
    value != null && value.isFinite && value > 0;

bool _savedGramTarget(double? value) => value != null && value.isFinite;

bool _largeMacroType(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20;

const _kMacroColGap = 10.0;
const _kMacroPairGap = 4.0;
const _kMacroHeaderGap = 12.0;
const _kMacroKcalUnitGap = 6.0;

TextStyle _macroLabelStyle(OB p) => p
    .text(12, weight: FontWeight.w600, color: p.muted)
    .copyWith(height: 16 / 12);

TextStyle _macroValueStyle(OB p) => p
    .text(13, weight: FontWeight.w700, display: true)
    .copyWith(
      height: 16 / 13,
      letterSpacing: 0,
      fontFeatures: const [FontFeature.proportionalFigures()],
    );

double _macroPaintWidth(
  String text,
  TextStyle style, {
  required TextScaler scaler,
  required Locale locale,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
    locale: locale,
  )..layout();
  return painter.width;
}

bool _macroRowFitsThree({
  required double maxWidth,
  required List<(String label, String value)> items,
  required TextStyle labelStyle,
  required TextStyle valueStyle,
  required TextScaler scaler,
  required Locale locale,
}) {
  if (items.isEmpty) return true;
  final columnWidth =
      (maxWidth - _kMacroColGap * (items.length - 1)) / items.length;
  if (columnWidth <= 0) return false;
  for (final (label, value) in items) {
    final needed =
        _macroPaintWidth(label, labelStyle, scaler: scaler, locale: locale) +
        _kMacroPairGap +
        _macroPaintWidth(value, valueStyle, scaler: scaler, locale: locale);
    if (needed > columnWidth) return false;
  }
  return true;
}

bool _macroHeaderFits({
  required double maxWidth,
  required String kcal,
  required String ziel,
  required TextStyle kcalStyle,
  required TextStyle unitStyle,
  required TextStyle zielStyle,
  required TextScaler scaler,
  required Locale locale,
}) {
  final kcalWidth =
      _macroPaintWidth(kcal, kcalStyle, scaler: scaler, locale: locale) +
      _kMacroKcalUnitGap +
      _macroPaintWidth('kcal', unitStyle, scaler: scaler, locale: locale);
  final zielWidth = _macroPaintWidth(
    ziel,
    zielStyle,
    scaler: scaler,
    locale: locale,
  );
  return kcalWidth + _kMacroHeaderGap + zielWidth <= maxWidth;
}

class OBMacroBars extends StatelessWidget {
  final DayMeals meals;
  final NutritionTargetValues? targets;
  final bool targetsUnavailable;
  final VoidCallback? onGoalTap;
  const OBMacroBars({
    super.key,
    required this.meals,
    this.targets,
    this.targetsUnavailable = false,
    this.onGoalTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final t = targetsUnavailable
        ? const NutritionTargetValues()
        : targets ?? const NutritionTargetValues();
    final large = _largeMacroType(context);
    final energyTarget = _positiveTarget(t.energyKcal) ? t.energyKcal : null;
    final energyLabel = targetsUnavailable
        ? 'Ziel —'
        : energyTarget == null
        ? 'Kein Ziel'
        : 'Ziel ${_nutritionQty(energyTarget)}';
    final missing = _missingShownNutrientCount(meals);
    final labelStyle = _macroLabelStyle(p);
    final valueStyle = _macroValueStyle(p);
    final macros = [
      (
        name: 'protein',
        label: 'Eiweiß',
        semantic: 'Eiweiß',
        sum: meals.proteinG,
        target: t.proteinG,
        color: p.pulse,
      ),
      (
        name: 'fat',
        label: 'Fett',
        semantic: 'Fett',
        sum: meals.fatG,
        target: t.fatG,
        color: p.food,
      ),
      (
        name: 'carbs',
        label: large ? 'Kohlenhydrate' : 'KH',
        semantic: 'Kohlenhydrate',
        sum: meals.carbsG,
        target: t.carbohydrateG,
        color: p.strain,
      ),
    ];
    final headline = p
        .text(34, weight: FontWeight.w800, display: true)
        .copyWith(height: 36 / 34);
    final unitStyle = p
        .text(14, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 14);
    final zielStyle = p
        .text(13, weight: FontWeight.w600, color: p.muted)
        .copyWith(height: 18 / 13);
    final missingStyle = p.text(12, color: p.muted).copyWith(height: 16 / 12);
    final semantics = [
      '${_nutritionQty(meals.kcal.value)} kcal',
      energyLabel,
      for (final m in macros)
        '${m.semantic} ${_macroGramsLine(m.sum, _savedGramTarget(m.target) ? m.target : null)}',
      if (missing > 0) _missingNutrientLabel(missing),
    ].join('. ');

    Widget column({
      required String name,
      required String label,
      required NutrientSum sum,
      required double? target,
      required Color color,
    }) {
      final saved = _savedGramTarget(target);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: labelStyle),
              const SizedBox(width: _kMacroPairGap),
              Expanded(
                child: Text(
                  _macroGramsLine(sum, saved ? target : null),
                  textAlign: TextAlign.right,
                  style: valueStyle,
                ),
              ),
            ],
          ),
          if (saved)
            _MacroFillTrack(
              name: name,
              height: 6,
              radius: 3,
              fillColor: color,
              actual: sum.value,
              target: target,
            ),
        ],
      );
    }

    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: OBCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final locale = Localizations.localeOf(context);
              final kcalText = _nutritionQty(meals.kcal.value);
              final headerBeside =
                  !large &&
                  _macroHeaderFits(
                    maxWidth: constraints.maxWidth,
                    kcal: kcalText,
                    ziel: energyLabel,
                    kcalStyle: headline,
                    unitStyle: unitStyle,
                    zielStyle: zielStyle,
                    scaler: scaler,
                    locale: locale,
                  );
              final stacked =
                  large ||
                  !_macroRowFitsThree(
                    maxWidth: constraints.maxWidth,
                    items: [
                      for (final m in macros)
                        (
                          m.label,
                          _macroGramsLine(
                            m.sum,
                            _savedGramTarget(m.target) ? m.target : null,
                          ),
                        ),
                    ],
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                    scaler: scaler,
                    locale: locale,
                  );
              final kcalRow = Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(kcalText, style: headline),
                  const SizedBox(width: _kMacroKcalUnitGap),
                  Text('kcal', style: unitStyle),
                ],
              );
              Widget goalLabel({required TextAlign align}) {
                final text = Text(
                  energyLabel,
                  textAlign: align,
                  style: zielStyle,
                );
                if (onGoalTap == null) return text;
                return Tooltip(
                  message: 'Ernährungsziele',
                  child: InkWell(
                    onTap: onGoalTap,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: align == TextAlign.right
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: text,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  if (headerBeside)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        kcalRow,
                        Expanded(child: goalLabel(align: TextAlign.right)),
                      ],
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        kcalRow,
                        goalLabel(align: TextAlign.left),
                      ],
                    ),
                  if (energyTarget != null)
                    _MacroFillTrack(
                      name: 'energy',
                      height: 8,
                      radius: 4,
                      fillColor: p.ink,
                      actual: meals.kcal.value,
                      target: energyTarget,
                    ),
                  if (stacked)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        for (final m in macros)
                          column(
                            name: m.name,
                            label: m.label,
                            sum: m.sum,
                            target: m.target,
                            color: m.color,
                          ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: _kMacroColGap,
                      children: [
                        for (final m in macros)
                          Expanded(
                            child: column(
                              name: m.name,
                              label: m.label,
                              sum: m.sum,
                              target: m.target,
                              color: m.color,
                            ),
                          ),
                      ],
                    ),
                  if (missing > 0)
                    Text(_missingNutrientLabel(missing), style: missingStyle),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MacroFillTrack extends StatelessWidget {
  final String name;
  final double height;
  final double radius;
  final Color fillColor;
  final double? actual;
  final double? target;
  const _MacroFillTrack({
    required this.name,
    required this.height,
    required this.radius,
    required this.fillColor,
    required this.actual,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final canFill =
        actual != null &&
        actual!.isFinite &&
        target != null &&
        target!.isFinite &&
        target! > 0;
    final factor = canFill ? (actual! / target!).clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        key: ValueKey('macro-$name-track'),
        height: height,
        width: double.infinity,
        child: ColoredBox(
          color: p.well,
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                key: ValueKey('macro-$name-fill'),
                width: constraints.maxWidth * factor,
                height: height,
                child: ColoredBox(color: fillColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OBMealSection extends StatelessWidget {
  final String meal, label;
  final List<MealEntry> entries;
  final VoidCallback? onAdd;
  final ValueChanged<MealEntry>? onOpen;
  const OBMealSection({
    super.key,
    required this.meal,
    required this.label,
    required this.entries,
    this.onAdd,
    this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final large = MediaQuery.textScalerOf(context).scale(15) > 20;
    final known = entries.where((e) => e.kcal != null).toList();
    final total = known.isEmpty
        ? null
        : known.fold<double>(0, (a, e) => a + e.kcal!);
    final partial = known.length < entries.length && entries.isNotEmpty;
    final energy = total == null ? '—' : '${obNumber(total)} kcal';
    final titleStyle = p
        .text(15, weight: FontWeight.w600)
        .copyWith(height: 20 / 15);
    final partialStyle = p
        .text(13, weight: FontWeight.w500, color: p.muted)
        .copyWith(height: 18 / 13);
    final energyStyle = p
        .text(
          15,
          weight: FontWeight.w700,
          color: total == null ? p.muted : p.ink,
          display: true,
        )
        .copyWith(height: 20 / 15, letterSpacing: 0);
    final add = Tooltip(
      message: '$label ergänzen',
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          onPressed: onAdd,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          icon: Container(
            width: large ? 44 : 28,
            height: large ? 44 : 28,
            decoration: BoxDecoration(
              color: p.well,
              borderRadius: BorderRadius.circular(large ? 12 : 8),
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.plus, size: 20, color: p.ink),
          ),
        ),
      ),
    );
    final header = large
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label, style: titleStyle)),
                    const SizedBox(width: 8),
                    add,
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (partial) ...[
                      Expanded(child: Text('Teilweise', style: partialStyle)),
                      const SizedBox(width: 10),
                    ],
                    Text(energy, style: energyStyle),
                  ],
                ),
              ],
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(child: Text(label, style: titleStyle)),
                      if (partial) ...[
                        const SizedBox(width: 8),
                        Flexible(child: Text('Teilweise', style: partialStyle)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(energy, style: energyStyle),
                const SizedBox(width: 10),
                add,
              ],
            ),
          );
    return OBCard(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
      child: Column(
        children: [
          header,
          for (final e in entries)
            OpenBandFoodEnergyRow(
              id: e.id,
              label: e.label,
              kcal: e.kcal,
              onTap: onOpen == null ? null : () => onOpen!(e),
            ),
        ],
      ),
    );
  }
}

/// Stages entries for one meal and saves them atomically (B05). The picker
/// that fills the draft is the host's; this widget owns preview and commit.
class OBMealDraftSheet extends StatefulWidget {
  final OpenBandRepository repository;
  final MealDraft draft;
  const OBMealDraftSheet({
    super.key,
    required this.repository,
    required this.draft,
  });
  @override
  State<OBMealDraftSheet> createState() => _OBMealDraftSheetState();
}

class _OBMealDraftSheetState extends State<OBMealDraftSheet> {
  late MealDraft _draft = widget.draft;
  late final String _day = widget.draft.day;
  late final String _meal = widget.draft.meal;
  bool _busy = false;
  bool _conflict = false;
  bool _missing = false;
  String? _error;

  Future<void> _commit() async {
    if (_busy || _conflict || _missing) return;
    _busy = true;
    setState(() => _error = null);
    try {
      final result = await widget.repository.commitMealDraft(_draft);
      if (!mounted) return;
      switch (result) {
        case MealDraftCommitResult.saved:
          Navigator.of(context).pop(true);
        case MealDraftCommitResult.conflict:
          setState(() {
            _busy = false;
            _conflict = true;
            _error = 'Entwurf nicht gespeichert';
          });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Speichern fehlgeschlagen';
      });
    }
  }

  Future<void> _reload() async {
    if (_busy || _missing) return;
    _busy = true;
    setState(() {});
    try {
      final current = await widget.repository.readMealDraft(_day, _meal);
      if (!mounted) return;
      if (current == null) {
        setState(() {
          _busy = false;
          _conflict = false;
          _missing = true;
          _error = 'Entwurf nicht gefunden';
        });
        return;
      }
      setState(() {
        _busy = false;
        _conflict = false;
        _missing = false;
        _error = null;
        _draft = current;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Entwurf nicht geladen';
      });
    }
  }

  void _dismiss() {
    if (!mounted || _busy) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final d = _draft;
    final label = obMeals.firstWhere((m) => m.$1 == d.meal).$2;
    final large = MediaQuery.textScalerOf(context).scale(15) > 20;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final String footerLabel;
    final VoidCallback? footerAction;
    if (_missing) {
      footerLabel = 'Schließen';
      footerAction = _busy ? null : _dismiss;
    } else if (_conflict || _error == 'Entwurf nicht geladen') {
      footerLabel = 'Neu laden';
      footerAction = _busy ? null : _reload;
    } else if (_error == 'Speichern fehlgeschlagen') {
      footerLabel = 'Erneut versuchen';
      footerAction = _busy ? null : _commit;
    } else {
      footerLabel = _busy ? 'Wird gespeichert…' : 'Speichern';
      footerAction = _busy || d.entries.isEmpty ? null : _commit;
    }
    final errorColor = _missing ? p.ink : p.danger;
    return PopScope(
      canPop: !_busy,
      child: Material(
        color: p.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AlpRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: p
                              .text(18, weight: FontWeight.w600)
                              .copyWith(height: 24 / 18),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: 'Schließen',
                          onPressed: _busy ? null : _dismiss,
                          padding: EdgeInsets.zero,
                          icon: Icon(LucideIcons.x, size: 20, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_missing && _error != 'Entwurf nicht geladen')
                          for (var i = 0; i < d.entries.length; i++)
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 52),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: large ? 12 : 0,
                                ),
                                decoration: i == 0
                                    ? null
                                    : BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: p.line),
                                        ),
                                      ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        d.entries[i].label,
                                        style: p
                                            .text(15)
                                            .copyWith(height: 20 / 15),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      d.entries[i].kcal == null
                                          ? '—'
                                          : '${obNumber(d.entries[i].kcal)} kcal',
                                      style: p
                                          .text(15, weight: FontWeight.w600)
                                          .copyWith(height: 20 / 15),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        if (_error case final err?)
                          Padding(
                            padding: EdgeInsets.only(
                              top:
                                  _missing ||
                                      d.entries.isEmpty ||
                                      _error == 'Entwurf nicht geladen'
                                  ? 0
                                  : 16,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _missing
                                      ? LucideIcons.info
                                      : LucideIcons.circleAlert,
                                  size: 20,
                                  color: errorColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    err,
                                    style: p
                                        .text(14, color: errorColor)
                                        .copyWith(height: 20 / 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: large ? 64 : 48),
                  child: OBAction(
                    footerLabel,
                    ink: true,
                    onPressed: footerAction,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> showOpenBandMealDraft(
  BuildContext context,
  OpenBandRepository repository,
  MealDraft draft,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: 0.32),
  builder: (_) => OBMealDraftSheet(repository: repository, draft: draft),
);

Future<double?> showOpenBandFoodPortionSheet(
  BuildContext context,
  FoodHit hit,
) {
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    isScrollControlled: true,
    builder: (context) => _FoodPortionSheet(hit: hit),
  );
}

class _FoodPortionSheet extends StatefulWidget {
  final FoodHit hit;
  const _FoodPortionSheet({required this.hit});

  @override
  State<_FoodPortionSheet> createState() => _FoodPortionSheetState();
}

class _FoodPortionSheetState extends State<_FoodPortionSheet> {
  final _grams = TextEditingController();

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  double? _parsed() {
    final raw = _grams.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final safeBottom = media.viewPadding.bottom > media.padding.bottom
        ? media.viewPadding.bottom
        : media.padding.bottom;
    final bottom =
        (safeBottom > 34 ? safeBottom : 34.0) + media.viewInsets.bottom;
    final grams = _parsed();
    return Material(
      color: p.card,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AlpRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Text(
              widget.hit.label,
              style: p
                  .text(18, weight: FontWeight.w600)
                  .copyWith(height: 24 / 18),
            ),
            TextField(
              key: const ValueKey('food-portion-grams'),
              controller: _grams,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Menge in g',
                hintText: 'Menge wählen',
                filled: true,
                fillColor: p.well,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AlpRadius.row),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            OBAction(
              'Übernehmen',
              onPressed: grams == null
                  ? null
                  : () => Navigator.pop(context, grams),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search the local food dictionary and stage portions into a [MealDraft].
/// Returns the updated draft when the user confirms, null when dismissed.
class OBFoodSearchSheet extends StatefulWidget {
  final OpenBandRepository repository;
  final MealDraft draft;
  const OBFoodSearchSheet({
    super.key,
    required this.repository,
    required this.draft,
  });
  @override
  State<OBFoodSearchSheet> createState() => _OBFoodSearchSheetState();
}

class _OBFoodSearchSheetState extends State<OBFoodSearchSheet> {
  final _query = TextEditingController();
  late final List<MealDraftEntry> _entries = [...widget.draft.entries];
  List<FoodHit> _hits = const [];
  bool _searching = false;
  String? _searchError;
  int _searchRequest = 0;

  Future<void> _search(String q) async {
    final request = ++_searchRequest;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final hits = await widget.repository.searchFoods(q);
      if (!mounted || request != _searchRequest || _query.text != q) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || request != _searchRequest || _query.text != q) return;
      setState(() {
        _hits = const [];
        _searching = false;
        _searchError = 'Suche fehlgeschlagen';
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final label = obMeals.firstWhere((m) => m.$1 == widget.draft.meal).$2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              '$label ergänzen',
              style: p.text(18, weight: FontWeight.w700, display: true),
            ),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Lebensmittel suchen',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                filled: true,
                fillColor: p.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AlpRadius.row),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_searchError != null)
              Row(
                children: [
                  Icon(LucideIcons.circleAlert, size: 18, color: p.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _searchError!,
                      style: p.text(13, color: p.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: _searching ? null : () => _search(_query.text),
                    child: const Text('Erneut'),
                  ),
                ],
              )
            else if (_hits.isEmpty && _query.text.isNotEmpty && !_searching)
              Text(
                'Nichts gefunden. Eigene Lebensmittel lassen sich im Profil anlegen.',
                style: p.text(13, color: p.muted),
              ),
            for (final h in _hits.take(6))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  h.label,
                  style: p.text(15, weight: FontWeight.w500),
                ),
                subtitle: Text(
                  [
                    if (h.brand.isNotEmpty) h.brand,
                    h.kcal100 == null
                        ? 'ohne Nährwerte'
                        : '${obNumber(h.kcal100)} kcal / 100 g',
                  ].join(' · '),
                  style: p.text(12, color: p.muted),
                ),
                trailing: Icon(LucideIcons.plus, size: 20, color: p.action),
                onTap: () async {
                  final stored = h.servingG;
                  final grams = stored != null && stored.isFinite && stored > 0
                      ? stored
                      : await showOpenBandFoodPortionSheet(context, h);
                  if (!mounted || grams == null) return;
                  setState(() {
                    _entries.add(h.portion(newOpenBandDraftEntryId(), grams));
                  });
                },
              ),
            if (_entries.isNotEmpty)
              Text(
                '${_entries.length} im Entwurf: ${_entries.map((e) => e.label).join(', ')}',
                style: p.text(13, weight: FontWeight.w600),
              ),
            OBAction(
              'Übernehmen',
              onPressed: _entries.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      MealDraft(
                        id: widget.draft.id,
                        day: widget.draft.day,
                        meal: widget.draft.meal,
                        entries: _entries,
                        updatedAt: DateTime.now(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
