import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/journal_fields.dart';
import 'alp_tokens.dart';
import 'journal_fields.dart';
import 'theme.dart';
import 'time_picker.dart';

/// Local apply vs persisted mutation. Journal keeps the former.
enum OpenBandJournalValueApplyOutcome { committed, failed, conflict, stale }

/// Clear is [value] == null; cancel is a null sheet result.
class OpenBandJournalValueResult {
  final JournalMetricValue? value;
  const OpenBandJournalValueResult(this.value);
}

typedef OpenBandJournalValueApply =
    Future<OpenBandJournalValueApplyOutcome> Function(
      JournalMetricValue? value,
    );

typedef OpenBandJournalValueReload = Future<JournalMetricValue?> Function();

Future<OpenBandJournalValueResult?> showOpenBandJournalValueSheet({
  required BuildContext context,
  required JournalFieldSpec spec,
  JournalMetricValue? metric,
  OpenBandJournalValueApply? apply,
  OpenBandJournalValueReload? reload,
  String? contextLabel,
  bool showRemove = true,
}) {
  return showModalBottomSheet<OpenBandJournalValueResult>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => OBJournalValueSheet(
      spec: spec,
      metric: metric,
      apply: apply,
      reload: reload,
      contextLabel: contextLabel,
      showRemove: showRemove,
    ),
  );
}

/// Paper 3Q5H amount sheet. Optional time stays; amount-only omits Menge.
class OBJournalValueSheet extends StatefulWidget {
  final JournalFieldSpec spec;
  final JournalMetricValue? metric;
  final OpenBandJournalValueApply? apply;
  final OpenBandJournalValueReload? reload;
  final String? contextLabel;
  final bool showRemove;
  const OBJournalValueSheet({
    super.key,
    required this.spec,
    required this.metric,
    this.apply,
    this.reload,
    this.contextLabel,
    this.showRemove = true,
  });

  @override
  State<OBJournalValueSheet> createState() => _OBJournalValueSheetState();
}

class _OBJournalValueSheetState extends State<OBJournalValueSheet> {
  late JournalMetricValue? _metric = widget.metric;
  late final TextEditingController _value = TextEditingController(
    text: _metric == null ? '' : journalMetricEditableText(_metric!.value),
  );
  int? _minute;
  String? _error;
  bool _saving = false;
  bool _reloading = false;
  bool _saveError = false;
  bool _reloadError = false;
  bool _conflict = false;

  @override
  void initState() {
    super.initState();
    _minute = _metric?.atMinuteOfDay;
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  bool get _busy => _saving || _reloading;

  Future<void> _pickTime() async {
    if (_busy) return;
    final initial = _minute == null
        ? const TimeOfDay(hour: 0, minute: 0)
        : TimeOfDay(hour: _minute! ~/ 60, minute: _minute! % 60);
    final picked = await showOpenBandTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null || !mounted) return;
    setState(() => _minute = picked.hour * 60 + picked.minute);
  }

