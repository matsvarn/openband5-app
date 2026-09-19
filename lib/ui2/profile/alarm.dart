// The band alarm.
//
// This screen exists because the alarm is the one thing in the app that keeps
// working when the app does not. It is armed on the STRAP's own real-time
// clock, so it survives the app being killed, the phone rebooting, and the
// phone being out of range entirely.
//
// The honesty problem is confirmation. Writing SET_ALARM to the band is not
// evidence that the band latched it; the strap says so separately, by emitting
// event 56, and it might never arrive. And after a relaunch there is no live
// confirmation at all — only the epoch we wrote down. The hero says which of
// those it is rather than drawing a confident tick over all three.
//
// A single next-occurrence time picker used to live here. It is gone: the
// weekly schedule below is now the ONLY thing that arms the band (AppState
// computes the next enabled occurrence on every connect/sync), so a second,
// independent "set one alarm" affordance would just be a second source of
// truth that the schedule engine silently overwrites on the next sync.
// The time above is [armedAt] only — the schedule cannot invent it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../openband/settings_controls.dart';
import '../../openband/theme.dart';
import '../../state/alarm_schedule.dart';
import '../../state/app_state.dart';

/// What we actually know about the armed alarm.
enum AlarmArmState {
  /// Nothing armed.
  none,

  /// Written to the band; its confirmation event may still be in flight.
  pending,

  /// The band emitted ALARM_SET — it latched.
  confirmed,

  /// Armed, but unconfirmed: either the band never acknowledged the write, or
  /// this is an alarm from a previous run of the app and there is no live
  /// confirmation to read. Both mean the same thing to the user — we cannot
  /// promise it will fire — so they share one state rather than being dressed
  /// up as two.
  unknown,
}

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final epoch = app.alarmEpoch;
    return AlarmScreenView(
      armedAt: epoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
      state: epoch == null
          ? AlarmArmState.none
          : app.alarmConfirmed
              ? AlarmArmState.confirmed
              : app.alarmPending
                  ? AlarmArmState.pending
                  : AlarmArmState.unknown,
      connected: app.isConnected,
      schedule: app.alarmSchedule,
      onToggleDay: (weekday, enabled) =>
          app.setScheduleDay(weekday: weekday, enabled: enabled),
      onSetDayTime: (weekday, hour, minute) =>
          app.setScheduleDay(weekday: weekday, hour: hour, minute: minute),
      onTest: app.testAlarmBuzz,
      onCancel: app.disableAlarm,
    );
  }
}

class AlarmScreenView extends StatefulWidget {
  final DateTime? armedAt;
  final AlarmArmState state;
  final bool connected;

  /// Injectable clock. Relative labels (and goldens) must not depend on when
  /// the suite happens to run.
  final DateTime? now;

  /// Always exactly 7 entries in weekday order — see
  /// `fillDefaultAlarmSchedule` in state/alarm_schedule.dart, which is what
  /// [AppState.alarmSchedule] guarantees.
  final List<AlarmScheduleEntry> schedule;

  /// All four talk to the band or its schedule. The screen reports a failure
  /// rather than pretending the write worked. An epoch written is not
  /// band-confirmed.
  final Future<void> Function(int weekday, bool enabled)? onToggleDay;
  final Future<void> Function(int weekday, int hour, int minute)? onSetDayTime;
  final Future<void> Function()? onTest, onCancel;

  /// Gallery-only. Production never sets this.
  final bool synthetic;

  const AlarmScreenView({
    super.key,
    this.armedAt,
    this.state = AlarmArmState.none,
    this.connected = false,
    this.now,
    this.schedule = const [],
    this.onToggleDay,
    this.onSetDayTime,
    this.onTest,
    this.onCancel,
    this.synthetic = false,
  });

  // Kept context-free and @visibleForTesting: the arm-state contract this
  // guards ("only `confirmed` may claim it") is tested without a widget tree.
  @visibleForTesting
  static String stateLabel(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => 'Confirmed',
        AlarmArmState.pending => 'Waiting',
        AlarmArmState.unknown => 'Not confirmed',
        AlarmArmState.none => 'Not set',
      };

  /// Civil-day count from [from]'s calendar date to [to]'s. Local midnight
  /// [Duration.inDays] is not safe: a 23-hour spring-forward "tomorrow" is 0.
  @visibleForTesting
  static int civilDayDelta(DateTime from, DateTime to) => DateTime.utc(
        to.year,
        to.month,
        to.day,
      ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  @visibleForTesting
  static String whichDay(DateTime d, DateTime now, AppLocalizations? l) {
    final days = civilDayDelta(now, d);
    if (days < 0) {
      return l?.alarmInThePast ??
          'In der Vergangenheit — er hat bereits ausgelöst oder wurde verpasst';
    }
    if (days == 0) return l?.alarmLaterToday ?? 'Später heute';
    if (days == 1) return l?.alarmTomorrow ?? 'Morgen';
    return l?.alarmInDays(days) ?? 'In $days Tagen';
  }

  @override
  State<AlarmScreenView> createState() => _AlarmScreenViewState();
}

class _AlarmScreenViewState extends State<AlarmScreenView> {
  bool _busy = false;

