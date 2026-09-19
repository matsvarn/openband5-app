import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'alp_tokens.dart';
import 'theme.dart';

bool _stackSettingsControls(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20 ||
    MediaQuery.sizeOf(context).width < 360;

/// Label + Cupertino-like switch. Shared by notification settings and any
/// other on/off row. Schedule rows add a time well on top of this layout.
class OBSettingsToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool interactive;
  final VoidCallback? onToggle;

  const OBSettingsToggleRow({
    super.key,
    required this.label,
    required this.value,
    this.interactive = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) => _SettingsLabeledRow(
    label: label,
    value: value,
    interactive: interactive,
    onToggle: onToggle,
    minHeight: 56,
  );
}

/// Weekday + optional time well + the same switch as [OBSettingsToggleRow].
///
/// Off rows keep layout without exposing a time control: [timeLabel] null
/// shows an emdash placeholder. The stored time lives with the caller.
class OBScheduleTimeToggleRow extends StatelessWidget {
  final String weekday;
  final String? timeLabel;
  final bool enabled;
  final bool interactive;
  final VoidCallback? onToggle;
  final VoidCallback? onPickTime;
  final String onLabel;
  final String offLabel;
  final String timeSemanticLabel;

  const OBScheduleTimeToggleRow({
    super.key,
    required this.weekday,
    required this.enabled,
    this.timeLabel,
    this.interactive = true,
    this.onToggle,
    this.onPickTime,
    this.onLabel = 'An',
    this.offLabel = 'Aus',
    this.timeSemanticLabel = 'Uhrzeit',
  });

  @override
  Widget build(BuildContext context) => _SettingsLabeledRow(
    label: weekday,
    value: enabled,
    interactive: interactive,
    onToggle: onToggle,
    minHeight: 64,
    onLabel: onLabel,
    offLabel: offLabel,
    detail: timeLabel,
    trailing: _ScheduleTimeWell(
      weekday: weekday,
      timeLabel: timeLabel,
      interactive: interactive,
      onPickTime: onPickTime,
      timeSemanticLabel: timeSemanticLabel,
    ),
  );
}

class _SettingsLabeledRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool interactive;
  final VoidCallback? onToggle;
  final double minHeight;
  final Widget? trailing;
  final String? detail;
  final String onLabel;
  final String offLabel;

  const _SettingsLabeledRow({
    required this.label,
    required this.value,
    required this.interactive,
    required this.onToggle,
    required this.minHeight,
    this.trailing,
    this.detail,
    this.onLabel = 'An',
    this.offLabel = 'Aus',
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked = _stackSettingsControls(context);
    final labelText = Text(label, style: p.text(15, weight: FontWeight.w500));
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
        _OBSettingsSwitch(
          value: value,
          interactive: interactive,
          onToggle: onToggle,
        ),
      ],
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: detail == null
          ? '$label, ${value ? onLabel : offLabel}'
          : '$label, $detail, ${value ? onLabel : offLabel}',
      child: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: (minHeight - 44) / 2,
              horizontal: 14,
            ),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [labelText, const SizedBox(height: 8), controls],
                  )
                : Row(
                    children: [
                      Expanded(child: labelText),
                      controls,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleTimeWell extends StatelessWidget {
  final String weekday;
  final String? timeLabel;
  final bool interactive;
  final VoidCallback? onPickTime;
  final String timeSemanticLabel;

  const _ScheduleTimeWell({
    required this.weekday,
    required this.timeLabel,
    required this.interactive,
    required this.onPickTime,
    required this.timeSemanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final label = timeLabel ?? '—';
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
    if (timeLabel == null) return ExcludeSemantics(child: child);
    final name = '$timeSemanticLabel $weekday $timeLabel';
    if (!interactive || onPickTime == null) {
      return Semantics(label: name, readOnly: true, child: child);
    }
    return Semantics(
      button: true,
      label: name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPickTime,
          borderRadius: BorderRadius.circular(12),
          child: child,
        ),
      ),
    );
  }
}

/// Canonical switch: 51×31 in a 44pt target.
/// Light selected: ink track, white knob. Dark selected: light track, dark
/// knob. Dark off: dark track, light knob.
class _OBSettingsSwitch extends StatelessWidget {
  final bool value;
  final bool interactive;
  final VoidCallback? onToggle;

  const _OBSettingsSwitch({
    required this.value,
    required this.interactive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: Center(
        child: SizedBox(
          width: 51,
          height: 31,
          child: CupertinoSwitch(
            value: value,
            onChanged: interactive && onToggle != null
                ? (_) => onToggle!()
                : null,
            activeTrackColor: p.ink,
            thumbColor: p.dark ? p.canvas : AlpColor.canvas,
            inactiveTrackColor: p.line,
            inactiveThumbColor: p.dark ? p.ink : AlpColor.canvas,
          ),
        ),
      ),
    );
  }
}
