import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../domain.dart';
import '../theme.dart' show OBChevron, OBLed, obTime;
import 'chrome.dart' show OBActionPrimary, OBActionSecondary;
import 'g3_theme.dart';

class OBSetupHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback onInfo;
  final String backLabel;
  const OBSetupHeader({
    super.key,
    required this.title,
    this.onBack,
    required this.onInfo,
    this.backLabel = 'Zurück',
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final large = MediaQuery.textScalerOf(context).scale(15) > 20;
    final back = onBack == null
        ? const SizedBox.shrink()
        : Tooltip(
            message: backLabel,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                decoration: g.raised(radius: 20),
                padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OBChevron(
                      direction: AxisDirection.left,
                      size: 20,
                      color: g.ink,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        backLabel,
                        maxLines: 2,
                        style: g.t(15, 20, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
    final info = InkWell(
      onTap: onInfo,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: g.raised(radius: 20),
        child: Icon(LucideIcons.info, size: 18, color: g.ink),
      ),
    );
    final center = Column(
      children: [
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          style: g.t(13, 16, weight: FontWeight.w700, tracking: .1),
        ),
        Text('WHOOP 5.0', style: g.t(12, 15, color: g.muted)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: large
          ? Column(
              children: [
                Row(children: [back, const Spacer(), info]),
                const SizedBox(height: 8),
                center,
              ],
            )
          : Row(
              children: [
                SizedBox(width: 104, child: back),
                Expanded(child: center),
                SizedBox(
                  width: 104,
                  child: Align(alignment: Alignment.centerRight, child: info),
                ),
              ],
            ),
    );
  }
}

class OBSettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final bool inset;
  const OBSettingsGroup({
    super.key,
    required this.children,
    this.inset = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      decoration: inset ? g.pressed(radius: 16) : g.raised(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: g.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class OBSettingsRow extends StatelessWidget {
  final String label;
  final String? detail;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  const OBSettingsRow({
    super.key,
    required this.label,
    this.detail,
    this.value,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: g.t(15, 20, weight: FontWeight.w500)),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail!, style: g.t(12, 17, color: g.muted)),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.end,
                  style: g.t(
                    15,
                    20,
                    weight: onTap == null ? FontWeight.w700 : FontWeight.w400,
                    color: onTap == null ? g.ink : g.ink2,
                  ),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (onTap != null && trailing == null) ...[
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, size: 14, color: g.gap),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: [label, detail, value].whereType<String>().join(', '),
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class OBStepProgress extends StatelessWidget {
  final int step;
  const OBStepProgress({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('EINRICHTUNG', style: g.caps())),
            Text('Schritt $step von 3', style: g.t(12, 16, color: g.muted)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 1; i <= 3; i++) ...[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? g.ink : g.band,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class OBFrontierCard extends StatelessWidget {
  final DateTime? storedAt;
  final DateTime now;
  final String? caption;
  final String? rightLabel;
  const OBFrontierCard({
    super.key,
    required this.storedAt,
    required this.now,
    this.caption,
    this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final stored = storedAt;
    final sameDay =
        stored != null &&
        dayLabelOf(stored) == todayLabel(now) &&
        !stored.isAfter(now);
    final age = sameDay ? now.difference(stored).inMinutes : 0;
    final ageText = age >= 60
        ? '${age ~/ 60} h ${(age % 60).toString().padLeft(2, '0')}'
        : '$age Min.';
    final storedDay = stored == null
        ? ''
        : bandFrontierDayPrefix(
            stored,
            now,
            de: Localizations.localeOf(context).languageCode == 'de',
          );
    final marker = stored == null
        ? null
        : (1 -
                  now.difference(stored).inSeconds /
                      const Duration(days: 1).inSeconds)
              .clamp(0.0, 1.0);
    return Container(
      decoration: g.raised(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('AUF DEM IPHONE', style: g.caps())),
              if (rightLabel != null)
                Text(rightLabel!, style: g.t(13, 18, color: g.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stored == null ? '—' : 'bis $storedDay${obTime(stored)}',
            style: g.t(40, 44, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: stored == null
                ? 'Noch kein gespeicherter Bandwert'
                : 'Letzter gespeicherter Bandwert $storedDay${obTime(stored)}',
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: g.track,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  if (marker != null)
                    Positioned(
                      left: (constraints.maxWidth - 3) * marker,
                      child: Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          color: g.ink,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'letzter gespeicherter Wert',
                  style: g.t(11, 15, color: g.muted),
                ),
              ),
              Text(
                'jetzt ${obTime(now)}',
                style: g.t(11, 15, weight: FontWeight.w700, color: g.ink2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (caption != null || rightLabel == null)
            Text(
              caption ??
                  (stored == null
                      ? 'Noch keine bestätigten Banddaten gespeichert.'
                      : sameDay
                      ? 'letzter Wert vor $ageText'
                      : 'Zuletzt bestätigter Datenstand. Noch ausstehende Banddaten sind unbekannt.'),
              style: g.t(13, 19, color: g.muted),
            ),
        ],
      ),
    );
  }
}

String bandFrontierDayPrefix(DateTime stored, DateTime now, {bool de = true}) {
  if (dayLabelOf(stored) == todayLabel(now)) return '';
  if (dayLabelOf(stored) ==
      dayLabelOf(DateTime(now.year, now.month, now.day - 1))) {
    return de ? 'gestern · ' : 'yesterday · ';
  }
  return '${stored.day.toString().padLeft(2, '0')}.${stored.month.toString().padLeft(2, '0')}. · ';
}

enum OBBandIssue { bluetoothOff }

String bandConnectionLabel(BandConnection connection) => switch (connection) {
  BandConnection.connected => 'Verbunden',
  BandConnection.connecting => 'Verbindet …',
  BandConnection.disconnected => 'Nicht verbunden',
};

class OBToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  const OBToggle({
    super.key,
    required this.value,
    required this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      label: label,
      toggled: value,
      enabled: onChanged != null,
      button: true,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 48,
          height: 44,
          child: Center(
            child: Container(
              width: 46,
              height: 28,
              decoration: BoxDecoration(
                color: value ? g.ink : g.track,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: value ? g.onInk : g.canvas,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OBBandActionNotice extends StatelessWidget {
  final String title;
  final String body;
  final String action;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final VoidCallback? onHelp;
  final String helpLabel;
  const OBBandActionNotice({
    super.key,
    required this.title,
    required this.body,
    required this.action,
    this.actionIcon,
    this.onAction,
    this.onHelp,
    this.helpLabel = 'Hilfe',
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      decoration: g.pressed(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.triangleAlert, size: 18, color: g.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: g.t(16, 20, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: g.t(14, 19, color: g.ink2)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OBActionPrimary(
                action,
                icon: actionIcon,
                height: 40,
                onPressed: onAction,
              ),
              if (onHelp != null)
                OBActionSecondary(helpLabel, height: 40, onPressed: onHelp),
            ],
          ),
        ],
      ),
    );
  }
}

class OBBandHero extends StatelessWidget {
  final BandSnapshot band;
  final DateTime now;
  final VoidCallback? onStatus;
  final OBBandIssue? issue;
  const OBBandHero({
    super.key,
    required this.band,
    required this.now,
    this.onStatus,
    this.issue,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final stored = band.latestStoredAt;
    final connected = band.connection == BandConnection.connected;
    final sameDay = stored != null && dayLabelOf(stored) == todayLabel(now);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dayWord = stored == null
        ? '—'
        : sameDay
        ? 'heute'
        : dayLabelOf(stored) == dayLabelOf(yesterday)
        ? 'gestern'
        : '${stored.day.toString().padLeft(2, '0')}.${stored.month.toString().padLeft(2, '0')}.';
    final age = stored == null || stored.isAfter(now)
        ? null
        : now.difference(stored);
    final ageText = age == null
        ? 'Datenstand unbekannt'
        : age.inHours > 0
        ? 'vor ${age.inHours} h'
        : 'vor ${age.inMinutes} Min.';
    final status = switch (issue) {
      OBBandIssue.bluetoothOff => 'Bluetooth aus',
      null when connected && band.transfer == TransferState.receiving =>
        'Band wird gelesen',
      null => bandConnectionLabel(band.connection),
    };
    return Container(
      decoration: g.raised(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text('DATEN BIS', style: g.caps()),
                    if (onStatus != null) ...[
                      const SizedBox(width: 4),
                      Icon(LucideIcons.chevronRight, size: 12, color: g.muted),
                    ],
                  ],
                ),
              ),
              if (issue != null || !connected)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: g.muted, width: 1.5),
                  ),
                )
              else if (band.transfer == TransferState.receiving)
                Icon(LucideIcons.refreshCw, size: 15, color: g.ink)
              else
                OBLed(on: true, size: 8),
              const SizedBox(width: 7),
              Text(status, style: g.t(13, 18, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Semantics(
                  button: onStatus != null,
                  label: onStatus == null
                      ? 'Daten bis ${obTime(stored)}'
                      : 'Daten bis ${obTime(stored)}. Datenstand öffnen',
                  child: InkWell(
                    onTap: onStatus,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        obTime(stored),
                        style: g.t(
                          92,
                          84,
                          weight: FontWeight.w700,
                          tracking: -.045,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dayWord, style: g.t(14, 19, weight: FontWeight.w700)),
                    Text(ageText, style: g.t(13, 18, color: g.ink2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('LETZTE 24 STUNDEN', style: g.caps(color: g.muted)),
              ),
              Text('—', style: g.t(12, 17, color: g.ink2)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 14,
            child: CustomPaint(painter: _DashedTrack(g.gap)),
          ),
          const SizedBox(height: 6),
          Text(
            'Abdeckung noch nicht erfasst',
            style: g.t(12, 17, color: g.ink2),
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: g.hairline),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroFact(
                  'AKKU',
                  connected && band.batteryPercent != null
                      ? '${band.batteryPercent} %'
                      : '—',
                  detail: !connected && band.batteryPercent != null
                      ? 'zuletzt ${band.batteryPercent} %'
                      : null,
                  battery: connected ? band.batteryPercent : null,
                ),
              ),
              Expanded(
                child: _HeroFact('AUSSTEHEND', '—', detail: 'unbekannt'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  final String label, value;
  final String? detail;
  final int? battery;
  const _HeroFact(this.label, this.value, {this.detail, this.battery});
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: g.caps()),
        if (label == 'AKKU' && battery != null)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$battery',
                  style: g.t(36, 40, weight: FontWeight.w700, tracking: -.035),
                ),
                TextSpan(
                  text: ' %',
                  style: g.t(13, 18, weight: FontWeight.w500, color: g.muted),
                ),
              ],
            ),
          )
        else
          Text(
            value,
            style: g.t(
              36,
              40,
              weight: FontWeight.w700,
              color: value == '—' ? g.gap : g.ink,
            ),
          ),
        if (detail != null) Text(detail!, style: g.t(12, 17, color: g.muted)),
        if (label == 'AKKU') ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: battery == null ? 0 : battery!.clamp(0, 100) / 100,
              minHeight: 6,
              backgroundColor: g.track,
              valueColor: AlwaysStoppedAnimation(g.ink),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text('0', style: g.t(11, 15, color: g.muted)),
              const Spacer(),
              Text('100 %', style: g.t(11, 15, color: g.muted)),
            ],
          ),
        ],
      ],
    );
  }
}

class _DashedTrack extends CustomPainter {
  final Color color;
  const _DashedTrack(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(7),
    );
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      for (var x = 0.0; x < metric.length; x += 8) {
        canvas.drawPath(
          metric.extractPath(x, (x + 4).clamp(0, metric.length)),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedTrack old) => old.color != color;
}
