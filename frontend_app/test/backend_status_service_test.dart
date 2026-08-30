import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/service/backend_status_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('accepts a valid PaperPulse status response', () async {
    final service = BackendStatusService(
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/status');
        return http.Response(
          '{"status":"ok","service":"paperpulse-backend","version":"0.0.5"}',
          200,
        );
      }),
    );

    final status = await service.fetch('https://example.test/');

    expect(status.version, '0.0.5');
  });

  test('rejects an unrelated server returning 200', () async {
    final service = BackendStatusService(
      client: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
    );

    expect(
      () => service.fetch('https://example.test'),
      throwsA(isA<BackendStatusException>()),
    );
  });

  test('compares backend and frontend semantic versions', () {
    expect(BackendStatusController.compareVersions('0.0.5', '0.0.4'), 1);
    expect(BackendStatusController.compareVersions('v0.0.4', '0.0.4'), 0);
    expect(BackendStatusController.compareVersions('0.0.3', '0.0.4'), -1);
  });

  test('marks a newer backend version as an available update', () async {
    final controller = BackendStatusController(
      BackendStatusService(
        client: MockClient(
          (_) async => http.Response(
            '{"status":"ok","service":"paperpulse-backend","version":"0.0.5"}',
            200,
          ),
        ),
      ),
    );

    await controller.check('https://example.test');

    expect(controller.hasUpdate, isTrue);
    expect(controller.hasVersionMismatch, isTrue);
  });
}
