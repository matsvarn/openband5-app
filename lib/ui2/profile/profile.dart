// Profile.
//
// Reached from the Home avatar, never a sixth tab — the shell has five
// destinations and the type system says so.
//
// The reference design had a Premium badge and a Following/Followers pair.
// Both are gone, and not for lack of screen space: there is no account and no
// social graph, so a follower count would have to be invented and a premium
// tier would have to be sold. What replaces them is what this app actually
// knows — how much it has measured, and from what.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../health/health_import_state.dart' show storeName;
import '../../l10n/app_localizations.dart';
import '../../openband/alp_tokens.dart';
import '../../openband/domain.dart';
import '../../openband/local_repository.dart';
import '../../openband/release_scope.dart';
import '../../openband/scale.dart';
import '../../openband/theme.dart';
import '../../compute/profile.dart' show PersonalProfile, ageOnDate;
import '../../state/app_state.dart';
import '../../state/locale_controller.dart';
import '../ui2.dart';
import '../screens/coach.dart' show CoachSetup, coachSubtitle;
import 'data.dart';
import 'devices.dart';
import 'settings.dart';

// ══════════════════ shared list furniture ══════════════════

/// One row in a settings list. Shared by all three profile screens.
class SetRow extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String title, sub, value;
  final bool danger, chevron;
  final double minHeight;
  final VoidCallback? onTap;

  /// A brand mark in place of [icon] — Lucide has no GitHub/Discord/Reddit
  /// logo, and a generic glyph standing in for one of those is worse than
  /// the extra param. Sized and tinted the same as the [Icon] it replaces.
  final Widget Function(Color tint)? glyph;

  const SetRow(
    IconData this.icon,
    this.color,
    this.title, {
    super.key,
    this.sub = '',
    this.value = '',
    this.danger = false,
    this.chevron = true,
    this.minHeight = 52,
    this.onTap,
  }) : glyph = null;

  const SetRow.brand(
    this.glyph,
    this.color,
    this.title, {
    super.key,
    this.sub = '',
    this.value = '',
    this.danger = false,
    this.chevron = true,
    this.minHeight = 52,
    this.onTap,
  }) : icon = null;

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final tint = danger ? p.danger : p.ink;
    return Pressable(
      onTap: onTap,
      semanticLabel: sub.isEmpty ? title : '$title. $sub',
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Row(
          children: [
            if (glyph != null)
              glyph!(tint)
            else
              Icon(icon, size: 20, color: tint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: p.text(
                      15,
                      weight: FontWeight.w500,
                      color: danger ? p.danger : p.ink,
                    ),
                  ),
                  if (value.isNotEmpty && bigText(c))
                    Text(
                      value,
                      style: p.text(
                        13,
                        weight: FontWeight.w600,
                        color: p.muted,
                      ),
                    ),
                  if (sub.isNotEmpty)
                    Text(sub, style: p.text(12, color: p.muted)),
                ],
              ),
            ),
            // THE ROW RULE (see MetricRow): the title is the only flexible part,
            // so every value in a settings list ends on one right edge. Two flex
            // children would split the width by ratio and break that column.
            // The value moves UNDER the title at accessibility sizes instead —
            // "2026-08-16 04:12" is arbitrary-length, and at 3.1× it pushed
            // itself and the chevron off the right of every settings screen.
            if (value.isNotEmpty && !bigText(c)) ...[
              const SizedBox(width: 12),
              Text(
                value,
                style: p.text(13, color: p.muted).copyWith(height: 16 / 13),
              ),
            ],
            // Paper G2: a light "›", not an icon.
            if (chevron && !danger) ...[
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Text(
                  '›',
                  style: p.text(16, color: p.gap).copyWith(height: 20 / 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A titled card of [SetRow]s, hairline-separated.
Widget settingsGroup(
  BuildContext c,
  String title,
  List<Widget> rows, {
  double top = 16,
}) {
  final p = OB.of(c);
  return Padding(
    padding: EdgeInsets.only(top: top),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title.toUpperCase(), style: p.label(size: 11)),
          ),
        OBCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Divider(color: p.line, height: 1, thickness: 1),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Push a screen, keeping the enclosing domain accent. Returns when it pops,
/// so a caller whose own numbers the pushed screen can change is able to
/// re-read them.
Future<void> goto(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

/// The one way into the profile stack. Home's avatar calls this — profile is
/// a pushed route, never a sixth tab.
void openProfile(BuildContext c) => goto(c, const ProfileHome());

/// Display name for a language code, sourced from a small hardcoded table.
/// Add a row here when a contributor's `app_<code>.arb` lands — nothing else
/// to touch; the picker below only ever offers what [AppLocalizations]
/// actually has translations for.
const Map<String, String> _kLanguageNames = {
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'zh': '中文',
  'hi': 'हिन्दी',
};

String _languageLabel(BuildContext c, String? code) => code == null
    ? (AppLocalizations.of(c)?.languageSystemDefault ?? 'System default')
    : (_kLanguageNames[code] ?? code);

Future<void> _pickLanguage(BuildContext c) async {
  final p = P.of(c);
  final ctrl = c.read<LocaleController>();
  final options = <String?>[
    null,
    ...AppLocalizations.supportedLocales.map((l) => l.languageCode),
  ];
  await showModalBottomSheet<void>(
    context: c,
    backgroundColor: p.card,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final code in options)
            ListTile(
              title: Text(
                _languageLabel(sheet, code),
                style: F.body.copyWith(color: p.ink),
              ),
              trailing: ctrl.code == code
                  ? Icon(LucideIcons.check, size: 18, color: p.on(C.blue))
                  : null,
              onTap: () async {
                await ctrl.setCode(code);
                if (sheet.mounted) Navigator.of(sheet).pop();
              },
            ),
        ],
      ),
    ),
  );
}

