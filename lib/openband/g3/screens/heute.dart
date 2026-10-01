// G3 · Heute (Paper page G3 · Heute, p-17-0).
//
// One lead number (Erholung on the personal range), Schlaf and Belastung,
// the rule-based Für-heute note with its opt-in reminder, activities, the
// check-in, the week strip, the night, body values and steps. Every value
// comes from the repository; a missing input renders "—" or a refusal.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../../data/journal_fields.dart' show JournalFieldKind;
import '../../../notify/notification_center.dart';
import '../../../state/prefs.dart';
import '../../controller.dart';
import '../../day_picker.dart';
import '../../domain.dart';
import '../../journal_fields.dart'
    show journalFieldTitle, journalFieldUnitLabel;
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../../today_note.dart';
import '../chrome.dart';
import '../check_in.dart';
import '../count_copy.dart';
import '../day.dart';
import '../g3_format.dart';
import '../g3_theme.dart';
import '../heute_parts.dart'
    show OBYesNoKeys, OBRatingKeys, OBCountAnswer, OBNoteAnswer;
import '../metrics.dart';
import '../sport.dart';

/// An armed bedtime reminder: its instant and the day whose note armed it.
typedef ArmedBedtime = ({DateTime at, String day});

/// The bedtime reminder behind "Erinnern". Injectable for tests; the default
/// arms the one-shot through NotificationCenter and remembers it in Prefs.
abstract class HeuteReminder {
  /// The stored reminder, also one whose time has passed.
  Future<ArmedBedtime?> armed();

  /// Arms [at] for the note of [day]; anything but scheduled armed nothing.
  Future<BedtimeReminderResult> arm(DateTime at, String day, String body);

  /// Cancels the one-shot and forgets it.
  Future<void> cancel();
}

class NotificationHeuteReminder implements HeuteReminder {
  const NotificationHeuteReminder();
  static const _key = 'ui.openband.bedtimeReminder';

  @override
  Future<ArmedBedtime?> armed() async {
    await Prefs.ensureLoaded();
    final raw = Prefs.getString(_key, '');
    if (raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.parse(m['at'] as String);
      return (at: at, day: m['day'] as String);
    } catch (_) {
      // An unreadable entry has no day to belong to: report it for an
      // unknown day so Heute cancels it. The {at, day} shape has no
      // predecessor in any installed build (0.9.31+67 predates the
      // reminder), so a bare-string pref is safely cancelled.
      final at = DateTime.tryParse(raw);
      return at == null ? null : (at: at, day: '');
    }
  }

  @override
  Future<BedtimeReminderResult> arm(
    DateTime at,
    String day,
    String body,
  ) async {
    final result = await NotificationCenter.instance.scheduleBedtimeReminder(
      at: at,
      body: body,
    );
    if (result == BedtimeReminderResult.scheduled) {
      await Prefs.ensureLoaded();
      await Prefs.setStringAcked(
        _key,
        jsonEncode({'at': at.toIso8601String(), 'day': day}),
      );
    }
    return result;
  }

  @override
  Future<void> cancel() async {
    await NotificationCenter.instance.cancelBedtimeReminder();
    await Prefs.ensureLoaded();
    await Prefs.setStringAcked(_key, '');
  }
}

/// Keeps the reminder in memory only: the synthetic gallery and tests arm
/// nothing on the operating system.
class MemoryHeuteReminder implements HeuteReminder {
  MemoryHeuteReminder({
    this.result = BedtimeReminderResult.scheduled,
    ArmedBedtime? armed,
  }) : _armed = armed;

  /// What the next [arm] reports.
  BedtimeReminderResult result;
  ArmedBedtime? _armed;
  int cancels = 0;

  Future<DateTime?> armedAt() async => _armed?.at;
  @override
  Future<ArmedBedtime?> armed() async => _armed;
  @override
  Future<BedtimeReminderResult> arm(
    DateTime at,
    String day,
    String body,
  ) async {
    if (result == BedtimeReminderResult.scheduled) _armed = (at: at, day: day);
    return result;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _armed = null;
  }
}

/// Everything Heute reads besides [OpenBandController.day].
class _HeuteData {
  final Map<G3Metric, G3Baseline> ranges;
  final int? sleepGoal;
  final G3SleepPlus? plus;
  final List<G3Activity> activities;
  final G3CheckIn? checkIn;
  final Map<G3Metric, G3WeekStrip> week;
  final DateTime? reminderAt;

  /// A past day's last stored band sample; today uses the band snapshot.
  final DateTime? lastSample;
  const _HeuteData({
    this.ranges = const {},
    this.sleepGoal,
    this.plus,
    this.activities = const [],
    this.checkIn,
    this.week = const {},
    this.reminderAt,
    this.lastSample,
  });
}

/// Where Heute opens scrolled to (a notification or the review harness).
enum HeuteAnchor { activity }

class OpenBandHeute extends StatefulWidget {
  final OpenBandController controller;
  final HeuteAnchor? initialAnchor;
  final HeuteReminder reminder;
  final VoidCallback? onProfile, onBand, onDataStatus, onConnect, onAddActivity;

  /// Opens the journal on a day: a check-in answer's own day, which can be
  /// yesterday while Heute shows today.
  final ValueChanged<String>? onJournalDay;
  final ValueChanged<G3Metric>? onOpenMetric;
  final ValueChanged<G3Activity>? onOpenActivity;
  final VoidCallback? onOpenAllMetrics;
  final VoidCallback? onOpenSleep;
  const OpenBandHeute({
    super.key,
    required this.controller,
    this.initialAnchor,
    this.reminder = const NotificationHeuteReminder(),
    this.onProfile,
    this.onBand,
    this.onDataStatus,
    this.onConnect,
    this.onAddActivity,
    this.onJournalDay,
    this.onOpenMetric,
    this.onOpenActivity,
    this.onOpenAllMetrics,
    this.onOpenSleep,
  });

  @override
  State<OpenBandHeute> createState() => _OpenBandHeuteState();
}

enum _Week { recovery, sleep, strain }

