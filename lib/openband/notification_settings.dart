import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../notify/notification_prefs.dart';
import '../notify/notification_service.dart';
import '../notify/tap_router.dart';
import 'release_scope.dart';
import '../state/app_state.dart';
import '../ui2/profile/band_notifications.dart';
import 'settings_controls.dart';
import 'theme.dart';
import 'time_picker.dart';

/// Paper Mitteilungen frames (light / dark / denied). Nested battery and
/// water rows still appear when those switches are on.
const openBandPaperNotificationPrefs = NotificationPrefs(
  remindersEnabled: false,
  autoDetectEnabled: false,
  movementEnabled: true,
  windDownEnabled: true,
  medsEnabled: true,
  checkInEnabled: true,
  waterEnabled: true,
  batteryAlertPct: 20,
);

/// Notification preferences. Load/save stay on [NotificationPrefs]; scheduling
/// still goes through AppState. The view never treats defaults as loaded state.
class NotificationSettings extends StatefulWidget {
  const NotificationSettings({
    super.key,
    this.loadPrefs,
    this.persistPrefs,
    this.readPermission,
    this.requestPermission,
    this.openSystemSettings,
    this.onRefreshReminders,
    this.onArmWater,
    this.onRefreshBattery,
    this.relaySupported,
    this.synthetic = false,
    this.releaseReduced = false,
  });

  final Future<NotificationPrefs> Function()? loadPrefs;
  final Future<void> Function(NotificationPrefs prefs)? persistPrefs;
  final Future<bool> Function()? readPermission;
  final Future<bool> Function()? requestPermission;
  final Future<void> Function()? openSystemSettings;
  final Future<void> Function()? onRefreshReminders;
  final Future<void> Function(NotificationPrefs prefs)? onArmWater;
  final Future<void> Function(NotificationPrefs prefs)? onRefreshBattery;
  final bool? relaySupported;
  final bool synthetic;

