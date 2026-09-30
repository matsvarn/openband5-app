// G3 chrome Bausteine: headers, band capsule, sync line, section and card
// headers, list rows, keys, segmented control, sheet, empty/error blocks,
// footer stamp, date strip, number field and panels.
//
// Visual keys follow Paper (40 pt); every tap target keeps 44 pt.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../ble/band_status_l10n.dart' show localizedBandStatus;
import '../../ble/ble_state.dart' show BandCondition, BandStatus;

import '../alp_tokens.dart';
import '../theme.dart' show OBChevron, OBLed;
import 'g3_format.dart';
import 'g3_theme.dart';
import 'metrics.dart' show G3LabelRow;

/// A 44 pt hit area around a smaller visual key.
class _Hit extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final double? width;
  final Alignment alignment;
  final double bottomPadding, height;
  const _Hit({
    required this.label,
    required this.onTap,
    required this.child,
    this.width,
    this.alignment = Alignment.center,
    this.bottomPadding = 0,
    this.height = 44,
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
        height: height,
        child: Align(
          alignment: alignment,
          widthFactor: width == null ? 1 : null,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Text link with the shared inline chevron and a 44 pt tap target.
class OBLink extends StatelessWidget {
  final String label;
  final bool bottomAligned;
  final String? semanticsLabel;
  final VoidCallback onTap;
  const OBLink(
    this.label, {
    super.key,
    this.semanticsLabel,
    this.bottomAligned = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final footer =
        bottomAligned &&
        context.findAncestorWidgetOfExactType<OBPanel>() != null;
    final lineHeight = MediaQuery.textScalerOf(context).scale(13) * 16 / 13;
    final targetHeight = footer
        ? (lineHeight + 20).clamp(44.0, double.infinity)
        : 44.0;
    final target = _Hit(
      height: targetHeight,
      bottomPadding: footer ? 18 : 0,
      label: semanticsLabel ?? label,
      onTap: onTap,
      alignment: bottomAligned ? Alignment.bottomCenter : Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: g.t(13, 16, weight: FontWeight.w700)),
          const SizedBox(width: 2),
          OBChevron(size: 12, color: g.muted),
        ],
      ),
    );
    if (!footer) {
      return target;
    }
    return _LinkTapArea(
      overlap: targetHeight - (lineHeight + 2).clamp(18.0, double.infinity),
      child: target,
    );
  }
}

// Footer layout stays at text height; its target uses the gap and bottom padding.
class _LinkTapArea extends SingleChildRenderObjectWidget {
  const _LinkTapArea({required this.overlap, required super.child});
  final double overlap;
  @override
  RenderObject createRenderObject(BuildContext context) => _LinkTapBox(overlap);
  @override
  void updateRenderObject(BuildContext context, _LinkTapBox renderObject) =>
      renderObject.overlap = overlap;
}

class _LinkTapBox extends RenderShiftedBox {
  _LinkTapBox(this._overlap) : super(null);
  double _overlap;
  bool _panelHit = false;
  set overlap(double value) {
    if (value == _overlap) return;
    _overlap = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height - _overlap),
    );
    (child!.parentData! as BoxParentData).offset = Offset(0, 18 - _overlap);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_panelHit && !size.contains(position)) return false;
    final hit = result.addWithPaintOffset(
      offset: Offset(0, 18 - _overlap),
      position: position,
      hitTest: (result, position) => child!.hitTest(result, position: position),
    );
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset + Offset(0, 18 - _overlap));
}

