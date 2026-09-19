import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'domain.dart';
import 'theme.dart';
import 'training.dart';

/// Compact active-template list. Create opens the existing editor; Starten
/// navigates into the existing live strength UI. One shared [OBTemplateRow].
class OpenBandTemplates extends StatefulWidget {
  final OpenBandRepository repository;
  final Future<void> Function(WorkoutTemplate)? onStartTemplate;
  final Future<void> Function(WorkoutTemplate?)? onEditTemplate;
  final bool synthetic;
  const OpenBandTemplates({
    super.key,
    required this.repository,
    this.onStartTemplate,
    this.onEditTemplate,
    this.synthetic = false,
  });
  @override
  State<OpenBandTemplates> createState() => _OpenBandTemplatesState();
}

class _OpenBandTemplatesState extends State<OpenBandTemplates> {
  List<WorkoutTemplate>? _templates;
  String? _pinnedId;
  Object? _error;
  bool _busy = false;
  bool _loading = true;
  int _load = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final token = ++_load;
    if (!mounted) return;
    setState(() {
      _loading = _templates == null;
      if (_templates == null) _error = null;
    });
    try {
      final templates = await widget.repository.readTemplates();
      final pin = await widget.repository.readPinnedTemplateId();
      if (!mounted || token != _load) return;
      setState(() {
        _templates = templates;
        _pinnedId = pin;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _load) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    await widget.onEditTemplate?.call(null);
    if (mounted) await _reload();
  }

  Future<void> _start(WorkoutTemplate template) async {
    if (_busy || widget.onStartTemplate == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onStartTemplate!(template);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(WorkoutTemplate template) async {
    if (_busy) return;
    final pinned = template.id == _pinnedId;
    final choice = await showTemplateActionSheet(
      context,
      template: template,
      pinned: pinned,
    );
    if (!mounted || choice == null) return;
    if (choice == TemplateMenuChoice.edit) {
      await widget.onEditTemplate?.call(template);
      if (mounted) await _reload();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (choice) {
        case TemplateMenuChoice.duplicate:
          await widget.repository.saveTemplate(copyWorkoutTemplate(template));
        case TemplateMenuChoice.pin:
          await widget.repository.pinTemplate(template.id);
        case TemplateMenuChoice.unpin:
          await widget.repository.pinTemplate(null);
        case TemplateMenuChoice.archive:
          await widget.repository.archiveTemplate(template.id);
        case TemplateMenuChoice.edit:
          break;
      }
      await _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = switch (choice) {
            TemplateMenuChoice.duplicate => 'Speichern fehlgeschlagen',
            TemplateMenuChoice.archive => 'Archivieren fehlgeschlagen',
            _ => 'Anheften fehlgeschlagen',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final templates = _templates;
    final readFailed = _error != null && templates == null;
    final empty = templates != null && templates.isEmpty && _error == null;
    final showPlus = !empty && !readFailed && templates != null;
    Widget circle(IconData icon, String tooltip, VoidCallback? onPressed) =>
        SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: p.card,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: Icon(icon, size: 20, color: p.ink),
            ),
          ),
        );
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(
          spacing: 12,
          children: [
            circle(
              LucideIcons.chevronLeft,
              'Zurück',
              () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Text(
                'Vorlagen',
                textAlign: TextAlign.center,
                style: p
                    .text(18, weight: FontWeight.w600)
                    .copyWith(height: 24 / 18),
              ),
            ),
            showPlus
                ? circle(LucideIcons.plus, 'Neue Vorlage', _create)
                : IgnorePointer(
                    child: Opacity(
                      opacity: 0,
                      child: circle(LucideIcons.plus, '', null),
                    ),
                  ),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_loading && templates == null)
                    const Center(child: CircularProgressIndicator.adaptive())
                  else if (readFailed) ...[
                    Text(
                      'Vorlagen konnten nicht geladen werden.',
                      style: p
                          .text(14, color: p.danger)
                          .copyWith(height: 18 / 14),
                    ),
                    const SizedBox(height: 12),
                    OBAction(
                      'Erneut laden',
                      ink: true,
                      onPressed: _busy ? null : _reload,
                    ),
                  ] else ...[
                    if (_error != null) ...[
                      Text(
                        _error is String
                            ? _error! as String
                            : 'Vorlagen konnten nicht geladen werden.',
                        style: p
                            .text(14, color: p.danger)
                            .copyWith(height: 18 / 14),
                      ),
                      const SizedBox(height: 12),
                      OBAction(
                        'Erneut versuchen',
                        ink: true,
                        onPressed: _busy ? null : _reload,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (empty) ...[
                      OBCard(
                        padding: const EdgeInsets.all(20),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 92),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Keine Vorlagen',
                              style: p
                                  .text(20, weight: FontWeight.w600)
                                  .copyWith(height: 26 / 20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OBAction(
                        'Vorlage erstellen',
                        ink: true,
                        onPressed: _busy ? null : _create,
                      ),
                    ] else ...[
                      for (final (i, t) in templates!.indexed) ...[
                        if (i > 0) const SizedBox(height: 12),
                        OBTemplateRow(
                          template: t,
                          pinned: t.id == _pinnedId,
                          busy: _busy,
                          onStart: widget.onStartTemplate == null
                              ? null
                              : _start,
                          onMenu: _menu,
                        ),
                      ],
                    ],
                    if (widget.synthetic) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Synthetische Daten',
                        style: p
                            .text(12, color: p.muted)
                            .copyWith(height: 16 / 12),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