  bool get _canWrite => widget.connected && !_busy;

  /// No epoch is always off, even if a stale [AlarmArmState] is still set.
  AlarmArmState get _latch =>
      widget.armedAt == null ? AlarmArmState.none : widget.state;

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final l = AppLocalizations.of(c);
    final at = widget.armedAt;
    final anyDayEnabled = widget.schedule.any((d) => d.enabled);
    final showTest = widget.onTest != null && at != null;
    final showCancel =
        widget.onCancel != null && (at != null || anyDayEnabled);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  backgroundColor: p.card,
                  foregroundColor: p.ink,
                  minimumSize: const Size(44, 44),
                  shape: const CircleBorder(),
                ),
              ),
              child: OBPageHeader(
                title: l?.alarmNavTitle ?? 'Alarm',
                subtitle: '',
                onInfo: () => _info(c),
                infoLabel: _infoLabel(c),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _hero(c, p, at),
                const SizedBox(height: 12),
                _scheduleCard(c),
                if (showTest || showCancel) ...[
                  const SizedBox(height: 12),
                  _actions(c, showTest: showTest, showCancel: showCancel),
                ],
                if (widget.synthetic) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Synthetische Daten',
                    style: p.text(12, color: p.muted),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _hero(BuildContext c, OB p, DateTime? at) {
    final date = at == null ? _nextAlarmLabel(c) : _dateLabel(c, at);
    final relative = at == null
        ? null
        : AlarmScreenView.whichDay(at, widget.now ?? DateTime.now(), AppLocalizations.of(c));
    return OBCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            date,
            semanticsLabel: relative == null ? date : '$date. $relative',
            style: p.text(13, color: p.muted),
          ),
          Text(
            at == null ? '—' : _hhmm(at),
            key: const ValueKey('alarm-hero-time'),
            style: p
                .text(48, weight: FontWeight.w700, display: true)
                .copyWith(height: 56 / 48),
          ),
          Text(
            _latchLabel(c),
            key: const ValueKey('alarm-hero-status'),
            style: p.text(13, color: p.muted),
          ),
          if (!widget.connected)
            Text(
              _offlineLabel(c),
              key: const ValueKey('alarm-hero-connection'),
              style: p.text(13, color: p.muted),
            ),
        ],
      ),
    );
  }

  Widget _scheduleCard(BuildContext c) {
    return OBCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final day in widget.schedule)
            OBScheduleTimeToggleRow(
              key: ValueKey('alarm-day-${day.weekday}'),
              weekday: _weekdayLabel(c, day.weekday),
              enabled: day.enabled,
              timeLabel: day.enabled ? _hhmmOf(day.hour, day.minute) : null,
              interactive: _canWrite,
              onToggle: widget.onToggleDay == null
                  ? null
                  : () => _run(
                        () => widget.onToggleDay!(day.weekday, !day.enabled),
                      ),
              onPickTime: widget.onSetDayTime == null
                  ? null
                  : () => _pickDayTime(c, day),
              onLabel: _onLabel(c),
              offLabel: _offLabel(c),
              timeSemanticLabel: _timeSemantic(c),
            ),
        ],
      ),
    );
  }

  Widget _actions(
    BuildContext c, {
    required bool showTest,
    required bool showCancel,
  }) {
    final test = !showTest
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: OBAction(
              AppLocalizations.of(c)?.alarmTestTheBuzz ?? 'Vibration testen',
              secondary: true,
              onPressed: !_canWrite ? null : () => _run(() => widget.onTest!()),
            ),
          );
    final cancel = !showCancel
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: OBAction(
              _cancelLabel(c),
              secondary: true,
              destructive: true,
              onPressed:
                  !_canWrite ? null : () => _run(() => widget.onCancel!()),
            ),
          );
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(15) > 20 ||
          test == null ||
          cancel == null;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?test,
            if (test != null && cancel != null) const SizedBox(height: 12),
            ?cancel,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: test),
          const SizedBox(width: 12),
          Expanded(child: cancel),
        ],
      );
    });
  }

  Future<void> _pickDayTime(BuildContext c, AlarmScheduleEntry day) async {
    if (!_canWrite || widget.onSetDayTime == null) return;
    await _run(() async {
      final picked = await showTimePicker(
        context: c,
        initialTime: TimeOfDay(hour: day.hour, minute: day.minute),
      );
      if (picked == null || !c.mounted) return;
      await widget.onSetDayTime!(day.weekday, picked.hour, picked.minute);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _say(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(BuildContext c, String msg) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

  void _info(BuildContext c) {
    final p = OB.of(c);
    showModalBottomSheet<void>(
      context: c,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheet) {
        final sp = OB.of(sheet);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Text(
                  AppLocalizations.of(sheet)?.alarmNavTitle ?? 'Alarm',
                  style: sp.text(22, weight: FontWeight.w700),
                ),
                for (final paragraph in _infoBody(sheet))
                  Text(paragraph, style: sp.text(14)),
                OBAction(
                  _closeLabel(sheet),
                  onPressed: () => Navigator.pop(sheet),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _infoBody(BuildContext c) {
    final confirmation = switch (_latch) {
      AlarmArmState.confirmed => _s(
          c,
          'Das Band hat diesen Alarm bestätigt.',
          'The band confirmed this alarm.',
          l10n: (l) => l.alarmDetailConfirmed,
        ),
      AlarmArmState.pending => _s(
          c,
          'Der Alarm wurde gesendet. Die Bestätigung steht noch aus.',
          'The alarm was sent. Confirmation is still outstanding.',
          l10n: (l) => l.alarmDetailPending,
        ),
      AlarmArmState.unknown => _s(
          c,
          'Zu diesem gespeicherten Termin liegt keine aktuelle Bestätigung vor.',
          'There is no current confirmation for this stored time.',
          l10n: (l) => l.alarmDetailUnknown,
        ),
      AlarmArmState.none => null,
    };
    return [
      _s(
        c,
        'Der Wochenplan bestimmt den nächsten Alarm am Band.',
        'The weekly plan determines the next alarm on the band.',
      ),
      ?confirmation,
      _s(
        c,
        'Zum Ändern ist eine Verbindung nötig. Ein gestellter Alarm läuft auch ohne Telefon.',
        'A connection is required to change it. An armed alarm still runs without the phone.',
        l10n: (l) => l.alarmNotConnectedBody,
      ),
    ];
  }

  String _latchLabel(BuildContext c) => switch (_latch) {
        AlarmArmState.confirmed => _confirmedLabel(c),
        AlarmArmState.pending || AlarmArmState.unknown => _pendingLabel(c),
        AlarmArmState.none => _offLabel(c),
      };

  String _dateLabel(BuildContext c, DateTime at) {
    final weekday = _weekdayLabel(c, at.weekday - 1);
    final dd = at.day.toString().padLeft(2, '0');
    final mm = at.month.toString().padLeft(2, '0');
    return '$weekday $dd.$mm.';
  }

  static String _hhmm(DateTime d) => _hhmmOf(d.hour, d.minute);

  static String _hhmmOf(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static const _weekdaysDe = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  String _weekdayLabel(BuildContext c, int weekday) {
    final l = AppLocalizations.of(c);
    if (l == null) return _weekdaysDe[weekday];
    return [
      l.homeWeekdayMonday,
      l.homeWeekdayTuesday,
      l.homeWeekdayWednesday,
      l.homeWeekdayThursday,
      l.homeWeekdayFriday,
      l.homeWeekdaySaturday,
      l.homeWeekdaySunday,
    ][weekday];
  }

  String _offLabel(BuildContext c) =>
      AppLocalizations.of(c)?.stateOff ?? 'Aus';

  String _onLabel(BuildContext c) =>
      AppLocalizations.of(c)?.stateOn ?? 'An';

  String _confirmedLabel(BuildContext c) => _s(
        c,
        'Am Band bestätigt',
        'Confirmed on the band',
        l10n: (l) => l.alarmHeadlineConfirmed,
      );

  String _pendingLabel(BuildContext c) => _s(
        c,
        'Bestätigung offen',
        'Confirmation pending',
        l10n: (l) => _latch == AlarmArmState.unknown
            ? l.alarmHeadlineUnknown
            : l.alarmHeadlinePending,
      );

  String _offlineLabel(BuildContext c) => _s(
        c,
        'Nicht verbunden',
        'Not connected',
        l10n: (l) => l.alarmNotConnectedTitle,
      );

  String _nextAlarmLabel(BuildContext c) => _s(
        c,
        'Nächster Alarm',
        'Next alarm',
        l10n: (l) => l.alarmHeadlineNone,
      );

  String _cancelLabel(BuildContext c) => _s(
        c,
        'Ausschalten',
        'Turn off',
        l10n: (l) => l.alarmCancelTheAlarm,
      );

  String _closeLabel(BuildContext c) => _s(c, 'Schließen', 'Close');

  String _infoLabel(BuildContext c) => _s(
        c,
        'Alarm: Plan und Bestätigung',
        'Alarm: schedule and confirmation',
        l10n: (l) => l.alarmNavTitle,
      );

  String _timeSemantic(BuildContext c) => _s(c, 'Uhrzeit', 'Time');

  /// Paper DE/EN; other locales keep the old ARB string when a matching key
  /// exists. No new keys.
  String _s(
    BuildContext c,
    String de,
    String en, {
    String? Function(AppLocalizations)? l10n,
  }) {
    final loc = AppLocalizations.of(c);
    final code = Localizations.maybeLocaleOf(c)?.languageCode ?? 'de';
    if (l10n != null && loc != null && code != 'de' && code != 'en') {
      return l10n(loc) ?? en;
    }
    return code == 'de' ? de : en;
  }
}