  Future<void> _commit(JournalMetricValue? metric) async {
    if (_busy) return;
    final apply = widget.apply;
    if (apply == null) {
      Navigator.pop(context, OpenBandJournalValueResult(metric));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saveError = false;
      _reloadError = false;
      _conflict = false;
    });
    OpenBandJournalValueApplyOutcome outcome;
    try {
      outcome = await apply(metric);
    } catch (_) {
      outcome = OpenBandJournalValueApplyOutcome.failed;
    }
    if (!mounted) return;
    if (outcome == OpenBandJournalValueApplyOutcome.committed) {
      Navigator.pop(context, OpenBandJournalValueResult(metric));
      return;
    }
    if (outcome == OpenBandJournalValueApplyOutcome.stale) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _conflict = outcome == OpenBandJournalValueApplyOutcome.conflict;
      _saveError = outcome == OpenBandJournalValueApplyOutcome.failed;
    });
  }

  Future<void> _apply() async {
    if (_busy) return;
    final raw = _value.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) {
      await _commit(null);
      return;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      setState(() => _error = 'Wert ist keine Zahl.');
      return;
    }
    final rangeError = journalMetricRangeError(widget.spec, parsed);
    if (rangeError != null) {
      setState(() => _error = rangeError);
      return;
    }
    final original = _metric?.value;
    final amount = original != null && original == parsed ? original : parsed;
    await _commit(
      JournalMetricValue(
        amount,
        atMinuteOfDay: widget.spec.hasTime ? _minute : _metric?.atMinuteOfDay,
      ),
    );
  }

  Future<void> _reload() async {
    final reload = widget.reload;
    if (reload == null || _busy) return;
    setState(() => _reloading = true);
    try {
      final metric = await reload();
      if (!mounted) return;
      setState(() {
        _reloading = false;
        _metric = metric;
        _value.text = metric == null
            ? ''
            : journalMetricEditableText(metric.value);
        _minute = metric?.atMinuteOfDay;
        _error = null;
        _saveError = false;
        _reloadError = false;
        _conflict = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reloading = false;
        _reloadError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final safeBottom = media.viewPadding.bottom > media.padding.bottom
        ? media.viewPadding.bottom
        : media.padding.bottom;
    final bottom = math.max(12.0, safeBottom);
    final unit = journalFieldUnitLabel(widget.spec);
    final display = p
        .text(28, weight: FontWeight.w700, display: true)
        .copyWith(height: 34 / 28);
    Widget well(Widget child) => DecoratedBox(
      decoration: BoxDecoration(
        color: p.well,
        borderRadius: BorderRadius.circular(AlpRadius.well),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: child,
        ),
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return RepaintBoundary(
              key: const ValueKey('journal-value-sheet'),
              child: Material(
                color: p.card,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AlpRadius.card),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, bottom),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  journalFieldTitle(widget.spec),
                                  style: p
                                      .text(18, weight: FontWeight.w600)
                                      .copyWith(height: 24 / 18),
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                height: 44,
                                child: IconButton(
                                  tooltip: 'Schließen',
                                  onPressed: _busy
                                      ? null
                                      : () => Navigator.pop(context),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 44,
                                    height: 44,
                                  ),
                                  icon: Icon(
                                    LucideIcons.x,
                                    size: 20,
                                    color: p.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 16),
                                if (widget.contextLabel != null) ...[
                                  Text(
                                    widget.contextLabel!,
                                    style: p
                                        .text(13, color: p.muted)
                                        .copyWith(height: 18 / 13),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                ..._valueFields(
                                  p: p,
                                  display: display,
                                  unit: unit,
                                  well: well,
                                  innerWidth: constraints.maxWidth - 40,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: p.text(14, color: p.danger)),
                        ],
                        if (_reloadError || _saveError || _conflict) ...[
                          const SizedBox(height: 16),
                          _inlineIssue(
                            p,
                            _reloadError
                                ? 'Laden fehlgeschlagen'
                                : _saveError
                                ? 'Speichern fehlgeschlagen'
                                : 'Eintrag wurde geändert',
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (_conflict && widget.reload != null)
                          _sheetAction(
                            p,
                            label: 'Neu laden',
                            onPressed: _busy ? null : _reload,
                          )
                        else
                          _sheetAction(
                            p,
                            label: widget.apply == null
                                ? 'Übernehmen'
                                : (_saveError
                                      ? 'Erneut versuchen'
                                      : 'Speichern'),
                            onPressed: _busy ? null : _apply,
                          ),
                        if (widget.showRemove) ...[
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: TextButton(
                              onPressed: _busy ? null : () => _commit(null),
                              child: Text(
                                'Wert entfernen',
                                style: p
                                    .text(15, color: p.danger)
                                    .copyWith(height: 20 / 15),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _valueFields({
    required OB p,
    required TextStyle display,
    required String unit,
    required Widget Function(Widget) well,
    required double innerWidth,
  }) {
    final amount = well(_amountRow(display, unit, gap: widget.spec.hasTime));
    if (!widget.spec.hasTime) return [amount];
    final time = InkWell(
      onTap: _busy ? null : _pickTime,
      borderRadius: BorderRadius.circular(AlpRadius.well),
      child: well(
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _minute == null ? '—' : journalMinuteLabel(_minute!),
            style: display.copyWith(color: _minute == null ? p.muted : p.ink),
          ),
        ),
      ),
    );
    final menge = _labeled(
      key: const ValueKey('journal-value-amount'),
      p: p,
      label: 'Menge',
      child: amount,
    );
    final zuletzt = _labeled(
      key: const ValueKey('journal-value-time'),
      p: p,
      label: 'Zuletzt',
      child: time,
    );
    if (_stackHasTime(innerWidth, display, p)) {
      return [menge, const SizedBox(height: 12), zuletzt];
    }
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Expanded(child: menge),
          Expanded(child: zuletzt),
        ],
      ),
    ];
  }

  Widget _amountRow(TextStyle display, String unit, {required bool gap}) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('journal-value'),
            controller: _value,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
            ],
            style: display,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: '—',
              hintStyle: display.copyWith(color: OB.of(context).muted),
            ),
          ),
        ),
        if (unit.isNotEmpty) ...[
          if (gap) const SizedBox(width: 8),
          Text(
            unit,
            style: OB
                .of(context)
                .text(15, color: OB.of(context).muted)
                .copyWith(height: 20 / 15),
          ),
        ],
      ],
    );
  }

  Widget _labeled({
    required Key key,
    required OB p,
    required String label,
    required Widget child,
  }) {
    return KeyedSubtree(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: p.text(13, color: p.muted).copyWith(height: 18 / 13),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  bool _stackHasTime(double innerWidth, TextStyle display, OB p) {
    if (MediaQuery.textScalerOf(context).scale(15) > 20) return true;
    final unit = journalFieldUnitLabel(widget.spec);
    final unitStyle = p.text(15, color: p.muted).copyWith(height: 20 / 15);
    final amount = _value.text.isEmpty ? '—' : _value.text;
    final amountW =
        _textWidth(display, amount) +
        (unit.isEmpty ? 0 : 8 + _textWidth(unitStyle, unit));
    final timeW = _textWidth(
      display,
      _minute == null ? '—' : journalMinuteLabel(_minute!),
    );
    final labelW = math.max(
      _textWidth(p.text(13, color: p.muted).copyWith(height: 18 / 13), 'Menge'),
      _textWidth(
        p.text(13, color: p.muted).copyWith(height: 18 / 13),
        'Zuletzt',
      ),
    );
    final column = math.max(labelW, 28 + math.max(amountW, timeW));
    return innerWidth + 0.5 < column * 2 + 12;
  }

  double _textWidth(TextStyle style, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  Widget _inlineIssue(OB p, String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 18, color: p.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: p.text(13, color: p.danger).copyWith(height: 18 / 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetAction(
    OB p, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    final foreground = p.dark ? p.canvas : AlpColor.canvas;
    final style = p
        .text(15, weight: FontWeight.w600)
        .copyWith(height: 20 / 15, color: foreground);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: p.ink,
          foregroundColor: foreground,
          disabledBackgroundColor: p.ink.withValues(alpha: 0.4),
          disabledForegroundColor: foreground,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AlpRadius.well),
          ),
          textStyle: style,
        ),
        child: Text(label, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}
