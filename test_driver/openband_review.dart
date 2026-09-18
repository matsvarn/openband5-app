import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['OPENBAND_REVIEW_OUTPUT'] ?? 'build/ui-review',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
        throw FormatException('Unexpected screenshot name: $name');
      }
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final frames = data?['frames'] ?? [];
      await File('${output.path}/frames.json').writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'synthetic': true, 'frames': frames}),
      );
    },
  );
}
