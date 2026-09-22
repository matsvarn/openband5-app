import 'package:flutter/foundation.dart';
import '../data/day_label.dart';
import 'domain.dart';

class OpenBandController extends ChangeNotifier {
  final OpenBandRepository repository;
  final Future<void> Function(String)? persistDay;

  /// Wall clock for "today" decisions (calendar bounds, the Heute title).
  /// Injectable so goldens do not move when the date rolls over.
  final DateTime Function() now;
  String selectedDay;
  OpenBandDay? day;
  BandSnapshot band;
  Object? loadError;
  bool loading = false;
  int _request = 0;
  bool _disposed = false;
  final Set<String> _calculating = {};
  final Map<String, SleepCorrection> _queued = {};
  final Set<String> _napCalculating = {};
  final Map<String, int> _queuedNap = {};
  Future<void> _persistWrite = Future.value();
  final Map<String, String> calculationErrors = {};
  final Map<String, String> napCalculationErrors = {};

  OpenBandController({
    required this.repository,
    String? initialDay,
    this.persistDay,
    this.band = const BandSnapshot(),
    this.now = DateTime.now,
  }) : selectedDay = initialDay ?? todayLabel();

  bool get calculating => _calculating.contains(selectedDay);
  int get refreshRequest => _request;
  bool get napCalculating => _napCalculating.contains(selectedDay);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> selectDay(String value) async {
    if (value == selectedDay) return;
    selectedDay = value;
    day = null;
    final persisted = _persistWrite = _persistWrite
        .catchError((Object _) {})
        .then((_) async {
          await persistDay?.call(value);
        });
    await refresh();
    await persisted;
    if (selectedDay != value || _disposed) return;
    final correction = day?.correction;
    if (correction?.state == CorrectionState.pending) {
      await calculate(correction!);
    }
  }

  void updateBand(BandSnapshot value) {
    band = value;
    _notify();
  }

  Future<void> refresh() async {
    final request = ++_request;
    final date = selectedDay;
    loading = true;
    loadError = null;
    _notify();
    try {
      final result = await repository.readDay(date);
      if (request == _request && !_disposed) day = result;
    } catch (e) {
      if (request == _request) loadError = e;
    } finally {
      if (request == _request) {
        loading = false;
        _notify();
      }
    }
  }

  Future<SleepCorrection> save(SleepDraft draft) async {
    final correction = await repository.saveCorrection(draft);
    if (draft.day == selectedDay) await refresh();
    return correction;
  }

  Future<void> calculate(SleepCorrection correction) async {
    if (!_calculating.add(correction.day)) {
      _queued[correction.day] = correction;
      return;
    }
    calculationErrors.remove(correction.day);
    _notify();
    try {
      await repository.recalculate(correction);
    } catch (_) {
      calculationErrors[correction.day] =
          'Die Zeiten sind gespeichert. Die Auswertung konnte nicht abgeschlossen werden.';
    } finally {
      _calculating.remove(correction.day);
      if (correction.day == selectedDay && !_disposed) await refresh();
      _notify();
      final next = _queued.remove(correction.day);
      if (next != null &&
          (next.id != correction.id || next.revision != correction.revision)) {
        await calculate(next);
      }
    }
  }

  Future<void> calculateNaps({required String day, required int revision}) async {
    if (!_napCalculating.add(day)) {
      _queuedNap[day] = revision;
      return;
    }
    napCalculationErrors.remove(day);
    _notify();
    try {
      await repository.recalculateNaps(day: day, revision: revision);
    } catch (_) {
      napCalculationErrors[day] = 'Gespeichert · Auswertung offen';
    } finally {
      _napCalculating.remove(day);
      if (day == selectedDay && !_disposed) await refresh();
      _notify();
      final next = _queuedNap.remove(day);
      if (next != null && next != revision) {
        await calculateNaps(day: day, revision: next);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
