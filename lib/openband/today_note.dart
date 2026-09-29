import '../data/day_label.dart';
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

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _sleepLength(int minutes) =>
    '${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}';

/// A note can describe only the current derived day and available inputs.
TodayNote? todayNote({
  required String derivedDay,
  required DateTime now,
  required double? recovery,
  required G3Baseline recoveryBaseline,
  required int? sleepMinutes,
  required int? sleepGoalMinutes,
  required DateTime? suggestedBedtime,
  required DateTime? suggestedWake,
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
      suggestedBedtime != null &&
      sleepMinutes < sleepGoalMinutes - 15) {
    sentences.add('Heute früher ins Bett.');
    facts.add('Schlaf ${sleepGoalMinutes - sleepMinutes} Min. unter Ziel');
    if (suggestedWake != null) {
      action = TodayNoteAction(
        '${_clock(suggestedBedtime)} ins Bett',
        'für ${_sleepLength(sleepGoalMinutes)} Schlaf bis ${_clock(suggestedWake)}',
        suggestedBedtime,
      );
    }
  }
  if (sentences.isEmpty) return null;
  final needed = recoveryBaseline.status.nightsNeeded;
  if (recoveryBaseline.status.phase == BaselinePhase.building &&
      needed != null) {
    facts.add('Erholung ab Nacht $needed');
  }
  return TodayNote(sentences.join(' '), facts.join(', '), action: action);
}