/// Human-readable byte size. No dependency for four lines of arithmetic.
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}

// ══════════════════ 1 · PROFILE HOME ══════════════════

/// What the profile screen still shows: who you are, how many sources are
/// live, and how much room the data takes.
///
/// The workouts / records / days / sessions counters are gone with the tile
/// that displayed them. They cost a `getRecords()` and a whole year-of-workouts
/// query on every open, so leaving the fields behind would have kept paying for
/// numbers nobody reads.
class ProfileStats {
  final String? name;
  final int sources;
  final int? storageBytes;
  final bool bandReadFailed;

  const ProfileStats({
    this.name,
    this.sources = 0,
    this.storageBytes,
    this.bandReadFailed = false,
  });
}

class ProfileHome extends StatefulWidget {
  const ProfileHome({super.key});

  @override
  State<ProfileHome> createState() => _ProfileHomeState();
}

class _ProfileHomeState extends State<ProfileHome> {
  /// Re-read after every screen this one pushes. It used to be a single
  /// `late final` Future, so pairing a band from My sources (which auto-pops
  /// straight back here) left the row reading "0 sources", and an import or a
  /// reset left Storage on the old size until the screen was left and
  /// re-entered.
  late Future<ProfileStats> _stats = _load();
  BandSnapshot? _band;

  Future<ProfileStats> _load() async {
    final app = context.read<AppState>();
    final repo = app.repo;
    final sources = liveSources(app).length;
    var bandReadFailed = false;
    try {
      _band = await LocalOpenBandRepository(app).readBand();
    } catch (_) {
      // A failed status read keeps the last real observation. If there has not
      // been one, the view says the status is unavailable rather than claiming
      // that no band is paired.
      bandReadFailed = true;
    }
    if (repo == null) {
      return ProfileStats(
        name: app.user?['name'] as String?,
        sources: sources,
        bandReadFailed: bandReadFailed,
      );
    }
    final bytes = await app.dataFileBytes();
    return ProfileStats(
      name: app.user?['name'] as String?,
      sources: sources,
      storageBytes: bytes,
      bandReadFailed: bandReadFailed,
    );
  }

