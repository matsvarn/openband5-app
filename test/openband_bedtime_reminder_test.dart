// The Für-heute bedtime reminder reports what happened: scheduled only when
// the one-shot reached the OS, otherwise why not (passed, denied, failed).
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_center.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = NotificationService.instance;
  var scheduled = 0;

  void reset() {
    svc.invalidatePermissionCache();
    svc.debugRequestPermission = null;
    svc.debugProbePermission = null;
    svc.debugZonedSchedule = null;
    scheduled = 0;
  }

  // scheduleOnce converts to tz.local; no plugin init runs in a unit test.
  setUpAll(() => tz.setLocalLocation(tz.UTC));
  setUp(reset);
  tearDown(reset);

  Future<BedtimeReminderResult> remind(Duration fromNow) =>
      NotificationCenter.instance.scheduleBedtimeReminder(
        at: DateTime.now().add(fromNow),
        body: '22:20 ins Bett',
      );

  void allow(bool granted) {
    svc.debugRequestPermission = () async => granted;
    svc.debugProbePermission = () async => granted;
  }

  test('scheduled when the OS took the one-shot', () async {
    allow(true);
    svc.debugZonedSchedule = () async => scheduled++;
    expect(await remind(const Duration(hours: 2)), BedtimeReminderResult.scheduled);
    expect(scheduled, 1);
  });

  test('failed, not scheduled, when the plugin call fails', () async {
    allow(true);
    svc.debugZonedSchedule = () async => throw StateError('plugin');
    expect(await remind(const Duration(hours: 2)), BedtimeReminderResult.failed);
  });

  test('passed when the time is no longer ahead; nothing is scheduled', () async {
    allow(true);
    svc.debugZonedSchedule = () async => scheduled++;
    expect(await remind(const Duration(minutes: -1)), BedtimeReminderResult.passed);
    expect(scheduled, 0);
  });

  test('denied when notifications are off; nothing is scheduled', () async {
    allow(false);
    svc.debugZonedSchedule = () async => scheduled++;
    expect(await remind(const Duration(hours: 2)), BedtimeReminderResult.denied);
    expect(scheduled, 0);
  });
}
