// One G3 sport order, label and pictogram source for Heute and Training.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../training.dart' show OBSportIcon;

class G3Sport {
  final String id, label, icon;
  const G3Sport(this.id, this.label, this.icon);
}

const g3Sports = <G3Sport>[
  G3Sport('running', 'Lauf', 'run'),
  G3Sport('cycling', 'Rad', 'bike'),
  G3Sport('walking', 'Gehen', 'walk'),
  G3Sport('hiking', 'Wandern', 'trekking'),
  G3Sport('weight_training', 'Kraft', 'barbell'),
  G3Sport('swimming', 'Schwimmen', 'swimming'),
  G3Sport('yoga', 'Yoga', 'yoga'),
  G3Sport('tennis', 'Tennis', 'ball-tennis'),
  G3Sport('intervals', 'Intervalle', 'jump-rope'),
  G3Sport('stretching', 'Dehnen', 'stretching'),
  G3Sport('soccer', 'Fußball', 'ball-football'),
  G3Sport('rowing', 'Rudern', 'kayak'),
  G3Sport('climbing', 'Klettern', 'mountain'),
  G3Sport('skiing', 'Ski', 'ski-jumping'),
  G3Sport('martial_arts', 'Kampfsport', 'karate'),
  G3Sport('other', 'Sonstiges', ''),
];

final g3SportIds = List<String>.unmodifiable(g3Sports.map((s) => s.id));
final g3QuickSportIds = List<String>.unmodifiable([
  ...g3Sports.take(8).map((s) => s.id),
  'other',
]);

G3Sport? g3Sport(String id) {
  final canonical = switch (id) {
    'strength' || 'weightlifting' => 'weight_training',
    'football' => 'soccer',
    _ => id,
  };
  for (final sport in g3Sports) {
    if (sport.id == canonical) return sport;
  }
  return null;
}

String g3SportLabel(String id) => g3Sport(id)?.label ?? 'Aktivität';

Widget g3SportIcon(String id, {double size = 24, required Color color}) {
  final icon = g3Sport(id)?.icon;
  if (icon == 'yoga') {
    return Icon(LucideIcons.flower2, size: size, color: color);
  }
  return icon == null || icon.isEmpty
      ? Icon(LucideIcons.activity, size: size, color: color)
      : OBSportIcon(icon, size: size, color: color);
}