  Future<void> _open(BuildContext c, Widget w) async {
    await goto(c, w);
    if (mounted) setState(() => _stats = _load());
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<ProfileStats>(
    future: _stats,
    builder: (c, snap) => ProfileHomeView(
      stats: snap.data,
      user: c.read<AppState>().user,
      band: _band,
      bandName: c.read<AppState>().strapName,
      releaseReduced: kOpenBandReleaseReduced,
      onDevices: () => _open(c, const MyDevices()),
      onData: () => _open(c, const DataScreen()),
      onSettings: () => _open(c, const MoreSettings()),
      onEdit: () => _open(c, const EditProfile()),
      onLanguage: () => _pickLanguage(c),
      showCoach: !kOpenBandReleaseReduced,
      onCoach: kOpenBandReleaseReduced
          ? null
          : () => _open(c, const CoachSetup()),
    ),
  );
}

class ProfileHomeView extends StatelessWidget {
  /// Null while the counts are still being read — the numbers are absent, not
  /// zero, and a zero rendered during a load is a wrong number on screen.
  final ProfileStats? stats;
  final Map<String, dynamic>? user;
  final BandSnapshot? band;
  final String? bandName;
  final VoidCallback? onDevices,
      onData,
      onSettings,
      onEdit,
      onCoach,
      onLanguage;
  final String? languageLabel;
  final bool showCoach;

  /// Explicit so archive/gallery fixtures retain the full-product surface.
  final bool releaseReduced;