// Route footer targets through the card so rows do not clip the padding area.
class _PanelLinkTargets extends SingleChildRenderObjectWidget {
  const _PanelLinkTargets({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _PanelLinkBox();
}

class _PanelLinkBox extends RenderProxyBox {
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final links = <_LinkTapBox>[];
    final content = <Rect>[];
    bool collect(RenderObject object) {
      if (object is _LinkTapBox) {
        links.add(object);
        return true;
      }
      var hasLink = false;
      object.visitChildren((child) {
        hasLink = collect(child) || hasLink;
      });
      if (!hasLink &&
          object is RenderBox &&
          (object is RenderParagraph ||
              object is RenderImage ||
              object is RenderCustomPaint ||
              object is RenderDecoratedBox)) {
        content.add(
          MatrixUtils.transformRect(
            object.getTransformTo(this),
            Offset.zero & object.size,
          ),
        );
      }
      return hasLink;
    }

    child?.visitChildren(collect);
    for (final link in links) {
      final transform = link.getTransformTo(this);
      final visual = MatrixUtils.transformRect(
        transform,
        Offset.zero & link.size,
      );
      var top = visual.top + 18 - link._overlap;
      for (final rect in content) {
        if (rect.bottom <= visual.top &&
            rect.right > visual.left &&
            rect.left < visual.right) {
          if (rect.bottom > top) top = rect.bottom;
        }
      }
      final target = Rect.fromLTRB(
        visual.left,
        top,
        visual.right,
        visual.bottom + 18,
      );
      if (target.contains(position) &&
          result.addWithPaintTransform(
            transform: transform,
            position: position,
            hitTest: (result, position) {
              link._panelHit = true;
              try {
                return link.hitTest(result, position: position);
              } finally {
                link._panelHit = false;
              }
            },
          )) {
        return true;
      }
    }
    return super.hitTestChildren(result, position: position);
  }
}

// ---------------------------------------------------------------------------
// Band capsule and icon button

enum OBBandState { live, off, none }

class OBBandCapsule extends StatelessWidget {
  final OBBandState state;
  final BandStatus? bandStatus;

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
    this.bandStatus,
  });

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final h = small ? 32.0 : 40.0;
    final status = bandStatus;
    final statusText = switch (status?.condition) {
      BandCondition.connecting => 'Verbindet …',
      BandCondition.scanning => g3BandScanningLabel,
      BandCondition.unreachable => 'nicht erreichbar',
      BandCondition.bluetoothOff => 'Bluetooth aus',
      BandCondition.bluetoothDenied => 'Bluetooth gesperrt',
      _ when status?.isFault == true => localizedBandStatus(
        context,
        status!,
      ).title,
      _ => null,
    };
    final displayState = switch (status?.condition) {
      BandCondition.connected => OBBandState.live,
      null => state,
      BandCondition.disconnected when state == OBBandState.none => state,
      _ => OBBandState.off,
    };
    final (Widget lead, String text) = switch (displayState) {
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
        statusText ?? 'getrennt',
      ),
      OBBandState.none => (
        Icon(LucideIcons.plus, size: 14, color: g.ink),
        'Band',
      ),
    };
    final label = switch (displayState) {
      OBBandState.live =>
        'Band verbunden, Akku ${battery == null ? 'unbekannt' : '$battery Prozent'}',
      OBBandState.off => statusText ?? 'Band getrennt',
      OBBandState.none => 'Band verbinden',
    };
    return _Hit(
      label: label,
      onTap: onTap,
      child: Container(
        height: h,
        padding: EdgeInsets.only(left: small ? 10 : 12, right: small ? 11 : 14),
        decoration: onTap == null
            ? BoxDecoration(
                color: g.track,
                borderRadius: BorderRadius.circular(h / 2),
              )
            : g.raised(radius: h / 2),
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
  final bool small, plain;
  final VoidCallback? onTap;
  const OBIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.small = false,
    this.plain = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    if (onTap == null) return const SizedBox(width: 44, height: 44);
    final g = G3.of(context);
    final s = small ? 32.0 : 40.0;
    return _Hit(
      label: label,
      onTap: onTap,
      width: 44,
      child: Container(
        width: s,
        height: s,
        decoration: plain ? null : g.raised(radius: s / 2),
        child: Icon(icon, size: small ? 16 : 18, color: g.ink),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page headers

class OBPageHeader extends StatelessWidget {
  final G3Domain domain;
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
       domain = G3Domain.neutral,
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
    this.domain = G3Domain.neutral,
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
       domain = G3Domain.neutral,
       onBack = null,
       onTitle = null,
       onTrailing = null,
       backLabel = '',
       trailing = LucideIcons.info,
       trailingLabel = '';

  /// Modal flow header with a 44 pt close target and a centred title.
  const OBPageHeader.modal({
    super.key,
    required this.title,
    required this.onBack,
    this.backLabel = 'Schließen',
    IconData leadingIcon = LucideIcons.x,
  }) : _kind = _Kind.modal,
       domain = G3Domain.neutral,
       trailing = leadingIcon,
       subtitle = null,
       band = null,
       onTitle = null,
       onProfile = null,
       onTrailing = null,
       trailingLabel = '',
       assert(onBack != null);

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    switch (_kind) {
      case _Kind.modal:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              OBIconButton(icon: trailing, label: backLabel, onTap: onBack),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: g.t(13, 16, weight: FontWeight.w700, tracking: .1),
                ),
              ),
              const SizedBox(width: 44, height: 44),
            ],
          ),
        );
      case _Kind.hub:
        return Padding(
          padding: const EdgeInsets.only(left: 24, right: 16, top: 4),
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
                            if (onTitle != null)
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
              if (onProfile == null)
                const SizedBox(width: 44, height: 44)
              else
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
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Row(
            children: [
              if (onBack == null)
                const SizedBox(width: 44, height: 44)
              else
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: g.t(
                          13,
                          16,
                          weight: FontWeight.w700,
                          tracking: .1,
                          color: g.domainHue(domain),
                        ),
                      ),
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
              if (onTrailing == null)
                const SizedBox(width: 44, height: 44)
              else
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
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
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
              if (onProfile == null)
                const SizedBox(width: 44, height: 44)
              else
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

enum _Kind { hub, detail, compact, modal }

/// A detail header outside the 16 pt content gutter, followed by a 12 pt gap.
/// [bottomInset] is scroll padding, so content can travel behind a tab bar.
class G3DetailPage extends StatelessWidget {
  final Widget header;
  final List<Widget> children;

  /// A section after the inset content, spanning the page width.
  final Widget? fullWidthSection;
  final ScrollController? scrollController;
  final double bottomInset;
  const G3DetailPage({
    super.key,
    required this.header,
    required this.children,
    this.fullWidthSection,
    this.scrollController,
    this.bottomInset = 0,
  });

  @override
  Widget build(BuildContext context) => ListView(
    controller: scrollController,
    padding: EdgeInsets.only(bottom: bottomInset),
    children: [
      header,
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
      ?fullWidthSection,
    ],
  );
}

// ---------------------------------------------------------------------------
// Sync line

enum OBSyncKind { live, partial, stale, never, past }

// Keep the 44 pt target while the line occupies only its visible rhythm.
class _SyncTapArea extends SingleChildRenderObjectWidget {
  const _SyncTapArea({required this.compact, required super.child});
  final bool compact;
  @override
  RenderObject createRenderObject(BuildContext context) => _SyncTapBox(compact);
  @override
  void updateRenderObject(BuildContext context, _SyncTapBox renderObject) =>
      renderObject.compact = compact;
}

class _SyncTapBox extends RenderShiftedBox {
  _SyncTapBox(this._compact) : super(null);
  bool _compact;
  set compact(bool value) {
    if (value == _compact) return;
    _compact = value;
    markNeedsLayout();
  }

  Offset get _offset => Offset(0, _compact ? -12 : 0);
  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height - (_compact ? 20 : 0)),
    );
    (child!.parentData! as BoxParentData).offset = _offset;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!child!.hitTest(result, position: position - _offset)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset + _offset);
}

