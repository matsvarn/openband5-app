// G3 Journal screen builders for the Paper and real-data review harness.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/openband/controller.dart';
import 'package:openstrap_edge/openband/domain.dart';
import 'package:openstrap_edge/openband/g3/screens/journal_screen.dart';
import 'package:openstrap_edge/openband/g3/g3_theme.dart';
import 'package:openstrap_edge/openband/synthetic_repository.dart';
import 'package:openstrap_edge/openband/tab_bar.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';

import 'env.dart';

final Map<String, G3ScreenBuilder> journalScreens = {
  for (final name in [
    'G3JournalTabLight',
    'G3JournalTabDark',
    'G3JournalScrolledLight',
    'G3JournalYesNoLight',
    'G3JournalAmountLight',
    'G3JournalNoteLight',
    'G3JournalDoneLight',
    'G3JournalSaveFailedLight',
    'G3JournalEditSheetLight',
  ])
    name: (env) => env.real && !name.contains('Tab')
        ? null
        : _JournalPreview(name: name, env: env),
  for (final name in [
    'G3JournalCustomizeLight',
    'G3JournalCustomizeDark',
    'G3JournalCustomSheetLight',
    'G3JournalCustomSheetDark',
  ])
    name: (env) => env.real ? null : _JournalPreview(name: name, env: env),
  for (final name in [
    'G3JournalPatternRefusedLight',
    'G3JournalPatternRefusedDark',
    'G3JournalPatternMatureLight',
    'G3JournalPatternMatureDark',
    'G3JournalParts',
  ])
    name: (env) => env.real ? null : _JournalPreview(name: name, env: env),
};

G3ScreenBuilder g31JournalBuilder(String legacyName) =>
    (env) => _JournalPreview(name: legacyName, env: env, g31: true);

class _JournalPreview extends StatefulWidget {
  const _JournalPreview({
    required this.name,
    required this.env,
    this.g31 = false,
  });
  final String name;
  final G3Env env;
  final bool g31;
  @override
  State<_JournalPreview> createState() => _JournalPreviewState();
}

class _JournalPreviewState extends State<_JournalPreview> {
  late final OpenBandRepository repo;
  late final OpenBandController controller;
  late final ScrollController scrollController;
  bool ready = false;
  bool _sheetOpened = false;
  @override
  void initState() {
    super.initState();
    repo = widget.env.repository(() => _syntheticRepository(widget.name));
    scrollController = ScrollController(
      initialScrollOffset: widget.name.contains('Scrolled') ? 910 : 0,
    );
    controller = OpenBandController(
      repository: repo,
      initialDay: widget.env.day('2026-09-29'),
      now: widget.env.now(() => DateTime(2026, 9, 29)),
      band: widget.env.band(
        () => BandSnapshot(
          connection: BandConnection.connected,
          batteryPercent: 64,
          latestStoredAt: DateTime(2026, 9, 29, 9, 38),
          receivedAt: DateTime(2026, 9, 29, 9, 38),
        ),
      ),
    );
    controller.refresh().then((_) {
      if (mounted) setState(() {});
    });
    initializeDateFormatting('de_DE').then((_) {
      if (mounted) setState(() => ready = true);
    });
  }

