// G3 · Tagesblatt palette and type on top of the G2 `OB` palette.
//
// Paper `Bausteine · G3` (p-16-0) is canonical. Existing roles come from
// `OB` (tokens.json values); G3-only roles from the generated AlpColor
// tokens. Dark uses the dark twins, never an inversion.
import 'package:flutter/material.dart';

import '../alp_tokens.dart';
import '../theme.dart' show OB, OBBezel;

/// Shared card interior. Hero cards change radius, not text alignment.
const kG3CardPadding = EdgeInsets.all(18);

/// Colour marks only a value outside the caller's personal normal range.
/// The widgets never decide this; the caller passes it.
enum G3Deviation { none, better, worse }

/// Identity belongs to a metric, not the tab that shows it. Omit [domain] in
/// shared components to retain the neutral G3 appearance.
enum G3Domain { recovery, sleep, load, neutral }

class G3 {
  final bool dark;
  final OB ob;
  G3(this.dark) : ob = OB(dark);
  factory G3.of(BuildContext context) =>
      G3(Theme.of(context).brightness == Brightness.dark);

  Color _p(Color light, Color darkColor) => dark ? darkColor : light;

  // Existing roles (tokens.json via OB).
  Color get page => ob.canvas;
  Color get canvas => ob.card;
  Color get inset => ob.inset;
  Color get line => ob.line;
  Color get ink => ob.ink;
  Color get muted => ob.muted;
  Color get gap => ob.gap;
  Color get led => ob.led;
  // The original greys remain the neutral default after the named stage
  // tokens become the G3.1 Schlaf ramp.
  Color get stageDeep => ob.stageDeep;
  Color get stageLight => ob.stageLight;
  Color get stageRem => ob.stageRem;
  Color get wake => ob.wake;

  /// Text and icons on an ink-filled key.
  Color get onInk => dark ? AlpColor.ink : AlpColor.canvas;

  // G3 roles.
  Color get ink2 => _p(AlpColor.ink2, AlpColor.darkInk2);
  Color get band => _p(AlpColor.band, AlpColor.darkBand);
  Color get track => _p(AlpColor.track, AlpColor.darkTrack);
  Color get chip => _p(AlpColor.chip, AlpColor.darkChip);
  Color get hairline => _p(AlpColor.hairline, AlpColor.darkHairline);
  Color get bar => _p(AlpColor.bar, AlpColor.darkBar);
  Color get betterMark => _p(AlpColor.betterMark, AlpColor.darkBetterMark);
  Color get betterText => _p(AlpColor.better, AlpColor.darkBetterText);
  Color get betterTint => _p(AlpColor.betterTint, AlpColor.darkBetterTint);
  Color get worseMark => _p(AlpColor.worseMark, AlpColor.darkWorseMark);
  Color get worseText => _p(AlpColor.worse, AlpColor.darkWorseText);
  Color get worseTint => _p(AlpColor.worseTint, AlpColor.darkWorseTint);
  Color get note => _p(AlpColor.note, AlpColor.darkNote);
  Color get noteInset => _p(AlpColor.noteInset, AlpColor.darkNoteInset);
  Color get noteInk => _p(AlpColor.noteInk, AlpColor.darkNoteInk);
  Color get noteInk2 => _p(AlpColor.noteInk2, AlpColor.darkNoteInk2);
  Color get noteMuted => _p(AlpColor.noteMuted, AlpColor.darkNoteMuted);
  Color get noteAction => _p(AlpColor.noteAction, AlpColor.darkNoteAction);
  Color get hypnoLane =>
      dark ? const Color(0xFF262624) : const Color(0xFFEDEDE9);

  Color domainHue(G3Domain domain) => switch (domain) {
    G3Domain.recovery => _p(
      AlpColor.domainRecovery,
      AlpColor.darkDomainRecovery,
    ),
    G3Domain.sleep => _p(AlpColor.domainSleep, AlpColor.darkDomainSleep),
    G3Domain.load => _p(AlpColor.domainLoad, AlpColor.darkDomainLoad),
    G3Domain.neutral => ink,
  };

  Color domainBar(G3Domain domain) => switch (domain) {
    G3Domain.recovery => _p(
      AlpColor.domainRecoveryBar,
      AlpColor.darkDomainRecoveryBar,
    ),
    G3Domain.sleep => _p(AlpColor.domainSleepBar, AlpColor.darkDomainSleepBar),
    G3Domain.load => _p(AlpColor.domainLoadBar, AlpColor.darkDomainLoadBar),
    G3Domain.neutral => bar,
  };

  Color domainTint(G3Domain domain) => switch (domain) {
    G3Domain.recovery => _p(
      AlpColor.domainRecoveryTint,
      AlpColor.darkDomainRecoveryTint,
    ),
    G3Domain.sleep => _p(
      AlpColor.domainSleepTint,
      AlpColor.darkDomainSleepTint,
    ),
    G3Domain.load => _p(AlpColor.domainLoadTint, AlpColor.darkDomainLoadTint),
    G3Domain.neutral => band,
  };

