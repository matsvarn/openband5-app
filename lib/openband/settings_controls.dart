import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'alp_tokens.dart';
import 'theme.dart';

bool _stackSettingsControls(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(15) > 20 ||
    MediaQuery.sizeOf(context).width < 360;

/// Paper 3N1Y-0 retry card: 14 pad, 24 radius, 14 danger copy, 8 gap,
/// 48 secondary ink retry. Shared by notification settings and appearance.
class OBSettingsErrorCard extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;
  const OBSettingsErrorCard({
    super.key,
    required this.message,
    required this.retryLabel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return OBCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: p.text(14, color: p.danger)),
          const SizedBox(height: 8),
          OBAction(
            retryLabel,
            secondary: true,
            ink: true,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Paper 3MCG-0 selected row: 15 regular / 600 selected, 18 ink check in a
/// fixed lane, 48 min height. Shared by notification choice sheets and
/// appearance. Decorative radios stay out.
class OBSettingsChoiceRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const OBSettingsChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: p.text(
                      15,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: selected
                      ? Icon(LucideIcons.check, size: 18, color: p.ink)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paper 3MB6-0 compact value row: min 56, pad 10/14, 15 w500 / optional 15 w600.
/// Comfortable: min 64, pad 14/20, label 15/20; empty value stays inline at large text.
class OBSettingsValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool interactive;
  final bool chevron;
  final bool comfortable;
  final bool mutedValue;
  final VoidCallback? onTap;

  const OBSettingsValueRow({
    super.key,
    required this.label,
    required this.value,
    this.interactive = true,
    this.chevron = false,
    this.comfortable = false,
    this.mutedValue = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final stacked =
        _stackSettingsControls(context) && !(comfortable && value.isEmpty);
    final labelText = Text(
      label,
      style: comfortable
          ? p.text(15, weight: FontWeight.w500).copyWith(height: 20 / 15)
          : p.text(15, weight: FontWeight.w500),
    );
    final valueStyle = p.text(
      15,
      weight: FontWeight.w600,
      color: mutedValue ? p.muted : null,
    );
    Widget trailing({required bool expanded}) => Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (value.isNotEmpty)
          expanded
              ? Expanded(child: Text(value, style: valueStyle))
              : Flexible(
                  child: Text(
                    value,
                    style: valueStyle,
                    textAlign: TextAlign.end,
                  ),
                ),
        if (chevron) ...[
          if (value.isNotEmpty) const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight, size: 18, color: p.muted),
        ],
      ],
    );
    final child = SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: comfortable ? 64 : 56),
        child: Padding(
          padding: comfortable
              ? const EdgeInsets.symmetric(vertical: 14, horizontal: 20)
              : const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labelText,
                    const SizedBox(height: 8),
                    trailing(expanded: true),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 12.0;
                    const minLabel = 64.0;
                    final maxTrailing = (constraints.maxWidth - gap - minLabel)
                        .clamp(0.0, double.infinity);
                    return Row(
                      children: [
                        Expanded(child: labelText),
                        const SizedBox(width: gap),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxTrailing),
                          child: trailing(expanded: false),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
    if (!interactive || onTap == null) return child;
    return Semantics(
      button: true,
      label: value.isEmpty ? label : '$label, $value',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: comfortable
              ? BorderRadius.circular(AlpRadius.card)
              : null,
          child: child,
        ),
      ),
    );
  }
}

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

Future<T?> showOpenBandSettingsChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<(T value, String label)> choices,
  T? selected,
  Key? sheetKey,
  Key Function(T value)? choiceKey,
  Color? barrierColor,
}) {
  final p = OB.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    barrierColor: barrierColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AlpRadius.card)),
    ),
    builder: (sheet) => OBSettingsChoiceSheet<T>(
      title: title,
      choices: choices,
      selected: selected,
      sheetKey: sheetKey,
      choiceKey: choiceKey,
    ),
  );
}

/// Shared choice list. Notification battery/interval keep their keys via
/// [sheetKey] / [choiceKey].
class OBSettingsChoiceSheet<T> extends StatelessWidget {
  final String title;
  final List<(T value, String label)> choices;
  final T? selected;
  final Key? sheetKey;
  final Key Function(T value)? choiceKey;

  const OBSettingsChoiceSheet({
    super.key,
    required this.title,
    required this.choices,
    this.selected,
    this.sheetKey,
    this.choiceKey,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      key: sheetKey,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: p.text(18, weight: FontWeight.w600).copyWith(
                  height: 24 / 18,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: choices.length,
                  itemBuilder: (context, i) {
                    final choice = choices[i];
                    final on = choice.$1 == selected;
                    return OBSettingsChoiceRow(
                      key: choiceKey?.call(choice.$1),
                      label: choice.$2,
                      selected: on,
                      onTap: () => Navigator.pop(context, choice.$1),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<int?> showOpenBandSettingsCountSheet({
  required BuildContext context,
  required String title,
  int? value,
  Key? sheetKey,
}) {
  final p = OB.of(context);
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    barrierColor: const Color(0x52000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AlpRadius.card)),
    ),
    builder: (sheet) => OBSettingsCountSheet(
      title: title,
      value: value,
      sheetKey: sheetKey,
    ),
  );
}

class OBSettingsCountSheet extends StatefulWidget {
  final String title;
  final int? value;
  final Key? sheetKey;

  const OBSettingsCountSheet({
    super.key,
    required this.title,
    this.value,
    this.sheetKey,
  });

  @override
  State<OBSettingsCountSheet> createState() => _OBSettingsCountSheetState();
}

/// Strict positive integer. Fractions, signs, and other non-digits are
/// rejected as a whole; characters are never stripped.
int? parseOpenBandPositiveCount(String raw) {
  final text = raw.trim();
  if (text.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(text)) return null;
  final value = int.tryParse(text, radix: 10);
  if (value == null || value < 1) return null;
  return value;
}

class _OBSettingsCountSheetState extends State<OBSettingsCountSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value == null ? '' : '${widget.value}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _parsed => parseOpenBandPositiveCount(_controller.text);

  void _apply() {
    final value = _parsed;
    if (value == null) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final maxH = media.size.height * 0.75;
    return Padding(
      key: widget.sheetKey,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        bottom: keyboard == 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: p.text(18, weight: FontWeight.w600).copyWith(
                      height: 24 / 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.well,
                      borderRadius: BorderRadius.circular(AlpRadius.well),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                        child: TextField(
                          key: const ValueKey('settings-count-field'),
                          controller: _controller,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          style: p
                              .text(20, weight: FontWeight.w600)
                              .copyWith(height: 28 / 20),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _apply(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OBAction(
                    'Übernehmen',
                    ink: true,
                    onPressed: _parsed == null ? null : _apply,
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