  /// Hides toggles whose tap would open a parked flow. Stored prefs stay.
  final bool releaseReduced;

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings>
    with WidgetsBindingObserver {
  NotificationPrefs? _committed;
  NotificationPrefs? _desired;
  NotificationPrefs? _saveRetry;
  bool? _granted;
  bool _busy = false;
  bool _flushing = false;
  int _permGen = 0;
  String? _loadError;
  String? _saveError;
  String? _applyError;
  String? _permissionError;
  bool _grantApplyPending = false;

  bool get _relaySupported =>
      widget.relaySupported ?? defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshPermission());
  }

  Future<void> _load() async {
    NotificationPrefs? prefs;
    String? prefsError;
    try {
      prefs = await (widget.loadPrefs ?? NotificationPrefs.load)();
    } catch (e) {
      prefsError = _shortError(e);
    }
    final gen = ++_permGen;
    bool? granted;
    String? permError;
    try {
      granted = await _readPermission();
    } catch (e) {
      permError = _shortError(e);
    }
    if (!mounted) return;
    setState(() {
      if (prefsError != null) {
        _committed = null;
        _desired = null;
        _saveRetry = null;
        _loadError = prefsError;
      } else {
        _committed = prefs;
        _desired = prefs;
        _saveRetry = null;
        _loadError = null;
      }
      _saveError = null;
      _applyError = null;
    });
    _applyPermission(gen, granted: granted, error: permError);
    await _applyCommittedIfGrantPending();
  }

  Future<bool> _readPermission() async {
    final read = widget.readPermission;
    if (read != null) return await read();
    return await NotificationService.instance.readPermissionStatus();
  }

  void _applyPermission(int gen, {bool? granted, String? error}) {
    if (gen != _permGen) return;
    final wasBlocked = _granted == false || _permissionError != null;
    if (mounted) {
      setState(() {
        _granted = granted;
        _permissionError = error;
      });
    } else {
      _granted = granted;
      _permissionError = error;
    }
    if (granted == true && error == null && wasBlocked) {
      _grantApplyPending = true;
    }
  }

  Future<void> _refreshPermission() async {
    if (mounted) _bindApply();
    final gen = ++_permGen;
    try {
      final granted = await _readPermission();
      _applyPermission(gen, granted: granted);
    } catch (e) {
      _applyPermission(gen, error: _shortError(e));
    }
    await _applyCommittedIfGrantPending();
  }

  Future<void> _applyCommittedIfGrantPending() async {
    if (!_grantApplyPending) return;
    if (_flushing) return;
    final prefs = _committed;
    if (prefs == null || (mounted && _granted != true)) {
      _grantApplyPending = false;
      return;
    }
    _grantApplyPending = false;
    _flushing = true;
    if (mounted) setState(() => _busy = true);
    try {
      await _refreshAll(prefs);
      _applyError = null;
      _mark();
    } catch (e) {
      _applyError = _shortError(e);
      _mark();
    } finally {
      _flushing = false;
      if (_grantApplyPending) {
        await _applyCommittedIfGrantPending();
      } else if (_desired != null &&
          _committed != null &&
          !_samePrefs(_desired!, _committed!)) {
        unawaited(_enqueue(_desired!));
      } else if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> Function(NotificationPrefs)? _persist;
  Future<void> Function(NotificationPrefs)? _apply;

  void _onEdit(NotificationPrefs Function(NotificationPrefs current) update) {
    final base = _desired ?? _committed;
    if (base == null) return;
    _saveRetry = null;
    unawaited(_enqueue(update(base)));
  }

  void _bindApply() {
    if (!mounted) return;
    _persist = widget.persistPrefs ?? (NotificationPrefs p) => p.save();
    final reminders = widget.onRefreshReminders;
    final water = widget.onArmWater;
    final battery = widget.onRefreshBattery;
    if (reminders != null || water != null || battery != null) {
      _apply = (prefs) => _runApply(prefs, reminders, water, battery);
      return;
    }
    final app = context.read<AppState>();
    _apply = (prefs) => _runApply(
      prefs,
      app.refreshAiReminders,
      app.armWaterReminder,
      app.refreshBatteryThreshold,
    );
  }

  void _mark() {
    if (mounted) setState(() {});
  }

  Future<void> _enqueue(NotificationPrefs next) async {
    _desired = next;
    if (_flushing) return;
    _flushing = true;
    if (mounted) {
      _bindApply();
      setState(() => _busy = true);
    }
    try {
      while (true) {
        final committed = _committed;
        final desired = _desired;
        if (desired == null ||
            committed == null ||
            _samePrefs(desired, committed)) {
          break;
        }
        final target = desired;
        try {
          await (_persist ??
              widget.persistPrefs ??
              (NotificationPrefs p) => p.save())(target);
        } catch (e) {
          _saveRetry = _desired ?? target;
          _desired = committed;
          _saveError = _shortError(e);
          _applyError = null;
          _mark();
          return;
        }
        _committed = target;
        _saveError = null;
        _saveRetry = null;
        _mark();
        try {
          await _refreshAll(target);
          _applyError = null;
          _mark();
        } catch (e) {
          _applyError = _shortError(e);
          _mark();
        }
      }
    } finally {
      _flushing = false;
      if (_grantApplyPending) {
        await _applyCommittedIfGrantPending();
      } else if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshAll(NotificationPrefs prefs) async {
    if (mounted) _bindApply();
    final apply = _apply;
    if (apply == null) return;
    await apply(prefs);
  }

  Future<void> _runApply(
    NotificationPrefs prefs,
    Future<void> Function()? reminders,
    Future<void> Function(NotificationPrefs)? water,
    Future<void> Function(NotificationPrefs)? battery,
  ) async {
    Object? error;
    Future<void> wrap(Future<void> Function() run) async {
      try {
        await run();
      } catch (e) {
        error ??= e;
      }
    }

    await wrap(() => (reminders ?? () async {})());
    await wrap(() => (water ?? (_) async {})(prefs));
    await wrap(() => (battery ?? (_) async {})(prefs));
    if (error != null) throw error!;
  }

  Future<void> _retrySave() async {
    final target = _saveRetry ?? _desired ?? _committed;
    if (target == null) return;
    _saveRetry = null;
    setState(() => _saveError = null);
    await _enqueue(target);
  }

  Future<void> _retryApply() async {
    final pending = _desired;
    final committed = _committed;
    if (pending != null &&
        committed != null &&
        !_samePrefs(pending, committed)) {
      await _enqueue(pending);
      return;
    }
    if (committed == null) return;
    if (mounted) setState(() => _busy = true);
    try {
      await _refreshAll(committed);
      if (mounted) setState(() => _applyError = null);
    } catch (e) {
      if (mounted) setState(() => _applyError = _shortError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPermission() async {
    if (_busy) return;
    var gen = ++_permGen;
    if (mounted) {
      _bindApply();
      setState(() => _busy = true);
    }
    try {
      bool granted;
      try {
        final request = widget.requestPermission;
        granted = request != null
            ? await request()
            : await NotificationService.instance.ensurePermission();
      } catch (e) {
        _applyPermission(gen, error: _shortError(e));
        return;
      }
      if (granted) {
        if (gen != _permGen) {
          gen = ++_permGen;
          try {
            granted = await _readPermission();
          } catch (e) {
            _applyPermission(gen, error: _shortError(e));
            return;
          }
          if (gen != _permGen) return;
          if (!granted) {
            _applyPermission(gen, granted: false);
            return;
          }
        }
        _applyPermission(gen, granted: true);
        await _applyCommittedIfGrantPending();
        return;
      }
      if (gen != _permGen) return;
      if (!mounted) return;
      _applyPermission(gen, granted: false);
      try {
        await (widget.openSystemSettings ?? Geolocator.openAppSettings)();
      } catch (e) {
        if (mounted && gen == _permGen) {
          setState(() => _permissionError = _shortError(e));
        }
      }
      if (gen != _permGen) return;
      await _refreshPermission();
    } finally {
      if (mounted && !_flushing) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationSettingsView(
      prefs: _committed ?? const NotificationPrefs(),
      loaded: _committed != null,
      granted: _granted,
      busy: _busy,
      relaySupported: _relaySupported,
      synthetic: widget.synthetic,
      releaseReduced: widget.releaseReduced,
      loadError: _loadError,
      permissionError: _permissionError,
      saveError: _saveError,
      applyError: _applyError,
      onEdit: _committed == null || _busy ? null : _onEdit,
      onRequestPermission: _busy ? null : _requestPermission,
      onRetryLoad: () => unawaited(_load()),
      onRetryPermission: () => unawaited(_refreshPermission()),
      onRetrySave: _saveError == null ? null : () => unawaited(_retrySave()),
      onRetryApply: _applyError == null ? null : () => unawaited(_retryApply()),
    );
  }
}

class NotificationSettingsView extends StatelessWidget {
  final NotificationPrefs prefs;
  final bool loaded;
  final bool? granted;
  final bool busy;
  final bool relaySupported;
  final bool synthetic;
  final bool releaseReduced;
  final String? loadError;
  final String? permissionError;
  final String? saveError;
  final String? applyError;
  final void Function(NotificationPrefs Function(NotificationPrefs current))?
  onEdit;
  final Future<void> Function(NotificationPrefs next)? onChanged;
  final VoidCallback? onRequestPermission;
  final VoidCallback? onOpenRelay;
  final VoidCallback? onRetryLoad;
  final VoidCallback? onRetryPermission;
  final VoidCallback? onRetrySave;
  final VoidCallback? onRetryApply;

  const NotificationSettingsView({
    super.key,
    this.prefs = const NotificationPrefs(),
    this.loaded = true,
    this.granted = true,
    this.busy = false,
    this.relaySupported = false,
    this.synthetic = false,
    this.releaseReduced = false,
    this.loadError,
    this.permissionError,
    this.saveError,
    this.applyError,
    this.onEdit,
    this.onChanged,
    this.onRequestPermission,
    this.onOpenRelay,
    this.onRetryLoad,
    this.onRetryPermission,
    this.onRetrySave,
    this.onRetryApply,
  });

  static const waterEvery = [
    (30, '30m'),
    (60, '1h'),
    (90, '90m'),
    (120, '2h'),
    (180, '3h'),
    (240, '4h'),
  ];

  static const batteryChoices = [10, 15, 20, 25, 30, 40];

  static String _everyLabel(int min) => waterEvery
      .firstWhere((e) => e.$1 == min, orElse: () => (min, '${min}m'))
      .$2;

  static String hhmm(int minuteOfDay) {
    final m = minuteOfDay % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  void _set(NotificationPrefs Function(NotificationPrefs current) update) {
    if (busy) return;
    final edit = onEdit;
    if (edit != null) {
      edit(update);
      return;
    }
    final changed = onChanged;
    if (changed == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await changed(update(prefs));
        } catch (_) {}
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final interactive =
        loaded && !busy && (onEdit != null || onChanged != null);
    bool parked(String route) =>
        openBandReleaseParksRoute(route, reduced: releaseReduced);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title: _s(
                  context,
                  'Mitteilungen',
                  'Notifications',
                  l10n: (l) =>
                      Localizations.localeOf(context).languageCode == 'de'
                      ? null
                      : l.settingsNotificationsNavTitle,
                ),
                subtitle: '',
                onInfo: () => _info(context),
              ),
            ),
            Expanded(
              child: ListView(
                cacheExtent: 2500,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (loadError != null) ...[
                    OBSettingsErrorCard(
                      message: _s(
                        context,
                        'Laden fehlgeschlagen',
                        'Could not load',
                      ),
                      retryLabel: _retryLabel(context),
                      onRetry: onRetryLoad,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!loaded && loadError == null)
                    const _LoadingCard()
                  else if (loaded) ...[
                    if (permissionError != null) ...[
                      OBSettingsErrorCard(
                        key: const ValueKey('notification-permission-error'),
                        message: _s(
                          context,
                          'Mitteilungen-Status unbekannt',
                          'Notification status unknown',
                        ),
                        retryLabel: _retryLabel(context),
                        onRetry: onRetryPermission,
                      ),
                      const SizedBox(height: 12),
                    ] else if (granted == false) ...[
                      _DeniedCard(
                        label: _s(
                          context,
                          'Mitteilungen nicht erlaubt',
                          'Notifications are not allowed',
                        ),
                        action: _s(context, 'Erlauben', 'Allow'),
                        onAllow: busy ? null : onRequestPermission,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (saveError != null) ...[
                      OBSettingsErrorCard(
                        key: const ValueKey('notification-error'),
                        message: _s(
                          context,
                          'Speichern fehlgeschlagen',
                          'Could not save',
                        ),
                        retryLabel: _retryLabel(context),
                        onRetry: onRetrySave,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (applyError != null) ...[
                      OBSettingsErrorCard(
                        key: const ValueKey('notification-apply-error'),
                        message: _s(
                          context,
                          'Gespeichert. Anwenden fehlgeschlagen',
                          'Saved. Could not apply',
                        ),
                        retryLabel: _retryLabel(context),
                        onRetry: onRetryApply,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _Group(
                      children: [
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-health'),
                          label: _s(
                            context,
                            'Auffällige Werte',
                            'Unusual readings',
                            l10n: (l) =>
                                Localizations.localeOf(context).languageCode ==
                                    'de'
                                ? null
                                : l.settingsHealthExceptionsRowTitle,
                          ),
                          value: prefs.healthEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) => p.copyWith(healthEnabled: !p.healthEnabled),
                          ),
                        ),
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-device'),
                          label: _s(
                            context,
                            'Bandstatus',
                            'Band status',
                            l10n: (l) =>
                                Localizations.localeOf(context).languageCode ==
                                    'de'
                                ? null
                                : l.settingsBandAlertsRowTitle,
                          ),
                          value: prefs.deviceEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) => p.copyWith(deviceEnabled: !p.deviceEnabled),
                          ),
                        ),
                        if (prefs.deviceEnabled)
                          OBSettingsValueRow(
                            key: const ValueKey('notif-battery'),
                            label: _s(
                              context,
                              'Warnen unter',
                              'Alert me at',
                              l10n: (l) => l.settingsAlertMeAtRowTitle,
                            ),
                            value: '${prefs.batteryAlertPct} %',
                            chevron: true,
                            interactive: interactive,
                            onTap: () => unawaited(
                              _pickChoice(
                                context,
                                title: _s(
                                  context,
                                  'Warnen unter',
                                  'Alert me at',
                                  l10n: (l) => l.settingsAlertMeAtRowTitle,
                                ),
                                choices: [
                                  for (final pct in batteryChoices)
                                    (pct, '$pct %'),
                                ],
                                selected: prefs.batteryAlertPct,
                                apply: (p, pct) =>
                                    p.copyWith(batteryAlertPct: pct),
                              ),
                            ),
                          ),
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-alarm-latch'),
                          label: _s(context, 'Alarmfehler', 'Alarm error'),
                          value: prefs.alarmLatchFailedEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) => p.copyWith(
                              alarmLatchFailedEnabled:
                                  !p.alarmLatchFailedEnabled,
                            ),
                          ),
                        ),
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-alarm-night'),
                          label: _s(
                            context,
                            'Abends ohne Alarm',
                            'No alarm tonight',
                            l10n: (l) => l.settingsAlarmNightCheckRowTitle,
                          ),
                          value: prefs.alarmNightCheckEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) => p.copyWith(
                              alarmNightCheckEnabled: !p.alarmNightCheckEnabled,
                            ),
                          ),
                        ),
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-recovery'),
                          label: _s(
                            context,
                            'Erholung bereit',
                            'Recovery ready',
                            l10n: (l) => l.settingsRecoveryReadyRowTitle,
                          ),
                          value: prefs.recoveryEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) =>
                                p.copyWith(recoveryEnabled: !p.recoveryEnabled),
                          ),
                        ),
                        if (!parked(kRouteRecap))
                          OBSettingsToggleRow(
                            key: const ValueKey('notif-weekly'),
                            label: _s(
                              context,
                              'Wochenrückblick',
                              'Weekly lookback',
                              l10n: (l) => l.settingsWeeklyLookbackRowTitle,
                            ),
                            value: prefs.remindersEnabled,
                            interactive: interactive,
                            onToggle: () => _set(
                              (p) => p.copyWith(
                                remindersEnabled: !p.remindersEnabled,
                              ),
                            ),
                          ),
                        if (!parked(kRouteWorkoutSuggestion))
                          OBSettingsToggleRow(
                            key: const ValueKey('notif-autodetect'),
                            label: _s(
                              context,
                              'Erkannte Aktivitäten',
                              'Detected activities',
                              l10n: (l) => l.settingsDetectedWorkoutsRowTitle,
                            ),
                            value: prefs.autoDetectEnabled,
                            interactive: interactive,
                            onToggle: () => _set(
                              (p) => p.copyWith(
                                autoDetectEnabled: !p.autoDetectEnabled,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Group(
                      children: [
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-movement'),
                          label: _s(
                            context,
                            'Bewegung',
                            'Movement',
                            l10n: (l) => l.settingsMovementNudgeRowTitle,
                          ),
                          value: prefs.movementEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) =>
                                p.copyWith(movementEnabled: !p.movementEnabled),
                          ),
                        ),
                        if (!parked(kRouteBreathing))
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-winddown'),
                          label: _s(
                            context,
                            'Schlafenszeit',
                            'Bedtime',
                            l10n: (l) => l.settingsWindDownRowTitle,
                          ),
                          value: prefs.windDownEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) =>
                                p.copyWith(windDownEnabled: !p.windDownEnabled),
                          ),
                        ),
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-steps'),
                          label: _s(
                            context,
                            'Schrittziel',
                            'Step goal',
                            l10n: (l) => l.settingsStepGoalAlertsRowTitle,
                          ),
                          value: prefs.stepGoalEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) =>
                                p.copyWith(stepGoalEnabled: !p.stepGoalEnabled),
                          ),
                        ),
                        if (!parked(kRouteMeds))
                          OBSettingsToggleRow(
                            key: const ValueKey('notif-meds'),
                            label: _s(
                              context,
                              'Medikamente',
                              'Medication',
                              l10n: (l) =>
                                  l.settingsMedicationRemindersRowTitle,
                            ),
                            value: prefs.medsEnabled,
                            interactive: interactive,
                            onToggle: () => _set(
                              (p) => p.copyWith(medsEnabled: !p.medsEnabled),
                            ),
                          ),
                        if (!parked(kRouteJournalCompose))
                          OBSettingsToggleRow(
                            key: const ValueKey('notif-checkin'),
                            label: _s(
                              context,
                              'Tages-Check-in',
                              'Daily check-in',
                              l10n: (l) => l.settingsDailyCheckInRowTitle,
                            ),
                            value: prefs.checkInEnabled,
                            interactive: interactive,
                            onToggle: () => _set(
                              (p) =>
                                  p.copyWith(checkInEnabled: !p.checkInEnabled),
                            ),
                          ),
                        if (!parked(kRouteWater))
                          OBSettingsToggleRow(
                            key: const ValueKey('notif-water'),
                            label: _s(
                              context,
                              'Wasser',
                              'Water',
                              l10n: (l) => l.settingsWaterReminderRowTitle,
                            ),
                            value: prefs.waterEnabled,
                            interactive: interactive,
                            onToggle: () => _set(
                              (p) => p.copyWith(waterEnabled: !p.waterEnabled),
                            ),
                          ),
                        if (!parked(kRouteWater) && prefs.waterEnabled)
                          OBSettingsValueRow(
                            key: const ValueKey('notif-water-interval'),
                            label: _s(
                              context,
                              'Abstand',
                              'Remind me every',
                              l10n: (l) => l.settingsRemindMeEveryRowTitle,
                            ),
                            value: _everyLabel(prefs.waterIntervalMin),
                            chevron: true,
                            interactive: interactive,
                            onTap: () => unawaited(
                              _pickChoice(
                                context,
                                title: _s(
                                  context,
                                  'Abstand',
                                  'Remind me every',
                                  l10n: (l) => l.settingsRemindMeEveryRowTitle,
                                ),
                                choices: waterEvery,
                                selected: prefs.waterIntervalMin,
                                apply: (p, min) =>
                                    p.copyWith(waterIntervalMin: min),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (relaySupported) ...[
                      const SizedBox(height: 12),
                      _Group(
                        children: [
                          OBSettingsValueRow(
                            key: const ValueKey('notification-relay'),
                            label: _s(
                              context,
                              'Bei App-Mitteilungen vibrieren',
                              'Buzz on app notifications',
                              l10n: (l) =>
                                  l.settingsBuzzOnAppNotificationsRowTitle,
                            ),
                            value: '',
                            chevron: true,
                            interactive: !busy,
                            onTap: () {
                              if (onOpenRelay != null) {
                                onOpenRelay!();
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const BandNotifications(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    _Group(
                      children: [
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-quiet'),
                          label: _s(
                            context,
                            'Ruhezeiten',
                            'Quiet hours',
                            l10n: (l) => l.settingsQuietHoursRowTitle,
                          ),
                          value: prefs.quietEnabled,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) => p.copyWith(quietEnabled: !p.quietEnabled),
                          ),
                        ),
                        _QuietRangeRow(
                          startLabel: hhmm(prefs.quietStartMin),
                          endLabel: hhmm(prefs.quietEndMin),
                          interactive: interactive,
                          onPickStart: () =>
                              unawaited(_pickQuiet(context, start: true)),
                          onPickEnd: () =>
                              unawaited(_pickQuiet(context, start: false)),
                        ),
                        OBSettingsToggleRow(
                          key: const ValueKey('notif-critical'),
                          label: _s(
                            context,
                            'Wichtige Hinweise zulassen',
                            'Allow important alerts',
                            l10n: (l) =>
                                l.settingsHealthExceptionsBreakThroughRowTitle,
                          ),
                          value: prefs.criticalOverridesQuiet,
                          interactive: interactive,
                          onToggle: () => _set(
                            (p) => p.copyWith(
                              criticalOverridesQuiet: !p.criticalOverridesQuiet,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (synthetic) ...[
                      const SizedBox(height: 12),
                      Text(
                        key: const ValueKey('notification-synthetic'),
                        'Synthetische Daten',
                        textAlign: TextAlign.center,
                        style: p.text(12, color: p.muted),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickChoice(
    BuildContext context, {
    required String title,
    required List<(int value, String label)> choices,
    required int selected,
    required NotificationPrefs Function(NotificationPrefs current, int value)
    apply,
  }) async {
    if (busy) return;
    final picked = await showOpenBandSettingsChoiceSheet<int>(
      context: context,
      title: title,
      choices: choices,
      selected: selected,
      sheetKey: const ValueKey('notification-choice'),
      choiceKey: (value) => ValueKey('notification-choice-$value'),
    );
    if (!context.mounted || picked == null) return;
    _set((current) => apply(current, picked));
  }

  Future<void> _pickQuiet(BuildContext context, {required bool start}) async {
    if (busy) return;
    final current = start ? prefs.quietStartMin : prefs.quietEndMin;
    final picked = await showOpenBandTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    _set(
      (p) => start
          ? p.copyWith(quietStartMin: minutes)
          : p.copyWith(quietEndMin: minutes),
    );
  }

  void _info(BuildContext context) {
    final p = OB.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      builder: (sheet) {
        final sp = OB.of(sheet);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s(sheet, 'Mitteilungen', 'Notifications'),
                  style: sp.text(18, weight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  _s(
                    sheet,
                    releaseReduced
                        ? 'Hinweise: auffällige Werte, Bandstatus, unbestätigter Alarm, fehlender Abend-Alarm, fertige Erholung — nur mit eingeschaltetem Schalter.'
                        : 'Hinweise: auffällige Werte, Bandstatus, unbestätigter Alarm, fehlender Abend-Alarm, fertige Erholung, Wochenrückblick, erkannte Aktivitäten — nur mit eingeschaltetem Schalter.',
                    releaseReduced
                        ? 'Alerts: unusual readings, band status, unconfirmed alarm, missing evening alarm, recovery ready — only when that switch is on.'
                        : 'Alerts: unusual readings, band status, unconfirmed alarm, missing evening alarm, recovery ready, weekly lookback, detected activities — only when that switch is on.',
                  ),
                  style: sp.text(14),
                ),
                const SizedBox(height: 8),
                Text(
                  _s(
                    sheet,
                    releaseReduced
                        ? 'Erinnerungen: Bewegung, Schrittziel.'
                        : 'Erinnerungen: Bewegung, Schlafenszeit, Schrittziel, Medikamente, Check-in, Wasser.',
                    releaseReduced
                        ? 'Reminders: movement, step goal.'
                        : 'Reminders: movement, bedtime, step goal, medication, check-in, water.',
                  ),
                  style: sp.text(14),
                ),
                const SizedBox(height: 8),
                Text(
                  _s(
                    sheet,
                    'Ruhezeiten halten Hinweise und Erinnerungen in diesem Zeitraum zurück. Der Wecker auf dem Band bleibt. Wichtige Hinweise sind auffällige Werte mit hoher Priorität; sie kommen in der Ruhezeit nur, wenn „Wichtige Hinweise zulassen“ an ist. Nicht jede Mitteilung wird stummgeschaltet.',
                    'Quiet hours hold alerts and reminders in that window. The band alarm still fires. Important alerts are high-priority unusual readings; they break through only when “Allow important alerts” is on. Not every notification is silenced.',
                  ),
                  style: sp.text(14),
                ),
                const SizedBox(height: 16),
                OBAction(
                  _s(sheet, 'Schließen', 'Close'),
                  onPressed: () => Navigator.pop(sheet),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return OBCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: children),
      ),
    );
  }
}

class _QuietRangeRow extends StatelessWidget {
  final String startLabel;
  final String endLabel;
  final bool interactive;
  final VoidCallback? onPickStart;
  final VoidCallback? onPickEnd;

  const _QuietRangeRow({
    required this.startLabel,
    required this.endLabel,
    required this.interactive,
    this.onPickStart,
    this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _stackControls(context);
    final label = Text(
      _s(context, 'Zeitraum', 'Time range'),
      style: p.text(15),
    );
    final wells = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _TimeWell(
          key: const ValueKey('quiet-start'),
          label: startLabel,
          semanticLabel: '${_s(context, 'Beginn', 'Starts')} $startLabel',
          onTap: interactive ? onPickStart : null,
        ),
        Text('–', style: p.text(13, color: p.muted)),
        _TimeWell(
          key: const ValueKey('quiet-end'),
          label: endLabel,
          semanticLabel: '${_s(context, 'Ende', 'Ends')} $endLabel',
          onTap: interactive ? onPickEnd : null,
        ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 8), wells],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  wells,
                ],
              ),
      ),
    );
  }
}

class _TimeWell extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;

  const _TimeWell({
    super.key,
    required this.label,
    required this.semanticLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final child = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 68, minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.well,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Center(
            child: Text(label, style: p.text(17, weight: FontWeight.w600)),
          ),
        ),
      ),
    );
    if (onTap == null) return ExcludeSemantics(child: child);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: child,
        ),
      ),
    );
  }
}

class _DeniedCard extends StatelessWidget {
  final String label;
  final String action;
  final VoidCallback? onAllow;
  const _DeniedCard({required this.label, required this.action, this.onAllow});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _stackControls(context);
    final title = Text(label, style: p.text(15, weight: FontWeight.w500));
    final allow = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: TextButton(
        onPressed: onAllow,
        style: TextButton.styleFrom(
          foregroundColor: p.action,
          textStyle: p.text(14, weight: FontWeight.w600, color: p.action),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(action),
      ),
    );
    return OBCard(
      key: const ValueKey('notification-denied'),
      padding: const EdgeInsets.all(14),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, allow],
            )
          : Row(
              children: [
                Expanded(child: title),
                allow,
              ],
            ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      key: const ValueKey('notification-loading'),
      child: SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.muted),
          ),
        ),
      ),
    );
  }
}

