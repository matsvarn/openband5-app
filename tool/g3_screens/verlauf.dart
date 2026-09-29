// Synthetic G3 Verlauf screen builders for the Paper diff harness.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/charts.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/g3/screens/verlauf.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

import 'env.dart';

const _day = '2026-09-29';

_PaperVerlaufRepository _repo(SyntheticScenario scenario) {
  initializeDateFormatting('de_DE');
  Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
    jsonDecode(File('docs/openband5/assets/fixtures/$name').readAsStringSync())
        as Map,
  );
  return _PaperVerlaufRepository(
    fixture('day-summary.json'),
    fixture('sleep-detail.json'),
    scenario: scenario,
  );
}

/// The screen artboards have denser historical rows than the shared daily
/// fixture. These extra values exist only in the synthetic diff gallery.
class _PaperVerlaufRepository extends SyntheticOpenBandRepository {
  _PaperVerlaufRepository(super.summary, super.detail, {super.scenario})
    : super.fromMaps();

  static const _recovery = <double?>[
    66,
    62,
    65,
    72,
    65,
    67,
    68,
    64,
    62,
    70,
    75,
    null,
    null,
    null,
    70,
    71,
    64,
    64,
    67,
    69,
    72,
    66,
    64,
    66,
    55,
    62,
    71,
    49,
    63,
    74,
  ];
  static const _hrv = <double?>[
    44,
    46,
    42,
    47,
    45,
    43,
    49,
    46,
    44,
    41,
    45,
    47,
    50,
    46,
    43,
    36,
    42,
    45,
    47,
    44,
    46,
    43,
    45,
    44,
    41,
    46,
    50,
    42,
    45,
    48,
  ];
  static const _skin = <double?>[
    .1,
    -.1,
    0,
    .2,
    .1,
    -.2,
    0,
    .1,
    .3,
    .2,
    -.1,
    0,
    .1,
    -.3,
    -.1,
    0,
    .2,
    .5,
    .6,
    .3,
    .1,
    0,
    -.1,
    .1,
    0,
    -.2,
    .1,
    0,
    .1,
    .4,
  ];

  @override
  Future<G3Baseline> readPersonalRange(G3Metric metric, String day) {
    if (metric == G3Metric.respRate) {
      return Future.value(
        const G3Baseline(
          BaselineStatus(
            BaselinePhase.building,
            nightsHave: 4,
            nightsNeeded: 14,
          ),
        ),
      );
    }
    return super.readPersonalRange(metric, day);
  }

  @override
  Future<G3Trend> readTrend(G3Metric metric, String endDay, int days) async {
    final labels = g3DaysEnding(endDay, days);
    List<double?>? values;
    if (metric == G3Metric.recovery) {
      values = days == 90
          ? [...List<double?>.filled(60, null), ..._recovery]
          : _recovery.sublist(30 - days);
    } else if (metric == G3Metric.hrv) {
      values = days == 90
          ? [...List<double?>.filled(60, null), ..._hrv]
          : _hrv.sublist(30 - days);
    } else if (metric == G3Metric.skinTempZ) {
      values = days == 90
          ? [...List<double?>.filled(60, null), ..._skin]
          : _skin.sublist(30 - days);
    } else if (metric == G3Metric.respRate) {
      values = [
        ...List<double?>.filled(days - 4, null),
        15.8,
        15.9,
        15.7,
        15.8,
      ];
    } else if (metric == G3Metric.rhr) {
      values = [
        for (var i = 0; i < days; i++)
          if ((days - i >= 54 && days - i <= 60) ||
              (days - i >= 18 && days - i <= 20))
            null
          else if (i == 17)
            51
          else if (i == days - 4)
            59
          else if (i == days - 2)
            60
          else if (i == days - 1)
            54
          else
            55 +
                (i % 7 == 0
                        ? 2
                        : i % 5 == 0
                        ? -2
                        : 0)
                    .toDouble(),
      ];
    }
    if (values == null) return super.readTrend(metric, endDay, days);
    return g3Trend(metric, [
      for (var i = 0; i < labels.length; i++) MetricPoint(labels[i], values[i]),
    ], await readPersonalRange(metric, endDay));
  }

  @override
  Future<G3Weight> readG3Weight(String endDay, int days) async {
    const entries = <(String, double)>[
      ('2026-07-02', 81.6),
      ('2026-07-10', 81.1),
      ('2026-07-17', 81.3),
      ('2026-07-25', 80.8),
      ('2026-08-02', 80.9),
      ('2026-08-10', 80.4),
      ('2026-08-18', 80.6),
      ('2026-08-26', 80.1),
      ('2026-09-03', 80.2),
      ('2026-09-10', 79.8),
      ('2026-09-16', 79.9),
      ('2026-09-20', 79.0),
      ('2026-09-27', 78.9),
      ('2026-09-29', 78.4),
    ];
    return G3Weight(
      buildWeightHistory(
        endDay: endDay,
        days: days,
        rows: [
          for (final e in entries)
            WeightStoredRow(
              date: e.$1,
              value: e.$2,
              atMinuteOfDay: e.$1 == '2026-09-29' ? 425 : 440,
            ),
        ],
      ),
      {
        for (final e in entries)
          e.$1: e.$1 == '2026-09-29'
              ? G3WeightSource.manual
              : G3WeightSource.imported,
      },
    );
  }
}

