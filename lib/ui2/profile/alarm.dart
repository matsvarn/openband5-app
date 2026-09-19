// The band alarm.
//
// This screen exists because the alarm is the one thing in the app that keeps
// working when the app does not. It is armed on the STRAP's own real-time
// clock, so it survives the app being killed, the phone rebooting, and the
// phone being out of range entirely.
//
// The honesty problem is confirmation. Writing SET_ALARM to the band is not
// evidence that the band latched this arm. Events 56/59 are uncorrelated
// history, not current-request proof, even when received after a write. The
// hero shows pending/unknown unless a current correlated GET matches the
// exact stored seconds. This is stored configuration, never a firing promise;
// restart cannot restore readback evidence.
//
// A single next-occurrence time picker used to live here. It is gone: the
// weekly schedule below is now the ONLY thing that arms the band (AppState
// computes the next enabled occurrence on every connect/sync), so a second,
// independent "set one alarm" affordance would just be a second source of
// truth that the schedule engine silently overwrites on the next sync.
// The time above is [armedAt] only — the schedule cannot invent it.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../openband/alp_tokens.dart';
import '../../openband/settings_controls.dart';
import '../../openband/theme.dart';
import '../../openband/time_picker.dart';
import '../../state/alarm_schedule.dart';
import '../../ble/ble_state.dart' show AlarmReadbackState;
import '../../state/app_state.dart';

/// What we actually know about the armed alarm — and about turning it off.
enum AlarmArmState {
  /// Current correlated GET matches this SET's whole-second stored target.
  storedSeconds,

  /// Current gen5 GET coverage says all six requested slots are inactive.
  allSlotsInactive,

  /// Nothing armed. Never armed, or a previous off that is not live knowledge.
  none,

  /// Written to the band and inside the initial grace window, not confirmed.
  /// Historical lifecycle events cannot establish the current arm.
  pending,

  /// A target was written, but no current GET proves its wall-time mapping
  /// and stored seconds (including after restart). Not proof of a failed SET.
  /// Even storedSeconds is not a promise that the alarm will fire.
  unknown,

  /// DISABLE left the phone; band-off remains unconfirmed.
  offPending,

