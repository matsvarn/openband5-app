import '../data/day_label.dart';
import 'domain.dart' show significantSleepGap;
import 'g3/g3_format.dart' show g3Clock;
import 'g3_data.dart';

class TodayNoteAction {
  const TodayNoteAction(this.label, this.sub, this.reminderAt);
  final String label, sub;
  final DateTime reminderAt;
}

class TodayNote {
  const TodayNote(this.headline, this.reason, {this.action});
  final String headline, reason;
  final TodayNoteAction? action;
}

String _sleepLength(int minutes) =>
    '${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}';

String _deficitLength(int minutes) =>
    minutes >= 60 ? _sleepLength(minutes) : '$minutes Min.';

DateTime _roundedBedtime(DateTime bedtime) {
  final minute = ((bedtime.minute / 5).round() * 5);
  return DateTime(
    bedtime.year,
    bedtime.month,
    bedtime.day,
    bedtime.hour,
    minute,
  );
}

/// A note can describe only the current derived day and available inputs.
TodayNote? todayNote({
  required String derivedDay,
  required DateTime now,
  required double? recovery,
  required G3Baseline recoveryBaseline,
  required int? sleepMinutes,
  required int? sleepGoalMinutes,
  required double? sleepNeedMinutes,
  required DateTime? suggestedBedtime,
  required DateTime? suggestedWake,
  double? sleepUnobservedMinutes,
}) {
  if (derivedDay != todayLabel(now)) return null;
  final sentences = <String>[];
  final facts = <String>[];
  final range = recoveryBaseline.status.phase == BaselinePhase.trusted
      ? recoveryBaseline.range
      : null;
  if (recovery != null && range != null) {
    if (recovery > range.high) {
      sentences.add('Besser erholt als üblich.');
      facts.add('Erholung über deinem Bereich');
    } else if (recovery >= range.median) {
      sentences.add('Gut erholt.');
      facts.add('Erholung über Median');
    } else if (recovery >= range.low) {
      sentences.add('Normal erholt.');
      facts.add('Erholung unter Median');
    } else {
      sentences.add('Weniger erholt als üblich.');
      facts.add('Erholung unter deinem Bereich');
    }
  }
  TodayNoteAction? action;
  if (sleepMinutes != null &&
      sleepGoalMinutes != null &&
      sleepNeedMinutes != null &&
      suggestedBedtime != null &&
      suggestedWake != null &&
      significantSleepGap(sleepUnobservedMinutes) == null &&
      sleepMinutes < sleepGoalMinutes - 15) {
    sentences.add('Heute früher ins Bett.');
    facts.add(
      'Schlaf ${_deficitLength(sleepGoalMinutes - sleepMinutes)} unter Ziel',
    );
    final displayedBedtime = _roundedBedtime(suggestedBedtime);
    action = TodayNoteAction(
      '${g3Clock(displayedBedtime)} ins Bett',
      'für ${_sleepLength(sleepNeedMinutes.round())} Schlafbedarf bis ${g3Clock(suggestedWake)}',
      displayedBedtime.subtract(const Duration(minutes: 15)),
    );
  }
  if (sentences.isEmpty) return null;
  final needed = recoveryBaseline.status.nightsNeeded;
  if (recoveryBaseline.status.phase == BaselinePhase.building &&
      recoveryBaseline.status.nightsHave != null &&
      needed != null) {
    facts.add('Erholung ab Nacht $needed');
  }
  return TodayNote(sentences.join(' '), '${facts.join(', ')}.', action: action);
}
