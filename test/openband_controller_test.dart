import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';

class _Repository implements OpenBandRepository {
  final reads = <String, Completer<OpenBandDay>>{};
  final calculations = <String, Completer<void>>{};
  @override
  Future<OpenBandDay> readDay(String day) =>
      reads[day]?.future ?? Future.value(OpenBandDay(day: day));
  @override
  Future<void> recalculate(SleepCorrection correction) =>
      (calculations[correction.id] ??= Completer<void>()).future;
  @override
  Future<SleepDraft?> readDraft(String day) async => null;
  @override
  Future<void> saveDraft(SleepDraft draft) async {}
  @override
  Future<void> discardDraft(String day) async {}
  @override
  Future<Set<String>> sleepDays() async => {};
  @override
  Future<SleepCorrection> saveCorrection(SleepDraft draft) =>
      throw UnimplementedError();
  @override
  Future<void> restoreAutomatic(String day) async {}
}

void main() {
  test(
    'late date reads cannot replace or persist an older selection',
    () async {
      final repository = _Repository();
      repository.reads['2026-09-14'] = Completer<OpenBandDay>();
      repository.reads['2026-09-13'] = Completer<OpenBandDay>();
      final persisted = <String>[];
      final controller = OpenBandController(
        repository: repository,
        initialDay: '2026-09-15',
        persistDay: (day) async => persisted.add(day),
      );
      addTearDown(controller.dispose);
      final older = controller.selectDay('2026-09-14');
      final newer = controller.selectDay('2026-09-13');
      repository.reads['2026-09-13']!.complete(
        const OpenBandDay(day: '2026-09-13'),
      );
      await newer;
      repository.reads['2026-09-14']!.complete(
        const OpenBandDay(day: '2026-09-14'),
      );
      await older;
      expect(controller.day?.day, '2026-09-13');
      expect(controller.selectedDay, '2026-09-13');
      expect(persisted.last, '2026-09-13');
    },
  );
  test(
    'a newer correction runs after an older in-flight calculation',
    () async {
      final repository = _Repository();
      final controller = OpenBandController(
        repository: repository,
        initialDay: '2026-09-15',
      );
      addTearDown(controller.dispose);
      SleepCorrection correction(String id, int revision) => SleepCorrection(
        id: id,
        revision: revision,
        day: '2026-09-15',
        onset: DateTime(2026, 9, 14, 23),
        wake: DateTime(2026, 9, 15, 7),
        savedAt: DateTime(2026, 9, 15, 8),
        state: CorrectionState.pending,
      );
      final first = controller.calculate(correction('first', 1));
      await controller.calculate(correction('second', 2));
      expect(repository.calculations.keys, ['first']);
      repository.calculations['first']!.completeError(
        StateError('stale revision'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.calculations.keys, ['first', 'second']);
      repository.calculations['second']!.complete();
      await first;
      expect(controller.calculating, isFalse);
      expect(controller.calculationErrors, isEmpty);
    },
  );
}
