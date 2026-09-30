// DAY STEPS — when the day's steps were counted, and by what.
//
// The day total on Home is a sum of SPANS: each stretch of the day goes to the
// sensor that was actually recording it, overlaps are counted once, and the
// rest of the day is not counted at all. That resolution has never been
// visible anywhere — the tile can say "Strap + phone" in two words and stops
// there. This is the screen that shows the stretches.
//
// WHY THE SOURCE IS THE POINT, and not a footnote on it. The two counters are
// not two readings of one quantity. Measured against camera-annotated free
// living (docs/internal/OXWALK_VALIDATION.md), a wrist reads a real walk about
// a quarter low and can read rhythmic hand work as walking — its error runs
// both ways and has no ceiling above. The same class of counter carried at the
// trunk barely over-counts at all. So a strap-counted hour and a phone-counted
// hour are different kinds of number, and the one place a user could ever learn
// that is here, beside the spans themselves.
//
// It is ONE line, in the frame's footnote, phrased for whichever sensors
// actually counted this day — not a warning per span, not a percentage beside
// every number, not a modal. No numbers from that study appear on screen: a
// "33% error" printed against today's count would be read as a correction the
// user could apply, and it is not one (the error changes sign with the
// activity, which is exactly why no gain fixes it).
//
// What this screen deliberately does NOT do: no goal, no target, no comparison
// with yesterday, no streak. It answers one question — where did today's steps
// come from — and the trend lives one screen up.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../profile/devices.dart' show bandLabelFor;
import 'metric_detail.dart' show pickDay;

/// One resolved stretch of the day.
class DayStepSpan {
  const DayStepSpan({
    required this.startTs,
    required this.endTs,
    required this.steps,
    required this.fromBand,
    this.activity,
  });

  final int startTs, endTs, steps;

  /// The band's own 100 Hz pedometer (as opposed to the phone's).
  final bool fromBand;

  /// The session type this span sits inside, when it sits inside one. Null is
  /// the ordinary case: a step count is not an activity, and the phone's hourly
  /// windows are not bouts.
  final String? activity;
}

class DayStepsData {
  const DayStepsData({
    this.day,
    this.days = const [],
    this.spans = const [],
    this.total = 0,
    this.strap = 0,
    this.phone = 0,
    this.dayTotal,
    this.daySource,
    this.note,
    this.bandLabel = _defaultBand,
  });

  /// The fallback name for the strap. Nothing is paired, or the link has not
  /// said which generation it is this process — either way, naming a model we
  /// were not told is a guess.
  static const _defaultBand = 'Your band';

  /// The day these spans belong to, and every derived day this install has —
  /// newest first, which is what [DayNav] steers over.
  final String? day;
  final List<String> days;

  final List<DayStepSpan> spans;

  /// The spans' own totals, from the ladder. Not re-summed here.
  final int total, strap, phone;

  /// What the day actually published, and off which sensor. Usually [total] —
  /// but a day whose only counter was the strap's on-chip one publishes a
  /// whole-day figure with no times behind it, and therefore no spans.
  final int? dayTotal;
  final String? daySource;

  /// The bundle's own reason for an absent count. Never a sentence written
  /// here.
  final String? note;

  /// The paired band's name, in the same words the Devices screen uses —
  /// or [_defaultBand] when nothing has told us which band it is.
  final String bandLabel;

  bool get mixed => strap > 0 && phone > 0;

  static Future<DayStepsData> load(
    LocalRepository repo, {
    String bandLabel = _defaultBand,
    String? want,
  }) async {
    final days = await repo.availableDays();
    final day = pickDay(days, want, todayLabel()) ?? todayLabel();
    final d = await repo.getDaySteps(day);
    return DayStepsData(
      day: day,
      days: days,
      spans: [
        for (final s in (d['spans'] as List? ?? const []))
          if (s is Map &&
              s['start_ts'] is num &&
              s['end_ts'] is num &&
              s['steps'] is num)
            DayStepSpan(
              startTs: (s['start_ts'] as num).toInt(),
              endTs: (s['end_ts'] as num).toInt(),
              steps: (s['steps'] as num).toInt(),
              fromBand: s['source'] != 'phone',
              activity: s['activity'] as String?,
            ),
      ],
      total: (d['total'] as num?)?.toInt() ?? 0,
      strap: (d['strap'] as num?)?.toInt() ?? 0,
      phone: (d['phone'] as num?)?.toInt() ?? 0,
      dayTotal: (d['day_total'] as num?)?.toInt(),
      daySource: d['day_source'] as String?,
      note: d['note'] as String?,
      bandLabel: bandLabel,
    );
  }
}

