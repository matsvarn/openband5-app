import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui2/app_shell.dart';
import 'alp_tokens.dart';
import 'theme.dart';

abstract final class _G3Tab {
  // Paper Bausteine · G3 geometry and shadow values without shared tokens.
  static const double height = 64;
  static const double itemMinHeight = 54;
  static const double itemRadius = 27;
  static const double outerPadding = 5;
  static const double iconLabelGap = 3;
  static const double maxLabelScale = 2;
  static const double contentInset = 112;
  static const double safeAreaOffset = 8;
  static const double bottomMin = 24;
  static const double bottomMax = 40;
  static const double bannerGap = 8;
  static const double iconSize = 22;
  static const double labelSize = 11;
  static const double labelHeight = 13 / 11;
  static const Color lightHighlight = Color(0xE6FFFFFF);
  static const Color darkHighlight = Color(0x12FFFFFF);
  static const List<BoxShadow> lightShadow = [
    BoxShadow(color: Color(0x24000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 6), blurRadius: 16),
  ];
  static const List<BoxShadow> darkShadow = [
    BoxShadow(color: Color(0xA6000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 6), blurRadius: 16),
  ];
}

/// Space for a root scroll view to pass under the floating control and still
/// reveal its last row above it.
const double kOBTabBarContentInset = _G3Tab.contentInset;
const double kOBTabBarHeight = _G3Tab.height;
const double kOBTabBarHorizontalInset = AlpSpace.s20;
const double kOBTabBarBannerGap = _G3Tab.bannerGap;

double obTabBarBottom(BuildContext context) =>
    (MediaQuery.viewPaddingOf(context).bottom - _G3Tab.safeAreaOffset).clamp(
      _G3Tab.bottomMin,
      _G3Tab.bottomMax,
    );

class OBTabBar extends StatelessWidget {
  final List<ShellDomain> domains;
  final ShellDomain selected;
  final ValueChanged<ShellDomain> onSelect;

  const OBTabBar({
    super.key,
    required this.domains,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final labelScale = math.min(
      MediaQuery.textScalerOf(context).scale(1),
      _G3Tab.maxLabelScale,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: _G3Tab.height),
      padding: const EdgeInsets.all(_G3Tab.outerPadding),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AlpRadius.tabbar),
        boxShadow: p.dark ? _G3Tab.darkShadow : _G3Tab.lightShadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AlpRadius.tabbar),
        border: Border.all(
          color: p.dark ? _G3Tab.darkHighlight : _G3Tab.lightHighlight,
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < domains.length; index++) ...[
            if (index > 0) const SizedBox(width: AlpSpace.s4),
            Expanded(child: _item(context, domains[index], index, labelScale)),
          ],
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    ShellDomain domain,
    int index,
    double labelScale,
  ) {
    final p = OB.of(context);
    final active = domain == selected;
    final color = active ? p.ink : p.muted;
    return Semantics(
      key: ValueKey('ob-tab-${domain.name}'),
      label: '${domain.label}, Tab, ${index + 1} von ${domains.length}',
      selected: active,
      button: true,
      onTap: () => onSelect(domain),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(domain),
          borderRadius: BorderRadius.circular(_G3Tab.itemRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: _G3Tab.itemMinHeight),
            decoration: active
                ? p.insetDecoration(
                    radius: _G3Tab.itemRadius,
                    color: p.dark ? AlpColor.darkTrack : AlpColor.track,
                  )
                : null,
            child: Center(
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AlpSpace.s4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(domain.icon, size: _G3Tab.iconSize, color: color),
                    const SizedBox(height: _G3Tab.iconLabelGap),
                    Text(
                      domain.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.linear(labelScale),
                      style: p
                          .text(
                            _G3Tab.labelSize,
                            weight: active ? FontWeight.w700 : FontWeight.w500,
                            color: color,
                          )
                          .copyWith(height: _G3Tab.labelHeight),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
