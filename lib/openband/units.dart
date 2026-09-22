import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/units_controller.dart';
import 'settings_controls.dart';
import 'theme.dart';

const _kPreviewMeters = 5000.0;
const _kPreviewSeconds = 25 * 60;
const _kPreviewKg = 70;
const _kPreviewCm = 180;

String unitsChoiceLabel(BuildContext context, UnitSystem system) {
  final de = Localizations.localeOf(context).languageCode == 'de';
  return switch (system) {
    UnitSystem.metric => de ? 'Metrisch' : 'Metric',
    UnitSystem.imperial => 'Imperial',
  };
}

({String distance, String pace, String weight, String height})
unitsPreviewSamples(UnitSystem system) {
  final u = UnitsController.seed(system);
  try {
    return (
      distance:
          '${obNumber(u.distanceValue(_kPreviewMeters), digits: 2)} ${u.distanceUnit}',
      pace: u.pace(_kPreviewMeters, _kPreviewSeconds)!,
      weight: u.weight(_kPreviewKg),
      height: u.height(_kPreviewCm)!,
    );
  } finally {
    u.dispose();
  }
}

/// Production host. Selection is the last committed [UnitsController] system;
/// a failed save keeps that system and offers retry for the requested one.
class UnitsSettings extends StatefulWidget {
  const UnitsSettings({
    super.key,
    this.controller,
    this.synthetic = false,
  });

  final UnitsController? controller;
  final bool synthetic;

  @override
  State<UnitsSettings> createState() => _UnitsSettingsState();
}

class _UnitsSettingsState extends State<UnitsSettings> {
  bool _busy = false;
  String? _saveError;
  UnitSystem? _retrySystem;

  UnitsController get _units =>
      widget.controller ?? context.read<UnitsController>();

  Future<void> _select(UnitSystem system) async {
    if (_busy) return;
    if (system == _units.system && _retrySystem == null) return;
    setState(() {
      _busy = true;
      _saveError = null;
    });
    final ok = await _units.setSystem(system);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _saveError = null;
        _retrySystem = null;
      } else {
        _saveError = 'Speichern fehlgeschlagen';
        _retrySystem = system;
      }
    });
  }

  Future<void> _retry() async {
    final system = _retrySystem;
    if (system == null || _busy) return;
    await _select(system);
  }

  @override
  Widget build(BuildContext context) {
    final units = widget.controller ?? context.read<UnitsController>();
    return ListenableBuilder(
      listenable: units,
      builder: (context, _) => UnitsSettingsView(
        selected: units.system,
        busy: _busy,
        saveError: _saveError,
        synthetic: widget.synthetic,
        onSelect: _busy ? null : (system) => unawaited(_select(system)),
        onRetry: _saveError == null ? null : () => unawaited(_retry()),
      ),
    );
  }
}

class UnitsSettingsView extends StatelessWidget {
  final UnitSystem selected;
  final bool busy;
  final bool synthetic;
  final String? saveError;
  final ValueChanged<UnitSystem>? onSelect;
  final VoidCallback? onRetry;

  const UnitsSettingsView({
    super.key,
    required this.selected,
    this.busy = false,
    this.synthetic = false,
    this.saveError,
    this.onSelect,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final preview = unitsPreviewSamples(selected);
    return PopScope<Object?>(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OBPageHeader(
                  title: _s(context, 'Einheiten', 'Units'),
                  subtitle: '',
                  onBack: busy ? () {} : null,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (saveError != null) ...[
                      OBSettingsErrorCard(
                        key: const ValueKey('units-error'),
                        message: _s(
                          context,
                          'Speichern fehlgeschlagen',
                          'Could not save',
                        ),
                        retryLabel: _s(context, 'Erneut', 'Retry'),
                        onRetry: busy ? null : onRetry,
                      ),
                      const SizedBox(height: 12),
                    ],
                    OBCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final system in UnitSystem.values)
                            OBSettingsChoiceRow(
                              key: ValueKey('units-choice-${system.name}'),
                              label: unitsChoiceLabel(context, system),
                              selected: system == selected,
                              onTap: busy || onSelect == null
                                  ? null
                                  : () => onSelect!(system),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OBCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 4,
                              bottom: 8,
                            ),
                            child: Text(
                              'Beispiel',
                              style: p.text(13, color: p.muted).copyWith(
                                    height: 18 / 13,
                                  ),
                            ),
                          ),
                          _PreviewRows(
                            rows: [
                              (
                                const ValueKey('units-preview-distance'),
                                _s(context, 'Entfernung', 'Distance'),
                                preview.distance,
                              ),
                              (
                                const ValueKey('units-preview-pace'),
                                _s(context, 'Tempo', 'Pace'),
                                preview.pace,
                              ),
                              (
                                const ValueKey('units-preview-weight'),
                                _s(context, 'Gewicht', 'Weight'),
                                preview.weight,
                              ),
                              (
                                const ValueKey('units-preview-height'),
                                _s(context, 'Größe', 'Height'),
                                preview.height,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (synthetic) ...[
                      const SizedBox(height: 12),
                      Text(
                        key: const ValueKey('units-synthetic'),
                        'Synthetische Daten',
                        textAlign: TextAlign.center,
                        style: p.text(12, color: p.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewRows extends StatelessWidget {
  final List<(Key key, String label, String value)> rows;

  const _PreviewRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final labelStyle = p.text(15).copyWith(height: 20 / 15);
    final valueStyle = p.text(15, weight: FontWeight.w600).copyWith(
          height: 20 / 15,
        );
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final large = scaler.scale(15) > 20 ||
            MediaQuery.sizeOf(context).width < 360;
        final overflow = constraints.hasBoundedWidth &&
            rows.any((row) {
              final needed = _textWidth(row.$2, labelStyle, scaler, dir) +
                  12 +
                  _textWidth(row.$3, valueStyle, scaler, dir);
              return needed > constraints.maxWidth;
            });
        final stacked = large || overflow;
        return Column(
          key: ValueKey(stacked ? 'units-preview-stacked' : 'units-preview-row'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              _PreviewRow(
                key: row.$1,
                label: row.$2,
                value: row.$3,
                stacked: stacked,
                labelStyle: labelStyle,
                valueStyle: valueStyle,
              ),
          ],
        );
      },
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool stacked;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  const _PreviewRow({
    super.key,
    required this.label,
    required this.value,
    required this.stacked,
    required this.labelStyle,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: labelStyle);
    final valueText = Text(
      value,
      textAlign: stacked ? TextAlign.start : TextAlign.right,
      style: valueStyle,
    );
    final scaler = MediaQuery.textScalerOf(context);
    // Paper 3UQ6/3URH: pad 8, gap 4, minHeight 100 at 2x
    // (label 40 + 4 + value 40 + 16). Normal rows stay 48.
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: stacked ? 16 + 4 + 2 * scaler.scale(20) : 48,
      ),
      child: stacked
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelText,
                  const SizedBox(height: 4),
                  valueText,
                ],
              ),
            )
          : Row(
              children: [
                Expanded(child: labelText),
                const SizedBox(width: 12),
                valueText,
              ],
            ),
    );
  }
}

double _textWidth(
  String text,
  TextStyle style,
  TextScaler scaler,
  TextDirection dir,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: dir,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

String _s(BuildContext context, String de, String en) =>
    Localizations.localeOf(context).languageCode == 'de' ? de : en;
