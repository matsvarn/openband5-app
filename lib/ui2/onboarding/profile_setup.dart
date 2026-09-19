// Profile setup.
//
// The audit found this screen promising one thing and enforcing another: the
// copy said "leave a field blank and only that metric stays unknown — never
// guessed", and the validator then refused to continue until all four were
// filled. A promise the form contradicts is worse than no promise, because it
// teaches the user that the honesty copy elsewhere is decoration too.
//
// So: every field is optional except sex, which is the one input with no
// honest default — the analytics coefficient tables key on it and the
// midpoint of two sexes is a third person. Everything else that is blank
// simply withholds the metrics that need it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../compute/profile.dart';
import '../profile/birth_date_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../screens/home_screen.dart' show monthShortName, weekdayShortName;
import '../../openband/health.dart';
import '../../openband/theme.dart';
import '../ui2.dart';

class ProfileSetupScreen extends StatefulWidget {
  /// Called after the profile has been written. The router uses it to let a
  /// deliberately-partial profile through the gate.
  final VoidCallback? onDone;

  const ProfileSetupScreen({super.key, this.onDone});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  @override
  Widget build(BuildContext c) {
    final app = context.read<AppState>();
    return ProfileSetupView(
      initial: app.user ?? const {},
      units: context.watch<UnitsController>(),
      onSave: (fields) async {
        await app.updateProfile(fields);
        widget.onDone?.call();
      },
    );
  }
}

/// The three answers the analytics coefficient tables can take.
///
/// 'other' maps to the non-binary block FOR CALORIES, which is the published
/// mean of the two sex constants. It does NOT for training load: Banister
/// publishes two constants and no third, so `nonbinary` collapses onto the
/// male pair everywhere TRIMP and the 0–21 strain score are computed
/// (`derivation_engine.dart` says so at its collapse). The screen says which,
/// because a woman who picks it is otherwise scored as a man with nothing on
/// screen admitting it.
List<(String, String)> _sexes(BuildContext c) {
  final l = AppLocalizations.of(c);
  return [
    ('m', l?.profileSetupSexMale ?? 'Male'),
    ('f', l?.profileSetupSexFemale ?? 'Female'),
    ('other', l?.profileSetupSexPreferNotToSay ?? 'Prefer not to say'),
  ];
}

