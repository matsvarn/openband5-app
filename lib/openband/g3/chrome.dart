// G3 chrome Bausteine: headers, band capsule, sync line, section and card
// headers, list rows, keys, segmented control, sheet, empty/error blocks,
// footer stamp, date strip, number field and panels.
//
// Visual keys follow Paper (40 pt); every tap target keeps 44 pt.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../alp_tokens.dart';
import '../theme.dart' show OBChevron, OBLed;
import 'g3_theme.dart';
import 'metrics.dart' show G3LabelRow;

/// A 44 pt hit area around a smaller visual key.
class _Hit extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final double? width;
  const _Hit({
    required this.label,
    required this.onTap,
    required this.child,
    this.width,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: onTap != null,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: 44,
        child: Center(widthFactor: width == null ? 1 : null, child: child),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Band capsule and icon button

enum OBBandState { live, off, none }

class OBBandCapsule extends StatelessWidget {
  final OBBandState state;

  /// Battery percent from the band; null shows "—", never a guess.
  final int? battery;
  final bool small;
  final VoidCallback? onTap;
  const OBBandCapsule({
    super.key,
    required this.state,
    this.battery,
    this.small = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final h = small ? 32.0 : 40.0;
    final (Widget lead, String text) = switch (state) {
      OBBandState.live => (
        OBLed(on: true, size: small ? 7 : 8),
        battery == null ? '—' : '$battery %',
      ),
      OBBandState.off => (
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: g.muted, width: 1.5),
          ),
        ),
        'getrennt',
      ),
      OBBandState.none => (
        Icon(LucideIcons.plus, size: 14, color: g.ink),
        'Band',
      ),
    };
    final label = switch (state) {
      OBBandState.live =>
        'Band verbunden, Akku ${battery == null ? 'unbekannt' : '$battery Prozent'}',
      OBBandState.off => 'Band getrennt',
      OBBandState.none => 'Band verbinden',
    };
    return _Hit(
      label: label,
      onTap: onTap,
      child: Container(
        height: h,
        padding: EdgeInsets.only(left: small ? 10 : 12, right: small ? 11 : 14),
        decoration: g.raised(radius: h / 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            lead,
            SizedBox(width: small ? 6 : 8),
            Text(
              text,
              style: g.t(
                small ? 13 : 14,
                small ? 16 : 18,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OBIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool small;
  final VoidCallback? onTap;
  const OBIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.small = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final s = small ? 32.0 : 40.0;
    return _Hit(
      label: label,
      onTap: onTap,
      width: 44,
      child: Container(
        width: s,
        height: s,
        decoration: g.raised(radius: s / 2),
        child: Icon(icon, size: small ? 16 : 18, color: g.ink),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page headers

class OBPageHeader extends StatelessWidget {
  final _Kind _kind;
  final String title;
  final String? subtitle;
  final Widget? band;
  final VoidCallback? onTitle, onProfile, onBack, onTrailing;
  final String backLabel;
  final IconData trailing;
  final String trailingLabel;

  /// Hub: "Heute ⌄" + date, band capsule and profile on the right.
  const OBPageHeader.hub({
    super.key,
    required this.title,
    required this.subtitle,
    required this.band,
    this.onTitle,
    this.onProfile,
  }) : _kind = _Kind.hub,
       onBack = null,
       onTrailing = null,
       backLabel = '',
       trailing = LucideIcons.info,
       trailingLabel = '';

  /// Detail: back key with the previous page, centred caps title, info key.
  const OBPageHeader.detail({
    super.key,
    required this.title,
    this.subtitle,
    required this.backLabel,
    required this.onBack,
    this.trailing = LucideIcons.info,
    this.trailingLabel = 'Erklärung',
    this.onTrailing,
  }) : _kind = _Kind.detail,
       band = null,
       onTitle = null,
       onProfile = null;

  /// Compact: the scrolled hub, small band capsule and profile.
  const OBPageHeader.compact({
    super.key,
    required this.title,
    this.subtitle,
    required this.band,
    this.onProfile,
  }) : _kind = _Kind.compact,
       onBack = null,
       onTitle = null,
       onTrailing = null,
       backLabel = '',
       trailing = LucideIcons.info,
       trailingLabel = '';

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    switch (_kind) {
      case _Kind.hub:
        return Padding(
          padding: const EdgeInsets.only(left: 24, right: 18, top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  button: onTitle != null,
                  label: onTitle == null ? null : '$title, Datum wählen',
                  child: GestureDetector(
                    onTap: onTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: g.t(
                                  30,
                                  34,
                                  weight: FontWeight.w700,
                                  tracking: -.03,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OBChevron(
                              direction: AxisDirection.down,
                              size: 16,
                              color: g.muted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (subtitle != null)
                          Text(subtitle!, style: g.t(14, 18, color: g.ink2)),
                      ],
                    ),
                  ),
                ),
              ),
              ?band,
              const SizedBox(width: 4),
              OBIconButton(
                icon: LucideIcons.user,
                label: 'Profil',
                onTap: onProfile,
              ),
            ],
          ),
        );
      case _Kind.detail:
        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 14, top: 2),
          child: Row(
            children: [
              _Hit(
                label: 'Zurück zu $backLabel',
                onTap: onBack,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 8, right: 14),
                  decoration: g.raised(radius: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OBChevron(
                        direction: AxisDirection.left,
                        size: 20,
                        color: g.ink,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        backLabel,
                        style: g.t(15, 18, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: g.t(13, 16, weight: FontWeight.w700, tracking: .1),
                    ),
                    const SizedBox(height: 1),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: g.t(12, 15, color: g.muted),
                      ),
                  ],
                ),
              ),
              OBIconButton(
                icon: trailing,
                label: trailingLabel,
                onTap: onTrailing,
              ),
            ],
          ),
        );
      case _Kind.compact:
        // Opaque page tone: it floats over scrolled content, and a
        // translucent fill without blur shows that content as ghosts.
        return Container(
          padding: const EdgeInsets.only(left: 16, right: 14, bottom: 4),
          decoration: BoxDecoration(
            color: g.page,
            border: Border(bottom: BorderSide(color: g.hairline)),
          ),
          child: Row(
            children: [
              ?band,
              Expanded(
                child: Column(
                  children: [
                    Text(title, style: g.t(17, 21, weight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!, style: g.t(11, 14, color: g.muted)),
                  ],
                ),
              ),
              OBIconButton(
                icon: LucideIcons.user,
                label: 'Profil',
                small: true,
                onTap: onProfile,
              ),
            ],
          ),
        );
    }
  }
}

enum _Kind { hub, detail, compact }

// ---------------------------------------------------------------------------
// Sync line

enum OBSyncKind { live, partial, stale, never, past }

/// "Daten bis 09:38 · Nacht lückenlos ›". The caller writes the sentence; the
/// kind sets its weight and the hollow LED for a stale band.
class OBSyncState extends StatelessWidget {
  final OBSyncKind kind;
  final String text;
  final bool synthetic;
  final VoidCallback? onTap;
  const OBSyncState({
    super.key,
    required this.kind,
    required this.text,
    this.synthetic = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final strong = kind == OBSyncKind.stale || kind == OBSyncKind.never;
    return Semantics(
      button: onTap != null,
      label: text,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 22, top: 8),
            // The chevron is part of the text so both wrap as one unit; the
            // synthetic tag (gallery/synthetic only) yields to its own line.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind == OBSyncKind.stale) ...[
                  // Centred on the first 16 pt text line.
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 4.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: g.muted, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: text),
                            if (onTap != null)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: OBChevron(size: 12, color: g.muted),
                                ),
                              ),
                          ],
                        ),
                        style: g.t(
                          12,
                          16,
                          weight: strong ? FontWeight.w700 : FontWeight.w500,
                          color: strong ? g.ink : g.muted,
                        ),
                      ),
                      if (synthetic)
                        Text(
                          'SYNTHETISCHE DATEN',
                          style: g.t(
                            10,
                            14,
                            weight: FontWeight.w500,
                            color: g.muted,
                            tracking: .1,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header, card header, footer

class OBSectionHeader extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  const OBSectionHeader(
    this.text, {
    super.key,
    this.action,
    this.onAction,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(text, style: g.caps(color: g.muted)),
            ),
          ),
          if (action != null && onAction != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _Hit(
                label: action!,
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(LucideIcons.plus, size: 14, color: g.ink),
                      const SizedBox(width: 2),
                      Text(
                        action!,
                        style: g.t(13, 16, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (action != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(action!, style: g.t(13, 16, color: g.muted)),
            )
          else if (trailing != null)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: trailing),
        ],
      ),
    );
  }
}