  Color normalBand(G3Domain domain) =>
      domain == G3Domain.neutral ? band : domainBar(domain);

  Color hypnoLaneFor(G3Domain domain) => domain == G3Domain.sleep
      ? _p(AlpColor.hypnoLane, AlpColor.darkHypnoLane)
      : hypnoLane;

  Color stageFor(G3Domain domain, int lane) {
    if (domain != G3Domain.sleep) {
      return [wake, stageRem, stageLight, stageDeep][lane];
    }
    return dark
        ? [
            AlpColor.darkWake,
            AlpColor.darkStageRem,
            AlpColor.darkStageLight,
            AlpColor.darkStageDeep,
          ][lane]
        : [
            AlpColor.wake,
            AlpColor.stageRem,
            AlpColor.stageLight,
            AlpColor.stageDeep,
          ][lane];
  }

  List<Color> zonesFor(G3Domain domain) => domain == G3Domain.load
      ? loadZones
      : dark
      ? const [
          Color(0xFF3A3A36),
          Color(0xFF55554F),
          Color(0xFF7C7C76),
          Color(0xFFAEAEA9),
          Color(0xFFEDEDE9),
        ]
      : const [
          Color(0xFFD2D2CC),
          Color(0xFFB4B4AE),
          Color(0xFF8A8A84),
          Color(0xFF55554F),
          Color(0xFF1B1B1A),
        ];

  List<Color> get zones => zonesFor(G3Domain.neutral);
  List<Color> get loadZones => dark
      ? const [
          AlpColor.darkZone1,
          AlpColor.darkZone2,
          AlpColor.darkZone3,
          AlpColor.darkZone4,
          AlpColor.darkZone5,
        ]
      : const [
          AlpColor.zone1,
          AlpColor.zone2,
          AlpColor.zone3,
          AlpColor.zone4,
          AlpColor.zone5,
        ];

  /// Mark (pointer, bar, dot) for a deviation; null keeps it neutral.
  Color? mark(G3Deviation d) => switch (d) {
    G3Deviation.none => null,
    G3Deviation.better => betterMark,
    G3Deviation.worse => worseMark,
  };

  /// Paper sets px line heights; `even` puts the extra leading on both sides
  /// like CSS so text sits where Paper draws it.
  TextStyle t(
    double size,
    double lineHeight, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double tracking = 0,
  }) => TextStyle(
    fontFamily: OB.family(weight: weight),
    fontFamilyFallback: const [AlpFont.sans],
    fontSize: size,
    height: lineHeight / size,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: weight,
    color: color ?? ink,
    letterSpacing: tracking * size,
  );

  /// 12 pt bold caps label with open tracking: "ERHOLUNG".
  TextStyle caps({Color? color, double size = 12}) =>
      t(size, 16, weight: FontWeight.w700, color: color ?? ink, tracking: .1);

  /// The lead number. Decimals step down to 72 pt so value, unit and chip fit.
  TextStyle lead({required bool decimal, Color? color}) => t(
    decimal ? 72 : AlpText.lead,
    decimal ? 76 : AlpLeading.lead,
    weight: FontWeight.w700,
    color: color ?? ink,
    tracking: AlpTracking.lead,
  );

  /// Figures (≥ 20 pt) grow with Dynamic Type only up to 130 %; labels and
  /// sentences scale fully and wrap.
  static TextScaler figures(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

  Decoration raised({double radius = AlpRadius.card}) =>
      OBBezel(color: canvas, radius: radius, inset: false, dark: dark);

  Decoration pressed({double radius = AlpRadius.card, Color? color}) =>
      OBBezel(color: color ?? inset, radius: radius, inset: true, dark: dark);

  /// The floating tab-bar / sheet shadow is the only other elevation.
  List<BoxShadow> get noteShadow => dark
      ? const [
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x24000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ];
}

/// German number: 7,5 · −31 · +0,4. Presentation only; never rounds a
/// missing value to zero — callers pass null and get "—".
String g3Number(double? v, {int digits = 0, bool signed = false}) {
  if (v == null || !v.isFinite) return '—';
  final s = v.abs().toStringAsFixed(digits).replaceAll('.', ',');
  if (v < 0 && s.replaceAll(RegExp('[0,]'), '').isNotEmpty) return '−$s';
  return signed && v > 0 ? '+$s' : s;
}

/// Thousands with a dot: 6.480.
String g3Count(int? v) {
  if (v == null) return '—';
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '−' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Hollow, dashed rounded rectangle: an honest empty slot ("keine Daten",
/// a night still missing from the baseline). Never filled.
class G3Dashed extends StatelessWidget {
  final double? width, height;
  final double radius;
  final Color? color;
  final Widget? child;
  const G3Dashed({
    super.key,
    this.width,
    this.height,
    this.radius = 4,
    this.color,
    this.child,
  });
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashPainter(color ?? G3.of(context).gap, radius),
    child: SizedBox(width: width, height: height, child: child),
  );
}

class _DashPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashPainter(this.color, this.radius);
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.75),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (double d = 0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color || old.radius != radius;
}
