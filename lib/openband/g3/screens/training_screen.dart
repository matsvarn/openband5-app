import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/day_label.dart';
import '../../controller.dart';
import '../../domain.dart';
import '../../tab_bar.dart' show kOBTabBarContentInset;
import '../charts.dart'
    show OBHrTrace, OBTrendChart, OBTrendPeriod, OBZone, OBZoneRows;
import '../day.dart' as day_widgets show OBWeekBar, OBWeekBars;
import '../chrome.dart'
    show
        OBBandCapsule,
        OBBandState,
        OBSyncKind,
        OBSyncState,
        OBActionPrimary,
        OBActionSecondary,
        OBPageHeader,
        OBFooterStamp,
        OBSheet;
import '../g3_theme.dart';
import '../training_parts.dart';

typedef TrainingAction = Future<void> Function();

class G3TrainingScreen extends StatefulWidget {
  final OpenBandController controller;
  final ValueChanged<String>? onStart;
  final TrainingAction? onManual;
  final VoidCallback? onProfile;
  final ScrollController? scrollController;
  const G3TrainingScreen({
    super.key,
    required this.controller,
    this.onStart,
    this.onManual,
    this.onProfile,
    this.scrollController,
  });

  @override
  State<G3TrainingScreen> createState() => _G3TrainingScreenState();
}

class _TrainingData {
  final OpenBandDay day;
  final List<G3Activity> activities;
  final G3WeeklyLoad weekly;
  const _TrainingData(this.day, this.activities, this.weekly);
}

class _G3TrainingScreenState extends State<G3TrainingScreen> {
  final Set<String> _confirming = {};
  late ScrollController _scroll;
  late bool _compact;
  late Future<_TrainingData> _data;
  late String _day;
  late int _revision;

  @override
  void initState() {
    super.initState();
    _day = widget.controller.selectedDay;
    _revision = widget.controller.refreshRequest;
    _scroll = widget.scrollController ?? ScrollController();
    _compact = _scroll.initialScrollOffset > 120;
    _scroll.addListener(_scrollChanged);
    _data = _read();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(G3TrainingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _scroll.removeListener(_scrollChanged);
      if (oldWidget.scrollController == null) _scroll.dispose();
      _scroll = widget.scrollController ?? ScrollController();
      _scroll.addListener(_scrollChanged);
      _scrollChanged();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      _reload();
    }
  }

  void _scrollChanged() {
    final compact = _scroll.hasClients && _scroll.offset > 120;
    if (compact != _compact && mounted) setState(() => _compact = compact);
  }

  void _controllerChanged() {
    if (_day != widget.controller.selectedDay ||
        _revision != widget.controller.refreshRequest) {
      _reload();
    }
  }

  void _reload() {
    _day = widget.controller.selectedDay;
    _revision = widget.controller.refreshRequest;
    if (mounted) {
      setState(() {
        _data = _read();
      });
    }
  }

  Future<_TrainingData> _read() async {
    final repo = widget.controller.repository;
    final day = _day;
    final values = await Future.wait([
      repo.readDay(day),
      repo.readWeeklyLoad(day),
      Future.wait([
        for (final d in g3DaysEnding(day, 7)) repo.readActivities(d),
      ]),
    ]);
    final activities =
        (values[2] as List<List<G3Activity>>).expand((v) => v).toList()
          ..sort((a, b) => b.start.compareTo(a.start));
    return _TrainingData(
      values[0] as OpenBandDay,
      activities,
      values[1] as G3WeeklyLoad,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _scroll.removeListener(_scrollChanged);
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  Future<void> _datePicker() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: widget.controller.now(),
      initialDate: DateTime.parse(_day),
    );
    if (selected != null) {
      await widget.controller.selectDay(dayLabelOf(selected));
    }
  }

  Future<void> _manual() async {
    await widget.onManual?.call();
    if (mounted) _reload();
  }

