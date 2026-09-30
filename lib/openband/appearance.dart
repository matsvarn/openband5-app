import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme_controller.dart';
import 'settings_controls.dart';
import 'theme.dart';

String appearanceChoiceLabel(BuildContext context, AppThemeChoice choice) {
  final de = Localizations.localeOf(context).languageCode == 'de';
  return switch (choice) {
    AppThemeChoice.system => 'System',
    AppThemeChoice.light => de ? 'Hell' : 'Light',
    AppThemeChoice.dark => de ? 'Dunkel' : 'Dark',
  };
}

/// Production host. Selection is the last committed [ThemeController] choice;
/// a failed save keeps that choice and offers retry for the requested one.
class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({
    super.key,
    this.controller,
    this.synthetic = false,
  });

  final ThemeController? controller;
  final bool synthetic;

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  bool _busy = false;
  String? _saveError;
  AppThemeChoice? _retryChoice;

  ThemeController get _theme =>
      widget.controller ?? context.read<ThemeController>();

  Future<void> _select(AppThemeChoice choice) async {
    if (_busy) return;
    if (choice == _theme.choice && _retryChoice == null) return;
    setState(() {
      _busy = true;
      _saveError = null;
    });
    final ok = await _theme.setChoice(choice);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _saveError = null;
        _retryChoice = null;
      } else {
        _saveError = 'Speichern fehlgeschlagen';
        _retryChoice = choice;
      }
    });
  }

  Future<void> _retry() async {
    final choice = _retryChoice;
    if (choice == null || _busy) return;
    await _select(choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.controller ?? context.read<ThemeController>();
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => AppearanceSettingsView(
        selected: theme.choice,
        busy: _busy,
        saveError: _saveError,
        synthetic: widget.synthetic,
        onSelect: _busy ? null : (choice) => unawaited(_select(choice)),
        onRetry: _saveError == null ? null : () => unawaited(_retry()),
      ),
    );
  }
}

class AppearanceSettingsView extends StatelessWidget {
  final AppThemeChoice selected;
  final bool busy;
  final bool synthetic;
  final String? saveError;
  final ValueChanged<AppThemeChoice>? onSelect;
  final VoidCallback? onRetry;

  const AppearanceSettingsView({
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
                  title: _s(context, 'Darstellung', 'Appearance'),
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
                      key: const ValueKey('appearance-error'),
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
                        for (final choice in AppThemeChoice.values)
                          OBSettingsChoiceRow(
                            key: ValueKey(
                              'appearance-choice-${choice.name}',
                            ),
                            label: appearanceChoiceLabel(context, choice),
                            selected: choice == selected,
                            onTap: busy || onSelect == null
                                ? null
                                : () => onSelect!(choice),
                          ),
                      ],
                    ),
                  ),
                  if (synthetic) ...[
                    const SizedBox(height: 12),
                    Text(
                      key: const ValueKey('appearance-synthetic'),
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

String _s(BuildContext context, String de, String en) =>
    Localizations.localeOf(context).languageCode == 'de' ? de : en;
