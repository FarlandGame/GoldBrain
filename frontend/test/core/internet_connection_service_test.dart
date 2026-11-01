import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/internet_connection_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'requires a real JSON response and rejects captive portal HTML',
    () async {
      final service = InternetConnectionService(
        client: MockClient((request) async {
          if (request.url.host == 'blocked.example') {
            return http.Response('<html>Sign in to Wi-Fi</html>', 200);
          }
          return http.Response('{"ok":true}', 200);
        }),
        probeUris: [
          Uri.parse('https://blocked.example/probe'),
          Uri.parse('https://market.example/probe'),
        ],
      );

      expect(await service.hasInternetAccess(), isTrue);
      service.close();
    },
  );

  test('reports offline when every real HTTPS probe fails', () async {
    final service = InternetConnectionService(
      client: MockClient((_) async => http.Response('{}', 503)),
      probeUris: [Uri.parse('https://market.example/probe')],
    );

    expect(await service.hasInternetAccess(), isFalse);
    service.close();
  });
}