/// "Daten bis 09:38 · Nacht lückenlos ›" with a separate 44 pt tap target.
class OBSyncState extends StatelessWidget {
  final OBSyncKind kind;
  final String text;
  final bool synthetic, compact;
  final VoidCallback? onTap;
  const OBSyncState({
    super.key,
    required this.kind,
    required this.text,
    this.synthetic = false,
    this.compact = true,
    this.onTap,
  });
  OBSyncState.dataThrough({
    super.key,
    required this.kind,
    required DateTime? storedAt,
    required DateTime now,
    this.synthetic = false,
    this.compact = true,
    this.onTap,
  }) : text = g3DataThrough(storedAt, now: now);
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final strong = kind == OBSyncKind.stale || kind == OBSyncKind.never;
    return _SyncTapArea(
      compact: compact,
      child: Semantics(
        button: onTap != null,
        label: text,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 16,
                top: compact ? 20 : 8,
                bottom: compact ? 8 : 0,
              ),
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
                        if (synthetic) const G3SyntheticLabel(),
                      ],
                    ),
                  ),
                ],
              ),
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
  final G3Domain domain;
  final IconData? glyph;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final double trailingTopPadding;
  final bool _insideDetailPage;
  const OBSectionHeader(
    this.text, {
    super.key,
    this.domain = G3Domain.neutral,
    this.glyph,
    this.action,
    this.onAction,
    this.trailing,
    this.trailingTopPadding = 10,
  }) : _insideDetailPage = false;

  /// Use in [G3DetailPage.children], which already have a 16 pt gutter.
  const OBSectionHeader.detail(
    this.text, {
    super.key,
    this.domain = G3Domain.neutral,
    this.glyph,
    this.action,
    this.onAction,
    this.trailing,
    this.trailingTopPadding = 10,
  }) : _insideDetailPage = true;
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: _insideDetailPage ? 8 : 24,
        right: _insideDetailPage ? 0 : 16,
      ),
      child: trailing != null && action == null
          ? Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _title(g),
                Padding(
                  padding: EdgeInsets.only(top: trailingTopPadding),
                  child: Transform.translate(
                    offset: Offset(0, 5 - trailingTopPadding / 2),
                    child: trailing!,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _title(g)),
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
                  ),
              ],
            ),
    );
  }

  Widget _title(G3 g) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (glyph != null) ...[
          Icon(glyph, size: 16, color: g.domainHue(domain)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: g.caps(
              color: domain == G3Domain.neutral ? g.muted : g.domainHue(domain),
            ),
          ),
        ),
      ],
    ),
  );
}