  const ProfileHomeView({
    super.key,
    this.stats,
    this.user,
    this.band,
    this.bandName,
    this.onDevices,
    this.onData,
    this.onCoach,
    this.onSettings,
    this.onEdit,
    this.onLanguage,
    this.languageLabel,
    this.showCoach = true,
    this.releaseReduced = false,
  });

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final l = AppLocalizations.of(c);
    final s = stats;
    return Scaffold(
      key: const ValueKey('profile-screen'),
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OBPageHeader(
                title:
                    releaseReduced &&
                        Localizations.localeOf(c).languageCode == 'de'
                    ? 'Profil'
                    : (l?.profileTitle ?? 'Profile'),
                subtitle: '',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                children: [
                  _identityCard(c, p, s),
                  if (s != null) _bandCard(c, p, s),
                  if (releaseReduced)
                    _reducedRoutes(c)
                  else ...[
                    settingsGroup(c, l?.profileQuickAccessGroup ?? 'Quick access', [
                      SetRow(
                        LucideIcons.watch,
                        C.blue,
                        l?.profileMyDevices ?? 'My devices',
                        sub: s == null
                            ? ''
                            : (l?.profileSourcesCount(s.sources) ??
                                  '${s.sources} source${s.sources == 1 ? '' : 's'}'),
                        onTap: onDevices,
                      ),
                      SetRow(
                        LucideIcons.userPen,
                        C.purple,
                        l?.profileEditProfile ?? 'Edit profile',
                        sub:
                            l?.profileEditProfileSub ??
                            'Sex, birth date, height, weight',
                        onTap: onEdit,
                      ),
                      // THE ONLY DOOR TO THE COACH'S SETUP, and it has to be —
                      // Home's sparkles button is now gated on `coachReady`, so on
                      // a fresh install there is no icon to find it behind. It
                      // belongs here anyway: a model, a base URL and a key are
                      // settings, and the coach's own overflow menu offering the
                      // same form was two doors onto one state.
                      //
                      // `watch` rather than `read` so the sub-line stops saying
                      // "Not set up" the moment it is.
                      if (showCoach)
                        Builder(
                          builder: (c) => SetRow(
                            LucideIcons.sparkles,
                            C.purple,
                            AppLocalizations.of(c)?.profileAiCoach ??
                                'AI coach',
                            sub:
                                coachSubtitle(c) ??
                                (AppLocalizations.of(c)?.profileNotSetUp ??
                                    'Not set up'),
                            onTap: onCoach,
                          ),
                        ),
                      Builder(
                        builder: (c) => SetRow(
                          LucideIcons.languages,
                          C.blue,
                          AppLocalizations.of(c)?.profileLanguage ?? 'Language',
                          sub: _languageLabel(
                            c,
                            c.watch<LocaleController>().code,
                          ),
                          onTap: () => _pickLanguage(c),
                        ),
                      ),
                    ]),
                    settingsGroup(c, l?.profileYourDataGroup ?? 'Your data', [
                      // When the band card renders, its Archiv column already
                      // carries this number — showing it twice is how two figures
                      // drift apart.
                      if (band == null)
                        SetRow(
                          LucideIcons.database,
                          C.green,
                          l?.profileStorage ?? 'Storage',
                          value: s?.storageBytes == null
                              ? ''
                              : formatBytes(s!.storageBytes!),
                          chevron: false,
                        ),
                      SetRow(
                        LucideIcons.settings,
                        C.n500,
                        l?.profileMoreSettings ?? 'More settings',
                        // `From $storeName` used to sit on Quick access too. It
                        // came off: height, weight and workouts already moved to
                        // the screens they fill, and what is left — a resting
                        // heart rate the app does not use yet, plus readings from
                        // instruments this band does not have — is not quick and
                        // is not accessed often. It keeps its one door here, and
                        // this line names it so the door is findable.
                        sub:
                            l?.profileMoreSettingsSub(storeName) ??
                            'Import from $storeName, export, backup, units, '
                                'privacy, reset',
                        onTap: onSettings,
                      ),
                    ]),
                    settingsGroup(c, l?.profileCommunityGroup ?? 'Community', [
                      SetRow.brand(
                        brandGlyph('assets/icons/github.svg'),
                        C.n500,
                        l?.profileGithubTitle ?? 'GitHub',
                        sub:
                            l?.profileGithubSub ??
                            'Please star and show your support — it helps '
                                'the project grow',
                        onTap: () => open3rdPartyLink(kGithubUrl),
                      ),
                      SetRow.brand(
                        brandGlyph('assets/icons/reddit.svg'),
                        C.orange,
                        l?.profileRedditTitle ?? 'Reddit',
                        sub:
                            l?.profileRedditSub ??
                            'Join r/OpenStrap — post your achievements, '
                                'questions, anything',
                        onTap: () => open3rdPartyLink(kRedditUrl),
                      ),
                      SetRow.brand(
                        brandGlyph('assets/icons/discord.svg'),
                        C.indigo,
                        l?.profileDiscordTitle ?? 'Discord',
                        sub:
                            l?.profileDiscordSub ??
                            'Hang out with other users and the people '
                                'building this',
                        onTap: () => open3rdPartyLink(kDiscordUrl),
                      ),
                      SetRow(
                        LucideIcons.heartHandshake,
                        C.pink,
                        l?.profileSponsorTitle ?? 'Sponsor',
                        sub:
                            l?.profileSponsorSub ??
                            'This is a free, open-source project — '
                                'sponsoring keeps it going',
                        onTap: () => open3rdPartyLink(kSponsorUrl),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reducedRoutes(BuildContext c) {
    final de = Localizations.localeOf(c).languageCode == 'de';
    final language =
        languageLabel ?? _languageLabel(c, c.watch<LocaleController>().code);
    final rows = <Widget>[
      SetRow(
        LucideIcons.download,
        C.green,
        de ? 'Daten & Sicherung' : 'Data & backup',
        key: const ValueKey('profile-data'),
        onTap: onData,
      ),
      SetRow(
        LucideIcons.slidersHorizontal,
        C.n500,
        de ? 'Einstellungen' : 'Settings',
        key: const ValueKey('profile-settings'),
        chevron: onSettings != null,
        onTap: onSettings,
      ),
      SetRow(
        LucideIcons.languages,
        C.blue,
        de ? 'Sprache' : 'Language',
        value: language,
        key: const ValueKey('profile-language'),
        chevron: onLanguage != null,
        onTap: onLanguage,
      ),
    ];
    return settingsGroup(c, '', rows, top: 0);
  }

  Widget _identityCard(BuildContext c, OB p, ProfileStats? s) {
    final de = Localizations.localeOf(c).languageCode == 'de';
    final name = (s?.name ?? '').trim();
    final profile = PersonalProfile.fromMap(user);
    final parts = <String>[
      if (ageOnDate(profile.birthDate, DateTime.now()) case final age?) '$age',
      if (profile.heightCm != null) '${profile.heightCm!.round()} cm',
      if (profile.weightKg != null)
        '${profile.weightKg!.toStringAsFixed(1).replaceAll('.', ',')} kg',
    ];
    final initials = name.isEmpty
        ? ''
        : name
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        key: const ValueKey('profile-identity'),
        onTap: onEdit,
        semanticLabel: name.isEmpty ? (de ? 'Profil' : 'Profile') : name,
        child: OBCard(
          child: Row(
            children: [
              Container(
                width: releaseReduced ? 48 : 44,
                height: releaseReduced ? 48 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.sleepTint,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials,
                  style: p.text(
                    releaseReduced ? 18 : 16,
                    weight: FontWeight.w700,
                    color: p.sleep,
                  ),
                ),
              ),
              SizedBox(width: releaseReduced ? 14 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? (de ? 'Profil' : 'Profile') : name,
                      style: p.text(
                        releaseReduced ? 16 : 17,
                        weight: FontWeight.w600,
                      ),
                    ),
                    if (parts.isNotEmpty)
                      Text(
                        parts.join(' · '),
                        style: p.text(13, color: p.muted),
                      ),
                  ],
                ),
              ),
              if (onEdit != null)
                Icon(LucideIcons.chevronRight, size: 17, color: p.gap),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bandCard(BuildContext c, OB p, ProfileStats s) {
    final de = Localizations.localeOf(c).languageCode == 'de';
    final b = band;
    if (b == null) {
      final unavailable = s.bandReadFailed;
      final label = unavailable
          ? (de
                ? 'Bandstatus nicht verfügbar · erneut versuchen'
                : 'Band status unavailable · try again')
          : (de ? 'Kein Band verbunden' : 'No band connected');
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Pressable(
          key: const ValueKey('profile-band'),
          onTap: onDevices,
          semanticLabel: label,
          child: OBCard(
            child: Row(
              children: [
                Icon(LucideIcons.bluetooth, size: 18, color: p.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: p.text(15, weight: FontWeight.w500),
                  ),
                ),
                if (onDevices != null)
                  Icon(LucideIcons.chevronRight, size: 17, color: p.gap),
              ],
            ),
          ),
        ),
      );
    }
    final connected = b.connection == BandConnection.connected;
    final statusUnavailable = s.bandReadFailed;
    var archive = s.storageBytes == null ? '—' : formatBytes(s.storageBytes!);
    if (releaseReduced && de) archive = archive.replaceFirst('.', ',');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        key: const ValueKey('profile-band'),
        onTap: onDevices,
        semanticLabel: statusUnavailable
            ? '${bandName ?? 'Band'}. ${de ? 'Status nicht verfügbar' : 'Status unavailable'}'
            : (bandName ?? 'Band'),
        child: OBCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: releaseReduced ? 40 : 36,
                    height: releaseReduced ? 40 : 36,
                    alignment: Alignment.center,
                    decoration: p.insetDecoration(radius: AlpRadius.card / 2),
                    child: Icon(
                      LucideIcons.bluetooth,
                      size: releaseReduced ? 20 : 18,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bandName ?? 'Band',
                          style: p.text(
                            releaseReduced ? 16 : 17,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OBLed(on: !statusUnavailable && connected, size: 7),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                statusUnavailable
                                    ? (de
                                          ? 'Bandstatus nicht verfügbar'
                                          : 'Band status unavailable')
                                    : connected
                                    ? (de ? 'Verbunden' : 'Connected')
                                    : (de ? 'Getrennt' : 'Disconnected'),
                                style: p.text(
                                  13,
                                  weight: FontWeight.w600,
                                  color: !statusUnavailable && connected
                                      ? p.ink
                                      : p.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (b.batteryPercent != null)
                    if (releaseReduced)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${b.batteryPercent}',
                            style: p.text(
                              22,
                              weight: FontWeight.w800,
                              display: true,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text('%', style: p.text(13, color: p.muted)),
                        ],
                      )
                    else
                      Text(
                        '${b.batteryPercent} %',
                        style: p.text(
                          24,
                          weight: FontWeight.w700,
                          display: true,
                        ),
                      ),
                ],
              ),
              if (b.batteryPercent != null) ...[
                const SizedBox(height: 8),
                OBScale(
                  min: 0,
                  max: 100,
                  value: b.batteryPercent!.toDouble(),
                  fill: p.ink,
                  labels: ('0 %', de ? 'Akku' : 'Battery', '100 %'),
                  semanticsLabel: de
                      ? 'Akku ${b.batteryPercent} Prozent'
                      : 'Battery ${b.batteryPercent} percent',
                ),
              ],
              SizedBox(height: releaseReduced ? 12 : 14),
              if (releaseReduced)
                Divider(color: p.line, height: 1, thickness: 1),
              if (releaseReduced) const SizedBox(height: 10),
              if (releaseReduced && bigText(c))
                LayoutBuilder(
                  builder: (context, _) {
                    final stackLabels =
                        MediaQuery.textScalerOf(context).scale(12) > 28;
                    return Column(
                      children: [
                        _bandFactLarge(
                          p,
                          de ? 'Datenstand' : 'Data as of',
                          obTime(b.latestStoredAt),
                          stackLabel: stackLabels,
                        ),
                        const SizedBox(height: 8),
                        _bandFactLarge(
                          p,
                          de ? 'Gespeichert' : 'Stored',
                          obTime(b.receivedAt),
                          stackLabel: stackLabels,
                        ),
                        const SizedBox(height: 8),
                        _bandFactLarge(
                          p,
                          de ? 'Archiv' : 'Archive',
                          archive,
                          stackLabel: stackLabels,
                        ),
                      ],
                    );
                  },
                )
              else
                Row(
                  children: [
                    _bandFact(
                      p,
                      de ? 'Datenstand' : 'Data as of',
                      obTime(b.latestStoredAt),
                    ),
                    _bandFact(
                      p,
                      de ? 'Gespeichert' : 'Stored',
                      obTime(b.receivedAt),
                    ),
                    _bandFact(p, de ? 'Archiv' : 'Archive', archive),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bandFactLarge(
    OB p,
    String label,
    String value, {
    required bool stackLabel,
  }) {
    final valueText = Text(
      value,
      style: p.text(17, weight: FontWeight.w700, display: true),
    );
    final labelText = Text(
      label,
      style: p.text(12, weight: FontWeight.w600, color: p.muted),
    );
    if (stackLabel) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [valueText, const SizedBox(height: 2), labelText],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          SizedBox(width: 140, child: valueText),
          const SizedBox(width: 12),
          Expanded(child: labelText),
        ],
      ),
    );
  }

  Widget _bandFact(OB p, String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: releaseReduced
          ? [
              Text(
                value,
                style: p.text(17, weight: FontWeight.w700, display: true),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: p.text(12, weight: FontWeight.w600, color: p.muted),
              ),
            ]
          : [
              Text(
                label,
                style: p.text(12, weight: FontWeight.w600, color: p.muted),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: p.text(15, weight: FontWeight.w700, display: true),
              ),
            ],
    ),
  );
}