class _OpenBandHeuteState extends State<OpenBandHeute>
    with WidgetsBindingObserver {
  _HeuteData _data = const _HeuteData();

  /// The day [_data] was loaded for.
  String? _dataFor;

  /// False when the sleep goal or sleep plan read threw on the last load:
  /// the note's missing action is then unknown, not absent.
  bool _planRead = false;
  String? _loadedFor;

  /// Bumped by every arm, cancel and reconcile: a read of the reminder that
  /// started before one of them is stale and must not overwrite it.
  int _reminderGen = 0;
  int _loadedRequest = -1;
  int _load = 0;
  _Week? _week;
  bool _checkInLater = false;

  /// The count and note being entered in the check-in, before Speichern.
  int? _count;
  final _noteText = TextEditingController();
  bool _remindBusy = false;
  bool _compact = false;
  bool _anchored = false;
  final _scroll = ScrollController();
  final _activityKey = GlobalKey();

  /// The compact header replaces the hub header once it has scrolled away.
  static const double _compactAfter = 64;
  static const double _compactHeight = 49;

  OpenBandController get c => widget.controller;
  OpenBandRepository get repo => c.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    _scroll.addListener(() {
      final compact = _scroll.hasClients && _scroll.offset > _compactAfter;
      if (compact != _compact) setState(() => _compact = compact);
    });
    _changed();
  }

  @override
  void didUpdateWidget(OpenBandHeute old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _loadedFor = null;
      _changed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    _scroll.dispose();
    _noteText.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reconcileReminder());
  }

  void _jumpToAnchor() {
    if (_anchored || widget.initialAnchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _activityKey.currentContext?.findRenderObject() as RenderBox?;
      final list = context.findRenderObject() as RenderBox?;
      if (!mounted || box == null || list == null || !_scroll.hasClients) {
        return;
      }
      _anchored = true;
      final y = box.localToGlobal(Offset.zero, ancestor: list).dy;
      _scroll.jumpTo(
        (_scroll.offset + y - _compactHeight).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  void _changed() {
    if (!mounted) return;
    if (c.selectedDay != _loadedFor || c.refreshRequest != _loadedRequest) {
      _loadedFor = c.selectedDay;
      _loadedRequest = c.refreshRequest;
      unawaited(_reload());
    }
    setState(() {});
  }

  Future<T?> _try<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null; // an unreadable part renders as missing, never invented
    }
  }

  Future<void> _reload() async {
    final request = ++_load;
    final day = c.selectedDay;
    final today = day == todayLabel(c.now());
    final metrics = [
      G3Metric.recovery,
      G3Metric.hrv,
      G3Metric.rhr,
      G3Metric.respRate,
    ];
    final ranges = <G3Metric, G3Baseline>{};
    for (final m in metrics) {
      final r = await _try(() => repo.readPersonalRange(m, day));
      if (r != null) ranges[m] = r;
    }
    var planFailed = false;
    Future<T?> plan<T>(Future<T> Function() read) async {
      try {
        return await read();
      } catch (_) {
        planFailed = true;
        return null;
      }
    }

    final goal = await plan(() => repo.readSleepGoal(day));
    final plus = today
        ? await plan(() => repo.readSleepPlus(day, now: c.now()))
        : null;
    final activities =
        await _try(() => repo.readActivities(day)) ?? const <G3Activity>[];
    final checkIn = today ? await _try(() => repo.readCheckIn(day)) : null;
    final lastSample = today
        ? null
        : await _try(() => repo.readLastBandSampleAt(day));
    final week = <G3Metric, G3WeekStrip>{};
    for (final m in [
      G3Metric.recovery,
      G3Metric.sleepMinutes,
      G3Metric.strain,
    ]) {
      final w = await _try(() => repo.readWeekStrip(m, day));
      if (w != null) week[m] = w;
    }
    final gen = _reminderGen;
    final armed = today ? await _try(widget.reminder.armed) : null;
    if (!mounted || request != _load) return;
    setState(() {
      _dataFor = day;
      _planRead = !planFailed;
      _data = _HeuteData(
        ranges: ranges,
        sleepGoal: goal?.targetMinutes,
        plus: plus,
        activities: activities,
        checkIn: checkIn,
        week: week,
        lastSample: lastSample,
        reminderAt: gen != _reminderGen
            ? _data.reminderAt
            : armed?.day == day
            ? armed?.at
            : null,
      );
    });
    _jumpToAnchor();
    unawaited(_reconcileReminder());
  }

  /// Cancels an armed bedtime reminder that no longer matches: armed for a
  /// day that is not today (after midnight too), or today's note has no
  /// action or another time. Runs after every load and on every foreground.
  Future<void> _reconcileReminder() async {
    final gen = _reminderGen;
    final armed = await _try(widget.reminder.armed);
    if (!mounted || armed == null || gen != _reminderGen) return;
    final now = c.now();
    final today = todayLabel(now);
    if (armed.day == today) {
      final day = c.day;
      // Judge the note only on today's loaded inputs.
      if (day == null || day.day != today || _dataFor != today) return;
      // A failed plan read is not "no action": keep the reminder.
      if (!_planRead) return;
      final action = _todayNote(day, now)?.action;
      if (action != null && action.reminderAt == armed.at) return;
    }
    _reminderGen++;
    await _try(widget.reminder.cancel);
    if (!mounted) return;
    setState(() => _data = _copy(reminderAt: null));
  }

  // ---------------------------------------------------------------------
  // formatting

  static String _hm(num minutes) => g3Duration(minutes.round());

  static String _signedMinutes(int d) {
    if (d.abs() < 60) return g3Signed(d, unit: 'Min.');
    return '${d < 0 ? '−' : '+'}${g3Duration(d.abs())}';
  }

  static int _int(double v) => v.round();

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final now = c.now();
    final today = todayLabel(now);
    final isToday = c.selectedDay == today;
    final day = c.day;
    final band = c.band;
    final synthetic = day?.synthetic == true;
    final sleepMin = day?.sleep.duration.value;
    final noData =
        day != null &&
        day.recovery.value == null &&
        sleepMin == null &&
        day.strain.value == null &&
        day.steps.value == null;
    final never =
        band.latestStoredAt == null &&
        band.receivedAt == null &&
        band.connection != BandConnection.connected &&
        (day == null || noData);
    final disconnected = band.connection != BandConnection.connected;
    // "Daten bis" and "Letzter Bandwert" are one instant: the band's latest
    // stored sample today, the day's last stored sample on a past day.
    final stored = isToday ? band.latestStoredAt : _data.lastSample;
    final stale =
        isToday &&
        !never &&
        disconnected &&
        (stored == null || dayLabelOf(stored) != today);
    final gap = significantSleepGap(day?.sleep.unobservedMinutes);

    final children = <Widget>[
      _header(context, isToday, never, disconnected),
      if (!isToday) ...[
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _dateStrip(context, today),
        ),
      ],
      _sync(isToday, never, stale, gap, day, synthetic, now, stored),
      if (c.loadError != null) ...[
        const SizedBox(height: 12),
        _pad(
          OBErrorBlock(
            title: 'Tag nicht geladen',
            reason:
                'Die gespeicherten Werte konnten nicht gelesen werden. Es wird nichts geschätzt.',
            onRetry: c.refresh,
          ),
        ),
      ],
      if (stale) ...[
        const SizedBox(height: 12),
        _pad(
          OBErrorBlock(
            title: 'Band nicht verbunden',
            reason: stored == null
                ? 'Noch keine Übertragung. Die Nacht liegt auf dem Band und kommt beim Verbinden.'
                : 'Letzte Übertragung ${g3Relative(stored, now: now)}. Die Nacht liegt auf dem Band und kommt beim Verbinden.',
            retryLabel: 'Verbinden',
            onRetry: widget.onConnect,
          ),
        ),
      ],
      if (day != null || never) ...[
        const SizedBox(height: 10),
        _pad(_lead(day, isToday, never, stale)),
      ],
      if (never) ...[
        if (widget.onConnect != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: OBActionPrimary(
              'WHOOP 5.0 verbinden',
              expand: true,
              height: 52,
              onPressed: widget.onConnect,
            ),
          ),
        const SizedBox(height: 12),
        _pad(
          const OBEmptyState(
            title: 'So entstehen deine Werte',
            reason:
                'Das Band misst nachts. Erholung braucht danach 14 Nächte als Basis. Alles bleibt auf deinem iPhone.',
          ),
        ),
      ] else if (day != null) ...[
        if (isToday) ...?_note(day, now, stale),
        if (gap != null && day.sleep.segments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _pad(_night(day, gap)),
        ],
        // Stale: today's activities may not have arrived; stored rows show,
        // an empty card would claim there were none.
        if (!stale || _data.activities.isNotEmpty) ..._activity(isToday),
        if (isToday && !stale) ...?_checkIn(),
        if (!stale) ...[
          ..._weekSection(isToday),
          if (gap == null || day.sleep.segments.isEmpty) ...[
            const SizedBox(height: 12),
            _pad(_night(day, gap)),
          ],
          const SizedBox(height: 12),
          _pad(_body(day)),
          const SizedBox(height: 12),
          _pad(_steps(day, isToday)),
        ],
      ],
    ];
    if (day != null && (_data.checkIn != null || !isToday)) _jumpToAnchor();
    return ColoredBox(
      color: g.page,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: kOBTabBarContentInset),
              children: children,
            ),
          ),
          if (_compact)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: OBPageHeader.compact(
                title: isToday
                    ? 'Heute'
                    : g3DayShort(DateTime.parse(c.selectedDay)),
                subtitle: [
                  if (isToday)
                    g3DayShort(DateTime.parse(c.selectedDay))
                  else
                    _selectedDayAge(c.selectedDay, c.now()),
                  if (synthetic) 'SYNTHETISCHE DATEN',
                ].join(' · '),
                band: OBBandCapsule(
                  bandStatus: c.bandStatus,
                  state: never
                      ? OBBandState.none
                      : disconnected
                      ? OBBandState.off
                      : OBBandState.live,
                  battery: band.batteryPercent,
                  small: true,
                  onTap: never ? widget.onConnect : widget.onBand,
                ),
                onProfile: widget.onProfile,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );

  String _selectedDayAge(String day, DateTime now) {
    final selected = DateTime.parse(day);
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(selected.year, selected.month, selected.day))
        .inDays;
    return days == 1 ? 'gestern' : 'vor $days Tagen';
  }

  // ---------------------------------------------------------------------
  // header, date strip, sync line

  Widget _header(
    BuildContext context,
    bool isToday,
    bool never,
    bool disconnected,
  ) {
    final day = DateTime.parse(c.selectedDay);
    final now = c.now();
    final longDay = g3DayLong(day);
    final title = isToday ? 'Heute' : longDay.split(', ').first;
    final date = longDay.split(', ').last;
    final subtitle = isToday
        ? longDay
        : '$date · ${_selectedDayAge(c.selectedDay, now)}';
    return OBPageHeader.hub(
      title: title,
      subtitle: subtitle,
      band: OBBandCapsule(
        bandStatus: c.bandStatus,
        state: never
            ? OBBandState.none
            : disconnected
            ? OBBandState.off
            : OBBandState.live,
        battery: c.band.batteryPercent,
        onTap: never ? widget.onConnect : widget.onBand,
      ),
      onTitle: () => chooseOpenBandDay(context, c),
      onProfile: widget.onProfile,
    );
  }

  Widget _dateStrip(BuildContext context, String today) {
    final days = g3DaysEnding(today, 7);
    final selected = days.indexOf(c.selectedDay);
    return OBDateStrip(
      days: [
        for (final d in days)
          (g3Weekday(DateTime.parse(d)), DateTime.parse(d).day.toString()),
      ],
      selected: selected < 0 ? -1 : selected,
      onSelect: (i) => c.selectDay(days[i]),
      onCalendar: () => chooseOpenBandDay(context, c),
    );
  }

  Widget _sync(
    bool isToday,
    bool never,
    bool stale,
    double? gap,
    OpenBandDay? day,
    bool synthetic,
    DateTime now,
    DateTime? stored,
  ) {
    final (OBSyncKind kind, String text) = never
        ? (OBSyncKind.never, 'Noch kein Band verbunden')
        : !isToday
        ? (
            OBSyncKind.past,
            stored == null
                ? 'Gespeicherter Tag'
                : 'Gespeicherter Tag · ${g3DataThrough(stored, now: now)}',
          )
        : stale
        ? (
            OBSyncKind.stale,
            stored == null
                ? 'Getrennt · noch keine Daten'
                : 'Getrennt · ${g3DataThrough(stored, now: now)}',
          )
        : (
            gap != null ? OBSyncKind.partial : OBSyncKind.live,
            [
              if (stored != null) g3DataThrough(stored, now: now),
              if (day?.sleep.duration.value == null)
                'keine Nacht'
              else
                gap != null ? 'Nacht mit Lücke' : 'Nacht lückenlos',
            ].join(' · '),
          );
    return OBSyncState(
      compact: true,
      kind: kind,
      text: text,
      synthetic: synthetic,
      onTap: widget.onDataStatus,
    );
  }

  // ---------------------------------------------------------------------
  // lead card

  Widget _lead(OpenBandDay? day, bool isToday, bool never, bool stale) {
    final g = G3.of(context);
    final baseline = _data.ranges[G3Metric.recovery];
    final phase = baseline?.status.phase ?? BaselinePhase.none;
    final value = day?.recovery.value;
    final range = phase == BaselinePhase.trusted ? baseline?.range : null;
    final OBLeadMetric lead;
    void open() => widget.onOpenMetric?.call(G3Metric.recovery);
    if (never) {
      lead = const OBLeadMetric(
        domain: G3Domain.recovery,
        glyph: LucideIcons.heartPulse,
        label: 'ERHOLUNG',
        note: 'kein Band',
        state: OBLeadState.missing,
        title: 'Noch keine Werte',
        reason: 'Erste Werte nach der ersten Nacht mit Band.',
      );
    } else if (value != null && range != null) {
      final state = value > range.high
          ? OBLeadState.better
          : value < range.low
          ? OBLeadState.worse
          : OBLeadState.normal;
      final delta = _int(value) - _int(range.median);
      final median = _int(range.median);
      lead = OBLeadMetric(
        domain: G3Domain.recovery,
        glyph: LucideIcons.heartPulse,
        label: 'ERHOLUNG',
        note: 'normal ${_int(range.low)}–${_int(range.high)}',
        state: state,
        value: value.roundToDouble(),
        delta: '${delta.abs()}',
        deltaUp: delta >= 0,
        caption: switch (state) {
          OBLeadState.better => 'über deinem Normalbereich',
          OBLeadState.worse => 'unter deinem Normalbereich',
          _ =>
            delta == 0
                ? 'auf deinem Median $median'
                : '${delta > 0 ? 'über' : 'unter'} deinem Median $median',
        },
        scale: G3Scale(
          min: 0,
          max: 100,
          band: (range.low, range.high),
          median: range.median,
          ticks: [
            const G3Tick(0, '0'),
            G3Tick(range.low, '${_int(range.low)}', strong: true),
            G3Tick(range.high, '${_int(range.high)}', strong: true),
            const G3Tick(100, '100'),
          ],
        ),
        onTap: widget.onOpenMetric == null ? null : open,
      );
    } else if (value == null && phase == BaselinePhase.building) {
      final need = baseline?.status.nightsNeeded;
      lead = OBLeadMetric(
        domain: G3Domain.recovery,
        glyph: LucideIcons.heartPulse,
        label: 'ERHOLUNG',
        state: OBLeadState.building,
        have: baseline?.status.nightsHave,
        need: need,
        title: 'Noch keine Erholung',
        reason: '',
        onTap: widget.onOpenMetric == null ? null : open,
      );
    } else if (value != null) {
      lead = OBLeadMetric(
        domain: G3Domain.recovery,
        glyph: LucideIcons.heartPulse,
        label: 'ERHOLUNG',
        note: phase == BaselinePhase.building ? 'Basis im Aufbau' : null,
        state: OBLeadState.plain,
        value: value.roundToDouble(),
        basisChip: 'kein Normalbereich',
        scale: const G3Scale(
          min: 0,
          max: 100,
          ticks: [G3Tick(0, '0'), G3Tick(100, '100')],
        ),
        onTap: widget.onOpenMetric == null ? null : open,
      );
    } else {
      lead = OBLeadMetric(
        domain: G3Domain.recovery,
        glyph: LucideIcons.heartPulse,
        label: 'ERHOLUNG',
        note: stale ? 'nicht übertragen' : 'Keine Nacht',
        state: OBLeadState.missing,
        title: isToday
            ? 'Keine Erholung für heute'
            : 'Keine Erholung an diesem Tag',
        reason: stale
            ? 'Die Nacht ist noch nicht übertragen.'
            : 'Es fehlt die Nacht. Nichts wird geschätzt.',
      );
    }
    return OBPanel(
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          lead,
          if (!never) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: g.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _sleepMetric(day, stale)),
                  const SizedBox(width: 25),
                  Expanded(child: _strainMetric(day, isToday, stale)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sleepMetric(OpenBandDay? day, bool stale) {
    final minutes = day?.sleep.duration.value;
    final goal = _data.sleepGoal;
    return OBSecondaryMetric(
      domain: G3Domain.sleep,
      glyph: LucideIcons.moon,
      label: 'SCHLAF',
      value: minutes == null ? null : _hm(minutes),
      aside: minutes == null
          ? (stale ? 'nicht übertragen' : 'keine Nacht')
          : goal == null
          ? null
          : _signedMinutes(minutes.round() - goal),
      fill: minutes == null ? null : minutes / 600,
      goal: goal == null ? null : (goal / 600, 'Ziel ${_hm(goal)}'),
      start: '0 h',
      end: '10 h',
      onTap: widget.onOpenSleep,
    );
  }

  Widget _strainMetric(OpenBandDay? day, bool isToday, bool stale) {
    final v = day?.strain.value;
    return OBSecondaryMetric(
      domain: G3Domain.load,
      glyph: LucideIcons.flame,
      label: 'BELASTUNG',
      value: v == null ? null : g3Number(v, digits: 1),
      aside: v == null
          ? (stale ? 'nicht übertragen' : 'keine Daten')
          : (isToday ? 'läuft' : 'ganzer Tag'),
      fill: v == null ? null : v / 21,
      start: '0',
      end: '21',
      onTap: widget.onOpenMetric == null
          ? null
          : () => widget.onOpenMetric!(G3Metric.strain),
    );
  }

  // ---------------------------------------------------------------------
  // Für heute

  TodayNote? _todayNote(OpenBandDay day, DateTime now) {
    final plus = _data.plus;
    return todayNote(
      derivedDay: c.selectedDay,
      now: now,
      recovery: day.recovery.value,
      recoveryBaseline:
          _data.ranges[G3Metric.recovery] ??
          const G3Baseline(BaselineStatus(BaselinePhase.none)),
      sleepMinutes: day.sleep.duration.value?.round(),
      sleepGoalMinutes: _data.sleepGoal,
      sleepNeedMinutes: plus?.needMinutes,
      suggestedBedtime: plus?.bedtime,
      suggestedWake: plus?.wake,
      sleepUnobservedMinutes: day.sleep.unobservedMinutes,
    );
  }

  List<Widget>? _note(OpenBandDay day, DateTime now, bool stale) {
    final note = _todayNote(day, now);
    Widget? block;
    if (note != null) {
      final action = note.action;
      final remindable = action != null && action.reminderAt.isAfter(now);
      final armed = remindable && _data.reminderAt == action.reminderAt;
      block = OBDayNote(
        state: !remindable
            ? OBNoteState.text
            : armed
            ? OBNoteState.reminded
            : OBNoteState.action,
        headline: note.headline,
        reason: note.reason,
        actionTitle: armed
            ? 'Erinnerung um ${g3Clock(action.reminderAt)}'
            : action?.label,
        actionSubtitle: armed
            ? '15 Min. vor ${g3Clock(action.reminderAt.add(const Duration(minutes: 15)))} · abbestellen'
            : _data.plus?.needMinutes != null && _data.plus?.wake != null
            ? 'Bedarf ${_hm(_data.plus!.needMinutes!)} · bis ${g3Clock(_data.plus!.wake!)}'
            : action?.sub,
        onRemind: remindable && !armed && !_remindBusy
            ? () => _arm(action)
            : null,
        onUnsubscribe: armed && !_remindBusy ? _unarm : null,
      );
    } else if (day.sleep.duration.value == null) {
      block = OBDayNote(
        state: OBNoteState.absent,
        headline: 'Heute keine Notiz',
        reason: stale
            ? 'Ihr fehlen Nacht und Tag. Sie erscheint nach der Übertragung.'
            : 'Ihr fehlt die Nacht. Sie erscheint, wenn alle Werte da sind.',
      );
    }
    if (block == null) return null;
    return [const SizedBox(height: 12), _pad(block)];
  }

  Future<void> _arm(TodayNoteAction action) async {
    _reminderGen++;
    setState(() => _remindBusy = true);
    final result = await widget.reminder.arm(
      action.reminderAt,
      c.selectedDay,
      '${action.label} · ${action.sub}',
    );
    if (!mounted) return;
    final ok = result == BedtimeReminderResult.scheduled;
    setState(() {
      _remindBusy = false;
      if (ok) _data = _copy(reminderAt: action.reminderAt);
    });
    final why = switch (result) {
      BedtimeReminderResult.scheduled => null,
      BedtimeReminderResult.passed =>
        'Keine Erinnerung gestellt: ${g3Clock(action.reminderAt)} ist schon vorbei.',
      BedtimeReminderResult.denied =>
        'Keine Erinnerung gestellt: Mitteilungen sind aus. In den iOS-Einstellungen erlauben.',
      BedtimeReminderResult.failed =>
        'Keine Erinnerung gestellt. Bitte noch einmal versuchen.',
    };
    if (why != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(why)));
    }
  }

  Future<void> _unarm() async {
    _reminderGen++;
    setState(() => _remindBusy = true);
    await widget.reminder.cancel();
    if (!mounted) return;
    setState(() {
      _remindBusy = false;
      _data = _copy(reminderAt: null);
    });
  }

  _HeuteData _copy({
    DateTime? reminderAt,
    G3CheckIn? checkIn,
    List<G3Activity>? activities,
  }) => _HeuteData(
    ranges: _data.ranges,
    sleepGoal: _data.sleepGoal,
    plus: _data.plus,
    activities: activities ?? _data.activities,
    checkIn: checkIn ?? _data.checkIn,
    week: _data.week,
    reminderAt: reminderAt,
    lastSample: _data.lastSample,
  );

  // ---------------------------------------------------------------------
  // activities

  List<Widget> _activity(bool isToday) {
    final list = _data.activities;
    return [
      OBSectionHeader(
        'AKTIVITÄT',
        key: _activityKey,
        action: widget.onAddActivity == null ? null : 'Eintragen',
        onAction: widget.onAddActivity,
      ),
      if (list.isEmpty)
        _pad(
          OBEmptyState(
            title: isToday
                ? 'Noch keine Aktivität heute'
                : 'Keine Aktivität an diesem Tag',
            reason: 'Nichts erkannt und nichts eingetragen.',
            action: widget.onAddActivity == null
                ? null
                : 'Aktivität nachtragen',
            onAction: widget.onAddActivity,
          ),
        )
      else
        for (final (i, a) in list.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _pad(_activityRow(a)),
        ],
    ];
  }

  Widget _activityRow(G3Activity a) {
    final g = G3.of(context);
    final unconfirmed = a.source == G3ActivitySource.auto && !a.confirmed;
    final end = a.end;
    final minutes = a.duration?.inMinutes;
    return OBActivityRow(
      domain: G3Domain.load,
      pictogram: g3SportIcon(
        a.sport,
        size: 24,
        color: g.domainHue(G3Domain.load),
      ),
      title: g3SportLabel(a.sport),
      subtitle: [
        end == null
            ? 'seit ${g3Clock(a.start)}'
            : '${g3Clock(a.start)}–${g3Clock(end)}',
        if (minutes != null) g3Duration(minutes),
      ].join(' · '),
      unconfirmed: unconfirmed,
      strain: a.strain == null
          ? null
          : g3Number(a.strain, digits: 1, signed: true),
      zoneMinutes: a.zoneMinutes?.map((m) => m.round()).toList(),
      onTap: unconfirmed
          ? () => _suggestion(a)
          : widget.onOpenActivity == null
          ? null
          : () => widget.onOpenActivity!(a),
    );
  }

  Future<void> _suggestion(G3Activity a) async {
    var sport = a.sport;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          final g = G3.of(sheet);
          Future<void> run(Future<void> Function() op) async {
            try {
              await op();
              if (sheet.mounted) Navigator.of(sheet).pop();
            } catch (_) {
              if (sheet.mounted && mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Nicht gespeichert. Der Vorschlag ist nicht mehr offen.',
                    ),
                  ),
                );
                Navigator.of(sheet).pop();
              }
            }
          }

          return OBSheet(
            title: 'Automatisch erkannt',
            subtitle: [
              a.end == null
                  ? 'seit ${g3Clock(a.start)}'
                  : '${g3Clock(a.start)}–${g3Clock(a.end!)}',
              if (a.duration != null) g3Duration(a.duration!.inMinutes),
            ].join(' · '),
            cancelLabel: 'Ändern',
            confirmLabel: 'Stimmt',
            onCancel: () async {
              final picked = await showModalBottomSheet<String>(
                context: sheet,
                backgroundColor: Colors.transparent,
                builder: (pick) => OBSheet(
                  title: 'Sportart',
                  cancelLabel: 'Abbrechen',
                  confirmLabel: 'Fertig',
                  onCancel: () => Navigator.of(pick).pop(),
                  onConfirm: () => Navigator.of(pick).pop(),
                  child: Column(
                    children: [
                      for (final s in g3QuickSportIds)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OBListRow(
                            leading: g3SportIcon(s, size: 18, color: g.ink),
                            title: g3SportLabel(s),
                            onTap: () => Navigator.of(pick).pop(s),
                          ),
                        ),
                    ],
                  ),
                ),
              );
              if (picked == null || picked == sport) return;
              try {
                await repo.changeSuggestionSport(a.id, picked);
                if (sheet.mounted) setSheet(() => sport = picked);
                // The list and a reopened sheet read the stored sport; a
                // stale one would overwrite the change on Stimmt.
                await c.refresh();
              } catch (_) {
                await run(() async => throw StateError('closed'));
              }
            },
            onConfirm: () => run(() async {
              await repo.confirmSuggestion(a.id, sport: sport);
              await c.refresh();
            }),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: g.pressed(radius: 12, color: g.track),
                      child: g3SportIcon(sport, size: 24, color: g.ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        g3SportLabel(sport),
                        style: g.t(17, 22, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Zonen und Belastung erscheinen nach der Bestätigung.',
                  style: g.t(13, 17, color: g.ink2),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label: 'Keine Aktivität, verwerfen',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => run(() async {
                        await repo.dismissSuggestion(a.id);
                        await c.refresh();
                      }),
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            'Keine Aktivität · verwerfen',
                            style: g.t(14, 18, weight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // check-in

  List<Widget>? _checkIn() {
    final ci = _data.checkIn;
    if (ci == null || ci.total == 0) return null;
    final open = ci.questions.where((q) => q.answer == null).toList();
    if (open.isEmpty) return null;
    final Widget card;
    if (_checkInLater) {
      card = OBCheckIn(
        title: '',
        index: ci.answered + 1,
        total: ci.total,
        answer: const SizedBox.shrink(),
        onLater: () {},
        later: true,
        onResume: () => setState(() => _checkInLater = false),
      );
    } else {
      final q = open.first;
      // The answer shown above the question: the nearest answered one before
      // it, else the last answered one.
      final at = ci.questions.indexOf(q);
      final before = ci.questions.take(at).where((x) => x.answer != null);
      final after = ci.questions.skip(at).where((x) => x.answer != null);
      final last = before.isNotEmpty
          ? before.last
          : after.isEmpty
          ? null
          : after.last;
      final copy = g3CheckInCopy(q.key, _checkInTitle(q));
      final question = copy.question;
      OBCheckIn ask(Widget answer) => OBCheckIn(
        title: question,
        index: ci.answered + 1,
        total: ci.total,
        target: _targetLabel(ci.day, q.targetDay),
        answered: last == null ? null : _answerText(last),
        onChange: last == null || widget.onJournalDay == null
            ? null
            : () => widget.onJournalDay!(last.targetDay),
        onLater: () => setState(() => _checkInLater = true),
        inlineLater: q.kind == G3CheckInKind.yesNo,
        footerLabel: q.kind == G3CheckInKind.rating
            ? '1 ${copy.low} · ${(q.field?.max ?? 5).round()} ${copy.high}'
            : null,
        answer: answer,
      );
      final field = q.field;
      card = switch (q.kind) {
        G3CheckInKind.yesNo => ask(
          OBYesNoKeys(
            onYes: () => _answer(q, const G3YesNoAnswer(true)),
            onNo: () => _answer(q, const G3YesNoAnswer(false)),
          ),
        ),
        G3CheckInKind.rating => ask(
          OBRatingKeys(
            question: question,
            max: (field?.max ?? 5).round(),
            onRate: (v) => _answer(q, G3RatingAnswer(v)),
          ),
        ),
        G3CheckInKind.quantity => ask(
          OBCountAnswer(
            value: _count,
            max: (field?.max ?? 20).round(),
            unit: field == null ? '' : journalFieldUnitLabel(field),
            onChanged: (v) => setState(() => _count = v),
            onSave: () => _answer(q, G3QuantityAnswer(_count!.toDouble())),
          ),
        ),
        G3CheckInKind.freeNote => ask(
          OBNoteAnswer(
            controller: _noteText,
            onSave: () => _answer(q, G3FreeNoteAnswer(_noteText.text.trim())),
          ),
        ),
      };
    }
    return [const SizedBox(height: 12), _pad(card)];
  }

  static String _checkInTitle(G3CheckInQuestion q) =>
      q.field == null ? q.label : journalFieldTitle(q.field!);

  /// The day an answer belongs to when it is not the selected day.
  static String? _targetLabel(String selected, String target) {
    if (target == selected) return null;
    if (target == g3DaysEnding(selected, 2).first) return 'zu gestern';
    return 'zu ${g3DateShort(DateTime.parse(target))}';
  }

  static String _answerText(G3CheckInQuestion q) {
    final field = q.field;
    final value = switch (q.answer) {
      G3YesNoAnswer(:final value) => value ? 'Ja' : 'Nein',
      G3RatingAnswer(:final value) => '$value von ${(field?.max ?? 5).round()}',
      G3QuantityAnswer(:final value) =>
        value == 0
            ? 'Keins'
            : field?.kind == JournalFieldKind.duration
            ? g3Duration(value.round())
            : '${g3Number(value)} ${field == null ? '' : journalFieldUnitLabel(field)}'
                  .trim(),
      G3FreeNoteAnswer() => 'gespeichert',
      null => '—',
    };
    return '${_checkInTitle(q)}: $value';
  }

  /// Writes through the data layer to the question's own day, then rereads.
  Future<void> _answer(G3CheckInQuestion q, G3CheckInAnswer answer) async {
    final day = c.selectedDay;
    try {
      await repo.answerCheckIn(day, q.key, answer);
      final fresh = await repo.readCheckIn(day);
      if (!mounted || c.selectedDay != day) return;
      setState(() {
        _count = null;
        _noteText.clear();
        _data = _copy(reminderAt: _data.reminderAt, checkIn: fresh);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Antwort nicht gespeichert.')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // week

  List<Widget> _weekSection(bool isToday) {
    final recovery = _data.week[G3Metric.recovery];
    final building =
        _data.ranges[G3Metric.recovery]?.status.phase == BaselinePhase.building;
    final recoveryEmpty =
        recovery == null || recovery.days.every((d) => d.value == null);
    final selected =
        _week ?? (building || recoveryEmpty ? _Week.sleep : _Week.recovery);
    return [
      OBSectionHeader(
        'WOCHE',
        trailing: OBSegmented(
          items: const ['Erholung', 'Schlaf', 'Belastung'],
          selected: selected.index,
          disabled: recoveryEmpty ? const {0} : const {},
          onChanged: (i) => setState(() => _week = _Week.values[i]),
        ),
      ),
      _pad(_weekBars(selected, isToday)),
    ];
  }

  Widget _weekBars(_Week which, bool isToday) {
    final metric = switch (which) {
      _Week.recovery => G3Metric.recovery,
      _Week.sleep => G3Metric.sleepMinutes,
      _Week.strain => G3Metric.strain,
    };
    final strip = _data.week[metric];
    final days =
        strip?.days ??
        [for (final d in g3DaysEnding(c.selectedDay, 7)) G3WeekValue(d, null)];
    final range = strip?.range;
    String dayName(int i, String d) => i == days.length - 1 && isToday
        ? 'Heute'
        : g3Weekday(DateTime.parse(d));
    G3Deviation dev(G3WeekValue v) {
      if (v.value == null || range == null || v.outOfRange != true) {
        return G3Deviation.none;
      }
      return v.value! < range.low ? G3Deviation.worse : G3Deviation.better;
    }

    final bars = [
      for (final (i, v) in days.indexed)
        OBWeekBar(
          dayName(i, v.day),
          v.value,
          label: v.value == null
              ? null
              : switch (which) {
                  _Week.recovery => '${_int(v.value!)}',
                  _Week.sleep => _hm(v.value!),
                  _Week.strain => g3Number(v.value, digits: 1),
                },
          deviation: which == _Week.recovery ? dev(v) : G3Deviation.none,
          today: i == days.length - 1,
        ),
    ];
    final empty = days.every((d) => d.value == null);
    final baseline = _data.ranges[G3Metric.recovery];
    switch (which) {
      case _Week.recovery:
        final below = bars
            .where((b) => b.deviation == G3Deviation.worse)
            .length;
        final above = bars
            .where((b) => b.deviation == G3Deviation.better)
            .length;
        final need = baseline?.status.nightsNeeded,
            left = baseline?.status.remaining;
        return OBWeekBars(
          domain: G3Domain.recovery,
          bars: bars,
          max: 100,
          band: range == null ? null : (range.low, range.high),
          emptyReason: empty
              ? (need != null && left != null
                    ? 'Erholung braucht $need ${g3CountNoun(need, 'Nacht', 'Nächte')} · noch $left'
                    : 'Keine Erholung in dieser Woche')
              : null,
          footer: [
            if (range != null)
              G3Legend.band(
                'dein Normalbereich ${_int(range.low)}–${_int(range.high)}',
                domain: G3Domain.recovery,
              )
            else
              const G3Legend.text('noch kein Normalbereich'),
            if (below > 0)
              G3Legend.mark(
                '$below ${g3CountNoun(below, 'Tag', 'Tage')} darunter',
                G3Deviation.worse,
              ),
            if (above > 0)
              G3Legend.mark(
                '$above ${g3CountNoun(above, 'Tag', 'Tage')} darüber',
                G3Deviation.better,
              ),
          ],
        );
      case _Week.sleep:
        final goal = strip?.goal;
        return OBWeekBars(
          domain: G3Domain.sleep,
          bars: bars,
          max: 111 / 11 * 60,
          goal: goal,
          labelsBelow: true,
          emptyReason: empty ? 'Keine Nacht in dieser Woche' : null,
          footer: [
            if (goal != null)
              G3Legend.goal('Ziel ${_hm(goal)}')
            else
              const G3Legend.text('kein Schlafziel'),
          ],
        );
      case _Week.strain:
        return OBWeekBars(
          domain: G3Domain.load,
          bars: bars,
          max: 21,
          emptyReason: empty ? 'Keine Belastung in dieser Woche' : null,
        );
    }
  }

  // ---------------------------------------------------------------------
  // night

  Widget _night(OpenBandDay day, double? gap) {
    final s = day.sleep;
    final asleep = s.duration.value;
    if (asleep == null) {
      return const OBNightCard(
        domain: G3Domain.sleep,
        state: OBNightState.missing,
      );
    }
    final onset = s.onset, wake = s.wake;
    final segments = <OBStageSegment>[];
    final gaps = <(double, double)>[];
    double total = s.bedMinutes ?? 1;
    if (onset != null && wake != null && wake.isAfter(onset)) {
      total = wake.difference(onset).inSeconds / 60;
      double at(DateTime t) => t.difference(onset).inSeconds / 60;
      for (final seg in s.segments) {
        final stage = seg.stage;
        if (stage == null) {
          if (seg.end.difference(seg.start).inSeconds / 60 >=
              kSleepGapSignificantMinutes) {
            gaps.add((at(seg.start), at(seg.end)));
          }
          continue;
        }
        segments.add(
          OBStageSegment(
            switch (stage) {
              NightStage.awake => OBStage.wake,
              NightStage.rem => OBStage.rem,
              NightStage.light => OBStage.light,
              NightStage.deep => OBStage.deep,
            },
            at(seg.start),
            at(seg.end),
          ),
        );
      }
    }
    String? m(double? v) => v == null ? null : _hm(v);
    final mid = onset != null && wake != null
        ? onset.add(wake.difference(onset) ~/ 2)
        : null;
    final firstGap = gaps.isEmpty || onset == null ? null : gaps.first;
    final bed = s.bedMinutes;
    final totals = [
      (OBStage.deep, m(s.deepMinutes)),
      (OBStage.light, m(s.lightMinutes)),
      (OBStage.rem, m(s.remMinutes)),
      (OBStage.wake, m(s.awakeMinutes)),
    ];
    if (segments.isEmpty) {
      // No stored timeline: totals only, never empty lanes that read as data.
      return _nightTotals(asleep, bed, totals);
    }
    return OBNightCard(
      domain: G3Domain.sleep,
      state: gap != null ? OBNightState.gap : OBNightState.full,
      note: gap != null ? '${g3Duration(gap.round())} Lücke' : null,
      asleep: _hm(asleep),
      subtitle: bed == null
          ? null
          : gap != null
          ? 'gezählt in ${_hm(bed - gap)} mit Daten'
          : 'Schlaf von ${_hm(bed)} im Bett',
      segments: segments,
      totalMinutes: total,
      gaps: gaps,
      gapNote: firstGap == null
          ? null
          : '${g3Clock(onset!.add(Duration(seconds: (firstGap.$1 * 60).round())))}–${g3Clock(onset.add(Duration(seconds: (firstGap.$2 * 60).round())))} ohne Daten · nicht aufgefüllt',
      axis: onset == null || wake == null || mid == null
          ? ('', '', '')
          : (g3Clock(onset), g3Clock(mid), g3Clock(wake)),
      totals: totals,
      onTap: widget.onOpenSleep,
    );
  }

  Widget _nightTotals(
    double asleep,
    double? bed,
    List<(OBStage, String?)> totals,
  ) {
    final g = G3.of(context);
    Color color(OBStage s) => switch (s) {
      OBStage.deep => g.stageFor(G3Domain.sleep, 3),
      OBStage.light => g.stageFor(G3Domain.sleep, 2),
      OBStage.rem => g.stageFor(G3Domain.sleep, 1),
      OBStage.wake => g.stageFor(G3Domain.sleep, 0),
    };
    return Semantics(
      button: widget.onOpenSleep != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpenSleep,
        child: OBPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const G3LabelRow(
                'NACHT',
                domain: G3Domain.sleep,
                glyph: LucideIcons.moon,
                note: 'ohne Verlauf',
              ),
              const SizedBox(height: 4),
              G3ValueLine(
                _hm(asleep),
                g.t(36, 42, weight: FontWeight.w700, tracking: -.035),
                aside: bed == null ? null : 'Schlaf von ${_hm(bed)} im Bett',
                asideStyle: g.t(13, 16, color: g.ink2),
                gap: 8,
              ),
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: g.line)),
                ),
                child: OBStageLegend([
                  for (final (st, v) in totals)
                    (OBNightCard.stageName(st), v, color(st)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // body

  Widget _body(OpenBandDay day) {
    final rows = <Widget>[];
    void open(G3Metric m) => widget.onOpenMetric?.call(m);
    OBBodyRow valueRow(
      String name,
      G3Metric metric,
      DayMetric v,
      String unit, {
      int digits = 0,
    }) {
      final base = _data.ranges[metric];
      final value = v.value;
      final range = base?.status.phase == BaselinePhase.trusted
          ? base?.range
          : null;
      final tap = widget.onOpenMetric == null ? null : () => open(metric);
      if (value == null) {
        return OBBodyRow(
          domain: G3Domain.recovery,
          state: OBBodyState.missing,
          name: name,
          reason: v.nightScalar == NightScalarState.failed
              ? kNightScalarFailedLabel
              : null,
          onTap: tap,
        );
      }
      final text = g3Number(value, digits: digits);
      // A partial night keeps its value but makes no range claim, the same
      // as its detail and Messwerte.
      if (v.nightScalar == NightScalarState.partial) {
        return OBBodyRow(
          domain: G3Domain.recovery,
          state: OBBodyState.building,
          name: name,
          value: text,
          unit: unit,
          note: kNightScalarPartialLabel,
          onTap: tap,
        );
      }
      if (range != null) {
        final pad = (range.high - range.low) * .6;
        return OBBodyRow(
          domain: G3Domain.recovery,
          state: OBBodyState.range,
          name: name,
          value: text,
          unit: unit,
          at: value,
          min: range.low - pad,
          max: range.high + pad,
          band: (range.low, range.high),
          minLabel: g3Number(range.low, digits: digits),
          maxLabel: g3Number(range.high, digits: digits),
          onTap: tap,
        );
      }
      // No trusted range: HRV, Ruhepuls and Atemfrequenz have no fixed,
      // metric-defined scale, so no track is drawn from the value itself.
      final left = base?.status.remaining;
      return OBBodyRow(
        domain: G3Domain.recovery,
        state: OBBodyState.building,
        name: name,
        value: text,
        unit: unit,
        note: base?.status.phase == BaselinePhase.building
            ? (left == null
                  ? 'Basis im Aufbau'
                  : 'Basis: noch $left ${g3CountNoun(left, 'Nacht', 'Nächte')}')
            : 'kein Normalbereich',
        onTap: tap,
      );
    }

    rows
      ..add(valueRow('HRV', G3Metric.hrv, day.hrv, 'ms'))
      ..add(valueRow('Ruhepuls', G3Metric.rhr, day.restingHr, '/min'))
      ..add(
        valueRow(
          'Atemfrequenz',
          G3Metric.respRate,
          day.respiration,
          '/min',
          digits: 1,
        ),
      );
    final z = day.skinTemperature.value;
    rows.add(
      z == null
          ? OBBodyRow(
              domain: G3Domain.recovery,
              state: OBBodyState.missing,
              name: 'Hauttemperatur',
              last: true,
              onTap: widget.onOpenMetric == null
                  ? null
                  : () => open(G3Metric.skinTempZ),
            )
          : OBBodyRow(
              domain: G3Domain.recovery,
              state: OBBodyState.deviation,
              name: 'Hauttemperatur',
              // Relative to the personal basis; never °C.
              value: g3Number(z, digits: 1, signed: true),
              unit: 'zur Basis',
              at: z,
              min: -1.5,
              max: 1.5,
              last: true,
              onTap: widget.onOpenMetric == null
                  ? null
                  : () => open(G3Metric.skinTempZ),
            ),
    );
    return OBPanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OBCardHeader(
            'KÖRPER',
            domain: G3Domain.recovery,
            glyph: LucideIcons.personStanding,
            note: 'vergangene Nacht',
            onTap: widget.onOpenAllMetrics,
          ),
          ...rows,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // steps

  Widget _steps(OpenBandDay day, bool isToday) {
    final total = day.steps.value?.round();
    // Stored spans only, split across hours by overlap like stepsByHour. An
    // hour without a stored span stays empty; zero is a stored zero.
    final sums = List<double?>.filled(24, null);
    DateTime? last;
    for (final iv in day.stepIntervals) {
      final ms = iv.end.difference(iv.start).inMilliseconds;
      if (ms <= 0) continue;
      var t = iv.start;
      while (t.isBefore(iv.end)) {
        final hourEnd = DateTime(t.year, t.month, t.day, t.hour + 1);
        final sliceEnd = hourEnd.isBefore(iv.end) ? hourEnd : iv.end;
        if (dayLabelOf(t) == c.selectedDay) {
          sums[t.hour] =
              (sums[t.hour] ?? 0) +
              iv.steps * sliceEnd.difference(t).inMilliseconds / ms;
          if (last == null || sliceEnd.isAfter(last)) last = sliceEnd;
        }
        t = sliceEnd;
      }
    }
    final hourly = [for (final v in sums) v?.round()];
    return OBStepsCard(
      domain: G3Domain.load,
      total: total,
      note: last != null && isToday ? 'bis ${g3Clock(last)}' : '',
      hourly: total == null ? const [] : hourly,
      goalLabel: null,
    );
  }
}