  /// Desired-off without evidence of a DISABLE write.
  offUnknown,
}

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final epoch = app.alarmEpoch;
    final state = () {
      if (app.alarmReadbackState == AlarmReadbackState.allSlotsInactive) {
        return AlarmArmState.allSlotsInactive;
      }
      if (app.alarmReadbackState == AlarmReadbackState.storedSeconds) {
        return AlarmArmState.storedSeconds;
      }
      if (app.alarmDisableOutstanding) {
        return app.alarmDisableWritten
            ? AlarmArmState.offPending
            : AlarmArmState.offUnknown;
      }
      if (epoch == null) return AlarmArmState.none;
      if (app.alarmPending) return AlarmArmState.pending;
      return AlarmArmState.unknown;
    }();
    return AlarmScreenView(
      armedAt: epoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
      state: state,
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

  // Kept context-free and @visibleForTesting: typed GET evidence describes
  // stored configuration, never an unqualified promise that the alarm fires.
  @visibleForTesting
  static String stateLabel(AlarmArmState s) => switch (s) {
        AlarmArmState.storedSeconds => 'Stored on band',
        AlarmArmState.allSlotsInactive => 'Slots inactive',
        AlarmArmState.pending => 'Waiting',
        AlarmArmState.unknown => 'Not confirmed',
        AlarmArmState.none => 'Not set',
        AlarmArmState.offPending => 'Waiting',
        AlarmArmState.offUnknown => 'Not confirmed',
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

  /// No epoch means no observed arm for SET states. Disable pending/unknown
  /// keep the last instant; uncorrelated history cannot establish band-off.
  AlarmArmState get _latch {
    switch (widget.state) {
      case AlarmArmState.allSlotsInactive:
      case AlarmArmState.offPending:
      case AlarmArmState.offUnknown:
        return widget.state;
      default:
        return widget.armedAt == null ? AlarmArmState.none : widget.state;
    }
  }

  bool get _isDisableLatch =>
      _latch == AlarmArmState.offPending ||
      _latch == AlarmArmState.offUnknown ||
      _latch == AlarmArmState.allSlotsInactive;

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final l = AppLocalizations.of(c);
    final at = widget.armedAt;
    final anyDayEnabled = widget.schedule.any((d) => d.enabled);
    final showTest =
        widget.onTest != null && at != null && !_isDisableLatch;
    final retryDisable = _latch == AlarmArmState.offPending ||
        _latch == AlarmArmState.offUnknown;
    final showCancel = widget.onCancel != null &&
        (retryDisable || (!_isDisableLatch && (at != null || anyDayEnabled)));
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
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Synthetische Daten',
                      textAlign: TextAlign.center,
                      style: p.text(12, color: p.muted),
                    ),
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
    final showLast = (_latch == AlarmArmState.offPending ||
            _latch == AlarmArmState.offUnknown) &&
        at != null;
    final blankTime = at == null || _latch == AlarmArmState.allSlotsInactive;
    final date = showLast
        ? _lastArmedLabel(c)
        : blankTime
            ? _nextAlarmLabel(c)
            : _dateLabel(c, at);
    final relative = blankTime || showLast
        ? null
        : AlarmScreenView.whichDay(
            at,
            widget.now ?? DateTime.now(),
            AppLocalizations.of(c),
          );
    return OBCard(
      padding: const EdgeInsets.all(AlpSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AlpSpace.s4,
        children: [
          Text(
            date,
            semanticsLabel: relative == null ? date : '$date. $relative',
            style: p.text(13, color: p.muted).copyWith(height: 16 / 13),
          ),
          Text(
            blankTime ? '—' : _hhmm(at),
            key: const ValueKey('alarm-hero-time'),
            style: p
                .text(48, weight: FontWeight.w700, display: true)
                .copyWith(height: 56 / 48, letterSpacing: -0.04 * 48),
          ),
          _statusLine(c, p),
          if (!widget.connected)
            Text(
              _offlineLabel(c),
              key: const ValueKey('alarm-hero-connection'),
              style: p.text(13, color: p.muted).copyWith(height: 16 / 13),
            ),
        ],
      ),
    );
  }

  Widget _statusLine(BuildContext c, OB p) {
    final stored = _latch == AlarmArmState.storedSeconds;
    return Row(
      children: [
        if (stored) ...[
          ExcludeSemantics(
            child: Icon(LucideIcons.circleCheck, size: 14, color: p.ink),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            _latchLabel(c),
            key: const ValueKey('alarm-hero-status'),
            style: p.text(13, color: p.muted).copyWith(height: 16 / 13),
          ),
        ),
      ],
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
          const SizedBox(width: AlpSpace.s8),
          Expanded(child: cancel),
        ],
      );
    });
  }

  Future<void> _pickDayTime(BuildContext c, AlarmScheduleEntry day) async {
    if (!_canWrite || widget.onSetDayTime == null) return;
    await _run(() async {
      final picked = await showOpenBandTimePicker(
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
      AlarmArmState.storedSeconds => _s(c,
          'Die gespeicherte Zeit wurde in ganzen Sekunden aus dem Band gelesen. Das ist nur die Konfiguration, keine Zusage, dass der Alarm auslöst oder vibriert.',
          'The stored time was read from the band to whole-second precision. This is configuration readback, not a promise the alarm will fire or vibrate.'),
      AlarmArmState.allSlotsInactive => _s(c,
          'Alle sechs Alarmplätze wurden in dieser Verbindung als inaktiv ausgelesen.',
          'All six alarm slots were read as inactive in this connection.'),
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
      AlarmArmState.offPending => _s(
          c,
          'Ausschalten wurde gesendet. Die Bestätigung steht noch aus.',
          'Turn-off was sent. Confirmation is still outstanding.',
        ),
      AlarmArmState.offUnknown => _s(
          c,
          'Ob das Band den Alarm ausgeschaltet hat, ist nicht bestätigt.',
          'Whether the band switched the alarm off is not confirmed.',
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
        AlarmArmState.storedSeconds => _s(c, 'Im Band gespeichert', 'Stored on band'),
        AlarmArmState.allSlotsInactive => _s(c, 'Alarmplätze im Band aus', 'Band alarm slots off'),
        AlarmArmState.pending || AlarmArmState.unknown => _pendingLabel(c),
        AlarmArmState.offPending || AlarmArmState.offUnknown =>
          _disablePendingLabel(c),
        AlarmArmState.none => _offLabel(c),
      };

  String _dateLabel(BuildContext c, DateTime at) {
    final locale = Localizations.localeOf(c).languageCode;
    return DateFormat.MMMMEEEEd(locale).format(at);
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

  String _cancelLabel(BuildContext c) {
    if (_latch == AlarmArmState.offPending ||
        _latch == AlarmArmState.offUnknown) {
      return _s(c, 'Erneut ausschalten', 'Turn off again');
    }
    return _s(
      c,
      'Ausschalten',
      'Turn off',
      l10n: (l) => l.alarmCancelTheAlarm,
    );
  }

  String _lastArmedLabel(BuildContext c) => _s(
        c,
        'Letzter gestellter Alarm',
        'Last set alarm',
      );

  String _disablePendingLabel(BuildContext c) => _s(
        c,
        'Ausschalten offen',
        'Turn-off pending',
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