class OBCardHeader extends StatelessWidget {
  final G3Domain domain;
  final IconData? glyph;
  final String label;
  final String? note;
  final VoidCallback? onTap;
  // Kept until area callers migrate; it can suppress, never create, an arrow.
  final bool arrow;
  const OBCardHeader(
    this.label, {
    super.key,
    this.domain = G3Domain.neutral,
    this.glyph,
    this.note,
    this.onTap,
    this.arrow = true,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: G3LabelRow(
      label,
      domain: domain,
      glyph: glyph,
      note: note,
      onTap: onTap,
      arrow: arrow,
    ),
  );
}

class OBFooterStamp extends StatelessWidget {
  final String text;
  final bool synthetic;
  const OBFooterStamp(this.text, {super.key, this.synthetic = false});
  OBFooterStamp.dataThrough({
    super.key,
    required DateTime? storedAt,
    required DateTime now,
    this.synthetic = false,
  }) : text = g3DataThrough(storedAt, now: now);
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
            const G3SyntheticLabel(),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panels, list rows, keys

/// Show once per screen: on the tab root sync line or a detail footer.
class G3SyntheticLabel extends StatelessWidget {
  const G3SyntheticLabel({super.key});
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return Text(
      'SYNTHETISCHE DATEN',
      style: g.t(11, 14, weight: FontWeight.w500, color: g.muted, tracking: .1),
    );
  }
}

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
  Widget build(BuildContext context) => _PanelLinkTargets(
    child: Container(
      padding: padding ?? kG3CardPadding,
      decoration: G3
          .of(context)
          .raised(radius: hero ? AlpRadius.hero : AlpRadius.card),
      child: child,
    ),
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
          padding: kG3CardPadding,
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
              if (onTap != null) ...[
                const SizedBox(width: 12),
                OBChevron(size: 14, color: g.gap),
              ],
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
    final scaler = MediaQuery.textScalerOf(context);
    final bold = MediaQuery.boldTextOf(context);
    TextStyle style(int i) => DefaultTextStyle.of(context).style.merge(
      g.t(
        12,
        14,
        weight: bold || i == selected ? FontWeight.w700 : FontWeight.w500,
        color: i == selected ? g.ink : (disabled.contains(i) ? g.gap : g.ink2),
      ),
    );
    final lineHeight = scaler.scale(12) * 14 / 12;
    final height = (lineHeight + 30).clamp(44.0, double.infinity);
    final trackHeight = (lineHeight + 16).clamp(30.0, double.infinity);
    Widget seg(int i, {bool expanded = false}) {
      final on = i == selected;
      final off = disabled.contains(i);
      final child = Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 5,
        ),
        alignment: expanded ? Alignment.center : null,
        decoration: on ? g.raised(radius: 12) : null,
        child: Text(items[i], style: style(i)),
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
      return expanded ? Expanded(child: tap) : tap;
    }