  Future<void> _confirmSuggestion(G3Activity activity) async {
    if (!_confirming.add(activity.id)) return;
    setState(() {});
    try {
      await widget.controller.repository.confirmSuggestion(activity.id);
      if (mounted) {
        _reload();
        await _data;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bestätigung fehlgeschlagen. Erneut versuchen.'),
          ),
        );
      }
    } finally {
      _confirming.remove(activity.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _start() async {
    String? selectedSport;
    var showAll = false;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: OBSheet(
              title: 'Training starten',
              onCancel: () => Navigator.of(c).pop(),
              onConfirm: selectedSport == null
                  ? null
                  : () => Navigator.of(c).pop(selectedSport),
              confirmLabel: 'Starten',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GridView.count(
                    crossAxisCount: 4,
                    childAspectRatio: .9,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final sport in trainingSports.take(
                        showAll ? trainingSports.length : 8,
                      ))
                        OBSportTile(
                          sport: sport,
                          selected: selectedSport == sport,
                          onTap: () => update(() => selectedSport = sport),
                        ),
                    ],
                  ),
                  if (!showAll)
                    TextButton(
                      onPressed: () => update(() => showAll = true),
                      child: const Text('Weitere …'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && selected != null) widget.onStart?.call(selected);
  }

  void _detectionHelp() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aktivitätserkennung',
                style: G3.of(c).t(22, 28, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Längere Bewegung mit erhöhtem Puls kann als Training vorgeschlagen werden. Du prüfst und bestätigst die Sportart, bevor Zonen erscheinen.',
                style: G3.of(c).t(15, 21),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openActivity(G3Activity activity) {
    Navigator.of(context).push(
      g3ActivityResultRoute(
        repository: widget.controller.repository,
        activity: activity,
        onChanged: _reload,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return ColoredBox(
      color: g.page,
      child: FutureBuilder<_TrainingData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return _error(context, _reload);
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final current = _day == todayLabel(widget.controller.now());
          final stamp = widget.controller.band.latestStoredAt;
          final clock = current && stamp != null
              ? DateFormat.Hm('de_DE').format(stamp)
              : null;
          final activities = data.activities
              .where((a) => dayLabelOf(a.start) == _day)
              .toList();
          final emptyWeek = data.activities.isEmpty;
          return Stack(
            children: [
              ListView(
                controller: _scroll,
                key: const PageStorageKey('g3.training'),
                padding: const EdgeInsets.only(
                  top: 4,
                  bottom: kOBTabBarContentInset,
                ),
                children: [
                  OBPageHeader.hub(
                    title: 'Training',
                    subtitle: DateFormat(
                      'EEEE, d. MMMM',
                      'de_DE',
                    ).format(DateTime.parse(_day)),
                    band: OBBandCapsule(
                      state: switch (widget.controller.band.connection) {
                        BandConnection.connected => OBBandState.live,
                        BandConnection.disconnected => OBBandState.off,
                        BandConnection.connecting => OBBandState.off,
                      },
                      battery: widget.controller.band.batteryPercent,
                    ),
                    onTitle: _datePicker,
                    onProfile: widget.onProfile,
                  ),
                  OBSyncState(
                    kind: clock == null ? OBSyncKind.never : OBSyncKind.partial,
                    text: clock == null
                        ? 'Noch kein Datenstand'
                        : 'Daten bis $clock',
                    synthetic: data.day.synthetic,
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OBLoadLead(
                          value: data.day.strain.value,
                          countTime: clock,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => G3LoadScreen(
                                controller: widget.controller,
                                activity: activities.isEmpty
                                    ? null
                                    : activities.first,
                                weekly: data.weekly,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OBActionPrimary(
                                'Training starten',
                                onPressed: widget.onStart == null
                                    ? null
                                    : _start,
                                expand: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OBActionSecondary(
                                'Nachtragen',
                                onPressed: widget.onManual == null
                                    ? null
                                    : _manual,
                                expand: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          emptyWeek ? 'AKTIVITÄTEN' : 'HEUTE',
                          style: g.caps(color: g.muted),
                        ),
                        const SizedBox(height: 8),
                        if (activities.isEmpty)
                          _card(
                            context,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (emptyWeek) ...[
                                  const SizedBox(height: 22),
                                  Icon(
                                    LucideIcons.activity,
                                    size: 30,
                                    color: g.ink2,
                                  ),
                                  const SizedBox(height: 18),
                                ],
                                Text(
                                  'Noch keine Aktivität',
                                  style: g.t(17, 22, weight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  emptyWeek
                                      ? 'Längere Bewegung mit erhöhtem Puls schlägt das Band hier vor. Du kannst auch starten oder nachtragen.'
                                      : 'Einheiten erscheinen hier, sobald du sie startest oder nachträgst.',
                                  style: g.t(13, 18, color: g.ink2),
                                ),
                                if (emptyWeek)
                                  TextButton(
                                    onPressed: _detectionHelp,
                                    child: const Text(
                                      'Wie die Erkennung arbeitet',
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          for (final a in activities) ...[
                            _activityRow(
                              context,
                              a,
                              () => _openActivity(a),
                              _confirming.contains(a.id)
                                  ? null
                                  : () => _confirmSuggestion(a),
                            ),
                            const SizedBox(height: 10),
                          ],
                        const SizedBox(height: 4),
                        if (!emptyWeek ||
                            data.weekly.atl != null ||
                            data.weekly.ctl != null) ...[
                          OBTrainingLoad(
                            load: data.weekly,
                            onMethod: () => _method(context),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Text('WOCHE', style: g.caps(color: g.muted)),
                        const SizedBox(height: 8),
                        _week(context, data.weekly.days, today: current),
                        const SizedBox(height: 20),
                        if (data.activities.any(
                          (a) => dayLabelOf(a.start) != _day,
                        )) ...[
                          Text('ZULETZT', style: g.caps(color: g.muted)),
                          const SizedBox(height: 8),
                          _recentCard(
                            context,
                            data.activities
                                .where((a) => dayLabelOf(a.start) != _day)
                                .take(5)
                                .toList(),
                            _openActivity,
                          ),
                        ],
                      ],
                    ),
                  ),
                  OBFooterStamp(
                    clock == null ? 'Datenstand offen' : 'Daten bis $clock',
                    synthetic: data.day.synthetic,
                  ),
                ],
              ),
              if (_compact)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ColoredBox(
                    color: g.page,
                    child: OBPageHeader.compact(
                      title: 'Training',
                      subtitle:
                          '${DateFormat('EEE dd.MM', 'de_DE').format(DateTime.parse(_day)).replaceFirst('.', '')}${data.day.synthetic ? ' · Synthetische Daten' : ''}',
                      band: OBBandCapsule(
                        small: true,
                        state:
                            widget.controller.band.connection ==
                                BandConnection.connected
                            ? OBBandState.live
                            : OBBandState.off,
                        battery: widget.controller.band.batteryPercent,
                      ),
                      onProfile: widget.onProfile,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Widget _card(BuildContext context, Widget child) => Container(
  padding: const EdgeInsets.all(18),
  decoration: G3.of(context).raised(),
  child: child,
);

Widget _error(BuildContext context, VoidCallback retry) {
  final g = G3.of(context);
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Training konnte nicht geladen werden.', style: g.t(15, 20)),
        const SizedBox(height: 12),
        OBActionSecondary('Erneut laden', onPressed: retry),
      ],
    ),
  );
}

Widget _week(
  BuildContext context,
  List<MetricPoint> days, {
  required bool today,
}) {
  final g = G3.of(context);
  final whole = days
      .take(days.length - 1)
      .map((p) => p.value)
      .whereType<double>()
      .toList();
  return day_widgets.OBWeekBars(
    max: 21,
    bars: [
      for (final (index, point) in days.indexed)
        day_widgets.OBWeekBar(
          today && index == days.length - 1
              ? 'Heute'
              : DateFormat.E('de_DE').format(DateTime.parse(point.day)),
          point.value,
          label: point.value == null ? null : trainingNumber(point.value),
          today: today && index == days.length - 1,
        ),
    ],
    footer: [
      Text('Belastung je Tag · 0–21', style: g.t(12, 16, color: g.muted)),
      if (whole.length == 6)
        Text(
          'Ø ${trainingNumber(whole.reduce((a, b) => a + b) / whole.length)} · 6 ganze Tage',
          style: g.t(12, 16, color: g.ink2),
        ),
    ],
  );
}

Widget _recentCard(
  BuildContext context,
  List<G3Activity> activities,
  ValueChanged<G3Activity> open,
) {
  final g = G3.of(context);
  return _card(
    context,
    Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('AKTIVITÄTEN', style: g.caps())),
            Text('Belastung', style: g.t(12, 16, color: g.muted)),
          ],
        ),
        const SizedBox(height: 12),
        for (final a in activities)
          InkWell(
            onTap: () => open(a),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: g.track,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: trainingSportIcon(a.sport, size: 20, color: g.ink),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trainingSport(a.sport),
                          style: g.t(14, 18, weight: FontWeight.w700),
                        ),
                        Text(
                          '${DateFormat('E dd.MM', 'de_DE').format(a.start)}${a.source == G3ActivitySource.manual ? ' · nachgetragen' : ''}',
                          style: g.t(12, 16, color: g.ink2),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        trainingNumber(a.strain, signed: true),
                        style: g.t(15, 19, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.chevronRight, size: 16, color: g.muted),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _activityRow(
  BuildContext context,
  G3Activity a,
  VoidCallback open,
  VoidCallback? confirm,
) {
  final g = G3.of(context);
  return _card(
    context,
    Column(
      children: [
        InkWell(
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: g.track,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: trainingSportIcon(a.sport, color: g.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              trainingSport(a.sport),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: g.t(18, 22, weight: FontWeight.w700),
                            ),
                          ),
                          if (!a.confirmed &&
                              a.source == G3ActivitySource.auto) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: g.chip,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'auto-erkannt',
                                style: g.t(11, 14, color: g.ink2),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${DateFormat.Hm('de_DE').format(a.start)}–${a.end == null ? '—' : DateFormat.Hm('de_DE').format(a.end!)} · ${a.duration?.inMinutes ?? '—'} Min.',
                        style: g.t(12, 16, color: g.ink2),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      trainingNumber(a.strain, signed: true),
                      style: g.t(18, 22, weight: FontWeight.w700),
                    ),
                    Text('Belastung', style: g.t(11, 14, color: g.muted)),
                  ],
                ),
                const SizedBox(width: 5),
                Icon(LucideIcons.chevronRight, size: 17, color: g.muted),
              ],
            ),
          ),
        ),
        if (!a.confirmed && a.source == G3ActivitySource.auto) ...[
          Divider(color: g.line),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sportart richtig?',
                  style: g.t(12, 16, color: g.ink2),
                ),
              ),
              OBActionPrimary(
                'Stimmt',
                icon: LucideIcons.check,
                onPressed: confirm,
                height: 30,
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

void _method(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Trainingslast vergleicht die akute Last der letzten 7 Tage mit der gewohnten Last aus 6 Wochen. Grundlage ist tägliches TRIMP in einer eigenen Einheit.',
        style: G3.of(c).t(16, 22),
      ),
    ),
  ),
);

void _loadInfo(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Die Tagesbelastung liegt auf einer festen Skala von 0 bis 21. Sie hat keinen persönlichen Bereich. Wenig Tragezeit kann den Wert kleiner und den Tag schwer vergleichbar machen.',
        style: G3.of(c).t(16, 22),
      ),
    ),
  ),
);

void _resultInfo(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Pulserholung ist der Pulsabfall in der ersten Minute nach Ende. Lücken im Pulssignal bleiben leer.',
        style: G3.of(c).t(16, 22),
      ),
    ),
  ),
);

class G3SuggestionRoute extends StatelessWidget {
  final OpenBandRepository? repository;
  final String? focusId;
  const G3SuggestionRoute({super.key, required this.repository, this.focusId});

  @override
  Widget build(BuildContext context) => repository == null
      ? Scaffold(
          body: Center(
            child: Text(
              'Trainingsvorschlag konnte nicht geladen werden.',
              style: G3.of(context).t(15, 20),
            ),
          ),
        )
      : FutureBuilder<List<G3Activity>>(
          future: repository!.readActivities(todayLabel()),
          builder: (context, snap) {
            if (snap.hasError) {
              return _error(context, () => Navigator.of(context).maybePop());
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final pending = snap.data!.where(
              (a) => a.source == G3ActivitySource.auto && !a.confirmed,
            );
            G3Activity? target;
            for (final a in pending) {
              if (focusId == null || focusId == a.id) {
                target = a;
                break;
              }
            }
            if (target == null) {
              return Scaffold(
                body: Center(
                  child: Text(
                    'Kein offener Trainingsvorschlag.',
                    style: G3.of(context).t(15, 20),
                  ),
                ),
              );
            }
            return G3ActivityScreen(repository: repository!, activity: target);
          },
        );
}

/// Opens a stored activity from Training or another tab such as Heute.
/// Pass the repository activity unchanged so unknown sports and missing
/// metrics keep their stored state.
Route<void> g3ActivityResultRoute({
  required OpenBandRepository repository,
  required G3Activity activity,
  VoidCallback? onChanged,
}) => MaterialPageRoute<void>(
  builder: (_) => G3ActivityScreen(
    repository: repository,
    activity: activity,
    onChanged: onChanged,
  ),
);

class G3ActivityScreen extends StatefulWidget {
  final OpenBandRepository repository;
  final G3Activity activity;
  final VoidCallback? onChanged;
  final String? initialSheet;
  final String? initialSportSelection;
  final ScrollController? scrollController;
  const G3ActivityScreen({
    super.key,
    required this.repository,
    required this.activity,
    this.onChanged,
    this.initialSheet,
    this.initialSportSelection,
    this.scrollController,
  });

  @override
  State<G3ActivityScreen> createState() => _G3ActivityScreenState();
}

class _G3ActivityScreenState extends State<G3ActivityScreen> {
  late G3Activity _activity = widget.activity;
  late final Future<OpenBandDay> _day = widget.repository.readDay(
    dayLabelOf(widget.activity.start),
  );
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSheet != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.initialSheet == 'sport') _sportPicker();
        if (widget.initialSheet == 'dismiss') _dismissSuggestion();
      });
    }
  }

  Future<void> _refresh({String? savedId}) async {
    final all = await widget.repository.readActivities(
      dayLabelOf(_activity.start),
    );
    if (!mounted) return;
    final current =
        all.where((a) => a.id == (savedId ?? _activity.id)).firstOrNull ??
        all.where((a) => a.start == _activity.start && a.confirmed).firstOrNull;
    if (current != null) setState(() => _activity = current);
    widget.onChanged?.call();
  }

  Future<void> _confirm({String? sport}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final savedId = await widget.repository.confirmSuggestion(
        _activity.id,
        sport: sport,
      );
      await _refresh(savedId: savedId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Training konnte nicht bestätigt werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sportPicker() async {
    if (_busy) return;
    var selected = widget.initialSportSelection ?? _activity.sport;
    final sport = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final g = G3.of(c);
          const sports = trainingSports;
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: g.gap,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sportart ändern',
                            style: g.t(22, 28, weight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Schließen',
                          onPressed: () => Navigator.of(c).pop(),
                          icon: const Icon(LucideIcons.x),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Erkannt: ${trainingSport(_activity.sport)} ${DateFormat.Hm('de_DE').format(_activity.start)}–${_activity.end == null ? '—' : DateFormat.Hm('de_DE').format(_activity.end!)}. Puls und Belastung bleiben gleich.',
                      style: g.t(13, 18, color: g.ink2),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 4,
                      childAspectRatio: .94,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final s in sports)
                          OBSportTile(
                            sport: s,
                            selected: selected == s,
                            onTap: () => update(() => selected = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OBActionSecondary(
                      'Kein Training',
                      onPressed: () => Navigator.of(c).pop('dismiss'),
                      expand: true,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OBActionSecondary(
                            'Abbrechen',
                            onPressed: () => Navigator.of(c).pop(),
                            expand: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OBActionPrimary(
                            'Als ${trainingSport(selected)} speichern',
                            onPressed: () => Navigator.of(c).pop(selected),
                            expand: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || sport == null) return;
    if (sport == 'dismiss') {
      await _dismissSuggestion();
    } else {
      await _confirm(sport: sport);
    }
  }

  Future<void> _dismissSuggestion() async {
    final yes = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kein Training?',
                style: G3.of(c).t(20, 24, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${trainingSport(_activity.sport)} wird nicht als Aktivität gezählt.',
                style: G3.of(c).t(14, 19),
              ),
              const SizedBox(height: 12),
              Text(
                'Deine Pulswerte und die Belastung des Tages bleiben gespeichert.',
                style: G3.of(c).t(14, 19),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OBActionSecondary(
                      'Abbrechen',
                      onPressed: () => Navigator.of(c).pop(false),
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OBActionPrimary(
                      'Kein Training',
                      onPressed: () => Navigator.of(c).pop(true),
                      expand: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (yes != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.dismissSuggestion(_activity.id);
      widget.onChanged?.call();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vorschlag konnte nicht entfernt werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context), a = _activity;
    final duration = a.duration?.inMinutes;
    final confirmed = a.confirmed || a.source != G3ActivitySource.auto;
    final zones = confirmed && a.zoneMinutes != null;
    final basis = a.zoneBasis;
    final hfmax =
        basis?.kind == G3ZoneBasisKind.hfmaxEstimated ||
        basis?.kind == G3ZoneBasisKind.hfmaxObserved;
    final reserve = basis?.kind == G3ZoneBasisKind.heartRateReserve;
    final minutes = a.hrTrace
        .where((p) => p.meanBpm != null)
        .map((p) => (p.at.difference(a.start).inSeconds / 60, p.meanBpm!))
        .toList();
    final gaps = a.signalGaps
        .map(
          (gp) => (
            gp.start.difference(a.start).inSeconds / 60,
            gp.end.difference(a.start).inSeconds / 60,
          ),
        )
        .toList();
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.only(top: 4, bottom: kOBTabBarContentInset),
          children: [
            OBPageHeader.detail(
              title: 'EINHEIT',
              backLabel: 'Training',
              onBack: () => Navigator.of(context).maybePop(),
              onTrailing: () => _resultInfo(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: g.ink,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        alignment: Alignment.center,
                        child: trainingSportIcon(
                          a.sport,
                          size: 28,
                          color: g.canvas,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trainingSport(a.sport),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: g.t(30, 34, weight: FontWeight.w700),
                            ),
                            Text(
                              DateFormat(
                                'EEEE, d. MMMM',
                                'de_DE',
                              ).format(a.start),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: g.t(13, 17, color: g.ink2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _figure(
                        context,
                        'DAUER',
                        duration == null ? '—' : '$duration',
                        unit: duration == null ? null : 'Min.',
                        sub: a.end == null
                            ? null
                            : '${DateFormat.Hm('de_DE').format(a.start)}–${DateFormat.Hm('de_DE').format(a.end!)}',
                      ),
                      Container(
                        width: 1,
                        height: 67,
                        color: g.line,
                        margin: EdgeInsets.symmetric(
                          horizontal:
                              MediaQuery.textScalerOf(context).scale(1) > 1.3
                              ? 4
                              : 10,
                        ),
                      ),
                      _figure(
                        context,
                        'BELASTUNG',
                        trainingNumber(a.strain, signed: true),
                        sub: a.strain == null ? null : 'diese Einheit',
                      ),
                      Container(
                        width: 1,
                        height: 67,
                        color: g.line,
                        margin: EdgeInsets.symmetric(
                          horizontal:
                              MediaQuery.textScalerOf(context).scale(1) > 1.3
                              ? 4
                              : 10,
                        ),
                      ),
                      _figure(context, 'STRECKE', '—', sub: '+ hinzufügen'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!confirmed) ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                      decoration: g.pressed(radius: 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Auto-erkannt als ${trainingSport(a.sport)}',
                                  style: g.t(14, 18, weight: FontWeight.w700),
                                ),
                                Text(
                                  'Zonen nach Bestätigung',
                                  style: g.t(12, 16, color: g.ink2),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _sportPicker,
                            child: const Text('Ändern'),
                          ),
                          OBActionPrimary(
                            'Stimmt',
                            icon: LucideIcons.check,
                            height: 34,
                            onPressed: _busy ? null : _confirm,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (a.hrTrace.isNotEmpty &&
                      duration != null &&
                      duration > 0) ...[
                    OBHrTrace(
                      samples: minutes,
                      duration: duration.toDouble(),
                      gaps: gaps,
                      // The current activity read model has no stored bpm
                      // edges. A max-HR formula would invent the bands.
                      zoneEdges: const [],
                      average: a.avgHr?.round().toString(),
                      peak: a.maxHr?.round().toString(),
                      axis: (
                        DateFormat.Hm('de_DE').format(a.start),
                        '',
                        a.end == null
                            ? '—'
                            : DateFormat.Hm('de_DE').format(a.end!),
                      ),
                      signalShare: a.opticalShare == null
                          ? null
                          : '${(a.opticalShare! * 100).round()} %',
                      signalSegments: signalSegmentsFromGaps(
                        duration.toDouble(),
                        gaps,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (zones) ...[
                    OBZoneRows(
                      zones: [
                        for (var i = 4; i >= 0; i--)
                          OBZone(i + 1, '', a.zoneMinutes![i].round()),
                      ],
                      basis: basis == null
                          ? 'Grundlage unbekannt'
                          : reserve
                          ? '% Pulsreserve'
                          : hfmax
                          ? '% HFmax'
                          : 'Grundlage unbekannt',
                      source: basis == null
                          ? 'Keine %-Angabe ohne bekannte Grundlage'
                          : reserve
                          ? 'Pulsreserve (Karvonen) · aus deinen Zonen'
                          : hfmax
                          ? 'HFmax ${basis.maxHr.round()} · ${_basisLabel(basis)}'
                          : 'Keine %-Angabe ohne bekannte Grundlage',
                      onBasis: () => showModalBottomSheet<void>(
                        context: context,
                        builder: (c) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            reserve
                                ? 'Zonen sind Anteile der gespeicherten Pulsreserve.'
                                : hfmax
                                ? 'Zonen sind Anteile der gespeicherten maximalen Herzfrequenz.'
                                : 'Die Grundlage dieser gespeicherten Zonen ist unbekannt.',
                            style: G3.of(c).t(16, 22),
                          ),
                        ),
                      ),
                    ),
                  ] else if (!confirmed && basis != null)
                    OBZoneRows(
                      zones: [
                        for (var i = 4; i >= 0; i--) OBZone(i + 1, '', null),
                      ],
                      basis: reserve
                          ? '% Pulsreserve'
                          : hfmax
                          ? '% HFmax'
                          : 'Grundlage unbekannt',
                      source: 'Zonen nach Bestätigung',
                    )
                  else
                    _card(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('ZEIT IN ZONEN', style: g.caps()),
                          const SizedBox(height: 10),
                          Text(
                            !confirmed
                                ? 'Zonen nach Bestätigung'
                                : 'Zonen nicht verfügbar',
                            style: g.t(14, 19, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  _card(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PULSERHOLUNG', style: g.caps()),
                        const SizedBox(height: 8),
                        Text(
                          a.hrRecoveryOneMinute == null
                              ? '—'
                              : '−${a.hrRecoveryOneMinute!.round()} /min in 1 Min.',
                          style: g.t(
                            25,
                            29,
                            weight: FontWeight.w700,
                            color: a.hrRecoveryOneMinute == null
                                ? g.gap
                                : g.ink,
                          ),
                        ),
                        if (a.hrRecoveryOneMinute == null) ...[
                          const SizedBox(height: 5),
                          Text(
                            a.source == G3ActivitySource.manual &&
                                    a.hrTrace.isEmpty
                                ? 'Kein Bandpuls in diesem Zeitraum.'
                                : 'Pulserholung nicht erfasst.',
                            style: g.t(13, 18, color: g.ink2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  FutureBuilder<OpenBandDay>(
                    future: _day,
                    builder: (context, snapshot) => OBFooterStamp(
                      'Gespeicherte Bandwerte',
                      synthetic: snapshot.data?.synthetic ?? false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _basisLabel(G3ZoneBasis basis) => switch (basis.kind) {
  G3ZoneBasisKind.hfmaxEstimated => 'geschätzt aus Alter',
  G3ZoneBasisKind.hfmaxObserved => 'gemessen',
  G3ZoneBasisKind.heartRateReserve => 'Pulsreserve',
};

/// Signal strip lengths come from the same real gaps that break the trace.
List<(int, bool)> signalSegmentsFromGaps(
  double durationMinutes,
  List<(double, double)> gaps,
) {
  final total = (durationMinutes * 60).round();
  if (total <= 0) return const [];
  final spans = [
    for (final (start, end) in gaps)
      if (end > start)
        (
          (start * 60).round().clamp(0, total),
          (end * 60).round().clamp(0, total),
        ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final result = <(int, bool)>[];
  void add(int length, bool gap) {
    if (length <= 0) return;
    if (result.isNotEmpty && result.last.$2 == gap) {
      result[result.length - 1] = (result.last.$1 + length, gap);
    } else {
      result.add((length, gap));
    }
  }

  var cursor = 0;
  for (final (start, end) in spans) {
    if (end <= cursor) continue;
    if (start > cursor) add(start - cursor, false);
    add(end - (start > cursor ? start : cursor), true);
    cursor = end;
  }
  if (cursor < total) add(total - cursor, false);
  return result;
}

Widget _figure(
  BuildContext context,
  String label,
  String value, {
  String? unit,
  String? sub,
}) {
  final g = G3.of(context);
  return Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: g.caps(color: g.muted, size: 11),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: g.t(
                    44,
                    48,
                    weight: FontWeight.w700,
                    color: value == '—' ? g.gap : g.ink,
                    tracking: -.04,
                  ),
                ),
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(' $unit', style: g.t(15, 18, color: g.ink2)),
              ),
          ],
        ),
        if (sub != null)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: g.t(
              13,
              16,
              color: g.ink2,
              weight: sub == '+ hinzufügen' ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
      ],
    ),
  );
}

class G3LoadScreen extends StatefulWidget {
  final OpenBandController controller;
  final G3Activity? activity;
  final G3WeeklyLoad weekly;
  final OBTrendPeriod initialPeriod;
  const G3LoadScreen({
    super.key,
    required this.controller,
    required this.activity,
    required this.weekly,
    this.initialPeriod = OBTrendPeriod.d30,
  });

  @override
  State<G3LoadScreen> createState() => _G3LoadScreenState();
}

class _G3LoadScreenState extends State<G3LoadScreen> {
  late OBTrendPeriod period = widget.initialPeriod;
  late Future<G3Trend> trend = _load();

  Future<G3Trend> _load() => widget.controller.repository.readTrend(
    G3Metric.strain,
    widget.controller.selectedDay,
    switch (period) {
      OBTrendPeriod.d7 => 7,
      OBTrendPeriod.d30 => 30,
      OBTrendPeriod.d90 => 90,
    },
  );

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Scaffold(
      backgroundColor: g.page,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<G3Trend>(
          future: trend,
          builder: (context, snap) {
            if (snap.hasError) {
              return _error(context, () => setState(() => trend = _load()));
            }
            final points = snap.data?.points ?? const <MetricPoint>[];
            final values = [for (final p in points) p.partial ? null : p.value];
            final present = values.whereType<double>().toList();
            final avg = present.isEmpty
                ? null
                : present.reduce((a, b) => a + b) / present.length;
            return ListView(
              padding: const EdgeInsets.only(
                top: 4,
                bottom: kOBTabBarContentInset,
              ),
              children: [
                OBPageHeader.detail(
                  title: 'BELASTUNG',
                  backLabel: 'Training',
                  onBack: () => Navigator.of(context).maybePop(),
                  onTrailing: () => _loadInfo(context),
                  subtitle: DateFormat(
                    'EEEE, d. MMMM',
                    'de_DE',
                  ).format(DateTime.parse(widget.controller.selectedDay)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OBLoadLead(
                        value: widget.controller.day?.strain.value,
                        countTime:
                            widget.controller.selectedDay ==
                                    todayLabel(widget.controller.now()) &&
                                widget.controller.day?.calculatedAt != null
                            ? DateFormat.Hm(
                                'de_DE',
                              ).format(widget.controller.day!.calculatedAt!)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      if (snap.hasData)
                        OBTrendChart(
                          title: 'BELASTUNG · 0–21',
                          period: period,
                          values: values,
                          min: 0,
                          max: 21,
                          xLabels: const ['', '', 'heute'],
                          footLeft: avg == null
                              ? 'Ø —'
                              : 'Ø ${trainingNumber(avg)}',
                          footRight: 'ohne persönlichen Bereich',
                          onPeriod: (next) => setState(() {
                            period = next;
                            trend = _load();
                          }),
                        )
                      else
                        const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 12),
                      Text('HEUTE BISHER', style: g.caps(color: g.muted)),
                      const SizedBox(height: 8),
                      _card(
                        context,
                        Text(
                          widget.activity == null
                              ? 'Noch keine Aktivität heute.'
                              : '${trainingSport(widget.activity!.sport)} · ${trainingNumber(widget.activity!.strain, signed: true)}',
                          style: g.t(15, 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OBTrainingLoad(
                        load: widget.weekly,
                        onMethod: () => _method(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
