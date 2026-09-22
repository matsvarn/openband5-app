// The band alarm screen's one piece of real logic left in the screen itself:
// the mapping that decides what it is allowed to claim about confirmation.
// (The single next-occurrence picker — and its `nextAt` arithmetic — is gone;
// the weekly schedule in state/alarm_schedule.dart is now the only thing that
// arms the band, and its occurrence math is tested there, with no widget tree
// needed.)
//
// The screen is otherwise a rendering of AppState, and its layout is covered
// by the profile goldens.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/ui2/profile/alarm.dart';

void main() {
  group('what the screen may claim', () {
    test('an unconfirmed alarm never says it will fire', () {
      // Historical 56 does not establish the current arm, before or after
      // restart. No view state may claim confirmation with this source.
      for (final s in [AlarmArmState.unknown, AlarmArmState.pending]) {
        final view = AlarmScreenView(state: s, armedAt: DateTime(2026, 8, 22));
        expect(AlarmScreenView.stateLabel(s), isNot(contains('Confirmed')));
        expect(view.state, s);
      }
      expect(AlarmScreenView.stateLabel(AlarmArmState.unknown),
          'Not confirmed');
      for (final s in AlarmArmState.values) {
        expect(AlarmScreenView.stateLabel(s), isNot('Confirmed'));
      }
      expect(AlarmScreenView.stateLabel(AlarmArmState.offPending),
          isNot(contains('Confirmed')));
      expect(AlarmScreenView.stateLabel(AlarmArmState.offUnknown),
          isNot(contains('Confirmed')));
    });
  });
}