    final widths = <double>[];
    for (var i = 0; i < items.length; i++) {
      final textStyle = style(i);
      final painter = TextPainter(
        text: TextSpan(text: items[i], style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      widths.add(
        (painter.width + 2 * horizontalPadding).clamp(44.0, double.infinity),
      );
      painter.dispose();
    }
    Widget natural() {
      final visualWidth = widths.fold<double>(0, (sum, item) => sum + item);
      final width = visualWidth + 6;
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
              child: Text(items[i], style: style(i)),
            ),
          ),
        );
        targets.add(
          Positioned(
            left: left + 3,
            top: 0,
            width: itemWidth,
            height: height,
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
      return LayoutBuilder(
        builder: (context, constraints) {
          if (width > constraints.maxWidth) {
            return DecoratedBox(
              decoration: g.pressed(radius: 15),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Wrap(
                  children: [for (var i = 0; i < items.length; i++) seg(i)],
                ),
              ),
            );
          }
          return SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 7,
                  height: trackHeight,
                  child: DecoratedBox(decoration: g.pressed(radius: 15)),
                ),
                ExcludeSemantics(child: Stack(children: visuals)),
                ...targets,
              ],
            ),
          );
        },
      );
    }

    if (!expand) return natural();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widths.any(
          (width) => width > constraints.maxWidth / items.length,
        )) {
          return natural();
        }
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 7,
                height: trackHeight,
                child: DecoratedBox(decoration: g.pressed(radius: 15)),
              ),
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  for (var i = 0; i < items.length; i++) seg(i, expanded: true),
                ],
              ),
            ],
          ),
        );
      },
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
  final VoidCallback? onCancel, onConfirm, onClose;
  const OBSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.cancelLabel = 'Abbrechen',
    this.confirmLabel = 'Speichern',
    this.onCancel,
    this.onConfirm,
    this.onClose,
  });
  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    final close = onClose ?? onCancel ?? () => Navigator.of(context).maybePop();
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
                onTap: close,
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
          if (onCancel != null || onConfirm != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                if (onCancel != null)
                  Expanded(
                    child: OBActionSecondary(
                      cancelLabel,
                      onPressed: onCancel,
                      expand: true,
                    ),
                  ),
                if (onCancel != null && onConfirm != null)
                  const SizedBox(width: 10),
                if (onConfirm != null)
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
        ],
      ),
    );
  }
}

/// Shared explanation sheet. The route covers the floating tab bar.
class OBInfoSheet extends StatelessWidget {
  final String title;
  final List<String> paragraphs;
  const OBInfoSheet({super.key, required this.title, required this.paragraphs});

  @override
  Widget build(BuildContext context) {
    final g = G3.of(context);
    return OBSheet(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Text(paragraphs[i], style: g.t(14, 20, color: g.ink2)),
          ],
        ],
      ),
    );
  }
}

Future<void> showOBInfoSheet(
  BuildContext context, {
  required String title,
  required List<String> paragraphs,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => SafeArea(
    top: false,
    child: OBInfoSheet(title: title, paragraphs: paragraphs),
  ),
);

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
      padding: kG3CardPadding,
      decoration: g.pressed(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: g.ink),
          const SizedBox(height: 10),
          Text(title, style: g.t(17, 22, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(reason, style: g.t(14, 19, color: g.ink2)),
          if (action != null && onAction != null)
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