Widget _frame(Widget child) => Builder(
  builder: (context) {
    final g = G3.of(context);
    return Stack(
      children: [
        Positioned.fill(top: 48, bottom: 95, child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 48,
          child: ColoredBox(
            color: g.page,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(44, 15, 28, 0),
              child: Row(
                children: [
                  Text('9:41', style: g.t(17, 21, weight: FontWeight.w700)),
                  const Spacer(),
                  Icon(LucideIcons.signal, size: 17, color: g.ink),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.wifi, size: 17, color: g.ink),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.batteryFull, size: 22, color: g.ink),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 24,
          child: OBTabBar(
            domains: const [
              ShellDomain.home,
              ShellDomain.sleep,
              ShellDomain.workout,
              ShellDomain.wellness,
            ],
            selected: ShellDomain.home,
            onSelect: (_) {},
          ),
        ),
      ],
    );
  },
);

Widget _metric(G3Env env, G3Metric metric, {OBTrendPeriod? period}) {
  _PaperVerlaufRepository? synthetic;
  _PaperVerlaufRepository sample() =>
      synthetic ??= _repo(SyntheticScenario.g3Sample);
  final child = G3MetricDetail(
    metric: metric,
    repository: env.repository(sample),
    endDay: env.day(_day),
    band: env.band(() => sample().band),
    initialPeriod: period,
  );
  return env.real ? child : _frame(child);
}

class _WeightSheetPreview extends StatefulWidget {
  const _WeightSheetPreview({required this.repo, required this.day, this.band});
  final OpenBandRepository repo;
  final String day;
  final BandSnapshot? band;
  @override
  State<_WeightSheetPreview> createState() => _WeightSheetPreviewState();
}

class _WeightSheetPreviewState extends State<_WeightSheetPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final base = await widget.repo.readJournalDay(widget.day);
      await widget.repo.patchJournalDay(
        JournalDayPatch.fromBase(
          base,
          metrics: {
            kWeightJournalField: const JournalMetricValue(
              78.4,
              atMinuteOfDay: 425,
            ),
          },
        ),
      );
      if (mounted) openG3WeightEntry(context, widget.repo, widget.day);
    });
  }

  @override
  Widget build(BuildContext context) => G3WeightDetail(
    repository: widget.repo,
    endDay: widget.day,
    band: widget.band,
  );
}

Widget _weight(G3Env env) {
  _PaperVerlaufRepository? synthetic;
  _PaperVerlaufRepository sample() =>
      synthetic ??= _repo(SyntheticScenario.g3Sample);
  final child = G3WeightDetail(
    repository: env.repository(sample),
    endDay: env.day(_day),
    band: env.band(() => sample().band),
  );
  return env.real ? child : _frame(child);
}

Widget _allMetrics(G3Env env) {
  _PaperVerlaufRepository? synthetic;
  _PaperVerlaufRepository sample() =>
      synthetic ??= _repo(SyntheticScenario.g3Sample);
  final child = G3AllMetrics(
    repository: env.repository(sample),
    endDay: env.day(_day),
    band: env.band(() => sample().band),
  );
  return env.real ? child : _frame(child);
}

Widget _weightSheet(G3Env env) {
  final sample = _repo(SyntheticScenario.g3Sample);
  return _frame(
    _WeightSheetPreview(
      repo: env.repository(() => sample),
      day: env.day(_day),
      band: env.band(() => sample.band),
    ),
  );
}

final Map<String, G3ScreenBuilder> verlaufScreens = {
  'verlauf-erholung-30-tage-hell': (env) => _metric(env, G3Metric.recovery),
  'verlauf-erholung-30-tage-dunkel': (env) => _metric(env, G3Metric.recovery),
  'verlauf-hrv-hell': (env) => _metric(env, G3Metric.hrv),
  'verlauf-atemfrequenz-weniger-als-7-werte-hell': (env) => env.real
      ? null
      : _metric(env, G3Metric.respRate, period: OBTrendPeriod.d7),
  'verlauf-ruhepuls-90-tage-mit-luecken-hell': (env) =>
      _metric(env, G3Metric.rhr, period: OBTrendPeriod.d90),
  'verlauf-hauttemperatur-abweichung-hell': (env) =>
      _metric(env, G3Metric.skinTempZ),
  'verlauf-gewicht-hell': _weight,
  'verlauf-gewicht-eintrag-hell': (env) => env.real ? null : _weightSheet(env),
  'verlauf-alle-messwerte-hell': _allMetrics,
  'verlauf-alle-messwerte-dunkel': _allMetrics,
};