bool _stackControls(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20 ||
    MediaQuery.sizeOf(context).width < 360;

String _retryLabel(BuildContext context) => _s(context, 'Erneut', 'Retry');

String _s(
  BuildContext context,
  String de,
  String en, {
  String? Function(AppLocalizations)? l10n,
}) {
  final loc = AppLocalizations.of(context);
  final code = Localizations.localeOf(context).languageCode;
  if (l10n != null && loc != null && code != 'de') {
    return l10n(loc) ?? en;
  }
  return code == 'de' ? de : en;
}

String _shortError(Object error) {
  final text = '$error'.replaceFirst(RegExp(r'^Exception: '), '').trim();
  if (text.isEmpty) return 'Fehler';
  return text.length > 80 ? '${text.substring(0, 77)}…' : text;
}

bool _samePrefs(NotificationPrefs a, NotificationPrefs b) =>
    a.healthEnabled == b.healthEnabled &&
    a.recoveryEnabled == b.recoveryEnabled &&
    a.remindersEnabled == b.remindersEnabled &&
    a.deviceEnabled == b.deviceEnabled &&
    a.quietEnabled == b.quietEnabled &&
    a.quietStartMin == b.quietStartMin &&
    a.quietEndMin == b.quietEndMin &&
    a.criticalOverridesQuiet == b.criticalOverridesQuiet &&
    a.waterEnabled == b.waterEnabled &&
    a.waterIntervalMin == b.waterIntervalMin &&
    a.autoDetectEnabled == b.autoDetectEnabled &&
    a.movementEnabled == b.movementEnabled &&
    a.medsEnabled == b.medsEnabled &&
    a.checkInEnabled == b.checkInEnabled &&
    a.batteryAlertPct == b.batteryAlertPct &&
    a.stepGoalEnabled == b.stepGoalEnabled &&
    a.windDownEnabled == b.windDownEnabled &&
    a.alarmLatchFailedEnabled == b.alarmLatchFailedEnabled &&
    a.alarmNightCheckEnabled == b.alarmNightCheckEnabled;