/// 24 hourly buckets, one list per sensor, apportioned across the hours each
/// span covers.
///
/// Walked a minute at a time rather than by arithmetic on hour offsets, so the
/// two days a year that are 23 or 25 hours long put their steps in the hour
/// they happened in.
///
/// Splitting a span's steps across hours by TIME is the resolver's own model,
/// not a new claim: `resolveDaySteps` already apportions by shared time when it
/// settles an overlap. Nothing is invented — a span's steps stay inside the
/// span's own extent.
(List<double?>, List<double?>) hourlySteps(List<DayStepSpan> spans) {
  final band = List<double>.filled(24, 0);
  final phone = List<double>.filled(24, 0);
  for (final s in spans) {
    final dur = s.endTs - s.startTs;
    if (dur <= 0) continue;
    for (var t = s.startTs; t < s.endTs; t += 60) {
      final secs = (s.endTs - t).clamp(0, 60);
      final h = DateTime.fromMillisecondsSinceEpoch(t * 1000).hour;
      final share = s.steps * secs / dur;
      if (s.fromBand) {
        band[h] += share;
      } else {
        phone[h] += share;
      }
    }
  }
  // ONE BAR PER HOUR, in the colour of the sensor that counted most of it.
  // Two overlaid bars would hide the shorter one behind the taller, which is
  // the one thing a source chart may not do. The hour's height is still every
  // step counted in it, and the rows below carry the exact spans.
  final a = List<double?>.filled(24, null);
  final b = List<double?>.filled(24, null);
  for (var h = 0; h < 24; h++) {
    final sum = band[h] + phone[h];
    if (sum < .5) continue; // never measured — a hole, not a zero
    if (band[h] >= phone[h]) {
      a[h] = sum;
    } else {
      b[h] = sum;
    }
  }
  return (a, b);
}

/// Contiguous stretches from the SAME sensor, read as one.
///
/// The phone banks one row per HOUR, so a measured real day arrives as
/// seventeen phone rows that each say the same thing: seventeen lines of "your
/// phone" is the "too much on one screen" failure, not disclosure. Adjacent
/// hours from one sensor ARE one stretch of coverage.
///
/// Three things stop a merge, and each is information the list would otherwise
/// destroy: a GAP (an hour nothing covered), a stretch the OTHER sensor counted
/// starting inside the joined window (a walk the strap saw must never end up
/// buried inside a phone row that spans it), and a different session name. The
/// chart is drawn from the unmerged spans, so this changes what is listed and
/// never what is plotted.
List<DayStepSpan> mergeAdjacent(List<DayStepSpan> spans) {
  final out = <DayStepSpan>[];
  for (final s in spans) {
    final last = out.isEmpty ? null : out.last;
    final crossed = last != null &&
        spans.any((o) =>
            o.fromBand != s.fromBand &&
            o.startTs >= last.startTs &&
            o.startTs < s.endTs);
    if (last != null &&
        last.fromBand == s.fromBand &&
        last.activity == s.activity &&
        s.startTs <= last.endTs &&
        !crossed) {
      out[out.length - 1] = DayStepSpan(
        startTs: last.startTs,
        endTs: s.endTs > last.endTs ? s.endTs : last.endTs,
        steps: last.steps + s.steps,
        fromBand: s.fromBand,
        activity: s.activity,
      );
    } else {
      out.add(s);
    }
  }
  return out;
}

/// The paired band's name, in the Devices screen's own words — or null when
/// nothing is paired or the link has not said which generation it is.
///
/// It names the band that is paired NOW. A day's coverage rows do not record
/// which strap wrote them, so on the (rare) day someone swaps bands mid-day
/// this is the current one's name for both. The alternative is to name none of
/// them, which loses the thing the screen exists to say.
String bandLabel(BuildContext c) {
  final fallback =
      AppLocalizations.of(c)?.dayStepsYourBand ?? DayStepsData._defaultBand;
  try {
    final app = c.read<AppState>();
    if (!app.isPaired) return fallback;
    // The registry's own label for the band that is paired. A family with no
    // entry — an import, a pre-stamp row, an adapter this build does not carry
    // — is NOT a WHOOP 4, which is what the ternary here used to publish.
    return bandLabelFor(app.device.generation) ?? fallback;
  } catch (_) {
    return fallback;
  }
}
