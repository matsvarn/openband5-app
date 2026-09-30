import 'dart:convert';

import '../../../notify/notification_center.dart';
import '../../../state/prefs.dart';

typedef SleepArmedReminder = ({DateTime at, String day});

/// Shares Heute's one-shot slot and stored identity. The OS only receives a
/// reminder after the user taps Erinnern.
abstract class SleepBedtimeReminder {
  Future<SleepArmedReminder?> armed();
  Future<BedtimeReminderResult> arm(DateTime at, String day, String body);
  Future<void> cancel();

  Future<bool> reconcile({
    required String today,
    required bool planLoaded,
    DateTime? bedtime,
    bool Function()? active,
  }) async {
    final current = await armed();
    if (active?.call() == false) return false;
    if (current == null) return false;
    final expected = bedtime == null ? null : sleepReminderAt(bedtime);
    if (current.day == today &&
        (!planLoaded ||
            (expected != null && current.at.isAtSameMomentAs(expected)))) {
      return false;
    }
    await cancel();
    return true;
  }
}

DateTime sleepReminderAt(DateTime bedtime) {
  final rounded = DateTime(
    bedtime.year,
    bedtime.month,
    bedtime.day,
    bedtime.hour,
    ((bedtime.minute / 5).round() * 5),
  );
  return rounded.subtract(const Duration(minutes: 15));
}

class NotificationSleepBedtimeReminder extends SleepBedtimeReminder {
  static const _key = 'ui.openband.bedtimeReminder';

  @override
  Future<SleepArmedReminder?> armed() async {
    await Prefs.ensureLoaded();
    final raw = Prefs.getString(_key, '');
    if (raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return (
        at: DateTime.parse(map['at'] as String),
        day: map['day'] as String,
      );
    } catch (_) {
      final at = DateTime.tryParse(raw);
      return at == null ? null : (at: at, day: '');
    }
  }

  @override
  Future<BedtimeReminderResult> arm(
    DateTime at,
    String day,
    String body,
  ) async {
    final result = await NotificationCenter.instance.scheduleBedtimeReminder(
      at: at,
      body: body,
    );
    if (result == BedtimeReminderResult.scheduled) {
      await Prefs.ensureLoaded();
      await Prefs.setStringAcked(
        _key,
        jsonEncode({'at': at.toIso8601String(), 'day': day}),
      );
    }
    return result;
  }

  @override
  Future<void> cancel() async {
    await NotificationCenter.instance.cancelBedtimeReminder();
    await Prefs.ensureLoaded();
    await Prefs.setStringAcked(_key, '');
  }
}

class MemorySleepBedtimeReminder extends SleepBedtimeReminder {
  MemorySleepBedtimeReminder({this.result = BedtimeReminderResult.scheduled});
  BedtimeReminderResult result;
  SleepArmedReminder? current;
  int cancellations = 0;

  @override
  Future<SleepArmedReminder?> armed() async => current;
  @override
  Future<BedtimeReminderResult> arm(
    DateTime at,
    String day,
    String body,
  ) async {
    if (result == BedtimeReminderResult.scheduled) current = (at: at, day: day);
    return result;
  }

  @override
  Future<void> cancel() async {
    current = null;
    cancellations++;
  }
}
