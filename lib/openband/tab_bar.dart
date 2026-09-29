import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui2/app_shell.dart';
import 'alp_tokens.dart';
import 'theme.dart';

abstract final class _G3Tab {
  // G3 token pending: radius-alp-tabbar
  static const double radius = 32;
  // G3 token pending: tabbar-height
  static const double height = 64;
  // G3 token pending: tabbar-item-min-height
  static const double itemMinHeight = 56;
  // G3 token pending: tabbar-item-vertical-padding
  static const double itemVerticalPadding = 5;
  // G3 token pending: tabbar-max-label-scale
  static const double maxLabelScale = 2;
  // G3 token pending: tabbar-content-inset
  static const double contentInset = 112;
  // G3 token pending: tabbar-safe-area-offset
  static const double safeAreaOffset = 8;
  // G3 token pending: tabbar-bottom-min
  static const double bottomMin = 24;
  // G3 token pending: tabbar-bottom-max
  static const double bottomMax = 40;
  // G3 token pending: tabbar-banner-gap
  static const double bannerGap = 8;
  // G3 token pending: tabbar-icon-size
  static const double iconSize = 23;
  // G3 token pending: tabbar-label-size
  static const double labelSize = 11;
  // G3 token pending: tabbar-outer-highlight-light
  static const Color lightHighlight = Color(0xE6FFFFFF);
  // G3 token pending: tabbar-outer-highlight-dark
  static const Color darkHighlight = Color(0x12FFFFFF);
  // G3 token pending: shadow-alp-float-light
  static const List<BoxShadow> lightShadow = [
    BoxShadow(color: Color(0x24000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 6), blurRadius: 16),
  ];
  // G3 token pending: shadow-alp-float-dark
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
      padding: const EdgeInsets.all(AlpSpace.s4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(_G3Tab.radius),
        border: Border.all(
          color: p.dark ? _G3Tab.darkHighlight : _G3Tab.lightHighlight,
        ),
        boxShadow: p.dark ? _G3Tab.darkShadow : _G3Tab.lightShadow,
      ),
      child: Row(
        children: [
          for (var index = 0; index < domains.length; index++)
            Expanded(child: _item(context, domains[index], index, labelScale)),
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
          borderRadius: BorderRadius.circular(_G3Tab.radius),
          child: Container(
            constraints: const BoxConstraints(minHeight: _G3Tab.itemMinHeight),
            decoration: active
                ? p.insetDecoration(radius: _G3Tab.radius, color: p.canvas)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlpSpace.s4,
                vertical: _G3Tab.itemVerticalPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(domain.icon, size: _G3Tab.iconSize, color: color),
                  const SizedBox(height: AlpSpace.s4),
                  Text(
                    domain.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.linear(labelScale),
                    style: p.text(
                      _G3Tab.labelSize,
                      weight: active ? FontWeight.w700 : FontWeight.w600,
                      color: color,
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