class OBCardHeader extends StatelessWidget {
  final String label;
  final String? note;
  final bool arrow;
  const OBCardHeader(this.label, {super.key, this.note, this.arrow = true});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: G3LabelRow(label, note: note, arrow: arrow),
  );
}

class OBFooterStamp extends StatelessWidget {
  final String text;
  final bool synthetic;
  const OBFooterStamp(this.text, {super.key, this.synthetic = false});
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 20),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: g.t(12, 16, color: g.muted),
          ),
          if (synthetic) ...[
            const SizedBox(height: 4),
            Text(
              'SYNTHETISCHE DATEN',
              style: g.t(
                11,
                14,
                weight: FontWeight.w500,
                color: g.muted,
                tracking: .1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panels, list rows, keys

class OBPanel extends StatelessWidget {
  final bool hero;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const OBPanel({
    super.key,
    required this.child,
    this.hero = false,
    this.padding,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding:
        padding ??
        EdgeInsets.symmetric(horizontal: hero ? 20 : 18, vertical: 16),
    decoration: G3
        .of(context)
        .raised(radius: hero ? AlpRadius.hero : AlpRadius.card),
    child: child,
  );
}

class OBListRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle, value;
  final VoidCallback? onTap;
  const OBListRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Semantics(
      button: onTap != null,
      label: [title, ?value, ?subtitle].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: g.raised(),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: g.track,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    leading ??
                    Icon(icon ?? LucideIcons.circle, size: 18, color: g.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: g.t(15, 19, weight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!, style: g.t(12, 16, color: g.muted)),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Text(value!, style: g.t(15, 19, weight: FontWeight.w700)),
              ],
              const SizedBox(width: 12),
              OBChevron(size: 14, color: g.gap),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Key { primary, secondary, pill }

class _KeyButton extends StatelessWidget {
  final _Key kind;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool expand;
  const _KeyButton(
    this.kind,
    this.label, {
    this.icon,
    this.onPressed,
    required this.height,
    this.expand = false,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final (Color fg, Decoration deco) = switch (kind) {
      _Key.primary => (
        g.onInk,
        BoxDecoration(
          color: g.ink,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
      _Key.secondary => (g.ink, g.raised(radius: height / 2)),
      _Key.pill => (
        g.ink,
        BoxDecoration(
          color: g.chip,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    };
    final key = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: deco,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: g.t(
                height >= 40 ? 15 : 13,
                18,
                weight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            widthFactor: expand ? null : 1,
            heightFactor: 1,
            child: key,
          ),
        ),
      ),
    );
  }
}

class OBActionPrimary extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool expand;
  const OBActionPrimary(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.height = 48,
    this.expand = false,
  });
  @override
  Widget build(BuildContext context) => _KeyButton(
    _Key.primary,
    label,
    icon: icon,
    onPressed: onPressed,
    height: height,
    expand: expand,
  );
}

class OBActionSecondary extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool expand;
  const OBActionSecondary(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.height = 48,
    this.expand = false,
  });
  @override
  Widget build(BuildContext context) => _KeyButton(
    _Key.secondary,
    label,
    icon: icon,
    onPressed: onPressed,
    height: height,
    expand: expand,
  );
}

/// Small key on a panel: "Ziel festlegen".
class OBPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const OBPillButton(this.label, {super.key, this.onPressed});
  @override
  Widget build(BuildContext context) =>
      _KeyButton(_Key.pill, label, onPressed: onPressed, height: 30);
}

// ---------------------------------------------------------------------------
// Segmented control

class OBSegmented extends StatelessWidget {
  final List<String> items;
  final int selected;
  final double horizontalPadding;

  /// Indices that exist but have no data yet ("Erholung" before its basis).
  final Set<int> disabled;
  final ValueChanged<int>? onChanged;
  final bool expand;
  const OBSegmented({
    super.key,
    required this.items,
    required this.selected,
    this.horizontalPadding = 10,
    this.disabled = const {},
    this.onChanged,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    Widget seg(int i) {
      final on = i == selected;
      final off = disabled.contains(i);
      final child = Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 5,
        ),
        alignment: expand ? Alignment.center : null,
        decoration: on ? g.raised(radius: 12) : null,
        child: Text(
          items[i],
          style: g.t(
            12,
            14,
            weight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? g.ink : (off ? g.gap : g.ink2),
          ),
        ),
      );
      final tap = Semantics(
        button: true,
        selected: on,
        enabled: !off && onChanged != null,
        label: off ? '${items[i]}, noch keine Werte' : items[i],
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: off || onChanged == null ? null : () => onChanged!(i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Align(
              alignment: Alignment.topCenter,
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: child,
              ),
            ),
          ),
        ),
      );
      return expand ? Expanded(child: tap) : tap;
    }

    if (!expand) {
      final widths = <double>[];
      for (var i = 0; i < items.length; i++) {
        final on = i == selected;
        final off = disabled.contains(i);
        final style = g.t(
          12,
          14,
          weight: on ? FontWeight.w700 : FontWeight.w500,
          color: on ? g.ink : (off ? g.gap : g.ink2),
        );
        final painter = TextPainter(
          text: TextSpan(text: items[i], style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        widths.add(painter.width + 2 * horizontalPadding);
      }
      final visualWidth = widths.fold<double>(0, (sum, item) => sum + item);
      final width = visualWidth < 44 ? 44.0 : visualWidth;
      var left = 0.0;
      final visuals = <Widget>[];
      final targets = <Widget>[];
      for (var i = 0; i < items.length; i++) {
        final itemWidth = widths[i];
        final on = i == selected;
        final off = disabled.contains(i);
        visuals.add(
          Positioned(
            left: left + 3,
            top: 10,
            width: itemWidth,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 5,
              ),
              decoration: on ? g.raised(radius: 12) : null,
              child: Text(
                items[i],
                style: g.t(
                  12,
                  14,
                  weight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? g.ink : (off ? g.gap : g.ink2),
                ),
              ),
            ),
          ),
        );
        final targetWidth = itemWidth < 44 ? 44.0 : itemWidth;
        targets.add(
          Positioned(
            left: (left + (itemWidth - targetWidth) / 2).clamp(
              0.0,
              (width - targetWidth).clamp(0.0, width),
            ),
            top: 0,
            width: targetWidth,
            height: 44,
            child: Semantics(
              button: true,
              selected: on,
              enabled: !off && onChanged != null,
              label: off ? '${items[i]}, noch keine Werte' : items[i],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: off || onChanged == null ? null : () => onChanged!(i),
              ),
            ),
          ),
        );
        left += itemWidth;
      }
      return SizedBox(
        width: width,
        height: 44,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 7,
              height: 30,
              child: DecoratedBox(decoration: g.pressed(radius: 15)),
            ),
            ExcludeSemantics(child: Stack(children: visuals)),
            ...targets,
          ],
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 7,
            height: 30,
            child: DecoratedBox(decoration: g.pressed(radius: 15)),
          ),
          Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [for (var i = 0; i < items.length; i++) seg(i)],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet chrome

class OBSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final String cancelLabel, confirmLabel;
  final VoidCallback? onCancel, onConfirm;
  const OBSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.cancelLabel = 'Abbrechen',
    this.confirmLabel = 'Speichern',
    this.onCancel,
    this.onConfirm,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
      decoration: BoxDecoration(
        color: g.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: g.dark ? const Color(0xB3000000) : const Color(0x33000000),
            offset: const Offset(0, -2),
            blurRadius: 16,
          ),
        ],
      ),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    title,
                    style: g.t(20, 24, weight: FontWeight.w700, tracking: -.02),
                  ),
                ),
              ),
              _Hit(
                label: 'Schließen',
                width: 44,
                onTap: onCancel,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: g.chip,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.x, size: 16, color: g.ink),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            Text(subtitle!, style: g.t(14, 19, color: g.ink2)),
          ],
          const SizedBox(height: 16),
          child,
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OBActionSecondary(
                  cancelLabel,
                  onPressed: onCancel,
                  expand: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OBActionPrimary(
                  confirmLabel,
                  onPressed: onConfirm,
                  expand: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty and error blocks

/// An honest refusal: what is missing, why, and what to do. Not an error.
class OBEmptyState extends StatelessWidget {
  final IconData icon;
  final String title, reason;
  final String? action;
  final VoidCallback? onAction;
  const OBEmptyState({
    super.key,
    this.icon = LucideIcons.info,
    required this.title,
    required this.reason,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: g.pressed(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: g.ink),
          const SizedBox(height: 10),
          Text(title, style: g.t(17, 22, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(reason, style: g.t(14, 19, color: g.ink2)),
          if (action != null)
            Semantics(
              button: true,
              label: action,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          action!,
                          style: g.t(14, 18, weight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 2),
                      OBChevron(size: 14, color: g.muted),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A failure the user can retry — never shown as an empty state.
class OBErrorBlock extends StatelessWidget {
  final String title, reason;
  final String retryLabel;
  final VoidCallback? onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  const OBErrorBlock({
    super.key,
    required this.title,
    required this.reason,
    this.retryLabel = 'Erneut versuchen',
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: g.pressed(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          Text(reason, style: g.t(14, 19, color: g.ink2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              OBActionPrimary(
                retryLabel,
                icon: LucideIcons.refreshCw,
                onPressed: onRetry,
                height: 40,
              ),
              if (secondaryLabel != null)
                OBActionSecondary(
                  secondaryLabel!,
                  onPressed: onSecondary,
                  height: 40,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date strip

class OBDateStrip extends StatelessWidget {
  /// (weekday, day number); the last entry is today.
  final List<(String, String)> days;
  final int selected;
  final ValueChanged<int>? onSelect;
  final VoidCallback? onCalendar;
  const OBDateStrip({
    super.key,
    required this.days,
    required this.selected,
    this.onSelect,
    this.onCalendar,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: g.raised(),
      child: Row(
        children: [
          for (final (i, (wd, n)) in days.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: '$wd $n${i == days.length - 1 ? ', heute' : ''}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSelect == null ? null : () => onSelect!(i),
                  child: Container(
                    padding: const EdgeInsets.only(top: 7, bottom: 6),
                    decoration: i == selected
                        ? BoxDecoration(
                            color: g.ink,
                            borderRadius: BorderRadius.circular(14),
                          )
                        : null,
                    child: Column(
                      children: [
                        Text(
                          wd,
                          style: g.t(
                            11,
                            13,
                            weight: FontWeight.w500,
                            color: i == selected ? g.onInk : g.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          n,
                          style: g.t(
                            17,
                            21,
                            weight: FontWeight.w700,
                            color: i == selected ? g.onInk : g.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == days.length - 1
                                ? (i == selected ? g.onInk : g.ink)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          _Hit(
            label: 'Kalender',
            width: 44,
            onTap: onCalendar,
            child: Icon(LucideIcons.calendar, size: 18, color: g.ink),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Number field

/// Large numeric entry: "78,4 kg" in a pressed well, with its time below.
class OBFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String unit;
  final String when;
  final VoidCallback? onTime;
  const OBFormField.number({
    super.key,
    required this.label,
    required this.controller,
    required this.unit,
    required this.when,
    this.onTime,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final big = g.t(48, 52, weight: FontWeight.w700, tracking: -.04);
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: g.t(
                11,
                14,
                weight: FontWeight.w700,
                color: g.muted,
                tracking: .1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 88,
              decoration: g.pressed(radius: 16),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IntrinsicWidth(
                    child: TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                      ],
                      textAlign: TextAlign.right,
                      style: big,
                      cursorColor: g.ink,
                      decoration: const InputDecoration.collapsed(
                        hintText: '—',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    unit,
                    style: g.t(18, 22, weight: FontWeight.w500, color: g.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    when,
                    style: g.t(13, 16, weight: FontWeight.w500, color: g.ink2),
                  ),
                ),
                if (onTime != null)
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        Text(
                          'Zeit ändern',
                          style: g.t(13, 16, weight: FontWeight.w700),
                        ),
                        const SizedBox(width: 2),
                        OBChevron(size: 12, color: g.muted),
                      ],
                    ),
                  )
                else
                  Text('Zeit ändern', style: g.t(13, 16, color: g.muted)),
              ],
            ),
          ],
        ),
        if (onTime != null)
          Positioned(
            bottom: 0,
            right: 0,
            width: 100,
            height: 44,
            child: Semantics(
              button: true,
              label: 'Zeit ändern',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTime,
              ),
            ),
          ),
      ],
    );
  }
}