class ProfileSetupView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  /// Display units for height and weight. Null is metric, which is also what
  /// the storage is.
  final UnitsController? units;

  const ProfileSetupView({
    super.key,
    required this.onSave,
    this.initial = const {},
    this.units,
  });

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  late final UnitsController _u =
      widget.units ?? UnitsController.seed(UnitSystem.metric);
  late String? _sex = (widget.initial['sex'] as String?)?.toLowerCase();
  late DateTime? _birthDate = parseBirthDate(widget.initial['birth_date']);
  late final _height = TextEditingController(
    text: _u.heightField(widget.initial['height_cm'] as num?),
  );
  late final _weight = TextEditingController(
    text: _u.weightField(widget.initial['weight_kg'] as num?),
  );

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Only what was actually entered. A blank field writes nothing, so the
  /// dependent metric abstains rather than scoring somebody else's body. The
  /// fields are typed in the units on their labels and stored in metric.
  Map<String, dynamic> _fields() => {
    if (_sex != null) 'sex': _sex,
    if (_birthDate != null) 'birth_date': birthDateString(_birthDate!),
    'height_cm': ?_u.heightToCm(_height.text),
    'weight_kg': ?_u.weightToKg(_weight.text),
  };

  /// Continue, unless something typed cannot be read — a typo is not a blank,
  /// and dropping it silently is how a body ends up half-described.
  Future<void> _continue() async {
    final bad = [
      if (Typed.of(_height.text).bad) _u.heightLabel,
      if (Typed.of(_weight.text).bad) _u.weightLabel,
    ];
    if (bad.isNotEmpty) {
      sayUnreadable(context, bad);
      return;
    }
    await widget.onSave(_fields());
  }

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    final l = AppLocalizations.of(c);
    final sexes = _sexes(c);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            Text(
              l?.profileSetupTitle ?? 'About you',
              style: p.text(30, weight: FontWeight.w800, display: true),
            ),
            const SizedBox(height: 12),
            Text(
              l?.profileSetupBody ??
                  'These details personalize your estimates. Leave any of them '
                      'blank and only the metrics that need it stay unavailable.',
              style: p.text(15, color: p.muted),
            ),
            const SizedBox(height: 24),
            Text(
              l?.profileSetupSexHeader ?? 'SEX',
              style: p.text(13, weight: FontWeight.w600, color: p.muted),
            ),
            const SizedBox(height: 8),
            OBSegmented(
              labels: [for (final e in sexes) e.$2],
              selected: sexes.indexWhere((e) => e.$1 == _sex),
              onChanged: (i) => setState(() => _sex = sexes[i].$1),
            ),
            // Which constants that choice actually gets. Calories average the
            // two published sets; training load has no third set to average,
            // so it uses the male one — said here rather than nowhere.
            if (_sex == 'other') ...[
              const SizedBox(height: 8),
              Text(
                l?.profileSetupOtherSexNote ??
                    'Calories use the mean of the two published sets. Training '
                        'load and strain have only two published constants and no '
                        'third, so they use the male pair.',
                style: p.text(13, color: p.muted),
              ),
            ],
            const SizedBox(height: 20),
            BirthDateField(
              value: _birthDate,
              onChanged: (date) => setState(() => _birthDate = date),
            ),
            const SizedBox(height: 16),
            _Field(
              _height,
              l?.profileSetupHeightLabel ?? 'HEIGHT',
              _u.isImperial ? 'in' : 'cm',
              l?.profileSetupHeightConsequence ??
                  'Without it: stride length, and distance from steps.',
            ),
            _Field(
              _weight,
              l?.profileSetupWeightLabel ?? 'WEIGHT',
              _u.isImperial ? 'lb' : 'kg',
              l?.profileSetupWeightConsequence ??
                  'Without it: calories and training load.',
            ),
            // Max HR is never entered: it is estimated (Tanaka, 208 − 0.7·age)
            // in lib/compute/hr_max.dart. A note, not a field.
            OBCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.heartPulse, size: 18, color: p.pulse),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Maximalpuls wird geschätzt (208 − 0,7 × Alter). '
                      'Du musst ihn nicht eintragen.',
                      style: p.text(14, color: p.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OBAction(
              l?.actionContinue ?? 'Continue',
              onPressed: _sex == null ? null : _continue,
            ),
            if (_sex == null) ...[
              const SizedBox(height: 8),
              Text(
                l?.profileSetupPickOneToContinue ??
                    'Pick one option above to continue.',
                style: p.text(13, color: p.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, unit, consequence;
  const _Field(this.controller, this.label, this.unit, this.consequence);

  @override
  Widget build(BuildContext c) {
    final p = OB.of(c);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OBCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: p.text(13, weight: FontWeight.w600, color: p.muted),
                  ),
                ),
                Text(
                  AppLocalizations.of(c)?.profileSetupOptional ?? 'OPTIONAL',
                  style: p.text(11, color: p.muted),
                ),
              ],
            ),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: p.text(24, weight: FontWeight.w700, display: true),
              decoration: InputDecoration(
                hintText: unit,
                hintStyle: p.text(
                  24,
                  weight: FontWeight.w700,
                  display: true,
                  color: p.line,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: p.line),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: p.action),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(consequence, style: p.text(13, color: p.muted)),
          ],
        ),
      ),
    );
  }
}

// No day-0 "unlock contract" card. There was one — locked headline, unlock
// date, nights banked, live HR beside it — and nothing ever built it. Day zero
// is carried by `StatusCard.forMetric`, which already says how many more
// nights the metric needs.

/// "Thu 4 Sep" — a date a person can hold, not an ISO string. Local by
/// construction; the app's day labels are local everywhere.
String formatDay(DateTime d, [AppLocalizations? l]) =>
    '${weekdayShortName(d.weekday, l)} ${d.day} ${monthShortName(d.month, l)}';