  static SyntheticOpenBandRepository _syntheticRepository(String name) {
    final summary =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/day-summary.json',
              ).readAsStringSync(),
            )
            as Map;
    final detail =
        jsonDecode(
              File(
                'docs/openband5/assets/fixtures/sleep-detail.json',
              ).readAsStringSync(),
            )
            as Map;
    summary['day'] = '2026-09-29';
    final repo = SyntheticOpenBandRepository.fromMaps(summary, detail);
    if (name.contains('Tab') || name.contains('Scrolled')) {
      repo.seedCaffeineSleepPattern(
        '2026-09-29',
        seed: SyntheticCaffeineSleepSeed.insufficient,
      );
    }
    final done = name.contains('Done') || name.contains('EditSheet');
    final amount = name.contains('Amount');
    final note = name.contains('Note');
    final saveFailed = name.contains('SaveFailed');
    final tab = name.contains('Tab') || name.contains('Scrolled');
    if (name.contains('Amount')) {
      repo.seedJournalEditor(withCustom: true);
    }
    if (done || amount || saveFailed) {
      repo.seedJournalEditor(
        day: '2026-09-28',
        filled: true,
        metrics: {
          'alcohol_evening': const JournalMetricValue(0),
          'caffeine_late': const JournalMetricValue(1),
        },
      );
    } else if (tab || note) {
      repo.seedJournalEditor(
        day: '2026-09-28',
        metrics: {
          'alcohol_evening': const JournalMetricValue(0),
          'caffeine_late': const JournalMetricValue(1),
        },
      );
    }
    if (done || amount || note) {
      repo.seedJournalEditor(
        day: '2026-09-29',
        metrics: {'mood': const JournalMetricValue(4)},
      );
    }
    if (name.contains('EditSheet')) {
      repo.seedJournalEditor(
        day: '2026-09-29',
        metrics: {'alcohol_units': const JournalMetricValue(2)},
      );
    }
    repo.seedJournalEditor(
      day: '2026-09-27',
      metrics: {
        'alcohol_evening': const JournalMetricValue(0),
        'caffeine_late': const JournalMetricValue(1),
        'mood': const JournalMetricValue(4),
      },
    );
    if (name.contains('Customize') || name.contains('CustomSheet')) {
      repo.seedJournalEditor(withCustom: true);
    }
    return repo;
  }

  @override
  void dispose() {
    scrollController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const SizedBox.shrink();
    final name = widget.name;
    final patternFrame =
        name.contains('PatternRefused') || name.contains('PatternMature');
    if (!_sheetOpened &&
        (name.contains('EditSheet') || name.contains('CustomSheet'))) {
      _sheetOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: G3.of(context).canvas,
          barrierColor: Colors.black.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .55 : .35,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (_) => name.contains('EditSheet')
              ? G3JournalAnswerSheet.forField(
                  definition: kJournalFields.firstWhere(
                    (f) => f.key == 'alcohol_units',
                  ),
                  previous: '1 unit',
                  initial: 2.0,
                  onSave: (_) async => JournalAnswerSaveResult.saved,
                )
              : G3JournalNewQuestionSheet(
                  repository: repo,
                  initialName: 'Abends gelesen',
                ),
        );
      });
    }
    final detail = name.contains('Customize') || name.contains('CustomSheet');
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          top: detail || patternFrame ? 0 : 42,
          child: patternFrame
              ? G3JournalPatternScreen(
                  pattern: G3JournalPattern(
                    CaffeineSleepPattern(
                      kind: name.contains('Refused')
                          ? CaffeineSleepPatternKind.insufficient
                          : CaffeineSleepPatternKind.meaningful,
                      pairedN: name.contains('Refused') ? 5 : 31,
                      yesNights: name.contains('Refused') ? 1 : 12,
                      noNights: name.contains('Refused') ? 4 : 19,
                      delta: name.contains('Refused') ? null : 9,
                      endDay: '2026-09-29',
                      startDay: '2026-08-16',
                      nights: 45,
                      algoVersion: 98,
                    ),
                  ),
                )
              : detail
              ? G3JournalCustomize(repository: repo)
              : G3JournalScreen(
                  controller: controller,
                  scrollController: scrollController,
                  onEdit: (_) {},
                  onBand: widget.g31 ? () {} : null,
                  onProfile: widget.g31 ? () {} : null,
                  onDataStatus: widget.g31 ? () {} : null,
                ),
        ),
        Positioned(
          top: 18,
          left: 54,
          child: Text(
            '9:41',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : Colors.black,
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 32,
          child: OBTabBar(
            domains: const [
              ShellDomain.home,
              ShellDomain.sleep,
              ShellDomain.workout,
              ShellDomain.wellness,
            ],
            selected: ShellDomain.wellness,
            onSelect: (_) {},
          ),
        ),
        Positioned(
          bottom: 8,
          left: 140,
          right: 140,
          child: Container(
            height: 5,
            decoration: BoxDecoration(
              color: dark ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ],
    );
  }
}
