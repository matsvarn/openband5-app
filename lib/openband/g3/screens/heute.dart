// G3 · Heute (Paper page G3 · Heute, p-17-0).
//
// One lead number (Erholung on the personal range), Schlaf and Belastung,
// the rule-based Für-heute note with its opt-in reminder, activities, the
// check-in, the week strip, the night, body values and steps. Every value
// comes from the repository; a missing input renders "—" or a refusal.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/day_label.dart';
import '../../../data/journal_fields.dart' show JournalMetricValue;
import '../../../notify/notification_center.dart';
import '../../../state/prefs.dart';
import '../../controller.dart';
import '../../day_picker.dart';
import '../../domain.dart';
import '../../journal_fields.dart' show journalFieldTitle;
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../../today_note.dart';
import '../../training.dart' show OBSportIcon, obSport;
import '../chrome.dart';
import '../day.dart';
import '../g3_theme.dart';
import '../heute_parts.dart';
import '../metrics.dart';

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
  const _HeuteData({
    this.ranges = const {},
    this.sleepGoal,
    this.plus,
    this.activities = const [],
    this.checkIn,
    this.week = const {},
    this.reminderAt,
  });
}

/// Where Heute opens scrolled to (a notification or the review harness).
enum HeuteAnchor { activity }

class OpenBandHeute extends StatefulWidget {
  final OpenBandController controller;
  final HeuteAnchor? initialAnchor;
  final HeuteReminder reminder;
  final VoidCallback? onProfile, onBand, onConnect, onAddActivity, onJournal;
  final ValueChanged<G3Metric>? onOpenMetric;
  final ValueChanged<G3Activity>? onOpenActivity;
  final VoidCallback? onOpenSleep;
  const OpenBandHeute({
    super.key,
    required this.controller,
    this.initialAnchor,
    this.reminder = const NotificationHeuteReminder(),
    this.onProfile,
    this.onBand,
    this.onConnect,
    this.onAddActivity,
    this.onJournal,
    this.onOpenMetric,
    this.onOpenActivity,
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

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  static String _hm(num minutes) {
    final m = minutes.round();
    return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
  }

  static String _signedMinutes(int d) {
    final s = d < 0 ? '−' : '+';
    final a = d.abs();
    return a < 60
        ? '$s$a Min.'
        : '$s${a ~/ 60}h${(a % 60).toString().padLeft(2, '0')}';
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
    final stored = band.latestStoredAt;
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
      _sync(isToday, never, stale, gap, day, synthetic, now),
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
                : 'Letzte Übertragung ${_relative(stored, now)}. Die Nacht liegt auf dem Band und kommt beim Verbinden.',
            retryLabel: 'Verbinden',
            onRetry: widget.onConnect,
          ),
        ),
      ],
      if (day != null || never) ...[
        const SizedBox(height: 12),
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
        if (stored != null)
          OBFooterStamp(
            [
              'Letzter Bandwert ${_relative(stored, now)}',
              if (band.receivedAt != null)
                'Übertragung ${_relative(band.receivedAt!, now)}',
            ].join(' · '),
            synthetic: synthetic,
          ),
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
              child: ColoredBox(
                color: g.page.withValues(alpha: .95),
                child: OBPageHeader.compact(
                  title: isToday
                      ? 'Heute'
                      : DateFormat(
                          'EEEE',
                          'de_DE',
                        ).format(DateTime.parse(c.selectedDay)),
                  subtitle: [
                    DateFormat('E dd.MM', 'de_DE')
                        .format(DateTime.parse(c.selectedDay))
                        .replaceAll('.,', '')
                        .replaceFirst('. ', ' '),
                    if (synthetic) 'Synthetische Daten',
                  ].join(' · '),
                  band: OBBandCapsule(
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
            ),
        ],
      ),
    );
  }

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );

  String _relative(DateTime t, DateTime now) {
    final d = dayLabelOf(t);
    if (d == dayLabelOf(now)) return _clock(t);
    if (d == dayLabelOf(DateTime(now.year, now.month, now.day - 1))) {
      return 'gestern ${_clock(t)}';
    }
    return '${DateFormat('dd.MM.').format(t)} ${_clock(t)}';
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
    // Calendar days, not 24 h spans: a local span across a DST change is
    // 23 or 25 h. UTC dates have none.
    final ago = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
    final title = isToday ? 'Heute' : DateFormat('EEEE', 'de_DE').format(day);
    final date = DateFormat('d. MMMM', 'de_DE').format(day);
    final subtitle = isToday
        ? DateFormat('EEEE, d. MMMM', 'de_DE').format(day)
        : ago == 1
        ? '$date · gestern'
        : '$date · vor $ago Tagen';
    return OBPageHeader.hub(
      title: title,
      subtitle: subtitle,
      band: OBBandCapsule(
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
          (
            DateFormat(
              'E',
              'de_DE',
            ).format(DateTime.parse(d)).replaceAll('.', ''),
            DateTime.parse(d).day.toString(),
          ),
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
  ) {
    final stored = c.band.latestStoredAt;
    final (OBSyncKind kind, String text) = never
        ? (OBSyncKind.never, 'Noch kein Band verbunden')
        : !isToday
        ? (OBSyncKind.past, 'Gespeicherter Tag')
        : stale
        ? (
            OBSyncKind.stale,
            stored == null
                ? 'Getrennt · noch keine Daten'
                : 'Getrennt · Daten bis ${_relative(stored, now)}',
          )
        : (
            gap != null ? OBSyncKind.partial : OBSyncKind.live,
            [
              if (stored != null) 'Daten bis ${_relative(stored, now)}',
              if (day?.sleep.duration.value == null)
                'keine Nacht'
              else
                gap != null ? 'Nacht mit Lücke' : 'Nacht lückenlos',
            ].join(' · '),
          );
    return OBSyncState(
      kind: kind,
      text: text,
      synthetic: synthetic,
      onTap: widget.onBand,
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
        label: 'ERHOLUNG',
        note: 'Basis im Aufbau',
        state: OBLeadState.building,
        have: baseline?.status.nightsHave,
        need: need,
        title: 'Noch keine Erholung',
        reason: need == null
            ? 'Sie braucht eine Basis aus deinen Nächten.'
            : 'Sie braucht $need Nächte als Basis.',
        onTap: widget.onOpenMetric == null ? null : open,
      );
    } else if (value != null) {
      lead = OBLeadMetric(
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
            ? 'Erinnerung um ${_clock(action.reminderAt)}'
            : action?.label,
        actionSubtitle: armed
            ? '15 Min. vor ${action.label.split(' ').first} · abbestellen'
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
        'Keine Erinnerung gestellt: ${_clock(action.reminderAt)} ist schon vorbei.',
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
    final sport = obSport(a.sport);
    final unconfirmed = a.source == G3ActivitySource.auto && !a.confirmed;
    final end = a.end;
    final minutes = a.duration?.inMinutes;
    return OBActivityRow(
      pictogram: OBSportIcon(sport.icon, size: 24, color: g.ink),
      title: sport.label,
      subtitle: [
        end == null
            ? 'seit ${_clock(a.start)}'
            : '${_clock(a.start)}–${_clock(end)}',
        if (minutes != null) '$minutes Min.',
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

  static const _sports = [
    'running',
    'walking',
    'cycling',
    'hiking',
    'strength',
    'other',
  ];

  Future<void> _suggestion(G3Activity a) async {
    var sport = a.sport;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          final g = G3.of(sheet);
          final meta = obSport(sport);
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
                  ? 'seit ${_clock(a.start)}'
                  : '${_clock(a.start)}–${_clock(a.end!)}',
              if (a.duration != null) '${a.duration!.inMinutes} Min.',
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
                      for (final s in _sports)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OBListRow(
                            leading: OBSportIcon(
                              obSport(s).icon,
                              size: 18,
                              color: g.ink,
                            ),
                            title: obSport(s).label,
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
                      child: OBSportIcon(meta.icon, size: 24, color: g.ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        meta.label,
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
    final open = ci.questions.where((q) => q.value == null).toList();
    if (open.isEmpty) return null;
    final Widget card;
    if (_checkInLater) {
      card = OBCheckIn(
        state: OBCheckInState.later,
        progress: '${open.length} offen',
        onResume: () => setState(() => _checkInLater = false),
      );
    } else {
      final q = open.first;
      final done = ci.questions.where((x) => x.value != null).toList();
      final last = done.isEmpty ? null : done.last;
      final copy = heuteRatingCopy(q.field.key);
      card = OBCheckInRating(
        progress: '${ci.answered + 1} von ${ci.total}',
        question: copy.question,
        low: copy.low,
        high: copy.high,
        max: q.field.max.round(),
        answered: last == null
            ? null
            : '${journalFieldTitle(last.field)}: ${last.value!.value.round()} von ${last.field.max.round()}',
        onChange: last == null ? null : widget.onJournal,
        onRate: (v) => _answer(q.field.key, v),
        onLater: () => setState(() => _checkInLater = true),
      );
    }
    return [const SizedBox(height: 12), _pad(card)];
  }

  Future<void> _answer(String key, int value) async {
    final day = c.selectedDay;
    try {
      await repo.answerCheckIn(day, key, JournalMetricValue(value.toDouble()));
      final fresh = await repo.readCheckIn(day);
      if (!mounted || c.selectedDay != day) return;
      setState(
        () => _data = _copy(reminderAt: _data.reminderAt, checkIn: fresh),
      );
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
      Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(child: OBSectionHeader('WOCHE')),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: OBSegmented(
                items: const ['Erholung', 'Schlaf', 'Belastung'],
                selected: selected.index,
                disabled: recoveryEmpty ? const {0} : const {},
                onChanged: (i) => setState(() => _week = _Week.values[i]),
              ),
            ),
          ],
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
        : DateFormat(
            'E',
            'de_DE',
          ).format(DateTime.parse(d)).replaceAll('.', '');
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
          bars: bars,
          max: 111,
          band: range == null ? null : (range.low, range.high),
          emptyReason: empty
              ? (need != null && left != null
                    ? 'Erholung braucht $need Nächte · noch $left'
                    : 'Keine Erholung in dieser Woche')
              : null,
          footer: [
            if (range != null)
              G3Legend.band(
                'dein Normalbereich ${_int(range.low)}–${_int(range.high)}',
              )
            else
              const G3Legend.text('noch kein Normalbereich'),
            if (below > 0)
              G3Legend.mark(
                '$below ${below == 1 ? 'Tag' : 'Tage'} darunter',
                G3Deviation.worse,
              ),
            if (above > 0)
              G3Legend.mark(
                '$above ${above == 1 ? 'Tag' : 'Tage'} darüber',
                G3Deviation.better,
              ),
          ],
        );
      case _Week.sleep:
        final goal = strip?.goal;
        final recoveryEmpty = (_data.week[G3Metric.recovery]?.days ?? const [])
            .every((d) => d.value == null);
        return OBWeekBars(
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
            if (recoveryEmpty)
              const G3Legend.text('Erholung: noch keine Werte'),
          ],
        );
      case _Week.strain:
        return OBWeekBars(
          bars: bars,
          max: 21,
          emptyReason: empty ? 'Keine Belastung in dieser Woche' : null,
          footer: const [G3Legend.text('Skala 0–21 · kein Normalbereich')],
        );
    }
  }

  // ---------------------------------------------------------------------
  // night

  Widget _night(OpenBandDay day, double? gap) {
    final s = day.sleep;
    final asleep = s.duration.value;
    if (asleep == null) return const OBNightCard(state: OBNightState.missing);
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
    String? wakeText(double? v) =>
        v == null ? null : (v < 60 ? '${v.round()} Min.' : _hm(v));
    final mid = onset != null && wake != null
        ? onset.add(wake.difference(onset) ~/ 2)
        : null;
    final firstGap = gaps.isEmpty || onset == null ? null : gaps.first;
    final bed = s.bedMinutes;
    final totals = [
      (OBStage.deep, m(s.deepMinutes)),
      (OBStage.light, m(s.lightMinutes)),
      (OBStage.rem, m(s.remMinutes)),
      (OBStage.wake, wakeText(s.awakeMinutes)),
    ];
    if (segments.isEmpty) {
      // No stored timeline: totals only, never empty lanes that read as data.
      return _nightTotals(asleep, bed, totals);
    }
    return OBNightCard(
      state: gap != null ? OBNightState.gap : OBNightState.full,
      note: gap != null ? '${gap.round()} Min. Lücke' : 'lückenlos',
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
          : '${_clock(onset!.add(Duration(seconds: (firstGap.$1 * 60).round())))}–${_clock(onset.add(Duration(seconds: (firstGap.$2 * 60).round())))} ohne Daten · nicht aufgefüllt',
      axis: onset == null || wake == null || mid == null
          ? ('', '', '')
          : (_clock(onset), _clock(mid), _clock(wake)),
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
      OBStage.deep => g.stageDeep,
      OBStage.light => g.stageLight,
      OBStage.rem => g.stageRem,
      OBStage.wake => g.wake,
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
              const G3LabelRow('NACHT', note: 'ohne Verlauf'),
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
        return OBBodyRow(state: OBBodyState.missing, name: name, onTap: tap);
      }
      final text = g3Number(value, digits: digits);
      if (range != null) {
        final pad = (range.high - range.low) * .6;
        return OBBodyRow(
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
        state: OBBodyState.building,
        name: name,
        value: text,
        unit: unit,
        note: base?.status.phase == BaselinePhase.building
            ? (left == null ? 'Basis im Aufbau' : 'Basis: noch $left Nächte')
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
              state: OBBodyState.missing,
              name: 'Hauttemperatur',
              last: true,
              onTap: widget.onOpenMetric == null
                  ? null
                  : () => open(G3Metric.skinTempZ),
            )
          : OBBodyRow(
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
    final hrvBase = _data.ranges[G3Metric.hrv];
    final building = hrvBase?.status.phase == BaselinePhase.building;
    final left = hrvBase?.status.remaining;
    return OBPanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OBCardHeader(
            'KÖRPER',
            note: building
                ? (left == null
                      ? 'Basis im Aufbau'
                      : 'Basis: noch $left Nächte')
                : 'vergangene Nacht',
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
      total: total,
      note: last != null && isToday
          ? 'Zähler im Band · bis ${_clock(last)}'
          : 'Zähler im Band',
      hourly: total == null ? const [] : hourly,
      goalLabel: null,
    );
  }
}
